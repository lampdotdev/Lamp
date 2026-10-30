/* One LG game's phones as controllers, run by the game's own service on the TV (service.js), never by Lamp: the game's
 * phone page, served from the copy Lamp packaged beside this file (phone/), and the relay its phones and its page meet
 * at, each on a port the system gives it free. The same protocol, credentials and limits as Lamp's relay on the Mac
 * (LampRelayKit's Relay, ControllerToken, ControllerWire and PhonePageServer), so lamp.js and lamp-controller.js speak
 * to either alike. Only the game's half: a wish's rooms stay on the Mac.
 *
 * The credentials are signed with a key made for each session from the system's random source and kept only in this
 * process's memory: never in the package, the page's files, the link a phone opens or anything written. A session that
 * stops and starts again has a new key, so nothing handed out before gets in.
 *
 * Plain ES5 for Node 8.3 and later (webOS TV 5.0's Node is 8.12), with ws for WebSocket framing; nothing native.
 */
'use strict';
var crypto = require('crypto');
var fs = require('fs');
var http = require('http');
var os = require('os');
var path = require('path');
var WebSocket = require('ws');

// ControllerWire: the same numbers as lamp.js, lamp-controller.js and Lamp's relay.
var WIRE = {
  message: 16 * 1024, chunk: 64 * 1024, header: 8, window: 512 * 1024, file: 64 * 1024 * 1024, transfers: 2,
  players: 8, perSecond: 120, backlog: 32, silence: 15000, beat: 5000
};
var LIFETIME = { host: 12 * 3600, join: 15 * 60, controller: 2 * 60 };   // seconds
var MESSAGE_LIMIT = WIRE.chunk + 1024;
var HOST_BEHIND = 128;
var TEXT_LIMIT = { messages: 256, bytes: 2 * 1024 * 1024 };
var PIECE_LIMIT = WIRE.players * WIRE.transfers * (WIRE.window + WIRE.chunk + WIRE.header);
var GREETING_LIMIT = { all: 64, each: 8 };
var PAGE_LIMIT = { all: 64, each: 16, deadline: 10000 };
var FILE_LIMIT = 64 << 20;
var RENEW = 15;   // seconds between looks at the TV's address

// MARK: Credentials (ControllerToken)

function base64url(buffer) {
  return buffer.toString('base64').replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}
function unbase64url(text) {
  if (!/^[A-Za-z0-9_-]*$/.test(text)) return null;
  return Buffer.from(text.replace(/-/g, '+').replace(/_/g, '/'), 'base64');
}
function sign(body, key) { return crypto.createHmac('sha256', key).update(body).digest(); }

function issue(kind, app, generation, key, player) {
  var payload = { a: app, e: Math.floor(Date.now() / 1000) + LIFETIME[kind], g: generation, k: kind, n: base64url(crypto.randomBytes(9)) };
  if (player) payload.p = player;
  var body = base64url(Buffer.from(JSON.stringify(payload), 'utf8'));
  return body + '.' + base64url(sign(body, key));
}

// What a credential says when it was made with this key, for this app in this generation, of one of these kinds, and
// hasn't run out; null otherwise, whatever is wrong with it.
function check(token, kinds, app, generation, key) {
  if (typeof token !== 'string' || Buffer.byteLength(token) > 1024) return null;
  var parts = token.split('.');
  if (parts.length !== 2) return null;
  var signature = unbase64url(parts[1]), expected = sign(parts[0], key);
  if (!signature || signature.length !== expected.length || !crypto.timingSafeEqual(signature, expected)) return null;
  var body = unbase64url(parts[0]), payload;
  try { payload = JSON.parse(body.toString('utf8')); } catch (e) { return null; }
  if (!payload || typeof payload !== 'object' || kinds.indexOf(payload.k) < 0 || payload.a !== app || payload.g !== generation) return null;
  if (typeof payload.e !== 'number' || payload.e <= Date.now() / 1000) return null;
  return { kind: payload.k, player: typeof payload.p === 'number' ? payload.p : null };
}

// MARK: The TV's addresses

// The TV's IPv4 addresses on its networks, the ones a phone on the same Wi-Fi opens: wired first, as the TV prefers it.
function localAddresses() {
  var found = [], all = os.networkInterfaces();
  Object.keys(all).sort(function (a, b) { return (/^eth/.test(b) ? 1 : 0) - (/^eth/.test(a) ? 1 : 0) || (a < b ? -1 : 1); }).forEach(function (name) {
    all[name].forEach(function (entry) {
      if ((entry.family === 'IPv4' || entry.family === 4) && !entry.internal && !/^169\.254\./.test(entry.address)) found.push(entry.address);
    });
  });
  return found;
}

// MARK: The phone page (PhonePageServer)

