#!/usr/bin/env node
// lamp dev: runs a web app or web game from its folder, in any browser, and puts each saved change into the open
// page while it's used. A prototype of Lamp without the Mac app: whatever edits the files (a person, a coding agent)
// just saves them, and the page takes the change the way it does inside Lamp.
//
//   node cli/lamp.mjs dev [folder] [--port 4400] [--open]
//
// A game made with Lamp's runtime (lamp-game.js beside the page) keeps the player's place: the runtime is handed the
// change exactly as Lamp's app around the page hands it over (`window.__lampLive`), and swaps the code in, runs it
// again in place, or opens the page again from where the player was. Any other page is opened again.
//
// What the page logs goes to .lamp/runtime/log.txt in the folder, where Lamp keeps it too, for whoever is making the
// change to read. No dependencies: Node 20 or later.

import { createServer } from "node:http";
import { createHash } from "node:crypto";
import { watch, existsSync, statSync, mkdirSync, appendFileSync, writeFileSync, readdirSync } from "node:fs";
import { readFile, stat } from "node:fs/promises";
import { join, resolve, extname, sep, relative } from "node:path";
import { spawn } from "node:child_process";

const TYPES = {
  ".html": "text/html; charset=utf-8", ".htm": "text/html; charset=utf-8", ".js": "text/javascript; charset=utf-8",
  ".mjs": "text/javascript; charset=utf-8", ".css": "text/css; charset=utf-8", ".json": "application/json; charset=utf-8",
  ".map": "application/json", ".svg": "image/svg+xml", ".png": "image/png", ".jpg": "image/jpeg", ".jpeg": "image/jpeg",
  ".webp": "image/webp", ".gif": "image/gif", ".ico": "image/x-icon", ".avif": "image/avif", ".wasm": "application/wasm",
  ".glb": "model/gltf-binary", ".gltf": "model/gltf+json", ".bin": "application/octet-stream", ".gz": "application/gzip",
  ".mp3": "audio/mpeg", ".ogg": "audio/ogg", ".wav": "audio/wav", ".m4a": "audio/mp4", ".mp4": "video/mp4",
  ".webm": "video/webm", ".woff": "font/woff", ".woff2": "font/woff2", ".ttf": "font/ttf", ".txt": "text/plain; charset=utf-8",
  ".ktx2": "image/ktx2", ".csv": "text/csv; charset=utf-8", ".webmanifest": "application/manifest+json",
};

// The two files Lamp writes beside a game's runtime in each copy of the page, which the folder's own copy doesn't
// hold (`GamePage.stage`): which device the copy is on, and which build it is.
const DEVICE_FILE = "lamp-device.js", BUILD_FILE = "lamp-build.js", RUNTIME_FILE = "lamp-game.js";
// A browser on any device, as a page published to the web is given (`GamePage.anyBrowser`).
const ANY_BROWSER = `// Written by lamp dev for a browser on any device (any-browser); don't edit.
export default {"keys":{"AltLeft":"Alt / Option","AltRight":"Alt / Option","Backspace":"Backspace / Delete","Enter":"Enter / Return","MetaLeft":"Win / ⌘","MetaRight":"Win / ⌘"}};
`;

// What the page is given before any of its own scripts run: the two message handlers Lamp's app around a page has
// (so the game runtime knows changes come while it's played, and can say how each one went), a line to this server
// for changes, and the page's log sent back.
const CLIENT = `(() => {
  const send = (path, body) => { try { fetch('/__lamp/' + path, { method: 'POST', body: JSON.stringify(body), keepalive: true }).catch(() => {}); } catch (e) {} };
  const handlers = { lampLive: { postMessage: said => send('said', said) }, lampPlaying: { postMessage: state => send('said', { state: 'page-' + state }) } };
  try { window.webkit = window.webkit || {}; window.webkit.messageHandlers = Object.assign(window.webkit.messageHandlers || {}, handlers); }
  catch (e) { try { Object.defineProperty(window, 'webkit', { value: { messageHandlers: handlers }, configurable: true }); } catch (e) {} }
  let lines = [], timer = null;
  const say = (level, parts) => {
    let text;
    try { text = parts.map(p => typeof p === 'string' ? p : p instanceof Error ? (p.stack || p.message) : JSON.stringify(p)).join(' '); } catch (e) { text = String(parts[0]); }
    lines.push((level === 'log' ? '' : level + ': ') + String(text).slice(0, 4000));
    if (!timer) timer = setTimeout(() => { timer = null; const batch = lines; lines = []; send('log', { lines: batch }); }, 300);
  };
  for (const level of ['log', 'info', 'warn', 'error']) {
    const real = console[level];
    console[level] = (...parts) => { real.apply(console, parts); say(level === 'info' ? 'log' : level, parts); };
  }
  // A page with the game runtime logs its own errors; any other page's are logged here.
  window.addEventListener('error', e => { if (!window.__lampLive) say('error', [e.message + ' (' + String(e.filename || '').split('/').pop() + ':' + e.lineno + ')']); });
  window.addEventListener('unhandledrejection', e => { if (!window.__lampLive) say('error', [String(e.reason && e.reason.message || e.reason)]); });
  const events = new EventSource('/__lamp/events');
  events.addEventListener('change', e => {
    const change = JSON.parse(e.data);
    // A game takes the change and keeps the player's place; any other page opens again.
    let taken = false;
    try { taken = !!(window.__lampLive && window.__lampLive(change)); } catch (e) {}
    if (!taken) { send('said', { gen: change.gen, state: 'reloading' }); location.reload(); }
  });
})();
`;

