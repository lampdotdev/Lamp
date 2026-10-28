// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

/** Edge marker diameter and the gap kept to the playfield border, CSS px. */
export const MARKER = { size: 46, margin: 8 };

const rectOf = (el, pad = 0) => {
    const r = el.getBoundingClientRect();
    return { x0: r.left - pad, y0: r.top - pad, x1: r.right + pad, y1: r.bottom + pad };
};

/** HUD widgets the edge arrows steer around (other features can opt in with data-edge-avoid). */
const AVOID = [
    ".minimap-wrap", ".tl", ".topbar", ".zoombtns", "#toasts > .toast", ".chips > .chip", ".selpanel",
    ".banner.in", "#card", "#versus", ".bmeter", "[data-edge-avoid]"
].join(",");

/** Which side of its marker an arrow's label goes: toward the battlefield, clear of HUD widgets. */
function labelSide(a, text, avoid) {
    const W = window.innerWidth;
    const H = window.innerHeight;
    const pref = a.x < W * 0.33 ? "r" : a.x > W * 0.67 ? "l" : a.y < H / 2 ? "b" : "t";
    const w = text.length * 7 + 14;
    const hh = 9;
    const half = MARKER.size / 2;
    const rect = (s) => s === "r" ? { x0: a.x + half - 2, y0: a.y - hh, x1: a.x + half - 2 + w, y1: a.y + hh }
        : s === "l" ? { x0: a.x - half + 2 - w, y0: a.y - hh, x1: a.x - half + 2, y1: a.y + hh }
            : s === "b" ? { x0: a.x - w / 2, y0: a.y + half - 2, x1: a.x + w / 2, y1: a.y + half + 2 * hh }
                : { x0: a.x - w / 2, y0: a.y - half - 2 * hh, x1: a.x + w / 2, y1: a.y - half + 2 };
    const clear = (s) => {
        const r = rect(s);
        if (r.x0 < 0 || r.x1 > W || r.y0 < 0 || r.y1 > H)
            return false;
        // (ignore a widget the marker itself sits on)
        return !avoid.some((o) => !(a.x >= o.x0 && a.x <= o.x1 && a.y >= o.y0 && a.y <= o.y1) && r.x0 < o.x1 && r.x1 > o.x0 && r.y0 < o.y1 && r.y1 > o.y0);
    };
    for (const s of [pref, "b", "t", "l", "r"])
        if (clear(s))
            return s;
    return pref;
}

