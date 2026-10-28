import { BUILDINGS, ECONOMY, GOLIATH, TERRAIN, UNITS } from "./balance.js";
import { createFog } from "./fog.js";
import { createObjectiveState } from "./objectives.js";
import { createPowerState } from "./powers.js";
import { hypot } from "./fmath.js";
import { QUARTER, perSide, turnPoint, turnTile, turnVec } from "./sides.js";

const newFaction = () => ({
    scrap: ECONOMY.startingScrap,
    pending: null,
    stats: { unitsBuilt: 0, unitsLost: 0, unitsKilled: 0, buildingsLost: 0, buildingsKilled: 0, scrapHarvested: 0, scrapSalvaged: 0 },
    incomeMult: 1
});

export function createWorld(width, height) {
    return {
        tick: 0,
        width,
        height,
        terrain: new Uint8Array(width * height),
        scrap: new Uint16Array(width * height),
        occupancy: new Int32Array(width * height),
        nextId: 1,
        units: new Map(),
        buildings: new Map(),
        projectiles: [],
        wrecks: [],
        powers: createPowerState(),
        objectives: createObjectiveState(),
        factions: perSide(newFaction),
        winner: null,
        fx: [],
        fog: createFog(width, height),
        mapId: "custom",
        biome: "temperate",
        seed: 1
    };
}

export const tileIndex = (w, tx, ty) => ty * w.width + tx;

export const inBounds = (w, tx, ty) => tx >= 0 && ty >= 0 && tx < w.width && ty < w.height;

export function terrainAt(w, tx, ty) {
    if (!inBounds(w, tx, ty))
        return 1 /* Terrain.Rock */;
    return w.terrain[tileIndex(w, tx, ty)];
}

export function setTerrain(w, tx, ty, t) {
    const i = tileIndex(w, tx, ty);
    if (w.terrain[i] !== t)
        regionCache.delete(w);
    w.terrain[i] = t;
    w.scrap[i] =
        t === 2 /* Terrain.Scrap */ ? ECONOMY.scrapPerTile : t === 7 /* Terrain.Crystal */ ? ECONOMY.crystalPerTile : 0;
}

/** Is this a harvestable tile (scrap or crystal) with anything left? */
export function isResource(w, i) {
    const t = w.terrain[i];
    return (t === 2 /* Terrain.Scrap */ || t === 7 /* Terrain.Crystal */) && w.scrap[i] > 0;
}

/** Tiles occupied by any building footprint, for pathing/placement. */
export function buildingAtTile(w, tx, ty) {
    if (!inBounds(w, tx, ty))
        return null;
    const id = w.occupancy[tileIndex(w, tx, ty)];
    return id ? w.buildings.get(id) ?? null : null;
}

export const moveClassOf = (kind) => UNITS[kind].domain === "air" ? "air" : UNITS[kind].hover ? "hover" : UNITS[kind].squad ? "foot" : "ground";

/** Can a unit of this movement class stand on the tile? */
export function passable(w, tx, ty, mc) {
    if (!inBounds(w, tx, ty))
        return false;
    if (mc === "air")
        return true;
    const i = tileIndex(w, tx, ty);
    const info = TERRAIN[w.terrain[i]];
    if (!(mc === "hover" ? info.hover : mc === "foot" ? info.footSpeed > 0 : info.ground))
        return false;
    return w.occupancy[i] === 0;
}

const regionCache = new WeakMap();

const standsOn = (info, mc) => mc === "hover" ? info.hover : mc === "foot" ? info.footSpeed > 0 : info.ground;

/**
 * Connected regions of the map per movement class, from terrain alone:
 * two tiles share a label when a unit of that class could walk from one to
 * the other with no building in the way; 0 is terrain it can't stand on.
 * Buildings are left out (they come and go; terrain doesn't once a map is
 * painted), so this answers "is that island cut off?" in one lookup where
 * an A* search would flood the whole landmass first. 4-connected, which is
 * what A*'s no-corner-cutting rule amounts to. Cached per world and dropped
 * whenever a tile's terrain changes.
 */
