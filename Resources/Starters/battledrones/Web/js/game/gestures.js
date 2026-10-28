
export const TAP_SLOP_PX = 8;
export const HOLD_DELAY_MS = 250;
export const DOUBLE_TAP_MS = 300;
export const DOUBLE_TAP_SLOP_PX = 24;
/** Finger distance must change this much before a pinch starts zooming —
 * otherwise two-finger pans wobble the zoom from natural finger jitter. */
export const PINCH_ACTIVATE_PX = 16;
/** A finger farther than this from where a pointer was last seen isn't that pointer's finger. */
export const STRAND_PX = 64;

/**
 * Which tracked touch pointers have no finger on the screen any more? iOS
 * Safari can end a touch with neither pointerup nor pointercancel (an edge
 * swipe it abandons: WebKit bug 239014), so a recognizer left alone would
 * count that finger as down for good. `touches` is every finger down now (a
 * touchstart's TouchEvent.touches); each vouches for the nearest unclaimed
 * pointer within STRAND_PX (client coordinates), and pointers no finger
 * vouches for are stranded. The finger that just landed is in `touches`
 * whether its pointerdown came before the touchstart or comes after.
 */
export function strandedPointers(pointers, touches) {
    if (pointers.size === 0)
        return [];
    const pairs = [];
    for (const [id, p] of pointers)
        for (let t = 0; t < touches.length; t++) {
            const d = Math.hypot(touches[t].clientX - p.x, touches[t].clientY - p.y);
            if (d <= STRAND_PX)
                pairs.push({ id, t, d });
        }
    pairs.sort((a, b) => a.d - b.d);
    const held = new Set();
    const claimed = new Set();
    for (const { id, t } of pairs) {
        if (held.has(id) || claimed.has(t))
            continue;
        held.add(id);
        claimed.add(t);
    }
    return [...pointers.keys()].filter((id) => !held.has(id));
}

/**
 * Was this box (start and end corners) really a long-press released without
 * dragging? The recognizer reports such a hold as a degenerate box
 * (onBoxStart + onBoxEnd at about the same point); callers give it its own
 * meaning — loaded Condors drop their squads there (GameScene) — but only
 * when onBoxEnd says it was `released`.
 */
export function isHoldRelease(x0, y0, x1, y1) {
    return Math.hypot(x1 - x0, y1 - y0) <= TAP_SLOP_PX;
}

export class GestureRecognizer {
    cb;
    mode = "idle";
    pointers = new Map();
    downX = 0;
    downY = 0;
    downTime = 0;
    downType = "touch";
    lastX = 0;
    lastY = 0;
    lastTapTime = -Infinity;
    lastTapX = 0;
    lastTapY = 0;
    pinchDist = 0;
    pinchStartDist = 0;
    pinchActive = false;

    constructor(cb) {
        this.cb = cb;
    }

    down(p, now) {
        if (p.pointerType === "mouse" && p.button === 2) {
            this.cb.onRightClick(p.x, p.y);
            return;
        }
        this.pointers.set(p.id, { id: p.id, x: p.x, y: p.y, type: p.pointerType });

        if (this.pointers.size === 2) {
            this.enterMulti();
            return;
        }
        if (this.pointers.size > 2)
            return;

        if (p.pointerType === "mouse" && p.button === 1) {
            this.mode = "mousepan";
        }
        else {
            this.mode = "pending";
        }
        this.downX = p.x;
        this.downY = p.y;
        this.downTime = now;
        this.downType = p.pointerType;
        this.lastX = p.x;
        this.lastY = p.y;
    }

    move(p, now) {
        // (a pointer this never saw go down, or forgot, steers nothing)
        const t = this.pointers.get(p.id);
        if (!t)
            return;
        t.x = p.x;
        t.y = p.y;

        switch (this.mode) {
            case "pending": {
                const moved = Math.hypot(p.x - this.downX, p.y - this.downY) > TAP_SLOP_PX;
                if (!moved)
                    break;
                if (now - this.downTime >= HOLD_DELAY_MS || this.downType === "mouse") {
                    // mouse drags box-select immediately; touch only after the hold
                    this.mode = "box";
                    this.cb.onBoxStart(this.downX, this.downY);
                    this.cb.onBoxMove(p.x, p.y);
                }
                else {
                    this.mode = "pan";
                    this.cb.onPan(p.x - this.downX, p.y - this.downY);
                }
                this.lastX = p.x;
                this.lastY = p.y;
                break;
            }
            case "pan":
            case "mousepan":
                this.cb.onPan(p.x - this.lastX, p.y - this.lastY);
                this.lastX = p.x;
                this.lastY = p.y;
                break;
            case "box":
                this.cb.onBoxMove(p.x, p.y);
                this.lastX = p.x;
                this.lastY = p.y;
                break;
            case "multi": {
                const [a, b] = [...this.pointers.values()];
                if (!a || !b)
                    break;
                const cx = (a.x + b.x) / 2;
                const cy = (a.y + b.y) / 2;
                const dist = Math.hypot(a.x - b.x, a.y - b.y);
                this.cb.onPan(cx - this.lastX, cy - this.lastY);
                if (!this.pinchActive && Math.abs(dist - this.pinchStartDist) > PINCH_ACTIVATE_PX)
                    this.pinchActive = true;
                if (this.pinchActive && this.pinchDist > 0 && dist > 0)
                    this.cb.onPinch(dist / this.pinchDist, cx, cy);
                this.lastX = cx;
                this.lastY = cy;
                this.pinchDist = dist;
                break;
            }
            case "idle":
                break;
        }
    }

