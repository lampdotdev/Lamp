import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { isIP } from "node:net";
import { redis, reserve } from "./quota.js";

// A wish shared as a link (lamp.dev/w/<id>): only the idea, as the sharer confirmed it in Lamp. Its name, its line,
// its words and, if they kept them, a picture of it and its icon. No code and nothing else from their Mac: whoever
// opens the link makes their own version from the words. Lamp's side is Sources/Lamp/WishLink.swift; the two must
// agree on the limits.

/** The most each piece may hold. Lamp holds the sharer to the same numbers, so a longer one is refused, not cut. */
export const LIMITS = {
  name: 60,
  line: 140,
  words: 2000,
  picture: 1_500_000,
  icon: 300_000,
  /** Pixels on a side, for both pictures. */
  side: 4096,
};
/** Both pictures as base64 and the words, with room for the JSON around them. */
export const MAX_BODY_BYTES = 2_600_000;

// Enough to share and reshare a few wishes in an hour; overall, a ceiling on what a flood could store in a day.
export const QUOTAS = [
  { name: "share-ip", perIP: true, limit: 10, seconds: 3600 },
  { name: "share-hour", limit: 200, seconds: 3600 },
  { name: "share-day", limit: 1000, seconds: 86400 },
];
export const DELETE_QUOTAS = [{ name: "unshare-ip", perIP: true, limit: 60, seconds: 3600 }];

/** Ids are short enough to read in a link and long enough (about 58 bits) that nobody finds one by guessing. */
const ALPHABET = "23456789abcdefghijkmnpqrstuvwxyzABCDEFGHJKLMNPQRSTUVWXYZ";
export const ID_LENGTH = 10;
export const newID = () => Array.from({ length: ID_LENGTH }, () => ALPHABET[randomInt(ALPHABET.length)]).join("");
export const isID = (id) => typeof id === "string" && id.length === ID_LENGTH && [...id].every((c) => ALPHABET.includes(c));

/** The secret that lets the sharer's Lamp change or remove the link. Only its hash is kept here. */
export const newSecret = () => randomBytes(32).toString("base64url");
const hashSecret = (secret) => createHash("sha256").update(secret).digest("hex");
function secretMatches(secret, hash) {
  if (typeof secret !== "string" || !/^[A-Za-z0-9_-]{43}$/.test(secret) || typeof hash !== "string") return false;
  const a = Buffer.from(hashSecret(secret), "hex"), b = Buffer.from(hash, "hex");
  return a.length === b.length && timingSafeEqual(a, b);
}

/** Words as they're kept: no control characters (a line break only where lines are allowed), trimmed. Null when
 *  there's nothing, or more than `max` characters. */
export function tidy(value, max, { lines = false } = {}) {
  if (typeof value !== "string") return null;
  const spaced = value.replace(/\r\n?/g, "\n").replace(lines ? /\t/g : /[\t\n]/g, " ");
  const kept = [...spaced].filter((c) => (lines && c === "\n") || !/[\p{Cc}\p{Cf}\u2028\u2029]/u.test(c) || c === "\u200d").join("");
  const text = (lines ? kept.replace(/\n{3,}/g, "\n\n") : kept.replace(/\s+/g, " ")).trim();
  return text && characters(text) <= max ? text : null;
}

/** Characters as people see them (and as Swift counts them on Lamp's card): an accented letter or a family emoji
 *  made of several code points is one. */
const graphemes = new Intl.Segmenter("en", { granularity: "grapheme" });
export const characters = (text) => { let n = 0; for (const _ of graphemes.segment(text)) n++; return n; };

/** What a picture is, read from its first bytes: only a PNG or a JPEG of a sensible size. */
export function imageInfo(bytes) {
  if (bytes.length > 24 && bytes.readUInt32BE(0) === 0x89504e47 && bytes.readUInt32BE(4) === 0x0d0a1a0a && bytes.toString("latin1", 12, 16) === "IHDR") {
    return { type: "image/png", extension: "png", width: bytes.readUInt32BE(16), height: bytes.readUInt32BE(20) };
  }
  if (bytes.length > 4 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    // The frame's size is in its start-of-frame segment, found by walking the segments before it.
    let at = 2;
    while (at + 9 < bytes.length) {
      if (bytes[at] !== 0xff) return null;
      const marker = bytes[at + 1];
      if (marker === 0xff) { at += 1; continue; }
      const length = bytes.readUInt16BE(at + 2);
      if (length < 2) return null;
      if (marker >= 0xc0 && marker <= 0xcf && ![0xc4, 0xc8, 0xcc].includes(marker)) {
        return { type: "image/jpeg", extension: "jpg", width: bytes.readUInt16BE(at + 7), height: bytes.readUInt16BE(at + 5) };
      }
      at += 2 + length;
    }
  }
  return null;
}

