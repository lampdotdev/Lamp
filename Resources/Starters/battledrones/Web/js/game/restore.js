// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

export function restoreWorld(w, saved) {
    const copy = structuredClone(saved);
    const fields = w;
    for (const k of Object.keys(fields))
        if (!(k in copy))
            delete fields[k];
    Object.assign(w, copy);
}
