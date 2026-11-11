import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { quotaScript } from "./quota.js";
import { casScript } from "./relay-store.js";
import { isID, oneFile, pageType } from "./shared-wishes.js";

// The relay (RELAY.md): a shared game's page asks the player's own agent, on their own Mac, to change the game, and
// the rebuilt game comes back into the page. The page and the helper (`lamp play <code>`) each ask these functions,
// every couple of seconds while something's happening and less often while nothing is; nothing here runs between
// their calls. What a room is lives in the relay's own Redis, its files in the relay's own private Blob store.

/** What a room may hold and for how long. */
export const RELAY_LIMITS = {
  codeMs: 5 * 60_000,             // a pairing code works once, for this long
  idleMs: 2 * 3600_000,           // a room no one has used for this long is gone
  lifeMs: 24 * 3600_000,          // and every room is gone after this long
  runMs: 20 * 60_000,             // a change running longer than this, with no word, is reported as uncertain
  helperMs: 45_000,               // a helper heard from within this long is shown as there
  prompt: 1000,                   // characters in a request
  requests: 30,                   // requests in a room's life
  kept: 20,                       // requests a room lists
  queued: 5,                      // requests waiting at once
  files: 3000, file: 16_000_000, total: 64_000_000,   // a version: files, the largest, all together
  stored: 256_000_000,            // bytes a room keeps in Blob, every version together
  uploadMs: 10 * 60_000,          // how long an upload's permission lasts
  post: 4_000_000,                // bytes of a game sent whole by an AI app (Vercel takes at most 4.5 MB in a request)
  postsPerHour: 30,               // games a room takes that way in an hour
  posted: 20,                     // idempotency keys a room remembers
  seedMs: 20_000,                 // how long one call spends copying the link's page into a room
  seedAtOnce: 4,                  // files copied at once
};

/** The calls one address, and everyone together, may make. */
export const RELAY_QUOTAS = {
  open: [{ name: "open", perIP: true, limit: 10, seconds: 3600 }, { name: "open-all", limit: 500, seconds: 86_400 }],
  pair: [{ name: "pair", perIP: true, limit: 5, seconds: 60 }, { name: "pair-hour", perIP: true, limit: 30, seconds: 3600 }],
  ask: [{ name: "ask", perIP: true, limit: 60, seconds: 3600 }, { name: "ask-all", limit: 5000, seconds: 86_400 }],
  upload: [{ name: "upload", perIP: true, limit: 60, seconds: 3600 }],
  post: [{ name: "post", perIP: true, limit: 120, seconds: 3600 }, { name: "post-all", limit: 20_000, seconds: 86_400 }],
};

const CODE_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";

/** An empty room's first version, until the player's AI app sends a game. */
const WAITING_PAGE = `<!doctype html>
<html lang="en"><head><meta charset="utf-8"><title>Waiting for a game</title>
<style>html,body{margin:0;height:100%;background:#111;color:#bbb;font:16px system-ui,sans-serif;display:grid;place-items:center}</style>
</head><body><p>Waiting for your game…</p></body></html>
`;
const ROOM = /^[0-9a-f]{16}$/;
const hashOf = (secret) => createHash("sha256").update(String(secret)).digest("hex");
const same = (a, b) => typeof a === "string" && typeof b === "string" && a.length === b.length && timingSafeEqual(Buffer.from(a), Buffer.from(b));
const finished = (state) => ["done", "failed", "unchanged", "uncertain"].includes(state);

/** Seconds to wait, or 0 when the call may go ahead and has been counted: quota.js's script, in the relay's Redis. */
export async function relayReserve(db, ip, quotas) {
  const keys = quotas.map((q) => `${db.limiter.prefix}:${q.name}${q.perIP ? ":" + db.limiter.ipHash(ip) : ""}`);
  return Number(await db.command(["EVAL", quotaScript, String(keys.length), ...keys, ...quotas.map((q) => String(q.limit)), ...quotas.map((q) => String(q.seconds))]));
}

/** A path in a game as the site takes one (`readZip`): relative, never stepping up, nothing hidden. */
export function goodPath(path) {
  return typeof path === "string" && path.length > 0 && path.length <= 512 && !path.startsWith("/") && !path.includes("\\") && !path.includes("\0")
    && path.split("/").every((part) => part && part !== "." && part !== ".." && !part.startsWith("."));
}

/** Where a room's game plays: a host of its own under the play host (`r-<room>.play.lamp.dev`), apart from every link's. */
export function relayPlayOrigin(base, room) {
  if (!base || !ROOM.test(room)) return null;
  const url = new URL(base);
  return `${url.protocol}//r-${room}.${url.host}`;
}

/** A room's keys in the relay's Redis, and its files' place in Blob. */
function keysFor(scope) {
  const base = `lamp:relay:{${scope}}`;
  return {
    room: (id) => `${base}:room:${id}`, rev: (id) => `${base}:rev:${id}`, code: (code) => `${base}:code:${code}`,
    // A version's list of files is kept under an id of its own, never under its number, and is never written over: two
    // versions sent at once each write their own, and only the room's compare-and-set decides which one is played.
    build: (id, build) => `${base}:build:${id}:${build}`, blobs: (id) => `${base}:blobs:${id}`,
    seed: (id) => `${base}:seed:${id}`, seeding: (id) => `${base}:seeding:${id}`,
    prefix: `relay/${scope}/`, file: (id, build, sha) => `relay/${scope}/${id}/${build}/${sha}`,
  };
}

/** The key of the list of files the room plays as `version`, or null when it plays no such version. */
const buildKey = (keys, room, version) => (room.builds?.[version] ? keys.build(room.id, room.builds[version]) : null);

/**
 * Moves the room on to a new version, inside its compare-and-set: the version before stays playable, and the list of
 * the one before that is answered for removal once the move is in.
 */
function advance(room, build) {
  const dropped = room.previous ? room.builds?.[room.previous] ?? null : null;
  room.builds = { ...(room.current ? { [room.current]: room.builds?.[room.current] } : {}), [room.current + 1]: build };
  room.previous = room.current || null;
  room.current += 1;
  return dropped;
}

