
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
