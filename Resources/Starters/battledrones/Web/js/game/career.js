// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { TICK_RATE } from "../sim/balance.js";
import { MEDAL_IDS, computeMedals } from "../sim/awards.js";
import { wavesSurvived } from "../sim/modes/survival.js";
import { isMutated, rulesOf } from "../sim/rules.js";
import { OPS, opById, opsUnlocked } from "../sim/ops.js";
import { mapById } from "../sim/maps.js";
import { isRandomMapId } from "../sim/mapgen.js";
import { chronicleOf } from "./chronicle.js";
import { today as todayIndex } from "./daily.js";
import { perSide, rivalsOf } from "../sim/sides.js";

export const RANKS = [
    { name: "Cadet", xp: 0 },
    { name: "Private", xp: 100 },
    { name: "Corporal", xp: 300 },
    { name: "Sergeant", xp: 600 },
    { name: "Lieutenant", xp: 1000 },
    { name: "Captain", xp: 1500 },
    { name: "Major", xp: 2200 },
    { name: "Colonel", xp: 3100 },
    { name: "General", xp: 4300 },
    { name: "Marshal", xp: 6000 }
];

export function rankOf(xp) {
    let i = 0;
    while (i + 1 < RANKS.length && xp >= RANKS[i + 1].xp)
        i++;
    const floor = RANKS[i].xp;
    const nxt = RANKS[i + 1] ?? null;
    return {
        index: i,
        name: RANKS[i].name,
        floor,
        next: nxt ? nxt.xp : null,
        nextName: nxt ? nxt.name : null,
        progress: nxt ? Math.max(0, Math.min(1, (xp - floor) / (nxt.xp - floor))) : 1
    };
}

// --------------------------------------------------------------------- XP ---

export const XP = {
    win: 100,
    loss: 30,
    /** A Robot Love draw: more than a loss, less than a win. */
    draw: 60,
    /** A loss (or a draw) pays in full only after this long (no farming by quitting fast). */
    lossFullSecs: 300,
    medal: 25,
    /** Last Stand: per wave survived. */
    wave: 10,
    /** First Daily Op win of the day. */
    dailyWin: 100,
    /** Ops: completing one, failing one (scaled by time like losses), first clear, each new star. */
    opWin: 60,
    opLoss: 15,
    opFirstClear: 100,
    opStar: 40,
    difficulty: { easy: 1, normal: 1.5, hard: 2.2 }
};

/** Stars per map × difficulty: win · win under 8:00 (a big map gives longer) · win without losing a building. */
export const STAR_SECS = 8 * 60;
export const STAR_LABELS = ["Win", "Win in under 8:00", "Win without losing a building"];

/** The ★★ time on a map: 8:00, or the map's own (MapDef.starSecs). */
export const starSecsFor = (mapId) => mapById(mapId).starSecs ?? STAR_SECS;

/** The three star labels on a map (its ★★ time spelled out). */
export function starLabelsFor(mapId) {
    const s = starSecsFor(mapId);
    return [STAR_LABELS[0], `Win in under ${Math.floor(s / 60)}:${String(s % 60).padStart(2, "0")}`, STAR_LABELS[2]];
}

const diffLabel = (d) => d.charAt(0).toUpperCase() + d.slice(1);

/** The XP breakdown for a result (before the daily bonus, which depends on the career). */
export function xpLines(r) {
    const mult = XP.difficulty[r.difficulty] ?? 1;
    const lines = [];
    if (r.kind === "op") {
        const title = opById(r.op?.id ?? "")?.title ?? "Op";
        if (r.won)
            lines.push({ label: `Op complete · ${title}`, xp: XP.opWin });
        else
            lines.push({ label: `Op failed · ${title}`, xp: Math.round(XP.opLoss * Math.max(0.2, Math.min(1, r.secs / 120))) });
    }
    else if (r.kind === "survival") {
        const waves = r.waves ?? 0;
        lines.push({ label: `${waves} wave${waves === 1 ? "" : "s"} · ${diffLabel(r.difficulty)}`, xp: Math.round(XP.wave * waves * mult) });
    }
    else if (r.won) {
        lines.push({ label: `Victory · ${diffLabel(r.difficulty)}`, xp: Math.round(XP.win * mult) });
    }
    else {
        // (a short match pays a fraction, a draw as a loss: no farming XP by quitting, or by a quick Robot Love)
        const k = Math.max(0.2, Math.min(1, r.secs / XP.lossFullSecs));
        if (r.drawn)
            lines.push({ label: `Draw · ${diffLabel(r.difficulty)}`, xp: Math.round(XP.draw * mult * k) });
        else
            lines.push({ label: `Defeat · ${diffLabel(r.difficulty)}`, xp: Math.round(XP.loss * mult * k) });
    }
    if (r.medals.length > 0)
        lines.push({ label: `${r.medals.length} medal${r.medals.length === 1 ? "" : "s"}`, xp: XP.medal * r.medals.length });
    return lines;
}

