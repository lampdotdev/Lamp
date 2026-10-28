// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
/**
 * Onboarding hint pacing. A new player has a lot of one-time tips coming
 * their way in the first minutes (the tutorial stages, squads, touch
 * placement, infantry and the Condor, the Goliath and its lift, calldowns,
 * salvage), each gated once per device by its own module. Shown as they
 * trigger, several would land at once — usually on top
 * of the opener roll-out banner. Every one-time hint goes through this queue
 * instead:
 *
 * - at most one hint every `gapS` seconds of play (paused time doesn't count);
 * - the most important waiting hint goes first (lower `priority`), oldest
 *   first among equals;
 * - a hint that is no longer true (`valid()` false) or has waited longer than
 *   its `ttlS` is dropped — its module can offer it again next time, since
 *   the once-only flag is only written when the hint is actually shown
 *   (`onShow`);
 * - while the HUD is busy with a big moment (opener cards, a banner, the
 *   finale) nothing new starts.
 *
 * Offering an id that is already waiting does nothing, so modules can simply
 * re-offer every frame while their condition holds. Engine-free and tested
 * (tests/hints.test.ts); the HUD (src/ui/hud.ts) owns the instance.
 */

export const HINTS = {
    /** Seconds of play between two hints starting. */
    gapS: 12,
    /** A waiting hint is dropped after this long (seconds of play) unless it says otherwise. */
    ttlS: 30,
    /** How long a hint stays in the ticker, ms. */
    showMs: 7000,
    /** Priorities (lower first): what the player is doing right now beats the curriculum. */
    priority: { placement: 0, squads: 1, transport: 1, goliath: 1, tutorial: 2, calldowns: 3, salvage: 4 }
};

export class HintQueue {
    waiting = [];
    clock = 0;
    lastShown = -Infinity;
    /** Every hint shown: id and when (seconds of play), for debugging and tests. */
    log = [];

    /** Seconds of play so far. */
    get now() {
        return this.clock;
    }

    /** Queue a hint; false if one with this id is already waiting. */
    offer(h) {
        if (this.waiting.some((w) => w.id === h.id))
            return false;
        this.waiting.push({ ...h, at: this.clock });
        return true;
    }

    has(id) {
        return this.waiting.some((w) => w.id === id);
    }

    get size() {
        return this.waiting.length;
    }

    /**
     * Advance the play clock by `dtS` seconds (pass 0 while paused) and return
     * the hint to show now, if any. `quiet`: a big moment is on screen, hold back.
     */
    update(dtS, quiet) {
        this.clock += Math.max(0, dtS);
        this.waiting = this.waiting.filter((w) => this.clock - w.at <= (w.ttlS ?? HINTS.ttlS) && (w.valid?.() ?? true));
        if (quiet || this.waiting.length === 0 || this.clock - this.lastShown < HINTS.gapS)
            return null;
        let best = 0;
        for (let i = 1; i < this.waiting.length; i++) {
            const a = this.waiting[i];
            const b = this.waiting[best];
            if (a.priority < b.priority || (a.priority === b.priority && a.at < b.at))
                best = i;
        }
        const h = this.waiting.splice(best, 1)[0];
        this.lastShown = this.clock;
        this.log.push({ id: h.id, t: this.clock });
        h.onShow?.();
        return h;
    }
}
