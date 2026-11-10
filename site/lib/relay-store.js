import { createHash, createHmac, timingSafeEqual } from "node:crypto";
import { quotaScript } from "./quota.js";

// Where the relay keeps what it knows (RELAY.md): a Redis of its own in Upstash for rooms, codes, the request journal
// and each version's list of files, and a private Blob store of its own for the files. Neither is the shared wishes'
// database or store: a room holds a player's own changes, and it's cleared on its own schedule. Each has a stand-in
// kept in memory, with the same calls, for the tests and `npm run dev`.

// MARK: Redis

/**
 * A compare-and-set of a room: its JSON and its revision are written together, and only when the revision is still
 * the one the change was made from. Every change to a room goes through this, so two functions changing a room at
 * once never lose one of the changes: the one that loses reads the room again and tries again.
 * KEYS: room, revision. ARGV: the revision read, the room's JSON, the new revision, its lifetime in ms.
 */
export const casScript = `
if (redis.call('GET', KEYS[2]) or '0') ~= ARGV[1] then return 0 end
redis.call('SET', KEYS[1], ARGV[2], 'PX', ARGV[4])
redis.call('SET', KEYS[2], ARGV[3], 'PX', ARGV[4])
return 1
`;

/** The relay's Upstash database: RELAY_REDIS_REST_URL and RELAY_REDIS_REST_TOKEN, and nothing else's names. */
export function relayRedis(env, fetcher = fetch) {
  const url = env.RELAY_REDIS_REST_URL, token = env.RELAY_REDIS_REST_TOKEN;
  if (!url || !token || new URL(url).protocol !== "https:") throw new Error("Relay store unavailable");
  const scope = env.VERCEL_ENV === "production" ? "production" : "preview";
  const command = async (args) => {
    const response = await fetcher(url, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(3000),
      headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" }, body: JSON.stringify(args),
    });
    let body = null;
    try { body = await response.json(); } catch {}
    if (body?.error) throw new Error(`Relay store unavailable (${response.status}): ${String(body.error).slice(0, 200)}`);
    if (!response.ok || !body) throw new Error(`Relay store unavailable (${response.status})`);
    return body.result;
  };
  return {
    scope, command,
    // The quota counters (quota.js's `reserve` speaks to this): a keyed hash of an address, never the address.
    limiter: { url, token, prefix: `lamp:relay:{${scope}}:quota`, ipHash: (ip) => createHmac("sha256", token).update(ip).digest("hex") },
  };
}

/**
 * Redis in memory: the commands the relay sends, with its two scripts run as they run in Redis. Keys run out at their
 * time, read against `now`.
 */
export function memoryRedis({ now = () => Date.now() } = {}) {
  const values = new Map(), ends = new Map();
  const live = (key) => { if (ends.has(key) && ends.get(key) <= now()) { values.delete(key); ends.delete(key); } return values.has(key); };
  const get = (key) => (live(key) ? values.get(key) : null);
  const set = (key, value, ms) => { values.set(key, String(value)); if (ms) ends.set(key, now() + Number(ms)); else ends.delete(key); };
  const commands = {
    GET: ([key]) => get(key),
    MGET: (keys) => keys.map(get),
    SET: ([key, value, ...options]) => {
      const upper = options.map((option) => String(option).toUpperCase());
      if (upper.includes("NX") && live(key)) return null;
      const px = upper.indexOf("PX"), ex = upper.indexOf("EX");
      set(key, value, px >= 0 ? Number(options[px + 1]) : ex >= 0 ? Number(options[ex + 1]) * 1000 : 0);
      return "OK";
    },
    GETDEL: ([key]) => { const value = get(key); values.delete(key); ends.delete(key); return value; },
    DEL: (keys) => keys.reduce((n, key) => n + (values.delete(key) ? 1 : 0), 0),
    PEXPIRE: ([key, ms]) => { if (!live(key)) return 0; ends.set(key, now() + Number(ms)); return 1; },
    EXISTS: (keys) => keys.filter(live).length,
    EVAL: ([script, count, ...rest]) => {
      const keys = rest.slice(0, Number(count)), argv = rest.slice(Number(count));
      if (script === casScript) {
        if ((get(keys[1]) ?? "0") !== argv[0]) return 0;
        set(keys[0], argv[1], argv[3]);
        set(keys[1], argv[2], argv[3]);
        return 1;
      }
      if (script === quotaScript) {
        const n = keys.length;
        let retry = 0;
        keys.forEach((key, i) => { if (Number(get(key) ?? 0) >= Number(argv[i])) retry = Math.max(retry, Math.max(1, Math.ceil(((ends.get(key) ?? now()) - now()) / 1000))); });
        if (retry) return retry;
        keys.forEach((key, i) => { const v = Number(get(key) ?? 0) + 1; const end = ends.get(key); values.set(key, String(v)); if (v === 1) ends.set(key, now() + Number(argv[n + i]) * 1000); else if (end) ends.set(key, end); });
        return 0;
      }
      throw new Error("memoryRedis: unknown script");
    },
  };
  const ipHash = (ip) => createHash("sha256").update(`memory ${ip}`).digest("hex");
  return {
    scope: "memory", values,
    async command([name, ...args]) {
      const run = commands[String(name).toUpperCase()];
      if (!run) throw new Error(`memoryRedis: ${name} isn't kept here`);
      return run(args);
    },
    limiter: { memory: true, prefix: "lamp:relay:{memory}:quota", ipHash },
  };
}

// MARK: Blob

/** The Blob API's version this speaks, as @vercel/blob 2.8.2 sends it. */
const BLOB_API_VERSION = "13";
const BLOB_API = "https://vercel.com/api/blob";