/** Star bitmask (bit 0 win, bit 1 fast win, bit 2 no buildings lost) this result earns (none on a generated map: there are endlessly many). */
export function starsFor(r) {
    if (r.kind !== "skirmish" || !r.won || r.mutators.length > 0 || r.daily !== null || isRandomMapId(r.mapId))
        return 0;
    let s = 1;
    if (r.secs < starSecsFor(r.mapId))
        s |= 2;
    if (r.buildingsLost === 0)
        s |= 4;
    return s;
}

export const starCount = (mask) => (mask & 1) + ((mask >> 1) & 1) + ((mask >> 2) & 1);

/** Ops completed (any stars). */
export const opsCompleted = (c) => OPS.filter((o) => (c.ops[o.id]?.stars ?? 0) & 1).length;
/** Is this op open yet? The first three are; each completion opens one more. */
export const opUnlocked = (c, id) => OPS.findIndex((o) => o.id === id) < opsUnlocked(opsCompleted(c));

export function emptyCareer() {
    return {
        v: 1,
        xp: 0,
        wins: 0,
        losses: 0,
        medals: {},
        stars: {},
        records: {},
        daily: { lastWin: 0, streak: 0, bestStreak: 0, wins: 0, plays: 0 },
        laststand: { runs: 0, waves: 0, best: 0 },
        ops: {}
    };
}

export const recordKey = (mapId, difficulty) => `${mapId}:${difficulty}`;

/** The streak as it stands today: it survives until a whole day passes without a win. */
export function currentStreak(c, day) {
    return c.daily.lastWin >= day - 1 && c.daily.lastWin > 0 ? c.daily.streak : 0;
}

/** Bank a result: pure — returns the new career and what changed. */
export function applyResult(c0, r, day = todayIndex(), opNumber = 0) {
    const c = JSON.parse(JSON.stringify(c0));
    const lines = xpLines(r);
    let daily = null;
    if (r.daily !== null) {
        c.daily.plays++;
        const firstWinToday = r.won && c.daily.lastWin !== r.daily;
        if (firstWinToday) {
            c.daily.streak = c.daily.lastWin === r.daily - 1 ? c.daily.streak + 1 : 1;
            c.daily.lastWin = r.daily;
            c.daily.bestStreak = Math.max(c.daily.bestStreak, c.daily.streak);
            c.daily.wins++;
            lines.push({ label: "Daily Op", xp: XP.dailyWin });
        }
        daily = { number: opNumber, won: r.won, streak: currentStreak(c, day), firstWinToday };
    }
    const firstMedals = r.medals.filter((m) => !c.medals[m]);
    for (const m of r.medals)
        c.medals[m] = (c.medals[m] ?? 0) + 1;
    const key = recordKey(r.mapId, r.difficulty);
    const starsBefore = c.stars[key] ?? 0;
    let op = null;
    if (r.kind === "op" && r.op) {
        const id = r.op.id;
        const rec = c.ops[id] ?? { stars: 0, bestSecs: null, plays: 0, wins: 0 };
        const before = rec.stars;
        const openBefore = opsUnlocked(opsCompleted(c));
        rec.plays++;
        if (r.won) {
            rec.wins++;
            rec.stars |= r.op.stars | 1;
            rec.bestSecs = rec.bestSecs === null ? r.secs : Math.min(rec.bestSecs, r.secs);
        }
        c.ops[id] = rec;
        const firstClear = r.won && !(before & 1);
        if (firstClear)
            lines.push({ label: "First clear", xp: XP.opFirstClear });
        const newStars = starCount(rec.stars & ~before & 6);
        if (newStars > 0)
            lines.push({ label: `${newStars} new star${newStars === 1 ? "" : "s"}`, xp: XP.opStar * newStars });
        const openAfter = opsUnlocked(opsCompleted(c));
        op = { id, starsBefore: before, starsAfter: rec.stars, firstClear, unlocked: openAfter > openBefore ? (OPS[openAfter - 1]?.id ?? null) : null };
    }
    if (r.kind === "op") {
        /* ops keep their own records: no skirmish W/L, map stars or Last Stand totals */
    }
    else if (r.kind === "skirmish") {
        // (a draw is neither)
        if (r.won)
            c.wins++;
        else if (!r.drawn)
            c.losses++;
        const rec = c.records[key] ?? { w: 0, l: 0, bestSecs: null };
        if (r.won) {
            rec.w++;
            if (r.mutators.length === 0 && r.daily === null)
                rec.bestSecs = rec.bestSecs === null ? r.secs : Math.min(rec.bestSecs, r.secs);
        }
        else if (!r.drawn)
            rec.l++;
        c.records[key] = rec;
        const add = starsFor(r);
        if (add)
            c.stars[key] = starsBefore | add;
    }
    else {
        c.laststand.runs++;
        c.laststand.waves += r.waves ?? 0;
        c.laststand.best = Math.max(c.laststand.best, r.waves ?? 0);
    }
    const gained = lines.reduce((s, l) => s + l.xp, 0);
    const xpBefore = c.xp;
    c.xp += gained;
    const rankBefore = rankOf(xpBefore);
    const rankAfter = rankOf(c.xp);
    return {
        career: c,
        s: {
            result: r,
            xpBefore,
            xpAfter: c.xp,
            gained,
            lines,
            rankBefore,
            rankAfter,
            rankedUp: rankAfter.index > rankBefore.index,
            medals: r.medals,
            firstMedals,
            starsBefore,
            starsAfter: c.stars[key] ?? 0,
            daily,
            op
        }
    };
}