var TYPES = {
  html: 'text/html; charset=utf-8', htm: 'text/html; charset=utf-8', js: 'text/javascript; charset=utf-8',
  mjs: 'text/javascript; charset=utf-8', css: 'text/css; charset=utf-8', json: 'application/json',
  webmanifest: 'application/json', svg: 'image/svg+xml', png: 'image/png', jpg: 'image/jpeg', jpeg: 'image/jpeg',
  gif: 'image/gif', webp: 'image/webp', ico: 'image/x-icon', woff2: 'font/woff2', woff: 'font/woff', mp3: 'audio/mpeg',
  wav: 'audio/wav', mp4: 'video/mp4', txt: 'text/plain; charset=utf-8'
};

// Whether a Host header names one of `hosts`, with at most a numeric port after it: a page elsewhere that made its own
// name lead here (DNS rebinding) reads nothing.
function names(header, hosts) {
  var host = String(header || '').trim().toLowerCase();
  if (!host) return false;
  var m = /^\[([^\]]+)\](?::(\d+))?$/.exec(host) || /^([^:\[\]]+)(?::(\d+))?$/.exec(host);
  if (!m) return false;
  return hosts.indexOf(m[1]) >= 0;
}

// Whether a path inside a page is one served: steps of a name each, none hidden, empty or stepping up.
function isServed(relative) {
  if (!relative || Buffer.byteLength(relative) > 1024 || relative.indexOf('\0') >= 0 || relative.indexOf('\\') >= 0) return false;
  return relative.split('/').every(function (step) { return step.length > 0 && step.charAt(0) !== '.' && Buffer.byteLength(step) <= 255; });
}

// The answer to a GET of `full` asked for as `host`: { status, type, body }, or a file's { file, size } to stream, so a
// large picture or sound never sits whole in the TV's memory.
function answer(root, full, host, hosts, relay) {
  var text = function (status, said) { return { status: status, type: TYPES.txt, body: Buffer.from(said) }; };
  if (!names(host, hosts)) return text(403, 'Not for this host.');
  var missing = text(404, 'Nothing here. Open the game on the TV first.');
  var p = full.split('?')[0];
  if (p.charAt(0) !== '/') return missing;
  var steps;
  try { steps = p.slice(1).split('/').map(decodeURIComponent); } catch (e) { return missing; }
  if (steps[steps.length - 1] === '') steps[steps.length - 1] = 'index.html';
  if (steps.length === 1 && steps[0] === 'lamp-relay.json') {
    if (!relay) return text(503, 'The link for controllers isn\'t open.');
    return { status: 200, type: TYPES.json, body: Buffer.from(JSON.stringify(relay)) };
  }
  if (steps.some(function (s) { return s.indexOf('/') >= 0; }) || !isServed(steps.join('/'))) return missing;
  // Each step from the page's folder down, the folder itself included, must be no link.
  var at = root;
  try {
    if (fs.lstatSync(at).isSymbolicLink()) return missing;
    for (var i = 0; i < steps.length; i++) {
      at = path.join(at, steps[i]);
      if (fs.lstatSync(at).isSymbolicLink()) return missing;
    }
    var stat = fs.statSync(at);
    if (!stat.isFile() || stat.size > FILE_LIMIT) return missing;
    var ext = path.extname(at).slice(1).toLowerCase();
    return { status: 200, type: TYPES[ext] || 'application/octet-stream', file: at, size: stat.size };
  } catch (e) {
    return missing;
  }
}

// PhonePagePolicy's rules for the page, in the same words: nothing but the page's own files, the game's relay on the TV
// by the name the phone used, at the port it listens on now, and the sites the app may reach, from lamp-reach.json,
// which Lamp writes beside the page (none when it's missing).
var REACH_FILE = 'lamp-reach.json';

function plainHost(host) {
  return host.length > 0 && host.length <= 253 && host.charAt(0) !== '.' && host.charAt(host.length - 1) !== '.'
    && host.indexOf('..') < 0 && /^[a-z0-9.-]+$/.test(host);
}

function policySource(text) {
  var site = String(text).trim().toLowerCase();
  var split = site.indexOf('://');
  if (split < 0) return plainHost(site) ? site : null;
  var scheme = site.slice(0, split);
  if (['http', 'https', 'ws', 'wss'].indexOf(scheme) < 0) return null;
  var rest = site.slice(split + 3);
  if (rest.charAt(rest.length - 1) === '/') rest = rest.slice(0, -1);
  var host = rest, colon = rest.indexOf(':');
  if (colon >= 0) {
    if (!/^[0-9]{1,5}$/.test(rest.slice(colon + 1))) return null;
    host = rest.slice(0, colon);
  }
  return plainHost(host) ? scheme + '://' + rest : null;
}

function readReachJSON(text) {
  try {
    var object = JSON.parse(text);
    if (object && object.secureSites === true) return { secureSites: true };
    return { only: Array.isArray(object && object.only) ? object.only.filter(function (s) { return typeof s === 'string'; }) : [] };
  } catch (e) {
    return { only: [] };
  }
}

