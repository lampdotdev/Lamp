// A match as plain JSON, for Lamp's runtime to keep while the game's code changes (`snapshot()` in lamp-game.js), and
// back. The sim keeps its state in plain objects, Maps, Sets and typed arrays, all of which come back as they were, so
// a match decoded here plays on exactly as the one it was taken from would have.

const toBase64 = (view) => {
    const bytes = new Uint8Array(view.buffer, view.byteOffset, view.byteLength);
    let text = "";
    for (let i = 0; i < bytes.length; i += 32768)
        text += String.fromCharCode.apply(null, bytes.subarray(i, i + 32768));
    return btoa(text);
};

const fromBase64 = (text) => {
    const raw = atob(text), bytes = new Uint8Array(raw.length);
    for (let i = 0; i < raw.length; i++)
        bytes[i] = raw.charCodeAt(i);
    return bytes.buffer;
};

const ARRAYS = { Uint8Array, Int8Array, Uint16Array, Int16Array, Uint32Array, Int32Array, Float32Array, Float64Array };

/** `value` as JSON-safe data: Maps, Sets, typed arrays and numbers JSON can't hold are tagged. */
export function encodeState(value) {
    return JSON.parse(JSON.stringify(value, (key, v) => {
        if (v instanceof Map)
            return { $map: [...v] };
        if (v instanceof Set)
            return { $set: [...v] };
        if (ArrayBuffer.isView(v))
            return { $bytes: v.constructor.name, data: toBase64(v) };
        if (typeof v === "number" && !Number.isFinite(v))
            return { $number: String(v) };
        return v;
    }));
}

/** What `encodeState` gave, as it was. */
export function decodeState(data) {
    return JSON.parse(JSON.stringify(data), (key, v) => {
        if (v && typeof v === "object") {
            if (Array.isArray(v.$map))
                return new Map(v.$map);
            if (Array.isArray(v.$set))
                return new Set(v.$set);
            if (typeof v.$bytes === "string" && ARRAYS[v.$bytes])
                return new ARRAYS[v.$bytes](fromBase64(v.data));
            if (typeof v.$number === "string")
                return Number(v.$number);
        }
        return v;
    });
}