export function regionLabels(w, mc) {
    let byClass = regionCache.get(w);
    if (!byClass)
        regionCache.set(w, (byClass = {}));
    const have = byClass[mc];
    if (have)
        return have;
    const W = w.width;
    const n = W * w.height;
    const labels = new Int32Array(n);
    const stack = [];
    let next = 0;
    for (let start = 0; start < n; start++) {
        if (labels[start] || !standsOn(TERRAIN[w.terrain[start]], mc))
            continue;
        const id = ++next;
        labels[start] = id;
        stack.push(start);
        while (stack.length) {
            const i = stack.pop();
            const x = i % W;
            for (const j of [i - W, i + W, x > 0 ? i - 1 : -1, x < W - 1 ? i + 1 : -1]) {
                if (j < 0 || j >= n || labels[j] || !standsOn(TERRAIN[w.terrain[j]], mc))
                    continue;
                labels[j] = id;
                stack.push(j);
            }
        }
    }
    byClass[mc] = labels;
    return labels;
}

/** Region label of a tile for a movement class (air: 1 anywhere on the map; 0 off it or on impassable terrain). */
export function regionAt(w, tx, ty, mc) {
    if (!inBounds(w, tx, ty))
        return 0;
    if (mc === "air")
        return 1;
    return regionLabels(w, mc)[tileIndex(w, tx, ty)];
}

/** How far short of a tile centre a unit may stop (crowds, arrival slack), for canGetWithin. */
const REACH_SLACK = 0.35;

/**
 * Could a unit of class `mc` standing at (fx, fy) get within `range` of
 * (x, y) on foot or tracks? Air always can. A point in the unit's own region
 * is reachable; otherwise (an island, a target out over the sea) the centre
 * of some tile of that region — where pathing stops — must lie within range
 * of it, with a little slack. `dist` measures from a point to the target
 * (default: to (x, y); a building passes its footprint distance).
 */
export function canGetWithin(w, mc, fx, fy, x, y, range, dist = (px, py) => hypot(px - x, py - y), span = 0) {
    if (mc === "air")
        return true;
    const reg = regionAt(w, Math.floor(fx), Math.floor(fy), mc);
    if (!reg)
        return true; // standing somewhere odd (a bail-out, a building edge): don't second-guess
    if (regionAt(w, Math.floor(x), Math.floor(y), mc) === reg)
        return true;
    const labels = regionLabels(w, mc);
    const R = Math.ceil(range + span);
    const x0 = Math.max(0, Math.floor(x - R));
    const x1 = Math.min(w.width - 1, Math.floor(x + R));
    const y0 = Math.max(0, Math.floor(y - R));
    const y1 = Math.min(w.height - 1, Math.floor(y + R));
    for (let ty = y0; ty <= y1; ty++)
        for (let tx = x0; tx <= x1; tx++)
            if (labels[ty * w.width + tx] === reg && dist(tx + 0.5, ty + 0.5) <= range - REACH_SLACK)
                return true;
    return false;
}

/**
 * Is tile (tx, ty) on land joined to this side's HQ (by ground: bridges and
 * fords count, the sea doesn't)? Islands are not. Only an island map asks
 * (Rules.islands); elsewhere, and for a side with no HQ, it is all home.
 */
export function onHomeLand(w, faction, tx, ty) {
    if (!w.rules?.islands)
        return true;
    const hq = hqOf(w, faction);
    const s = BUILDINGS.hq.size;
    // (the HQ gone, the land it stood on still counts: Rules.homeTiles)
    const at = hq ? [hq.tx + (s >> 1), hq.ty + (s >> 1)] : w.rules.homeTiles?.[faction];
    if (!at)
        return true;
    const home = regionAt(w, at[0], at[1], "ground");
    return !home || regionAt(w, tx, ty, "ground") === home;
}

/** A terrain's speed multiplier for a (non-air) movement class. */
export function terrainMult(info, mc) {
    return mc === "hover" ? info.hoverSpeed : mc === "foot" ? info.footSpeed : info.speed;
}

/** Ground-passability of a tile for tracked/wheeled units (air ignores this). */
export function groundPassable(w, tx, ty) {
    return passable(w, tx, ty, "ground");
}

/** Speed multiplier for a movement class on the tile under (x, y). */
export function terrainSpeed(w, x, y, mc) {
    if (mc === "air")
        return 1;
    const info = TERRAIN[terrainAt(w, Math.floor(x), Math.floor(y))];
    return terrainMult(info, mc) || 1;
}

/** Which way a side's new units and turrets face: toward the map centre from its corner, north for blue (its frame's north for the rest). */
export const FACE = { blue: 0, red: Math.PI, green: Math.PI / 2, purple: Math.PI * 1.5 };

