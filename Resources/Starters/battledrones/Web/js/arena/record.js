// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { step } from "../sim/sim.js";

// setup and hashing live in the sim, shared with sound duels (SOUND-DUEL.md)
export { setupWorld } from "../sim/setup.js";
export { worldHash } from "../sim/checksum.js";
import { setupWorld } from "../sim/setup.js";
import { worldHash } from "../sim/checksum.js";

export const HASH_EVERY = 100;

/**
 * How a decided world ends a record: a side won, or nobody did. `resigned`
 * is the world's own: the side that gave up, null when both did on one tick
 * (a draw by "resign", not Robot Love's), unset otherwise (an HQ, or Robot
 * Love). The sound duel's duelEnd (src/versus/records.ts, which may not
 * import this) says the same; tests/resign.test.ts holds them together.
 */
export function endOf(tick, winner, resigned) {
    if (winner === "draw")
        return { tick, winner: null, reason: resigned === null ? "resign" : "love" };
    return { tick, winner, reason: resigned ? "resign" : "hq" };
}

/**
 * Re-run a record from its setup and commands, checking the hash trail.
 * `until` stops early (a tick); `onTick` sees the world after every step.
 */
export function replay(r, opts = {}) {
    const w = setupWorld(r);
    const byTick = new Map();
    for (const [tick, , cmds] of r.turns)
        byTick.set(tick, [...(byTick.get(tick) ?? []), ...cmds]);
    const hashes = new Map(r.hashes);
    // (an unfinished record: as far as it was played; one from before `tick` was kept: its last checkpoint)
    const end = Math.min(opts.until ?? Infinity, r.end?.tick ?? r.tick ?? Math.max(0, ...r.hashes.map((h) => h[0])));
    let divergedAt = null;
    let checked = 0;
    while (w.tick < end && !w.winner) {
        step(w, byTick.get(w.tick) ?? []);
        opts.onTick?.(w);
        const want = hashes.get(w.tick);
        if (want !== undefined) {
            checked++;
            if (divergedAt === null && worldHash(w) !== want)
                divergedAt = w.tick;
        }
    }
    return { world: w, divergedAt, checked };
}

// --------------------------------------------------------------- upgrade ---

/**
 * The same battle on this sim code: the record's commands re-run from its
 * setup, with a new hash trail and ending, so a record from older sim code
 * replays (exactly, from then on) with this one. The commands were chosen
 * against the old sim's world, and they are kept as they were: a unit that
 * died a moment sooner ignores its last order, a building placed on a tile
 * now in use isn't, so a re-simulated battle can end differently, or later.
 * If no HQ has fallen by the original ending, it plays on with the standing
 * orders until one does, or until the battle's time limit (a draw). The
 * models' notes, orders and radio lines stay as they were played; `upgraded`
 * keeps what the record said before, its ending included.
 */
export function resimulate(r, code) {
    const w = setupWorld(r);
    const byTick = new Map();
    for (const [tick, , cmds] of r.turns)
        byTick.set(tick, [...(byTick.get(tick) ?? []), ...cmds]);
    // (a draw on time stays a draw on time; a finished battle plays on until an HQ falls; an unfinished one as far as it went)
    const limit = r.end?.reason === "time" ? r.end.tick : r.end ? r.maxTicks : r.tick;
    const hashes = [];
    while (w.tick < limit && !w.winner) {
        step(w, byTick.get(w.tick) ?? []);
        if (w.tick % HASH_EVERY === 0)
            hashes.push([w.tick, worldHash(w)]);
    }
    const end = w.winner
        ? endOf(w.tick, w.winner, w.resigned)
        : r.end
            ? { tick: w.tick, winner: null, reason: r.end.reason === "aborted" ? "aborted" : "time" }
            : null;
    return {
        ...r,
        commit: code.commit,
        sim: code.sim,
        // (new hashes: the version it was pinned to no longer plays them)
        version: undefined,
        hashes,
        tick: w.tick,
        end,
        upgraded: [...(r.upgraded ?? []), { from: { commit: r.commit, sim: r.sim }, end: r.end, at: new Date().toISOString() }]
    };
}