function picture(value, max, { square = false } = {}) {
  if (value == null) return { bytes: null };
  if (typeof value !== "string" || !/^[A-Za-z0-9+/]+={0,2}$/.test(value) || value.length > Math.ceil(max / 3) * 4) return null;
  const bytes = Buffer.from(value, "base64");
  const info = imageInfo(bytes);
  if (!info || bytes.length > max || !info.width || !info.height || info.width > LIMITS.side || info.height > LIMITS.side) return null;
  if (square && (info.type !== "image/png" || info.width !== info.height)) return null;
  return { bytes, ...info };
}

/** What a share sends, checked. Null when anything is off. */
export function readShare(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const known = ["name", "line", "words", "picture", "icon"];
  if (Object.keys(body).some((key) => !known.includes(key))) return null;
  const name = tidy(body.name, LIMITS.name);
  const words = tidy(body.words, LIMITS.words, { lines: true });
  const line = body.line == null || body.line === "" ? "" : tidy(body.line, LIMITS.line);
  const shot = picture(body.picture, LIMITS.picture);
  const icon = picture(body.icon, LIMITS.icon, { square: true });
  if (!name || !words || line == null || !shot || !icon) return null;
  return { name, line, words, picture: shot.bytes ? shot : null, icon: icon.bytes ? icon : null };
}

/** What anyone may see of a shared wish: never its secret. */
export const shown = (record) => record && ({
  id: record.id, name: record.name, line: record.line, words: record.words,
  picture: record.picture, icon: record.icon, updated: record.updated,
});

/** The link people pass around. */
export const linkFor = (origin, id) => `${origin}/w/${id}`;

// MARK: Where shared wishes are kept

/**
 * The record of each shared wish in Upstash (the store the site's quotas already use), its pictures in Vercel
 * Blob, public at addresses with a random part. Preview deployments keep theirs apart from production's.
 */
