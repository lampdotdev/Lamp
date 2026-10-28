// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

/** Every side there can be, in canonical order. */
export const FACTIONS = ["blue", "red", "green", "purple"];
/** A classic match's sides. */
export const DUO = ["blue", "red"];

export const isFaction = (s) => typeof s === "string" && FACTIONS.includes(s);

/** The sides playing this match, in canonical order. */
export const sidesOf = (w) => w.sides ?? DUO;

/** More than two sides: a free-for-all (otherwise every rule plays exactly as a duel always has). */
export const isMulti = (w) => (w.sides?.length ?? 2) > 2;

/** One value per side there can be (every Record<Faction, …> in the world has all four). */
export function perSide(make) {
    return { blue: make("blue"), red: make("red"), green: make("green"), purple: make("purple") };
}

/** The other sides playing, in canonical order. */
export const rivalsOf = (w, f) => sidesOf(w).filter((s) => s !== f);

/**
 * The one enemy of a duel. (A free-for-all has several: code that needs
 * this must ask rivalsOf, or the side a kill or a strike came from.)
 */
export const otherSide = (f) => (f === "blue" ? "red" : "blue");

/** Quarter turns (clockwise on screen) from blue's frame to this side's: blue 0, green 1, red 2, purple 3. */
export const QUARTER = { blue: 0, green: 1, red: 2, purple: 3 };

/** The side whose frame is `q` quarter turns from blue's. */
export const SIDE_AT_QUARTER = ["blue", "green", "red", "purple"];

/**
 * A vector turned by q quarter turns (clockwise on screen, y down): one turn
 * takes (dx, dy) to (−dy, dx). Two is (−dx, −dy), exactly red's mirror.
 */
export function turnVec(q, dx, dy) {
    switch (q & 3) {
        case 1:
            return [-dy, dx];
        case 2:
            return [-dx, -dy];
        case 3:
            return [dy, -dx];
        default:
            return [dx, dy];
    }
}

/**
 * A point (continuous tile coordinates) turned q quarter turns about the
 * centre of a w × h map. One turn takes (x, y) to (h − y, x), which needs a
 * square map; two is (w − x, h − y), red's mirror, on any map.
 */
export function turnPoint(q, width, height, x, y) {
    switch (q & 3) {
        case 1:
            return { x: height - y, y: x };
        case 2:
            return { x: width - x, y: height - y };
        case 3:
            return { x: y, y: width - x };
        default:
            return { x, y };
    }
}

/** The top-left tile of a size² footprint at top-left (tx, ty), turned q quarter turns (as turnPoint). */
export function turnTile(q, width, height, tx, ty, size = 1) {
    switch (q & 3) {
        case 1:
            return [height - ty - size, tx];
        case 2:
            return [width - tx - size, height - ty - size];
        case 3:
            return [ty, width - tx - size];
        default:
            return [tx, ty];
    }
}

/** How many copies a map's symmetry makes of each feature: 4 on a four-player map, else 2. */
export const symmetryOf = (w) => (isMulti(w) ? 4 : 2);

/** The quarter turns that carry a feature onto its symmetric copies: [0, 2] on a 2-player map, [0, 1, 2, 3] on a four-player one. */
export const symmetryTurns = (w) => (isMulti(w) ? [0, 1, 2, 3] : [0, 2]);
