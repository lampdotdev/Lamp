// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.
/**
 * The one way a skirmish match is set up from its description (battle
 * records, AGENT-BATTLES.md; sound duels, SOUND-DUEL.md; a Last Stand or an
 * op played here, game/recorder.ts, with `survival` or `op`): the map with
 * objectives, blue's opener then red's (they take ids from the shared counter,
 * so the order matters; a four-player map's in canonical side order, sides.ts),
 * each side's income, then the fog drawn once. Two
 * phones that call this with the same setup hold the same world.
 */
import { tickFog } from "./fog.js";
import { createMapWorld } from "./maps.js";
import { applyOpener } from "./openers.js";
import { sidesOf } from "./sides.js";

export function setupWorld(r) {
    const w = createMapWorld(r.map, {
        seed: r.seed,
        objectives: true,
        ...(r.mutators.length ? { mutators: r.mutators } : {}),
        ...(r.survival ? { survival: r.survival } : {}),
        ...(r.op ? { op: r.op } : {})
    });
    for (const f of sidesOf(w)) {
        const o = r.openers[f];
        if (o)
            applyOpener(w, f, o);
        const m = r.income?.[f];
        if (m !== undefined)
            w.factions[f].incomeMult = m;
    }
    tickFog(w);
    return w;
}
