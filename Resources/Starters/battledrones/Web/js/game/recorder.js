// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { worldHash } from "../sim/checksum.js";
import { sidesOf } from "../sim/sides.js";
/** The sim this build plays (vite.config.ts), or null outside a Vite build (tests). */
const BUILD_SIM = typeof __SIM_HASH__ === "undefined" ? null : __SIM_HASH__;


/** A world hash goes into the record every this many ticks: the arena's rate (arena/record.ts HASH_EVERY), which the viewer checks. */
export const HASH_EVERY = 100;

/**
 * How a decided world ends its record: arena/record.ts endOf, which this
 * may not import (tests/resign.test.ts holds the two together).
 */
export function recordEnd(tick, winner, resigned) {
    if (winner === "draw")
        return { tick, winner: null, reason: resigned === null ? "resign" : "love" };
    return { tick, winner, reason: resigned ? "resign" : "hq" };
}

export class MatchRecorder {
    map;
    opts;
    seats;
    openers = {};
    turns = [];
    hashes = [];
    created = new Date().toISOString();

    constructor(map, opts, seats) {
        this.map = map;
        this.opts = opts;
        this.seats = seats;
    }

    /** The openers each side was dealt (before tick 0). */
    setOpeners(picks) {
        this.openers = { ...picks };
    }

    /** Tick `w.tick - 1` was just stepped with `cmds`. */
    stepped(w, cmds) {
        const t = w.tick - 1;
        for (const side of sidesOf(w)) {
            const theirs = cmds.filter((c) => c.faction === side);
            if (theirs.length)
                this.turns.push([t, side, structuredClone(theirs)]);
        }
        if (w.tick % HASH_EVERY === 0)
            this.hashes.push([w.tick, worldHash(w)]);
    }

    /** The record of the match so far. */
    record(w) {
        const income = {};
        for (const f of sidesOf(w))
            if (w.factions[f].incomeMult !== 1)
                income[f] = w.factions[f].incomeMult;
        const end = w.winner ? recordEnd(w.tick, w.winner, w.resigned) : null;
        const o = this.opts;
        return {
            v: 1,
            commit: null,
            sim: BUILD_SIM,
            created: this.created,
            map: this.map,
            mutators: o.mutators?.slice() ?? [],
            seed: w.seed,
            round: 1,
            maxTicks: w.tick,
            openers: { ...this.openers },
            ...(Object.keys(income).length ? { income } : {}),
            ...(o.survival ? { survival: { ...o.survival } } : {}),
            ...(o.op ? { op: o.op } : {}),
            seats: Object.fromEntries(sidesOf(w).map((f) => [f, { ...this.seats[f] }])),
            frames: "own",
            turns: this.turns.map(([t, f, c]) => [t, f, c]),
            radio: [],
            hashes: this.hashes.slice(),
            log: [],
            tick: w.tick,
            end,
            usage: {}
        };
    }
}