function readReach(root) {
  try { return readReachJSON(fs.readFileSync(path.join(root, REACH_FILE), 'utf8')); } catch (e) { return { only: [] }; }
}

function policy(host, relayPort, reach) {
  var sites = reach.secureSites ? ['https:'] : reach.only.map(policySource).filter(Boolean);
  var connect = ["'self'"];
  var name = String(host || '').trim().toLowerCase();
  if (name && name.charAt(0) !== '[') {
    if (name.indexOf(':') >= 0) name = name.slice(0, name.indexOf(':'));
    if (plainHost(name) && relayPort) connect.push('ws://' + name + ':' + relayPort);
  }
  if (reach.secureSites) connect.push('wss:');
  var list = function (base) { return base.concat(sites).join(' '); };
  return [
    "default-src 'none'",
    'script-src ' + list(["'self'", "'unsafe-inline'"]),
    'style-src ' + list(["'self'", "'unsafe-inline'"]),
    'img-src ' + list(["'self'", 'data:', 'blob:']),
    'media-src ' + list(["'self'", 'data:', 'blob:']),
    'font-src ' + list(["'self'", 'data:']),
    'connect-src ' + list(connect),
    "worker-src 'self' blob:",
    "manifest-src 'self'",
    "base-uri 'none'",
    "form-action 'none'"
  ].join('; ');
}

// MARK: One socket (RelayPeer)

function Peer(socket, from) {
  this.socket = socket;
  this.from = from;
  this.open = true;
  this.heard = Date.now();
  this.pendingText = 0;
  this.pendingBytes = 0;
  this.pieces = [];
  this.pieceBytes = 0;
  this.sendingPiece = false;
  this.onText = function () {};
  this.onBinary = function () {};
  this.onClose = function () {};
  var self = this;
  socket.on('message', function (data) {
    if (!self.open) return;
    self.heard = Date.now();
    if (typeof data === 'string') {
      if (Buffer.byteLength(data) > WIRE.message) return self.close(1009);
      self.onText(data);
    } else {
      self.onBinary(Buffer.isBuffer(data) ? data : Buffer.from(data));
    }
  });
  socket.on('close', function () { self.closed(); });
  socket.on('error', function () { socket.terminate(); self.closed(); });
}
Peer.prototype.send = function (text) {
  if (!this.open) return;
  var size = Buffer.byteLength(text);
  if (this.pendingText >= TEXT_LIMIT.messages || this.pendingBytes + size > TEXT_LIMIT.bytes) return this.close(4002);
  var self = this;
  this.pendingText += 1;
  this.pendingBytes += size;
  this.socket.send(text, function () { self.pendingText -= 1; self.pendingBytes -= size; });
};
// Queues a piece of a file; false when the peer already has more waiting than it could ever be owed.
Peer.prototype.sendPiece = function (piece) {
  if (!this.open || this.pieceBytes + piece.length > PIECE_LIMIT) return false;
  this.pieces.push(piece);
  this.pieceBytes += piece.length;
  this.pump();
  return true;
};
Peer.prototype.pump = function () {
  if (!this.open || this.sendingPiece || !this.pieces.length) return;
  var piece = this.pieces.shift(), self = this;
  this.pieceBytes -= piece.length;
  this.sendingPiece = true;
  this.socket.send(piece, { binary: true }, function () { self.sendingPiece = false; self.pump(); });
};
// Says why, when the socket can still hear it, and lets it go either way.
Peer.prototype.close = function (code) {
  if (!this.open) return;
  var socket = this.socket;
  try { socket.close(code || 1000); } catch (e) { socket.terminate(); }
  setTimeout(function () { socket.terminate(); }, 2000);
  this.closed();
};
Peer.prototype.closed = function () {
  if (!this.open) return;
  this.open = false;
  this.pieces = [];
  this.pieceBytes = 0;
  this.onClose();
};

// MARK: The relay's game (Relay's game half)

function Transfer(size) { this.size = size; this.passed = 0; this.acknowledged = 0; this.unacknowledged = 0; }
Transfer.prototype.acknowledge = function (got) {
  if (this.size === 0 && got === 0 && this.acknowledged === 0 && this.unacknowledged === 0) { this.unacknowledged = -1; return true; }
  if (!(got > this.acknowledged && got <= this.passed && this.unacknowledged > 0)) return false;
  this.acknowledged = got;
  this.unacknowledged -= 1;
  return true;
};

function Rate() { this.tokens = WIRE.perSecond; this.refilled = Date.now(); this.over = null; this.lastDropped = 0; }
Rate.prototype.allowed = function (peer) {
  var now = Date.now();
  this.tokens = Math.min(WIRE.perSecond, this.tokens + (now - this.refilled) / 1000 * WIRE.perSecond);
  this.refilled = now;
  if (now - this.lastDropped > 2000) this.over = null;
  if (this.tokens >= 1) { this.tokens -= 1; return true; }
  this.lastDropped = now;
  if (this.over === null) this.over = now;
  if (now - this.over > 10000 && peer) peer.close(4008);
  return false;
};