function usage(problem) {
  if (problem) console.error(`lamp: ${problem}\n`);
  console.error("Usage: lamp dev [folder] [--port 4400] [--open]\n\nRuns the web app or game in the folder and puts each saved change into the open page.");
  process.exit(problem ? 1 : 0);
}

const args = process.argv.slice(2);
if (args[0] !== "dev") usage(args.length && args[0] !== "--help" && args[0] !== "-h" ? `there's no "${args[0]}" yet, only dev` : null);
let folder = ".", port = 4400, opens = false;
for (let i = 1; i < args.length; i++) {
  if (args[i] === "--port") port = Number(args[++i]);
  else if (args[i] === "--open") opens = true;
  else if (args[i] === "--help" || args[i] === "-h") usage();
  else if (args[i].startsWith("-")) usage(`unknown option ${args[i]}`);
  else folder = args[i];
}
if (!Number.isInteger(port) || port < 1 || port > 65535) usage("--port takes a number from 1 to 65535");
folder = resolve(folder);
if (!existsSync(folder) || !statSync(folder).isDirectory()) usage(`${folder} isn't a folder`);

// The page: Web/ in an app Lamp made, else the folder itself for a plain site.
const root = [join(folder, "Web"), folder].find((candidate) => existsSync(join(candidate, "index.html")));
if (!root) usage(`${folder} has no page: no Web/index.html and no index.html`);
const isGame = existsSync(join(root, RUNTIME_FILE));
const logFolder = join(folder, ".lamp", "runtime"), logFile = join(logFolder, "log.txt");
mkdirSync(logFolder, { recursive: true });
writeFileSync(logFile, "");

// What's never part of a change: hidden files and folders, what tools keep beside the code, and Lamp's own two files.
const ignored = (path) => path.split("/").some((part) => part.startsWith(".") || part === "node_modules") || path.endsWith("~")
  || path === DEVICE_FILE || path === BUILD_FILE;

/** Every file of the page, by its path under the root. */
function filesUnder(dir = root, prefix = "", found = []) {
  for (const entry of readdirSync(dir, { withFileTypes: true })) {
    const path = prefix + entry.name;
    if (ignored(path)) continue;
    if (entry.isDirectory()) filesUnder(join(dir, entry.name), path + "/", found);
    else if (entry.isFile()) found.push(path);
  }
  return found;
}

// A file as it last was, to tell a real change from a save that changed nothing: its size and when it was written.
const stamp = (path) => { try { const s = statSync(join(root, path)); return s.isFile() ? `${s.size}:${s.mtimeMs}` : null; } catch { return null; } };
const known = new Map(filesUnder().map((path) => [path, stamp(path)]));

/** A name for the page's files as they are, so a copy opened after a change knows it's a newer build. */
function buildName() {
  const hash = createHash("sha256");
  for (const path of [...known.keys()].sort()) hash.update(path).update(known.get(path) ?? "");
  return hash.digest("hex").slice(0, 16);
}

const clients = new Set();
let gen = 0;
const waitingFor = new Map();   // gen → what changed, until the page says how it went
const time = () => new Date().toLocaleTimeString([], { hour12: false });
const print = (text) => console.log(`${time()}  ${text}`);

function broadcast(changed, removed) {
  gen += 1;
  const change = { gen, changed, removed, now: false, pill: true };
  const what = [...changed, ...removed.map((path) => `${path} (removed)`)];
  waitingFor.set(gen, what.length > 4 ? `${what.slice(0, 3).join(", ")} and ${what.length - 3} more` : what.join(", "));
  if (waitingFor.size > 50) waitingFor.delete(waitingFor.keys().next().value);
  const data = `event: change\ndata: ${JSON.stringify(change)}\n\n`;
  for (const response of clients) response.write(data);
  if (!clients.size) print(`${waitingFor.get(gen)}: no page is open; it's in the next one opened`);
}

