// A controller on the game's own screen (or a TV's remote, whose arrows and OK Lamp's runtime gives as a pad): in the
// menus the stick or d-pad moves a highlight between the buttons and A presses one; in a match the stick moves a
// pointer that does what the mouse does (A clicks, held down it drags a box round units, RT gives an order where it
// points), the right stick and the screen's edges move the camera, and the shoulder buttons zoom. Every control is in
// CONTROLS, and the legend drawn from it names each button as the player's own controller does (lamp-game.js's glyph).
import { BUTTON, STICK, TRIGGER, glyph, input, onInput } from "../../lamp-game.js";

/** What each button does in a match, in the order the legend lists them. */
const CONTROLS = [
    { what: STICK.LEFT, says: "Point" },
    { what: BUTTON.A, says: "Select · hold to box", key: null },
    { what: TRIGGER.RT, says: "Order here", key: null },
    { what: BUTTON.B, says: "Cancel", key: "Escape" },
    { what: BUTTON.X, says: "Whole army", key: "q" },
    { what: BUTTON.Y, says: "Jump to alert", key: "j" },
    { what: STICK.RIGHT, says: "Move camera" },
    { what: BUTTON.LB, says: "Zoom out" },
    { what: BUTTON.RB, says: "Zoom in" },
    { what: BUTTON.MENU, says: "Pause", key: "p" },
    { what: BUTTON.VIEW, says: "Game speed", key: "." },
    { what: BUTTON.LEFT, says: "Squad 1", key: "1", code: "Digit1" },
    { what: BUTTON.UP, says: "Squad 2", key: "2", code: "Digit2" },
    { what: BUTTON.RIGHT, says: "Squad 3", key: "3", code: "Digit3" }
];

let cursor = null, legend = null, focused = null;
const at = { x: innerWidth / 2, y: innerHeight / 2 };
let holding = null, ordering = null, usedAt = -1, repeatAt = 0, lastDir = "";

/** Turns the controllers off while a match is played together: there each controller is a player of its own (party.js). */
export const pads = { off: false };

function key(k, code = "") {
    const ev = { key: k, code: code || (k.length === 1 ? `Key${k.toUpperCase()}` : k), bubbles: true, cancelable: true };
    window.dispatchEvent(new KeyboardEvent("keydown", ev));
    window.dispatchEvent(new KeyboardEvent("keyup", ev));
}

// The pointer, as the mouse would be: events at the element under it, so the map, the HUD and every sheet take it as
// they take a click.
function pointer(type, button = 0) {
    const target = document.elementFromPoint(at.x, at.y);
    if (!target)
        return null;
    const init = { clientX: at.x, clientY: at.y, pointerId: 41, pointerType: "mouse", isPrimary: true, button,
                   buttons: type === "pointerup" ? 0 : button === 2 ? 2 : 1, bubbles: true, cancelable: true, composed: true };
    target.dispatchEvent(new PointerEvent(type, init));
    if (type !== "pointermove")
        target.dispatchEvent(new MouseEvent(type === "pointerdown" ? "mousedown" : "mouseup", init));
    return target;
}

function showCursor() {
    if (!cursor) {
        cursor = document.createElement("div");
        cursor.className = "padcursor";
        cursor.innerHTML = `<svg viewBox="0 0 24 24" width="30" height="30"><path d="M3 2l7 19 2.6-7.6L20 11z" fill="#fff" stroke="#0a1220" stroke-width="1.6" stroke-linejoin="round"/></svg>`;
        document.body.append(cursor);
    }
    cursor.hidden = false;
    cursor.style.transform = `translate(${at.x - 4}px, ${at.y - 3}px)`;
}

function drawLegend() {
    if (!legend) {
        legend = document.createElement("div");
        legend.className = "padlegend";
        document.body.append(legend);
    }
    legend.replaceChildren(...CONTROLS.slice(0, 7).map((c) => {
        const row = document.createElement("span");
        const g = glyph(c.what);
        if (g)
            row.append(g, " " + c.says);
        return row;
    }).filter((row) => row.childNodes.length));
}

// The menus: what can be pressed, inside the sheet in front when one is open.
function pressables() {
    const sheets = [...document.querySelectorAll(".sheet-wrap, .party, .screen")].filter((el) => el.offsetParent || el === document.body);
    const scope = sheets.length ? sheets[sheets.length - 1] : document;
    return [...scope.querySelectorAll("button, .mapcard, input, [data-focus]")]
        .filter((el) => !el.disabled && !el.hidden && el.getClientRects().length && getComputedStyle(el).visibility !== "hidden");
}

function focus(el) {
    focused?.classList.remove("padfocus");
    focused = el;
    if (!el)
        return;
    el.classList.add("padfocus");
    el.scrollIntoView({ block: "nearest", inline: "nearest" });
}

/** The nearest pressable from the highlighted one in a direction, going by the gap along it and twice the gap across. */
function step(dir) {
    const all = pressables();
    if (!focused || !all.includes(focused))
        return focus(all.find((el) => el.id === "play") ?? all[0] ?? null);
    const from = focused.getBoundingClientRect(), fx = from.left + from.width / 2, fy = from.top + from.height / 2;
    let best = null, bestScore = Infinity;
    for (const el of all) {
        if (el === focused)
            continue;
        const r = el.getBoundingClientRect(), dx = r.left + r.width / 2 - fx, dy = r.top + r.height / 2 - fy;
        const along = dir === "left" ? -dx : dir === "right" ? dx : dir === "up" ? -dy : dy;
        const across = dir === "left" || dir === "right" ? Math.abs(dy) : Math.abs(dx);
        if (along <= 4)
            continue;
        const score = along + across * 2;
        if (score < bestScore)
            [best, bestScore] = [el, score];
    }
    if (best)
        focus(best);
}

