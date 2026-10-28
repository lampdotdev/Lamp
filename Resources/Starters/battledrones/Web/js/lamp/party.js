// Playing together on one screen (the TV, or the Mac): each person commands a side of their own. Phones join from a
// QR code with Lamp's phone controllers (Lamp.controllers here, the page in Phone/ on theirs) and get the whole
// command table on their phone: the battlefield as their side sees it, to select and order on with a finger, and the
// build, train and calldown buttons. A controller, or the mouse, takes a seat too, with the same table drawn in a
// corner of the screen. The screen shows the whole battle with the camera following the action; sides nobody took
// go to the computer.
//
// Each seat has the game's own Controller for its side (game/controller.js), so a tap from a phone means what a tap
// on the map means in single player: select, move, attack, harvest, board, drop. The match asks each seat for its
// orders every tick (`drain`, from GameScene.multiTick).
import { BUTTON, STICK, TRIGGER, glyph, log } from "../../lamp-game.js";
import { Controller, hitTest } from "../game/controller.js";
import { BUILDINGS, UNITS } from "../sim/balance.js";
import { buildingBlocker, unitBlocker } from "../sim/economy.js";
import { isVisible } from "../sim/fog.js";
import { unitCost } from "../sim/goliath.js";
import { unitSeenBy } from "../sim/infantry.js";
import { mapById } from "../sim/maps.js";
import { suggestPlacement } from "../sim/placement.js";
import { POWER_KINDS, POWER_NAMES, powerStatus } from "../sim/powers.js";
import { buildingCenter, hqOf } from "../sim/world.js";
import { pickProducer } from "../game/controller.js";
import { mapThumbUrl } from "../game/assets.js";
import { SIDE_CSS, SIDE_NAME } from "../game/side-style.js";
import { pads } from "./pads.js";
import qrcode from "./../lib/qrcode.js";

const SIDES = ["blue", "red", "green", "purple"];
/** How often each phone hears its side's state, in seconds. */
const STATE_EVERY = 0.25;
/** The corners of the screen a controller's or the mouse's table takes, seat by seat. */
const CORNERS = ["bl", "br", "tl", "tr"];

