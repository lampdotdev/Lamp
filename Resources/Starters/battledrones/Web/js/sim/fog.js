// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { BUILDINGS, OBJECTIVES, UNITS } from "./balance.js";
import { rulesOf } from "./rules.js";
import { inBounds } from "./world.js";
import { perSide, sidesOf } from "./sides.js";

export function createFog(width, height) {
    return perSide(() => ({ vis: new Uint8Array(width * height), known: new Map() }));
}

const idx = (w, tx, ty) => ty * w.width + tx;

export function isVisible(w, f, tx, ty) {
    return inBounds(w, tx, ty) && w.fog[f].vis[idx(w, tx, ty)] === 2 /* Vis.Visible */;
}

export function isExplored(w, f, tx, ty) {
    return inBounds(w, tx, ty) && w.fog[f].vis[idx(w, tx, ty)] >= 1 /* Vis.Explored */;
}

export function knownBuildings(w, f) {
    return [...w.fog[f].known.values()];
}

function stamp(w, vis, cx, cy, radius) {
    const r2 = radius * radius;
    const x0 = Math.max(0, Math.floor(cx - radius));
    const x1 = Math.min(w.width - 1, Math.ceil(cx + radius));
    const y0 = Math.max(0, Math.floor(cy - radius));
    const y1 = Math.min(w.height - 1, Math.ceil(cy + radius));
    for (let ty = y0; ty <= y1; ty++)
        for (let tx = x0; tx <= x1; tx++) {
            // (products, not `** 2`: the exponent operator is as loosely specified as Math.pow, fmath.ts)
            const dx = tx + 0.5 - cx;
            const dy = ty + 0.5 - cy;
            if (dx * dx + dy * dy <= r2)
                vis[ty * w.width + tx] = 2 /* Vis.Visible */;
        }
}

function footprintVisible(w, f, b) {
    const size = BUILDINGS[b.kind].size;
    for (let dy = 0; dy < size; dy++)
        for (let dx = 0; dx < size; dx++)
            if (isVisible(w, f, b.tx + dx, b.ty + dy))
                return true;
    return false;
}

/** Recompute every side's visibility and building memory. */
export function tickFog(w) {
    for (const f of sidesOf(w)) {
        const fog = w.fog[f];
        // decay: everything visible becomes merely explored
        for (let i = 0; i < fog.vis.length; i++)
            if (fog.vis[i] === 2 /* Vis.Visible */)
                fog.vis[i] = 1 /* Vis.Explored */;
        for (const u of w.units.values())
            if (u.faction === f)
                stamp(w, fog.vis, u.x, u.y, UNITS[u.kind].sight);
        for (const b of w.buildings.values())
            if (b.faction === f) {
                const size = BUILDINGS[b.kind].size;
                stamp(w, fog.vis, b.tx + size / 2, b.ty + size / 2, BUILDINGS[b.kind].sight + size / 2);
            }
        for (const l of w.objectives.uplinks)
            if (l.owner === f)
                stamp(w, fog.vis, l.x, l.y, OBJECTIVES.uplink.sight); // a held Uplink sees around it
        // Clear Skies mutator: everything is in sight for both sides
        if (rulesOf(w).fogOff)
            fog.vis.fill(2 /* Vis.Visible */);
        // memory: record enemy buildings whose footprint we can see now (a Gantry: always)
        for (const b of w.buildings.values())
            if (b.faction !== f && (BUILDINGS[b.kind].alwaysVisible || footprintVisible(w, f, b)))
                fog.known.set(b.id, { id: b.id, kind: b.kind, faction: b.faction, tx: b.tx, ty: b.ty });
        // forget remembered buildings we can re-see are gone (a Gantry's fall is seen at once)
        for (const [id, kb] of fog.known)
            if (!w.buildings.has(id) && (BUILDINGS[kb.kind].alwaysVisible || footprintVisible(w, f, kb)))
                fog.known.delete(id);
    }
}

export function buildingSightCenter(b) {
    const size = BUILDINGS[b.kind].size;
    return { x: b.tx + size / 2, y: b.ty + size / 2 };
}