export function createRelayHandler({ env = process.env, db, blobs, wishes, now = () => Date.now(), limits = RELAY_LIMITS, quotas = RELAY_QUOTAS, limited = true, site = null, playBase = null } = {}) {
  const keys = keysFor(db.scope);
  const siteOrigin = (url) => (typeof site === "function" ? site(url) : site) ?? env.LAMP_SITE_ORIGIN ?? "https://lamp.dev";
  const playOf = (room, version) => { const origin = relayPlayOrigin((typeof playBase === "function" ? playBase() : playBase) ?? env.LAMP_PLAY_ORIGIN, room); return origin ? `${origin}/relay-play/${room}/${version}/` : null; };

  // MARK: The room, read and changed whole

  const read = async (id) => {
    const [json, rev] = await db.command(["MGET", keys.room(id), keys.rev(id)]);
    if (!json) return null;
    const room = JSON.parse(json);
    return room.ends <= now() ? null : { room, rev: rev ?? "0" };
  };
  const lifetime = (room) => Math.max(1, Math.min(limits.idleMs, room.ends - now()));
  /** Changes a room with `change` (which may say no by returning false) until it goes in. Null when there's none. */
  const update = async (id, change) => {
    for (let tries = 0; tries < 8; tries++) {
      const found = await read(id);
      if (!found) return null;
      const room = structuredClone(found.room);
      const said = change(room);
      if (said === false) return { room: found.room, rev: found.rev, refused: true };
      room.active = now();
      const rev = String(Number(found.rev) + 1);
      if (Number(await db.command(["EVAL", casScript, "2", keys.room(id), keys.rev(id), found.rev, JSON.stringify(room), rev, String(lifetime(room))])) === 1) {
        return { room, rev, said };
      }
    }
    throw new Error("Room busy");
  };
  /** A change that's run too long with no word from the helper is reported as uncertain: never run again. */
  const settle = (room) => {
    const running = room.requests.find((request) => request.id === room.running);
    if (running && now() - running.started > limits.runMs) {
      Object.assign(running, { state: "uncertain", message: "Your Mac stopped answering while it worked on this.", ended: now() });
      room.running = null;
      return true;
    }
    return false;
  };

  const summary = ({ room, rev }) => ({
    rev, room: room.id, wish: room.wish, version: room.current, play: room.current ? playOf(room.id, room.current) : null, ends: room.ends,
    seeding: room.seeding ?? null, mode: room.mode ?? "helper", posted: room.postedAt ?? null,
    paired: !!room.helperHash, helper: !!room.helperSeen && now() - room.helperSeen < limits.helperMs,
    code: room.helperHash ? null : room.codeEnds > now() ? room.code : null, codeEnds: room.helperHash ? null : room.codeEnds,
    requests: room.requests.map(({ id, prompt, state, message, version }) => ({ id, prompt, state, message, version })),
  });

  const newCode = async (room) => {
    for (let tries = 0; tries < 10; tries++) {
      const code = Array.from({ length: 6 }, () => CODE_LETTERS[randomInt(CODE_LETTERS.length)]).join("");
      if (await db.command(["SET", keys.code(code), room, "PX", String(limits.codeMs), "NX"])) return code;
    }
    throw new Error("No code free");
  };

  // MARK: Answers

  const reply = (status, body, headers = {}) => Response.json(body, { status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers } });
  // What the app reads back: plain words, one line, since it's a person's AI app that reads them and says what happened.
  const text = (status, words, headers = {}) => new Response(`${words}\n`, { status, headers: { "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers } });
  const etag = (version) => `"${version}"`;
  const sent = (room, version, again) => new Response(JSON.stringify({ version, play: playOf(room.id, version), again }) + "\n", {
    status: again ? 200 : 201, headers: { "Content-Type": "application/json", "Cache-Control": "no-store", ETag: etag(version) },
  });
  const ipOf = (request) => (request.headers.get("x-forwarded-for") ?? "").split(",")[0].trim() || request.headers.get("x-real-ip") || "unknown";
  const slowed = async (request, which) => {
    if (!limited) return 0;
    try { return await relayReserve(db, ipOf(request), quotas[which]); } catch { return -1; }
  };
  const readJSON = async (request, most = 600_000) => {
    const text = await request.text();
    if (text.length > most) return null;
    try { const body = JSON.parse(text); return body && typeof body === "object" && !Array.isArray(body) ? body : null; } catch { return null; }
  };
  /** The room a credential opens, and which side holds it: `<room>.<secret>`, compared by its hash. */
  const holder = async (request, side) => {
    const [id, secret] = (/^Bearer (\S+)$/.exec(request.headers.get("authorization") ?? "")?.[1] ?? "").split(".");
    if (!ROOM.test(id ?? "") || !secret) return null;
    const found = await read(id);
    return found && same(found.room[{ page: "pageHash", helper: "helperHash", post: "postHash" }[side]], hashOf(secret)) ? found : null;
  };

  return async function relay(request) {
    const url = new URL(request.url);
    const op = url.searchParams.get("op") ?? "";
    const origin = request.headers.get("origin");
    try {
      // The page's side: from the site's own pages only (a browser always names where a POST comes from), and every
      // call but `open` with the page's credential. The game's frame is on another host, so it's turned away here,
      // and it never holds the credential anyway.
      // An AI app sending the whole game: its own key, never the page's or the helper's.
      if (op === "game") {
        if (origin !== null || request.headers.get("sec-fetch-site")) return text(403, "This address is for an app on your computer, not a web page.");
        if (request.method === "GET") return await gameSource(request, url);
        if (request.method === "POST") return await post(request, url);
        return text(405, "Use GET to read the game, POST to send it.", { Allow: "GET, POST" });
      }
      if (["open", "seed", "state", "code", "postkey", "ask", "close"].includes(op)) {
        if (request.method === "POST" && origin !== siteOrigin(url)) return reply(403, { error: "wrong_origin" });
        if (op === "open") return await open(request);
        const found = await holder(request, "page");
        if (!found) return reply(401, { error: "not_this_page" });
        if (op === "state" && request.method === "GET") return await state(request, found);
        if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
        if (op === "seed") return await seed(found.room.id);
        if (op === "code") return await code(found);
        if (op === "postkey") return await postKey(found);
        if (op === "ask") return await ask(request, found);
        if (op === "close") return await close(found);
      }
      // The helper's side: never from a browser, so no web page can try codes or speak as a helper.
      if (["pair", "next", "claim", "finish", "reconcile", "files", "file", "upload", "commit"].includes(op)) {
        if (origin !== null || request.headers.get("sec-fetch-site")) return reply(403, { error: "not_a_helper" });
        if (op === "pair") return await pair(request);
        const found = await holder(request, "helper");
        if (!found) return reply(401, { error: "not_this_helper" });
        if (op === "next" && request.method === "GET") return await next(found);
        if (op === "files" && request.method === "GET") return await fileList(url, found);
        if (op === "file" && request.method === "GET") return await file(url, found);
        if (request.method !== "POST") return reply(405, { error: "method_not_allowed" });
        const body = await readJSON(request);
        if (!body) return reply(400, { error: "bad_request" });
        if (op === "claim") return await claim(body, found);
        if (op === "finish") return await finish(body, found);
        if (op === "reconcile") return await reconcile(body, found);
        if (op === "upload") return await upload(request, body, found);
        if (op === "commit") return await commit(body, found);
      }
      return reply(404, { error: "not_found" });
    } catch (error) {
      console.error("relay:", op, error?.name, error?.message);
      return reply(error?.message === "Room busy" ? 409 : 503, { error: "service_unavailable" });
    }
  };

  // MARK: The page

  /**
   * A room for a link's page. The room keeps its own copy of the page as version 1, in the relay's store: the link's
   * files go when the sharer sends it again, and a room's game must not go with them. The copy is made a few files at
   * a time, by this call and the page's `op=seed` after it, since a big page takes longer than one call may run. Only
   * once it's whole does the room play, and give a code.
   */
  async function open(request) {
    const body = await readJSON(request, 4096);
    const wish = body?.wish ?? null, mode = body?.mode === "post" ? "post" : "helper";
    // A room the player's AI app sends whole games to may start empty; one for the helper starts from a link's page.
    if (wish === null ? mode !== "post" : !isID(wish)) return reply(400, { error: "bad_request" });
    const record = wish ? await wishes.get(wish) : null;
    const source = wish ? record?.page?.files : { "index.html": null };
    if (!source || !("index.html" in source)) return reply(404, { error: "no_page" });
    const paths = Object.keys(source);
    // An AI app reads and sends the game as one file, so a room for one takes only a game that's exactly index.html;
    // refused here, a stale page or a typed address fails at once instead of at the app's first read.
    if (mode === "post" && !oneFile(source)) return reply(422, { error: "not_one_file" });
    const sizes = record?.page?.sizes ?? {};
    if (paths.length > limits.files || !paths.every(goodPath) || paths.some((path) => (sizes[path] ?? 0) > limits.file)
      || Object.values(sizes).reduce((sum, size) => sum + size, 0) > limits.total) return reply(422, { error: "too_large" });
    const wait = await slowed(request, "open");
    if (wait < 0) return reply(503, { error: "service_unavailable" });
    if (wait) return reply(429, { error: "slow_down" }, { "Retry-After": String(wait) });
    const id = randomBytes(8).toString("hex"), secret = randomBytes(32).toString("base64url"), postSecret = randomBytes(32).toString("base64url");
    const room = {
      id, wish, mode, created: now(), active: now(), ends: now() + limits.lifeMs, pageHash: hashOf(secret), helperHash: null, helperSeen: 0,
      postHash: mode === "post" ? hashOf(postSecret) : null, posted: {}, postTimes: [], postedAt: null, stored: 0,
      code: null, codeEnds: 0, current: 0, previous: null, builds: {}, running: null, count: 0, requests: [], pending: null,
      seeding: { copied: 0, total: paths.length, failed: null },
    };
    const ms = String(lifetime(room));
    if (!wish) {
      // An empty room's version 1 is a page of its own that waits for the first game.
      const bytes = Buffer.from(WAITING_PAGE);
      const at = keys.file(id, "seed", createHash("sha256").update(bytes).digest("hex"));
      await blobs.put(at, bytes);
      const build = randomBytes(6).toString("hex");
      await db.command(["SET", keys.build(id, build), JSON.stringify({ files: { "index.html": { at, sha256: at.split("/").pop(), size: bytes.length } } }), "PX", String(limits.lifeMs), "NX"]);
      room.seeding = null;
      advance(room, build);
      await db.command(["SET", keys.blobs(id), "{}", "PX", String(limits.lifeMs)]);
      if (Number(await db.command(["EVAL", casScript, "2", keys.room(id), keys.rev(id), "0", JSON.stringify(room), "1", ms])) !== 1) throw new Error("Room busy");
      return reply(200, { token: `${id}.${secret}`, postKey: `${id}.${postSecret}`, ...summary({ room, rev: "1" }) });
    }
    await db.command(["SET", keys.seed(id), JSON.stringify({ source, done: {} }), "PX", String(limits.lifeMs)]);
    await db.command(["SET", keys.blobs(id), "{}", "PX", String(limits.lifeMs)]);
    if (Number(await db.command(["EVAL", casScript, "2", keys.room(id), keys.rev(id), "0", JSON.stringify(room), "1", ms])) !== 1) throw new Error("Room busy");
    const answer = await seed(id);
    return reply(answer.status, { token: `${id}.${secret}`, ...(mode === "post" ? { postKey: `${id}.${postSecret}` } : {}), ...(await answer.json()) });
  }

  /**
   * Copies the next files of the link's page into the room, for as long as one call may: each read whole, checked
   * against the limits, kept under its SHA-256 (so the first change sends only what it changed), and listed. One call
   * copies at a time (a lease in Redis); another meanwhile just answers how far it's got. With every file in, version 1
   * is written and the room moves to it, with a code, in one step.
   */
  async function seed(id) {
    const found = await read(id);
    if (!found) return reply(404, { error: "room_gone" });
    if (!found.room.seeding || found.room.seeding.failed) return reply(200, summary(found));
    if (!(await db.command(["SET", keys.seeding(id), "1", "PX", String(limits.seedMs * 3), "NX"]))) return reply(200, summary(found));
    try {
      const plan = JSON.parse((await db.command(["GET", keys.seed(id)])) ?? "null");
      if (!plan) return reply(200, summary(found));
      const started = now(), left = Object.keys(plan.source).filter((path) => !plan.done[path]);
      let total = Object.values(plan.done).reduce((sum, file) => sum + file.size, 0), failed = null;
      const shas = new Map(Object.values(plan.done).map((file) => [file.sha256, file.at]));
      while (left.length && !failed && now() - started < limits.seedMs) {
        const batch = left.splice(0, limits.seedAtOnce);
        const read = await Promise.all(batch.map(async (path) => {
          try { return { path, bytes: await wishes.readFile(plan.source[path]) }; } catch { return { path, bytes: null }; }
        }));
        for (const { path, bytes } of read) {
          if (!bytes) { failed = "The game's files couldn't be read."; break; }
          total += bytes.length;
          if (bytes.length > limits.file || total > limits.total) { failed = "This game is too big to change here."; break; }
          const sha256 = createHash("sha256").update(bytes).digest("hex");
          if (!shas.has(sha256)) { const at = keys.file(id, "seed", sha256); await blobs.put(at, bytes); shas.set(sha256, at); }
          plan.done[path] = { at: shas.get(sha256), sha256, size: bytes.length };
        }
      }
      const copied = Object.keys(plan.done).length, whole = copied === Object.keys(plan.source).length;
      await db.command(["SET", keys.seed(id), JSON.stringify(plan), "PX", String(Math.max(1, found.room.ends - now()))]);
      const build = whole && !failed ? randomBytes(6).toString("hex") : null;
      if (build) {
        const ms = String(Math.max(1, found.room.ends - now()));
        await db.command(["SET", keys.build(id, build), JSON.stringify({ files: plan.done }), "PX", ms, "NX"]);
        const kept = Object.fromEntries(Object.values(plan.done).map((file) => [file.sha256, { pathname: file.at, size: file.size }]));
        await db.command(["SET", keys.blobs(id), JSON.stringify(kept), "PX", ms]);
      }
      // A room for the helper gives its code once it plays; one an AI app sends to has its key already.
      const code = build && found.room.mode !== "post" ? await newCode(id) : null;
      const changed = await update(id, (room) => {
        if (!room.seeding) return false;
        room.seeding = { copied, total: room.seeding.total, failed };
        if (build) { room.seeding = null; advance(room, build); }
        if (code) { room.code = code; room.codeEnds = now() + limits.codeMs; }
      });
      if (whole && !failed) await db.command(["DEL", keys.seed(id)]);
      return reply(200, summary(changed ?? found));
    } finally {
      await db.command(["DEL", keys.seeding(id)]);
    }
  }

  async function state(request, found) {
    let current = found;
    if (settle(structuredClone(found.room))) current = (await update(found.room.id, settle)) ?? found;
    const known = new URL(request.url).searchParams.get("rev");
    if (known && known === current.rev) return reply(200, { rev: current.rev, same: true });
    return reply(200, summary(current));
  }

  async function code(found) {
    const id = found.room.id;
    const fresh = await newCode(id);
    const changed = await update(id, (room) => {
      if (room.helperHash) return false;
      room.code = fresh; room.codeEnds = now() + limits.codeMs;
    });
    if (!changed || changed.refused) { await db.command(["DEL", keys.code(fresh)]); return reply(409, { error: "already_paired" }); }
    if (found.room.code) await db.command(["DEL", keys.code(found.room.code)]);
    return reply(200, summary(changed));
  }

  async function ask(request, found) {
    const body = await readJSON(request, 8192);
    const id = String(body?.id ?? ""), prompt = String(body?.prompt ?? "").trim();
    if (!/^[\w-]{8,64}$/.test(id) || !prompt || prompt.length > limits.prompt) return reply(400, { error: "bad_request" });
    // The same request sent again (the page retried after a dropped answer) is the one already taken.
    const known = found.room.requests.find((request) => request.id === id);
    if (known) return reply(200, summary(found));
    if (!found.room.helperHash) return reply(409, { error: "no_helper" });
    if (found.room.count >= limits.requests) return reply(429, { error: "room_used_up" });
    if (found.room.requests.filter((request) => request.state === "queued").length >= limits.queued) return reply(429, { error: "too_many_waiting" });
    const wait = await slowed(request, "ask");
    if (wait < 0) return reply(503, { error: "service_unavailable" });
    if (wait) return reply(429, { error: "slow_down" }, { "Retry-After": String(wait) });
    const changed = await update(found.room.id, (room) => {
      if (room.requests.some((request) => request.id === id)) return;
      if (room.count >= limits.requests) return false;
      room.count++;
      room.requests.push({ id, prompt, state: "queued", message: null, version: null, at: now() });
      // The oldest finished requests drop off the list; nothing waiting or running ever does.
      while (room.requests.length > limits.kept) {
        const old = room.requests.findIndex((request) => finished(request.state));
        if (old < 0) break;
        room.requests.splice(old, 1);
      }
    });
    if (!changed) return reply(404, { error: "room_gone" });
    if (changed.refused) return reply(429, { error: "room_used_up" });
    return reply(200, summary(changed));
  }

  async function close(found) {
    const id = found.room.id;
    // Its files stay in Blob until the cleanup, which removes every file of a room that's gone.
    await db.command(["DEL", keys.room(id), keys.rev(id), keys.blobs(id), ...Object.values(found.room.builds ?? {}).map((build) => keys.build(id, build)),
      ...(found.room.code ? [keys.code(found.room.code)] : [])]);
    return reply(200, { closed: true });
  }

  /** A new key for the AI app, in place of the one it had: the old one stops working at once. */
  async function postKey(found) {
    if (found.room.mode !== "post") return reply(409, { error: "not_direct" });
    const secret = randomBytes(32).toString("base64url");
    const changed = await update(found.room.id, (room) => { room.postHash = hashOf(secret); });
    if (!changed) return reply(404, { error: "room_gone" });
    return reply(200, { postKey: `${found.room.id}.${secret}`, ...summary(changed) });
  }

  // MARK: An AI app sending the whole game


  /** The room a post key opens, for the room the address names; the room must take whole games and play one file. */
  async function poster(request, url) {
    const found = await holder(request, "post");
    if (!found || found.room.id !== url.searchParams.get("room")) return { refused: text(401, "That key doesn't open this room. Copy the words from the game's page again.") };
    if (found.room.mode !== "post") return { refused: text(409, "This room isn't taking games from an app.") };
    if (found.room.seeding) return { refused: text(409, "The room is still getting its game ready. Try again in a few seconds.") };
    const key = buildKey(keys, found.room, found.room.current);
    const build = key ? JSON.parse((await db.command(["GET", key])) ?? "null") : null;
    const paths = Object.keys(build?.files ?? {});
    // Only a game that's one file goes back and forth whole: one of several files can't be read or replaced as one.
    if (paths.length !== 1 || paths[0] !== "index.html") return { refused: text(409, "This game is more than one file, so it can't be sent as one. Change it with lamp play instead.") };
    return { found, entry: build.files["index.html"] };
  }

  /**
   * The game's one file as the app reads it: plain text that never runs (no-store, nosniff, a sandbox with nothing
   * allowed), with the version it is as its ETag for the app's If-Match.
   */
  async function gameSource(request, url) {
    const { found, entry, refused } = await poster(request, url);
    if (refused) return refused;
    const opened = await blobs.open(entry.at);
    if (!opened) return text(503, "The game couldn't be read. Try again.");
    return new Response(opened.body, {
      headers: {
        "Content-Type": "text/plain; charset=utf-8", "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
        "Content-Security-Policy": "default-src 'none'; sandbox", "Content-Disposition": 'attachment; filename="game.html"',
        ETag: etag(found.room.current), ...(opened.size ? { "Content-Length": String(opened.size) } : {}),
      },
    });
  }

  /** The request's body, as long as it's at most `most` bytes: null past that, whatever the request says its length is. */
  async function bodyUpTo(request, most) {
    if (Number(request.headers.get("content-length") ?? 0) > most) return null;
    if (!request.body) return Buffer.alloc(0);
    const parts = [];
    let size = 0;
    for await (const part of request.body) {
      size += part.length;
      if (size > most) return null;
      parts.push(Buffer.from(part));
    }
    return Buffer.concat(parts);
  }

  /**
   * A whole game from the player's AI app, as the room's next version. Checked first for a quick answer, then kept in
   * Blob under a name of its own and listed under an id of its own; it's published only by the room's compare-and-set,
   * which checks again, against the room as it's replaced, the key, the base version (If-Match), the idempotency key and
   * the room's quotas. Anything off there and nothing is played; what was written is left for the cleanup.
   */
  async function post(request, url) {
    const { found, refused } = await poster(request, url);
    if (refused) return refused;
    const presented = hashOf((/^Bearer \S+\.(\S+)$/.exec(request.headers.get("authorization") ?? ""))?.[1] ?? "");
    const match = /^\s*(?:W\/)?"?(\d+)"?\s*$/.exec(request.headers.get("if-match") ?? "");
    if (!match) return text(428, `Send If-Match with the version you changed: read the game first, and use its ETag (now ${etag(found.room.current)}).`);
    const base = Number(match[1]);
    const bytes = await bodyUpTo(request, limits.post);
    if (!bytes) return text(413, `The game is more than ${limits.post.toLocaleString("en-US")} bytes. Make it smaller: one file, nothing big inlined.`);
    if (!bytes.length) return text(400, "The game was empty. Send the file with --data-binary @game.html.");
    let html;
    try { html = new TextDecoder("utf-8", { fatal: true }).decode(bytes); } catch { return text(415, "The game isn't UTF-8 text. Send the HTML file as it is."); }
    if (!/<(?:!doctype\s+html|html|head|body|script|canvas)[\s>]/i.test(html)) return text(422, "That isn't an HTML page. Send the whole game as one HTML file.");
    const sha256 = createHash("sha256").update(bytes).digest("hex");
    const given = request.headers.get("idempotency-key");
    if (given !== null && !/^[\w.:-]{8,128}$/.test(given)) return text(400, "Idempotency-Key is 8 to 128 letters, digits, dots, colons, dashes or underscores.");
    // Without a key of the app's own, the same file sent again on the same version is the one already taken.
    const idempotency = given ?? `${base}:${sha256}`;
    // A retry of a game already taken is answered as it was, whatever the room has played since.
    const known = found.room.posted?.[idempotency];
    if (known) return sent(found.room, known.version, true);
    if (base !== found.room.current) return text(412, `The game changed since you read it: it's version ${found.room.current} now. Read it again, and send your change on top of it.`, { ETag: etag(found.room.current) });
    const recent = (found.room.postTimes ?? []).filter((at) => now() - at < 3600_000);
    if (recent.length >= limits.postsPerHour) return text(429, `This room has taken ${limits.postsPerHour} games in the last hour. Wait a while.`);
    if ((found.room.stored ?? 0) + bytes.length > limits.stored) return text(507, "This room is full. Open a new one from the game's page.");
    const wait = await slowed(request, "post");
    if (wait < 0) return text(503, "lamp.dev isn't answering. Try again.");
    if (wait) return text(429, `Too many games sent from here. Wait ${wait} seconds.`, { "Retry-After": String(wait) });

    const build = randomBytes(6).toString("hex");
    const at = keys.file(found.room.id, `post-${build}`, sha256);
    await blobs.put(at, bytes);
    const ms = String(Math.max(1, found.room.ends - now()));
    await db.command(["SET", keys.build(found.room.id, build), JSON.stringify({ files: { "index.html": { at, sha256, size: bytes.length } } }), "PX", ms, "NX"]);
    let dropped = null, why = null;
    const changed = await update(found.room.id, (room) => {
      if (!same(room.postHash, presented)) { why = text(401, "That key was replaced. Copy the words from the game's page again."); return false; }
      if (room.posted?.[idempotency]) return false;
      if (room.current !== base) { why = text(412, `The game changed since you read it: it's version ${room.current} now. Read it again.`, { ETag: etag(room.current) }); return false; }
      if (room.running) { why = text(409, "A change is being made to the game right now. Try again when it's done."); return false; }
      const times = (room.postTimes ?? []).filter((time) => now() - time < 3600_000);
      if (times.length >= limits.postsPerHour) { why = text(429, `This room has taken ${limits.postsPerHour} games in the last hour.`); return false; }
      if ((room.stored ?? 0) + bytes.length > limits.stored) { why = text(507, "This room is full."); return false; }
      dropped = advance(room, build);
      room.postTimes = [...times, now()];
      room.stored = (room.stored ?? 0) + bytes.length;
      room.postedAt = now();
      room.posted = Object.fromEntries([...Object.entries(room.posted ?? {}), [idempotency, { version: room.current }]].slice(-limits.posted));
    });
    if (!changed) return text(404, "This room has closed. Open a new one from the game's page.");
    if (changed.refused) {
      await db.command(["DEL", keys.build(found.room.id, build)]);
      const again = changed.room.posted?.[idempotency];
      return again ? sent(changed.room, again.version, true) : why ?? text(409, "The game wasn't taken. Try again.");
    }
    if (dropped) await db.command(["DEL", keys.build(found.room.id, dropped)]);
    return sent(changed.room, changed.room.current, false);
  }


  // MARK: The helper

  async function pair(request) {
    const wait = await slowed(request, "pair");
    if (wait < 0) return reply(503, { error: "service_unavailable" });
    if (wait) return reply(429, { error: "slow_down" }, { "Retry-After": String(wait) });
    const body = await readJSON(request, 1024);
    const code = String(body?.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
    // Taken out as it's read, so it works once; Redis lets it run out at its time. One answer for every code that
    // doesn't work, so a guess learns nothing.
    const id = code.length === 6 ? await db.command(["GETDEL", keys.code(code)]) : null;
    if (!id) return reply(404, { error: "no_such_code" });
    const secret = randomBytes(32).toString("base64url");
    const changed = await update(id, (room) => {
      if (room.helperHash || room.code !== code || room.codeEnds <= now()) return false;
      room.helperHash = hashOf(secret); room.helperSeen = now(); room.code = null; room.codeEnds = 0;
    });
    if (!changed || changed.refused) return reply(404, { error: "no_such_code" });
    return reply(200, { room: id, token: `${id}.${secret}`, version: changed.room.current });
  }

  /** The helper's poll: it's there, and what's next. Its word is kept at most every 20 seconds. */
  async function next(found) {
    let current = found;
    if (now() - found.room.helperSeen > 20_000 || settle(structuredClone(found.room))) {
      current = (await update(found.room.id, (room) => { room.helperSeen = now(); settle(room); })) ?? found;
    }
    const { room } = current;
    const waiting = room.running ? null : room.requests.find((request) => request.state === "queued");
    return reply(200, { version: room.current, running: room.running, next: waiting ? { id: waiting.id, prompt: waiting.prompt } : null, ends: room.ends });
  }

  async function claim(body, found) {
    const id = String(body.id ?? "");
    const changed = await update(found.room.id, (room) => {
      settle(room);
      const request = room.requests.find((one) => one.id === id);
      if (!request) return false;
      if (room.running === id) return;
      if (room.running || request.state !== "queued") return false;
      Object.assign(request, { state: "running", started: now() });
      room.running = id;
    });
    if (!changed) return reply(404, { error: "room_gone" });
    if (changed.refused) return reply(409, { error: "not_yours_to_run", running: changed.room.running });
    return reply(200, { id, state: "running", version: changed.room.current });
  }

  async function finish(body, found) {
    const id = String(body.id ?? ""), state = String(body.state ?? "");
    if (!["failed", "unchanged"].includes(state)) return reply(400, { error: "bad_state" });
    const message = String(body.message ?? "").slice(0, 300) || null;
    const changed = await update(found.room.id, (room) => {
      const request = room.requests.find((one) => one.id === id);
      if (!request || finished(request.state)) return false;
      if (room.running !== id) return false;
      Object.assign(request, { state, message, ended: now() });
      room.running = null;
      if (room.pending?.request === id) room.pending = null;
    });
    if (!changed) return reply(404, { error: "room_gone" });
    const request = changed.room.requests.find((one) => one.id === id);
    return reply(changed.refused && !request ? 404 : 200, request ? { id, state: request.state, version: request.version } : { error: "no_such_request" });
  }

  /**
   * The helper's journal against the room's, as the helper starts or comes back: a change the room thinks is running
   * that the helper didn't finish (it stopped, or never heard it was its) is uncertain, said so, and never run again.
   * The room's word on every request goes back, so the helper settles its own journal by it.
   */
  async function reconcile(body, found) {
    const journal = body.journal && typeof body.journal === "object" ? body.journal : {};
    const changed = await update(found.room.id, (room) => {
      room.helperSeen = now();
      const running = room.requests.find((one) => one.id === room.running);
      if (running && journal[running.id] !== "running") {
        Object.assign(running, { state: "uncertain", message: "Your Mac stopped while it worked on this, so it wasn't run again.", ended: now() });
        room.running = null;
        room.pending = null;
      }
    });
    if (!changed) return reply(404, { error: "room_gone" });
    return reply(200, { version: changed.room.current, requests: changed.room.requests.map(({ id, state, version }) => ({ id, state, version })) });
  }

  async function fileList(url, found) {
    const version = Number(url.searchParams.get("v") ?? found.room.current);
    if (version !== found.room.current && version !== found.room.previous) return reply(404, { error: "no_such_version" });
    const key = buildKey(keys, found.room, version);
    const build = key ? JSON.parse((await db.command(["GET", key])) ?? "null") : null;
    if (!build) return reply(404, { error: "no_such_version" });
    return reply(200, { version, files: Object.entries(build.files).map(([path, file]) => ({ path, size: file.size, sha256: file.sha256 ?? null })) });
  }

  async function file(url, found) {
    const version = Number(url.searchParams.get("v") ?? found.room.current), path = url.searchParams.get("path") ?? "";
    const opened = await openFile(found.room.id, version, path, found.room);
    if (!opened) return new Response(null, { status: 404, headers: { "Cache-Control": "no-store" } });
    return new Response(opened.body, { headers: { "Content-Type": "application/octet-stream", "Cache-Control": "no-store", ...(opened.size ? { "Content-Length": String(opened.size) } : {}) } });
  }

  async function openFile(id, version, path, room) {
    const key = version === room.current || version === room.previous ? buildKey(keys, room, version) : null;
    const build = key ? JSON.parse((await db.command(["GET", key])) ?? "null") : null;
    const entry = build?.files?.[path];
    if (!entry) return null;
    return blobs.open(entry.at);
  }

  /**
   * A version's list of files from the helper, each with its size and SHA-256: checked whole before anything is sent,
   * then permission to send, straight to Blob, each file the room doesn't already keep.
   */
  async function upload(request, body, found) {
    const id = String(body.id ?? "");
    const { room } = found;
    if (room.running !== id) return reply(409, { error: "not_running" });
    const list = Array.isArray(body.files) ? body.files : null;
    if (!list || !list.length || list.length > limits.files) return reply(422, { error: "too_many_files" });
    const files = {};
    let total = 0;
    for (const one of list) {
      if (!goodPath(one?.path) || files[one.path] || !Number.isInteger(one.size) || one.size < 0 || one.size > limits.file || !/^[0-9a-f]{64}$/.test(one.sha256 ?? "")) {
        return reply(422, { error: "bad_file", path: typeof one?.path === "string" ? one.path.slice(0, 200) : null });
      }
      total += one.size;
      files[one.path] = { sha256: one.sha256, size: one.size };
    }
    if (total > limits.total) return reply(422, { error: "too_large" });
    if (!files["index.html"]) return reply(422, { error: "no_index" });
    const wait = await slowed(request, "upload");
    if (wait < 0) return reply(503, { error: "service_unavailable" });
    if (wait) return reply(429, { error: "slow_down" }, { "Retry-After": String(wait) });
    const kept = JSON.parse((await db.command(["GET", keys.blobs(room.id)])) ?? "{}");
    const stored = Object.values(kept).reduce((sum, blob) => sum + blob.size, 0);
    const build = randomBytes(6).toString("hex");
    const missing = new Map();
    for (const { sha256, size } of Object.values(files)) if (!kept[sha256] && !missing.has(sha256)) missing.set(sha256, size);
    const adding = [...missing.values()].reduce((sum, size) => sum + size, 0);
    if (stored + adding > limits.stored) return reply(422, { error: "room_full" });
    const changed = await update(room.id, (next) => {
      if (next.running !== id) return false;
      next.pending = { request: id, build, files, at: now() };
    });
    if (!changed || changed.refused) return reply(409, { error: "not_running" });
    const uploads = [];
    for (const [sha256, size] of missing) {
      // The type the play host serves a file with comes from its path when played, never from what was sent.
      uploads.push({ sha256, ...(await blobs.uploadTarget({ pathname: keys.file(room.id, build, sha256), size, contentType: "application/octet-stream", ms: limits.uploadMs })) });
    }
    return reply(200, { build, uploads });
  }

  /**
   * The version, once the helper has sent its files: each new file read back from Blob and checked against its size and
   * SHA-256, then the room moved to it in one step. Anything off and the room stays on the version it had.
   */
  async function commit(body, found) {
    const id = String(body.id ?? ""), build = String(body.build ?? "");
    const { room } = found;
    const request = room.requests.find((one) => one.id === id);
    if (request?.state === "done") return reply(200, { id, state: "done", version: request.version });
    if (room.running !== id || room.pending?.request !== id || room.pending.build !== build) return reply(409, { error: "not_running" });
    const kept = JSON.parse((await db.command(["GET", keys.blobs(room.id)])) ?? "{}");
    const added = {};
    for (const { sha256, size } of Object.values(room.pending.files)) {
      if (kept[sha256] || added[sha256]) continue;
      const pathname = keys.file(room.id, build, sha256);
      const opened = await blobs.open(pathname);
      const checked = opened ? await digest(opened.body, size) : null;
      if (!checked || checked.size !== size || checked.sha256 !== sha256) {
        await update(room.id, (next) => { if (next.pending?.build === build) next.pending = null; });
        return reply(422, { error: "file_not_as_listed", sha256 });
      }
      added[sha256] = { pathname, size };
    }
    const files = Object.fromEntries(Object.entries(room.pending.files).map(([path, { sha256, size }]) => [path, { at: (kept[sha256] ?? added[sha256]).pathname, sha256, size }]));
    const ms = String(Math.max(1, room.ends - now()));
    // The version's list is written first, under the upload's own id and never over another: it isn't played until
    // the room's compare-and-set points at it, which is the one step that publishes it.
    if (!(await db.command(["SET", keys.build(room.id, build), JSON.stringify({ files }), "PX", ms, "NX"]))) return reply(409, { error: "not_running" });
    const allKept = { ...kept, ...added };
    await db.command(["SET", keys.blobs(room.id), JSON.stringify(allKept), "PX", ms]);
    let dropped = null;
    const changed = await update(room.id, (next) => {
      const taken = next.requests.find((one) => one.id === id);
      if (next.running !== id || next.pending?.build !== build || !taken) return false;
      dropped = advance(next, build);
      Object.assign(taken, { state: "done", version: next.current, message: null, ended: now() });
      next.running = null;
      next.pending = null;
    });
    if (!changed || changed.refused) { await db.command(["DEL", keys.build(room.id, build)]); return reply(409, { error: "not_running" }); }
    // The version two back is no longer played: its list goes now, and the cleanup removes files nothing points at.
    if (dropped) await db.command(["DEL", keys.build(room.id, dropped)]);
    return reply(200, { id, state: "done", version: changed.room.current });
  }
}

/** A stream's or a buffer's size and SHA-256, reading no more than `most` bytes past what's expected. */
async function digest(body, expected) {
  const hash = createHash("sha256");
  let size = 0;
  if (Buffer.isBuffer(body) || body instanceof Uint8Array) { hash.update(body); size = body.length; }
  else {
    for await (const part of body) {
      size += part.length;
      if (size > expected) return { size, sha256: null };
      hash.update(part);
    }
  }
  return { size, sha256: hash.digest("hex") };
}

/**
 * A room's game, one file at a time (`/relay-play/<room>/<version>/<path>`): only on the room's own host
 * (`relayPlayOrigin`), only into a frame on the site's own pages, only the version it plays now or the one before.
 * It holds no credential and answers nothing but files.
 */
export function createRelayPlayHandler({ env = process.env, db, blobs, anyHost = false, site = null, playBase = null } = {}) {
  const keys = keysFor(db.scope);
  return async (request) => {
    const headers = { "Cache-Control": "no-store", "Origin-Agent-Cluster": "?1" };
    if (request.method !== "GET" && request.method !== "HEAD") return new Response(null, { status: 405, headers: { ...headers, Allow: "GET, HEAD" } });
    const url = new URL(request.url);
    const room = url.searchParams.get("room") ?? "", version = Number(url.searchParams.get("v"));
    const own = relayPlayOrigin((typeof playBase === "function" ? playBase() : playBase) ?? env.LAMP_PLAY_ORIGIN, room);
    if (!own || (!anyHost && url.host !== new URL(own).host)) return new Response(null, { status: 404, headers });
    let path = url.searchParams.get("path") || "index.html";
    if (path.endsWith("/")) path += "index.html";
    if (!goodPath(path) || !Number.isInteger(version)) return new Response(null, { status: 404, headers });
    try {
      const [json] = await db.command(["MGET", keys.room(room)]);
      const kept = json ? JSON.parse(json) : null;
      const key = kept && (version === kept.current || version === kept.previous) ? buildKey(keys, kept, version) : null;
      if (!key) return new Response(null, { status: 404, headers });
      const build = JSON.parse((await db.command(["GET", key])) ?? "null");
      const entry = build?.files?.[path] ?? build?.files?.[`${path}.html`] ?? build?.files?.[`${path}/index.html`];
      if (!entry) return new Response(null, { status: 404, headers });
      const name = build.files[path] ? path : build.files[`${path}.html`] ? `${path}.html` : `${path}/index.html`;
      let body = null, size = 0;
      if (request.method !== "HEAD") {
        const opened = await blobs.open(entry.at);
        if (!opened) return new Response(null, { status: 404, headers });
        ({ body, size } = opened);
      }
      const siteOrigin = (typeof site === "function" ? site(url) : site) ?? env.LAMP_SITE_ORIGIN ?? "https://lamp.dev";
      return new Response(body, {
        headers: {
          ...headers, "Content-Type": pageType(name), "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
          ...(size ? { "Content-Length": String(size) } : {}),
          // Framed only by the site's own page, whose frame is sandboxed. A page is sandboxed by its own answer too, for
          // when its address is opened by itself: scripts run and keep their saves on the room's own host, but it can't
          // take over the window it's in or open others.
          "Content-Security-Policy": `frame-ancestors ${siteOrigin}${/\.html?$/i.test(name) ? "; sandbox allow-scripts allow-same-origin allow-pointer-lock allow-forms allow-modals" : ""}`,
        },
      });
    } catch (error) {
      console.error("relay play:", error?.name, error?.message);
      return new Response(null, { status: 503, headers });
    }
  };
}

/**
 * The scheduled cleanup: Redis lets a room run out by itself, but Blob keeps its files until they're removed. Every file
 * of a room that's gone goes, and in a room that's still there, every file no version points at that's older than an
 * upload's permission (one left by an upload that didn't finish, or by a version no longer played).
 */
export async function cleanupRelay({ db, blobs, now = () => Date.now(), limits = RELAY_LIMITS }) {
  const keys = keysFor(db.scope);
  const all = await blobs.list(keys.prefix);
  const byRoom = new Map();
  for (const blob of all) {
    const room = blob.pathname.slice(keys.prefix.length).split("/")[0];
    if (!byRoom.has(room)) byRoom.set(room, []);
    byRoom.get(room).push(blob);
  }
  const removed = [];
  for (const [id, files] of byRoom) {
    const [json] = ROOM.test(id) ? await db.command(["MGET", keys.room(id)]) : [null];
    const room = json ? JSON.parse(json) : null;
    if (!room || room.ends <= now()) { removed.push(...files); continue; }
    // A room still copying the link's page keeps all it has copied.
    if (room.seeding) continue;
    const used = new Set();
    for (const version of [room.current, room.previous].filter(Boolean)) {
      const key = buildKey(keys, room, version);
      const build = key ? JSON.parse((await db.command(["GET", key])) ?? "null") : null;
      for (const entry of Object.values(build?.files ?? {})) used.add(entry.at);
    }
    const pending = room.pending?.build;
    // A version being sent may name files the room kept from before: they stay until it's in or given up.
    if (room.pending) {
      const kept = JSON.parse((await db.command(["GET", keys.blobs(id)])) ?? "{}");
      for (const { sha256 } of Object.values(room.pending.files)) if (kept[sha256]) used.add(kept[sha256].pathname);
    }
    for (const blob of files) {
      if (used.has(blob.pathname) || now() - blob.uploadedAt < limits.uploadMs * 2) continue;
      if (pending && blob.pathname.includes(`/${pending}/`)) continue;
      removed.push(blob);
    }
    // The room's own list of what it keeps loses what's removed, so a later version sends those files again.
    const gone = new Set(removed.filter((blob) => blob.pathname.startsWith(`${keys.prefix}${id}/`)).map((blob) => blob.pathname));
    if (gone.size) {
      const kept = JSON.parse((await db.command(["GET", keys.blobs(id)])) ?? "{}");
      for (const [sha, blob] of Object.entries(kept)) if (gone.has(blob.pathname)) delete kept[sha];
      await db.command(["SET", keys.blobs(id), JSON.stringify(kept), "PX", String(Math.max(1, room.ends - now()))]);
    }
  }
  await blobs.remove(removed.map((blob) => blob.url));
  return { files: all.length, removed: removed.length, rooms: byRoom.size };
}
