import { POWERS, TICK_RATE, UNITS } from "./balance.js";
import { hasGoliath } from "./goliath.js";
import { areaBlast, strikeDamage } from "./combat.js";
import { isExplored, isVisible } from "./fog.js";
import { worldRandom } from "./rand.js";
import { applySpawnRank, bannedBy, rulesOf } from "./rules.js";
import { distToBuilding, hasBuilding, hqOf, inBounds, moveClassOf, onHomeLand, passable, regionAt, spawnUnit } from "./world.js";
import { atan2, cos, hypot, sin } from "./fmath.js";
import { QUARTER, isMulti, otherSide, perSide, rivalsOf, sidesOf, turnVec } from "./sides.js";

/**
 * Commander calldowns. Each side has a Command meter (0–100) that fills
 * slowly on its own and mostly from losses, spent on three map-targeted
 * powers — Barrage, EMP, Drop Pod — each with its own cooldown. The Sky
 * Hammer is separate: it comes online for both sides at 6:00 and recharges
 * every two and a half minutes, the late-game pressure that ends stalemates.
 *
 * Every calldown is telegraphed: `World.powers.active` (and the "calldown"
 * FxEvent) is public, so both sides see the reticle through the fog and can
 * get out of the way. The player and the AI fire them with the same
 * `calldown` Command, validated identically (calldownBlocker). Damage is
 * credited to the firing side's HQ, so kills count for the right faction.
 */

export const POWER_KINDS = ["barrage", "emp", "droppod", "hammer"];

export const POWER_NAMES = {
    barrage: "Barrage",
    emp: "EMP",
    droppod: "Drop Pod",
    hammer: "Sky Hammer"
};

const ticks = (secs) => Math.round(secs * TICK_RATE);

export function createPowerState() {
    const ready = () => ({ barrage: 0, emp: 0, droppod: 0, hammer: ticks(POWERS.hammer.unlock) });
    const zero = () => ({ barrage: 0, emp: 0, droppod: 0, hammer: 0 });
    return {
        meter: perSide(() => 0),
        readyAt: perSide(ready),
        active: [],
        stunned: new Map(),
        fired: perSide(zero)
    };
}

/** Meter charge a power costs (the Sky Hammer runs on its own timer). */
export function powerCost(p) {
    return p === "hammer" ? 0 : POWERS[p].cost;
}

/** Radius of the power's reticle (the area it can affect), in tiles. */
export function powerRadius(p) {
    return POWERS[p].radius;
}

export function telegraphTicks(p) {
    return ticks(POWERS[p].telegraph);
}

export function cooldownTicks(p) {
    return ticks(POWERS[p].cooldown);
}

/** Is this unit or building EMP'd right now? (No moving, firing or producing.) */
export function isStunned(w, id) {
    const s = w.powers.stunned;
    return s.size > 0 && (s.get(id) ?? 0) > w.tick;
}

/** Charge / cooldown / lock state of one power, for the HUD and the AI. */
export function powerStatus(w, faction, power) {
    const ps = w.powers;
    const cost = powerCost(power);
    const unlock = power === "hammer" ? ticks(POWERS.hammer.unlock) : 0;
    const locked = Math.max(0, unlock - w.tick);
    const cooldown = locked > 0 ? 0 : Math.max(0, ps.readyAt[faction][power] - w.tick);
    const charge = cost === 0 ? 1 : Math.min(1, ps.meter[faction] / cost);
    return {
        power, cost, charge, cooldown, cooldownTotal: cooldownTicks(power), locked,
        ready: locked === 0 && cooldown === 0 && charge >= 1 && !w.winner && !rulesOf(w).noCalldowns
    };
}