function isID(value) { return typeof value === 'number' && value % 1 === 0 && value > 0 && value < 2147483648 ? value : null; }
function isInt(value) { return typeof value === 'number' && value % 1 === 0; }
function short(value, limit) { return typeof value === 'string' ? Array.from(value).slice(0, limit).join('') : ''; }
function clamp(value) { return typeof value === 'number' && isFinite(value) ? Math.max(-1, Math.min(1, value)) : 0; }
function parse(text) {
  if (Buffer.byteLength(text) > WIRE.message) return null;
  try { var v = JSON.parse(text); return v && typeof v === 'object' && !Array.isArray(v) ? v : null; } catch (e) { return null; }
}
function json(value) { return JSON.stringify(value); }
function readdressed(data, player) { var copy = Buffer.from(data); copy[1] = player; return copy; }
function chunkHeader(data) {
  if (data.length < WIRE.header || data[0] !== 1) return null;
  return { player: data[1], id: data.readUInt32BE(4) };
}
// Where a connection comes from, for its limits: an IPv6 address by its /64, since a device can take many there.
function addressOf(socket) {
  var a = String(socket.remoteAddress || '?').replace(/^::ffff:/i, '').split('%')[0].toLowerCase();
  if (a.indexOf(':') < 0) return a;
  var halves = a.split('::'), head = halves[0] ? halves[0].split(':') : [], tail = halves.length > 1 && halves[1] ? halves[1].split(':') : [];
  var groups = halves.length > 1 ? head.concat(new Array(Math.max(0, 8 - head.length - tail.length) + 1).join('0').split(''), tail) : head;
  return groups.slice(0, 4).map(function (g) { return parseInt(g, 16) || 0; }).join(':');
}

function Game(app, key) {
  this.app = app;
  this.key = key;
  this.generation = 0;
  this.page = null;
  this.pagePort = null;
  this.hosts = [];
  this.host = null;
  this.players = {};
  this.renewed = Date.now();
  this.greeting = [];
}

// A browser always says which page opened a socket: of web pages, only the game's own phone page, at the port it's
// served at by one of the TV's names, is let in. The game's own page is a file of its package ("file://" or "null"),
// and like any client that isn't a browser could say whatever origin it liked, so its credential is what lets it in.
Game.prototype.admits = function (origin) {
  if (origin === undefined || origin === null || origin === '') return true;
  var lower = String(origin).toLowerCase();
  if (lower === 'null' || lower === 'file://') return true;
  var m = /^http:\/\/(\[[^\]]+\]|[^:\/]+):(\d+)$/.exec(lower);
  if (!m) return false;
  return +m[2] === this.pagePort && this.hosts.indexOf(m[1].replace(/^\[|\]$/g, '')) >= 0;
};

Game.prototype.accept = function (socket, from, raw) {
  var self = this, peer = new Peer(socket, from), greeted = false;
  peer.raw = raw;
  this.greeting.push(peer);
  var forget = function () { var i = self.greeting.indexOf(peer); if (i >= 0) self.greeting.splice(i, 1); };
  peer.onClose = forget;
  peer.onBinary = function () { peer.close(4003); };
  peer.onText = function (text) {
    if (greeted) return;
    greeted = true;
    forget();
    self.hello(peer, text);
  };
  setTimeout(function () { if (!greeted) { forget(); peer.close(4001); } }, 5000);
};

Game.prototype.hello = function (peer, text) {
  var hello = parse(text);
  if (!hello || hello.t !== 'hello' || hello.app !== this.app) return peer.close(4003);
  var claim = check(hello.credential, ['host', 'join', 'controller'], this.app, this.generation, this.key);
  if (!claim) return peer.close(4003);
  if (peer.raw) peer.raw.proven = true;
  if (claim.kind === 'host') return this.joinAsHost(peer);
  this.joinAsPlayer(peer, claim.kind === 'controller' ? claim.player : null);
};

Game.prototype.joinAsHost = function (peer) {
  var self = this, old = this.host;
  if (old) {
    old.onClose = function () {};
    old.close(4000);
    this.dropTransfers();
    this.eachPlayer(function (p) { p.peer.send('{"t":"state","host":false}'); });
  }
  this.host = peer;
  peer.onText = function (text) { var m = parse(text); if (m) self.fromHost(m); };
  peer.onBinary = function (data) { self.pieceFromHost(data); };
  peer.onClose = function () {
    if (self.host !== peer) return;
    self.host = null;
    self.dropTransfers();
    self.eachPlayer(function (p) { p.peer.send('{"t":"state","host":false}'); });
  };
  var players = Object.keys(this.players).filter(function (n) { return self.players[n].peer; }).map(Number).sort();
  peer.send(json({ t: 'welcome', role: 'host', players: players, now: Date.now() }));
  this.eachPlayer(function (p) { p.peer.send('{"t":"state","host":true}'); });
};

