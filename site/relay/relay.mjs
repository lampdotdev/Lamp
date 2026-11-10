// PROTOTYPE, not deployed. A relay between a game's page and a helper on the player's Mac (`lamp play <code>`), so the
// player's own agent can change the game they're playing and the rebuilt game comes back into the page.
//
// It stands outside the site's Vercel functions on purpose: rooms, pairing codes and builds live in this process's
// memory, which a function doesn't keep. Plain Node, no dependencies. Both sides dial in: the page and the helper each
// hold a stream of events (SSE) and send with POST, so nothing reaches into the player's Mac.
//
// Who is who is a secret, never an origin. A page that opens a room gets the page's secret; the short code it shows is
// single-use, expires, and is rate-limited, and the helper trades it for the helper's own secret. Every later call
// carries one of the two. The game itself is served from another origin, one host per room under the play host, which
// never sees either secret, the way lamp.dev serves a shared game from `<id>.play.lamp.dev`. Origin checks only add to
// that: they keep a browser page that isn't ours (the game's frame among them) from sending anything.
//
// Run: node site/relay/relay.mjs --game <folder of a static game> [--port 4700] [--play-port 4701]

import { createHash, randomBytes, randomInt, timingSafeEqual } from "node:crypto";
import { readFileSync, readdirSync, lstatSync } from "node:fs";
import { createServer } from "node:http";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { pageType, readZip } from "../lib/shared-wishes.js";

const HERE = dirname(fileURLToPath(import.meta.url));

/** How much the relay takes and keeps. A build is unpacked under the site's own page limits, lowered for memory. */
export const RELAY_LIMITS = {
  codeMs: 5 * 60_000,          // a pairing code lives this long
  pairsPerMinute: 5,           // tries at a code from one address
  roomsPerMinute: 10,          // rooms one address opens
  prompt: 2000,                // characters in a request
  build: { files: 3000, total: 64_000_000 },
  upload: 32_000_000,          // bytes of a packed build
  events: 500,                 // events a room keeps for a stream that reconnects
  versions: 2,                 // builds a room keeps: the one shown, and the one before for a frame still on it
};

const CODE_LETTERS = "ABCDEFGHJKMNPQRSTUVWXYZ23456789";
const newCode = () => Array.from({ length: 6 }, () => CODE_LETTERS[randomInt(CODE_LETTERS.length)]).join("");
const newSecret = () => randomBytes(32).toString("base64url");
const hashOf = (secret) => createHash("sha256").update(String(secret)).digest();
const sameHash = (a, b) => !!a && !!b && a.length === b.length && timingSafeEqual(a, b);

/** The files of a static game's folder, as the hosted copy would hold them: nothing hidden, no link followed. */
export function filesOf(folder) {
  const files = new Map();
  const walk = (dir, prefix) => {
    for (const name of readdirSync(dir)) {
      if (name.startsWith(".") || name === "node_modules") continue;
      const path = join(dir, name), stat = lstatSync(path);
      if (stat.isDirectory()) walk(path, `${prefix}${name}/`);
      else if (stat.isFile()) files.set(prefix + name, readFileSync(path));
    }
  };
  walk(folder, "");
  if (!files.has("index.html")) throw new Error(`${folder} has no index.html`);
  return files;
}

/**
 * The relay: `request` answers the page's origin (the stand-in page and the API), `play` the play host (the game's
 * files only). `now` and `log` are given by a test.
 */
