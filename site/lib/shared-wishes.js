import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { isIP } from "node:net";
import { redis, reserve } from "./quota.js";

// A wish shared as a link (lamp.dev/w/<id>): the idea, as the sharer confirmed it in Lamp. Its name, its line,
// its words and, if they kept them, a picture of it and its icon; whoever opens the link makes their own version from
// the words. If the sharer chose to, the wish itself goes too, as the shared file Lamp makes (`<name>.lampapp`,
// `createFileHandler`): then the page offers that exact wish to anyone with Lamp, which reviews it before it opens, as
// any shared file. Lamp's side is Sources/Lamp/WishLink.swift; the two must agree on the limits.

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

/** The wish itself, a shared file: sent in parts, since a request to a function holds 4.5 MB at most. */
export const FILE_LIMITS = { part: 3_000_000, parts: 6, total: 16_000_000 };

// Enough to share and reshare a few wishes in an hour; overall, a ceiling on what a flood could store in a day.
export const QUOTAS = [
  { name: "share-ip", perIP: true, limit: 10, seconds: 3600 },
  { name: "share-hour", limit: 200, seconds: 3600 },
  { name: "share-day", limit: 1000, seconds: 86400 },
];
export const DELETE_QUOTAS = [{ name: "unshare-ip", perIP: true, limit: 60, seconds: 3600 }];
/** A file's parts: a few files' worth an hour from one address. Putting the parts together counts as a share. */
export const PART_QUOTAS = [
  { name: "part-ip", perIP: true, limit: 40, seconds: 3600 },
  { name: "part-day", limit: 3000, seconds: 86400 },
];

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
  picture: record.picture, icon: record.icon, file: record.file ?? null, updated: record.updated,
});

/** Every file kept for a record: its pictures, the wish's file and any parts of one still being sent. */
const blobsOf = (record) => [record?.picture?.url, record?.icon?.url, record?.file?.url, ...Object.values(record?.parts?.urls ?? {})].filter(Boolean);

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
  // A store connected now gives the project its id (BLOB_STORE_ID), and @vercel/blob signs in with the deployment's
  // own OIDC token; an older connection gave a read-write token instead.
  const auth = env.BLOB_READ_WRITE_TOKEN ? { token: env.BLOB_READ_WRITE_TOKEN } : {};
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
      const { put } = await import("@vercel/blob");
      const blob = await put(`${scope}/w/${id}/${name}.${image.extension}`, image.bytes, {
        access: "public", contentType: image.type, addRandomSuffix: true, cacheControlMaxAge: 300, ...auth,
      });
      return blob.url;
    },
    async removeImages(urls) {
      if (!urls.length) return;
      const { del } = await import("@vercel/blob");
      await del(urls, auth);
    },
    // A part of the wish's file, or the file once its parts are together: public at an address with a random part, as
    // the pictures are, and only ever read back from the store's own host.
    async putFile(id, name, bytes) {
      const { put } = await import("@vercel/blob");
      const blob = await put(`${scope}/w/${id}/${name}`, bytes, {
        access: "public", contentType: "application/octet-stream", addRandomSuffix: true, cacheControlMaxAge: 300, ...auth,
      });
      return blob.url;
    },
    async readFile(url) {
      const address = new URL(url);
      if (address.protocol !== "https:" || !address.hostname.endsWith(".public.blob.vercel-storage.com")) throw new Error("Not the store's");
      const response = await fetcher(url, { redirect: "error", signal: AbortSignal.timeout(10000) });
      if (!response.ok) throw new Error("Part unavailable");
      return Buffer.from(await response.arrayBuffer());
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
    async putFile(_id, _name, bytes) { return `data:application/octet-stream;base64,${bytes.toString("base64")}`; },
    async readFile(url) { return Buffer.from(url.slice(url.indexOf(",") + 1), "base64"); },
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
        await kept.removeImages(blobsOf(earlier));
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
  await kept.removeImages(blobsOf(record));
  await kept.forget(id);
  return true;
}

// MARK: The wish itself

/** A shared file Lamp made: a zip whose listing names lamp-app.json, the file every shared wish has at its root. */
export function isWishFile(bytes) {
  if (bytes.length < 22 || bytes.readUInt32LE(0) !== 0x04034b50) return false;
  // The central directory's entries, from the end record backwards: only a name, not what's in it, is read here; Lamp
  // reads and reviews the rest when the file is opened.
  const from = Math.max(0, bytes.length - 65_557);
  const end = bytes.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (end < from) return false;
  const size = bytes.readUInt32LE(end + 12), offset = bytes.readUInt32LE(end + 16);
  if (offset + size > end) return false;
  for (let at = offset; at + 46 <= offset + size;) {
    if (bytes.readUInt32LE(at) !== 0x02014b50) return false;
    const nameLength = bytes.readUInt16LE(at + 28), extra = bytes.readUInt16LE(at + 30), comment = bytes.readUInt16LE(at + 32);
    if (bytes.toString("utf8", at + 46, at + 46 + nameLength) === "lamp-app.json") return true;
    at += 46 + nameLength + extra + comment;
  }
  return false;
}