Game.prototype.eachPlayer = function (fn) {
  for (var n in this.players) if (this.players[n].peer) fn(this.players[n], +n);
};

Game.prototype.joinAsPlayer = function (peer, resuming) {
  var self = this, now = Date.now(), number = resuming;
  if (resuming && this.players[resuming] && this.players[resuming].peer) {
    var old = this.players[resuming].peer;
    old.onClose = function () {};
    old.close(4000);   // the same phone, back on a new connection
    if (this.host) this.host.send(json({ t: 'left', player: resuming }));
  }
  if (!number) {
    for (var n = 1; n <= WIRE.players; n++) {
      var p = this.players[n];
      if (!p || (!p.peer && p.heldUntil < now)) { number = n; break; }
    }
  }
  if (!number) { peer.send('{"t":"full"}'); return peer.close(4004); }
  var player = { peer: peer, heldUntil: 0, rate: new Rate(), toHost: {}, toPhone: {} };
  this.players[number] = player;
  peer.send(json({ t: 'welcome', role: 'controller', place: number, host: !!this.host,
                   credential: issue('controller', this.app, this.generation, this.key, number) }));
  if (this.host) this.host.send(json({ t: 'joined', player: number }));
  peer.onText = function (text) { self.fromPlayer(number, player, text); };
  peer.onBinary = function (data) { self.pieceFromPlayer(number, player, data); };
  peer.onClose = function () {
    if (self.players[number] !== player || player.peer !== peer) return;
    player.peer = null;
    player.heldUntil = Date.now() + LIFETIME.controller * 1000;
    player.toHost = {};
    player.toPhone = {};
    if (self.host) self.host.send(json({ t: 'left', player: number }));
  };
};

Game.prototype.refuse = function (player, id, reason) {
  if (player.peer) player.peer.send(json({ t: 'file-refuse', id: id, reason: reason }));
};

Game.prototype.fromPlayer = function (number, player, text) {
  var m = parse(text);
  if (!m) return;
  var kind = typeof m.t === 'string' ? m.t : '';
  var keepsFileMoving = kind === 'file-ack' || kind === 'file-cancel' || kind === 'file-refuse';
  // A file's acknowledgements come as fast as its pieces, and are what keeps it moving: they aren't counted.
  if (!keepsFileMoving && !player.rate.allowed(player.peer)) return;
  var host = this.host, id;
  if (!host) {
    if (kind === 'file' && (id = isID(m.id))) this.refuse(player, id, 'The TV app isn\'t there.');
    return;
  }
  // A TV that's behind isn't let go for what phones send it: what they send meanwhile is dropped instead, all but what
  // keeps a file moving, and buttons, whose letting go the TV must never miss.
  if (host.pendingText > HOST_BEHIND && !keepsFileMoving && kind !== 'button') {
    if (kind === 'file' && (id = isID(m.id))) this.refuse(player, id, 'The TV app is busy; try again.');
    return;
  }
  var at = Date.now(), seq = isInt(m.seq) ? m.seq : 0;
  var name = typeof m.name === 'string' && /^[A-Za-z0-9_-]{1,32}$/.test(m.name) ? m.name : null;
  var transfer, got;
  switch (kind) {
    case 'button':
      if (name) host.send(json({ t: 'button', player: number, name: name, down: m.down === true, seq: seq, at: at }));
      break;
    case 'axis':
      // Movement is only worth its latest value: when the TV is behind, it's dropped rather than queued.
      if (name && host.pendingText <= WIRE.backlog) host.send(json({ t: 'axis', player: number, name: name, x: clamp(m.x), y: clamp(m.y), seq: seq, at: at }));
      break;
    case 'message':
      if (m.data !== undefined) host.send(json({ t: 'message', player: number, data: m.data, at: at }));
      break;
    case 'too-big':
      if (isInt(m.bytes)) host.send(json({ t: 'too-big', player: number, bytes: m.bytes }));
      break;
    case 'file':
      if (!(id = isID(m.id))) return;
      if (!isInt(m.size) || m.size < 0 || m.size > WIRE.file) return this.refuse(player, id, 'The file is too big to send.');
      if (player.toHost[id] || Object.keys(player.toHost).length >= WIRE.transfers) return this.refuse(player, id, 'Another file is still on its way.');
      player.toHost[id] = new Transfer(m.size);
      host.send(json({ t: 'file', player: number, id: id, name: short(m.name, 200), type: short(m.type, 100), size: m.size, at: at }));
      break;
    case 'file-cancel':
      if (!(id = isID(m.id)) || !player.toHost[id]) return;
      delete player.toHost[id];
      host.send(json({ t: 'file-cancel', player: number, id: id }));
      break;
    case 'file-ack':
      if (!(id = isID(m.id)) || !(transfer = player.toPhone[id]) || !isInt(got = m.got) || !transfer.acknowledge(got)) return;
      if (got === transfer.size) delete player.toPhone[id];
      host.send(json({ t: 'file-ack', player: number, id: id, got: got }));
      break;
    case 'file-refuse':
      if (!(id = isID(m.id)) || !player.toPhone[id]) return;
      delete player.toPhone[id];
      host.send(json({ t: 'file-refuse', player: number, id: id, reason: short(m.reason, 200) }));
      break;
  }
};

