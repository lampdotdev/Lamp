// Lamp's controller relay: phones become controllers for a TV app. Each session is one TV app (or Lamp's preview
// of it, which Lamp connects for) and up to eight phones. The relay hands out the session's phone page at an
// address of the session's own, so no two apps' pages share an origin, over https where it's hosted, which phones'
// browsers ask for before they give a page their motion sensors. It passes buttons, sticks and tilt from each phone
// to the host and small messages back, and keeps nothing: no message is written down, a session lives in memory
// and goes when its host has been gone a while.
//
// Run it with `node relay/server.js`; see relay/README.md for its settings.

import { createServer } from 'node:http';
import { readFileSync } from 'node:fs';
import { accept } from './websocket.js';
import { issue, check, newSecret, newSessionId, lifetimes } from './credentials.js';

export const limits = {
  players: 8,
  message: 1024,              // bytes, any message on a socket
  page: 2 * 1024 * 1024,      // bytes, a session's page whole
  files: 200,
  perSecond: 120,             // messages a phone may send each second, a little over a phone's screen rate
  hostBacklog: 16 * 1024,     // bytes waiting for the host past which movement is dropped rather than queued
  silence: 15_000,            // ms without a word before a socket is taken to be gone
  hostAway: 10 * 60_000,      // ms a session waits for its host to come back
  sessionsPerAddress: 30,     // sessions one address may open in an hour
  sessions: 5000,
};

const library = readFileSync(new URL('./public/lamp-controller.js', import.meta.url), 'utf8');