function direction(pad) {
    const d = pad.down;
    if (d & BUTTON.LEFT || pad.lx < -0.6) return "left";
    if (d & BUTTON.RIGHT || pad.lx > 0.6) return "right";
    if (d & BUTTON.UP || pad.ly > 0.6) return "up";
    if (d & BUTTON.DOWN || pad.ly < -0.6) return "down";
    return "";
}

/** All the pads as one: whoever picks one up is the player on the screen. */
function merged(pads) {
    const out = { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0, down: 0, pressed: 0, released: 0 };
    for (const p of pads) {
        if (!p.connected)
            continue;
        out.down |= p.down; out.pressed |= p.pressed; out.released |= p.released;
        for (const a of ["lx", "ly", "rx", "ry", "lt", "rt"])
            if (Math.abs(p[a]) > Math.abs(out[a]))
                out[a] = p[a];
    }
    return out;
}

function menuFrame(pad, time) {
    const dir = direction(pad);
    if (dir && (dir !== lastDir || time >= repeatAt)) {
        repeatAt = time + (dir === lastDir ? 0.12 : 0.4);
        step(dir);
    }
    lastDir = dir;
    if (pad.pressed & BUTTON.A) {
        if (!focused || !pressables().includes(focused))
            step("down");
        else if (focused.tagName === "INPUT")
            focused.focus();
        else
            focused.click();
    }
    if (pad.pressed & BUTTON.B) {
        const close = pressables().find((el) => el.matches(".sheet-close, #cancel, .op-back, [data-close]"));
        if (close)
            close.click();
        else
            key("Escape");
    }
}

function matchFrame(pad, f, scene) {
    if (focused)
        focus(null);
    const scale = Math.max(0.6, innerHeight / 900);
    // Fine near the middle of the stick, fast at its edge.
    const speed = 1300 * scale * f.dt;
    const mx = Math.sign(pad.lx) * pad.lx * pad.lx, my = Math.sign(pad.ly) * pad.ly * pad.ly;
    at.x = Math.max(0, Math.min(innerWidth - 1, at.x + mx * speed));
    at.y = Math.max(0, Math.min(innerHeight - 1, at.y - my * speed));
    const moved = mx || my;
    if (moved || pad.pressed) {
        showCursor();
        if (!legend)
            drawLegend();
    }
    if (moved)
        pointer("pointermove");
    // The camera: the right stick, or the pointer pushed against an edge of the screen.
    let px = pad.rx, py = -pad.ry;
    const edge = 6;
    if (at.x <= edge && pad.lx < 0) px = pad.lx;
    if (at.x >= innerWidth - 1 - edge && pad.lx > 0) px = pad.lx;
    if (at.y <= edge && pad.ly > 0) py = -pad.ly;
    if (at.y >= innerHeight - 1 - edge && pad.ly < 0) py = -pad.ly;
    if (px || py)
        scene.nudgeCamera(px * 900 * scale * f.dt, py * 900 * scale * f.dt);
    if (pad.pressed & BUTTON.LB)
        scene.zoomBy(1 / 1.3);
    if (pad.pressed & BUTTON.RB)
        scene.zoomBy(1.3);
    // A is the mouse's button: down, moved (a box), up; a press shorter than a frame is still a click.
    if (pad.pressed & BUTTON.A)
        holding = pointer("pointerdown");
    if (holding && (pad.released & BUTTON.A || !(pad.down & BUTTON.A))) {
        const target = pointer("pointerup");
        if (target && (target === holding || holding.contains(target) || target.contains(holding)))
            target.dispatchEvent(new MouseEvent("click", { clientX: at.x, clientY: at.y, bubbles: true, cancelable: true }));
        holding = null;
    }
    // RT is the right button: an order there that keeps the selection.
    const rt = pad.rt > 0.5;
    if (rt && !ordering) {
        ordering = true;
        pointer("pointerdown", 2);
        pointer("pointerup", 2);
    }
    else if (!rt)
        ordering = false;
    for (const c of CONTROLS)
        if (c.key && typeof c.what === "number" && pad.pressed & c.what)
            key(c.key, c.code);
}

/** Each frame of Lamp's runtime, with its pads; `scene` is the match being played, or null in the menus. */
export function frame(f, scene) {
    if (pads.off) {
        if (cursor) cursor.hidden = true;
        return;
    }
    const pad = merged(f.pads);
    const used = pad.down || Math.abs(pad.lx) > 0.3 || Math.abs(pad.ly) > 0.3 || Math.abs(pad.rx) > 0.3 || Math.abs(pad.ry) > 0.3 || pad.rt > 0.3;
    if (used)
        usedAt = f.time;
    const playing = input().kind === "controller" && usedAt >= 0;
    document.body.classList.toggle("onpad", playing);
    if (!playing) {
        if (cursor) cursor.hidden = true;
        focus(null);
        return;
    }
    if (scene && !scene.over)
        matchFrame(pad, f, scene);
    else {
        if (cursor) cursor.hidden = true;
        menuFrame(pad, f.time);
    }
}

// The legend follows the controller in the player's hands (an Xbox's letters, a PlayStation's shapes).
onInput(() => { if (legend || input().kind === "controller") drawLegend(); });