Game.prototype.pieceFromPlayer = function (number, player, data) {
  var head = chunkHeader(data), transfer = head && player.toHost[head.id];
  if (!transfer) return;
  var bytes = data.length - WIRE.header, host = this.host;
  // A piece past the file's size, or past the window the host has acknowledged, is a sender that doesn't keep to what
  // it said: the file goes no further.
  if (!host || bytes <= 0 || transfer.passed + bytes > transfer.size
      || transfer.passed + bytes - transfer.acknowledged > WIRE.window + WIRE.chunk || !host.sendPiece(readdressed(data, number))) {
    delete player.toHost[head.id];
    if (this.host) this.host.send(json({ t: 'file-cancel', player: number, id: head.id }));
    return this.refuse(player, head.id, 'The file didn\'t keep to its size.');
  }
  transfer.passed += bytes;
  transfer.unacknowledged += 1;
};

Game.prototype.fromHost = function (m) {
  var number = isInt(m.player) ? m.player : 0, player = this.players[number], id, transfer, got;
  switch (m.t) {
    case 'link':
      this.sendLink();
      break;
    case 'send':
      if (m.data === undefined) return;
      var text = json({ t: 'message', data: m.data });
      this.eachPlayer(function (p, place) { if (number === 0 || number === place) p.peer.send(text); });
      break;
    case 'player':
      // The number the TV page knows this phone by, which the phone shows.
      if (player && player.peer && isInt(m.number) && m.number > 0 && m.number < 1000) player.peer.send(json({ t: 'player', number: m.number }));
      break;
    case 'file':
      if (!(id = isID(m.id))) return;
      if (!player || !player.peer || !isInt(m.size) || m.size < 0 || m.size > WIRE.file || player.toPhone[id]
          || Object.keys(player.toPhone).length >= WIRE.transfers) {
        return this.host.send(json({ t: 'file-refuse', player: number, id: id, reason: 'The phone can\'t take it now.' }));
      }
      player.toPhone[id] = new Transfer(m.size);
      player.peer.send(json({ t: 'file', id: id, name: short(m.name, 200), type: short(m.type, 100), size: m.size }));
      break;
    case 'file-cancel':
      if (!(id = isID(m.id)) || !player || !player.toPhone[id]) return;
      delete player.toPhone[id];
      if (player.peer) player.peer.send(json({ t: 'file-cancel', id: id }));
      break;
    case 'file-ack':
      if (!(id = isID(m.id)) || !player || !(transfer = player.toHost[id]) || !isInt(got = m.got) || !transfer.acknowledge(got)) return;
      if (got === transfer.size) delete player.toHost[id];
      if (player.peer) player.peer.send(json({ t: 'file-ack', id: id, got: got }));
      break;
    case 'file-refuse':
      if (!(id = isID(m.id)) || !player || !player.toHost[id]) return;
      delete player.toHost[id];
      if (player.peer) player.peer.send(json({ t: 'file-refuse', id: id, reason: short(m.reason, 200) }));
      break;
  }
};

Game.prototype.pieceFromHost = function (data) {
  var head = chunkHeader(data), player = head && this.players[head.player], transfer = player && player.toPhone[head.id];
  if (!transfer) return;
  var bytes = data.length - WIRE.header;
  if (!player.peer || bytes <= 0 || transfer.passed + bytes > transfer.size
      || transfer.passed + bytes - transfer.acknowledged > WIRE.window + WIRE.chunk || !player.peer.sendPiece(readdressed(data, 0))) {
    delete player.toPhone[head.id];
    if (player.peer) player.peer.send(json({ t: 'file-cancel', id: head.id }));
    if (this.host) this.host.send(json({ t: 'file-refuse', player: head.player, id: head.id, reason: 'The file didn\'t keep to its size.' }));
    return;
  }
  transfer.passed += bytes;
  transfer.unacknowledged += 1;
};

Game.prototype.dropTransfers = function () {
  for (var n in this.players) { this.players[n].toHost = {}; this.players[n].toPhone = {}; }
};

// A link for phones: the page's address with a fresh join credential after the #.
Game.prototype.sendLink = function () {
  if (!this.page || !this.host) return;
  this.host.send(json({ t: 'link', url: this.page + '#' + issue('join', this.app, this.generation, this.key) }));
};

