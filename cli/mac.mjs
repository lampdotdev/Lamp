// An app Lamp made in Swift, built and run on this Mac from its folder, with Lamp's app closed. The folder holds all
// it takes: its own build script (build.sh, which Lamp writes) builds build/<Name>.app, and the app's support code
// (Sources/LampSupport.swift) reads where Lamp is from values in its Info.plist (`LampInstall`, which Lamp's app
// writes into every copy it installs: `Template.installValues`). Here lamp writes those values, so the app takes lamp
// for its Lamp: it keeps its log and pictures of its own windows in the folder's .lamp/runtime, and takes a picture
// when lamp asks it to, with no permission asked of anyone (an app may picture its own windows).
//
// A saved change builds the app again and opens it again. Putting a change into the app while it runs is Lamp's
// app's still (`LiveReload`).

import { createServer } from "node:http";
import { randomBytes, createHash, createHmac } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { watch, existsSync, statSync, mkdirSync, appendFileSync, writeFileSync, readFileSync, readdirSync, rmSync, copyFileSync, openSync, readSync, closeSync } from "node:fs";
import { basename, dirname, join, sep } from "node:path";
import { Problem, stateOf, serverFileOf, firstPortOf } from "./state.mjs";

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** Whether the folder is an app Lamp made in Swift for the Mac: its package, and the build script Lamp writes. */
export const isMacApp = (folder) => existsSync(join(folder, "Package.swift")) && existsSync(join(folder, "build.sh")) && existsSync(join(folder, "Sources"));

/** Says something to every app listening for it on this Mac (a distributed notification), as Lamp's app does. */
function post(name, info = null) {
  spawnSync("/usr/bin/osascript", ["-l", "JavaScript", "-e",
    `ObjC.import("Foundation"); $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately(${JSON.stringify(name)}, $(), ${info ? `$(${JSON.stringify(info)})` : "$()"}, true)`],
  { stdio: "ignore", timeout: 10_000 });
}

/**
 * Starts building and running the app in the folder. `quiet` prints nothing; `idle` (minutes) ends a server nothing
 * has used for that long, which one started by `lamp look` is given.
 */