/**
 * The relay's private Blob store: RELAY_BLOB_READ_WRITE_TOKEN. Each file's upload is given to the helper as an address
 * and the headers to send with it, under a client token that names that one file, its size and its type, ends in ten
 * minutes and can't overwrite. The helper sends the bytes straight to Blob, since a function takes at most 4.5 MB.
 */
export function relayBlobs(env) {
  const token = env.RELAY_BLOB_READ_WRITE_TOKEN;
  if (!token) throw new Error("Relay files unavailable");
  const storeId = token.split("_")[3];
  if (!storeId) throw new Error("Relay files unavailable");
  const blob = () => import("@vercel/blob");
  const client = () => import("@vercel/blob/client");
  return {
    async uploadTarget({ pathname, size, contentType, ms = 600_000 }) {
      const { generateClientTokenFromReadWriteToken } = await client();
      const clientToken = await generateClientTokenFromReadWriteToken({
        token, pathname, maximumSizeInBytes: Math.max(1, size), allowedContentTypes: [contentType],
        validUntil: Date.now() + ms, addRandomSuffix: false, allowOverwrite: false,
      });
      return {
        url: `${BLOB_API}/?${new URLSearchParams({ pathname })}`,
        headers: {
          authorization: `Bearer ${clientToken}`, "x-api-version": BLOB_API_VERSION, "x-vercel-blob-store-id": storeId,
          "x-vercel-blob-access": "private", "x-content-type": contentType, "x-content-length": String(size),
          "x-add-random-suffix": "0", "x-allow-overwrite": "0",
        },
      };
    },
    /** Keeps a file the relay itself copied (a room's version 1). */
    async put(pathname, bytes) {
      const { put } = await blob();
      await put(pathname, bytes, { access: "private", token, contentType: "application/octet-stream", addRandomSuffix: false, allowOverwrite: true });
    },
    /** The file as a stream with its size, or null when it isn't there. */
    async open(pathname) {
      const { get } = await blob();
      const found = await get(pathname, { access: "private", token, useCache: false }).catch(() => null);
      if (!found || found.statusCode === 404 || !found.stream) return null;
      return { body: found.stream, size: Number(found.blob?.size ?? found.headers?.get?.("content-length") ?? 0) };
    },
    async list(prefix) {
      const { list } = await blob();
      const all = [];
      let cursor;
      do {
        const page = await list({ prefix, cursor, limit: 1000, token });
        for (const one of page.blobs) all.push({ pathname: one.pathname, url: one.url, size: one.size, uploadedAt: new Date(one.uploadedAt).getTime() });
        cursor = page.hasMore ? page.cursor : undefined;
      } while (cursor);
      return all;
    },
    async remove(urls) {
      if (!urls.length) return;
      const { del } = await blob();
      for (let at = 0; at < urls.length; at += 500) await del(urls.slice(at, at + 500), { token });
    },
  };
}

/**
 * Blob in memory, with an upload address of its own for the helper (`upload`, served by whoever runs it: the dev
 * server answers `/__relay-blob/`). Its tokens are signed here and say what Blob's client tokens say: one file, its
 * size and type, until when, and never over a file that's there.
 */
export function memoryBlobs({ origin, secret = "memory-blob-secret", now = () => Date.now() } = {}) {
  const files = new Map();   // pathname → { bytes, contentType, uploadedAt }
  const sign = (payload) => createHmac("sha256", secret).update(payload).digest("hex");
  const store = {
    files,
    async uploadTarget({ pathname, size, contentType, ms = 600_000 }) {
      const payload = Buffer.from(JSON.stringify({ pathname, size, contentType, validUntil: now() + ms })).toString("base64url");
      return { url: `${typeof origin === "function" ? origin() : origin}/__relay-blob/?${new URLSearchParams({ pathname })}`, headers: { authorization: `Bearer ${sign(payload)}.${payload}`, "x-content-type": contentType, "x-content-length": String(size) } };
    },
    async put(pathname, bytes) { files.set(pathname, { bytes: Buffer.from(bytes), contentType: "application/octet-stream", uploadedAt: now() }); },
    async open(pathname) { const file = files.get(pathname); return file ? { body: file.bytes, size: file.bytes.length } : null; },
    async list(prefix) { return [...files].filter(([path]) => path.startsWith(prefix)).map(([pathname, file]) => ({ pathname, url: pathname, size: file.bytes.length, uploadedAt: file.uploadedAt })); },
    async remove(urls) { for (const url of urls) files.delete(url); },
    /** The upload address: a PUT the token allows, as Blob answers one. */
    async upload(request) {
      if (request.method !== "PUT") return new Response(null, { status: 405 });
      const pathname = new URL(request.url).searchParams.get("pathname") ?? "";
      const [signature, payload] = (/^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "")?.[1] ?? "").split(".");
      const ok = signature && payload && signature.length === 64 && timingSafeEqual(Buffer.from(signature), Buffer.from(sign(payload)));
      const said = ok ? JSON.parse(Buffer.from(payload, "base64url").toString("utf8")) : null;
      if (!said || said.pathname !== pathname || said.validUntil < now()) return Response.json({ error: { code: "forbidden" } }, { status: 403 });
      if (request.headers.get("x-content-type") !== said.contentType) return Response.json({ error: { code: "content_type_not_allowed" } }, { status: 400 });
      if (files.has(pathname)) return Response.json({ error: { code: "file_already_exists" } }, { status: 400 });
      const bytes = Buffer.from(await request.arrayBuffer());
      if (bytes.length > said.size) return Response.json({ error: { code: "file_too_large" } }, { status: 400 });
      files.set(pathname, { bytes, contentType: said.contentType, uploadedAt: now() });
      return Response.json({ pathname, contentType: said.contentType });
    },
  };
  return store;
}