const clock = (t) => {
    const s = Math.ceil(t / TICK_RATE);
    return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`;
};

/** Why the power can't be fired at all right now (charge, cooldown, lock), or null. */
export function powerBlocker(w, faction, power) {
    if (w.winner)
        return "The battle is over";
    if (rulesOf(w).noCalldowns)
        return "No calldowns in this match";
    if (!hqOf(w, faction) && !hasGoliath(w, faction))
        return "Calldowns need an HQ or a Goliath";
    if (power === "droppod" && podCrew(w, faction).length === 0)
        return "Drop Pod is disabled in this match";
    const st = powerStatus(w, faction, power);
    if (st.locked > 0)
        return `Sky Hammer comes online at ${clock(ticks(POWERS.hammer.unlock))}`;
    if (st.cooldown > 0)
        return `${POWER_NAMES[power]} recharging: ${Math.ceil(st.cooldown / TICK_RATE)} s`;
    if (st.charge < 1)
        return `${POWER_NAMES[power]} needs ${st.cost} charge (${Math.floor(w.powers.meter[faction])})`;
    return null;
}

/** Why (x, y) is not a legal target for the power, or null. */
export function targetBlocker(w, faction, power, x, y) {
    const tx = Math.floor(x);
    const ty = Math.floor(y);
    if (!inBounds(w, tx, ty))
        return "Off the map";
    if (!isExplored(w, faction, tx, ty))
        return "Can't target unexplored ground";
    if (power === "droppod") {
        if (!isVisible(w, faction, tx, ty))
            return "Drop Pods need eyes on the landing zone";
        if (!passable(w, tx, ty, "ground"))
            return "Drop Pods need open ground to land on";
        if (!onHomeLand(w, faction, tx, ty))
            return "Drop Pods can't land on islands: fly troops in by Condor";
    }
    return null;
}

/** Why this calldown would be rejected (null = it will fire). Binds the player and the AI alike. */
export function calldownBlocker(w, faction, power, x, y) {
    return powerBlocker(w, faction, power) ?? targetBlocker(w, faction, power, x, y);
}

/** Apply a `calldown` command: spend the charge, start the cooldown, raise the public telegraph. */
export function applyCalldown(w, c) {
    if (!POWER_KINDS.includes(c.power) || !Number.isFinite(c.x) || !Number.isFinite(c.y))
        return;
    if (calldownBlocker(w, c.faction, c.power, c.x, c.y))
        return;
    const ps = w.powers;
    ps.meter[c.faction] -= powerCost(c.power);
    ps.readyAt[c.faction][c.power] = w.tick + cooldownTicks(c.power);
    ps.fired[c.faction][c.power]++;
    const id = w.nextId++;
    const landTick = w.tick + telegraphTicks(c.power);
    const radius = powerRadius(c.power);
    const cd = {
        id, faction: c.faction, power: c.power, x: c.x, y: c.y, radius,
        startTick: w.tick, landTick, shells: []
    };
    if (c.power === "barrage") {
        const b = POWERS.barrage;
        for (let i = 0; i < b.shells; i++) {
            // seeded scatter, uniform over the disc
            const a = worldRandom(w, "barrage", id, i, 0) * Math.PI * 2;
            const r = b.scatter * Math.sqrt(worldRandom(w, "barrage", id, i, 1));
            cd.shells.push({
                x: Math.min(w.width - 0.01, Math.max(0, c.x + sin(a) * r)),
                y: Math.min(w.height - 0.01, Math.max(0, c.y - cos(a) * r)),
                tick: landTick + i * ticks(b.shellGap)
            });
        }
    }
    ps.active.push(cd);
    w.fx.push({ type: "calldown", id, faction: c.faction, power: c.power, x: c.x, y: c.y, radius, landTick });
}

/**
 * Per tick, before combat: power-ups come online, stuns wear off and
 * telegraphed calldowns land (so their victims die in this tick's cleanup).
 */
export function tickPowers(w) {
    const ps = w.powers;
    for (const f of sidesOf(w))
        if (w.tick === ps.readyAt[f].hammer && !rulesOf(w).noCalldowns)
            w.fx.push({ type: "powerOnline", faction: f, power: "hammer" });
    if (ps.stunned.size > 0)
        for (const [id, until] of ps.stunned)
            if (until <= w.tick || (!w.units.has(id) && !w.buildings.has(id)))
                ps.stunned.delete(id);
    if (ps.active.length === 0)
        return;
    const keep = [];
    for (const c of ps.active) {
        if (c.power === "barrage") {
            for (const s of c.shells)
                if (s.tick === w.tick)
                    landShell(w, c, s.x, s.y);
            if (w.tick < c.shells[c.shells.length - 1].tick)
                keep.push(c);
            continue;
        }
        if (w.tick < c.landTick) {
            keep.push(c);
            continue;
        }
        if (c.power === "emp")
            landEmp(w, c);
        else if (c.power === "droppod")
            landPod(w, c);
        else
            landHammer(w, c);
    }
    ps.active = keep;
}

/** Per tick, after deaths are settled: the Command meters fill (mostly from losses). */
export function chargePowers(w) {
    const m = w.powers.meter;
    const sides = sidesOf(w);
    for (const f of sides)
        m[f] += POWERS.passive / TICK_RATE;
    for (const ev of w.fx) {
        if (ev.type !== "death")
            continue;
        if (!ev.free)
            m[ev.faction] += ev.value * POWERS.perScrapLost; // (a free Condor's loss cost nothing)
        // (a duel's other side made the kill; in a free-for-all, whoever did, when it's known)
        const by = isMulti(w) ? ev.by ?? null : otherSide(ev.faction);
        if (by)
            m[by] += ev.value * POWERS.perScrapKilled;
    }
    for (const f of sides)
        m[f] = Math.min(POWERS.meterMax, m[f]);
}

/** Who a calldown's kills are credited to: the HQ (so faction stats count them, and no unit takes their XP), else no one (0). */
const attackerOf = (w, f) => hqOf(w, f)?.id ?? 0;

function impact(w, c, x, y, hits, unitIds = []) {
    w.fx.push({
        type: "calldownImpact", id: c.id, faction: c.faction, power: c.power, x, y, radius: c.radius, hits, unitIds
    });
}

function landShell(w, c, x, y) {
    const b = POWERS.barrage;
    const hits = areaBlast(w, c.faction, x, y, b.splash, b.damage, "explosive", "ground", attackerOf(w, c.faction));
    impact(w, c, x, y, hits);
}

function landEmp(w, c) {
    const r = POWERS.emp.radius;
    const until = w.tick + ticks(POWERS.emp.stun);
    let hits = 0;
    // every side but the caster's (a duel's one enemy), each side's stun its own event
    for (const victim of rivalsOf(w, c.faction)) {
        const ids = [];
        for (const u of w.units.values())
            if (u.faction === victim && hypot(u.x - c.x, u.y - c.y) <= r)
                ids.push(u.id);
        for (const b of w.buildings.values())
            if (b.faction === victim && distToBuilding(b, c.x, c.y) <= r)
                ids.push(b.id);
        for (const id of ids)
            w.powers.stunned.set(id, Math.max(until, w.powers.stunned.get(id) ?? 0));
        if (ids.length > 0)
            w.fx.push({ type: "stun", faction: victim, ids, x: c.x, y: c.y, until });
        hits += ids.length;
    }
    impact(w, c, c.x, c.y, hits);
}

/**
 * Stand-ins for pod crew a match rule bans, first allowed one wins: aircraft
 * under the Air War mutator, robot infantry under Infantry War.
 */
const POD_SUBSTITUTE = {
    stinger: ["wasp", "trooper"], lancer: ["wasp", "rocket-squad"], "flak-crawler": ["raptor", "rocket-squad"]
};

/**
 * What a Drop Pod delivers for this faction right now: the tech tier's crew,
 * with any kind the match rules ban swapped for an allowed stand-in (or
 * dropped). Empty means the Drop Pod can't be used in this match.
 */
export function podCrew(w, faction) {
    const base = hasBuilding(w, faction, "tech-lab") ? POWERS.droppod.techUnits : POWERS.droppod.units;
    const out = [];
    for (const kind of base) {
        if (!bannedBy(w, kind, faction))
            out.push(kind);
        else {
            const alt = POD_SUBSTITUTE[kind]?.find((k) => !bannedBy(w, k, faction));
            if (alt)
                out.push(alt);
        }
    }
    return out;
}

function landPod(w, c) {
    const p = POWERS.droppod;
    const hits = areaBlast(w, c.faction, c.x, c.y, p.radius, p.damage, "explosive", "ground", attackerOf(w, c.faction));
    const kinds = podCrew(w, c.faction);
    const ids = [];
    kinds.forEach((kind, i) => {
        const spot = podSpot(w, kind, c.x, c.y, i, kinds.length, QUARTER[c.faction]);
        if (!spot)
            return;
        const u = spawnUnit(w, kind, c.faction, spot.x, spot.y);
        applySpawnRank(w, u); // the Veterans mutator ranks pod crews too
        u.facing = u.aim = atan2(spot.x - c.x, -(spot.y - c.y)) || u.facing;
        ids.push(u.id);
    });
    impact(w, c, c.x, c.y, hits, ids);
}

/**
 * Where crew member i of n steps out of the pod: a small ring around the
 * landing point, or the nearest tile its movement class can stand on.
 */
function podSpot(w, kind, x, y, i, n, q = 0) {
    const mc = moveClassOf(kind);
    // the crew ring (and the tile search below) in the side's own frame: red's is blue's turned 180°, green's and purple's a quarter turn
    const a = (i / n) * Math.PI * 2 + 0.4 + (q === 2 ? Math.PI : q === 1 ? Math.PI / 2 : q === 3 ? Math.PI * 1.5 : 0);
    const px = x + sin(a) * 0.65;
    const py = y - cos(a) * 0.65;
    // crew step out onto the pod's own landmass, never across water onto an island
    const land = regionAt(w, Math.floor(x), Math.floor(y), "ground");
    if (passable(w, Math.floor(px), Math.floor(py), mc) && regionAt(w, Math.floor(px), Math.floor(py), "ground") === land)
        return { x: px, y: py };
    for (let r = 0; r <= 3; r++) {
        let best = null;
        let bestD = Infinity;
        for (let i2 = -r; i2 <= r; i2++)
            for (let j2 = -r; j2 <= r; j2++) {
                const [dx, dy] = turnVec(q, j2, i2);
                if (Math.max(Math.abs(dx), Math.abs(dy)) !== r)
                    continue;
                const tx = Math.floor(px) + dx;
                const ty = Math.floor(py) + dy;
                if (!passable(w, tx, ty, mc) || regionAt(w, tx, ty, "ground") !== land)
                    continue;
                const d = hypot(tx + 0.5 - px, ty + 0.5 - py);
                if (d < bestD) {
                    bestD = d;
                    best = { x: tx + 0.5, y: ty + 0.5 };
                }
            }
        if (best)
            return best;
    }
    return null;
}

function landHammer(w, c) {
    const h = POWERS.hammer;
    const hits = [];
    // (every side but the caster's: a duel's one enemy)
    for (const u of w.units.values()) {
        if (u.faction === c.faction)
            continue;
        const d = hypot(u.x - c.x, u.y - c.y);
        if (d <= h.radius)
            hits.push({ id: u.id, damage: h.unitDamage * (1 - 0.5 * (d / h.radius)) });
    }
    for (const b of w.buildings.values())
        if (b.faction !== c.faction && distToBuilding(b, c.x, c.y) <= h.radius)
            hits.push({ id: b.id, damage: h.buildingDamage });
    strikeDamage(w, hits, attackerOf(w, c.faction));
    impact(w, c, c.x, c.y, hits.length);
}

/** Total scrap value of what a Drop Pod delivers right now (AI and HUD). */
export function podValue(w, faction) {
    return podCrew(w, faction).reduce((v, k) => v + UNITS[k].cost, 0);
}
