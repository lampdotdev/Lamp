// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { SIDE_NAME } from "./side-style.js";
import { Ease } from "./three/tween.js";

/**
 * The cinematic end of a match (render only — the sim has already stopped
 * at the winner). A kill: everything drops to slow motion, the camera
 * glides and zooms onto what decided it (an HQ, or a side's last Goliath
 * toppling), a staged chain of explosions rolls across it, a white flash
 * and a heavy shake, then real time resumes and the end screen arrives at
 * ~2.8 s. Robot Love: no blasts and no slow motion — the camera glides onto
 * the two Goliaths as they meet (render/goliath.ts plays their part), a
 * burst of hearts, the banner, and the draw.
 */

export const FINALE = {
    /** Render time scale during the slow-motion stretch. */
    slow: 0.3,
    /** Camera glide onto the HQ (real ms). */
    panMs: 900,
    /** First blast, interval between blasts, and how many (real ms). */
    blastAt: 250,
    blastEvery: 250,
    blasts: 5,
    /** White flash; slow motion eases back to real time after it. */
    flashAt: 1500,
    easeOutMs: 700,
    /** End screen. */
    doneAt: 2800
};

/** Robot Love's beats (real ms): the heart burst as their hands meet, the banner, the end screen. */
export const LOVE_FINALE = {
    burstAt: 4300,
    bannerAt: 4700,
    doneAt: 7800
};

export class Finale {
    o;
    /** Current render time scale (GameScene scales frame deltas by it). */
    timeScale = FINALE.slow;
    t = 0;
    flashed = false;
    done = false;
    blasts = 0;
    spots = [
        [-0.55, -0.45], [0.5, -0.5], [-0.45, 0.5], [0.55, 0.45], [0, 0]
    ];

    pan;

    constructor(o) {
        this.o = o;
        this.apply(o.love ? 1 : FINALE.slow);
        const rig = o.view.rig;
        this.pan = { x0: rig.x, y0: rig.y, t: 0 };
    }

    /** Glide the camera so the HQ lands mid free area (recomputed as the zoom pushes in). */
    glide(realMs) {
        const p = this.pan;
        if (!p)
            return;
        p.t = Math.min(FINALE.panMs, p.t + realMs);
        const rig = this.o.view.rig;
        const to = rig.targetFor(this.o.x, this.o.y, this.o.screenX ?? rig.width / 2, this.o.screenY ?? rig.height / 2);
        const k = Ease.sineInOut(p.t / FINALE.panMs);
        rig.x = p.x0 + (to.x - p.x0) * k;
        rig.y = p.y0 + (to.y - p.y0) * k;
        rig.apply();
        if (p.t >= FINALE.panMs)
            this.pan = null;
    }

    /** Advance with the real (unscaled) frame delta. */
    update(realMs) {
        if (this.done)
            return;
        this.t += realMs;
        this.glide(realMs);
        const v = this.o.view;
        if (this.o.love) {
            this.loveBeats(realMs);
            return;
        }
        // staged chain of blasts across the footprint, outside-in (real time,
        // like everything here, so a slow frame can't reorder the beats)
        const n = this.o.blasts === false ? 0 : Math.min(FINALE.blasts, this.spots.length);
        while (this.blasts < n && this.t >= FINALE.blastAt + this.blasts * FINALE.blastEvery) {
            const [dx, dy] = this.spots[this.blasts];
            const last = this.blasts === n - 1;
            const half = this.o.size / 2;
            const bx = this.o.x + dx * half;
            const by = this.o.y + dy * half;
            // (sized for what died: an HQ's full chain, a Goliath's a little smaller)
            const k = Math.min(1, this.o.size / 3);
            this.o.fx.explosion({ type: "explosion", x: this.o.x, y: this.o.y, size: (last ? 2.2 : 1.3) * k, air: false, kind: "building" }, { x: bx, y: by, h: v.terrain.heightAt(bx, by) + 0.4 });
            this.blasts++;
        }
        if (!this.flashed && this.t >= FINALE.flashAt) {
            this.flashed = true;
            // the core goes up: a blast front rolls out across the base and a pillar of smoke climbs
            if (n > 0) {
                const h = v.terrain.heightAt(this.o.x, this.o.y);
                this.o.fx.shock(this.o.x, this.o.y, this.o.size * 1.5, 0xfff0d8, 0.85, 800);
                this.o.fx.plume(this.o.x, this.o.y, h + 0.6, 1.4 + this.o.size * 0.3, 8);
            }
            v.stage.flash(380, 255, 244, 228);
            v.rig.shake(520, 0.011);
            this.o.onFlash();
        }
        if (this.flashed) {
            const k = Math.min(1, (this.t - FINALE.flashAt) / FINALE.easeOutMs);
            this.apply(FINALE.slow + (1 - FINALE.slow) * k * k);
        }
        if (this.t >= FINALE.doneAt) {
            this.done = true;
            this.apply(1);
            this.o.onDone();
        }
    }

