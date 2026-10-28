// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { COMBAT, ECONOMY, UNITS } from "./balance.js";

export const DEFAULT_RULES = Object.freeze({
    startScrap: ECONOMY.startingScrap,
    incomeMult: 1,
    buildSpeed: 1,
    dmgMult: 1,
    bannedUnits: [],
    bannedBuildings: [],
    fogOff: false,
    startRank: 0,
    startUnits: [],
    mutators: []
});

/** Ground combat units: the tanks, the robot infantry squads and the Goliath. */
export const GROUND_COMBAT = ["stinger", "flak-crawler", "mortar", "mastodon", "lancer", "trooper", "rocket-squad", "sniper", "goliath"];

/**
 * What "no ground combat" bans (Air War, Sky Pirates): GROUND_COMBAT, and the
 * Condor — the starting Trooper Squad is kept to guard home, and a dropship
 * would fly it into the fight.
 */
export const NO_GROUND_COMBAT = [...GROUND_COMBAT, "condor"];

/** Robot infantry: the squads an Assembly Bay builds. */
export const INFANTRY_SQUADS = ["trooper", "rocket-squad", "sniper"];

/**
 * What Infantry War bans: every combat vehicle and combat aircraft. Harvesters,
 * Scouts, Menders and the Condor stay (none of them fights).
 */
export const NO_VEHICLES = [
    ...GROUND_COMBAT.filter((k) => !INFANTRY_SQUADS.includes(k)),
    "wasp",
    "raptor",
    "hornet"
];

export const MUTATORS = {
    blitz: {
        id: "blitz",
        name: "Blitz",
        icon: "⚡",
        desc: "Both sides start with 3,000 scrap",
        apply: (r) => (r.startScrap = 3000)
    },
    goldrush: {
        id: "goldrush",
        name: "Gold Rush",
        icon: "💰",
        desc: "Harvesting and HQ income ×1.5",
        apply: (r) => (r.incomeMult *= 1.5)
    },
    glass: {
        id: "glass",
        name: "Glass Cannons",
        icon: "💥",
        desc: "Every weapon deals double damage",
        apply: (r) => (r.dmgMult *= 2)
    },
    rapidfab: {
        id: "rapidfab",
        name: "Rapid Fab",
        icon: "🔧",
        desc: "Units and buildings build in half the time",
        apply: (r) => (r.buildSpeed *= 2)
    },
    airwar: {
        id: "airwar",
        name: "Air War",
        icon: "✈️",
        // SAM sites go too: measured, aircraft-only armies never crack a SAM line (every
        // AI-vs-AI Air War drew at 25:00); turrets and the HQ gun still shoot back.
        // Infantry and their Assembly Bay are ground combat too (the starting squad stays home,
        // so no Condor either: NO_GROUND_COMBAT)
        desc: "No ground combat units, Condors, Fab Plants, Assembly Bays or SAM sites: dogfights decide it",
        bansUnits: NO_GROUND_COMBAT,
        // (and no Goliath, which Nomads, Robot Love and Goliath Armada are about)
        conflicts: ["infantrywar", "airborne", "nomads", "robotlove", "armada"],
        bansBuildings: ["fab-plant", "assembly-bay", "sam-site"],
        apply: (r) => {
            r.bannedUnits.push(...NO_GROUND_COMBAT);
            r.bannedBuildings.push("fab-plant", "assembly-bay", "sam-site");
        }
    },
    infantrywar: {
        id: "infantrywar",
        name: "Infantry War",
        icon: "🤖",
        // the Airpad stays for Condors, Scouts and Menders; Turrets and SAM sites stay too
        // (Rocket Squads crack them, and SAMs are the answer to Condor drops)
        desc: "Robot infantry only: no combat vehicles, combat aircraft or Fab Plants",
        bansUnits: NO_VEHICLES,
        bansBuildings: ["fab-plant"],
        conflicts: ["airwar", "nomads", "robotlove", "armada"],
        apply: (r) => {
            r.bannedUnits.push(...NO_VEHICLES);
            r.bannedBuildings.push("fab-plant");
        }
    },
    airborne: {
        id: "airborne",
        name: "Airborne",
        icon: "🪂",
        // the classic start already has the Trooper Squad: this adds the other two and a ride
        desc: "Both sides start with a Condor dropship and one of each infantry squad",
        // (Goliath Armada starts with nothing but its Goliaths and their Condors)
        conflicts: ["airwar", "armada"],
        apply: (r) => {
            for (const k of ["condor", "rocket-squad", "sniper"])
                if (!r.startUnits.includes(k))
                    r.startUnits.push(k);
        }
    },
    veterans: {
        id: "veterans",
        name: "Veterans",
        icon: "🎖️",
        desc: "Combat units roll out at rank 1 (+15% damage)",
        apply: (r) => (r.startRank = Math.max(r.startRank, 1))
    },
    clearskies: {
        id: "clearskies",
        name: "Clear Skies",
        icon: "☀️",
        desc: "No fog of war: both sides see everything",
        apply: (r) => (r.fogOff = true)
    },
    nomads: {
        id: "nomads",
        name: "Nomads",
        icon: "🦿",
        // the base walks: anchored, it takes scrap, builds Harvesters and squads, and buildings go up round it
        desc: "Each side starts with a Goliath instead of a base",
        conflicts: ["airwar", "infantrywar", "armada"],
        apply: (r) => (r.nomads = true)
    },
    robotlove: {
        id: "robotlove",
        name: "Robot Love",
        icon: "💘",
        desc: "Two enemy Goliaths that meet fall in love, and the battle ends in a draw",
        conflicts: ["airwar", "infantrywar"],
        apply: (r) => (r.robotLove = true)
    },
    armada: {
        id: "armada",
        name: "Goliath Armada",
        icon: "🚁",
        // no base at all: anchored, the Goliaths build Harvesters and squads, and buildings go up round them
        desc: "Each side starts with four Goliaths in the air, two Condors carrying each, and nothing else",
        // (Air War and Infantry War ban the Goliath; Nomads and Airborne start a side some other way)
        conflicts: ["airwar", "infantrywar", "airborne", "nomads"],
        apply: (r) => (r.armada = true)
    }
};