const controllers = () => window.Lamp && window.Lamp.controllers;
const esc = (s) => String(s).replace(/[&<>"]/g, (ch) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[ch]);

// ------------------------------------------------------------------ seats ---

/** One side played by a person: a phone (`player`, Lamp.controllers' number), a controller (`pad`) or the mouse. */
class Seat {
    constructor(side, who) {
        this.side = side;
        this.who = who;
        this.ctrl = null;
        this.world = null;
        /** A calldown waiting for its target: the next tap fires it there. */
        this.arming = null;
    }

    get label() {
        return this.who.name || (this.who.kind === "pad" ? `Controller ${this.who.pad + 1}` : this.who.kind === "mouse" ? "Mouse" : "Phone");
    }

    get icon() {
        return this.who.kind === "phone" ? "📱" : this.who.kind === "pad" ? "🎮" : "🖱️";
    }

    begin(world) {
        this.world = world;
        this.ctrl = new Controller(world, this.side);
    }

    /** This tick's orders: what the seat's person asked for, and a finished building put down where it fits best. */
    drain() {
        const w = this.world, pending = w.factions[this.side].pending;
        if (pending?.ready && !this.placed) {
            const hq = hqOf(w, this.side);
            const at = suggestPlacement(w, this.side, pending.kind, hq ? buildingCenter(hq) : undefined);
            if (at) {
                this.ctrl.enqueue({ type: "placeBuilding", faction: this.side, tx: at.tx, ty: at.ty });
                this.placed = true;
            }
        }
        if (!pending)
            this.placed = false;
        return this.ctrl.drainCommands();
    }

    canSee(id) {
        const w = this.world, u = w.units.get(id);
        if (u)
            return unitSeenBy(w, this.side, u);
        const b = w.buildings.get(id);
        if (!b)
            return false;
        const c = buildingCenter(b);
        return b.faction === this.side || isVisible(w, this.side, Math.floor(c.x), Math.floor(c.y));
    }

    tap(x, y) {
        if (this.arming) {
            const power = this.arming;
            this.arming = null;
            this.ctrl.enqueue({ type: "calldown", faction: this.side, power, x, y });
            return `${POWER_NAMES[power] ?? power} on its way`;
        }
        this.ctrl.tapWorld(x, y, hitTest(this.world, x, y, 1.2, (id) => this.canSee(id), this.side));
        const tip = this.ctrl.tip;
        this.ctrl.tip = null;
        return tip;
    }

    box(x0, y0, x1, y1) {
        const [ax, bx] = [Math.min(x0, x1), Math.max(x0, x1)], [ay, by] = [Math.min(y0, y1), Math.max(y0, y1)];
        const inBox = [...this.world.units.values()].filter((u) => u.faction === this.side && u.x >= ax && u.x <= bx && u.y >= ay && u.y <= by);
        const army = inBox.filter((u) => u.kind !== "harvester");
        const ids = (army.length ? army : inBox).map((u) => u.id);
        if (ids.length)
            this.ctrl.selectUnits(ids);
        else
            this.ctrl.clearSelection();
    }

    command(c) {
        const ctrl = this.ctrl;
        if (c === "army") ctrl.selectArmy();
        else if (c === "idle") ctrl.selectUnits(ctrl.idleArmy());
        else if (c === "harvesters") ctrl.selectUnits([...this.world.units.values()].filter((u) => u.faction === this.side && u.kind === "harvester").map((u) => u.id));
        else if (c === "stop") ctrl.stopSelected();
        else if (c === "clear") { ctrl.clearSelection(); this.arming = null; }
        else if (c === "unload") ctrl.unloadSelected();
        else if (c === "anchor") ctrl.toggleAnchor();
    }

    /** Buy what the shop item says: a building (put down once it's built), a unit, or a calldown to aim. */
    buy(item) {
        const w = this.world, side = this.side;
        if (item.type === "build") {
            const why = buildingBlocker(w, side, item.kind);
            if (why) return why;
            if (w.factions[side].pending) return "Already building";
            this.ctrl.enqueue({ type: "startBuilding", faction: side, building: item.kind });
            return `Building a ${BUILDINGS[item.kind].name}`;
        }
        if (item.type === "train") {
            const why = unitBlocker(w, side, item.kind);
            if (why) return why;
            const at = pickProducer(w, item.kind, this.ctrl.selectedUnits, this.ctrl.view(), side);
            if (!at) return "Every queue is full";
            this.ctrl.enqueue({ type: "produce", faction: side, buildingId: at.id, unit: item.kind });
            return `Training a ${UNITS[item.kind].name}`;
        }
        if (item.type === "power") {
            const st = powerStatus(w, side, item.kind);
            if (!st.ready) return st.locked ? "Not yet" : st.cooldown ? "Recharging" : "Not charged";
            this.arming = item.kind;
            return `Tap where the ${POWER_NAMES[item.kind] ?? item.kind} goes`;
        }
        return null;
    }

    /** What the side can buy now, for the phone's buttons and a corner table's shop. */
    shop() {
        const w = this.world, side = this.side, scrap = w.factions[side].scrap, items = [];
        const pending = w.factions[side].pending;
        for (const kind of Object.keys(BUILDINGS)) {
            if (kind === "hq") continue;
            const why = buildingBlocker(w, side, kind);
            if (why?.startsWith("Disabled")) continue;
            const cost = BUILDINGS[kind].cost;
            items.push({ type: "build", kind, name: BUILDINGS[kind].name, cost, ok: !why && !pending && scrap >= cost, why: why ?? (pending ? "Building" : null) });
        }
        for (const kind of Object.keys(UNITS)) {
            const why = unitBlocker(w, side, kind);
            if (why?.startsWith("Disabled")) continue;
            const cost = unitCost(w, side, kind);
            items.push({ type: "train", kind, name: UNITS[kind].name, cost, ok: !why && scrap >= cost, why });
        }
        for (const kind of POWER_KINDS) {
            const st = powerStatus(w, side, kind);
            if (st.locked > 0 && kind !== "hammer") continue;
            items.push({ type: "power", kind, name: POWER_NAMES[kind] ?? kind, cost: 0, ok: st.ready, charge: Math.round(st.charge * 100), why: st.ready ? null : "Charging" });
        }
        return items;
    }

    /** The side as it sees the battle, small enough for a phone's message (16 KB): whole tiles to one decimal. */
    state() {
        const w = this.world, side = this.side, f = w.factions[side], r = (v) => Math.round(v * 10) / 10;
        const own = [], foes = [], buildings = [], sel = [...this.ctrl.selectedUnits];
        for (const u of w.units.values()) {
            if (u.faction === side)
                own.push([u.id, r(u.x), r(u.y), UNITS[u.kind].domain === "air" ? 1 : 0, u.kind === "harvester" ? 1 : 0]);
            else if (unitSeenBy(w, side, u))
                foes.push([r(u.x), r(u.y), u.faction]);
        }
        for (const b of w.buildings.values()) {
            const c = buildingCenter(b), size = BUILDINGS[b.kind].size;
            if (b.faction === side || isVisible(w, side, Math.floor(c.x), Math.floor(c.y)))
                buildings.push([r(b.tx), r(b.ty), size, b.faction, b.kind === "hq" ? 1 : 0]);
        }
        const pending = f.pending ? { kind: f.pending.kind, name: BUILDINGS[f.pending.kind].name, ready: !!f.pending.ready,
            left: Math.ceil(f.pending.remaining / 10) } : null;
        return { t: "state", side, scrap: Math.floor(f.scrap), tick: w.tick, size: w.width, own, foes, buildings, sel,
                 arming: this.arming, pending, shop: this.shop(), out: !!w.out?.[side], winner: w.winner ?? null };
    }
}

// --------------------------------------------------------- the party itself ---

const party = {
    open: false,
    /** side → Seat, while the lobby or a match has seats. */
    seats: new Map(),
    /** Phones by their player number: their id, name and side. */
    phones: new Map(),
    link: null,
    lobby: null,
    scene: null,
    mapId: null,
    sentAt: 0,
    sideOrder: SIDES.slice(0, 2),
    padSeat: new Map(),
    panels: new Map(),
    /** The table a controller's cursor is on: its corner panel's map, in tiles. */
    cursors: new Map(),
    started: false
};

/** The seats of the coming match for GameScene, or null when it isn't played together. */
export function seatsFor() {
    return party.started ? party.seats : null;
}

function sidesOf(mapId) {
    return mapById(mapId).players === 4 ? SIDES : SIDES.slice(0, 2);
}

function freeSide() {
    return party.sideOrder.find((s) => !party.seats.has(s)) ?? null;
}

function sit(who, side = freeSide()) {
    if (!side)
        return null;
    for (const [s, seat] of party.seats)
        if (sameWho(seat.who, who))
            party.seats.delete(s);
    const seat = new Seat(side, who);
    party.seats.set(side, seat);
    drawLobby();
    tellPhones();
    return seat;
}

const sameWho = (a, b) => a.kind === b.kind && (a.kind === "phone" ? a.id === b.id : a.kind === "pad" ? a.pad === b.pad : true);

function stand(who) {
    for (const [s, seat] of party.seats)
        if (sameWho(seat.who, who))
            party.seats.delete(s);
    drawLobby();
    tellPhones();
}

function send(player, data) {
    const c = controllers();
    if (c)
        c.send(player, data);
}

function seatOfPhone(player) {
    const phone = party.phones.get(player);
    if (!phone)
        return null;
    return [...party.seats.values()].find((s) => s.who.kind === "phone" && s.who.id === phone.id) ?? null;
}

function tellPhones() {
    for (const [player, phone] of party.phones) {
        const mine = seatOfPhone(player);
        send(player, {
            t: "lobby", started: party.started, map: mapById(party.mapId).name,
            you: mine ? mine.side : null, name: phone.name,
            seats: party.sideOrder.map((side) => {
                const seat = party.seats.get(side);
                return { side, name: SIDE_NAME[side], color: SIDE_CSS[side], who: seat ? seat.label : null, icon: seat ? seat.icon : null };
            })
        });
    }
}

// ------------------------------------------------------------ phones ---

let listening = false;
function listen() {
    const c = controllers();
    if (!c || listening)
        return;
    listening = true;
    c.onLink((url) => { party.link = url; drawLobby(); });
    c.onError((message) => { party.error = message; drawLobby(); });
    c.onJoin((player) => { party.phones.set(player, { id: `player-${player}`, name: "" }); });
    c.onLeave((player) => {
        party.phones.delete(player);
        drawLobby();
    });
    c.onMessage((player, m) => {
        if (!m || typeof m !== "object")
            return;
        if (m.t === "hi") {
            const id = typeof m.id === "string" ? m.id.slice(0, 40) : `player-${player}`;
            const name = typeof m.name === "string" ? m.name.trim().slice(0, 16) : "";
            party.phones.set(player, { id, name });
            const seat = [...party.seats.values()].find((s) => s.who.kind === "phone" && s.who.id === id);
            if (seat)
                seat.who.name = name || seat.who.name;
            // A phone that comes back to a match finds its side again; a new one sits where there's room.
            else if (!party.started && party.open)
                sit({ kind: "phone", id, name });
            drawLobby();
            tellPhones();
            if (party.started && seat)
                sendMap(player);
            return;
        }
        const seat = seatOfPhone(player);
        if (m.t === "seat" && !party.started && SIDES.includes(m.side) && !party.seats.has(m.side)) {
            const phone = party.phones.get(player);
            sit({ kind: "phone", id: phone.id, name: phone.name }, m.side);
        }
        else if (m.t === "leave" && !party.started) {
            const phone = party.phones.get(player);
            if (phone)
                stand({ kind: "phone", id: phone.id });
        }
        else if (m.t === "start" && !party.started)
            start();
        if (!party.started || !seat || !seat.ctrl)
            return;
        let note = null;
        if (m.t === "tap" && Number.isFinite(m.x) && Number.isFinite(m.y))
            note = seat.tap(m.x, m.y);
        else if (m.t === "box" && [m.x0, m.y0, m.x1, m.y1].every(Number.isFinite))
            seat.box(m.x0, m.y0, m.x1, m.y1);
        else if (m.t === "cmd" && typeof m.c === "string")
            seat.command(m.c);
        else if (m.t === "buy" && m.item && typeof m.item.kind === "string")
            note = seat.buy(m.item);
        else if (m.t === "look" && Number.isFinite(m.x) && Number.isFinite(m.y))
            party.scene?.lookAt(m.x, m.y);
        if (note)
            send(player, { t: "note", text: note });
        sendState(player, seat);
    });
}

async function sendMap(player) {
    const c = controllers();
    if (!c || !party.scene)
        return;
    // The map's picture once a match, as a file: too big for a message.
    try {
        const img = new Image();
        img.src = mapThumbUrl(party.scene.world.mapId);
        await img.decode();
        const cv = document.createElement("canvas");
        cv.width = cv.height = 256;
        cv.getContext("2d").drawImage(img, 0, 0, 256, 256);
        const blob = await new Promise((resolve) => cv.toBlob(resolve, "image/png"));
        if (blob)
            c.sendFile(player, blob, { name: "map.png", type: "image/png" });
    }
    catch (e) {
        log(`Couldn't send the map's picture: ${e && e.message || e}`);
    }
}

function sendState(player, seat) {
    send(player, seat.state());
}

// ------------------------------------------------------------- the lobby ---

/** Opens the lobby over the menu for the map picked there; `begin(seats)` starts the match. */
export function openLobby(host, mapId, begin) {
    party.open = true;
    party.mapId = mapId;
    party.sideOrder = sidesOf(mapId);
    party.begin = begin;
    party.seats.clear();
    pads.off = true;
    const c = controllers();
    if (c) {
        listen();
        c.start();
    }
    const el = document.createElement("div");
    el.className = "party";
    el.id = "party";
    host.append(el);
    party.lobby = el;
    el.addEventListener("click", (e) => {
        const t = e.target.closest("[data-act]");
        if (!t)
            return;
        const act = t.dataset.act;
        if (act === "start") start();
        else if (act === "back") closeLobby();
        else if (act === "mouse") sit({ kind: "mouse", name: "" }, t.dataset.side);
        else if (act === "stand") party.seats.delete(t.dataset.side), drawLobby(), tellPhones();
    });
    drawLobby();
    tellPhones();
}

function closeLobby() {
    party.open = false;
    party.lobby?.remove();
    party.lobby = null;
    party.seats.clear();
    pads.off = false;
    tellPhones();
}

function qrSvg(text) {
    const qr = qrcode(0, "M");
    qr.addData(text);
    qr.make();
    return qr.createSvgTag({ cellSize: 6, margin: 2, scalable: true });
}

function drawLobby() {
    const el = party.lobby;
    if (!el)
        return;
    const c = controllers();
    const humans = [...party.seats.values()].length;
    const join = !c
        ? `<p class="party-note">Phones join where Lamp hosts the game for them: on the Mac or a TV it's opened on. Here, pick up a controller.</p>`
        : party.link
            ? `<div class="party-qr">${qrSvg(party.link)}</div><p class="party-note">Scan with a phone's camera to join on this Wi-Fi.</p>`
            : `<div class="party-qr wait">…</div><p class="party-note">${esc(party.error || "Getting the link for phones…")}</p>`;
    el.innerHTML = `
      <div class="party-box">
        <h2>Play together</h2>
        <p class="party-map">${esc(mapById(party.mapId).name)} · ${party.sideOrder.length} sides</p>
        <div class="party-cols">
          <div class="party-join">${join}
            <p class="party-note">Or press <b class="party-a"></b> on a controller.</p>
          </div>
          <div class="party-seats">${party.sideOrder.map((side) => {
              const seat = party.seats.get(side);
              return `<div class="party-seat" style="--side:${SIDE_CSS[side]}">
                <span class="dot"></span><b>${SIDE_NAME[side]}</b>
                <span class="who">${seat ? `${seat.icon} ${esc(seat.label)}` : "Computer"}</span>
                ${seat ? `<button class="cta alt small" data-act="stand" data-side="${side}">✕</button>` : `<button class="cta alt small" data-act="mouse" data-side="${side}">🖱️ Sit here</button>`}
              </div>`;
          }).join("")}</div>
        </div>
        <div class="row">
          <button class="cta alt" data-act="back">Back</button>
          <button class="cta big" data-act="start" ${humans ? "" : "disabled"}>▶ Start battle</button>
        </div>
      </div>`;
    // The button named as a controller has it, whatever is in the player's hands now.
    const a = glyph(BUTTON.A, { kind: "controller", family: "" });
    if (a)
        el.querySelector(".party-a").replaceWith(a);
}

function start() {
    if (party.started || !party.seats.size)
        return;
    party.started = true;
    party.lobby?.remove();
    party.lobby = null;
    tellPhones();
    party.begin(party.seats);
}

// --------------------------------------------------------------- the match ---

/** The match played together has begun: every seat gets its side's Controller, and the screen its tables. */
export function matchStarted(scene) {
    if (!party.started)
        return;
    party.scene = scene;
    let corner = 0;
    for (const seat of party.seats.values()) {
        seat.begin(scene.world);
        if (seat.who.kind !== "phone")
            party.panels.set(seat.side, makePanel(seat, CORNERS[corner++ % CORNERS.length]));
    }
    for (const player of party.phones.keys())
        sendMap(player);
    tellPhones();
}

/** Each frame of Lamp's runtime: controllers' seats in the lobby and in the match, and the phones' states. */
export function frame(f) {
    if (!party.open)
        return;
    // In the lobby, A on a controller takes a seat, B gives it up, and Menu starts the battle.
    if (!party.started) {
        f.pads.forEach((pad, i) => {
            if (!pad.connected) return;
            if (pad.pressed & BUTTON.A) sit({ kind: "pad", pad: i, name: "" });
            if (pad.pressed & BUTTON.B) stand({ kind: "pad", pad: i });
            if (pad.pressed & BUTTON.MENU) start();
        });
        return;
    }
    for (const seat of party.seats.values()) {
        seat.ctrl?.prune();
        if (seat.who.kind === "pad")
            padFrame(seat, f.pads[seat.who.pad], f);
    }
    party.sentAt -= f.dt;
    if (party.sentAt <= 0) {
        party.sentAt = STATE_EVERY;
        for (const player of party.phones.keys()) {
            const seat = seatOfPhone(player);
            if (seat?.ctrl)
                sendState(player, seat);
        }
        for (const [side, panel] of party.panels)
            panel.draw(party.seats.get(side));
    }
}

/** The match is over, or left: the phones are told, and the corner tables go. */
export function matchEnded() {
    for (const panel of party.panels.values())
        panel.el.remove();
    party.panels.clear();
}

// ----------------------------------------- a controller's or the mouse's table ---

function makePanel(seat, corner) {
    const el = document.createElement("div");
    el.className = `party-panel ${corner}`;
    el.style.setProperty("--side", SIDE_CSS[seat.side]);
    el.innerHTML = `<div class="pp-head"><span class="dot"></span><b>${esc(seat.label)}</b><span class="pp-scrap"></span></div>
      <div class="pp-map"><canvas width="240" height="240"></canvas><div class="pp-cursor"></div></div>
      <div class="pp-shop"><span class="pp-prev"></span><span class="pp-item"></span><span class="pp-next"></span></div>
      <div class="pp-note"></div><div class="pp-keys"></div>`;
    document.getElementById("hud").append(el);
    const canvas = el.querySelector("canvas"), ctx = canvas.getContext("2d");
    const thumb = new Image();
    thumb.src = mapThumbUrl(seat.world.mapId);
    const panel = { el, slot: 0, cursor: { x: seat.world.width / 2, y: seat.world.height / 2 }, box: null, noteAt: 0 };
    // The mouse plays on the same table: a click is a tap, a drag a box.
    if (seat.who.kind === "mouse") {
        let down = null;
        const tile = (e) => { const r = canvas.getBoundingClientRect(); return { x: (e.clientX - r.left) / r.width * seat.world.width, y: (e.clientY - r.top) / r.height * seat.world.height }; };
        canvas.addEventListener("pointerdown", (e) => { e.stopPropagation(); down = tile(e); });
        canvas.addEventListener("pointermove", (e) => { if (down) panel.box = [down, tile(e)]; });
        canvas.addEventListener("pointerup", (e) => {
            const at = tile(e);
            if (down && Math.hypot(at.x - down.x, at.y - down.y) > 1.5) seat.box(down.x, down.y, at.x, at.y);
            else note(panel, seat.tap(at.x, at.y));
            down = null; panel.box = null;
        });
        el.querySelector(".pp-prev").addEventListener("click", () => { panel.slot--; panel.draw(seat); });
        el.querySelector(".pp-next").addEventListener("click", () => { panel.slot++; panel.draw(seat); });
        el.querySelector(".pp-item").addEventListener("click", () => { const items = seat.shop(); note(panel, seat.buy(items[mod(panel.slot, items.length)])); });
    }
    el.addEventListener("pointerdown", (e) => e.stopPropagation());
    panel.draw = (s) => drawPanel(panel, s, ctx, thumb);
    keys(el.querySelector(".pp-keys"), seat);
    return panel;
}

const mod = (a, n) => ((a % n) + n) % n;

function keys(el, seat) {
    if (seat.who.kind !== "pad")
        return el.replaceChildren(document.createTextNode("Click to select and order · drag to box · ‹ › to shop"));
    const parts = [[STICK.LEFT, "point"], [BUTTON.A, "select/order"], [BUTTON.X, "army"], [BUTTON.LB, ""], [BUTTON.RB, "shop"], [TRIGGER.RT, "buy"], [BUTTON.B, "clear"]];
    el.replaceChildren(...parts.flatMap(([what, says]) => { const g = glyph(what); return g ? [g, document.createTextNode(says ? ` ${says} ` : "")] : []; }));
}

function note(panel, text) {
    if (!text)
        return;
    panel.el.querySelector(".pp-note").textContent = text;
    panel.noteAt = performance.now();
}

function padFrame(seat, pad, f) {
    const panel = party.panels.get(seat.side);
    if (!panel || !pad || !pad.connected)
        return;
    const w = seat.world, speed = w.width * 0.6 * f.dt;
    const c = panel.cursor;
    c.x = Math.max(0, Math.min(w.width, c.x + Math.sign(pad.lx) * pad.lx * pad.lx * speed));
    c.y = Math.max(0, Math.min(w.height, c.y - Math.sign(pad.ly) * pad.ly * pad.ly * speed));
    if (pad.pressed & BUTTON.A)
        panel.down = { x: c.x, y: c.y };
    if (panel.down && (pad.released & BUTTON.A)) {
        if (Math.hypot(c.x - panel.down.x, c.y - panel.down.y) > 1.5) seat.box(panel.down.x, panel.down.y, c.x, c.y);
        else note(panel, seat.tap(c.x, c.y));
        panel.down = null;
    }
    panel.box = panel.down ? [panel.down, { x: c.x, y: c.y }] : null;
    if (pad.pressed & BUTTON.B) seat.command("clear");
    if (pad.pressed & BUTTON.X) seat.command("army");
    if (pad.pressed & BUTTON.Y) party.scene?.lookAt(c.x, c.y);
    if (pad.pressed & BUTTON.LB) panel.slot--;
    if (pad.pressed & BUTTON.RB) panel.slot++;
    if ((pad.pressed & (BUTTON.LB | BUTTON.RB)))
        panel.draw(seat);
    const rt = pad.rt > 0.5;
    if (rt && !panel.buying) {
        const items = seat.shop();
        note(panel, seat.buy(items[mod(panel.slot, items.length)]));
    }
    panel.buying = rt;
    const cur = panel.el.querySelector(".pp-cursor");
    cur.style.left = `${c.x / w.width * 100}%`;
    cur.style.top = `${c.y / w.height * 100}%`;
}

function drawPanel(panel, seat, ctx, thumb) {
    const s = seat.state(), S = 240, k = S / s.size;
    panel.el.querySelector(".pp-scrap").textContent = `⛁ ${s.scrap}`;
    ctx.clearRect(0, 0, S, S);
    if (thumb.complete && thumb.naturalWidth)
        ctx.drawImage(thumb, 0, 0, S, S);
    else {
        ctx.fillStyle = "#26301f";
        ctx.fillRect(0, 0, S, S);
    }
    for (const [x, y, size, side, hq] of s.buildings) {
        ctx.fillStyle = SIDE_CSS[side];
        ctx.fillRect(x * k, y * k, size * k, size * k);
        if (hq) { ctx.strokeStyle = "#fff"; ctx.strokeRect(x * k, y * k, size * k, size * k); }
    }
    for (const [x, y, side] of s.foes) {
        ctx.fillStyle = SIDE_CSS[side];
        ctx.fillRect(x * k - 2, y * k - 2, 4, 4);
    }
    const sel = new Set(s.sel);
    for (const [id, x, y, air] of s.own) {
        ctx.fillStyle = sel.has(id) ? "#fff" : SIDE_CSS[seat.side];
        ctx.beginPath();
        ctx.arc(x * k, y * k, air ? 2.4 : 3, 0, Math.PI * 2);
        ctx.fill();
    }
    if (panel.box) {
        const [a, b] = panel.box;
        ctx.strokeStyle = "#fff";
        ctx.strokeRect(Math.min(a.x, b.x) * k, Math.min(a.y, b.y) * k, Math.abs(a.x - b.x) * k, Math.abs(a.y - b.y) * k);
    }
    const item = s.shop.length ? s.shop[mod(panel.slot, s.shop.length)] : null;
    const shop = panel.el.querySelector(".pp-item");
    shop.textContent = item ? `${item.type === "power" ? "⚡" : item.type === "build" ? "🏗" : "🤖"} ${item.name}${item.cost ? ` · ${item.cost}` : item.charge != null ? ` · ${item.charge}%` : ""}` : "";
    shop.classList.toggle("off", !!item && !item.ok);
    panel.el.querySelector(".pp-prev").textContent = "‹";
    panel.el.querySelector(".pp-next").textContent = "›";
    if (s.pending)
        panel.el.querySelector(".pp-note").textContent = s.pending.ready ? `${s.pending.name} going up` : `${s.pending.name}: ${s.pending.left}s`;
    else if (performance.now() - panel.noteAt > 3000)
        panel.el.querySelector(".pp-note").textContent = seat.arming ? "Pick a spot for the calldown" : "";
}

/** For Lamp's snapshot: who sat where, so a match opened again for a change of code keeps its seats. */
export function partySnapshot() {
    if (!party.started)
        return null;
    return { mapId: party.mapId, seats: [...party.seats.values()].map((s) => ({ side: s.side, who: s.who })) };
}

/** A match played together, put back after a change of code: the same seats, the phones finding theirs as they rejoin. */
export function restoreParty(saved) {
    party.open = true;
    party.started = true;
    party.mapId = saved.mapId;
    party.sideOrder = sidesOf(saved.mapId);
    party.seats.clear();
    for (const { side, who } of saved.seats)
        party.seats.set(side, new Seat(side, who));
    pads.off = true;
    const c = controllers();
    if (c) {
        listen();
        c.start();
    }
    return party.seats;
}