export function spawnUnit(w, kind, faction, x, y) {
    const unit = {
        id: w.nextId++,
        kind,
        faction,
        x,
        y,
        hp: UNITS[kind].hp,
        facing: FACE[faction],
        aim: FACE[faction],
        order: { type: "idle" },
        path: null,
        pathGoal: null,
        cargo: 0,
        cooldown: 0,
        autoTargetId: null,
        damagedTick: -1000,
        lastAttackerId: null,
        firedTick: -1000,
        xp: 0,
        rank: 0,
        kills: 0
    };
    if (UNITS[kind].capacity)
        unit.passengers = [];
    if (kind === "goliath")
        unit.goliath = newGoliathState();
    w.units.set(unit.id, unit);
    return unit;
}

/** A fresh Goliath: walking, every weapon system online (goliath.ts). */
export function newGoliathState() {
    const weapon = () => ({ online: true, reboot: -1, cooldown: 0, targetId: null, firedTick: -1000 });
    return {
        mode: "walking",
        modeTicks: 0,
        weapons: { mortars: weapon(), laser: weapon(), cannons: weapon(), mg: weapon() },
        queue: [],
        rally: null,
        lift: null,
        foot: null
    };
}

/**
 * A unit's domain right now: its kind's, except a Goliath carried off the
 * ground by two Condors (lift.ts), which is an air target until it is set down.
 */
export function domainOf(u) {
    return u.goliath?.lift?.phase === "carrying" ? "air" : UNITS[u.kind].domain;
}

export function spawnBuilding(w, kind, faction, tx, ty) {
    const building = {
        id: w.nextId++,
        kind,
        faction,
        tx,
        ty,
        hp: BUILDINGS[kind].hp,
        queue: [],
        rally: null,
        facing: FACE[faction],
        cooldown: 0,
        damagedTick: -1000,
        lastAttackerId: null,
        firedTick: -1000
    };
    w.buildings.set(building.id, building);
    stampOccupancy(w, building, building.id);
    return building;
}

/** Remove a building and free its footprint. */
export function removeBuilding(w, b) {
    w.buildings.delete(b.id);
    stampOccupancy(w, b, 0);
    // footprint freed: re-plan the units heading for it (its approach point
    // moved, or a path ended at its edge), and any path that is a detour (it may
    // have gone round this very building); a direct path still works
    const size = BUILDINGS[b.kind].size;
    for (const u of w.units.values()) {
        const g = u.pathGoal;
        if (g && g.x >= b.tx - 2 && g.x <= b.tx + size + 2 && g.y >= b.ty - 2 && g.y <= b.ty + size + 2)
            u.path = null;
        else if (u.path && u.path.length > 4) {
            const end = u.path[u.path.length - 1];
            const dx = Math.abs(end.x - u.x);
            const dy = Math.abs(end.y - u.y);
            if (u.path.length > 1.3 * (Math.max(dx, dy) + 0.4142 * Math.min(dx, dy)) + 3)
                u.path = null;
        }
    }
}

/**
 * A building now stands on these tiles: re-plan only the paths that cross
 * them or brush past them (a diagonal step beside the new footprint may now
 * cut its corner, which A* never allows).
 */
export function invalidatePathsThrough(w, b) {
    const size = BUILDINGS[b.kind].size;
    const inside = (p) => p.x >= b.tx - 1 && p.x < b.tx + size + 1 && p.y >= b.ty - 1 && p.y < b.ty + size + 1;
    for (const u of w.units.values())
        if (u.path && u.path.some(inside))
            u.path = null;
}

function stampOccupancy(w, b, id) {
    const size = BUILDINGS[b.kind].size;
    for (let dy = 0; dy < size; dy++)
        for (let dx = 0; dx < size; dx++)
            if (inBounds(w, b.tx + dx, b.ty + dy))
                w.occupancy[tileIndex(w, b.tx + dx, b.ty + dy)] = id;
}

export function buildingCenter(b) {
    const size = BUILDINGS[b.kind].size;
    return { x: b.tx + size / 2, y: b.ty + size / 2 };
}

export const dist = (ax, ay, bx, by) => hypot(bx - ax, by - ay);

/** Distance from a point to a building's footprint (0 if inside). */
export function distToBuilding(b, x, y) {
    const size = BUILDINGS[b.kind].size;
    const dx = Math.max(b.tx - x, 0, x - (b.tx + size));
    const dy = Math.max(b.ty - y, 0, y - (b.ty + size));
    return hypot(dx, dy);
}

export function hqOf(w, faction) {
    for (const b of w.buildings.values())
        if (b.kind === "hq" && b.faction === faction)
            return b;
    return null;
}

