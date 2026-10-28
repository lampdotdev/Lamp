// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

export const Ease = {
    linear: (k) => k,
    quadIn: (k) => k * k,
    quadOut: (k) => k * (2 - k),
    cubicOut: (k) => 1 - Math.pow(1 - k, 3),
    sineOut: (k) => Math.sin((k * Math.PI) / 2),
    sineInOut: (k) => -(Math.cos(Math.PI * k) - 1) / 2,
    backOut: (k) => {
        const c1 = 1.70158;
        const c3 = c1 + 1;
        return 1 + c3 * Math.pow(k - 1, 3) + c1 * Math.pow(k - 1, 2);
    }
};

export class Tweens {
    list = [];

    add(spec) {
        this.list.push({ ...spec, t: 0, dead: false });
    }

    /** Run `fn` after `ms` of render time. */
    after(ms, fn, owner) {
        this.add({ dur: 0, delay: ms, owner, done: fn });
    }

    /** Stop (without finishing) every tween registered with this owner. */
    kill(owner) {
        for (const t of this.list)
            if (t.owner === owner)
                t.dead = true;
    }

    update(dtMs) {
        if (this.list.length === 0)
            return;
        const live = [];
        // (callbacks may add tweens: iterate a snapshot, keep the new ones)
        const list = this.list;
        this.list = [];
        for (const tw of list) {
            if (tw.dead)
                continue;
            tw.t += dtMs;
            const delay = tw.delay ?? 0;
            if (tw.t < delay) {
                live.push(tw);
                continue;
            }
            const raw = tw.dur <= 0 ? 1 : Math.min(1, (tw.t - delay) / tw.dur);
            const k = tw.yoyo ? 1 - Math.abs(raw * 2 - 1) : raw;
            tw.update?.((tw.ease ?? Ease.linear)(k));
            if (raw >= 1) {
                tw.dead = true;
                tw.done?.();
            }
            else
                live.push(tw);
        }
        this.list = live.concat(this.list);
    }

    get size() {
        return this.list.length;
    }

    clear() {
        this.list = [];
    }
}
