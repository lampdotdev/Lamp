// An app Lamp made in Swift, built and run on this Mac from its folder, with Lamp's app closed. The folder holds all
// it takes: its own build script (build.sh, which Lamp writes) builds build/<Name>.app, and the app's support code
// (Sources/LampSupport.swift) reads where Lamp is from values in its Info.plist (`LampInstall`, which Lamp's app
// writes into every copy it installs: `Template.installValues`). Here lamp writes those values, so the app takes lamp
// for its Lamp: it keeps its log and pictures of its own windows in the folder's .lamp/runtime, and takes a picture
// when lamp asks it to, with no permission asked of anyone (an app may picture its own windows).
//
// A saved change builds the app again and opens it again. Putting a change into the app while it runs is Lamp's
// app's still (`LiveReload`): `lamp open --in-lamp` hands the folder to it (outside.mjs).

import { createServer } from "node:http";
import { randomBytes, createHash, createHmac } from "node:crypto";
import { spawn, spawnSync } from "node:child_process";
import { watch, existsSync, statSync, mkdirSync, appendFileSync, writeFileSync, readFileSync, readdirSync, rmSync, copyFileSync, openSync, readSync, closeSync, cpSync, realpathSync, readlinkSync, chmodSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, sep } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, manifestOf, projectOf, stateOf, serverFileOf, firstPortOf } from "./state.mjs";

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** Whether the folder is an app Lamp made in Swift for the Mac: its package, and the build script Lamp writes. */
export const isMacApp = (folder) => existsSync(join(folder, "Package.swift")) && existsSync(join(folder, "build.sh")) && existsSync(join(folder, "Sources"));

/**
 * lamp's moves as a Mac app's driver takes them (`LampDriver`, the actions of Lamp's `use_app`), for lamp's own copy
 * of the app and for one Lamp's app has open alike.
 */
export function macActions(moves) {
  const number = (value, what) => { const n = Number(value); if (!Number.isFinite(n)) throw new Problem(what); return n; };
  return moves.map((move) => {
    if (move.kind === "click") return move.target ? { action: "click", target: String(move.target) } : { action: "click", x: number(move.x, "click takes a point of the picture, or a name from the screen as text"), y: number(move.y, "click takes a point of the picture, or a name from the screen as text") };
    if (move.kind === "type") return { action: "type", text: String(move.text ?? "") };
    if (move.kind === "key") return { action: "key", key: String(move.key), ...(Number(move.seconds) ? { amount: Math.min(Number(move.seconds), 10) } : {}) };
    if (move.kind === "drag") return { action: "drag", x: number(move.x, "drag takes where it starts and ends"), y: number(move.y, "drag takes where it starts and ends"), to_x: number(move.toX, "drag takes where it starts and ends"), to_y: number(move.toY, "drag takes where it starts and ends") };
    if (move.kind === "scroll") return { action: "scroll", amount: number(move.points, "scroll takes how far, down being positive"), ...(Number.isFinite(Number(move.x)) && Number.isFinite(Number(move.y)) ? { x: Number(move.x), y: Number(move.y) } : {}) };
    if (move.kind === "wait") return { action: "wait", amount: Math.min(Math.max(Number(move.seconds) || 1, 0), 30) };
    throw new Problem("a Mac app takes click, type, key, drag, scroll and wait: a stick and buttons are a game's");
  });
}

// MARK: Lamp's own files

const STARTER = join(dirname(fileURLToPath(import.meta.url)), "lamps", "mac-starter");

/**
 * A Mac app's starting files as Lamp's app makes them (`Template.scaffold`), from a copy Lamp's own code wrote under a
 * stand-in name (scripts/cli-files.sh), named `title` (letters, digits and spaces). With `only`, just those of them
 * (Lamp's own: Package.swift, build.sh, Sources/LampSupport.swift), each only where the folder has none: an app that
 * came in a shared file, which carries none of Lamp's files, gets this Lamp's before it builds.
 */