export function cloudStore(env, fetcher = fetch) {
  const db = redis(env);
  const scope = env.VERCEL_ENV === "production" ? "production" : "preview";
  const key = (id) => `lamp:shared-wish:{${scope}}:${id}`;
  const command = async (args) => {
    const response = await fetcher(db.url, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(3000),
      headers: { Authorization: `Bearer ${db.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    if (!response.ok) throw new Error("Store unavailable");
    const body = await response.json();
    if (body.error) throw new Error("Store unavailable");
    return body.result;
  };
  const token = env.BLOB_READ_WRITE_TOKEN;
  return {
    limiter: { ...db, prefix: `lamp:shared-wish:{${scope}}:quota` },
    async get(id) {
      const text = await command(["GET", key(id)]);
      return typeof text === "string" ? JSON.parse(text) : null;
    },
    async create(record) { return (await command(["SET", key(record.id), JSON.stringify(record), "NX"])) === "OK"; },
    async replace(record) { await command(["SET", key(record.id), JSON.stringify(record), "XX"]); },
    async remove(id) { await command(["DEL", key(id)]); },
    async putImage(id, name, image) {
      if (!token) throw new Error("Store unavailable");
      const { put } = await import("@vercel/blob");
      const blob = await put(`${scope}/w/${id}/${name}.${image.extension}`, image.bytes, {
        access: "public", contentType: image.type, token, addRandomSuffix: true, cacheControlMaxAge: 300,
      });
      return blob.url;
    },
    async removeImages(urls) {
      if (!urls.length || !token) return;
      const { del } = await import("@vercel/blob");
      await del(urls, { token });
    },
    // The page and its card are cached by Vercel's CDN, tagged with the wish (see `cacheTags`): a change or a removal
    // takes them out at once rather than when they'd have run out.
    async forget(id) {
      try {
        const { dangerouslyDeleteByTag } = await import("@vercel/functions");
        await dangerouslyDeleteByTag(`wish-${id}`);
      } catch {}
    },
  };
}

/** Kept in memory, for `npm run dev` and the tests: pictures as data: URLs, so nothing else needs serving. */
export function memoryStore() {
  const records = new Map();
  return {
    limiter: null,
    records,
    async get(id) { return records.has(id) ? structuredClone(records.get(id)) : null; },
    async create(record) { if (records.has(record.id)) return false; records.set(record.id, structuredClone(record)); return true; },
    async replace(record) { if (records.has(record.id)) records.set(record.id, structuredClone(record)); },
    async remove(id) { records.delete(id); },
    async putImage(_id, _name, image) { return `data:${image.type};base64,${image.bytes.toString("base64")}`; },
    async removeImages() {},
    async forget() {},
  };
}

export const cacheTags = (id) => ({ "Vercel-Cache-Tag": `wish-${id}` });

// MARK: The API Lamp talks to

const reply = (status, body, headers = {}) => (body == null
  ? new Response(null, { status, headers: { "Cache-Control": "no-store", ...headers } })
  : Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers } }));

async function readBody(request) {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BODY_BYTES)) throw new RangeError();
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_BODY_BYTES) { await reader.cancel(); throw new RangeError(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.concat(chunks));
}

const bearer = (request) => /^Bearer (\S+)$/.exec(request.headers.get("authorization") || "")?.[1];

/**
 * POST shares a wish and answers its id, link and secret. PUT ?id= with the secret replaces what the link shows,
 * keeping the link; DELETE ?id= with the secret takes it down. Lamp is the only caller: a browser on another site
 * is refused, and nothing a request holds is logged.
 */
export function createShareHandler({ env = process.env, fetcher = fetch, store, limited = true, now = () => new Date() } = {}) {
  return async (request) => {
    const method = request.method;
    if (!["POST", "PUT", "DELETE"].includes(method)) return reply(405, { error: "method_not_allowed" }, { Allow: "POST, PUT, DELETE" });
    const url = new URL(request.url);
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });
    const id = url.searchParams.get("id");
    if (method !== "POST" && !isID(id)) return reply(404, { error: "not_found" });

    let share = null;
    if (method !== "DELETE") {
      if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") || "")) return reply(415, { error: "json_required" });
      try { share = readShare(JSON.parse(await readBody(request))); }
      catch (error) { return reply(error instanceof RangeError ? 413 : 400, { error: "invalid_wish" }); }
      if (!share) return reply(400, { error: "invalid_wish" });
    }

    let kept;
    try { kept = store ?? cloudStore(env, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }
    if (limited) {
      // Vercel overwrites these headers with the client's address. Only a keyed hash of it is kept, in expiring counters.
      const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
      if (!isIP(ip) || !kept.limiter) return reply(503, { error: "service_unavailable" });
      let retry;
      try { retry = await reserve(kept.limiter, ip, method === "DELETE" ? DELETE_QUOTAS : QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }

    let uploaded = [];
    try {
      const earlier = method === "POST" ? null : await kept.get(id);
      if (method !== "POST" && (!earlier || !secretMatches(bearer(request), earlier.secret))) return reply(404, { error: "not_found" });
      const oldImages = [earlier?.picture?.url, earlier?.icon?.url].filter(Boolean);
      if (method === "DELETE") {
        await kept.remove(id);
        await kept.removeImages(oldImages);
        await kept.forget(id);
        return reply(204);
      }

      const wishID = method === "POST" ? newID() : id;
      // Pictures go up before the record that names them; until it's kept they're taken back on any failure, or
      // they'd stay public with nothing that leads to them.
      uploaded = [];
      const put = async (name, image) => { const at = await kept.putImage(wishID, name, image); uploaded.push(at); return at; };
      const picture = share.picture && { url: await put("picture", share.picture), width: share.picture.width, height: share.picture.height };
      const icon = share.icon && { url: await put("icon", share.icon) };
      const time = now().toISOString();
      const words = { name: share.name, line: share.line, words: share.words, picture: picture || null, icon: icon || null };
      if (method === "PUT") {
        await kept.replace({ ...earlier, ...words, updated: time });
        uploaded = [];
        await kept.removeImages(oldImages);
        await kept.forget(id);
        return reply(200, { id, url: linkFor(url.origin, id) });
      }
      const secret = newSecret();
      if (!(await kept.create({ id: wishID, ...words, secret: hashSecret(secret), created: time, updated: time }))) {
        throw new Error("Id taken");
      }
      uploaded = [];
      return reply(201, { id: wishID, url: linkFor(url.origin, wishID), secret });
    } catch {
      try { await kept.removeImages(uploaded); } catch {}
      return reply(503, { error: "service_unavailable" });
    }
  };
}

/** A shared wish for the page and its card, or null when there's none by that id (or it can't be read now). */
export async function findWish(id, { env = process.env, fetcher = fetch, store } = {}) {
  if (!isID(id)) return null;
  try { return shown(await (store ?? cloudStore(env, fetcher)).get(id)); }
  catch { return undefined; }
}

/** Takes a shared wish down without its secret: for the Lamp team, when a link shows what it mustn't. */
export async function takeDown(id, { env = process.env, fetcher = fetch } = {}) {
  if (!isID(id)) return false;
  const kept = cloudStore(env, fetcher);
  const record = await kept.get(id);
  if (!record) return false;
  await kept.remove(id);
  await kept.removeImages([record.picture?.url, record.icon?.url].filter(Boolean));
  return true;
}