export function createRelay({ game, pageOrigin, playOrigin, limits = RELAY_LIMITS, now = () => Date.now(), log = console.log }) {
  const rooms = new Map();        // room id → room
  const codes = new Map();        // code → room id
  const tries = new Map();        // address + what → times tried in the last minute
  const play = new URL(playOrigin);
  const roomHost = (room) => `${room}.${play.hostname}`;
  const playURL = (room, version) => `${play.protocol}//${roomHost(room)}${play.port ? `:${play.port}` : ""}/v/${version}/`;

  const limited = (address, what, most) => {
    const key = `${what} ${address}`, recent = (tries.get(key) ?? []).filter((at) => now() - at < 60_000);
    recent.push(now());
    tries.set(key, recent);
    return recent.length > most;
  };

  // MARK: Events

  const emit = (room, type, data) => {
    const event = { seq: ++room.seq, type, data };
    room.events.push(event);
    if (room.events.length > limits.events) room.events.shift();
    for (const stream of room.pages) send(stream, event);
  };
  const send = (stream, { seq, type, data }) => stream.write(`id: ${seq}\nevent: ${type}\ndata: ${JSON.stringify(data)}\n\n`);
  const toHelper = (room, request) => { if (room.helper) room.helper.write(`event: request\ndata: ${JSON.stringify({ id: request.id, prompt: request.prompt })}\n\n`); };

  const summary = (room) => ({
    room: room.id, version: room.current, play: playURL(room.id, room.current), paired: !!room.helperHash,
    helper: !!room.helper, code: room.helperHash ? null : room.code, expires: room.helperHash ? null : room.codeExpires,
    requests: room.order.map((id) => publicRequest(room.requests.get(id))),
  });
  const publicRequest = ({ id, prompt, state, message, version }) => ({ id, prompt, state, message, version });

  const giveCode = (room) => {
    if (room.code) codes.delete(room.code);
    let code;
    do code = newCode(); while (codes.has(code));
    room.code = code;
    room.codeExpires = now() + limits.codeMs;
    codes.set(code, room.id);
  };

  // MARK: Answers

  const reply = (response, status, body, headers = {}) => {
    response.writeHead(status, { "Content-Type": "application/json", "Cache-Control": "no-store", ...headers });
    response.end(JSON.stringify(body));
  };
  const readBody = (request, most) => new Promise((done, failed) => {
    const parts = [];
    let size = 0;
    request.on("data", (part) => {
      size += part.length;
      if (size > most) { failed(Object.assign(new Error("too large"), { status: 413 })); request.destroy(); return; }
      parts.push(part);
    });
    request.on("end", () => done(Buffer.concat(parts)));
    request.on("error", failed);
  });
  const readJSON = async (request) => {
    try { return JSON.parse((await readBody(request, 16_384)).toString("utf8")); } catch (error) { if (error.status) throw error; return null; }
  };
  const bearer = (request) => /^Bearer (\S+)$/.exec(request.headers.authorization ?? "")?.[1] ?? null;
  const roomFor = (request, which) => {
    const secret = bearer(request);
    if (!secret) return null;
    const hash = hashOf(secret);
    for (const room of rooms.values()) if (sameHash(room[which], hash)) return room;
    return null;
  };

  const PAGE_HEADERS = {
    "Content-Security-Policy": `default-src 'none'; script-src 'self'; style-src 'self'; connect-src 'self'; frame-src ${play.protocol}//*.${play.host}; img-src 'self' data:; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`,
    "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", "Referrer-Policy": "no-referrer",
  };
  const staticFile = (response, name, type) => {
    response.writeHead(200, { "Content-Type": type, ...PAGE_HEADERS });
    response.end(readFileSync(join(HERE, name)));
  };

  async function request(request, response) {
    const url = new URL(request.url, pageOrigin);
    const address = request.socket.remoteAddress ?? "?";
    const origin = request.headers.origin;
    try {
      if (request.method === "GET" && (url.pathname === "/" || url.pathname === "/w/demo")) {
        if (url.pathname === "/") { response.writeHead(302, { Location: "/w/demo" }); response.end(); return; }
        return staticFile(response, "page.html", "text/html; charset=utf-8");
      }
      if (request.method === "GET" && url.pathname === "/w/page.js") return staticFile(response, "page.js", "text/javascript; charset=utf-8");
      if (request.method === "GET" && url.pathname === "/w/page.css") return staticFile(response, "page.css", "text/css; charset=utf-8");

      // The page's side. A browser always says where a POST comes from; only the stand-in page's own origin may send.
      if (url.pathname.startsWith("/api/page/") || url.pathname === "/api/rooms") {
        if (request.method === "POST" && origin !== pageOrigin) {
          log(`refused ${request.method} ${url.pathname}: from origin ${origin ?? "(none)"}`);
          return reply(response, 403, { error: "wrong_origin" });
        }
      }

      if (request.method === "POST" && url.pathname === "/api/rooms") {
        if (limited(address, "room", limits.roomsPerMinute)) return reply(response, 429, { error: "slow_down" });
        const id = randomBytes(8).toString("hex"), secret = newSecret();
        const room = {
          id, pageHash: hashOf(secret), helperHash: null, code: null, codeExpires: 0, seq: 0, events: [], pages: new Set(), helper: null,
          versions: new Map([[1, { files: game, request: null }]]), current: 1, requests: new Map(), order: [], busy: false,
        };
        rooms.set(id, room);
        giveCode(room);
        log(`room ${id}: opened, code ${room.code} until ${new Date(room.codeExpires).toISOString()}`);
        return reply(response, 200, { secret, ...summary(room) });
      }

      if (url.pathname.startsWith("/api/page/")) {
        const room = roomFor(request, "pageHash");
        if (!room) {
          log(`refused ${request.method} ${url.pathname}: no page secret for any room`);
          return reply(response, 401, { error: "not_this_page" });
        }
        if (request.method === "GET" && url.pathname === "/api/page/events") {
          response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive" });
          response.write(`event: room\ndata: ${JSON.stringify(summary(room))}\n\n`);
          const since = Number(url.searchParams.get("since") ?? request.headers["last-event-id"] ?? 0);
          for (const event of room.events) if (event.seq > since) send(response, event);
          room.pages.add(response);
          const beat = setInterval(() => response.write(": beat\n\n"), 15_000);
          request.on("close", () => { clearInterval(beat); room.pages.delete(response); });
          return;
        }
        if (request.method === "POST" && url.pathname === "/api/page/code") {
          if (room.helperHash) return reply(response, 409, { error: "already_paired" });
          giveCode(room);
          log(`room ${room.id}: new code ${room.code}`);
          emit(room, "room", summary(room));
          return reply(response, 200, summary(room));
        }
        if (request.method === "POST" && url.pathname === "/api/page/requests") {
          const body = await readJSON(request);
          const id = String(body?.id ?? ""), prompt = String(body?.prompt ?? "").trim();
          if (!/^[\w-]{8,64}$/.test(id) || !prompt || prompt.length > limits.prompt) return reply(response, 400, { error: "bad_request" });
          // The same request sent again (the page retried after a dropped answer) is the one already taken.
          const known = room.requests.get(id);
          if (known) return reply(response, 200, publicRequest(known));
          if (!room.helperHash) return reply(response, 409, { error: "no_helper" });
          const taken = { id, prompt, state: "queued", message: null, version: null, at: now() };
          room.requests.set(id, taken);
          room.order.push(id);
          log(`room ${room.id}: request ${id} queued (${prompt.length} characters)`);
          emit(room, "request", publicRequest(taken));
          toHelper(room, taken);
          return reply(response, 200, publicRequest(taken));
        }
        return reply(response, 404, { error: "not_found" });
      }

      // The helper's side. It's never a browser: anything a browser sent (it always names its origin on a POST, and on
      // a cross-origin GET) is refused, so no web page can try codes or speak as a helper.
      if (url.pathname.startsWith("/api/helper/") || url.pathname === "/api/pair") {
        if (origin !== undefined || request.headers["sec-fetch-site"]) {
          log(`refused ${request.method} ${url.pathname}: a browser sent it (origin ${origin ?? "(none)"})`);
          return reply(response, 403, { error: "not_a_helper" });
        }
      }

      if (request.method === "POST" && url.pathname === "/api/pair") {
        if (limited(address, "pair", limits.pairsPerMinute)) {
          log(`refused pairing from ${address}: too many tries`);
          return reply(response, 429, { error: "slow_down" });
        }
        const body = await readJSON(request);
        const code = String(body?.code ?? "").toUpperCase().replace(/[^A-Z0-9]/g, "");
        const room = rooms.get(codes.get(code));
        // One answer for a code that never was, one already used and one that's run out, so a guess learns nothing.
        if (!room || room.code !== code || room.codeExpires <= now() || room.helperHash) {
          const why = !room ? "unknown or already used" : room.codeExpires <= now() ? "expired" : "already used";
          if (room && room.codeExpires <= now()) { codes.delete(code); room.code = null; emit(room, "room", summary(room)); }
          log(`refused pairing with code ${code || "(empty)"}: ${why}`);
          return reply(response, 404, { error: "no_such_code" });
        }
        const secret = newSecret();
        room.helperHash = hashOf(secret);
        codes.delete(code);
        room.code = null;
        log(`room ${room.id}: paired`);
        emit(room, "room", summary(room));
        return reply(response, 200, { room: room.id, secret, version: room.current });
      }

      if (url.pathname.startsWith("/api/helper/")) {
        const room = roomFor(request, "helperHash");
        if (!room) {
          log(`refused ${request.method} ${url.pathname}: no helper secret for any room`);
          return reply(response, 401, { error: "not_this_helper" });
        }
        if (request.method === "GET" && url.pathname === "/api/helper/events") {
          // One helper stream at a time: a reconnect replaces the one before.
          room.helper?.end();
          response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive" });
          response.write(`event: hello\ndata: ${JSON.stringify({ room: room.id, version: room.current })}\n\n`);
          room.helper = response;
          emit(room, "room", summary(room));
          // What the helper hasn't finished, again: it knows which it has started and never runs one twice.
          for (const id of room.order) { const taken = room.requests.get(id); if (taken.state === "queued" || taken.state === "running") toHelper(room, taken); }
          const beat = setInterval(() => response.write(": beat\n\n"), 15_000);
          request.on("close", () => {
            clearInterval(beat);
            if (room.helper === response) { room.helper = null; emit(room, "room", summary(room)); }
          });
          return;
        }
        if (request.method === "GET" && url.pathname === "/api/helper/build") {
          const { files } = room.versions.get(room.current);
          response.writeHead(200, { "Content-Type": "application/json", "Cache-Control": "no-store" });
          response.end(JSON.stringify({ version: room.current, files: Object.fromEntries([...files].map(([path, bytes]) => [path, bytes.toString("base64")])) }));
          return;
        }
        if (request.method === "POST" && url.pathname === "/api/helper/status") {
          const body = await readJSON(request);
          const taken = room.requests.get(String(body?.id ?? ""));
          if (!taken) return reply(response, 404, { error: "no_such_request" });
          const state = String(body?.state ?? "");
          if (!["running", "failed", "unchanged"].includes(state)) return reply(response, 400, { error: "bad_state" });
          if (["done", "failed", "unchanged"].includes(taken.state)) return reply(response, 200, publicRequest(taken));
          taken.state = state;
          taken.message = String(body?.message ?? "").slice(0, 500) || null;
          log(`room ${room.id}: request ${taken.id} ${state}${taken.message ? `: ${taken.message}` : ""}`);
          emit(room, "request", publicRequest(taken));
          return reply(response, 200, publicRequest(taken));
        }
        if (request.method === "PUT" && url.pathname === "/api/helper/build") {
          const taken = room.requests.get(url.searchParams.get("request") ?? "");
          if (!taken) return reply(response, 404, { error: "no_such_request" });
          // A build sent again for a request already published is the version it made, not another.
          if (taken.state === "done") return reply(response, 200, publicRequest(taken));
          if (taken.state !== "running") return reply(response, 409, { error: "not_running" });
          const bytes = await readBody(request, limits.upload);
          const files = readZip(bytes, limits.build);
          if (!files || !files.some((file) => file.path === "index.html")) {
            log(`room ${room.id}: request ${taken.id}: refused a build that isn't a page within the limits`);
            return reply(response, 422, { error: "not_a_page" });
          }
          const version = room.current + 1;
          room.versions.set(version, { files: new Map(files.map((file) => [file.path, file.bytes])), request: taken.id });
          room.current = version;
          for (const old of room.versions.keys()) if (old <= version - limits.versions) room.versions.delete(old);
          Object.assign(taken, { state: "done", version, message: null });
          log(`room ${room.id}: request ${taken.id} published version ${version} (${files.length} files)`);
          emit(room, "request", publicRequest(taken));
          emit(room, "build", { version, play: playURL(room.id, version), request: taken.id });
          return reply(response, 200, publicRequest(taken));
        }
        return reply(response, 404, { error: "not_found" });
      }

      return reply(response, 404, { error: "not_found" });
    } catch (error) {
      if (!response.headersSent) reply(response, error.status ?? 500, { error: error.status === 413 ? "too_large" : "failed" });
      if (!error.status) log(`error: ${error.stack ?? error}`);
    }
  }

  // MARK: The play host: a room's game, on a host of the room's own, and nothing else.

  function servePlay(request, response) {
    if (request.method !== "GET" && request.method !== "HEAD") { response.writeHead(405, { Allow: "GET, HEAD" }); response.end(); return; }
    const host = (request.headers.host ?? "").replace(/:\d+$/, "");
    const id = host.endsWith(`.${play.hostname}`) ? host.slice(0, -play.hostname.length - 1) : null;
    const room = id ? rooms.get(id) : null;
    const match = /^\/v\/(\d+)\/(.*)$/.exec(new URL(request.url, playOrigin).pathname);
    const kept = room && match ? room.versions.get(Number(match[1])) : null;
    let path = match ? decodeURIComponent(match[2]) : "";
    if (!path || path.endsWith("/")) path += "index.html";
    const bytes = kept?.files.get(path);
    if (!bytes) { response.writeHead(404, { "Cache-Control": "no-store" }); response.end(); return; }
    response.writeHead(200, {
      "Content-Type": pageType(path), "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff",
      // Framed only by the stand-in page, and on an agent cluster of its own, as the play host does on lamp.dev.
      "Content-Security-Policy": `frame-ancestors ${pageOrigin}`, "Origin-Agent-Cluster": "?1",
    });
    response.end(request.method === "HEAD" ? undefined : bytes);
  }

  return { request, play: servePlay, rooms };
}