export async function serveMac({ folder, port: asked, quiet = false, idle = 0 } = {}) {
  if (process.platform !== "darwin") throw new Problem("an app made in Swift for the Mac is built and run on a Mac");
  const state = stateOf(folder), logFile = join(state, "log.txt"), runtime = join(folder, ".lamp", "runtime");
  mkdirSync(state, { recursive: true });
  // The app keeps its log and pictures here, as it does under Lamp's app, once the folder's .lamp is there.
  mkdirSync(runtime, { recursive: true });
  writeFileSync(logFile, "");
  const print = (text) => { if (!quiet) console.log(`${new Date().toLocaleTimeString([], { hour12: false })}  ${text}`); };
  const slug = basename(folder), commandToken = randomBytes(24).toString("hex"), run = randomBytes(6).toString("hex");
  // What only lamp and the app have, the same from one run to the next.
  const tokenFile = join(state, "app-token");
  if (!existsSync(tokenFile)) writeFileSync(tokenFile, randomBytes(24).toString("hex"), { mode: 0o600 });
  const appToken = readFileSync(tokenFile, "utf8").trim();
  const note = `dev.lamp.cli.${createHash("sha256").update(folder).digest("hex").slice(0, 8)}.`;

  // MARK: The files and their changes

  const ignored = (path) => path.split("/").some((part) => part.startsWith(".") || part === "build" || part === "node_modules") || path.endsWith("~");
  const filesUnder = (dir = folder, prefix = "", found = []) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = prefix + entry.name;
      if (ignored(path)) continue;
      if (entry.isDirectory()) filesUnder(join(dir, entry.name), path + "/", found);
      else if (entry.isFile()) found.push(path);
    }
    return found;
  };
  const stamp = (path) => { try { const s = statSync(join(folder, path)); return s.isFile() ? `${s.size}:${s.mtimeMs}` : null; } catch { return null; } };
  const known = new Map(filesUnder().map((path) => [path, stamp(path)]));

  let gen = 0, lastLookGen = 0;
  const changes = [];           // { gen, files, outcome, means, errors }
  const log = [];
  let logCount = 0, lastLookLine = 0;
  function logged(text, level = "log") {
    for (const line of String(text).split("\n")) {
      if (!line.trim()) continue;
      log.push({ n: ++logCount, level, text: line });
      try { appendFileSync(logFile, `${level !== "log" ? level + ": " : ""}${line}\n`); } catch {}
    }
    if (log.length > 800) log.splice(0, log.length - 800);
  }
  const isError = (line) => line.level === "error" || /(^|\s)(Fatal error|fatal error|error):/.test(line.text);
  // What the app prints goes to its own log in the folder (`LampRuntime`), a new one each launch: read on from where
  // it was last read, from the start when the file is a new one.
  const appLog = join(runtime, "log.txt");
  // What an earlier run left there isn't this one's.
  let appLogAt = (() => { try { return statSync(appLog).size; } catch { return 0; } })();
  let appLogFile = (() => { try { return statSync(appLog).ino; } catch { return 0; } })();
  function readAppLog() {
    let size = 0;
    try { const info = statSync(appLog); size = info.size; if (info.ino !== appLogFile) { appLogFile = info.ino; appLogAt = 0; } } catch { return; }
    if (size < appLogAt) appLogAt = 0;
    if (size === appLogAt) return;
    const bytes = Buffer.alloc(Math.min(size - appLogAt, 400_000));
    try { const file = openSync(appLog, "r"); readSync(file, bytes, 0, bytes.length, size - bytes.length); closeSync(file); } catch { return; }
    appLogAt = size;
    logged(bytes.toString("utf8"));
  }
  const appLogTimer = setInterval(readAppLog, 1000);
  appLogTimer.unref();

  // MARK: Building and running

  let app = null;               // build/<Name>.app once it's built
  let child = null, launched = 0, quitting = false, exited = null;
  let building = null;          // the build under way, a promise
  let pendingFiles = new Set(), timer = null;

  /** Runs the app's own build script. What the compiler said, when it didn't build. */
  function runScript(env) {
    return new Promise((done) => {
      const began = Date.now();
      let said = "";
      const script = spawn("/bin/zsh", ["build.sh"], { cwd: folder, env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] });
      script.stdout.on("data", (chunk) => { said += chunk; });
      script.stderr.on("data", (chunk) => { said += chunk; });
      script.on("error", (error) => done({ ok: false, seconds: 0, errors: [error.message] }));
      script.on("exit", (code) => {
        const seconds = Math.round((Date.now() - began) / 100) / 10;
        const made = existsSync(join(folder, "build")) ? readdirSync(join(folder, "build")).find((name) => name.endsWith(".app")) : null;
        if (code === 0 && made) return done({ ok: true, seconds, app: join(folder, "build", made) });
        // The compiler's own errors (a file, a line and what's wrong), each once, without its colors or the folder in
        // front of every path.
        const plain = said.replace(/\x1b\[[0-9;]*m/g, "").replace(/\x1b\]8;;[^\x07\x1b]*(?:\x07|\x1b\\)/g, "");
        const errors = [...new Set(plain.split("\n").filter((line) => /^\S.*:\d+:\d+: error: /.test(line)).map((line) => line.replaceAll(folder + "/", "").trim()))];
        const other = plain.split("\n").filter((line) => /^error: /.test(line) && !/Command line:/.test(line)).map((line) => line.slice(0, 300));
        done({ ok: false, seconds, errors: errors.length ? errors.slice(0, 20) : other.length ? other.slice(0, 8) : plain.trim().split("\n").slice(-8) });
      });
    });
  }

  // The build Lamp's app makes while an app is being changed (LAMP_LIVE: a debug build of a copy of the sources in
  // .lamp/live, which builds only what changed) takes a few seconds where the plain one takes most of a minute. The
  // copy has lines of Lamp's own in it, so when it doesn't build, the plain build says what's wrong in the app's own
  // code, and where; and an app whose copy doesn't build though its code does is built plainly from then on.
  let quick = true;
  async function build() {
    if (quick) {
      const live = await runScript({ LAMP_LIVE: "1" });
      if (live.ok) return live;
    }
    const plain = await runScript({ LAMP_LIVE: "" });
    if (plain.ok && quick) quick = false;
    return plain;
  }

  /** Tells the built app where its Lamp is: here. The app's signature covers its Info.plist, so it's signed again. */
  function stage(bundle) {
    const plist = join(bundle, "Contents", "Info.plist");
    const read = (key) => spawnSync("/usr/bin/plutil", ["-extract", key, "raw", plist], { encoding: "utf8" }).stdout.trim();
    const values = {
      slug, folder: slug, apps: dirname(folder), dataID: read("CFBundleIdentifier"), token: appToken,
      // Where the app asks Lamp for what it keeps for it: lamp's own server for this folder, which answers its
      // secrets and its Reload, and nothing else yet (its AI, sharing), which the app takes as Lamp saying no.
      port: String(port), scheme: "lamp-cli", note, host: "dev.lamp.cli", macHost: "127.0.0.1", widgetPort: "0", widgetToken: "",
    };
    spawnSync("/usr/bin/plutil", ["-replace", "LampInstall", "-json", JSON.stringify(values), plist], { stdio: "ignore" });
    spawnSync("/usr/bin/codesign", ["--force", "-s", "-", bundle], { stdio: "ignore" });
    return read("CFBundleExecutable");
  }

  function launch() {
    const exe = stage(app);
    readAppLog();
    exited = null;
    quitting = false;
    launched = Date.now();
    child = spawn(join(app, "Contents", "MacOS", exe), [], { stdio: ["ignore", "pipe", "pipe"] });
    const mine = child;
    child.stdout.on("data", (chunk) => logged(chunk));
    child.stderr.on("data", (chunk) => logged(chunk));
    child.on("exit", (code, signal) => {
      if (child !== mine) return;
      child = null;
      if (quitting) return;
      // It went without being asked: it crashed, or the person quit it.
      exited = { code, signal, at: Date.now() };
      if (signal || code) { logged(`The app quit unexpectedly (${signal ?? `exit ${code}`}).`, "error"); print(`  ! the app quit unexpectedly (${signal ?? `exit ${code}`})`); }
      else print("the app was quit");
    });
  }

  async function quit() {
    if (!child) return;
    quitting = true;
    const going = child;
    going.kill("SIGTERM");
    for (let tries = 0; tries < 30 && child === going; tries++) await sleep(100);
    if (child === going) { going.kill("SIGKILL"); await sleep(200); child = null; }
  }

  /** Builds what the folder holds now and opens it in place of what's running. One at a time. */
  function rebuild(files) {
    const change = files ? { gen: ++gen, files: [...files].sort(), outcome: "building", means: "being built", errors: [] } : null;
    if (change) { changes.push(change); if (changes.length > 40) changes.shift(); }
    const named = change ? (change.files.length > 4 ? `${change.files.slice(0, 3).join(", ")} and ${change.files.length - 3} more` : change.files.join(", ")) : "the app";
    building = (building ?? Promise.resolve()).then(async () => {
      const built = await build();
      if (!built.ok) {
        if (change) Object.assign(change, { outcome: "not built", means: "it didn't build, so the app is as it was", errors: built.errors });
        for (const error of built.errors) logged(error, "error");
        print(`${named} → didn't build (${built.seconds} s)`);
        for (const error of built.errors.slice(0, 5)) print(`  ! ${error.slice(0, 300)}`);
        return;
      }
      app = built.app;
      await quit();
      launch();
      if (change) Object.assign(change, { outcome: "reopened", means: `built in ${built.seconds} s and opened again` });
      print(`${named} → built in ${built.seconds} s and opened${change ? " again" : ""}`);
    }).catch((error) => { logged(String(error?.message ?? error), "error"); });
    const mine = building;
    mine.finally(() => { if (building === mine) building = null; });
    return mine;
  }

  function check(paths) {
    const changed = [];
    for (const path of paths) {
      const now = stamp(path), before = known.get(path);
      if (now === before || (now === null && before === undefined)) continue;
      if (now === null) known.delete(path); else known.set(path, now);
      changed.push(now === null ? `${path} (removed)` : path);
    }
    if (changed.length) rebuild(changed);
  }
  function noticed(path) {
    if (!path) return;
    path = path.split(sep).join("/");
    if (ignored(path)) return;
    pendingFiles.add(path);
    clearTimeout(timer);
    // Longer than for a page: a change here costs a build, and an edit of several files is one change.
    timer = setTimeout(() => { timer = null; const paths = pendingFiles; pendingFiles = new Set(); check(paths); }, 500);
  }
  function checkAll() {
    clearTimeout(timer);
    timer = null;
    pendingFiles = new Set();
    check(new Set([...known.keys(), ...filesUnder()]));
  }
  const watcher = watch(folder, { recursive: true }, (_event, name) => noticed(name));
  watcher.on("error", () => {});

  // MARK: Looking

  let pictures = 0, lastUsed = Date.now();
  for (const name of readdirSync(state)) if (/^look(-\d+)*\.png$/.test(name)) rmSync(join(state, name), { force: true });

  /** How the changes since the last look went, pictures of the app's windows, its screen as text, and its log. */
  async function look({ wait = 120 } = {}) {
    lastUsed = Date.now();
    checkAll();
    const until = Date.now() + Math.max(0, wait) * 1000;
    while ((building || timer) && Date.now() < until) await sleep(100);
    const unfinished = building || timer ? "the app was still being built" : null;
    let picture = null, more = [], screen = null, problem = null;
    if (child) {
      // A moment for its first window, then the app pictures its own windows and says what's on them.
      if (Date.now() - launched < 2500) await sleep(2500 - (Date.now() - launched));
      const shot = join(runtime, "screenshot.png"), text = join(runtime, "screen.txt");
      const before = (() => { try { return statSync(shot).mtimeMs; } catch { return 0; } })();
      post(`${note}snapshot.${slug}`);
      for (let tries = 0; tries < 60; tries++) {
        try { if (statSync(shot).mtimeMs > before) break; } catch {}
        await sleep(100);
      }
      const taken = (() => { try { return statSync(shot).mtimeMs; } catch { return 0; } })();
      if (taken > before || (taken && taken >= launched)) {
        await sleep(150);
        const n = ++pictures;
        picture = join(state, `look-${n}.png`);
        copyFileSync(shot, picture);
        for (const index of [2, 3]) {
          const other = join(runtime, `screenshot-${index}.png`);
          try { if (statSync(other).mtimeMs >= taken - 2000) { const to = join(state, `look-${n}-${index}.png`); copyFileSync(other, to); more.push(to); } } catch {}
        }
        rmSync(join(state, `look-${n - 40}.png`), { force: true });
        try { if (statSync(text).mtimeMs >= taken - 2000) screen = readFileSync(text, "utf8").trim() || null; } catch {}
        if (taken <= before) problem = "The app took no new picture just now (its windows can't be pictured while the screen is locked or the display is asleep): this is its last one.";
      } else {
        problem = "The app took no picture of its windows: they can't be pictured while the screen is locked, the display is asleep, or the app is hidden.";
      }
    } else if (!app) {
      problem = "The app isn't built yet, so there's nothing to look at.";
    } else {
      problem = exited && (exited.signal || exited.code) ? "The app isn't running: it quit unexpectedly. Its log says why." : "The app isn't running: it was quit. A change, or lamp reload, opens it again.";
    }
    readAppLog();
    const since = changes.filter((change) => change.gen > lastLookGen)
      .map((change) => ({ files: change.files.length > 4 ? `${change.files.slice(0, 3).join(", ")} and ${change.files.length - 3} more` : change.files.join(", "), outcome: change.outcome, means: change.means, why: "" }));
    const fresh = log.filter((line) => line.n > lastLookLine);
    const errors = [...new Set(fresh.filter(isError).map((line) => line.text))];
    lastLookGen = gen;
    lastLookLine = logCount;
    return {
      where: "mac", opened: false, playing: null, address: app, picture, pictures: more, title: app ? basename(app, ".app") : slug, width: null, height: null, screen,
      unfinished, changes: since, errors: errors.slice(-20),
      log: fresh.filter((line) => !isError(line)).slice(-25).map((line) => line.text), logLines: fresh.length, logFile, problem,
    };
  }

  /**
   * Things done in the app as a person would, by the app's own driver (`LampDriver` in its support code), asked the
   * way Lamp's app asks: signed with what only lamp and the app have, and answered in the app's own words.
   */
  async function use(asked) {
    lastUsed = Date.now();
    const moves = Array.isArray(asked?.moves) ? asked.moves : [asked];
    if (building) await building;
    if (!child) throw new Problem("the app isn't running: lamp look says why");
    const number = (value, what) => { const n = Number(value); if (!Number.isFinite(n)) throw new Problem(what); return n; };
    const actions = moves.map((move) => {
      if (move.kind === "click") return move.target ? { action: "click", target: String(move.target) } : { action: "click", x: number(move.x, "click takes a point of the picture, or a name from the screen as text"), y: number(move.y, "click takes a point of the picture, or a name from the screen as text") };
      if (move.kind === "type") return { action: "type", text: String(move.text ?? "") };
      if (move.kind === "key") return { action: "key", key: String(move.key), ...(Number(move.seconds) ? { amount: Math.min(Number(move.seconds), 10) } : {}) };
      if (move.kind === "drag") return { action: "drag", x: number(move.x, "drag takes where it starts and ends"), y: number(move.y, "drag takes where it starts and ends"), to_x: number(move.toX, "drag takes where it starts and ends"), to_y: number(move.toY, "drag takes where it starts and ends") };
      if (move.kind === "scroll") return { action: "scroll", amount: number(move.points, "scroll takes how far, down being positive"), ...(Number.isFinite(Number(move.x)) && Number.isFinite(Number(move.y)) ? { x: Number(move.x), y: Number(move.y) } : {}) };
      if (move.kind === "wait") return { action: "wait", amount: Math.min(Math.max(Number(move.seconds) || 1, 0), 30) };
      throw new Problem("a Mac app takes click, type, key, drag, scroll and wait: a stick and buttons are a game's");
    });
    const id = randomBytes(8).toString("hex"), json = JSON.stringify(actions), answerFile = join(runtime, "use.json");
    rmSync(answerFile, { force: true });
    post(`${note}useApp.${slug}`, { actions: json, id, lampUseAppSignature: createHmac("sha256", appToken).update(`${id}\n${json}`).digest("hex") });
    const until = Date.now() + 20_000 + actions.reduce((total, action) => total + (action.amount && action.action !== "scroll" ? action.amount * 1000 : 0), 0);
    let answer = null;
    while (Date.now() < until && child) {
      try { const read = JSON.parse(readFileSync(answerFile, "utf8")); if (read.id === id) { answer = read; break; } } catch {}
      await sleep(100);
    }
    const did = answer ? (answer.report || "Done.") + (answer.stopped ? "\nThe person took the app back: it's theirs until they ask again." : "")
      : child ? "The app didn't answer: nothing may have been done." : "The app quit while it was being used.";
    return { did, ...(await look({ wait: 30 })) };
  }

  // MARK: What the app asks of Lamp

  // The app's secrets (a service's sign-in, a key: `LampSecrets` in its support code), kept for it here as Lamp's app
  // keeps them, since macOS ties a Keychain item of the app's own to one build of it. With lamp's state for the
  // folder, readable only by the person, never in the folder.
  const secretsFile = join(state, "secrets.json");
  const secrets = () => { try { return JSON.parse(readFileSync(secretsFile, "utf8")); } catch { return {}; } };

  /** The answer to one thing the app asked: a status and what's said. */
  async function asksOfLamp(path, asked) {
    if (path === "/app/secrets") {
      const name = typeof asked.name === "string" ? asked.name : "";
      if (!name || name.length > 200) return [400, { error: "a secret has a name" }];
      const kept = secrets();
      if (asked.op === "read") return [200, { ok: true, ...(typeof kept[name] === "string" ? { value: kept[name] } : {}) }];
      if (asked.op === "save" && typeof asked.value === "string" && asked.value.length < 200_000) kept[name] = asked.value;
      else if (asked.op === "delete") delete kept[name];
      else return [400, { error: "read, save or delete" }];
      writeFileSync(secretsFile, JSON.stringify(kept), { mode: 0o600 });
      return [200, { ok: true }];
    }
    // The app menu's Reload asks whether Lamp has a change of the app's waiting to go in: here a change goes in as
    // it's saved, so none is, and the app opens itself again.
    if (path === "/app/reload") return [200, { waiting: false }];
    // Its AI, sharing and the rest are Lamp's app's still.
    logged(`The app asked Lamp for ${path}, which lamp doesn't answer yet.`);
    return [404, { error: "Lamp's command line doesn't answer this yet." }];
  }

  // MARK: lamp's own commands

  let turns = Promise.resolve();
  const inTurn = (work) => { const mine = turns.then(work, work); turns = mine.catch(() => {}); return mine; };

  async function body(request) {
    const chunks = [];
    for await (const chunk of request) chunks.push(chunk);
    try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return null; }
  }
  const server = createServer((request, response) => {
    answer(request, response).catch(() => { try { if (!response.headersSent) response.writeHead(400); response.end(); } catch {} });
  });
  async function answer(request, response) {
    const url = new URL(request.url, "http://localhost");
    const json = (status, value) => { response.writeHead(status, { "Content-Type": "application/json; charset=utf-8", "Cache-Control": "no-store" }); response.end(JSON.stringify(value)); };
    const host = String(request.headers.host || "").replace(/:\d+$/, "").toLowerCase();
    if (!["localhost", "127.0.0.1"].includes(host) || request.headers.origin) return json(403, { problem: "not lamp's own command" });
    // What the app itself asks of its Lamp (`LampInstall.port`), shown the token only the two have.
    if (url.pathname.startsWith("/app/") || url.pathname.startsWith("/ai/")) {
      if (request.headers.authorization !== `Bearer ${appToken}` || request.method !== "POST") return json(403, { error: "not this app" });
      return json(...(await asksOfLamp(url.pathname, (await body(request)) ?? {})));
    }
    if (!url.pathname.startsWith("/__lamp/cli/") || request.headers["x-lamp-token"] !== commandToken) return json(403, { problem: "that isn't lamp's own command" });
    const what = url.pathname.slice("/__lamp/cli/".length);
    try {
      if (what === "hello") return json(200, { folder, url: app ?? `${slug} (being built)`, pid: process.pid, run, own: idle > 0, kind: "mac" });
      if (request.method !== "POST") return json(405, { problem: "not a thing to ask that way" });
      const asked = (await body(request)) ?? {};
      if (what === "look") return json(200, await inTurn(() => look(asked)));
      if (what === "open") {
        // Opened again when it was quit, and brought to the front.
        if (!child && app) launch();
        if (child) spawnSync("/usr/bin/osascript", ["-l", "JavaScript", "-e", `ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationWithProcessIdentifier(${child.pid}).activateWithOptions(2)`], { stdio: "ignore", timeout: 10_000 });
        return json(200, { opened: "app", url: app ?? slug });
      }
      if (what === "reload") { if (app) { await quit(); launch(); } return json(200, { pages: app ? 1 : 0 }); }
      if (what === "stop") { json(200, { stopped: true }); setTimeout(() => close().then(() => process.exit(0)), 50); return; }
      if (what === "use") return json(200, await inTurn(() => use(asked)));
      if (what === "card") return json(400, { problem: "sharing a Mac app is Lamp's app's still" });
      return json(404, { problem: `lamp dev doesn't know "${what}"` });
    } catch (error) {
      return json(error instanceof Problem ? 400 : 500, { problem: error.message });
    }
  }

  const portFile = join(state, "port");
  const remembered = Number((() => { try { return readFileSync(portFile, "utf8"); } catch { return ""; } })()) || 0;
  const first = firstPortOf(folder);
  let port = 0;
  for (const candidate of asked ? [asked] : [...new Set([remembered || first, ...Array.from({ length: 30 }, (_, i) => first + i)])]) {
    try {
      await new Promise((resolve, reject) => { server.once("error", reject); server.listen(candidate, "127.0.0.1", () => { server.off("error", reject); resolve(); }); });
      port = candidate;
      break;
    } catch (error) { if (error.code !== "EADDRINUSE") throw new Problem(error.message); }
  }
  if (!port) throw new Problem("no port is free for lamp's own commands");
  writeFileSync(portFile, String(port));
  writeFileSync(serverFileOf(folder), JSON.stringify({ port, pid: process.pid, token: commandToken, folder }), { mode: 0o600 });

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    clearInterval(idleTimer);
    clearInterval(appLogTimer);
    clearTimeout(timer);
    watcher.close();
    await quit();
    try { if (JSON.parse(readFileSync(serverFileOf(folder), "utf8")).pid === process.pid) rmSync(serverFileOf(folder)); } catch {}
    server.closeAllConnections?.();
    await new Promise((done) => server.close(done));
  }
  process.on("exit", () => { try { child?.kill("SIGTERM"); } catch {} });
  // A server `lamp look` started for itself ends once nothing has used it for a while, never under an app that's open.
  const idleTimer = setInterval(() => {
    if (!idle || Date.now() - lastUsed < idle * 60_000 || building || child) return;
    close().then(() => process.exit(0));
  }, 30_000);
  idleTimer.unref();

  if (!quiet) {
    console.log(`lamp dev  a Mac app in ${folder}`);
    console.log(`  Look  lamp look   how a change went, pictures of its windows, its screen as text and its log`);
    console.log(`  Log   ${logFile}`);
    console.log("  Each save builds the app again and opens it again.\n");
  }
  rebuild(null);
  return { url: null, port, token: commandToken, folder, state, logFile, look: (options) => inTurn(() => look(options)), close };
}