/**
 * Nearest friendly drop site to a point: a drop-off building, or an anchored
 * Goliath (packing up, it is none). With `mc`, a Goliath or an outpost (which
 * can stand out on an island) only counts if a unit of that class at (x, y)
 * can drive up to it; the base's own drop-offs always count, as they always did.
 */
export function nearestDropSite(w, faction, x, y, mc) {
    let best = null;
    let bestD = Infinity;
    const reaches = (tx, ty, size) => !mc || canGetWithin(w, mc, x, y, tx + size / 2, ty + size / 2, DOCK_REACH, (px, py) => distToFootprint(tx, ty, size, px, py), size);
    for (const b of w.buildings.values()) {
        if (b.faction !== faction || !BUILDINGS[b.kind].dropOff)
            continue;
        const size = BUILDINGS[b.kind].size;
        if (b.outpost && !reaches(b.tx, b.ty, size))
            continue;
        const d = distToFootprint(b.tx, b.ty, size, x, y);
        if (d < bestD) {
            bestD = d;
            best = { id: b.id, faction, tx: b.tx, ty: b.ty, size };
        }
    }
    const size = GOLIATH.footprint;
    for (const u of w.units.values()) {
        if (u.faction !== faction || u.goliath?.mode !== "anchored" || u.goliath.lift)
            continue;
        const tx = u.goliath.foot?.tx ?? u.x - size / 2;
        const ty = u.goliath.foot?.ty ?? u.y - size / 2;
        if (!reaches(tx, ty, size))
            continue;
        const d = distToFootprint(tx, ty, size, x, y);
        if (d < bestD) {
            bestD = d;
            best = { id: u.id, faction, tx, ty, size };
        }
    }
    return best;
}

/** How close (tiles) to a drop site's footprint a harvester must get to unload (economy.ts tickHarvest). */
const DOCK_REACH = 1.2;

/** Distance from a point to a size² footprint at top-left (tx, ty) (0 inside). */
function distToFootprint(tx, ty, size, x, y) {
    const dx = Math.max(tx - x, 0, x - (tx + size));
    const dy = Math.max(ty - y, 0, y - (ty + size));
    return hypot(dx, dy);
}

/** Nearest friendly scrap drop-off building (HQ or depot) to a point. */
export function nearestDropOff(w, faction, x, y) {
    let best = null;
    let bestD = Infinity;
    for (const b of w.buildings.values()) {
        if (b.faction !== faction || !BUILDINGS[b.kind].dropOff)
            continue;
        const d = distToBuilding(b, x, y);
        if (d < bestD) {
            bestD = d;
            best = b;
        }
    }
    return best;
}

/** Does the faction own at least one building of this kind? */
export function hasBuilding(w, faction, kind) {
    for (const b of w.buildings.values())
        if (b.faction === faction && b.kind === kind)
            return true;
    return false;
}

const same = (p) => ({ x: p.x, y: p.y });
const IDENTITY_FRAME = { q: 0, toFrame: same, toWorld: same, tile: (fx, fy) => [fx, fy], vec: (dx, dy) => [dx, dy] };

export function sideFrame(w, faction) {
    const q = faction ? QUARTER[faction] : 0;
    if (q === 0)
        return IDENTITY_FRAME;
    if (q === 2) {
        const turn = (p) => ({ x: w.width - p.x, y: w.height - p.y });
        return { q, toFrame: turn, toWorld: turn, tile: (fx, fy, size) => [w.width - fx - size, w.height - fy - size], vec: (dx, dy) => [-dx, -dy] };
    }
    const back = 4 - q;
    return {
        q,
        toFrame: (p) => turnPoint(back, w.width, w.height, p.x, p.y),
        toWorld: (p) => turnPoint(q, w.width, w.height, p.x, p.y),
        tile: (fx, fy, size) => turnTile(q, w.width, w.height, fx, fy, size),
        vec: (dx, dy) => turnVec(q, dx, dy)
    };
}

/**
 * The world tile under point (x, y) as `faction` sees it: floored in the
 * side's own frame, so a point exactly on a tile edge (an Uplink at (28, 28))
 * belongs to the tile on the side's own far side, as it does for blue.
 */
export function frameTileOf(w, faction, x, y) {
    const q = faction ? QUARTER[faction] : 0;
    if (q === 0)
        return [Math.floor(x), Math.floor(y)];
    if (q === 2)
        return [w.width - 1 - Math.floor(w.width - x), w.height - 1 - Math.floor(w.height - y)];
    const f = turnPoint(4 - q, w.width, w.height, x, y);
    return turnTile(q, w.width, w.height, Math.floor(f.x), Math.floor(f.y), 1);
}