// ---------------------------------------------------------------- storage ---

const KEY = "battledrones.career";

function sanitize(raw) {
    const c = emptyCareer();
    if (!raw || typeof raw !== "object")
        return c;
    const o = raw;
    const num = (v, d = 0) => (typeof v === "number" && Number.isFinite(v) ? v : d);
    c.xp = Math.max(0, num(o.xp));
    c.wins = num(o.wins);
    c.losses = num(o.losses);
    if (o.medals && typeof o.medals === "object")
        for (const id of MEDAL_IDS)
            if (num(o.medals[id]) > 0)
                c.medals[id] = num(o.medals[id]);
    if (o.stars && typeof o.stars === "object")
        for (const [k, v] of Object.entries(o.stars))
            if (typeof v === "number")
                c.stars[k] = v & 7;
    if (o.records && typeof o.records === "object")
        for (const [k, v] of Object.entries(o.records))
            if (v && typeof v === "object")
                c.records[k] = { w: num(v.w), l: num(v.l), bestSecs: typeof v.bestSecs === "number" ? v.bestSecs : null };
    if (o.daily && typeof o.daily === "object")
        c.daily = {
            lastWin: num(o.daily.lastWin),
            streak: num(o.daily.streak),
            bestStreak: num(o.daily.bestStreak),
            wins: num(o.daily.wins),
            plays: num(o.daily.plays)
        };
    if (o.laststand && typeof o.laststand === "object")
        c.laststand = { runs: num(o.laststand.runs), waves: num(o.laststand.waves), best: num(o.laststand.best) };
    if (o.ops && typeof o.ops === "object")
        for (const [k, v] of Object.entries(o.ops))
            if (opById(k) && v && typeof v === "object")
                c.ops[k] = { stars: num(v.stars) & 7, bestSecs: typeof v.bestSecs === "number" ? v.bestSecs : null, plays: num(v.plays), wins: num(v.wins) };
    return c;
}

export function loadCareer() {
    try {
        const raw = localStorage.getItem(KEY);
        return sanitize(raw ? JSON.parse(raw) : null);
    }
    catch {
        return emptyCareer(); // storage blocked or corrupt: play on without a career
    }
}

export function saveCareer(c) {
    try {
        localStorage.setItem(KEY, JSON.stringify(c));
    }
    catch {
        /* ignore */
    }
}

// ------------------------------------------------------------- settlement ---

/** One side's medal recap from the match chronicle (full information, end of match). */
export function recapOf(w, chronicle, pov) {
    const mvp = chronicle.mvp();
    return {
        pov,
        won: w.winner === pov,
        secs: w.tick / TICK_RATE,
        stats: perSide((f) => w.factions[f].stats),
        rivals: rivalsOf(w, pov),
        samples: chronicle.samples,
        deaths: chronicle.deaths,
        bestUnitKills: mvp[pov]?.kills ?? 0,
        strikes: chronicle.strikes,
        waves: w.survival ? wavesSurvived(w) : null
    };
}

/** Medals each side earned (spectator end screens annotate AI-vs-AI games). */
export function medalsOf(w, pov) {
    const ch = chronicleOf(w);
    ch.finish();
    return computeMedals(recapOf(w, ch, pov));
}

const settled = new WeakMap();

/**
 * Bank a finished match in the career (once per world: the scene calls it
 * when the HQ falls and the end screen asks again for the result).
 */
export function settleMatch(w, meta) {
    const done = settled.get(w);
    if (done)
        return done;
    const ch = chronicleOf(w);
    ch.finish();
    const recap = recapOf(w, ch, meta.pov);
    // an op is its own thing: stars per op, no medals, map stars or Last Stand records
    const op = w.ops ?? null;
    const result = {
        kind: op ? "op" : w.survival ? "survival" : "skirmish",
        mapId: w.mapId,
        difficulty: meta.difficulty,
        won: op ? w.winner === meta.pov : !w.survival && w.winner === meta.pov,
        ...(!op && !w.survival && w.winner === "draw" ? { drawn: true } : {}),
        secs: Math.round(recap.secs),
        buildingsLost: w.factions[meta.pov].stats.buildingsLost,
        medals: op ? [] : computeMedals(recap),
        mutators: isMutated(w) ? [...rulesOf(w).mutators] : [],
        daily: meta.daily ? meta.daily.day : null,
        ...(w.survival && !op ? { waves: recap.waves ?? 0 } : {}),
        ...(op ? { op: { id: op.id, stars: op.result?.stars ?? 0 } } : {})
    };
    const { career, s } = applyResult(loadCareer(), result, todayIndex(), meta.daily?.number ?? 0);
    saveCareer(career);
    settled.set(w, s);
    return s;
}

/** The settlement for a world, if it was banked. */
export const settlementOf = (w) => settled.get(w) ?? null;
