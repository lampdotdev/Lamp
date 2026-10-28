/**
 * Building placement helpers for the player's touch flow (and anything else
 * that wants to explain or suggest a spot). The rule itself stays
 * `canPlaceBuilding` in economy.ts: these functions only explain why a spot
 * fails and find a good valid one, so they can never disagree with it.
 */
import { BUILDINGS, ECONOMY, GOLIATH, TERRAIN } from "./balance.js";
import { canPlaceBuilding, inBaseRange } from "./economy.js";
import { anchoredGoliaths, inGoliathRing, overlapsGoliath } from "./goliath.js";
import { buildingAtTile, buildingCenter, domainOf, inBounds, terrainAt } from "./world.js";
import { hypot } from "./fmath.js";

/** Short names for unbuildable ground, per biome where it differs. */
function groundName(w, t) {
    switch (t) {
        case 3 /* Terrain.Water */:
            return w.biome === "volcanic" ? "lava" : "water";
        case 10 /* Terrain.Deep */:
            return "open sea";
        case 1 /* Terrain.Rock */:
            return "rock";
        case 5 /* Terrain.Rough */:
            return { temperate: "mud", desert: "scree", arctic: "slush", volcanic: "cinders", tropical: "mudflat" }[w.biome];
        case 6 /* Terrain.Forest */:
            return "woods";
        case 2 /* Terrain.Scrap */:
            return "scrap";
        case 7 /* Terrain.Crystal */:
            return "crystals";
        case 8 /* Terrain.Bridge */:
            return "a bridge";
        case 9 /* Terrain.Shallows */:
            return "a ford";
        default:
            return TERRAIN[t].name.toLowerCase();
    }
}

/**
 * Why `kind` can't go at top-left tile (tx, ty), as a short phrase for the
 * HUD ("Too far from base", "Blocked", "Not on water"), or null when it can.
 * Agrees with canPlaceBuilding by construction.
 */
export function placementBlocker(w, faction, kind, tx, ty) {
    if (canPlaceBuilding(w, faction, kind, tx, ty))
        return null;
    const size = BUILDINGS[kind].size;
    let offMap = false;
    let ground = null;
    let building = false;
    for (let dy = 0; dy < size; dy++)
        for (let dx = 0; dx < size; dx++) {
            const x = tx + dx;
            const y = ty + dy;
            if (!inBounds(w, x, y)) {
                offMap = true;
                continue;
            }
            if (buildingAtTile(w, x, y))
                building = true;
            else if (!TERRAIN[terrainAt(w, x, y)].buildable && ground === null)
                ground = terrainAt(w, x, y);
        }
    if (offMap)
        return "Off the map";
    // the most fundamental problem first: nothing nearby can be fixed by nudging
    if (!inBuildRange(w, faction, tx + size / 2, ty + size / 2) && (kind === "hq" || !inGoliathRing(w, faction, tx, ty, size)))
        return "Too far from base";
    if (ground !== null)
        return `Not on ${groundName(w, ground)}`;
    if (building)
        return "Blocked";
    for (const u of w.units.values())
        if (domainOf(u) === "ground" && u.x >= tx && u.x < tx + size && u.y >= ty && u.y < ty + size)
            return "Unit in the way";
    if (overlapsGoliath(w, tx, ty, size))
        return "Unit in the way";
    return "Blocked"; // a rule this explainer doesn't know about yet
}

/**
 * Is a footprint centred at (cx, cy) within build range of `faction`'s base?
 * Outposts (built in a Goliath's ring) never count as base; the rings
 * themselves are inGoliathRing.
 */
export function inBuildRange(w, faction, cx, cy) {
    return inBaseRange(w, faction, cx, cy);
}

/**
 * Would a footprint here leave no free tile along some side, walling in
 * what's next to it? (Mirrors the AI's own lane-keeping rule.)
 */
function cramped(w, tx, ty, size) {
    let free = 0;
    for (let i = -1; i <= size; i++)
        for (const [x, y] of [
            [tx + i, ty - 1],
            [tx + i, ty + size],
            [tx - 1, ty + i],
            [tx + size, ty + i]
        ]) {
            if (!inBounds(w, x, y))
                continue;
            if (w.occupancy[y * w.width + x] === 0 && TERRAIN[terrainAt(w, x, y)].ground)
                free++;
        }
    return free < (size + 2) * 2;
}

/**
 * The best valid top-left tile for `kind` near `anchor` (tile coords, e.g.
 * the middle of the player's view): the closest spot in build range, with a
 * small penalty for spots that would wall a lane shut. Null if nowhere fits.
 */
export function suggestPlacement(w, faction, kind, anchor) {
    const size = BUILDINGS[kind].size;
    const seen = new Set();
    let best = null;
    let bestScore = Infinity;
    // search around the base's buildings (not outposts: they don't count) and anchored Goliaths' rings
    const centres = [];
    for (const b of w.buildings.values())
        if (b.faction === faction && !b.outpost)
            centres.push({ c: buildingCenter(b), r: Math.ceil(ECONOMY.buildRadius + size) });
    if (kind !== "hq")
        for (const g of anchoredGoliaths(w, faction))
            centres.push({ c: g, r: Math.ceil(GOLIATH.buildRing + size) });
    for (const { c, r } of centres) {
        for (let dy = -r; dy <= r; dy++)
            for (let dx = -r; dx <= r; dx++) {
                const tx = Math.round(c.x + dx - size / 2);
                const ty = Math.round(c.y + dy - size / 2);
                const key = ty * 4096 + tx;
                if (seen.has(key))
                    continue;
                seen.add(key);
                const d = hypot(tx + size / 2 - anchor.x, ty + size / 2 - anchor.y);
                if (d >= bestScore)
                    continue;
                if (!canPlaceBuilding(w, faction, kind, tx, ty))
                    continue;
                const score = d + (size > 1 && cramped(w, tx, ty, size) ? 4 : 0);
                if (score < bestScore || (score === bestScore && best && (ty < best.ty || (ty === best.ty && tx < best.tx)))) {
                    best = { tx, ty };
                    bestScore = score;
                }
            }
    }
    return best;
}

/**
 * A finger tap is imprecise: if (tx, ty) is invalid but a valid spot is one
 * tile away, use that (closest first, in a fixed order). Otherwise the tap
 * stands, so the ghost can show why it can't go there.
 */
export function snapPlacement(w, faction, kind, tx, ty) {
    if (canPlaceBuilding(w, faction, kind, tx, ty))
        return { tx, ty };
    const ring = [[0, -1], [1, 0], [0, 1], [-1, 0], [1, -1], [1, 1], [-1, 1], [-1, -1]];
    for (const [dx, dy] of ring)
        if (canPlaceBuilding(w, faction, kind, tx + dx, ty + dy))
            return { tx: tx + dx, ty: ty + dy };
    return { tx, ty };
}
