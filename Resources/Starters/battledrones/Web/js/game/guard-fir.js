// From Battle Drones by Simon Willison (Apache License 2.0, see LICENSE-battledrones): its TypeScript turned into
// JavaScript and changed to play on Lamp.

export const GUARD_SPECS = {
    high: { passHz: 8000, stopHz: 9500, attenDb: 70 },
    low: { passHz: 4000, stopHz: 5000, attenDb: 60 }
};

/** Design headroom over the spec (dB): Float32 rounding and the grid's misses stay inside it. */
const MARGIN_DB = 1.5;
/** Give up growing past this many taps (a broken rate, not a design). */
const MAX_TAPS = 2047;

/** The zeroth-order modified Bessel function, for the Kaiser window. */
function besselI0(x) {
    let sum = 1;
    let term = 1;
    const q = (x * x) / 4;
    for (let k = 1; k < 60; k++) {
        term *= q / (k * k);
        sum += term;
        if (term < sum * 1e-17)
            break;
    }
    return sum;
}

/** Kaiser's β for a stopband `atten` dB down. */
function kaiserBeta(atten) {
    if (atten > 50)
        return 0.1102 * (atten - 8.7);
    if (atten >= 21)
        return 0.5842 * Math.pow(atten - 21, 0.4) + 0.07886 * (atten - 21);
    return 0;
}

/** A Kaiser-windowed sinc low-pass of odd `length`, −6 dB at `cutHz`, unit gain at DC. */
function design(sr, cutHz, length, atten) {
    const h = new Float64Array(length);
    const mid = (length - 1) / 2;
    const beta = kaiserBeta(atten);
    const i0b = besselI0(beta);
    const fc = cutHz / sr;
    let sum = 0;
    for (let i = 0; i < length; i++) {
        const n = i - mid;
        const ideal = n === 0 ? 2 * fc : Math.sin(2 * Math.PI * fc * n) / (Math.PI * n);
        const r = n / mid;
        h[i] = ideal * (besselI0(beta * Math.sqrt(Math.max(0, 1 - r * r))) / i0b);
        sum += h[i];
    }
    // exactly unit gain at DC: the window leaves it a hair off
    const out = new Float32Array(length);
    for (let i = 0; i < length; i++)
        out[i] = h[i] / sum;
    return out;
}

/**
 * The magnitude response of a linear-phase (symmetric, odd-length) FIR at
 * `hz`, in dB. Exact for the taps given: the zero-phase amplitude
 * h[mid] + 2·Σ h[mid+k]·cos(ωk).
 */
export function firGainDb(taps, sr, hz) {
    const mid = (taps.length - 1) / 2;
    const w = (2 * Math.PI * hz) / sr;
    let a = taps[mid];
    for (let k = 1; k <= mid; k++)
        a += 2 * taps[mid + k] * Math.cos(w * k);
    return 20 * Math.log10(Math.max(Math.abs(a), 1e-12));
}

/** The worst (highest) gain from `fromHz` to Nyquist, on a grid of 1/8 of the response's lobe width. */
function worstStopDb(taps, sr, fromHz) {
    const step = sr / taps.length / 8;
    let worst = -Infinity;
    for (let f = fromHz; f <= sr / 2; f += step)
        worst = Math.max(worst, firGainDb(taps, sr, f));
    return Math.max(worst, firGainDb(taps, sr, sr / 2));
}

const cache = new Map();

/**
 * The guard's taps for `plan` at sample rate `sr` (odd length, linear phase,
 * unit gain at DC; the single tap 1 at a rate whose Nyquist doesn't reach the
 * stopband). Designed once per rate and plan; the array is shared, so callers
 * copy it before changing it (a ConvolverNode's buffer copies it). Throws a
 * RangeError only for a rate that isn't one.
 */
export function guardFir(sr, plan) {
    const key = `${sr}:${plan}`;
    const hit = cache.get(key);
    if (hit)
        return hit;
    const spec = GUARD_SPECS[plan];
    if (!(sr > 0) || !Number.isFinite(sr))
        throw new RangeError(`${sr} Hz is not a sample rate`);
    if (sr <= 2 * spec.stopHz) {
        // nothing at this rate reaches the stopband: its own Nyquist is the guard
        const one = new Float32Array([1]);
        cache.set(key, one);
        return one;
    }
    const atten = spec.attenDb + MARGIN_DB;
    const cut = (spec.passHz + spec.stopHz) / 2;
    const dw = (2 * Math.PI * (spec.stopHz - spec.passHz)) / sr;
    // Kaiser's length estimate, rounded up to odd
    let len = Math.ceil((atten - 7.95) / (2.285 * dw)) + 1;
    if ((len & 1) === 0)
        len++;
    let taps = design(sr, cut, len, atten);
    while (worstStopDb(taps, sr, spec.stopHz) > -spec.attenDb - 0.5 * MARGIN_DB && len < MAX_TAPS) {
        len += 2;
        taps = design(sr, cut, len, atten);
    }
    cache.set(key, taps);
    return taps;
}
