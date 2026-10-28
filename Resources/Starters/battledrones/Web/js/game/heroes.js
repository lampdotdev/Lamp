import { UNITS } from "../sim/balance.js";
import { hash32 } from "../sim/rand.js";
import { perSide } from "../sim/sides.js";

/**
 * Veteran heroes: every unit has a callsign derived from its id; from rank 2
 * ("Hardened") the game uses it — in the selection panel, in toasts when it
 * is promoted or falls, and on the after-action report's MVP card.
 *
 * Presentation only (no three.js, no sim state): callsigns live in a per-world
 * registry so every HUD piece agrees on a unit's name. The first choice is a
 * pure hash of the unit id; a name the same side has already used this match
 * is skipped, so two living "Vipers" never share a squad.
 */

export const CALLSIGNS = [
    "Viper", "Ironhide", "Bulldog", "Sable", "Havoc", "Rook", "Jinx", "Talon",
    "Brick", "Nova", "Vandal", "Grit", "Onyx", "Ghost", "Hammer", "Kestrel",
    "Rampart", "Mako", "Ember", "Banshee", "Diesel", "Sparrow", "Tusk", "Cobalt",
    "Wraith", "Maverick", "Anvil", "Rascal", "Hex", "Lynx", "Bastion", "Zephyr",
    "Torque", "Vixen", "Grizzly", "Comet", "Ratchet", "Spectre", "Blitz", "Flint",
    "Mantis", "Juggernaut", "Echo", "Scorch", "Bruiser", "Valkyrie", "Patch", "Thunder"
];

/** Rank at which a unit is "named" (callsign shown, deaths reported). */
export const NAMED_RANK = 2;

/** Promotion titles by rank (index 0 unused). */
export const RANK_TITLES = ["", "VETERAN", "HARDENED", "ELITE"];

const ROMAN = ["", "", " II", " III", " IV", " V", " VI", " VII", " VIII", " IX"];

/** First-choice callsign for a unit id (pure, stable across sessions). */
export function baseCallsign(id) {
    return hash32(id, 0x5ca11) % CALLSIGNS.length;
}

export class CallsignRegistry {
    names = new Map();
    used = perSide(() => new Map());

    /** The unit's callsign, assigning one on first use. */
    name(id, faction) {
        const have = this.names.get(id);
        if (have)
            return have;
        const used = this.used[faction];
        const base = baseCallsign(id);
        let pick = null;
        for (let i = 0; i < CALLSIGNS.length && !pick; i++) {
            const n = CALLSIGNS[(base + i) % CALLSIGNS.length];
            if (!used.has(n))
                pick = n;
        }
        let name;
        if (pick) {
            used.set(pick, 1);
            name = pick;
        }
        else {
            // all 48 taken this match (long Last Stand runs): Viper II, Viper III…
            const root = CALLSIGNS[base];
            const n = (used.get(root) ?? 1) + 1;
            used.set(root, n);
            name = `${root}${ROMAN[n] ?? ` ${n}`}`;
        }
        this.names.set(id, name);
        return name;
    }

    /** The callsign if one was already assigned (no side effects). */
    peek(id) {
        return this.names.get(id);
    }
}

const registries = new WeakMap();

/** The match's shared callsign registry. */
export function callsigns(w) {
    let r = registries.get(w);
    if (!r)
        registries.set(w, (r = new CallsignRegistry()));
    return r;
}

export function callsignOf(w, u) {
    return callsigns(w).name(u.id, u.faction);
}

export const stars = (rank) => "★".repeat(Math.max(0, Math.min(3, rank)));

export const killsLabel = (n) => `${n} kill${n === 1 ? "" : "s"}`;

/** "Viper (Lancer, 9 kills)" — the toast form. */
export function heroShort(w, u) {
    return `${callsignOf(w, u)} (${UNITS[u.kind].name}, ${killsLabel(u.kills)})`;
}

/** "★★ Viper · Lancer · 9 kills" — the selection-panel form. */
export function heroLine(w, u) {
    return `${stars(u.rank)} ${callsignOf(w, u)} · ${UNITS[u.kind].name} · ${killsLabel(u.kills)}`;
}
