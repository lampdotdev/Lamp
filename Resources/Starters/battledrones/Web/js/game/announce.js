// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

const listeners = new Set();

/** Subscribe to announcements; returns an unsubscribe function. */
export function onAnnounce(l) {
    listeners.add(l);
    return () => listeners.delete(l);
}

export function announce(a) {
    for (const l of [...listeners])
        l(a);
}