export function mountAwareness(root, h) {
    const shield = (el) => el.addEventListener("pointerdown", (e) => e.stopPropagation());

    // ------------------------------------------------------------ speed ---
    const clock = root.querySelector("#clock");
    const speed = document.createElement("button");
    speed.id = "speed";
    speed.className = "speed";
    speed.title = "Game speed (.) — hold the clock to fast-forward";
    speed.textContent = "1×";
    // the clock and its speed chip share one row (pills added next to the clock land in it too)
    const tempo = document.createElement("div");
    tempo.className = "tempo";
    if (clock) {
        clock.replaceWith(tempo);
        tempo.appendChild(clock);
    }
    if (!h.fixedSpeed)
        tempo.appendChild(speed);
    speed.addEventListener("click", () => h.onCycleSpeed());
    shield(speed);
    let pid = null;
    if (clock && !h.fixedSpeed) {
        clock.classList.add("holdable");
        clock.title = "Hold to fast-forward (3×)";
        const release = () => {
            if (pid === null)
                return;
            pid = null;
            clock.classList.remove("held");
            h.onHold(false);
        };
        clock.addEventListener("pointerdown", (e) => {
            e.stopPropagation();
            e.preventDefault();
            pid = e.pointerId;
            try {
                clock.setPointerCapture(e.pointerId);
            }
            catch {
                /* synthetic events */
            }
            clock.classList.add("held");
            h.onHold(true);
        });
        clock.addEventListener("pointerup", release);
        clock.addEventListener("pointercancel", release);
        clock.addEventListener("lostpointercapture", release);
        clock.addEventListener("contextmenu", (e) => e.preventDefault());
    }

    // ------------------------------------------------------------ meter ---
    const meter = document.createElement("div");
    meter.className = "bmeter";
    meter.hidden = true;
    meter.innerHTML = `<span class="bm-side bm-own">${h.spectator ? "B" : "You"}</span><span class="bm-bar"><i class="bm-fill"></i><i class="bm-knob"></i></span><span class="bm-side bm-foe">${h.spectator ? "R" : "Foe"}</span><span class="bm-tp"></span>`;
    root.querySelector(".topbar")?.appendChild(meter);
    const fill = meter.querySelector(".bm-fill");
    const knob = meter.querySelector(".bm-knob");
    const tp = meter.querySelector(".bm-tp");
    let tpTimer = 0;

    // ------------------------------------------------------------ edges ---
    const edges = document.createElement("div");
    edges.className = "edges";
    root.appendChild(edges);
    const pool = new Map();
    const makeArrow = (key) => {
        const b = document.createElement("button");
        b.className = "edge";
        // a block arrow with a shaft: bare triangles and arrowheads read ambiguously at diagonals on a phone
        b.innerHTML = `<span class="ring"></span><svg class="chev" viewBox="-12 -12 24 24" aria-hidden="true"><path d="M-10 -4 L1 -4 L1 -10 L11 0 L1 10 L1 4 L-10 4 Z"/></svg><span class="el"></span>`;
        b.addEventListener("click", () => h.onArrow(b.dataset.key ?? key));
        shield(b);
        edges.appendChild(b);
        return b;
    };

    // ------------------------------------------------------------- jump ---
    const jump = document.createElement("button");
    jump.className = "zb jump";
    jump.title = "Jump to the action (J)";
    jump.innerHTML = `<span class="ji">⚡</span><span class="jdot" hidden></span>`;
    root.querySelector(".zoombtns")?.appendChild(jump);
    jump.addEventListener("click", () => h.onJump());
    shield(jump);
    const jdot = jump.querySelector(".jdot");

    // ----------------------------------------------------------- layout ---
    let cached = null;
    let cachedAt = 0;
    const onResize = () => (cached = null);
    window.addEventListener("resize", onResize);

    function layout() {
        const now = performance.now();
        if (cached && now - cachedAt < 300)
            return cached;
        const W = window.innerWidth;
        const H = window.innerHeight;
        const play = { x0: 0, y0: 0, x1: W, y1: H };
        const bar = root.querySelector(".buildbar");
        const bb = bar?.getBoundingClientRect();
        if (bb && bb.width > 0 && bb.height > 0) {
            if (bb.width >= W - 1)
                play.y1 = Math.min(play.y1, bb.top);
            else
                play.x1 = Math.min(play.x1, bb.left);
        }
        // the band of fixed widgets along the top
        let top = 0;
        for (const sel of [".tl", ".topbar"]) {
            const el = root.querySelector(sel);
            if (el)
                top = Math.max(top, el.getBoundingClientRect().bottom);
        }
        const m = MARKER.margin + MARKER.size / 2;
        const markers = { x0: play.x0 + m, y0: Math.max(play.y0 + m, top + 6 + MARKER.size / 2), x1: play.x1 - m, y1: play.y1 - m };
        const avoid = [];
        root.querySelectorAll(AVOID).forEach((el) => {
            if (el.hidden)
                return;
            const r = el.getBoundingClientRect();
            if (r.width > 0 && r.height > 0)
                avoid.push(rectOf(el, 4));
        });
        cached = { play, markers, avoid };
        cachedAt = now;
        return cached;
    }

    let lastSpeed = "";
    let lastMeter = "";
    let lastJump = "";

    return {
        setSpeed(value, base, held) {
            const key = `${value}|${base}|${held}`;
            if (key === lastSpeed)
                return;
            lastSpeed = key;
            speed.textContent = `${value}×`;
            speed.classList.toggle("fast", value > 1);
            speed.classList.toggle("held", held);
            clock?.classList.toggle("fast", value > 1);
        },
        cancelHold() {
            const id = pid;
            pid = null;
            clock?.classList.remove("held");
            if (id === null || !clock)
                return;
            try {
                clock.releasePointerCapture(id);
            }
            catch {
                /* already released */
            }
        },
        flashSpeed() {
            speed.classList.remove("drop");
            void speed.offsetWidth;
            speed.classList.add("drop");
        },
        setMeter(shown, share) {
            const pct = Math.round(Math.max(0.03, Math.min(0.97, share)) * 1000) / 10;
            const key = shown ? String(pct) : "off";
            if (key === lastMeter)
                return;
            const was = lastMeter;
            lastMeter = key;
            meter.hidden = !shown;
            if (!shown)
                return;
            if (was === "off" || was === "") {
                // replay the entrance
                meter.classList.remove("in");
                void meter.offsetWidth;
                meter.classList.add("in");
            }
            fill.style.width = `${pct}%`;
            knob.style.left = `${pct}%`;
            meter.classList.toggle("winning", share >= 0.6);
            meter.classList.toggle("losing", share <= 0.4);
        },
        turning(dir) {
            tp.textContent = "Turning point!";
            // spectators have no side: the swing is news, not good or bad
            tp.className = `bm-tp ${h.spectator ? "neutral" : dir}`;
            void tp.offsetWidth;
            tp.classList.add("show");
            window.clearTimeout(tpTimer);
            tpTimer = window.setTimeout(() => tp.classList.remove("show"), 1800);
        },
        setArrows(list) {
            const keep = new Set(list.map((a) => a.key));
            for (const [k, el] of pool)
                if (!keep.has(k)) {
                    el.remove();
                    pool.delete(k);
                }
            for (const a of list) {
                let el = pool.get(a.key);
                if (!el) {
                    el = makeArrow(a.key);
                    el.dataset.key = a.key;
                    pool.set(a.key, el);
                }
                if (el.dataset.kind !== a.kind) {
                    el.dataset.kind = a.kind;
                    el.className = `edge ${a.kind}`;
                }
                const label = el.querySelector(".el");
                if (label.textContent !== a.label)
                    label.textContent = a.label;
                // the label sits on the battlefield side of the marker, unless a HUD widget is there
                const side = labelSide(a, label.textContent ?? "", layout().avoid);
                if (el.dataset.side !== side)
                    el.dataset.side = side;
                // only touch the DOM when something moved (this runs every frame)
                const tr = `translate(${Math.round(a.x - MARKER.size / 2)}px, ${Math.round(a.y - MARKER.size / 2)}px) scale(${a.scale.toFixed(2)})`;
                if (el.style.transform !== tr)
                    el.style.transform = tr;
                const rot = `rotate(${a.angle.toFixed(2)}rad)`;
                const chev = el.querySelector(".chev");
                if (chev.style.transform !== rot)
                    chev.style.transform = rot;
            }
        },
        setJump(count, threat) {
            const key = `${count > 0}|${threat}`;
            if (key === lastJump)
                return;
            lastJump = key;
            jump.classList.toggle("idle", count === 0);
            jump.classList.toggle("threat", threat);
            jdot.hidden = !threat;
        },
        jumpNothing() {
            jump.classList.remove("nope");
            void jump.offsetWidth;
            jump.classList.add("nope");
        },
        layout,
        destroy() {
            window.removeEventListener("resize", onResize);
            window.clearTimeout(tpTimer);
            speed.remove();
            meter.remove();
            tempo.remove();
            edges.remove();
            jump.remove();
        }
    };
}