export function writeMacStarter(folder, title, { only = null } = {}) {
  if (!existsSync(join(STARTER, "lamp-starter.json"))) {
    throw new Problem(`Lamp's starting files for a Mac app aren't made yet. In Lamp's folder, run scripts/cli-files.sh: it writes them from Lamp's own code.`);
  }
  const stood = JSON.parse(readFileSync(join(STARTER, "lamp-starter.json"), "utf8"));
  // The program's name is the one the package already gives it, where it has one, so the script builds what's there.
  const given = (() => { try { return /name:\s*"([A-Za-z][A-Za-z0-9]*)"/.exec(readFileSync(join(folder, "Package.swift"), "utf8"))?.[1]; } catch { return null; } })();
  const exe = given ?? title.split(/\s+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(""), slug = exe.toLowerCase();
  const named = (text) => text.replaceAll(stood.bundle, `dev.lamp.cli.app.${slug}`).replaceAll(stood.name, title).replaceAll(stood.exe, exe).replaceAll(stood.slug, slug);
  const copy = (from, to, at = "") => {
    mkdirSync(to, { recursive: true });
    for (const entry of readdirSync(from, { withFileTypes: true })) {
      // What Lamp's app knows of the stand-in (.lamp) and the names it stood for aren't the new app's.
      if (entry.name === ".lamp" || entry.name === "lamp-starter.json") continue;
      // A starter from npm carries its .gitignore as gitignore, since npm leaves the other name out of a package.
      const as = at === "" && entry.name === "gitignore" ? ".gitignore" : named(entry.name);
      const source = join(from, entry.name), path = at + as, target = join(to, as);
      if (entry.isDirectory()) { copy(source, target, path + "/"); continue; }
      if (!entry.isFile() || (only && (!only.includes(path) || existsSync(target)))) continue;
      // Lamp's building blocks are the same for every app; the rest names this one.
      if (entry.name === "LampSupport.swift" || !/\.(swift|sh|md|json|plist|txt)$|^\.gitignore$/.test(entry.name)) cpSync(source, target);
      else writeFileSync(target, named(readFileSync(source, "utf8")));
      chmodSync(target, statSync(source).mode);
    }
  };
  copy(STARTER, folder);
}

/** A name Lamp's starting files can carry into a build script and code: letters, digits and spaces, a letter first. */
export function safeTitle(name) {
  const words = String(name ?? "").normalize("NFKD").replace(/[^A-Za-z0-9 ]+/g, " ").trim().split(/\s+/).filter(Boolean);
  const title = words.join(" ").replace(/^[0-9 ]+/, "").slice(0, 40).trim();
  return title || "App";
}

// MARK: The build's sandbox
//
// The build runs what's in the folder: its script, its package (which SwiftPM runs as a program before it builds
// anything) and whatever its code does as it compiles. Lamp's app runs it under sandbox-exec with a profile that
// closes every person's files and opens the app's own folder and what a build needs (`Sandbox.profile`); this is that
// profile, for a build. Later rules win, so the order is the meaning.

const real = (path) => { try { return realpathSync.native(path); } catch { return path; } };
const quotedPath = (path) => JSON.stringify(path);

/** The Xcode or command line tools in use, wherever they are: read by every compile, never written. */
function developerFolders() {
  const given = [process.env.DEVELOPER_DIR, (() => { try { return readlinkSync("/var/db/xcode_select_link"); } catch { return null; } })()];
  const folders = [];
  for (const folder of given) {
    if (!folder?.startsWith("/")) continue;
    const path = real(folder), at = path.indexOf(".app/");
    const bundle = at < 0 ? path : path.slice(0, at + 4);
    if (bundle !== "/" && !folders.includes(bundle)) folders.push(bundle);
  }
  return folders;
}

function buildProfile(app, bin) {
  const home = real(homedir());
  const lines = [
    "(version 1)",
    "(allow default)",
    '(deny file-read* file-write* (subpath "/Users") (subpath "/Volumes") (subpath "/Network") (subpath "/private/var/root"))',
    '(deny file-read* file-write* (subpath "/Library/Application Support") (subpath "/Library/Keychains"))',
    `(deny file-read* file-write* (subpath ${quotedPath(home)}))`,
    // What a build needs from the home folder: the toolchain, package caches, git's settings. Read only, apart from the caches.
    `(allow file-read* (subpath ${quotedPath(home + "/Library/Developer")}) (subpath ${quotedPath(home + "/.swiftpm")}) (literal ${quotedPath(home + "/.gitconfig")}) (subpath ${quotedPath(home + "/.config/git")}))`,
    `(allow file-read* file-write* (subpath ${quotedPath(home + "/Library/Caches")}) (subpath ${quotedPath(home + "/Library/org.swift.swiftpm")}) (subpath "/private/tmp") (subpath "/tmp"))`,
  ];
  if (process.env.TMPDIR) lines.push(`(allow file-read* file-write* (subpath ${quotedPath(real(process.env.TMPDIR))}))`);
  const developer = developerFolders();
  for (const folder of developer) {
    lines.push(`(allow file-read* (subpath ${quotedPath(folder)}))`);
    for (let path = dirname(folder); path !== "/"; path = dirname(path)) lines.push(`(allow file-read-metadata (literal ${quotedPath(path)}))`);
  }
  // The app's own folder opens, by its own name.
  lines.push(`(allow file-read* file-write* (subpath ${quotedPath(app)}))`);
  // lamp's \`swift\`, first on the build's path, is read and run from where lamp keeps it; nothing else of lamp's state opens.
  if (bin) {
    lines.push(`(allow file-read* (subpath ${quotedPath(real(bin))}))`);
    for (let path = dirname(real(bin)); path !== "/"; path = dirname(path)) lines.push(`(allow file-read-metadata (literal ${quotedPath(path)}))`);
  }
  // Where programs are found and run from stays as it is: nothing the build leaves there is run by anyone later.
  lines.push(`(deny file-write* (subpath ${quotedPath(real("/opt/homebrew"))}) (subpath ${quotedPath(real("/usr/local"))}))`);
  lines.push(`(deny file-write* ${[real("/Applications"), ...developer].map((path) => `(subpath ${quotedPath(path)})`).join(" ")})`);
  // The folders on the way to the app's can be looked at, not read: a program resolving a path looks at every step.
  for (let path = dirname(app); path.startsWith(home) && path.length >= home.length; path = dirname(path)) {
    lines.push(`(allow file-read-metadata (literal ${quotedPath(path)}))`);
    if (path === home) break;
  }
  lines.push(`(allow file-read-metadata (literal ${quotedPath(dirname(home))}))`);
  // Xcode's helpers that stay running are found through shared memory, whoever started them: each build starts its own.
  lines.push('(deny ipc-posix-shm* (ipc-posix-name-regex #"^/?ib"))');
  return lines.join("\n") + "\n";
}

// SwiftPM runs its builds under a sandbox of its own, which macOS won't start inside another: this `swift`, put first
// on the build's path, hands its build commands --disable-sandbox (the build is fenced in already) and passes
// everything else to the real one. Lamp's own (`Sandbox.swiftShim`).
const SWIFT_SHIM = `#!/bin/bash
# Written by lamp. SwiftPM's own sandbox can't start inside lamp's, which already confines the build.
here="$(cd "$(dirname "$0")" && pwd)"
rest="$(printf '%s' "$PATH" | tr ':' '\\n' | grep -vx "$here" | paste -sd: -)"
real="$(PATH="$rest" command -v swift)"
case "$1" in
    build|test|run|package) exec "$real" "$1" --disable-sandbox "\${@:2}" ;;
    *) exec "$real" "$@" ;;
esac
`;

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
  // An app that came without Lamp's own files (a shared file carries none) is given this Lamp's, as its app would.
  const missing = projectOf(folder).missing ?? [];
  if (missing.length) writeMacStarter(folder, safeTitle(manifestOf(folder)?.name ?? basename(folder)), { only: missing });
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
  // The build's fence, kept with lamp's own state, which the fence closes: the build can't change it.
  const fence = join(state, "sandbox");
  mkdirSync(join(fence, "bin"), { recursive: true });
  writeFileSync(join(fence, "bin", "swift"), SWIFT_SHIM);
  chmodSync(join(fence, "bin", "swift"), 0o755);
  writeFileSync(join(fence, "build.sb"), buildProfile(folder, join(fence, "bin")), { mode: 0o600 });

  // MARK: The files and their changes

  // What the build reads is a change: the code, the package and the app's own files. The app's notes and what Lamp
  // knows of it beside them (APP.md, icon.json…) aren't built, so saving one builds nothing.
  const ignored = (path) => path.split("/").some((part) => part.startsWith(".") || part === "build" || part === "node_modules") || path.endsWith("~")
    || (!path.includes("/") && /\.(md|json|txt)$/i.test(path));
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
  let running = null;           // lamp's own copy of it, which is the one that runs
  let shown = slug;             // its name as it shows it
  let child = null, launched = 0, quitting = false, exited = null;
  let building = null;          // the build under way, a promise
  let pendingFiles = new Set(), timer = null;

  /** Runs the app's own build script. What the compiler said, when it didn't build. */
  function runScript(env) {
    return new Promise((done) => {
      const began = Date.now();
      let said = "";
      const script = spawn("/usr/bin/sandbox-exec", ["-f", join(fence, "build.sb"), "/bin/zsh", "build.sh"],
        { cwd: folder, env: { ...process.env, ...env, PATH: `${join(fence, "bin")}:${process.env.PATH}` }, stdio: ["ignore", "pipe", "pipe"] });
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

  /**
   * Takes what the build made out of the folder, to where the build can't reach, and tells that copy where its Lamp
   * is: here. So what only lamp and the app have is never in the folder, for a later build to read, and the app
   * that runs is never one a build changed after it was made. The app's signature covers its Info.plist, so the copy
   * is signed again.
   */
  function stage(built) {
    const bundle = join(state, "app", basename(built));
    rmSync(join(state, "app"), { recursive: true, force: true });
    mkdirSync(join(state, "app"), { recursive: true });
    cpSync(built, bundle, { recursive: true, verbatimSymlinks: true });
    running = bundle;
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
    shown = read("CFBundleName") || shown;
    return read("CFBundleExecutable");
  }

  function launch() {
    const exe = stage(app);
    readAppLog();
    exited = null;
    quitting = false;
    launched = Date.now();
    // Kept awake while nobody looks at it (a default macOS reads from an app's arguments): an app the system has
    // put to sleep behind other windows, or with the display off, answers lamp's asking for a picture late or not at all.
    child = spawn(join(running, "Contents", "MacOS", exe), ["-NSAppSleepDisabled", "YES"], { stdio: ["ignore", "pipe", "pipe"] });
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
  async function look({ wait = 120, reopen = false } = {}) {
    lastUsed = Date.now();
    checkAll();
    const until = Date.now() + Math.max(0, wait) * 1000;
    while ((building || timer) && Date.now() < until) await sleep(100);
    // Opened again from its start, as someone opening it finds it: what it saved is still there.
    if (reopen && app && !building) { await quit(); launch(); }
    const unfinished = building || timer ? "the app was still being built" : null;
    let picture = null, more = [], screen = null, problem = null, remark = null;
    if (child) {
      // A moment for its first window, then the app pictures its own windows and says what's on them.
      if (Date.now() - launched < 2500) await sleep(2500 - (Date.now() - launched));
      const shot = join(runtime, "screenshot.png"), text = join(runtime, "screen.txt");
      const before = (() => { try { return statSync(shot).mtimeMs; } catch { return 0; } })();
      post(`${note}snapshot.${slug}`);
      // The first picture after a build takes longer: the system checks the app's new signature before it answers.
      for (let tries = 0, most = Date.now() - launched < 20_000 ? 150 : 60; tries < most; tries++) {
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
        // The app reads its screen through accessibility, on itself, which answers only once the app has been in
        // front with the screen unlocked.
        if (!screen) remark = "The app gave no screen as text (it can read its own screen only once it has been in front, with the Mac unlocked): aim by the picture, whose points are the points to click.";
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
      where: "mac", opened: false, playing: null, address: app, picture, pictures: more, title: shown, width: null, height: null, screen,
      unfinished, changes: since, errors: errors.slice(-20), note: remark,
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
    // In front, as Lamp's app puts it: the person sees what's done, and what only answers a real click takes it.
    activate();
    const actions = macActions(moves);
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

  function activate() {
    if (!child) return;
    spawnSync("/usr/bin/osascript", ["-l", "JavaScript", "-e", `ObjC.import("AppKit"); $.NSRunningApplication.runningApplicationWithProcessIdentifier(${child.pid}).activateWithOptions(2)`], { stdio: "ignore", timeout: 10_000 });
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
        if (!child && app && !building) launch();
        activate();
        return json(200, { opened: "app", url: shown, running: !!child, building: !!building });
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