export function startRelay({
  port = 8787,
  bind = '127.0.0.1',
  secret = newSecret(),
  api = `http://localhost:${port}`,
  pages = `http://{session}.localhost:${port}`,
} = {}) {
  const sessions = new Map();
  const opened = new Map();   // address -> times it opened a session in the last hour
  const socketURL = api.replace(/^http/, 'ws') + '/v1/socket';
  const pageOrigin = (id) => pages.replace('{session}', id);
  // A URL's host is lower-cased, so the stand-in for the session is too.
  const pageHost = new RegExp('^' + new URL(pages.replace('{session}', 'sessionid')).host
    .replace(/[.*+?^${}()|[\]\\]/g, '\\$&').replace('sessionid', '([a-z0-9]{20})') + '$');

  const server = createServer((request, response) => {
    const page = pageHost.exec(request.headers.host ?? '');
    if (page) return servePage(sessions.get(page[1]), request, response);
    return api_(request, response);
  });

  server.on('upgrade', (request, stream) => {
    if (new URL(request.url, 'http://relay').pathname !== '/v1/socket') return stream.destroy();
    const socket = accept(request, stream, { maxMessage: limits.message });
    if (socket) greet(socket, request.headers.origin);
  });

  // MARK: The API, for Lamp

  async function api_(request, response) {
    const url = new URL(request.url, 'http://relay');
    const parts = url.pathname.split('/').filter(Boolean);
    try {
      if (request.method === 'GET' && url.pathname === '/v1/health') return json(response, 200, { ok: true });
      if (request.method === 'POST' && url.pathname === '/v1/sessions') return openSession(request, response);
      if (request.method === 'PUT' && parts.length === 4 && parts[0] === 'v1' && parts[1] === 'sessions' && parts[3] === 'page') {
        const session = sessions.get(parts[2]);
        if (!session || !check(secret, bearer(request), { kinds: ['host'], session: session.id })) return json(response, 403, { error: 'Not this session\'s host.' });
        return putPage(session, request, response);
      }
      return json(response, 404, { error: 'Not found' });
    } catch (error) {
      return json(response, 400, { error: error.message });
    }
  }

  function openSession(request, response) {
    const address = request.socket.remoteAddress ?? '';
    const now = Date.now();
    const times = (opened.get(address) ?? []).filter((at) => now - at < 3_600_000);
    if (times.length >= limits.sessionsPerAddress || sessions.size >= limits.sessions) {
      return json(response, 429, { error: 'Too many sessions. Try again later.' });
    }
    opened.set(address, [...times, now]);
    const id = newSessionId();
    sessions.set(id, { id, started: now, host: null, hostGoneAt: now, controllers: new Map(), files: new Map() });
    return json(response, 201, {
      session: id,
      host: issue(secret, { kind: 'host', session: id }),
      socket: socketURL,
      page: pageOrigin(id) + '/',
    });
  }

  async function putPage(session, request, response) {
    const body = await read(request, limits.page * 2);
    const files = JSON.parse(body).files;
    if (!files || typeof files !== 'object') throw new Error('No files.');
    const kept = new Map();
    let size = 0;
    for (const [path, base64] of Object.entries(files)) {
      const names = path.split('/');
      if (!names.every((name) => /^[A-Za-z0-9_-][A-Za-z0-9._-]*$/.test(name))) throw new Error(`A file can't be named "${path}".`);
      const data = Buffer.from(String(base64), 'base64');
      size += data.length;
      kept.set(path, data);
    }
    if (kept.size > limits.files || size > limits.page) throw new Error('The page is too big.');
    if (!kept.has('index.html')) throw new Error('The page has no index.html.');
    session.files = kept;
    response.writeHead(204).end();
  }

  // MARK: The phone page, at the session's own address

  function servePage(session, request, response) {
    if (!session || (request.method !== 'GET' && request.method !== 'HEAD')) return text(response, 404, 'This game has ended. Scan the code on the TV again.');
    let path = decodeURIComponent(new URL(request.url, 'http://relay').pathname.slice(1));
    if (path === '' || path.endsWith('/')) path += 'index.html';
    const headers = {
      'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff',
      'Referrer-Policy': 'no-referrer',
      // The page reaches nothing but its own files and the relay's socket, and no other site may frame it.
      'Content-Security-Policy': `default-src 'self'; script-src 'self' 'unsafe-inline'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; media-src 'self' data:; font-src 'self' data:; connect-src ${socketURL}; frame-ancestors 'none'; base-uri 'none'; form-action 'none'`,
    };
    if (path === 'lamp-controller.js') {
      const body = `var LAMP_RELAY = ${JSON.stringify({ socket: socketURL, session: session.id })};\n` + library;
      response.writeHead(200, { ...headers, 'Content-Type': 'text/javascript; charset=utf-8' });
      return response.end(request.method === 'HEAD' ? undefined : body);
    }
    const data = session.files.get(path);
    if (!data) return text(response, 404, 'Not found');
    response.writeHead(200, { ...headers, 'Content-Type': type(path), 'Content-Length': data.length });
    response.end(request.method === 'HEAD' ? undefined : data);
  }

  // MARK: Sockets

  function greet(socket, origin) {
    socket.heard = Date.now();
    const waiting = setTimeout(() => socket.close(4001), 5000);
    socket.on('close', () => clearTimeout(waiting));
    socket.on('message', (text) => {
      clearTimeout(waiting);
      const hello = parse(text);
      const session = hello && sessions.get(hello.session);
      if (!session || hello.t !== 'hello') return socket.close(4003);
      const credential = check(secret, hello.credential, { kinds: ['host', 'join', 'controller'], session: session.id });
      if (!credential) return socket.close(4003);
      if (credential.k === 'host') return joinAsHost(session, socket);
      // A phone's page is the session's own; a page elsewhere holding a phone's link isn't let in as a player.
      if (origin !== pageOrigin(session.id)) return socket.close(4003);
      return joinAsPlayer(session, socket, credential);
    });
  }

  function joinAsHost(session, socket) {
    if (session.host?.open) session.host.close(4000);
    session.host = socket;
    session.hostGoneAt = null;
    socket.heard = Date.now();
    send(socket, { t: 'welcome', role: 'host', players: [...session.controllers.keys()], now: Date.now() });
    for (const controller of session.controllers.values()) send(controller.socket, { t: 'state', host: true });
    socket.on('message', (text) => {
      socket.heard = Date.now();
      const message = parse(text);
      if (!message) return;
      if (message.t === 'link') {
        const join = issue(secret, { kind: 'join', session: session.id });
        return send(socket, { t: 'link', url: `${pageOrigin(session.id)}/#${join}`, expires: Date.now() + lifetimes.join * 1000 });
      }
      if (message.t === 'send' && message.data !== undefined) {
        const to = message.player ? [session.controllers.get(message.player)].filter(Boolean) : [...session.controllers.values()];
        for (const controller of to) send(controller.socket, { t: 'message', data: message.data });
      }
    });
    socket.on('close', () => {
      if (session.host !== socket) return;
      session.host = null;
      session.hostGoneAt = Date.now();
      for (const controller of session.controllers.values()) send(controller.socket, { t: 'state', host: false });
    });
  }

  function joinAsPlayer(session, socket, credential) {
    let player = credential.k === 'controller' ? credential.p : undefined;
    if (player === undefined) {
      for (let p = 1; p <= limits.players; p++) if (!session.controllers.has(p)) { player = p; break; }
      if (player === undefined) { send(socket, { t: 'full' }); return socket.close(4004); }
    } else if (session.controllers.get(player)?.socket.open) {
      session.controllers.get(player).socket.close(4000);   // the same phone, come back on a new connection
    }
    const controller = { socket, player, tokens: limits.perSecond, refilled: Date.now(), over: 0 };
    session.controllers.set(player, controller);
    socket.heard = Date.now();
    send(socket, { t: 'welcome', role: 'controller', player, host: !!session.host?.open, credential: issue(secret, { kind: 'controller', session: session.id, player }) });
    if (session.host?.open) send(session.host, { t: 'joined', player });
    socket.on('message', (text) => {
      socket.heard = Date.now();
      if (!allowed(controller)) return;
      const message = parse(text);
      if (!message || !session.host?.open) return;
      const at = Date.now();
      const name = typeof message.name === 'string' && /^[A-Za-z0-9_-]{1,32}$/.test(message.name) ? message.name : null;
      const seq = Number.isSafeInteger(message.seq) ? message.seq : 0;
      if (message.t === 'button' && name) {
        send(session.host, { t: 'button', player, name, down: message.down === true, seq, at });
      } else if (message.t === 'axis' && name) {
        // Movement is only worth its latest value: when the host is behind, it's dropped rather than queued.
        if (session.host.backlog > limits.hostBacklog) return;
        send(session.host, { t: 'axis', player, name, x: clamp(message.x), y: clamp(message.y), seq, at });
      } else if (message.t === 'message' && message.data !== undefined) {
        send(session.host, { t: 'message', player, data: message.data, at });
      }
    });
    socket.on('close', () => {
      if (session.controllers.get(player)?.socket !== socket) return;
      session.controllers.delete(player);
      if (session.host?.open) send(session.host, { t: 'left', player });
    });
  }

  // A phone may send about as often as its screen draws; past that its messages are dropped, and a phone that goes
  // on past it for ten seconds is closed.
  function allowed(controller) {
    const now = Date.now();
    controller.tokens = Math.min(limits.perSecond, controller.tokens + ((now - controller.refilled) / 1000) * limits.perSecond);
    controller.refilled = now;
    if (controller.tokens >= 1) { controller.tokens -= 1; controller.over = 0; return true; }
    controller.over ||= now;
    if (now - controller.over > 10_000) controller.socket.close(4008);
    return false;
  }

  // Every few seconds: a beat on every socket (with the relay's time, which the host uses to tell how old movement
  // is), fresh credentials for the phones, and sockets and sessions that have gone quiet let go.
  const ticks = setInterval(() => {
    const now = Date.now();
    for (const [id, session] of sessions) {
      const sockets = [session.host, ...[...session.controllers.values()].map((c) => c.socket)].filter((s) => s?.open);
      for (const socket of sockets) {
        if (now - socket.heard > limits.silence) socket.close(4002);
        else send(socket, { t: 'beat', now });
      }
      if (now - (session.renewed ?? session.started) >= 60_000) {
        session.renewed = now;
        for (const controller of session.controllers.values()) {
          send(controller.socket, { t: 'credential', credential: issue(secret, { kind: 'controller', session: id, player: controller.player }) });
        }
      }
      const hostGone = session.hostGoneAt && now - session.hostGoneAt > limits.hostAway;
      if (hostGone || now - session.started > lifetimes.host * 1000) {
        for (const socket of sockets) socket.close(4005);
        sessions.delete(id);
      }
    }
  }, 5000);

  server.listen(port, bind);
  return { server, sessions, close: () => { clearInterval(ticks); server.close(); for (const s of sessions.values()) { s.host?.close(); for (const c of s.controllers.values()) c.socket.close(); } } };
}

