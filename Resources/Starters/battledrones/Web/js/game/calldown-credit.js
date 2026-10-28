import { POWER_NAMES } from "../sim/powers.js";
import { hqOf } from "../sim/world.js";
import { otherSide, rivalsOf, sidesOf } from "../sim/sides.js";

/** Reach beyond an impact's radius: a building's centre sits inside its footprint; a unit may have moved this tick. */
const SLACK = { unit: 1, building: 2.2 };

/** "Barrage", "Sky Hammer"… */
export const powerName = (p) => POWER_NAMES[p];

/** "a Barrage", "an EMP", "the Sky Hammer" (in running text). */
export function powerPhrase(p) {
    return p === "hammer" ? "the Sky Hammer" : p === "emp" ? "an EMP" : `a ${POWER_NAMES[p]}`;
}

/**
 * Was `death` a calldown kill? `impacts` are this tick's impacts so far;
 * `hqId` names each side's HQ (null when it has none), `hqStanding` says
 * whether it still stands (a side without one credits its strikes to no one).
 * `rivals`: the sides that could have fired it (a duel's one enemy by default;
 * every other side in a free-for-all), the nearest impact of any of them wins.
 */
export function calldownKillOf(death, impacts, hqId, hqStanding = (f) => hqId(f) !== null, rivals = [otherSide(death.faction)]) {
    if (death.killerKind !== null)
        return null;
    const slack = death.buildingKind ? SLACK.building : SLACK.unit;
    let best = null;
    let bestD = Infinity;
    for (const by of rivals) {
        if (death.killerId === null ? hqStanding(by) : death.killerId !== hqId(by))
            continue;
        for (const im of impacts) {
            if (im.faction !== by)
                continue;
            const d = Math.hypot(death.x - im.x, death.y - im.y);
            if (d <= im.radius + slack && d < bestD) {
                bestD = d;
                best = im;
            }
        }
    }
    return best ? { power: best.power, faction: best.faction, calldownId: best.id } : null;
}

/**
 * A per-consumer tracker: feed it every fx event in stream order (it keeps
 * the current tick's impacts) and it answers for each death. HQ ids are
 * remembered, so a strike that lands as its own HQ falls is still credited.
 */
export class CalldownCredit {
    w;
    tick = -1;
    impacts = [];
    hqs = {};

    constructor(w) {
        this.w = w;
        for (const f of sidesOf(w))
            this.hqId(f);
    }

    hqId(f) {
        const known = this.hqs[f];
        if (known)
            return known;
        const id = hqOf(this.w, f)?.id ?? null;
        this.hqs[f] = id;
        return id;
    }

    /** Feed one event; for a calldown kill (a death) returns who did it with what. */
    see(ev) {
        if (this.w.tick !== this.tick) {
            this.tick = this.w.tick;
            this.impacts = [];
        }
        if (ev.type === "calldownImpact") {
            this.impacts.push(ev);
            return null;
        }
        if (ev.type !== "death" || this.impacts.length === 0)
            return null;
        return calldownKillOf(ev, this.impacts, (f) => this.hqId(f), (f) => hqOf(this.w, f) !== null, rivalsOf(this.w, ev.faction));
    }

    /** One tick's events at once: death id → credit (empty when no calldown landed). */
    scan(fx) {
        const out = new Map();
        for (const ev of fx) {
            const k = this.see(ev);
            if (k && ev.type === "death")
                out.set(ev.id, k);
        }
        return out;
    }
}
