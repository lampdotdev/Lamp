
export function restoreWorld(w, saved) {
    const copy = structuredClone(saved);
    const fields = w;
    for (const k of Object.keys(fields))
        if (!(k in copy))
            delete fields[k];
    Object.assign(w, copy);
}
