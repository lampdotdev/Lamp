// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { isKnownMapId, mapBansMutator, mapById } from "../sim/maps.js";
import { isRandomMapId } from "../sim/mapgen.js";
import { isMutatorId } from "../sim/rules.js";
import { opById } from "../sim/ops.js";
import { setLocalSide } from "./controller.js";

/** Match settings, chosen on the menu before the game boots. */
export const gameMode = {
    /** AI vs AI: both factions computer-controlled, player just watches. */
    spectator: false,
    mapId: "riverlands",
    difficulty: "normal",
    mode: "skirmish",
    /** Skirmish mutators picked on the menu (saved with the settings). */
    mutators: [],
    /** Set while playing the Daily Op (never saved: it overrides map, difficulty and mutators). */
    daily: null,
    /** Set while playing an op (never saved: the op fixes map, enemy and rules). */
    op: null,
    /** The op card picked on the menu (saved). */
    opId: "",
    /**
     * Uncharted (saved): a generated map is played blind — no thumbnail, name
     * or preview on the menu, and nothing of it shows in the match until it's
     * scouted. Render/UI only: the sim and replays don't change.
     */
    uncharted: false,
    /** A match played together (lamp/party.js): people command sides from their phones and controllers (never saved). */
    party: false
};

/** Is the coming match on a generated map played Uncharted (not when watching AI vs AI, an op or the Daily)? */
export const unchartedMatch = () => gameMode.uncharted && isRandomMapId(gameMode.mapId) && !gameMode.spectator && !gameMode.op && !gameMode.daily;

/**
 * The mutators the next match runs with (Last Stand runs classic rules),
 * leaving out any the map can't be played with (Air War on the
 * Archipelago): the saved pick stays, for the next map that allows it.
 */
export function activeMutators() {
    if (gameMode.op)
        return []; // an op brings its own rules
    if (gameMode.daily)
        return gameMode.daily.mutators;
    if (gameMode.mode !== "skirmish")
        return [];
    const def = mapById(gameMode.mapId);
    return gameMode.mutators.filter((id) => !mapBansMutator(def, id));
}

/**
 * Point the coming match at a sound duel's agreed one (SOUND-DUEL.md "Getting
 * into a duel"): its map (a MAPS id, or a generated map's id) and mutators, a
 * plain skirmish played by this phone as `local`, so startGame loads the art
 * for the map both phones play. Never saved: the menu's own picks stay.
 */
export function duelSetup(cfg) {
    gameMode.mapId = cfg.mapId;
    gameMode.mode = "skirmish";
    gameMode.mutators = cfg.mutators.slice();
    gameMode.spectator = false;
    gameMode.daily = null;
    gameMode.op = null;
    gameMode.uncharted = false;
    setLocalSide(cfg.local);
}

/**
 * What the end screen's Rematch stores, so the reload replays the same kind of
 * match: "op:<id>", "daily", "spectate" (another AI-vs-AI match) or "1" (a
 * skirmish or Last Stand with the menu's picks). A watched Last Stand hands
 * over to the player ("▶ Your turn"), so it rematches as "1".
 */
export const rematchToken = () => gameMode.party
    ? "party"
    : gameMode.op
    ? `op:${gameMode.op.id}`
    : gameMode.daily
        ? "daily"
        : gameMode.spectator && gameMode.mode !== "survival"
            ? "spectate"
            : "1";

/**
 * The sim setup for the next match, built from the menu choices. A fresh
 * random seed per match (render side, so Math.random is fine here) keeps
 * seeded events varied while each match stays internally deterministic.
 * Skirmishes play with the map objectives (Uplinks, supply drops).
 */
export function matchOptions() {
    if (gameMode.op)
        return { seed: (Math.random() * 0x7fffffff) | 0, op: gameMode.op.id };
    const mutators = activeMutators();
    const survival = gameMode.mode === "survival";
    return {
        seed: (Math.random() * 0x7fffffff) | 0,
        // Uplinks and supply drops: skirmish (and the Daily Op); Last Stand has its waves
        ...(survival ? { survival: { difficulty: gameMode.difficulty } } : { objectives: true }),
        // mutators, and the Daily Op's date seed (everyone plays the same match)
        ...(mutators.length ? { mutators } : {}),
        ...(gameMode.daily ? { seed: gameMode.daily.seed } : {})
    };
}

const KEY = "battledrones.settings";

export function loadSettings() {
    try {
        const raw = localStorage.getItem(KEY);
        if (!raw)
            return;
        const s = JSON.parse(raw);
        // (a map this build doesn't have, or a malformed random id: back to the default)
        gameMode.mapId = typeof s.mapId === "string" && isKnownMapId(s.mapId) ? s.mapId : "riverlands";
        if (s.difficulty === "easy" || s.difficulty === "normal" || s.difficulty === "hard")
            gameMode.difficulty = s.difficulty;
        if (s.mode === "skirmish" || s.mode === "survival" || s.mode === "ops")
            gameMode.mode = s.mode;
        if (typeof s.opId === "string" && opById(s.opId))
            gameMode.opId = s.opId;
        if (Array.isArray(s.mutators))
            gameMode.mutators = s.mutators.filter(isMutatorId);
        gameMode.uncharted = s.uncharted === true;
    }
    catch {
        /* storage unavailable — defaults are fine */
    }
}

export function saveSettings() {
    if (gameMode.daily || gameMode.op)
        return; // the Daily Op's / an op's map and difficulty are not the player's picks
    try {
        localStorage.setItem(KEY, JSON.stringify({ mapId: gameMode.mapId, difficulty: gameMode.difficulty, mode: gameMode.mode, mutators: gameMode.mutators, opId: gameMode.opId, uncharted: gameMode.uncharted }));
    }
    catch {
        /* ignore */
    }
}
