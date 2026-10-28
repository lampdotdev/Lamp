// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { BUILDINGS, DAMAGE_VS, GOLIATH, UNITS } from "../balance.js";
import { knownBuildings } from "../fog.js";
import { GOLIATH_WEAPONS, weaponReady } from "../goliath.js";
import { unitSeenBy } from "../infantry.js";
import { hypot } from "../fmath.js";

/**
 * What the commander makes of the enemy it can see: who it sees (through
 * fog AND Sniper concealment, infantry.ts unitSeenBy), how much anti-air
 * covers a spot, and how well a weapon does against a target. Shared by
 * commander.ts and its helpers so every tactic reads the field the same way.
 */

/** Enemy units `faction` can see right now (fog and Woods concealment applied). */
export function seenEnemies(w, faction) {
    const out = [];
    for (const u of w.units.values())
        if (u.faction !== faction && unitSeenBy(w, faction, u))
            out.push(u);
    return out;
}

/**
 * Anti-air worth of a weapon, in Flak Crawlers: its DPS against aircraft
 * (airMult applied) over the Flak's, capped at 1, to a tenth. Flak, Raptors
 * and SAMs 1, Lancers 0.6, Turrets 0.8, a Trooper Squad's rifles (half
 * damage vs air) only 0.2 — a lone rifle squad is not flak.
 */
export function aaWeight(st) {
    if (st.targets !== "air" && st.targets !== "both")
        return 0;
    return Math.min(1, Math.round((10 * st.dps * (st.airMult ?? 1)) / UNITS["flak-crawler"].dps) / 10);
}

/**
 * Anti-air worth (aaWeight, in Flak) and range of a unit we see or remember.
 * A Goliath fights with several weapons (GOLIATH.weapons), so its worth is
 * that of the ones that can hit aircraft and fire right now — its laser and
 * machine guns, about 0.8 Flak at 4.5 tiles, down to 0.2 at 3 with the laser
 * out, or carried on a lift — not its kind's summary numbers (an 8-tile
 * full Flak). One only remembered (no state to read) counts with all of them.
 */
export function unitAntiAir(u) {
    if (u.kind !== "goliath")
        return { weight: aaWeight(UNITS[u.kind]), range: UNITS[u.kind].range };
    const live = "goliath" in u && u.goliath ? u : null;
    let dps = 0;
    let range = 0;
    for (const k of GOLIATH_WEAPONS) {
        const st = GOLIATH.weapons[k];
        if ((st.targets !== "air" && st.targets !== "both") || (live && !weaponReady(live, k)))
            continue;
        dps += st.dps * (st.airMult ?? 1);
        range = Math.max(range, st.range);
    }
    return { weight: Math.min(1, Math.round((10 * dps) / UNITS["flak-crawler"].dps) / 10), range };
}

/** Anti-air (in Flak) covering a spot at least this much keeps drones and dropships away. */
export const AA_COVER = 0.5;

/**
 * Anti-air we can see (units — or `seen`, which may add some we remember)
 * or remember (buildings) that could shoot at an aircraft, weighed in Flak
 * (aaWeight). Units reach range + 3, buildings range + 2; the HQ's
 * point-defence gun doesn't count (it swats lone drones, it doesn't close
 * the sky).
 */
export function aaSources(w, faction, seen) {
    const out = [];
    for (const u of seen ?? seenEnemies(w, faction)) {
        const { weight, range } = unitAntiAir(u);
        if (weight > 0)
            out.push({ x: u.x, y: u.y, reach: range + 3, weight });
    }
    for (const kb of knownBuildings(w, faction)) {
        if (kb.kind === "hq")
            continue;
        const st = BUILDINGS[kb.kind];
        const weight = aaWeight(st);
        if (weight > 0)
            out.push({ x: kb.tx + st.size / 2, y: kb.ty + st.size / 2, reach: st.range + 2, weight });
    }
    return out;
}

/** Anti-air (in Flak) covering (x, y): the sum over the sources in reach of it. */
export function aaStrengthAt(sources, x, y) {
    let v = 0;
    for (const a of sources)
        if (hypot(a.x - x, a.y - y) < a.reach)
            v += a.weight;
    return v;
}

/**
 * How hard `attacker`'s weapon hits a target of this armour and domain
 * (1 = a full armour match): DAMAGE_VS for its damage type, times airMult
 * against aircraft; 0 when it can't shoot that domain at all. A Sniper Team
 * vs a tank is 0.4, vs a building 0.15, vs infantry 3.
 */
export function effectivenessVs(attacker, armor, domain) {
    const st = UNITS[attacker];
    if (st.targets === "none" || (st.targets !== "both" && st.targets !== domain))
        return 0;
    return DAMAGE_VS[st.dmgType ?? "kinetic"][armor] * (domain === "air" ? st.airMult ?? 1 : 1);
}

/** effectivenessVs against a unit kind. */
export const effectiveness = (attacker, target) => effectivenessVs(attacker, UNITS[target].armor, UNITS[target].domain);

/** Below this effectiveness a unit is no answer to a target (a Sniper vs any vehicle). */
export const USELESS = 0.45;