    up(p, now) {
        if (p.pointerType === "mouse" && p.button === 2)
            return;
        if (!this.pointers.delete(p.id))
            return;

        switch (this.mode) {
            case "pending": {
                // never promoted: tap if quick, degenerate box if it was a long hold
                if (now - this.downTime >= HOLD_DELAY_MS) {
                    this.cb.onBoxStart(this.downX, this.downY);
                    this.cb.onBoxEnd(p.x, p.y, true);
                }
                else if (now - this.lastTapTime <= DOUBLE_TAP_MS &&
                    Math.hypot(p.x - this.lastTapX, p.y - this.lastTapY) <= DOUBLE_TAP_SLOP_PX) {
                    this.lastTapTime = -Infinity;
                    this.cb.onDoubleTap(p.x, p.y);
                }
                else {
                    this.lastTapTime = now;
                    this.lastTapX = p.x;
                    this.lastTapY = p.y;
                    this.cb.onTap(p.x, p.y, this.downType);
                }
                this.mode = "idle";
                break;
            }
            case "box":
                this.cb.onBoxEnd(p.x, p.y, true);
                this.mode = "idle";
                break;
            case "pan":
            case "mousepan":
                this.cb.onPanEnd?.();
                this.mode = "idle";
                break;
            case "multi":
                if (this.pointers.size < 2) {
                    this.cb.onPanEnd?.();
                    this.mode = "idle";
                }
                break;
            case "idle":
                break;
        }
        if (this.pointers.size === 0 && this.mode !== "idle")
            this.mode = "idle";
    }

    cancel(p) {
        if (!this.pointers.delete(p.id))
            return;
        if (this.mode === "box")
            this.cb.onBoxEnd(this.lastX, this.lastY, false);
        this.mode = this.pointers.size >= 2 ? "multi" : "idle";
    }

    /**
     * Forget pointers whose fingers left without a word (see strandedPointers):
     * one still counted as down would make every later touch the second finger
     * of a pinch (pan and zoom only; no tap, no box) for the rest of the match.
     * Nothing fires for them (a box they drew ends unreleased); the pointers
     * still down start afresh where they are, as if they had just landed.
     */
    forget(ids, now) {
        let gone = false;
        for (const id of ids)
            gone = this.pointers.delete(id) || gone;
        if (!gone)
            return;
        if (this.mode === "box")
            this.cb.onBoxEnd(this.lastX, this.lastY, false);
        const rest = [...this.pointers.values()];
        this.pointers.clear();
        this.mode = "idle";
        for (const t of rest)
            this.down({ id: t.id, x: t.x, y: t.y, pointerType: t.type }, now);
    }

    /**
     * Let go of every pointer without firing anything (no tap, box or pan end):
     * something else just took the camera. Later moves and lifts of those
     * pointers are ignored; the next down starts afresh.
     */
    reset() {
        this.pointers.clear();
        this.mode = "idle";
        this.pinchActive = false;
        this.pinchDist = 0;
        this.lastTapTime = -Infinity;
    }

    wheel(deltaY, x, y) {
        this.cb.onWheel(deltaY, x, y);
    }

    /** Call every frame: fires the long-press box start while holding still. */
    tick(now) {
        if (this.mode === "pending" && this.downType !== "mouse" && now - this.downTime >= HOLD_DELAY_MS) {
            this.mode = "box";
            this.cb.onBoxStart(this.downX, this.downY);
            if (navigator.vibrate)
                navigator.vibrate(10);
        }
    }

    enterMulti() {
        if (this.mode === "box")
            this.cb.onBoxEnd(this.lastX, this.lastY, false);
        this.mode = "multi";
        const [a, b] = [...this.pointers.values()];
        if (a && b) {
            this.lastX = (a.x + b.x) / 2;
            this.lastY = (a.y + b.y) / 2;
            this.pinchDist = Math.hypot(a.x - b.x, a.y - b.y);
            this.pinchStartDist = this.pinchDist;
            this.pinchActive = false;
        }
    }
}
