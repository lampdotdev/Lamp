import { UNITS } from "../sim/balance.js";
import { announce } from "./announce.js";
import { Ease } from "./three/tween.js";
import { CalldownCredit, powerName } from "./calldown-credit.js";
import { NAMED_RANK, RANK_TITLES, callsignOf, heroShort, killsLabel, stars } from "./heroes.js";
import { SIDE_NAME } from "./side-style.js";

const TITLE_STYLE = {
    1: { color: "#ffe7a6", size: 15 },
    2: { color: "#ffd66e", size: 17 },
    3: { color: "#ffc23a", size: 21 }
};

export class HeroPresenter {
    v;
    w;
    opts;
    lost = [];
    aces = [];
    /** Live promotion titles, one per unit (a new one replaces the old). */
    titles = new Map();
    /** Names the Barrage / Sky Hammer that got a hero (calldown-credit.ts). */
    credit;

    constructor(v, w, opts) {
        this.v = v;
        this.w = w;
        this.opts = opts;
        this.credit = new CalldownCredit(w);
    }

    handleFx(ev) {
        const by = this.credit.see(ev);
        if (ev.type === "rankUp")
            this.promoted(ev.id);
        else if (ev.type === "death" && ev.unitKind && ev.rank >= NAMED_RANK) {
            const rec = {
                name: callsignOf(this.w, { id: ev.id, faction: ev.faction }),
                line: heroShort(this.w, { id: ev.id, faction: ev.faction, kind: ev.unitKind, kills: ev.kills }),
                kills: ev.kills,
                x: ev.x,
                y: ev.y,
                strike: by ? { by: by.faction, power: by.power } : null
            };
            if (this.opts.spectator) {
                // both sides' real heroes, not every rank-2 grunt
                if (ev.rank >= 3 || ev.kills >= 6)
                    this.lost.push({ ...rec, line: `${SIDE_NAME[ev.faction]}'s ${rec.line}` });
            }
            else if (ev.faction === this.opts.player)
                this.lost.push(rec);
            // an enemy veteran that actually hurt you, seen going down (a Goliath is seen anywhere: it can't hide)
            else if ((ev.rank >= 3 || ev.kills >= 3) && (UNITS[ev.unitKind].alwaysVisible || this.opts.seesPoint(ev.x, ev.y)))
                this.aces.push(rec);
        }
    }

    /** "by the enemy Sky Hammer" / "to your Barrage" when one strike got them all, else "". */
    strikeNote(list, prep) {
        const s = list[0].strike;
        if (!s || list.some((x) => x.strike?.power !== s.power || x.strike.by !== s.by))
            return "";
        const whose = this.opts.spectator
            ? `${SIDE_NAME[s.by]}'s`
            : s.by === this.opts.player
                ? "your"
                : s.power === "hammer"
                    ? "the enemy"
                    : "an enemy";
        return ` ${prep} ${whose} ${powerName(s.power)}`;
    }

    /** Emit this tick's batched notices. */
    flush() {
        if (this.lost.length > 0) {
            const l = this.lost;
            const by = this.strikeNote(l, "by");
            const msg = l.length === 1
                ? `${l[0].line} destroyed${by}`
                : `${listNames(l.map((x) => x.name))} destroyed${by} (${killsLabel(l.reduce((s, x) => s + x.kills, 0))} between them)`;
            this.opts.notify(`✝ ${msg}`, this.opts.spectator ? "info" : "bad", l[0].x, l[0].y);
        }
        if (this.aces.length > 0) {
            const a = this.aces;
            const to = this.strikeNote(a, "to");
            const msg = a.length === 1 ? `Enemy ace ${a[0].line} down${to}` : `Enemy aces ${listNames(a.map((x) => x.name))} down${to}`;
            this.opts.notify(`🎯 ${msg}`, "good", a[0].x, a[0].y);
        }
        this.lost = [];
        this.aces = [];
    }

    promoted(id) {
        const u = this.w.units.get(id);
        if (!u)
            return;
        const mine = u.faction === this.opts.player || this.opts.spectator;
        // titles over your own units; an enemy's only once it's dangerous
        const p = this.opts.unitPos(id) ?? { x: u.x, y: u.y, top: UNITS[u.kind].radius };
        const onScreen = this.v?.rig.onScreen(p.x, p.y) ?? false;
        if (onScreen && this.opts.seesUnit(u) && (mine || u.rank >= NAMED_RANK))
            this.floatTitle(id, p.x, p.y, p.top + 0.15, u.rank, mine);
        if (u.rank < NAMED_RANK || this.opts.spectator || u.faction !== this.opts.player)
            return;
        const name = callsignOf(this.w, u);
        const kind = UNITS[u.kind].name;
        if (u.rank >= 3)
            announce({
                key: "unit-elite",
                text: `${name} is Elite`,
                // (elites patch themselves up; a Goliath doesn't: only Menders repair it, GOLIATH.md)
                sub: `${stars(3)} ${kind} · ${killsLabel(u.kills)}${u.goliath ? "" : " · self-repairing"}`,
                tone: "epic",
                x: u.x,
                y: u.y,
                priority: 3
            });
        else
            this.opts.notify(`${stars(u.rank)} Your ${kind} earned a callsign: ${name}`, "good", u.x, u.y);
    }

    /** "VETERAN" / "HARDENED" / "ELITE" rising over the unit. */
    floatTitle(id, x, y, h, rank, friendly) {
        const v = this.v;
        if (!v)
            return;
        const prev = this.titles.get(id);
        if (prev) {
            v.tweens.kill(prev);
            v.screen.remove(prev);
            this.titles.delete(id);
        }
        if (this.titles.size >= 8)
            return; // a huge brawl: the chevrons will do
        const st = TITLE_STYLE[Math.min(3, Math.max(1, rank))];
        const t = v.screen.label({
            x, y, h, text: RANK_TITLES[Math.min(3, rank)] ?? "", size: st.size, color: friendly ? st.color : "#ff9a8a",
            stroke: "#1a1205", shadow: true, scale: 1.5, alpha: 0
        });
        v.tweens.add({ dur: 260, ease: Ease.backOut, owner: t, update: (k) => {
                t.scale = 1.5 - 0.5 * k;
                t.alpha = k;
            } });
        v.tweens.add({ dur: 1200, ease: Ease.sineOut, owner: t, update: (k) => (t.dy = -30 * k) });
        this.titles.set(id, t);
        v.tweens.add({
            dur: 350, delay: 850, owner: t,
            update: (k) => (t.alpha = 1 - k),
            done: () => {
                v.screen.remove(t);
                if (this.titles.get(id) === t)
                    this.titles.delete(id);
            }
        });
    }
}

function listNames(names) {
    if (names.length <= 1)
        return names[0] ?? "";
    const shown = names.slice(0, 3);
    const extra = names.length - shown.length;
    if (extra > 0)
        return `${shown.join(", ")} +${extra}`;
    return `${shown.slice(0, -1).join(", ")} and ${shown[shown.length - 1]}`;
}