/** The file's name where it's downloaded: the wish's name, made safe for an address. */
export const fileName = (name) => `${(name.normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-").toLowerCase() || "wish").slice(0, 60)}.lampapp`;

/**
 * The wish's own file, for a link that has one, only with the link's secret. PUT ?id=&part=<n>&of=<count> sends one part
 * (raw bytes, at most `FILE_LIMITS.part`); POST ?id= puts the parts together, checks that it's a file Lamp made and
 * within `FILE_LIMITS.total`, and gives it to the link in place of any it had; DELETE ?id= takes it away. The parts
 * are taken away once they're together, or with the link.
 */
export function createFileHandler({ env = process.env, fetcher = fetch, store, limited = true, now = () => new Date() } = {}) {
  return async (request) => {
    const method = request.method;
    if (!["PUT", "POST", "DELETE"].includes(method)) return reply(405, { error: "method_not_allowed" }, { Allow: "PUT, POST, DELETE" });
    const url = new URL(request.url);
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });
    const id = url.searchParams.get("id");
    if (!isID(id)) return reply(404, { error: "not_found" });

    let part = null;
    if (method === "PUT") {
      const n = Number(url.searchParams.get("part")), of = Number(url.searchParams.get("of"));
      if (!Number.isInteger(of) || of < 1 || of > FILE_LIMITS.parts || !Number.isInteger(n) || n < 0 || n >= of) return reply(400, { error: "invalid_part" });
      if (!/^application\/octet-stream$/i.test(request.headers.get("content-type") || "")) return reply(415, { error: "bytes_required" });
      const length = request.headers.get("content-length");
      if (length && (!/^\d+$/.test(length) || Number(length) > FILE_LIMITS.part)) return reply(413, { error: "part_too_large" });
      const bytes = Buffer.from(await request.arrayBuffer());
      if (!bytes.length || bytes.length > FILE_LIMITS.part) return reply(bytes.length ? 413 : 400, { error: "invalid_part" });
      part = { n, of, bytes };
    }

    let kept;
    try { kept = store ?? cloudStore(env, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }
    if (limited) {
      const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
      if (!isIP(ip) || !kept.limiter) return reply(503, { error: "service_unavailable" });
      let retry;
      try { retry = await reserve(kept.limiter, ip, method === "PUT" ? PART_QUOTAS : method === "POST" ? QUOTAS : DELETE_QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }

    let uploaded = [];
    try {
      const record = await kept.get(id);
      if (!record || !secretMatches(bearer(request), record.secret)) return reply(404, { error: "not_found" });
      if (method === "PUT") {
        // A new count starts a new file: parts of an earlier one that never came together go.
        const parts = record.parts?.of === part.of ? record.parts : { of: part.of, urls: {} };
        const stale = record.parts && record.parts !== parts ? Object.values(record.parts.urls) : [];
        const replaced = parts.urls[part.n];
        const at = await kept.putFile(id, `part-${part.n}`, part.bytes);
        uploaded.push(at);
        await kept.replace({ ...record, parts: { of: parts.of, urls: { ...parts.urls, [part.n]: at } } });
        uploaded = [];
        await kept.removeImages([...stale, replaced].filter(Boolean));
        return reply(204);
      }
      if (method === "DELETE") {
        const gone = [record.file?.url, ...Object.values(record.parts?.urls ?? {})].filter(Boolean);
        const { file: _file, parts: _parts, ...rest } = record;
        await kept.replace({ ...rest, file: null, updated: now().toISOString() });
        await kept.removeImages(gone);
        await kept.forget(id);
        return reply(204);
      }
      const parts = record.parts;
      if (!parts || Object.keys(parts.urls).length !== parts.of) return reply(409, { error: "parts_missing" });
      const pieces = [];
      for (let n = 0; n < parts.of; n++) pieces.push(await kept.readFile(parts.urls[n]));
      const bytes = Buffer.concat(pieces);
      if (bytes.length > FILE_LIMITS.total) return reply(413, { error: "file_too_large" });
      if (!isWishFile(bytes)) return reply(400, { error: "invalid_file" });
      const at = await kept.putFile(id, fileName(record.name), bytes);
      uploaded.push(at);
      const { parts: _parts, ...rest } = record;
      await kept.replace({ ...rest, file: { url: at, size: bytes.length }, updated: now().toISOString() });
      uploaded = [];
      await kept.removeImages([record.file?.url, ...Object.values(parts.urls)].filter(Boolean));
      await kept.forget(id);
      return reply(200, { url: at, size: bytes.length });
    } catch {
      try { await kept.removeImages(uploaded); } catch {}
      return reply(503, { error: "service_unavailable" });
    }
  };
}