function send(socket, message) { if (socket?.open) socket.send(JSON.stringify(message)); }
function parse(text) { try { const value = JSON.parse(text); return value && typeof value === 'object' ? value : null; } catch { return null; } }
function clamp(value) { const n = Number(value); return Number.isFinite(n) ? Math.max(-1, Math.min(1, n)) : 0; }
function bearer(request) { return (request.headers.authorization ?? '').replace(/^Bearer /, ''); }
function json(response, status, value) { response.writeHead(status, { 'Content-Type': 'application/json', 'Cache-Control': 'no-store' }).end(JSON.stringify(value)); }
function text(response, status, value) { response.writeHead(status, { 'Content-Type': 'text/plain; charset=utf-8', 'Cache-Control': 'no-store' }).end(value); }

function read(request, max) {
  return new Promise((resolve, reject) => {
    const chunks = [];
    let size = 0;
    request.on('data', (chunk) => {
      size += chunk.length;
      if (size > max) { reject(new Error('Too big.')); request.destroy(); } else chunks.push(chunk);
    });
    request.on('end', () => resolve(Buffer.concat(chunks).toString('utf8')));
    request.on('error', reject);
  });
}

function type(path) {
  const ext = path.split('.').pop().toLowerCase();
  return {
    html: 'text/html; charset=utf-8', js: 'text/javascript; charset=utf-8', css: 'text/css; charset=utf-8',
    json: 'application/json', svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
    gif: 'image/gif', webp: 'image/webp', woff2: 'font/woff2', mp3: 'audio/mpeg', wav: 'audio/wav',
  }[ext] ?? 'application/octet-stream';
}

if (import.meta.url === `file://${process.argv[1]}`) {
  const env = process.env;
  const port = Number(env.PORT ?? 8787);
  startRelay({
    port,
    bind: env.BIND ?? '127.0.0.1',
    secret: env.RELAY_SECRET ? Buffer.from(env.RELAY_SECRET, 'hex') : newSecret(),
    api: env.RELAY_API ?? `http://localhost:${port}`,
    pages: env.RELAY_PAGES ?? `http://{session}.localhost:${port}`,
  });
  console.log(`Controller relay listening on ${env.BIND ?? '127.0.0.1'}:${port}`);
}