/** Canonical display order. */
export const MUTATOR_IDS = Object.keys(MUTATORS);

export const isMutatorId = (s) => typeof s === "string" && s in MUTATORS;

/** Do these mutators all work together? */
export function mutatorsCompatible(ids) {
    for (const a of ids)
        for (const b of ids)
            if (a !== b && MUTATORS[a].conflicts?.includes(b))
                return false;
    return true;
}

/**
 * The picker's toggle: `id` off if it is on, else on — switching off any
 * mutator it can't run with (Air War and the infantry ones). Canonical order.
 */
export function toggleMutator(on, id) {
    const keep = on.includes(id) ? on.filter((m) => m !== id) : [...on.filter((m) => mutatorsCompatible([id, m])), id];
    return MUTATOR_IDS.filter((m) => keep.includes(m));
}

/**
 * Rules for a set of mutators (deduplicated, unknown ids ignored; of two that
 * conflict, the first in canonical order wins and the other is left out).
 */
export function makeRules(ids) {
    const r = { ...DEFAULT_RULES, bannedUnits: [], bannedBuildings: [], startUnits: [], mutators: [] };
    for (const id of MUTATOR_IDS)
        if (ids.includes(id) && !r.mutators.some((m) => MUTATORS[m].conflicts?.includes(id))) {
            MUTATORS[id].apply(r);
            r.mutators.push(id);
        }
    return r;
}

/** Install a match's mutators (createMapWorld calls this before the first tick). */
export function applyMutators(w, ids) {
    const r = makeRules(ids.filter(isMutatorId));
    if (r.mutators.length === 0)
        return;
    w.rules = r;
    for (const f of Object.values(w.factions))
        f.scrap = r.startScrap;
}

export const rulesOf = (w) => w.rules ?? DEFAULT_RULES;

/** Nomads and Goliath Armada: no HQ is ever built, and a side's Goliaths are its base. */
export const goliathBase = (w) => !!(rulesOf(w).nomads || rulesOf(w).armada);

/** True when any mutator is active (career: no map stars). */
export const isMutated = (w) => rulesOf(w).mutators.length > 0;

/** Total income multiplier for a faction: AI handicap × mutators (× an op's per-side factor). */
export const incomeOf = (w, f) => {
    const r = rulesOf(w);
    return w.factions[f].incomeMult * r.incomeMult * (r.sideIncome?.[f] ?? 1);
};

/**
 * Why a kind is disabled by this match's rules (null = allowed): a mutator
 * for both sides, or (with `faction`) an op's ban on that side alone.
 */
export function bannedBy(w, kind, faction) {
    const r = rulesOf(w);
    const isUnit = kind in UNITS;
    const inList = (units, buildings) => isUnit ? !!units?.includes(kind) : !!buildings?.includes(kind);
    const side = faction ? r.sideBans?.[faction] : undefined;
    if (!inList(r.bannedUnits, r.bannedBuildings) && !inList(side?.units, side?.buildings))
        return null;
    const by = r.mutators.find((id) => inList(MUTATORS[id].bansUnits, MUTATORS[id].bansBuildings));
    return by ? `Disabled: ${MUTATORS[by].name}` : r.banLabel ?? "Disabled: match rules";
}

/** Veterans mutator: a freshly built combat unit starts ranked (with the XP to match). */
export function applySpawnRank(w, u) {
    const rank = Math.min(COMBAT.rankXp.length, rulesOf(w).startRank);
    if (rank <= 0 || UNITS[u.kind].dps <= 0 || u.rank >= rank)
        return;
    u.rank = rank;
    u.xp = Math.max(u.xp, COMBAT.rankXp[rank - 1] * UNITS[u.kind].cost);
}

/**
 * Is robot infantry this side's whole army? No Fab Plant and no combat
 * aircraft, but an Assembly Bay (Infantry War, or an op's bans to match):
 * the AI then builds Bays where its plan says Fab Plant (ai/commander.ts).
 */
export function infantryArmy(w, f) {
    return bannedBy(w, "fab-plant", f) !== null && bannedBy(w, "wasp", f) !== null && bannedBy(w, "assembly-bay", f) === null;
}

/**
 * Can an AI personality play its plan under these rules? (An air-only
 * commander needs an Airpad and aircraft to build there; a tank plan needs
 * the Fab Plant; a ground-raid plan needs it too, or under Infantry War an
 * Assembly Bay to field its early army instead. Measured: Ironclad, playing
 * Infantry War from Bays, won 20% of 100 AI-vs-AI games; Rush 40%.)
 */
export function strategyFits(s, r) {
    if (s.airOnly && (r.bannedBuildings.includes("airpad") || r.bannedUnits.includes("wasp")))
        return false;
    if (s.heavy && r.bannedBuildings.includes("fab-plant"))
        return false;
    if (s.groundRaids && r.bannedBuildings.includes("fab-plant") && r.bannedBuildings.includes("assembly-bay"))
        return false;
    return true;
}