// Every few seconds: a beat on every socket (with the relay's time, which the host uses to tell how old movement is),
// fresh credentials for the phones each minute, and sockets that have gone quiet let go.
Game.prototype.tick = function () {
  var now = Date.now(), beat = json({ t: 'beat', now: now }), renew = now - this.renewed >= 60000;
  if (renew) this.renewed = now;
  for (var n in this.players) {
    var player = this.players[n];
    if (!player.peer) { if (player.heldUntil < now) delete this.players[n]; continue; }
    if (now - player.peer.heard > WIRE.silence) { player.peer.close(4002); continue; }
    player.peer.send(beat);
    if (renew) player.peer.send(json({ t: 'credential', credential: issue('controller', this.app, this.generation, this.key, +n) }));
  }
  if (this.host) {
    if (now - this.host.heard > WIRE.silence) this.host.close(4002); else this.host.send(beat);
  }
};

Game.prototype.end = function () {
  this.eachPlayer(function (p) { p.peer.close(4005); });
  this.players = {};
  if (this.host) this.host.close(4005);
  this.host = null;
  this.greeting.slice().forEach(function (peer) { peer.close(1001); });
  this.greeting = [];
};

// MARK: A session

/* One game's session: its page and its relay, opened as the game asks for its controllers and closed as it lets them
 * go. `options`: root (the packaged phone page), app (the name its credentials are for), and for tests `addresses`
 * (the TV's addresses now) and `bind` (where to listen; every address otherwise). Starts and stops happen one at a time,
 * in the order they were asked.
 */
function Session(options) {
  this.root = options.root;
  this.app = options.app;
  this.addresses = options.addresses || localAddresses;
  this.bind = options.bind;
  this.game = null;
  this.relayServer = null;
  this.pageServer = null;
  this.relayPort = null;
  this.pagePort = null;
  this.timers = [];
  this.queue = [];
  this.busy = false;
  this.onChange = function () {};
}

Session.prototype.serially = function (work) {
  var self = this;
  this.queue.push(work);
  (function next() {
    if (self.busy || !self.queue.length) return;
    self.busy = true;
    self.queue.shift()(function () { self.busy = false; next(); });
  })();
};

// The game's session, opened if it isn't: callback(error, answer), where answer is what `/app/controller` answers on
// the Mac (`links`, `renew`) and the address phones open (`page`, null while the TV has no network).
Session.prototype.start = function (callback) {
  var self = this;
  this.serially(function (done) {
    self.open(function (error) {
      var answer = error ? null : self.answer();
      done();
      callback(error, answer);
    });
  });
};

Session.prototype.stop = function (callback) {
  var self = this;
  this.serially(function (done) { self.close(); done(); if (callback) callback(); });
};

Session.prototype.isRunning = function () { return !!this.game; };

Session.prototype.answer = function () {
  if (!this.game) return null;
  return {
    links: [{ kind: 'relay', socket: 'ws://127.0.0.1:' + this.relayPort + '/', app: this.app,
              credential: issue('host', this.app, this.game.generation, this.game.key) }],
    renew: RENEW,
    page: this.game.page
  };
};

Session.prototype.open = function (done) {
  var self = this;
  if (this.game) return done(null);
  try { if (!fs.statSync(path.join(this.root, 'index.html')).isFile()) throw new Error(); } catch (e) {
    return done(new Error('The game has no phone page yet: put one in Phone/index.html.'));
  }
  var game = new Game(this.app, crypto.randomBytes(32)), raw = [];
  var relayServer = http.createServer(function (req, res) { res.writeHead(426, { 'Connection': 'close' }); res.end(); });
  // Every connection counts from the moment it's taken, upgraded or not: one that hasn't proven itself with a credential
  // within a few seconds is let go, and only so many wait at once, in all and from one address. All of them go when the
  // session stops.
  relayServer.on('connection', function (socket) {
    var from = addressOf(socket), waiting = raw.filter(function (s) { return !s.proven; });
    if (self.game !== game || waiting.length >= GREETING_LIMIT.all
        || waiting.filter(function (s) { return s.from === from; }).length >= GREETING_LIMIT.each) return socket.destroy();
    socket.from = from;
    raw.push(socket);
    socket.on('close', function () { var i = raw.indexOf(socket); if (i >= 0) raw.splice(i, 1); });
    setTimeout(function () { if (!socket.proven) socket.destroy(); }, 5000);
  });
  var sockets = new WebSocket.Server({
    server: relayServer, maxPayload: MESSAGE_LIMIT, perMessageDeflate: false, clientTracking: false,
    // Nothing from a session that has ended: its key is no longer the one anything should get in with.
    verifyClient: function (info) { return self.game === game && game.admits(info.req.headers.origin); }
  });
  // The server's own errors are the session's to handle (below); ws repeats them here, where unheard they'd be thrown.
  sockets.on('error', function () {});
  sockets.on('connection', function (socket, req) { game.accept(socket, req.socket.from, req.socket); });
  var pageServer = this.pageServer = this.makePageServer();
  this.relayServer = relayServer;
  this.relaySockets = sockets;
  this.relayRaw = raw;
  this.game = game;
  var waiting = 2, failed = null;
  var listened = function (error) {
    failed = failed || error;
    if (--waiting) return;
    if (failed) { self.close(); return done(new Error('The link for phones couldn\'t open on this TV.')); }
    self.relayPort = relayServer.address().port;
    self.pagePort = pageServer.address().port;
    self.refresh();
    self.timers.push(setInterval(function () { game.tick(); }, WIRE.beat));
    // The TV's address moves with its network: the link phones open follows it.
    self.timers.push(setInterval(function () { if (self.refresh()) self.onChange(); }, RENEW * 1000));
    done(null);
  };
  [relayServer, pageServer].forEach(function (server) {
    var told = false;
    server.on('error', function (error) {
      if (!told) { told = true; return listened(error); }
      // It stopped listening (the network went away under it): the session starts afresh, with a new key, in its
      // turn among starts and stops.
      self.serially(function (done) {
        var ended = self.relayServer === relayServer;
        if (ended) self.close();
        done();
        if (ended) self.onChange();
      });
    });
    server.listen(0, self.bind, function () { if (!told) { told = true; listened(null); } });
  });
};

