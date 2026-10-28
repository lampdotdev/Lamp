// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
import { DIFFICULTY, STRATEGIES } from "../sim/ai/commander.js";
import { opAiState } from "../sim/ops.js";
import { MUTATORS, makeRules, rulesOf, strategyFits } from "../sim/rules.js";
import { announce } from "./announce.js";
import { settleMatch } from "./career.js";
import { activeMutators, gameMode } from "./mode.js";

/**
 * Glue between the match and the meta layer (mutators, Daily Op, career):
 * the AI personality the rules allow, the opening rules banner, and banking
 * the result when the HQ falls. Kept out of GameScene so it stays a few hooks.
 */

/**
 * The AI personality for a commander: the Daily Op's, or (with mutators on)
 * a random one from the difficulty's pool whose plan survives the rules.
 * Undefined = let createAiState pick as usual.
 */
export function aiStrategy(difficulty) {
    if (gameMode.daily)
        return gameMode.daily.strategy;
    const muts = activeMutators();
    if (muts.length === 0)
        return undefined;
    const rules = makeRules(muts);
    const pool = DIFFICULTY[difficulty].pool.filter((n) => strategyFits(STRATEGIES[n], rules));
    return pool.length ? pool[Math.floor(Math.random() * pool.length)] : "balanced";
}

/** Seed for the AI's tie-breaks: the Daily Op's (same match for everyone) or random. */
export const aiSeed = (salt) => gameMode.daily ? (gameMode.daily.seed + salt) | 0 : (Math.random() * 1e9) | 0;

/** "💥 Glass Cannons · ⚡ Blitz" for the active rules ("" if classic). */
export function mutatorLine(w, sep = " · ") {
    return rulesOf(w)
        .mutators.map((id) => `${MUTATORS[id].icon} ${MUTATORS[id].name}`)
        .join(sep);
}

/** An op's enemy commander (null outside ops, or when the op has none: waves or no enemy). */
export const opEnemyAi = () => (gameMode.op ? opAiState(gameMode.op, aiSeed(1)) : null);

/** Opening banner naming the Daily Op and/or the mutators in play. */
export function announceRules(w) {
    if (w.ops)
        return; // an op opens with its own briefing banner (game/ops.ts)
    const line = mutatorLine(w);
    const d = gameMode.daily;
    if (!line && !d)
        return;
    announce({
        key: "match-rules",
        text: d ? `Daily Op #${d.number}` : "Mutators active",
        sub: line,
        tone: "info",
        priority: 1
    });
}

/** Bank the finished match in the career (spectators never do). */
export function settleCareer(w, pov) {
    if (gameMode.spectator)
        return null;
    const d = gameMode.daily;
    return settleMatch(w, {
        pov,
        difficulty: w.survival?.difficulty ?? gameMode.difficulty,
        daily: d ? { day: d.day, number: d.number } : null
    });
}