    /** Robot Love: a burst of hearts where they meet, the banner, then the draw. */
    loveBeats(realMs) {
        const t = this.t;
        const prev = t - realMs;
        const { x, y } = this.o;
        if (prev < LOVE_FINALE.burstAt && t >= LOVE_FINALE.burstAt) {
            const h = this.o.view.terrain.heightAt(x, y);
            this.o.fx.heartBurst(x, y, h + 2.2);
            this.o.fx.sound("love", x, y, 1);
        }
        if (!this.flashed && t >= LOVE_FINALE.bannerAt) {
            this.flashed = true;
            this.o.onFlash();
        }
        if (t >= LOVE_FINALE.doneAt) {
            this.done = true;
            this.o.onDone();
        }
    }

    /** Slow (or restore) every render clock: GameScene scales the frame delta for tweens, particles and effects by it. */
    apply(k) {
        this.timeScale = k;
    }
}

/**
 * How the score resolves at the flash: a fanfare for a win (or a new Last
 * Stand record), a lament for a loss. A spectator hears the winner's fanfare,
 * except in Last Stand, where the watched base is always overrun in the end.
 */
export function finaleOutcome(o) {
    return o.won || o.newRecord || (o.spectator && !o.survival) ? "victory" : "defeat";
}

/**
 * The finale's banner: who won and what decided it. The keys stay the
 * announcer's (victory, defeat, hq-destroyed for a spectator, draw), only
 * the words change with the cause: an HQ ("Enemy HQ destroyed"), a side's
 * last Goliath ("Our last Goliath has fallen"), two Goliaths in love, or a
 * sound duel's resign ("Your friend resigned"; both at once is a draw, never
 * the Robot Love line).
 */
export function finaleBanner(o) {
    const { x, y } = o;
    if (o.lastOut && o.winner !== "draw") {
        // a free-for-all's end: the last rival standing falls
        const loser = SIDE_NAME[o.lastOut];
        const won = SIDE_NAME[o.winner];
        if (o.spectator)
            return { key: "hq-destroyed", text: `${loser} knocked out`, sub: `${won} wins`, tone: "epic", priority: 0, x, y };
        if (o.winner === o.player)
            return { key: "victory", text: "Last rival knocked out", sub: "Victory", tone: "epic", priority: 0, x, y };
        return { key: "defeat", text: o.lastOut === o.player ? "We're out" : `${won} takes the field`, sub: o.lastOut === o.player ? "Defeat" : `${won} wins`, tone: "bad", priority: 0, x, y };
    }
    if (o.cause === "resign") {
        if (o.winner === "draw")
            return { key: "draw", text: "Both resigned", sub: "Draw", tone: "info", priority: 0, x, y };
        if (o.spectator) {
            const won = o.winner === "blue" ? "Blue" : "Red";
            return { key: "hq-destroyed", text: `${won === "Blue" ? "Red" : "Blue"} resigned`, sub: `${won} wins`, tone: "epic", priority: 0, x, y };
        }
        if (o.winner === o.player)
            return { key: "victory", text: "Your friend resigned", sub: "Victory", tone: "epic", priority: 0, x, y };
        return { key: "defeat", text: "You resigned", sub: "Defeat", tone: "bad", priority: 0, x, y };
    }
    if (o.winner === "draw" || o.cause === "love")
        return { key: "draw", text: "💘 They fell in love", sub: "It's a draw", tone: "good", priority: 0, x, y, say: "They fell in love. It's a draw." };
    const loser = o.winner === "blue" ? "Red" : "Blue";
    const what = o.cause === "goliath" ? "Goliath" : "HQ";
    if (o.spectator)
        return { key: "hq-destroyed", text: `${loser} ${what} destroyed`, sub: `${loser === "Red" ? "Blue" : "Red"} wins`, tone: "epic", priority: 0, x, y };
    if (o.winner === o.player)
        return { key: "victory", text: `Enemy ${what} destroyed`, sub: "Victory", tone: "epic", priority: 0, x, y };
    return { key: "defeat", text: o.cause === "goliath" ? "Our last Goliath has fallen" : "Our HQ has fallen", sub: "Defeat", tone: "bad", priority: 0, x, y };
}

/** Zoom the finale settles at: a push-in, but never further out than `atLeast`. */
export function finaleZoom(current, atLeast) {
    return Math.max(current * 1.3, atLeast);
}

/**
 * Where the middle of the unobstructed battlefield sits relative to the
 * canvas centre, in CSS px: the build dock covers the bottom (portrait) or
 * the right edge (landscape).
 */
export function freeAreaOffset() {
    const bar = document.querySelector(".buildbar")?.getBoundingClientRect();
    const W = window.innerWidth;
    const H = window.innerHeight;
    if (!bar || bar.width === 0 || bar.height === 0)
        return { x: 0, y: 0 };
    if (bar.top > H * 0.4)
        return { x: 0, y: (bar.top - H) / 2 };
    if (bar.left > W * 0.4)
        return { x: (bar.left - W) / 2, y: 0 };
    return { x: 0, y: 0 };
}
