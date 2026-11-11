import { createHash, createHmac, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { isIP } from "node:net";
import { inflateRawSync } from "node:zlib";
import { redis, reserve } from "./quota.js";

// A wish shared as a link (lamp.dev/w/<id>): the idea, as the sharer confirmed it in Lamp. Its name, its line,
// its words and, if they kept them, a picture of it and its icon; whoever opens the link makes their own version from
// the words. If the sharer chose to, the wish itself goes too, as the shared file Lamp makes (`<name>.lampapp`,
// `createFileHandler`): then the page offers that exact wish to anyone with Lamp, which reviews it before it opens, as
// any shared file. Lamp's side is Sources/Lamp/WishLink.swift; the two must agree on the limits.

/** The most each piece may hold. Lamp holds the sharer to the same numbers, so a longer one is refused, not cut. */
export const LIMITS = {
  name: 60,
  /** Who shared it, as they want to be named on its page: their name, or nothing. */
  by: 60,
  line: 140,
  words: 2000,
  /** The changes Lamp suggests for the wish (`RemixSuggestions`), each a line; the page offers them to remix with. */
  ideas: 3,
  idea: 100,
  /** The questions the box under the app asks in turn, where people send its maker ideas ("Found a bug?"). */
  asks: 3,
  ask: 80,
  /** A playing page's shape, its width over its height (`shape`), within these; or "fill", a page that takes any. */
  shape: [0.2, 5],
  /** What's new in each version the sharer released (`releases`), newest first: the most kept, the lines each holds
   *  and the characters in a line. Lamp writes the lines; the sharer can change them before they go. */
  releases: 30,
  releaseLines: 5,
  releaseLine: 120,
  picture: 1_500_000,
  icon: 300_000,
  /** Pixels on a side, for both pictures. */
  side: 4096,
};
/** Both pictures as base64 and the words, with room for the JSON around them. */
export const MAX_BODY_BYTES = 2_600_000;

/** The wish itself, a shared file: sent in parts, since a request to a function holds 4.5 MB at most. */
export const FILE_LIMITS = { part: 3_000_000, parts: 16, total: 48_000_000 };

// Enough to share and reshare a few wishes in an hour; overall, a ceiling on what a flood could store in a day.
export const QUOTAS = [
  { name: "share-ip", perIP: true, limit: 10, seconds: 3600 },
  { name: "share-hour", limit: 200, seconds: 3600 },
  { name: "share-day", limit: 1000, seconds: 86400 },
];
export const DELETE_QUOTAS = [{ name: "unshare-ip", perIP: true, limit: 60, seconds: 3600 }];
/**
 * Changing a link that's out (its secret shown to the site) and putting its file and page together: kept apart from
 * new links, so someone working on a wish can update it again and again without running out of shares. An update
 * counts up to three here (the link, its file, its page). Overall, a ceiling on what a flood could rewrite in a day.
 */
export const UPDATE_QUOTAS = [
  { name: "update-ip", perIP: true, limit: 90, seconds: 3600 },
  { name: "update-day", limit: 5000, seconds: 86400 },
];
/** A file's parts: a few files' worth an hour from one address. Putting the parts together counts as an update. */
export const PART_QUOTAS = [
  // A share sends the file and its page, each in up to `FILE_LIMITS.parts` parts.
  { name: "part-ip", perIP: true, limit: 200, seconds: 3600 },
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

/** A release as it's kept: when it went out (an ISO time, never more than a day ahead) and its lines. Null when off. */
function release(value) {
  if (!value || typeof value !== "object" || Array.isArray(value) || Object.keys(value).some((key) => !["date", "lines"].includes(key))) return null;
  const time = typeof value.date === "string" && /^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d+)?Z$/.test(value.date) ? Date.parse(value.date) : NaN;
  if (!Number.isFinite(time) || time > Date.now() + 86_400_000) return null;
  if (!Array.isArray(value.lines) || !value.lines.length || value.lines.length > LIMITS.releaseLines) return null;
  const lines = value.lines.map((line) => tidy(line, LIMITS.releaseLine));
  return lines.includes(null) ? null : { date: new Date(time).toISOString(), lines };
}

/** What a share sends, checked. Null when anything is off. `releases` is undefined when the share didn't say (a Lamp
 *  from before them), so a change keeps the ones the link has. */
const GITHUB_REPO = /^[A-Za-z0-9](?:[A-Za-z0-9-]{0,38})\/(?!\.\.?$)[A-Za-z0-9._-]{1,100}$/;
export function readShare(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const known = ["name", "by", "line", "words", "ideas", "asks", "shape", "releases", "picture", "icon", "github"];
  if (Object.keys(body).some((key) => !known.includes(key))) return null;
  const name = tidy(body.name, LIMITS.name);
  const words = tidy(body.words, LIMITS.words, { lines: true });
  const line = body.line == null || body.line === "" ? "" : tidy(body.line, LIMITS.line);
  const by = body.by == null || body.by === "" ? "" : tidy(body.by, LIMITS.by);
  const ideas = body.ideas == null ? [] : Array.isArray(body.ideas) && body.ideas.length <= LIMITS.ideas
    ? body.ideas.map((idea) => tidy(idea, LIMITS.idea)) : [null];
  const asks = body.asks == null ? [] : Array.isArray(body.asks) && body.asks.length <= LIMITS.asks
    ? body.asks.map((ask) => tidy(ask, LIMITS.ask)) : [null];
  const shape = body.shape == null ? null : body.shape === "fill" ? "fill"
    : typeof body.shape === "number" && body.shape >= LIMITS.shape[0] && body.shape <= LIMITS.shape[1] ? Math.round(body.shape * 10000) / 10000 : undefined;
  const releases = body.releases === undefined ? undefined : Array.isArray(body.releases) && body.releases.length <= LIMITS.releases
    ? body.releases.map(release) : [null];
  const shot = picture(body.picture, LIMITS.picture);
  const icon = picture(body.icon, LIMITS.icon, { square: true });
  // The app's public repository on GitHub, as "owner/name", which the page links to: nothing else is taken.
  const github = body.github == null || body.github === "" ? null : GITHUB_REPO.test(body.github) ? body.github : undefined;
  if (!name || !words || line == null || by == null || ideas.includes(null) || asks.includes(null) || shape === undefined || releases?.includes(null) || !shot || !icon || github === undefined) return null;
  return { name, by, line, words, ideas, asks, shape, releases: releases?.sort((a, b) => b.date.localeCompare(a.date)),
    picture: shot.bytes ? shot : null, icon: icon.bytes ? icon : null, github };
}

/** What anyone may see of a shared wish: never its secret. */
export const shown = (record) => record && ({
  id: record.id, name: record.name, by: record.by ?? "", line: record.line, words: record.words, ideas: record.ideas ?? [], asks: record.asks ?? [], shape: record.shape ?? null,
  releases: record.releases ?? [], picture: record.picture, icon: record.icon, file: record.file ?? null, updated: record.updated, github: record.github ?? null,
  page: record.page ? { version: record.page.version } : null,
});

/** Every file kept for a record: its pictures, the wish's file and any parts of one still being sent. */
const blobsOf = (record) => [record?.picture?.url, record?.icon?.url, record?.file?.url, ...partBlobs(record?.parts),
  ...pageBlobs(record), ...partBlobs(record?.pageParts)].filter(Boolean);
/** A file's parts so far, and those set aside (`spare`): replaced by a part sent again, or left by an earlier count. */
const partBlobs = (parts) => [...Object.values(parts?.urls ?? {}), ...(parts?.spare ?? [])];
/** The page's files, and the version before it, kept for whoever was still playing that when this one went up. */
const pageBlobs = (record) => [...Object.values(record?.page?.files ?? {}), ...Object.values(record?.previousPage?.files ?? {})];

/**
 * What anyone's Lamp asks of a link it follows (`GET /api/wishes?id=`): the format of the answer, and the version of
 * the wish's file, which goes up each time the sharer sends it again (Release Update), with the file's address. Version 0
 * and no file for a link that carries none, and who it's by as the page names them (empty for nobody), which Lamp keeps
 * with what it pulls in from the copy so the change can credit them. Never the secret or anything a follower doesn't need.
 */
export const FOLLOW_FORMAT = 1;
export const latest = (record) => ({
  format: FOLLOW_FORMAT, id: record.id, name: record.name, by: record.by ?? "",
  version: record.file ? (record.file.version ?? 1) : 0, file: record.file?.url ?? null,
});

/**
 * The wish's name as its link spells it ("Falling Blocks" → "falling-blocks"), so a link says what it's for. Only for
 * reading: the id finds the wish (`wishIDFrom`), so a link with an old name or none still works. Empty for a name with
 * no letters or digits in plain Latin.
 */
export const slugFor = (name) => (name ?? "").normalize("NFKD").replace(/[\u0300-\u036f]/g, "")
  .replace(/[^A-Za-z0-9]+/g, "-").toLowerCase().replace(/^-+/, "").slice(0, 48).replace(/-+$/, "");

/** The link people pass around: the wish's id, then its name after a dash (`/w/JP2R862d45-falling-blocks`). */
export const linkFor = (origin, id, name) => {
  const slug = slugFor(name);
  return `${origin}/w/${id}${slug ? `-${slug}` : ""}`;
};

/** The wish's id in its link's last part, whatever name follows it after a dash. Null when it doesn't start with one. */
export const wishIDFrom = (part) => {
  const id = typeof part === "string" ? part.slice(0, ID_LENGTH) : null;
  return isID(id) && (part.length === ID_LENGTH || part[ID_LENGTH] === "-") ? id : null;
};

// MARK: Where shared wishes are kept

/**
 * The record of each shared wish in Upstash (the store the site's quotas already use), its pictures in Vercel
 * Blob, public at addresses with a random part. Preview deployments keep theirs apart from production's.
 */
/**
 * A write to the blob store that answers in time: one that hasn't after `seconds` is cancelled and tried again, a few
 * times, since a write that never answers held a whole page up until its function's time ran out.
 */
async function inTime(write, { seconds = 30, tries = 3, what = "a file" } = {}) {
  for (let attempt = 1; ; attempt++) {
    // Given up on at its time whatever the blob library is doing: its own retries of a failed request wait between
    // tries and don't hear a cancel then, so a write that keeps failing could otherwise hold on for minutes.
    const signal = AbortSignal.timeout(seconds * 1000);
    let timer;
    const late = new Promise((_, failed) => { timer = setTimeout(() => failed(new Error(`no answer in ${seconds}s`)), seconds * 1000 + 1000); });
    try { return await Promise.race([write(signal), late]); } catch (error) {
      if (attempt >= tries) throw error;
      console.warn(`Storing ${what} again (try ${attempt + 1} of ${tries}): ${error?.message ?? error}`);
    } finally { clearTimeout(timer); }
  }
}

export function cloudStore(env, fetcher = fetch) {
  // The blob library tries a failed request again 10 times by default, waiting longer each time; `inTime` tries again
  // itself, and says why, so the library's own are few.
  process.env.VERCEL_BLOB_RETRIES ??= "2";
  const db = redis(env);
  const scope = env.VERCEL_ENV === "production" ? "production" : "preview";
  const key = (id) => `lamp:shared-wish:{${scope}}:${id}`;
  const ideasKey = (id) => `lamp:shared-wish:{${scope}}:ideas:${id}`;
  const mailKey = (box) => `lamp:shared-wish:{${scope}}:idea-mail:${box}`;
  const makerKey = (id) => `lamp:shared-wish:{${scope}}:maker:${id}`;
  const command = async (args) => {
    const response = await fetcher(db.url, {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(3000),
      headers: { Authorization: `Bearer ${db.token}`, "Content-Type": "application/json" },
      body: JSON.stringify(args),
    });
    // Upstash's own words for it (a limit reached, say), which name no key: it gives them with a status that isn't
    // OK too, so the answer is read either way, and the status alone says it when there are none.
    let body = null;
    try { body = await response.json(); } catch {}
    if (body?.error) throw new Error(`Store unavailable (${response.status}): ${String(body.error).slice(0, 200)}`);
    if (!response.ok || !body) throw new Error(`Store unavailable (${response.status})`);
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
    /** False when the record is gone (taken down meanwhile): nothing was written. */
    async replace(record) { return (await command(["SET", key(record.id), JSON.stringify(record), "XX"])) === "OK"; },
    /** Writes `after` only while the record is still `before` as read: false when it changed meanwhile, or is gone. */
    async swap(before, after) {
      return (await command(["EVAL", "if redis.call('GET', KEYS[1]) == ARGV[1] then return redis.call('SET', KEYS[1], ARGV[2]) end return false",
        "1", key(after.id), JSON.stringify(before), JSON.stringify(after)])) === "OK";
    },
    async remove(id) { await command(["DEL", key(id), ideasKey(id), makerKey(id)]); },
    /** The maker's own address for a link's ideas, as `{ email, confirmed, key }`, or null. */
    async maker(id) { const text = await command(["GET", makerKey(id)]); return typeof text === "string" ? JSON.parse(text) : null; },
    async setMaker(id, value) { await command(value ? ["SET", makerKey(id), JSON.stringify(value)] : ["DEL", makerKey(id)]); },
    /** Confirms ("confirm") or lets go ("stop") the maker's address in one step, only while `key` is still its key. */
    async makerStep(id, key, step) {
      await command(["EVAL", `local text = redis.call('GET', KEYS[1])
        if not text then return 0 end
        local maker = cjson.decode(text)
        if maker.key ~= ARGV[1] then return 0 end
        if ARGV[2] == "confirm" then
          maker.confirmed = true
          redis.call('SET', KEYS[1], cjson.encode(maker))
        else redis.call('DEL', KEYS[1]) end
        return 1`, "1", makerKey(id), key, step]);
    },
    /** Keeps an idea for the link, numbered in the order they came: null when the link already holds `IDEA_LIMITS.kept`. */
    async addIdea(id, idea) {
      // Its number is its field, given as it's kept, so two at once never share one. The cap counts those still open
      // (`open`, which an outcome counts down), so a maker who deals with them makes room; and, far above it, all kept.
      const n = await command(["EVAL", `if tonumber(redis.call('HGET', KEYS[1], 'open') or '0') >= tonumber(ARGV[1]) then return false end
        if redis.call('HLEN', KEYS[1]) > 10 * tonumber(ARGV[1]) then return false end
        redis.call('HINCRBY', KEYS[1], 'open', 1)
        local n = redis.call('HINCRBY', KEYS[1], 'next', 1)
        redis.call('HSET', KEYS[1], tostring(n), ARGV[2])
        return n`, "1", ideasKey(id), String(IDEA_LIMITS.kept), JSON.stringify(idea)]);
      return Number.isInteger(n) ? n : null;
    },
    async ideas(id) {
      const flat = (await command(["HGETALL", ideasKey(id)])) ?? [];
      const ideas = [];
      for (let i = 0; i < flat.length; i += 2) if (flat[i] !== "next" && flat[i] !== "open") ideas.push({ ...JSON.parse(flat[i + 1]), n: Number(flat[i]) });
      return ideas.sort((a, b) => a.n - b.n);
    },
    /** True when this call took it away: two at once never both do. */
    async removeIdea(id, n) { return (await command(["HDEL", ideasKey(id), String(n)])) === 1; },
    /**
     * Gives idea `n` its outcome ("in" or "dismissed"), with the maker's note to its sender as the first of its thread
     * if they wrote one, in one step, and answers it as it was, its address included, to whichever call gave it: null
     * when it's gone or already has one, so it's told once. The picture goes with this step, and the address too when
     * it's dismissed with nothing said, since nothing more will be written to it.
     */
    async finishIdea(id, n, status, at, message) {
      const text = await command(["EVAL", `local text = redis.call('HGET', KEYS[1], ARGV[1])
        if not text then return false end
        local idea = cjson.decode(text)
        if idea.status then return false end
        idea.status = ARGV[2]
        idea.done = ARGV[3]
        idea.last = ARGV[3]
        idea.picture = nil
        idea.waiting = nil
        if ARGV[4] ~= "" then
          local thread = idea.thread or {}
          table.insert(thread, cjson.decode(ARGV[4]))
          idea.thread = thread
        end
        if ARGV[2] == "dismissed" and not idea.thread then idea.email = nil end
        redis.call('HSET', KEYS[1], ARGV[1], cjson.encode(idea))
        redis.call('HINCRBY', KEYS[1], 'open', -1)
        return text`, "1", ideasKey(id), String(n), status, at, message ? JSON.stringify(message) : ""]);
      return typeof text === "string" ? { ...JSON.parse(text), n } : null;
    },
    /**
     * One step in an idea's conversation, answering the idea as it was before it, or null when it's gone or the step
     * doesn't apply: "say" adds a message to its thread (one of a message id already there, or past
     * `IDEA_LIMITS.thread`, doesn't), and an answer from its sender leaves it waiting on the maker; "settle" says the
     * maker has seen to it; "box" gives it its mailbox and the subject of the first email, unless another call gave it
     * one first (whose is in what's answered), and "makerbox" the same for its maker's mailbox; "stop", with its mailbox,
     * lets its address go.
     */
    async talk(id, n, op, value = "", extra = "") {
      const text = await command(["EVAL", `local text = redis.call('HGET', KEYS[1], ARGV[1])
        if not text then return false end
        local idea = cjson.decode(text)
        local op = ARGV[2]
        if op == "say" then
          local said = cjson.decode(ARGV[3])
          -- A note given before ideas had threads starts its thread.
          if idea.note and not idea.thread then
            idea.thread = {{by = "maker", text = idea.note, at = idea.done or idea.at}}
            idea.note = nil
          end
          local thread = idea.thread or {}
          if #thread >= tonumber(ARGV[4]) then return false end
          for _, one in ipairs(thread) do
            if (said.mid and one.mid == said.mid) or (said.via and one.via == said.via) then return false end
          end
          table.insert(thread, said)
          idea.thread = thread
          idea.last = said.at
          if said.by == "sender" then idea.waiting = true else idea.waiting = nil end
        elseif op == "settle" then idea.waiting = nil
        elseif op == "box" then
          if idea.mailbox then return text end
          idea.mailbox = ARGV[3]; idea.subject = ARGV[4]
        elseif op == "makerbox" then
          if idea.makerBox then return text end
          idea.makerBox = ARGV[3]
        elseif op == "stop" then
          if idea.mailbox ~= ARGV[3] then return false end
          idea.email = nil
        else return false end
        redis.call('HSET', KEYS[1], ARGV[1], cjson.encode(idea))
        return text`, "1", ideasKey(id), String(n), op, typeof value === "string" ? value : JSON.stringify(value), String(extra || IDEA_LIMITS.thread)]);
      return typeof text === "string" ? { ...JSON.parse(text), n } : null;
    },
    /**
     * An idea's mailbox: the address replies to its emails come to, kept a while past the last of them. Each idea has
     * one for its sender's replies and, once its maker has emails of their own, one for the maker's (`side` "maker").
     */
    async openMailbox(id, n, side = "sender") {
      const box = randomBytes(10).toString("hex");
      await command(["SET", mailKey(box), `${id}:${n}${side === "maker" ? ":maker" : ""}`, "EX", String(MAILBOX_SECONDS)]);
      return box;
    },
    async mailbox(box) {
      const found = await command(["GETEX", mailKey(box), "EX", String(MAILBOX_SECONDS)]);
      const [id, n, side] = typeof found === "string" ? found.split(":") : [];
      return isID(id) && /^\d+$/.test(n ?? "") ? { id, n: Number(n), side: side === "maker" ? "maker" : "sender" } : null;
    },
    async closeMailbox(box) { await command(["DEL", mailKey(box)]); },
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
      const blob = await inTime((abortSignal) => put(`${scope}/w/${id}/${name}`, bytes, {
        access: "public", contentType: "application/octet-stream", addRandomSuffix: true, cacheControlMaxAge: 300, abortSignal, ...auth,
      }), { seconds: 60, what: name });
      return blob.url;
    },
    // One file of a playable page, under the version's own random folder: read back by the play handler, never served
    // from Blob itself (which hands HTML out as a download).
    async putPageFile(id, token, path, bytes) {
      const { put } = await import("@vercel/blob");
      const blob = await inTime((abortSignal) => put(`${scope}/w/${id}/page/${token}/${path}`, bytes, {
        // Kept as what it is, so a browser sent straight to a big one (`DIRECT_FILE`) runs or reads it. Written again
        // in place when a try was cancelled after it got there.
        access: "public", contentType: pageType(path), addRandomSuffix: false, allowOverwrite: true, cacheControlMaxAge: 300, abortSignal, ...auth,
      }), { seconds: 30, what: path });
      return blob.url;
    },
    async readFile(url) {
      const { body } = await this.openFile(url);
      return Buffer.from(await new Response(body).arrayBuffer());
    },
    // A page's file as it comes, passed on without being held whole: a big one (a game's map data, tens of MB) is more
    // than a function's answer may hold at once, and more than it can read in the time a whole read is given.
    // A small one is kept in the instance after its first read (`remembered`): a page's files never change, and a game
    // asks for some many times over (a worker's script, under an address of its own each time), which the CDN can't
    // keep. The store turns this function's reads away for a while when they come in bursts (403), and asking again
    // soon only keeps that going: a refused read is asked once more, a second later, and said with what the store
    // gave as its reason.
    async openFile(url) {
      const address = new URL(url);
      if (address.protocol !== "https:" || !address.hostname.endsWith(".public.blob.vercel-storage.com")) throw new Error("Not the store's");
      const kept = remembered.get(url);
      if (kept) { remembered.delete(url); remembered.set(url, kept); return { body: kept, length: String(kept.length) }; }
      let said = null;
      for (let attempt = 1; attempt <= 2; attempt++) {
        if (attempt > 1) await new Promise((done) => setTimeout(done, 1000 + Math.random() * 500));
        // The time limit is for the store to start answering: a big file's body may take longer to pass on.
        const waiting = new AbortController();
        const timer = setTimeout(() => waiting.abort(), 10000);
        let response;
        try { response = await fetcher(url, { redirect: "error", signal: waiting.signal }); }
        catch (error) { said = error?.message ?? String(error); continue; }
        finally { clearTimeout(timer); }
        const length = response.headers.get("content-length");
        if (response.ok && response.body) {
          if (length === null || Number(length) > REMEMBERED_FILE) return { body: response.body, length };
          const bytes = Buffer.from(await response.arrayBuffer());
          remember(url, bytes);
          return { body: bytes, length: String(bytes.length) };
        }
        // The start of the store's words, read for a moment at most: a body that stalls never holds up the next try.
        let words = "";
        const reader = response.body?.getReader();
        if (reader) {
          const first = await Promise.race([reader.read().catch(() => null), new Promise((done) => setTimeout(done, 1000, null))]);
          if (first?.value) words = Buffer.from(first.value).subarray(0, 100).toString("utf8").replace(/\s+/g, " ");
          reader.cancel().catch(() => {});
        }
        said = [response.status, response.headers.get("x-vercel-error"), response.headers.get("x-vercel-mitigated") && `mitigated ${response.headers.get("x-vercel-mitigated")}`, words && `"${words}"`].filter(Boolean).join(" ");
        if (!(response.status === 403 || response.status === 429 || response.status >= 500)) break;
      }
      throw new Error(`Part unavailable (${said})`);
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

// A page's small files, as read from the store by this instance, the most recently served last: at most REMEMBERED in
// all, the least recently served going first.
const REMEMBERED = 96 * 1024 * 1024, REMEMBERED_FILE = 2 * 1024 * 1024;
const remembered = new Map();
let rememberedBytes = 0;
function remember(url, bytes) {
  // Reads of one file at once each arrive here: the one already kept is counted out before its copy is counted in.
  rememberedBytes -= remembered.get(url)?.length ?? 0;
  remembered.delete(url);
  remembered.set(url, bytes);
  rememberedBytes += bytes.length;
  for (const [oldest, kept] of remembered) {
    if (rememberedBytes <= REMEMBERED) break;
    remembered.delete(oldest);
    rememberedBytes -= kept.length;
  }
}

/** Kept in memory, for `npm run dev` and the tests: pictures as data: URLs, so nothing else needs serving. */
export function memoryStore() {
  const records = new Map(), pages = new Map(), ideas = new Map(), mailboxes = new Map(), makers = new Map();
  return {
    limiter: null,
    records,
    async get(id) { return records.has(id) ? structuredClone(records.get(id)) : null; },
    async create(record) { if (records.has(record.id)) return false; records.set(record.id, structuredClone(record)); return true; },
    async replace(record) { if (!records.has(record.id)) return false; records.set(record.id, structuredClone(record)); return true; },
    async swap(before, after) {
      if (!records.has(after.id) || JSON.stringify(records.get(after.id)) !== JSON.stringify(before)) return false;
      records.set(after.id, structuredClone(after));
      return true;
    },
    async remove(id) { records.delete(id); ideas.delete(id); makers.delete(id); },
    async maker(id) { return makers.has(id) ? structuredClone(makers.get(id)) : null; },
    async setMaker(id, value) { if (value) makers.set(id, structuredClone(value)); else makers.delete(id); },
    async makerStep(id, key, step) {
      const maker = makers.get(id);
      if (maker?.key !== key) return;
      if (step === "confirm") maker.confirmed = true; else makers.delete(id);
    },
    async addIdea(id, idea) {
      const kept = ideas.get(id) ?? { next: 0, all: new Map() };
      if ([...kept.all.values()].filter((one) => !one.status).length >= IDEA_LIMITS.kept) return null;
      const n = ++kept.next;
      kept.all.set(n, { ...idea, n });
      ideas.set(id, kept);
      return n;
    },
    async ideas(id) { return [...(ideas.get(id)?.all.values() ?? [])].map((idea) => structuredClone(idea)).sort((a, b) => a.n - b.n); },
    async removeIdea(id, n) { return ideas.get(id)?.all.delete(n) ?? false; },
    async finishIdea(id, n, status, at, message) {
      const idea = ideas.get(id)?.all.get(n);
      if (!idea || idea.status) return null;
      const before = structuredClone(idea);
      Object.assign(idea, { status, done: at, last: at });
      delete idea.waiting;
      if (message) idea.thread = [...(idea.thread ?? []), message];
      if (status === "dismissed" && !idea.thread) delete idea.email;
      delete idea.picture;
      return before;
    },
    async talk(id, n, op, value = "", extra = "") {
      const idea = ideas.get(id)?.all.get(n);
      if (!idea) return null;
      const before = structuredClone(idea);
      if (op === "say") {
        if (idea.note && !idea.thread) { idea.thread = [{ by: "maker", text: idea.note, at: idea.done ?? idea.at }]; delete idea.note; }
        const thread = idea.thread ?? [];
        if (thread.length >= IDEA_LIMITS.thread || thread.some((one) => (value.mid && one.mid === value.mid) || (value.via && one.via === value.via))) return null;
        idea.thread = [...thread, value];
        idea.last = value.at;
        if (value.by === "sender") idea.waiting = true; else delete idea.waiting;
      } else if (op === "settle") delete idea.waiting;
      else if (op === "box") { if (!idea.mailbox) Object.assign(idea, { mailbox: value, subject: extra }); }
      else if (op === "makerbox") { if (!idea.makerBox) idea.makerBox = value; }
      else if (op === "stop" && idea.mailbox === value) delete idea.email;
      else return null;
      return before;
    },
    async openMailbox(id, n, side = "sender") { const box = randomBytes(10).toString("hex"); mailboxes.set(box, { id, n, side }); return box; },
    async mailbox(box) { return mailboxes.get(box) ?? null; },
    async closeMailbox(box) { mailboxes.delete(box); },
    async putImage(_id, _name, image) { return `data:${image.type};base64,${image.bytes.toString("base64")}`; },
    async removeImages() {},
    async putFile(_id, _name, bytes) { return `data:application/octet-stream;base64,${bytes.toString("base64")}`; },
    async putPageFile(id, token, path, bytes) { const at = `memory:${id}/${token}/${path}`; pages.set(at, Buffer.from(bytes)); return at; },
    async readFile(url) { return url.startsWith("memory:") ? pages.get(url) : Buffer.from(url.slice(url.indexOf(",") + 1), "base64"); },
    async openFile(url) { const bytes = await this.readFile(url); return { body: bytes, length: String(bytes.length) }; },
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
    if (!["GET", "POST", "PUT", "DELETE"].includes(method)) return reply(405, { error: "method_not_allowed" }, { Allow: "GET, POST, PUT, DELETE" });
    const url = new URL(request.url);
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });
    const id = url.searchParams.get("id");
    if (method !== "POST" && !isID(id)) return reply(404, { error: "not_found" });
    // Asked by the Lamps that follow this link: public, as the page is, and cheap (one read, no quota).
    if (method === "GET") {
      let kept;
      try { kept = store ?? cloudStore(env, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }
      try {
        const record = await kept.get(id);
        return record ? reply(200, latest(record)) : reply(404, { error: "not_found" });
      } catch { return reply(503, { error: "service_unavailable" }); }
    }

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
      try { retry = await reserve(kept.limiter, ip, method === "DELETE" ? DELETE_QUOTAS : method === "PUT" ? UPDATE_QUOTAS : QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }

    let uploaded = [];
    try {
      const earlier = method === "POST" ? null : await kept.get(id);
      if (method !== "POST" && (!earlier || !secretMatches(bearer(request), earlier.secret))) return reply(404, { error: "not_found" });
      const oldImages = [earlier?.picture?.url, earlier?.icon?.url].filter(Boolean);
      if (method === "DELETE") {
        const ideaShots = ideaPictures(await kept.ideas(id).catch(() => []));
        await kept.remove(id);
        await kept.removeImages([...blobsOf(earlier), ...ideaShots]);
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
      const words = { name: share.name, by: share.by, line: share.line, words: share.words, ideas: share.ideas, asks: share.asks, shape: share.shape, github: share.github,
        ...(share.releases ? { releases: share.releases } : {}), picture: picture || null, icon: icon || null };
      if (method === "PUT") {
        await kept.replace({ ...earlier, ...words, updated: time });
        uploaded = [];
        await kept.removeImages(oldImages);
        await kept.forget(id);
        return reply(200, { id, url: linkFor(url.origin, id, words.name) });
      }
      const secret = newSecret();
      if (!(await kept.create({ id: wishID, ...words, secret: hashSecret(secret), created: time, updated: time }))) {
        throw new Error("Id taken");
      }
      uploaded = [];
      return reply(201, { id: wishID, url: linkFor(url.origin, wishID, words.name), secret });
    } catch {
      try { await kept.removeImages(uploaded); } catch {}
      return reply(503, { error: "service_unavailable" });
    }
  };
}

// MARK: Ideas for the maker

/** What someone playing a shared wish may send its maker: their idea, and an address to hear back at if they want. */
export const IDEA_LIMITS = { text: 1000, note: 2000, thread: 60, earlier: 100, name: 60, email: 200, picture: 400_000, kept: 500, asked: 20, keptDone: 90 * 86400_000 };
// A visitor sends a handful an hour; a link takes a few hundred a day; overall, a ceiling on a flood.
export const IDEA_QUOTAS = [
  { name: "idea-ip", perIP: true, limit: 12, seconds: 3600 },
  { name: "idea-ip-day", perIP: true, limit: 40, seconds: 86400 },
  { name: "idea-day", limit: 5000, seconds: 86400 },
];
// Confirmations to a maker's address: one a minute per link, and a few an hour from one place, a ceiling overall.
export const MAKER_QUOTAS = [
  { name: "maker-ip", perIP: true, limit: 6, seconds: 3600 },
  { name: "maker-day", limit: 1000, seconds: 86400 },
];
const MAKER_RESEND_MS = 60_000;
const EMAIL = /^[^\s@<>()",;:]+@[^\s@<>()",;:]+\.[^\s@<>()",;:]+$/;
// An idea's mailbox outlives its last message by a little more than the idea itself does (`IDEA_LIMITS.keptDone`).
const MAILBOX_SECONDS = 100 * 86400;

/** The domain of the address the site's emails come from (`LAMP_IDEAS_FROM`), for the message ids it gives them. */
const mailDomain = (env) => /@([^\s>]+)>?\s*$/.exec(env.LAMP_IDEAS_FROM ?? "")?.[1] ?? "lamp.dev";
/** A new message id for something the maker says, which the email carrying it goes out with. */
const newMessageID = (env) => `<idea.${randomBytes(12).toString("hex")}@${mailDomain(env)}>`;

/**
 * Writes to an idea's sender through Resend (`RESEND_API_KEY`, from `LAMP_IDEAS_FROM`, an address on a domain Resend
 * has verified): `kind` "in" when it's in (with the maker's note, if any), "reply" for something the maker says after.
 * The first email gives the idea a mailbox: with `LAMP_IDEAS_REPLY_DOMAIN` set, a reply to any of them goes to
 * `idea-<mailbox>@` it, and comes back to the idea's thread (`createIdeaMailHandler`); each also has a link to stop
 * them. Every one after the first answers the one before, so they read as one conversation. False, and nothing
 * sent, without an address or Resend, or when Resend refuses.
 */
export async function writeToSender(kept, wishID, idea, record, link, { env = process.env, fetcher = fetch, kind = "in", said, origin, once } = {}) {
  const key = env.RESEND_API_KEY, from = env.LAMP_IDEAS_FROM;
  if (!key || !from || !idea.email) return false;
  let subject = idea.subject || (kind === "in" ? `Your idea is in ${record.name}` : `About your idea for ${record.name}`);
  let box = idea.mailbox;
  if (!box) {
    // Two first emails at once each open one, and both go with whichever the idea kept.
    box = await kept.openMailbox(wishID, idea.n);
    const before = await kept.talk(wishID, idea.n, "box", box, subject);
    if (before?.mailbox) {
      try { await kept.closeMailbox(box); } catch {}
      box = before.mailbox;
      subject = before.subject || subject;
    }
  }
  const by = record.by?.trim();
  const maker = by || "Whoever made it";
  const stop = `${origin}/api/wish-ideas?id=${wishID}&n=${idea.n}&stop=${box}`;
  const replies = env.LAMP_IDEAS_REPLY_DOMAIN ? `idea-${box}@${env.LAMP_IDEAS_REPLY_DOMAIN}` : null;
  const note = said?.text;
  const text = (kind === "in"
    ? `${maker} added your idea to ${record.name}:\n\n${idea.text}\n\n` + (note ? `${by ? `${by} wrote` : "Their note"}:\n\n${note}\n\n` : "")
    : `${by ? `${by} wrote` : "A note"} about your idea for ${record.name}:\n\n${note}\n\nYour idea: ${idea.text}\n\n`) +
    `Play it: ${link}\n\n` + (replies ? `Reply to this email to answer ${by || "them"}.\n` : "") +
    `No more emails about this idea: ${stop}`;
  // The thread so far, the emails each way, for mail apps to keep them together.
  const ids = (idea.thread ?? []).map((one) => one.mid).filter((mid) => typeof mid === "string" && /^<[^<>\s]+>$/.test(mid));
  const headers = {
    ...(said?.mid ? { "Message-ID": said.mid } : {}),
    ...(ids.length ? { "In-Reply-To": ids.at(-1), References: ids.slice(-20).join(" ") } : {}),
    "List-Unsubscribe": `<${stop}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
  };
  try {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(5000),
      // Resend sends one email for a key however often it's asked within a day.
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", ...(once ? { "Idempotency-Key": once } : {}) },
      body: JSON.stringify({
        from, to: [idea.email], subject: idea.mailbox ? `Re: ${subject}` : subject, text, headers,
        ...(replies ? { reply_to: [replies] } : {}),
      }),
    });
    return response.ok;
  } catch { return false; }
}

/** Sends one email through Resend; false, and nothing sent, without Resend or when it refuses. */
async function sendMail(env, fetcher, message, once) {
  if (!env.RESEND_API_KEY || !env.LAMP_IDEAS_FROM) return false;
  try {
    const response = await fetcher("https://api.resend.com/emails", {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(5000),
      headers: { Authorization: `Bearer ${env.RESEND_API_KEY}`, "Content-Type": "application/json", ...(once ? { "Idempotency-Key": once } : {}) },
      body: JSON.stringify({ from: env.LAMP_IDEAS_FROM, ...message }),
    });
    return response.ok;
  } catch { return false; }
}

/**
 * Writes to a link's maker at their own address (`maker`, once they've confirmed it): `kind` "idea" for a new idea,
 * "reply" for its sender's answer. The first gives the idea a mailbox of the maker's, and a reply to any of them comes
 * back as the maker's own word on its thread, sent on to the sender (`createIdeaMailHandler`). Each idea's emails to
 * the maker are one conversation of their own, and each has a link to stop them for the whole link.
 */
export async function writeToMaker(kept, wishID, idea, record, link, { env = process.env, fetcher = fetch, kind = "idea", said, origin, maker, once } = {}) {
  if (!env.RESEND_API_KEY || !env.LAMP_IDEAS_FROM || !maker?.confirmed || !maker.email) return false;
  let box = idea.makerBox;
  if (!box) {
    box = await kept.openMailbox(wishID, idea.n, "maker");
    const before = await kept.talk(wishID, idea.n, "makerbox", box);
    if (before?.makerBox) {
      try { await kept.closeMailbox(box); } catch {}
      box = before.makerBox;
    }
  }
  const replies = env.LAMP_IDEAS_REPLY_DOMAIN ? `idea-${box}@${env.LAMP_IDEAS_REPLY_DOMAIN}` : null;
  const stop = `${origin}/api/wish-ideas?id=${wishID}&stopmaker=${maker.key}`;
  const flat = idea.text.replace(/\s+/g, " ");
  const subject = `Idea for ${record.name}: ${[...flat].length > 60 ? `${[...flat].slice(0, 60).join("").trimEnd()}…` : flat}`;
  const root = `<idea-${box}@${mailDomain(env)}>`;
  const text = (kind === "idea"
    ? `${idea.name || "Someone"} playing ${record.name} sent an idea:\n\n${idea.text}\n\n` +
      (typeof idea.picture === "string" && idea.picture.startsWith("https://") ? `The app as they saw it: ${idea.picture}\n\n` : "") +
      (idea.email ? "They'd like to hear back.\n\n" : "They left no address, so what you say shows on the link's page.\n\n")
    : `${idea.name || "They"} answered about their idea for ${record.name}:\n\n${said.text}\n\nTheir idea: ${idea.text}\n\n`) +
    (replies ? "Reply to this email to answer them. It's in Lamp too.\n" : "Answer them in Lamp.\n") +
    `Play it: ${link}\n\nNo more emails about ideas for ${record.name}: ${stop}`;
  return sendMail(env, fetcher, {
    to: [maker.email], subject: kind === "idea" ? subject : `Re: ${subject}`, text,
    headers: {
      ...(kind === "idea" ? { "Message-ID": root } : { "In-Reply-To": root, References: root }),
      "List-Unsubscribe": `<${stop}>`, "List-Unsubscribe-Post": "List-Unsubscribe=One-Click",
    },
    ...(replies ? { reply_to: [replies] } : {}),
  }, once);
}

/**
 * An idea as sent from a link's page, or null: its words, an address to hear back at only if it looks like one, and
 * the picture of the app the page took when the sender opened the box, if they kept it in (a PNG or JPEG, base64).
 */
export function readIdea(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const text = tidy(body.text, IDEA_LIMITS.text, { lines: true });
  if (!text) return null;
  const shot = picture(body.picture, IDEA_LIMITS.picture);
  if (!shot) return null;
  // Their name, if they gave one, for the maker: shown in Lamp and in the maker's emails, where the address never is.
  const name = body.name == null || body.name === "" ? "" : tidy(body.name, IDEA_LIMITS.name);
  if (name == null) return null;
  const idea = { text, ...(name ? { name } : {}), ...(shot.bytes ? { picture: shot } : {}) };
  if (body.email == null || body.email === "") return idea;
  const email = tidy(body.email, IDEA_LIMITS.email);
  return email && EMAIL.test(email) ? { ...idea, email } : null;
}

/** The pictures a link's ideas carry, to go with them. */
const ideaPictures = (ideas) => ideas.map((one) => one.picture).filter((url) => typeof url === "string" && url.startsWith("https://"));

/**
 * Ideas for a link's maker (`/api/wish-ideas?id=`). POST, from the link's page once the sender confirms it, keeps one:
 * what someone using it would change, an address to hear back at, if they gave one, and the picture of the app the
 * page took as they opened the box, if they kept it in (in the store, until the idea has its outcome). GET, with the
 * link's secret, answers for Lamp to show the maker those still open and those whose sender has answered since
 * (`waiting`), or with `earlier=1` those seen to, each with its picture's address and its thread: never the keys or the addresses, only whether someone
 * wants to hear back. DELETE ?n= with the secret lets one go: with `built=1` it's in, and the site writes to whoever
 * asked (`writeToSender`); without, it's dismissed. Its JSON body may carry the maker's `note`, the first of the idea's
 * thread. PATCH ?n= with the secret and a `note` says something more, written to the sender if they gave an address;
 * without one it only says the maker has seen to their answer. Every idea is kept a while past its last word, for the
 * sender's own browser, which kept the number and a token the POST answered, to ask after it on a later visit (GET
 * `?id=&mine=<n>.<token>,…`, answering only those, with the maker's last word), and for the sender's replies by email.
 * A link in each email (`?stop=<mailbox>`, GET or a mail app's one-click POST) lets the address go. Never logged,
 * never on the page for anyone else, gone with the link.
 */
export function createIdeasHandler({ env = process.env, fetcher = fetch, store, limited = true, now = () => new Date() } = {}) {
  return async (request) => {
    const method = request.method;
    if (!["GET", "POST", "PUT", "PATCH", "DELETE"].includes(method)) return reply(405, { error: "method_not_allowed" }, { Allow: "GET, POST, PUT, PATCH, DELETE" });
    const url = new URL(request.url);
    const id = url.searchParams.get("id");
    if (!isID(id)) return reply(404, { error: "not_found" });
    const stop = url.searchParams.get("stop");
    if (stop != null && (method === "GET" || method === "POST")) return stopEmails(id, Number(url.searchParams.get("n")), stop);
    // The links in the maker's own emails: confirming their address, and stopping them.
    for (const step of ["confirm", "stopmaker"]) {
      const given = url.searchParams.get(step);
      if (given != null && (method === "GET" || method === "POST")) return makerLink(id, step, given);
    }
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });

    let idea = null;
    if (method === "POST") {
      if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") || "")) return reply(415, { error: "json_required" });
      try { idea = readIdea(JSON.parse(await readBody(request))); }
      catch (error) { return reply(error instanceof RangeError ? 413 : 400, { error: "invalid_idea" }); }
      if (!idea) return reply(400, { error: "invalid_idea" });
    }
    // The maker's own address for the link's ideas (PUT ?maker=1 with the secret): checked here, kept once the secret is.
    let makerEmail;
    if (method === "PUT") {
      if (url.searchParams.get("maker") !== "1") return reply(405, { error: "method_not_allowed" });
      let given;
      try { given = JSON.parse((await readBody(request)) || "{}")?.email; }
      catch (error) { return reply(error instanceof RangeError ? 413 : 400, { error: "invalid_email" }); }
      makerEmail = given == null || given === "" ? "" : tidy(given, IDEA_LIMITS.email);
      if (makerEmail === null || (makerEmail && !EMAIL.test(makerEmail))) return reply(400, { error: "invalid_email" });
    }
    const n = method === "DELETE" || method === "PATCH" ? Number(url.searchParams.get("n")) : null;
    if (n !== null && (!Number.isInteger(n) || n < 1)) return reply(400, { error: "invalid_idea" });
    // The maker's note to the sender, if they wrote one: a body with nothing in it, or none, is no note.
    let note = null;
    if (n !== null && /^application\/json/i.test(request.headers.get("content-type") || "")) {
      let given;
      try { given = JSON.parse((await readBody(request)) || "{}")?.note; }
      catch (error) { return reply(error instanceof RangeError ? 413 : 400, { error: "invalid_idea" }); }
      if (given != null && given !== "") {
        note = tidy(given, IDEA_LIMITS.note, { lines: true });
        if (!note) return reply(400, { error: "invalid_idea" });
      }
    }

    let kept;
    try { kept = store ?? cloudStore(env, fetcher); } catch { return reply(503, { error: "service_unavailable" }); }
    // A new idea, or a confirmation to a maker's address: each an email or more, so each is counted.
    if (limited && (method === "POST" || (method === "PUT" && makerEmail))) {
      const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
      if (!isIP(ip) || !kept.limiter) return reply(503, { error: "service_unavailable" });
      let retry;
      try { retry = await reserve(kept.limiter, ip, method === "POST" ? IDEA_QUOTAS : MAKER_QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }

    try {
      const record = await kept.get(id);
      if (!record) return reply(404, { error: "not_found" });
      if (method === "POST") {
        const token = randomBytes(12).toString("base64url");
        // The picture goes to the store first, at an address with a random part, and goes again if the idea can't.
        const { picture: shot, ...words } = idea;
        const at = shot ? await kept.putImage(id, "idea", shot) : null;
        let number = null;
        const added = { ...words, ...(at ? { picture: at } : {}), token, at: now().toISOString() };
        try { number = await kept.addIdea(id, added); }
        finally { if (!number && at) { try { await kept.removeImages([at]); } catch {} } }
        if (!number) return reply(429, { error: "full" });
        // To the maker's own address too, if they gave one: the idea is kept whether or not that goes.
        try {
          const maker = await kept.maker(id);
          if (maker?.confirmed) await writeToMaker(kept, id, { ...added, n: number }, record, linkFor(url.origin, id, record.name), { env, fetcher, origin: url.origin, maker, once: `maker-${id}-${number}` });
        } catch {}
        return reply(201, { n: number, token });
      }
      // The sender's own ideas, asked by number and token from their browser: what became of each, and the maker's
      // last word to them, nothing else.
      const mine = method === "GET" ? url.searchParams.get("mine") : null;
      if (mine != null) {
        const asked = new Map(mine.split(",").slice(0, IDEA_LIMITS.asked).map((one) => one.split("."))
          .filter(([n, token]) => /^\d{1,6}$/.test(n ?? "") && /^[A-Za-z0-9_-]{16}$/.test(token ?? "")).map(([n, token]) => [Number(n), token]));
        const all = await kept.ideas(id);
        return reply(200, { ideas: all.filter((one) => one.token && asked.get(one.n) === one.token).map((one) => {
          // A note given before ideas had threads was kept on its own.
          const last = (one.thread ?? []).filter((said) => said.by === "maker").at(-1)?.text ?? one.note;
          return { n: one.n, status: one.status ?? "open", ...(one.done ? { done: one.done } : {}), ...(last ? { note: last } : {}) };
        }) });
      }
      if (!secretMatches(bearer(request), record.secret)) return reply(404, { error: "not_found" });
      if (url.searchParams.get("maker") === "1" && (method === "GET" || method === "PUT")) return setMaker(kept, record, id, url.origin, method === "PUT" ? makerEmail : undefined);
      // The maker sees the ideas still open, and those answered since, and whether someone wants to hear back, never
      // their address: the site writes to them. Those settled are kept a while past their last word, then go.
      if (method === "GET") {
        const all = await kept.ideas(id);
        const old = all.filter((one) => one.done && now() - new Date(one.last ?? one.done) > IDEA_LIMITS.keptDone);
        for (const one of old) {
          await kept.removeIdea(id, one.n);
          for (const box of [one.mailbox, one.makerBox]) if (box) { try { await kept.closeMailbox(box); } catch {} }
        }
        try { await kept.removeImages(ideaPictures(old)); } catch {}
        // `earlier=1`: those seen to, the latest word first, for the maker to look back on or answer again.
        if (url.searchParams.get("earlier") === "1") {
          const settled = all.filter((one) => one.status && !one.waiting && !old.includes(one))
            .sort((a, b) => String(b.last ?? b.done).localeCompare(String(a.last ?? a.done)));
          return reply(200, { ideas: settled.slice(0, IDEA_LIMITS.earlier).map(shownToMaker) });
        }
        return reply(200, { ideas: all.filter((one) => !one.status || one.waiting).map(shownToMaker) });
      }
      const link = linkFor(url.origin, id, record.name);
      const write = (to, kind, said, once) => writeToSender(kept, id, to, record, link, { env, fetcher, kind, said, origin: url.origin, once });
      const said = note ? { by: "maker", text: note, at: now().toISOString(), mid: newMessageID(env) } : null;
      if (method === "PATCH") {
        if (!said) return (await kept.talk(id, n, "settle")) ? reply(200, { notified: false }) : reply(404, { error: "not_found" });
        const was = await kept.talk(id, n, "say", said);
        if (!was) return (await kept.ideas(id)).some((one) => one.n === n) ? reply(429, { error: "full" }) : reply(404, { error: "not_found" });
        return reply(200, { notified: await write(was, "reply", said, `idea-${id}-${n}-${said.mid}`) });
      }
      // An outcome, given once: only the call that gave it writes to the sender, so two at once, or one tried again,
      // send one email.
      const built = url.searchParams.get("built") === "1";
      // Its picture was for the maker, who has seen to it: it goes first, so a store that turns that away leaves the
      // idea open, with its picture, to be let go again, rather than the picture left with nothing pointing to it.
      const open = (await kept.ideas(id)).find((one) => one.n === n && !one.status);
      if (open) await kept.removeImages(ideaPictures([open]));
      const was = await kept.finishIdea(id, n, built ? "in" : "dismissed", now().toISOString(), said);
      const notified = built && was?.email ? await write(was, "in", said, `idea-${id}-${n}`) : false;
      return reply(200, { notified });
    } catch { return reply(503, { error: "service_unavailable" }); }
  };

  /**
   * The maker's own address: as it is (`email` undefined), or given (asked to confirm it first, by an email with a
   * link in it, unless it's the one they confirmed already) or taken away (""). Never anyone else's to see.
   */
  async function setMaker(kept, record, id, origin, email) {
    let maker = await kept.maker(id);
    let sent = false;
    if (email === "") { await kept.setMaker(id, null); maker = null; }
    else if (email !== undefined && !(maker?.confirmed && maker.email.toLowerCase() === email.toLowerCase())) {
      // Send Again, or another address, at most once a minute for a link.
      const since = now() - new Date(maker?.asked ?? 0);
      if (since < MAKER_RESEND_MS) return reply(429, { error: "rate_limited" }, { "Retry-After": String(Math.ceil((MAKER_RESEND_MS - since) / 1000)) });
      maker = { email, confirmed: false, key: randomBytes(10).toString("hex"), asked: now().toISOString() };
      await kept.setMaker(id, maker);
      sent = await sendMail(env, fetcher, {
        to: [email], subject: `Get ideas for ${record.name} by email`,
        text: `To get the ideas people send for ${record.name}, and their replies, at this address, confirm it here:\n\n` +
          `${origin}/api/wish-ideas?id=${id}&confirm=${maker.key}\n\nIf you didn't ask for this, you can ignore this email.`,
      });
    }
    return reply(200, { email: maker?.email ?? null, confirmed: maker?.confirmed === true, ...(email && !maker?.confirmed ? { sent } : {}) });
  }

  /** A link from the maker's emails: their address confirmed, or let go, if the key is theirs. */
  async function makerLink(id, step, key) {
    if (!/^[0-9a-f]{20}$/.test(key)) return reply(404, { error: "not_found" });
    try {
      const kept = store ?? cloudStore(env, fetcher);
      await kept.makerStep(id, key, step === "confirm" ? "confirm" : "stop");
    } catch { return reply(503, { error: "service_unavailable" }); }
    const words = step === "confirm" ? "Ideas for this link, and replies to them, will come to your email." : "You won't get any more emails about this link's ideas.";
    return new Response(`${words}\n`, { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  }

  /** A link from one of the emails: the idea's address goes, if the mailbox is the idea's own. */
  async function stopEmails(id, n, box) {
    if (!Number.isInteger(n) || n < 1 || !/^[0-9a-f]{20}$/.test(box)) return reply(404, { error: "not_found" });
    try {
      const kept = store ?? cloudStore(env, fetcher);
      await kept.talk(id, n, "stop", box);
    } catch { return reply(503, { error: "service_unavailable" }); }
    // The same words whether or not it was theirs, so the link says nothing about an idea to anyone else.
    return new Response("You won't get any more emails about this idea.\n", { status: 200, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store" } });
  }
}

/**
 * An idea as its maker sees it: never its sender's address, its token or its mailbox, only whether they want to hear.
 * A note given before ideas had threads is shown as the start of one.
 */
const shownToMaker = ({ email, token: _token, mailbox: _mailbox, makerBox: _makerBox, subject: _subject, note, ...given }) => {
  const shown = note && !given.thread ? { ...given, thread: [{ by: "maker", text: note, at: given.done ?? given.at }] } : given;
  return {
  ...shown,
  ...(shown.thread ? { thread: shown.thread.map(({ by, text, at }) => ({ by, text, at })) } : {}),
  ...(email ? { wantsNews: true } : {}),
  };
};

/** The address in a From line, in lower case: `Someone <a@b.c>` or `a@b.c`. */
const addressIn = (from) => (/<([^<>\s]+@[^<>\s]+)>/.exec(from ?? "")?.[1] ?? String(from ?? "").trim()).toLowerCase();

/**
 * A reply's own words: what's above the earlier email it quotes (a line "On … wrote:", a "-----Original Message-----"
 * or a "From:" line after a blank one), without lines quoted with ">", tidied and cut to `IDEA_LIMITS.note`.
 */
export function replyWords(text) {
  const lines = String(text ?? "").replace(/\r\n?/g, "\n").split("\n");
  const kept = [];
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const two = `${line} ${lines[i + 1] ?? ""}`;
    if (/^\s*-{2,}\s*Original Message\s*-{2,}/i.test(line) || /^\s*_{10,}\s*$/.test(line)) break;
    if (/^\s*On\b.{0,300}\bwrote:\s*$/i.test(line) || (/^\s*On\b/i.test(line) && /^\s*On\b.{0,300}\bwrote:\s*$/i.test(two))) break;
    if (/^\s*From:\s/i.test(line) && kept.length && kept.at(-1).trim() === "") break;
    if (/^\s*>/.test(line)) continue;
    kept.push(line);
  }
  const words = kept.join("\n").trim();
  return tidy([...words].slice(0, IDEA_LIMITS.note).join(""), IDEA_LIMITS.note, { lines: true });
}

/**
 * Whether a webhook from Resend is its own (`RESEND_WEBHOOK_SECRET`, `whsec_` and base64): Svix's signature, an
 * HMAC-SHA256 of `<id>.<timestamp>.<body>`, sent no more than five minutes ago.
 */
export function signedByResend(headers, body, secret, now = Date.now()) {
  const id = headers.get("svix-id"), at = headers.get("svix-timestamp"), signatures = headers.get("svix-signature");
  if (!secret || !id || !at || !signatures || !/^\d+$/.test(at) || Math.abs(now / 1000 - Number(at)) > 300) return false;
  const key = Buffer.from(secret.replace(/^whsec_/, ""), "base64");
  const expected = createHmac("sha256", key).update(`${id}.${at}.${body}`).digest();
  return signatures.split(" ").some((one) => {
    const [version, signature] = one.split(",");
    if (version !== "v1" || !signature) return false;
    const given = Buffer.from(signature, "base64");
    return given.length === expected.length && timingSafeEqual(given, expected);
  });
}

/**
 * Replies to an idea's emails (`/api/idea-mail`, Resend's `email.received` webhook, for mail to
 * `LAMP_IDEAS_REPLY_DOMAIN`). Each to `idea-<mailbox>@` it goes on that idea's thread, its own words only: from the
 * sender's mailbox, only from the address the idea was sent with, leaving it waiting on the maker and sent on to the
 * maker's own address if they gave one; from the maker's, only from their confirmed address, as their word, sent on to
 * the sender. Anything else is let go. Answers 200 to
 * whatever Resend signed, so it isn't sent again, and 401 to anything else.
 */
export function createIdeaMailHandler({ env = process.env, fetcher = fetch, store, now = () => new Date() } = {}) {
  return async (request) => {
    if (request.method !== "POST") return reply(405, { error: "method_not_allowed" }, { Allow: "POST" });
    let body;
    try { body = await readBody(request); } catch { return reply(413, { error: "too_large" }); }
    if (!signedByResend(request.headers, body, env.RESEND_WEBHOOK_SECRET, now().getTime())) return reply(401, { error: "unsigned" });
    let event;
    try { event = JSON.parse(body); } catch { return reply(200, {}); }
    const mail = event?.data;
    const domain = (env.LAMP_IDEAS_REPLY_DOMAIN ?? "").toLowerCase();
    if (event?.type !== "email.received" || !domain || typeof mail?.email_id !== "string") return reply(200, {});
    const boxes = [...new Set([...(mail.to ?? []), ...(mail.received_for ?? [])].map(addressIn)
      .map((to) => new RegExp(`^idea-([0-9a-f]{20})@${domain.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")}$`).exec(to)?.[1]).filter(Boolean))];
    if (!boxes.length) return reply(200, {});
    const origin = new URL(request.url).origin;
    try {
      const kept = store ?? cloudStore(env, fetcher);
      for (const box of boxes.slice(0, 3)) {
        const found = await kept.mailbox(box);
        if (!found) continue;
        const idea = (await kept.ideas(found.id)).find((one) => one.n === found.n);
        if (!idea) continue;
        const maker = await kept.maker(found.id);
        // Only from the address the idea's emails went to on that side, and only while it's kept.
        const from = addressIn(mail.from);
        const fromMaker = found.side === "maker";
        if (fromMaker ? !(maker?.confirmed && idea.makerBox === box && from === maker.email.toLowerCase())
          : !(idea.email && idea.mailbox === box && from === idea.email.toLowerCase())) continue;
        const response = await fetcher(`https://api.resend.com/emails/receiving/${encodeURIComponent(mail.email_id)}`, {
          redirect: "error", signal: AbortSignal.timeout(5000), headers: { Authorization: `Bearer ${env.RESEND_API_KEY}` },
        });
        if (!response.ok) return reply(503, { error: "service_unavailable" });
        const got = await response.json();
        const words = replyWords(got.text ?? String(got.html ?? "").replace(/<br\s*\/?>|<\/p>|<\/div>/gi, "\n").replace(/<[^>]*>/g, "")
          .replace(/&nbsp;/g, " ").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').replace(/&#39;/g, "'").replace(/&amp;/g, "&"));
        if (!words) continue;
        const mid = typeof mail.message_id === "string" && /^<[^<>\s]+>$/.test(mail.message_id) ? mail.message_id : undefined;
        const record = await kept.get(found.id);
        if (!record) continue;
        const link = linkFor(origin, found.id, record.name);
        // The email as Resend received it, which a webhook sent again names the same, keeps it from going on twice.
        const via = `resend:${mail.email_id}`;
        if (fromMaker) {
          // The maker's own word, as if said in Lamp: on the thread, and on to the sender, with a message id of its own.
          const said = { by: "maker", text: words, at: now().toISOString(), mid: newMessageID(env), via };
          const was = await kept.talk(found.id, found.n, "say", said);
          if (was?.email) await writeToSender(kept, found.id, was, record, link, { env, fetcher, kind: "reply", said, origin, once: `idea-${found.id}-${found.n}-${said.mid}` });
        } else {
          const said = { by: "sender", text: words, at: now().toISOString(), via, ...(mid ? { mid } : {}) };
          const was = await kept.talk(found.id, found.n, "say", said);
          if (was && maker?.confirmed) await writeToMaker(kept, found.id, was, record, link, { env, fetcher, kind: "reply", said, origin, maker, once: `maker-${found.id}-${found.n}-${mail.email_id}` });
        }
      }
    } catch { return reply(503, { error: "service_unavailable" }); }
    return reply(200, {});
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
  const ideaShots = ideaPictures(await kept.ideas(id).catch(() => []));
  await kept.remove(id);
  await kept.removeImages([...blobsOf(record), ...ideaShots]);
  await kept.forget(id);
  return true;
}

// MARK: The wish's page

/** The most a playable page may hold: as many bytes as the wish's file, in at most this many files. */
// A page is sent packed within `FILE_LIMITS.total`; what it unpacks to may be more, since a big 3D game's data packs small.
export const PAGE_LIMITS = { files: 3000, total: 128_000_000 };

/** How many of a page's files go to the blob store at once as it's put together. */
const PAGE_UPLOADS = 12;

/**
 * A zip's files, read from its central directory: stored or deflated, never a link, a folder, an absolute path or one
 * that steps up. Null for anything else, or past the limits, counting what they unpack to.
 */
export function readZip(bytes, limits = PAGE_LIMITS) {
  if (bytes.length < 22 || bytes.readUInt32LE(0) !== 0x04034b50) return null;
  const end = bytes.lastIndexOf(Buffer.from([0x50, 0x4b, 0x05, 0x06]));
  if (end < Math.max(0, bytes.length - 65_557)) return null;
  const count = bytes.readUInt16LE(end + 10), size = bytes.readUInt32LE(end + 12), offset = bytes.readUInt32LE(end + 16);
  if (offset + size > end || count > limits.files) return null;
  const files = [];
  let total = 0;
  for (let at = offset, n = 0; n < count; n++) {
    if (at + 46 > end || bytes.readUInt32LE(at) !== 0x02014b50) return null;
    const method = bytes.readUInt16LE(at + 10), packed = bytes.readUInt32LE(at + 20), unpacked = bytes.readUInt32LE(at + 24);
    const nameLength = bytes.readUInt16LE(at + 28), extra = bytes.readUInt16LE(at + 30), comment = bytes.readUInt16LE(at + 32);
    const external = bytes.readUInt32LE(at + 38), local = bytes.readUInt32LE(at + 42);
    const path = bytes.toString("utf8", at + 46, at + 46 + nameLength);
    at += 46 + nameLength + extra + comment;
    if (path.endsWith("/")) continue;
    // A link (its Unix mode in the high bits) never goes up.
    if (((external >>> 16) & 0o170000) === 0o120000) return null;
    if (!path || path.startsWith("/") || path.includes("\\") || path.split("/").some((part) => part === ".." || part === "" || part === ".")) return null;
    if (path.split("/").some((part) => part.startsWith(".")) || path.startsWith("__MACOSX/")) continue;
    total += unpacked;
    if (total > limits.total) return null;
    if (local + 30 > bytes.length || bytes.readUInt32LE(local) !== 0x04034b50) return null;
    const start = local + 30 + bytes.readUInt16LE(local + 26) + bytes.readUInt16LE(local + 28);
    const data = bytes.subarray(start, start + packed);
    let content;
    try { content = method === 0 ? Buffer.from(data) : method === 8 ? inflateRawSync(data, { maxOutputLength: Math.max(1, unpacked) }) : null; }
    catch { return null; }
    if (!content || content.length !== unpacked) return null;
    files.push({ path, bytes: content });
  }
  return files;
}

/** A playable page: a zip with index.html at its root (`WishLink.playablePage` in Lamp). Null for anything else. */
export function readPage(bytes) {
  const files = readZip(bytes);
  return files && files.some((file) => file.path === "index.html") ? files : null;
}

/** What a page's file is served as, by its extension: anything unknown as bytes, never guessed from what's in it. */
export function pageType(path) {
  const types = {
    html: "text/html; charset=utf-8", js: "text/javascript; charset=utf-8", mjs: "text/javascript; charset=utf-8",
    css: "text/css; charset=utf-8", json: "application/json", map: "application/json", txt: "text/plain; charset=utf-8",
    svg: "image/svg+xml", png: "image/png", jpg: "image/jpeg", jpeg: "image/jpeg", gif: "image/gif", webp: "image/webp",
    avif: "image/avif", ico: "image/x-icon", wasm: "application/wasm", mp3: "audio/mpeg", ogg: "audio/ogg", wav: "audio/wav",
    m4a: "audio/mp4", mp4: "video/mp4", webm: "video/webm", woff: "font/woff", woff2: "font/woff2", ttf: "font/ttf", otf: "font/otf",
    glb: "model/gltf-binary", gltf: "model/gltf+json", bin: "application/octet-stream", xml: "application/xml",
  };
  return types[path.split(".").pop()?.toLowerCase() ?? ""] ?? "application/octet-stream";
}

/**
 * Where a link's page plays: a host of its own under the play host (`LAMP_PLAY_ORIGIN`, say https://play.lamp.dev),
 * one for each link, so no shared page can read what another saved in the browser, nor anything of lamp.dev's. The id
 * is written in hex, since a host name doesn't keep the id's upper and lower case apart. Null without a play host.
 */
export function playOrigin(base, id) {
  if (!base || !isID(id)) return null;
  const url = new URL(base);
  return `${url.protocol}//${Buffer.from(id).toString("hex")}.${url.host}`;
}

/**
 * The page a link plays, one file at a time (`/w/<id>/play/<version>/<path>`): only on that link's own play host
 * (`playOrigin`), only into a frame on the site's own pages, and only the version the link has now. Each version's
 * files never change, so the CDN keeps them.
 */
/**
 * A page's file this big or bigger is played straight from the store instead of through the play host: the CDN keeps
 * nothing over 10 MB from a function, so every visit would pass it through again. Only for a page kept with each
 * file's own type (`page.sizes`), since a browser won't run a script the store calls anything else. Never a page's
 * HTML, which the store hands out as a download.
 */
export const DIRECT_FILE = 9_000_000;
/**
 * A file of data a game reads with fetch (map tiles, models, sound, JSON) is played straight from the store, whatever
 * its size: the store's CDN serves it to any page (CORS for all), keeps it whatever the site deploys, and the play host
 * reads nothing for it. A game may have hundreds of small ones (a map's tiles), all asked for again after each deploy.
 * From 1 byte, so only for a page kept with each file's size and type (`page.sizes`). The play host reading a game's hundreds of files from the store in bursts is what the store
 * turned away (403) until the game didn't load. Not a script or a style sheet, whose own imports would then resolve
 * at the store, nor a picture, which a game may draw from without asking for it cross-origin. Only when the page
 * fetched it (`Sec-Fetch-Mode: cors`): a video or sound an element of the page loads (no-cors), drawn into WebGL or
 * played through Web Audio, works only from the page's own origin.
 */
export const DIRECT_DATA = 1;
const DATA_FILE = /\.(bin|gz|br|zst|json|geojson|csv|txt|glb|gltf|ktx2|basis|drc|wasm|mp3|ogg|m4a|wav|aac|flac|opus|mp4|webm|mov)$/i;

/** How long a link's record is remembered for serving its page's files, and how many links at once. */
export const PLAY_MEMORY = { ms: 60_000, links: 200 };

/**
 * What a page played on its link is given at the top of its HTML: when the link's page asks for a picture of the app
 * (as someone opens the box to send its maker an idea), the app's biggest canvas, drawn after the app has drawn its
 * next frame (a 3D scene's picture is gone once the frame is shown), scaled to at most 1280 wide, as a JPEG small enough to go with an idea. Only the
 * site's own page may ask, and only it is answered. Nothing for an app without a canvas, or one that can't be read.
 */
export function pictureScript(site) {
  // The most a picture may be as a data: URL to go with an idea (`IDEA_LIMITS.picture` bytes, as base64).
  const limit = 23 + Math.floor(IDEA_LIMITS.picture / 3) * 4;
  return `<script>(()=>{const site=${JSON.stringify(site)};addEventListener("message",e=>{if(e.origin!==site||e.source!==parent||!e.data||e.data.lamp!=="picture")return;const n=e.data.n;requestAnimationFrame(()=>{let picture=null;try{const all=[...document.querySelectorAll("canvas")].filter(c=>c.width&&c.height&&c.getClientRects().length);const c=all.sort((a,b)=>b.clientWidth*b.clientHeight-a.clientWidth*a.clientHeight)[0];if(c){const k=Math.min(1,1280/c.width),o=document.createElement("canvas");o.width=Math.round(c.width*k);o.height=Math.round(c.height*k);o.getContext("2d").drawImage(c,0,0,o.width,o.height);for(const q of [0.8,0.6,0.4]){picture=o.toDataURL("image/jpeg",q);if(picture.length<=${limit})break;picture=null}}}catch(_){}parent.postMessage({lamp:"picture",n,picture},site)})})})()</script>`;
}

export function createPlayHandler({ env = process.env, fetcher = fetch, store, anyHost = false, direct = DIRECT_FILE, directData = DIRECT_DATA, now = () => Date.now() } = {}) {
  // A link's record, remembered a minute per instance: a game asks for hundreds of files as it's played, and reading
  // the store for each used up its allowance of requests in a day, which took every link down. A version the memory
  // doesn't have (a release since) is read afresh; a link taken down plays on here for that minute at most.
  // Files asked for together while it's being read share that one read; one that fails is let go, so the next asks again.
  const remembered = new Map(), reading = new Map();
  const recordOf = async (id, version) => {
    const kept = remembered.get(id);
    if (kept && now() - kept.at < PLAY_MEMORY.ms && (kept.record?.page?.version === version || kept.record?.previousPage?.version === version)) return kept.record;
    if (reading.has(id)) return reading.get(id);
    const read = (async () => {
      try {
        const record = await (store ?? cloudStore(env, fetcher)).get(id);
        remembered.delete(id);
        if (remembered.size >= PLAY_MEMORY.links) remembered.delete(remembered.keys().next().value);
        remembered.set(id, { record, at: now() });
        return record;
      } finally { reading.delete(id); }
    })();
    reading.set(id, read);
    return read;
  };
  // Every answer the play host gives, errors too (a browser settles an origin's cluster on its first answer): the
  // play host is the same site as lamp.dev, so without this Chrome runs the framed page in the site's own process,
  // sharing its memory with the page around it and other lamp.dev tabs. A big game ran out there and crashed the tab,
  // while the same game opened on its own didn't. An agent cluster of its own lets Chrome give it a process of its own.
  const isolated = (response) => { response.headers.set("Origin-Agent-Cluster", "?1"); return response; };
  return async (request) => isolated(await play(request));
  async function play(request) {
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405, headers: { Allow: "GET, HEAD" } });
    const url = new URL(request.url);
    const id = url.searchParams.get("id"), version = Number(url.searchParams.get("v"));
    const own = playOrigin(env.LAMP_PLAY_ORIGIN, id);
    if (!anyHost && (!own || url.host !== new URL(own).host)) return new Response(null, { status: 404 });
    const path = url.searchParams.get("path") || "index.html";
    const missing = () => new Response(null, { status: 404, headers: { "Cache-Control": "no-store" } });
    if (!isID(id) || !Number.isInteger(version)) return missing();
    let record;
    // Why it failed goes to the log, never the link's id or anything it holds: a 503 here once took every link down
    // with nothing to say which store refused.
    try { record = await recordOf(id, version); } catch (error) {
      console.error("wish play: the record couldn't be read:", error?.name, error?.message);
      return new Response(null, { status: 503 });
    }
    // A page's other .html files are asked for by their clean names (the site's `cleanUrls` redirects to them), and a
    // folder's index.html by the folder, with its slash or without (a rewrite may not keep it): without, the page is
    // given its folder as its base, so its own files resolve there and not one folder up.
    // The page as it is, or the version before it, for a game that was open on that when this one went up.
    const served = record?.page?.version === version ? record.page : record?.previousPage?.version === version ? record.previousPage : null;
    const files = served?.files ?? {};
    const folder = path.replace(/\/$/, "");
    const name = path.endsWith("/") ? (files[`${path}index.html`] ? `${path}index.html` : null)
      : files[path] ? path : files[`${path}.html`] ? `${path}.html` : files[`${folder}/index.html`] ? `${folder}/index.html` : null;
    const rebased = name === `${folder}/index.html` && !path.endsWith("/");
    const at = name ? files[name] : null;
    if (!at) return missing();
    // A big file: the browser goes to it in the store, which serves it to any page. Each version's files never change.
    // Not for a worker's own script, which a browser only takes from the page's own origin, nor from a store a browser
    // can't reach (the dev server's memory). Kept apart by what asked (`Vary`), so a worker never gets the redirect.
    const worker = /worker$/i.test(request.headers.get("sec-fetch-dest") ?? "");
    const size = served.sizes?.[name] ?? 0;
    if (!rebased && !worker && at.startsWith("https://") && !/\.html?$/i.test(name) && (size >= direct || (DATA_FILE.test(name) && size >= directData && request.headers.get("sec-fetch-mode") === "cors"))) {
      return new Response(null, { status: 302, headers: { Location: at, Vary: "Sec-Fetch-Dest, Sec-Fetch-Mode", "Cache-Control": "public, max-age=300, s-maxage=31536000", ...cacheTags(id) } });
    }
    // Passed on as it comes from the store; only a page's HTML is read whole, to be given what the link's page asks of
    // it (`pictureScript`), and a folder's index.html its base.
    const kept = store ?? cloudStore(env, fetcher);
    const site = env.LAMP_SITE_ORIGIN || (anyHost ? url.origin : "https://lamp.dev");
    let bytes, length;
    try {
      if (/\.html?$/i.test(name) && request.method !== "HEAD") {
        const base = rebased ? `<base href="/w/${id}/play/${version}/${folder.split("/").map(encodeURIComponent).join("/")}/">` : "";
        const added = base + pictureScript(site);
        const html = (await kept.readFile(at)).toString("utf8");
        // In its head, or after its doctype where it has no head of its own: before a doctype, a page is drawn in quirks mode.
        const head = /<head[^>]*>/i.exec(html) ?? /^(?:\s|<!--[\s\S]*?-->)*<!doctype[^>]*>/i.exec(html);
        bytes = Buffer.from(head ? html.slice(0, head.index + head[0].length) + added + html.slice(head.index + head[0].length) : added + html);
      } else if (request.method !== "HEAD") {
        ({ body: bytes, length } = await kept.openFile(at));
      }
    } catch (error) {
      console.error("wish play: a file couldn't be read:", error?.name, error?.message);
      return new Response(null, { status: 503 });
    }
    return new Response(request.method === "HEAD" ? null : bytes, {
      headers: {
        "Content-Type": pageType(name), "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
        ...(length ? { "Content-Length": length } : {}),
        // Framed only by the link's page; frame-ancestors takes the place of the site's X-Frame-Options.
        "Content-Security-Policy": `frame-ancestors ${site}`,
        "Cache-Control": "public, max-age=300, s-maxage=31536000", ...cacheTags(id),
      },
    });
  };
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
export const fileName = (name) => `${(name.normalize("NFKD").replace(/[^\w\s-]/g, "").trim().replace(/\s+/g, "-").toLowerCase() || "app").slice(0, 60)}.lampapp`;

/**
 * The wish's own file, for a link that has one, only with the link's secret. PUT ?id=&part=<n>&of=<count> sends one part
 * (raw bytes, at most `FILE_LIMITS.part`); POST ?id= puts the parts together, checks that it's a file Lamp made and
 * within `FILE_LIMITS.total`, and gives it to the link in place of any it had; DELETE ?id= takes it away. The parts
 * are taken away once they're together, or with the link.
 */
/**
 * Work a request goes on with once it has answered (`waitUntil`, on Vercel), which the function is kept alive for up
 * to its whole time; elsewhere (a test, `npm run dev`) it's done before the answer.
 */
async function afterAnswering(work, env) {
  if (!env.VERCEL) return await work();
  const { waitUntil } = await import("@vercel/functions");
  waitUntil(work());
}

export function createFileHandler({ env = process.env, fetcher = fetch, store, limited = true, now = () => new Date(), later = (work) => afterAnswering(work, env) } = {}) {
  return async (request) => {
    const method = request.method;
    if (!["PUT", "POST", "DELETE"].includes(method)) return reply(405, { error: "method_not_allowed" }, { Allow: "PUT, POST, DELETE" });
    const url = new URL(request.url);
    const origin = request.headers.get("origin");
    if (origin && origin !== url.origin) return reply(403, { error: "origin_not_allowed" });
    const id = url.searchParams.get("id");
    if (!isID(id)) return reply(404, { error: "not_found" });
    // The wish's file, or (`what=page`) its playable page, sent and put together the same way.
    const page = url.searchParams.get("what") === "page";
    const partsKey = page ? "pageParts" : "parts";

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
      try { retry = await reserve(kept.limiter, ip, method === "PUT" ? PART_QUOTAS : method === "POST" ? UPDATE_QUOTAS : DELETE_QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }

    let uploaded = [];
    try {
      const record = await kept.get(id);
      if (!record || !secretMatches(bearer(request), record.secret)) return reply(404, { error: "not_found" });
      if (method === "PUT") {
        const at = await kept.putFile(id, `${page ? "page-part" : "part"}-${part.n}`, part.bytes);
        uploaded.push(at);
        // The part goes into the record as it is when it's written, never as it was read before the part went up: Lamp
        // sends a part again when its connection drops, and the first try can still be storing then, so another part
        // may have gone in meanwhile, which a write from the old read would lose. What it replaces is only set aside,
        // never removed here: putting the parts together may be reading it right now. It goes when they've been put
        // together, or with the link.
        for (let attempt = 0; ; attempt++) {
          const current = attempt ? await kept.get(id) : record;
          // Taken down while the part went up: nothing leads to it, so it goes now (the catch below takes it away).
          if (!current || !secretMatches(bearer(request), current.secret)) throw new Error("Gone");
          // A new count starts a new file: parts of an earlier one that never came together are set aside.
          const earlier = current[partsKey];
          const same = earlier?.of === part.of;
          const urls = same ? earlier.urls : {};
          const spare = [...(earlier?.spare ?? []), ...(same ? [] : Object.values(earlier?.urls ?? {})),
            ...(urls[part.n] && urls[part.n] !== at ? [urls[part.n]] : [])];
          if (await kept.swap(current, { ...current, [partsKey]: { of: part.of, urls: { ...urls, [part.n]: at }, spare } })) break;
          if (attempt === 4) throw new Error("Busy");
        }
        uploaded = [];
        return reply(204);
      }
      if (method === "DELETE") {
        // The page goes with the wish itself: a link that no longer carries the wish has nothing to play.
        const gone = [...pageBlobs(record), ...partBlobs(record.pageParts),
          ...(page ? [] : [record.file?.url, ...partBlobs(record.parts)])].filter(Boolean);
        const { page: _page, previousPage: _previousPage, pageParts: _pageParts, ...rest } = record;
        // The count stays with the link, so a file sent again later is newer to its followers than any before.
        const next = { ...(page ? rest : { ...rest, file: null, parts: undefined, fileVersion: record.file?.version ?? record.fileVersion }),
          pageVersion: record.page?.version ?? record.pageVersion };
        await kept.replace({ ...next, updated: now().toISOString() });
        await kept.removeImages(gone);
        await kept.forget(id);
        return reply(204);
      }
      const parts = record[partsKey];
      if (!parts || Object.keys(parts.urls).length !== parts.of) return reply(409, { error: "parts_missing" });
      const pieces = [];
      for (let n = 0; n < parts.of; n++) pieces.push(await kept.readFile(parts.urls[n]));
      const bytes = Buffer.concat(pieces);
      if (bytes.length > FILE_LIMITS.total) return reply(413, { error: "file_too_large" });
      if (page) {
        const files = readPage(bytes);
        if (!files) return reply(400, { error: "invalid_page" });
        // The count is the link's (`pageVersion`), so a page taken away and sent again never reuses a play address.
        const version = (record.page?.version ?? record.pageVersion ?? 0) + 1;
        // Checked, it's answered at once, and its files are stored after: a big game's page is hundreds of files, which
        // take longer than a Lamp waits for an answer, and a Lamp that heard nothing took the link's page down. The
        // link plays the page it had until this one is in; if this one never gets in, it goes on playing that one.
        await later(async () => {
          const stored = [];
          try {
            // Each version in a folder of its own, under a random part, so an old one never mixes with a new one.
            const token = randomBytes(12).toString("base64url");
            const urls = {}, sizes = {};
            // Many at a time, within what the blob store takes. Said in the log as it goes, so a page that doesn't get in
            // shows how far it got.
            const began = Date.now();
            console.log(`Page ${version} of ${id}: storing ${files.length} files`);
            for (let n = 0; n < files.length; n += PAGE_UPLOADS) {
              await Promise.all(files.slice(n, n + PAGE_UPLOADS).map(async (file) => {
                // Each file named as it starts, so a page that stops shows on which.
                console.log(`Page ${version} of ${id}: storing ${file.path} (${file.bytes.length} bytes)`);
                urls[file.path] = await kept.putPageFile(id, token, file.path, file.bytes);
                sizes[file.path] = file.bytes.length;
                stored.push(urls[file.path]);
              }));
              if ((n / PAGE_UPLOADS) % 10 === 9) console.log(`Page ${version} of ${id}: ${stored.length} of ${files.length} stored, ${Math.round((Date.now() - began) / 1000)}s`);
            }
            console.log(`Page ${version} of ${id}: all ${files.length} stored in ${Math.round((Date.now() - began) / 1000)}s`);
            // As the record is now, not as it was when the parts were read: the link may have changed meanwhile.
            const current = await kept.get(id);
            if (!current || !secretMatches(bearer(request), current.secret)) throw new Error("Gone");
            // The page it replaces stays playable as the version before, so a game open on it goes on finding its
            // files (a game loads its map as the player moves); the one before that goes now.
            const { pageParts: _pageParts, ...rest } = current;
            const previousPage = current.page ? { version: current.page.version, files: current.page.files, sizes: current.page.sizes } : undefined;
            if (!(await kept.replace({ ...rest, page: { version, files: urls, sizes }, ...(previousPage ? { previousPage } : {}),
              pageVersion: Math.max(version, current.pageVersion ?? 0), updated: now().toISOString() }))) throw new Error("Gone");
            await kept.removeImages([...Object.values(current.previousPage?.files ?? {}), ...partBlobs(parts)]);
            await kept.forget(id);
          } catch (error) {
            console.error(`Page ${version} of ${id} didn't get in, ${stored.length} of ${files.length} stored: ${error?.message ?? error}${error?.cause ? ` (${error.cause.message ?? error.cause})` : ""}`);
            try { await kept.removeImages(stored); } catch {}
          }
        });
        return reply(200, { version, files: files.length });
      }
      if (!isWishFile(bytes)) return reply(400, { error: "invalid_file" });
      const at = await kept.putFile(id, fileName(record.name), bytes);
      uploaded.push(at);
      const { parts: _parts, ...rest } = record;
      // Each file sent counts up, so the Lamps that follow the link can tell a newer one (`latest`).
      const version = (record.file?.version ?? (record.file ? 1 : record.fileVersion ?? 0)) + 1;
      if (!(await kept.replace({ ...rest, file: { url: at, size: bytes.length, version }, fileVersion: version, updated: now().toISOString() }))) {
        // Taken down meanwhile: the file and its parts go with it.
        await kept.removeImages([...uploaded, ...partBlobs(parts)]);
        uploaded = [];
        return reply(404, { error: "not_found" });
      }
      uploaded = [];
      await kept.removeImages([record.file?.url, ...partBlobs(parts)].filter(Boolean));
      await kept.forget(id);
      return reply(200, { url: at, size: bytes.length });
    } catch (error) {
      try { await kept.removeImages(uploaded); } catch {}
      return error?.message === "Gone" ? reply(404, { error: "not_found" }) : reply(503, { error: "service_unavailable" });
    }
  };
}