// Reads the TV's addresses again; true when the link phones open has moved.
Session.prototype.refresh = function () {
  var game = this.game;
  if (!game) return false;
  var addresses = this.addresses();
  game.hosts = ['127.0.0.1', 'localhost', '::1'].concat(addresses.map(function (a) { return a.toLowerCase(); }));
  game.pagePort = this.pagePort;
  // Never the loopback address: a phone can't open it. No network, no link, until there is one.
  var page = addresses.length ? 'http://' + addresses[0] + ':' + this.pagePort + '/' : null;
  var moved = page !== game.page;
  game.page = page;
  if (moved) game.sendLink();
  return moved;
};

Session.prototype.makePageServer = function () {
  var self = this, open = [];
  var server = http.createServer(function (req, res) {
    req.socket.answered = true;
    var game = self.game;
    if (req.method !== 'GET' && req.method !== 'HEAD') { res.writeHead(405, { 'Content-Type': TYPES.txt }); return res.end('Not allowed'); }
    var page = answer(self.root, req.url, req.headers.host, game ? game.hosts : [], game ? { port: self.relayPort, app: self.app } : null);
    res.writeHead(page.status, {
      'Content-Type': page.type, 'Content-Length': page.file ? page.size : page.body.length, 'Cache-Control': 'no-store',
      'X-Content-Type-Options': 'nosniff', 'Referrer-Policy': 'no-referrer', 'Connection': 'close',
      'Content-Security-Policy': policy(req.headers.host, game ? self.relayPort : null, readReach(self.root))
    });
    if (req.method === 'HEAD') return res.end();
    if (!page.file) return res.end(page.body);
    // The file lasts as long as its answer does: a phone that goes away partway (a reload, Wi-Fi lost) lets the file go
    // too, rather than leave it open for the life of the service.
    var stream = fs.createReadStream(page.file);
    stream.on('error', function () { res.destroy(); });
    res.on('close', function () { stream.destroy(); });
    res.on('error', function () { stream.destroy(); });
    stream.pipe(res);
  });
  // A page is a few small requests, so a host that holds many open, or one that never finishes its request, is let go
  // before it can use up what the game needs for phones.
  server.on('connection', function (socket) {
    var from = String(socket.remoteAddress || '?');
    if (open.length >= PAGE_LIMIT.all || open.filter(function (s) { return s.from === from; }).length >= PAGE_LIMIT.each) return socket.destroy();
    socket.from = from;
    open.push(socket);
    socket.on('close', function () { var i = open.indexOf(socket); if (i >= 0) open.splice(i, 1); });
    setTimeout(function () { if (!socket.answered) socket.destroy(); }, PAGE_LIMIT.deadline);
  });
  server.openSockets = open;
  return server;
};

// Closes the page and the relay: every phone and the page's own socket are let go, and the key is forgotten.
Session.prototype.close = function () {
  this.timers.forEach(function (t) { clearInterval(t); });
  this.timers = [];
  if (this.game) this.game.end();
  this.game = null;
  if (this.relaySockets) { try { this.relaySockets.close(); } catch (e) {} }
  if (this.relayServer) { try { this.relayServer.close(); } catch (e) {} }
  (this.relayRaw || []).slice().forEach(function (s) { s.destroy(); });
  this.relaySockets = null;
  this.relayRaw = null;
  if (this.pageServer) {
    try { this.pageServer.close(); } catch (e) {}
    this.pageServer.openSockets.slice().forEach(function (s) { s.destroy(); });
  }
  this.relayServer = null;
  this.pageServer = null;
  this.relayPort = null;
  this.pagePort = null;
};

module.exports = { Session: Session, issue: issue, check: check, localAddresses: localAddresses, addressOf: addressOf, policy: policy, readReachJSON: readReachJSON, WIRE: WIRE };