// Saves are gathered for a moment, so a change of several files goes to the page as one.
let pending = new Set(), timer = null;
function noticed(path) {
  if (!path) return;
  path = path.split(sep).join("/");
  if (ignored(path)) return;
  pending.add(path);
  clearTimeout(timer);
  timer = setTimeout(() => {
    const changed = [], removed = [];
    for (const path of pending) {
      const now = stamp(path), before = known.get(path);
      if (now === before || (now === null && before === undefined)) continue;
      if (now === null) { known.delete(path); removed.push(path); }
      else { known.set(path, now); changed.push(path); }
    }
    pending = new Set();
    if (changed.length || removed.length) broadcast(changed.sort(), removed.sort());
  }, 120);
}
watch(root, { recursive: true }, (_event, name) => noticed(name));

// How the page says a change went, in plain words.
const OUTCOMES = {
  swapped: "swapped in while it ran",
  rerun: "the game's code ran again, the player where they were",
  reloading: "the page opened again",
  restored: "back where the player was",
  fresh: "started fresh",
  held: "waiting: press Reload in the page to apply",
};

function said(message) {
  const { gen: about, state, why } = message;
  if (state === "page-playing") return print("the game is playing");
  if (!OUTCOMES[state]) return;
  const what = waitingFor.get(about);
  print(`${what ? what + " → " : ""}${OUTCOMES[state]}${why ? ` (${why})` : ""}`);
}

async function body(request) {
  const chunks = [];
  let size = 0;
  for await (const chunk of request) { chunks.push(chunk); size += chunk.length; if (size > 2_000_000) return null; }
  try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return null; }
}

const server = createServer(async (request, response) => {
  const url = new URL(request.url, "http://localhost");
  const send = (status, type, content) => {
    response.writeHead(status, { "Content-Type": type, "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" });
    response.end(request.method === "HEAD" ? undefined : content);
  };
  // Only this Mac's own pages talk to the server: a page elsewhere can't read the folder through the browser.
  const host = (request.headers.host || "").replace(/:\d+$/, "");
  if (!["localhost", "127.0.0.1"].includes(host)) return send(403, "text/plain", "Not this page's server");
  if (url.pathname === "/__lamp/client.js") return send(200, TYPES[".js"], CLIENT);
  if (url.pathname === "/__lamp/events") {
    response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive" });
    response.write(": lamp dev\n\n");
    clients.add(response);
    const beat = setInterval(() => response.write(": still here\n\n"), 20_000);
    request.on("close", () => { clearInterval(beat); clients.delete(response); });
    return;
  }
  if (request.method === "POST" && url.pathname === "/__lamp/said") { const message = await body(request); if (message) said(message); return send(204, "text/plain", ""); }
  if (request.method === "POST" && url.pathname === "/__lamp/log") {
    const message = await body(request);
    if (Array.isArray(message?.lines)) { try { appendFileSync(logFile, message.lines.map((line) => String(line) + "\n").join("")); } catch {} }
    return send(204, "text/plain", "");
  }
  if (request.method !== "GET" && request.method !== "HEAD") return send(405, "text/plain", "Method not allowed");

  let path;
  try { path = decodeURIComponent(url.pathname); } catch { return send(400, "text/plain", "Bad path"); }
  if (path.endsWith("/")) path += "index.html";
  const file = resolve(join(root, path));
  if (file !== root && !file.startsWith(root + sep)) return send(403, "text/plain", "Outside the page");
  const name = relative(root, file).split(sep).join("/");
  // Hidden files (.git, .lamp, .env) are no part of the page.
  if (name.split("/").some((part) => part.startsWith("."))) return send(404, "text/plain", "Not found");
  let content;
  try {
    const info = await stat(file);
    if (info.isDirectory()) { response.writeHead(302, { Location: url.pathname + "/" }); return response.end(); }
    content = await readFile(file);
  } catch {
    if (isGame && name === DEVICE_FILE) return send(200, TYPES[".js"], ANY_BROWSER);
    if (isGame && name === BUILD_FILE) return send(200, TYPES[".js"], `export default "${buildName()}";\n`);
    return send(404, "text/plain", "Not found");
  }
  const type = TYPES[extname(file).toLowerCase()] ?? "application/octet-stream";
  if (type.startsWith("text/html")) {
    // First in the page, before any script of its own.
    const html = content.toString("utf8"), tag = '<script src="/__lamp/client.js"></script>';
    content = /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, (found) => found + tag) : tag + html;
  }
  send(200, type, content);
});

server.on("error", (error) => {
  console.error(error.code === "EADDRINUSE" ? `lamp: port ${port} is in use; pass --port with another` : `lamp: ${error.message}`);
  process.exit(1);
});
server.listen(port, "127.0.0.1", () => {
  const address = `http://localhost:${port}/`;
  console.log(`lamp dev  ${isGame ? "a game" : "a page"} in ${root}`);
  console.log(`  Open  ${address}`);
  console.log(`  Log   ${logFile}`);
  console.log(`  Each save goes into the open page.${isGame ? " A game keeps the player's place." : ""}\n`);
  if (opens) spawn(process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open", [address], { stdio: "ignore", shell: process.platform === "win32", detached: true }).unref();
});