// MARK: Run

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const args = process.argv.slice(2);
  const option = (name, fallback) => { const at = args.indexOf(`--${name}`); return at >= 0 ? args[at + 1] : fallback; };
  const folder = option("game");
  if (!folder) { console.error("usage: node site/relay/relay.mjs --game <folder> [--port 4700] [--play-port 4701]"); process.exit(64); }
  const port = Number(option("port", 4700)), playPort = Number(option("play-port", 4701));
  const limits = { ...RELAY_LIMITS, ...(process.env.RELAY_CODE_TTL_MS ? { codeMs: Number(process.env.RELAY_CODE_TTL_MS) } : {}) };
  const stamp = () => new Date().toISOString().slice(11, 23);
  const relay = createRelay({
    game: filesOf(resolve(folder)), limits, log: (line) => console.log(`${stamp()} ${line}`),
    // The page and the game are on different sites: 127.0.0.1 for the page, <room>.localhost for each room's game.
    pageOrigin: `http://127.0.0.1:${port}`, playOrigin: `http://localhost:${playPort}`,
  });
  createServer(relay.request).listen(port, "127.0.0.1");
  createServer(relay.play).listen(playPort, "127.0.0.1");
  console.log(`${stamp()} relay: page at http://127.0.0.1:${port}/w/demo, games at http://<room>.localhost:${playPort}`);
}
