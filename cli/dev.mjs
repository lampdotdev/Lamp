// lamp dev's server: serves a folder's page, watches its files, hands each saved change to the open pages, and answers
// lamp's other commands (look, use, open, stop) about them.
//
// A game made with Lamp's runtime (lamp-game.js beside the page) keeps the player's place: the runtime is handed the
// change exactly as Lamp's app around the page hands it over (`window.__lampLive`), and swaps the code in, runs it
// again in place, or opens the page again from where the player was. Any other page is opened again.

import { createServer } from "node:http";
import { createHash, randomBytes } from "node:crypto";
import { watch, statSync, mkdirSync, appendFileSync, writeFileSync, readFileSync, readdirSync, createReadStream, rmSync, realpathSync } from "node:fs";
import { readFile, stat, realpath } from "node:fs/promises";
import { networkInterfaces, hostname } from "node:os";
import { join, resolve, extname, sep, relative, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { spawn } from "node:child_process";
import { Problem, layoutOf, stateOf, logFileOf, serverFileOf, firstPortOf } from "./state.mjs";
import { findBrowser, launch, keyNamed } from "./browser.mjs";

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
export const DEVICE_FILE = "lamp-device.js";
const BUILD_FILE = "lamp-build.js";
// A browser on any device, as a page published to the web is given (`GamePage.anyBrowser`).
export const ANY_BROWSER = `// Written by lamp for a browser on any device (any-browser); don't edit.
export default {"keys":{"AltLeft":"Alt / Option","AltRight":"Alt / Option","Backspace":"Backspace / Delete","Enter":"Enter / Return","MetaLeft":"Win / ⌘","MetaRight":"Win / ⌘"}};
`;
const HERE = dirname(fileURLToPath(import.meta.url));
const PAGE_SCRIPT = readFileSync(join(HERE, "page.js"), "utf8");
// Lamp's building blocks for a page (AI, saved data, the app's files) come with Lamp's app around it, which writes
// lamp.js at each build. A game whose folder has none is given this in its place, so the page loads.
export const LAMP_JS = "// lamp's stand-in for lamp.js: Lamp's building blocks come with Lamp's app around the page, and aren't here.\n";
// The controllers a game names buttons for, which Lamp's app writes beside the page at every build and the game
// runtime can't load without: Lamp's list as a file (a test keeps it Lamp's, `CLIFilesTests`).
export const CONTROLLERS_FILE = "lamp-controllers.js", CONTROLLERS = join(HERE, "lamps", CONTROLLERS_FILE);
// The libraries Lamp puts beside a game's page when the page uses them (`DeviceSupport`), where they are in Lamp's
// own folder: a game whose folder has none of one is served Lamp's copy.
const LIBRARIES = join(HERE, "..", "Resources", "WebLibraries");
function lampsCopy(name) {
  if (name === CONTROLLERS_FILE) return CONTROLLERS;
  if (!/^(three|phaser|rapier)\//.test(name)) return null;
  const file = resolve(join(LIBRARIES, name));
  return file.startsWith(LIBRARIES + sep) ? file : null;
}

// How a page says a change went: the word lamp's commands answer with, and what it means.
const OUTCOMES = {
  swapped: ["live", "swapped in while it ran"],
  rerun: ["reran", "the game's code ran again, the player where they were"],
  reloading: ["reopened", "the page opened again"],
  held: ["held", "waiting for Reload to be pressed in the page, since the page must open again for it"],
};
// A change that only waits for a pause in the game goes in by itself then.
const HELD_FOR_A_PAUSE = "waiting for a pause in the game (the end of a round, a menu), and goes in by itself then";
// What a page says once it has finished with a change, or with opening.
const DONE = new Set(["swapped", "restored", "fresh", "held", "started", "shown"]);
const READY = new Set(["page-playing", "restored", "fresh", "started", "shown"]);

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
/** Log lines as a look shows them: a line said over and over, or the same but for its numbers, is shown once. */
function collapsed(lines) {
  const shown = [];
  for (const line of lines) {
    const text = `${line.level !== "log" ? line.level + ": " : ""}${line.text}`, shape = text.replace(/[\d.]+/g, "#");
    const last = shown[shown.length - 1];
    if (last && last.shape === shape) { last.text = text; last.times += 1; } else shown.push({ text, shape, times: 1 });
  }
  return shown.map((line) => (line.times > 1 ? `${line.text} (the last of ${line.times} like it)` : line.text));
}
const isError = (line) => line.level === "error" || /^(\[[\d.]+ s\] )?Error: /.test(line.text);

/**
 * Starts serving the folder. `port` asks for one port and no other; without it the folder's last is used again when
 * it's free (a game's saves belong to the address), else the folder's own (`firstPortOf`) or the next free. `lan` lets other devices on the
 * network open the page. `quiet` prints nothing. `idle` (minutes) ends a server nothing has used for that long, which
 * one started by `lamp look` is given.
 */
export async function serve({ folder: given, port: asked, lan = false, quiet = false, idle = 0 } = {}) {
  const layout = layoutOf(given ?? ".");
  const { folder, root } = layout;
  const state = stateOf(folder), logFile = logFileOf(layout), run = randomBytes(6).toString("hex"), token = randomBytes(24).toString("hex");
  mkdirSync(state, { recursive: true });
  mkdirSync(dirname(logFile), { recursive: true });
  writeFileSync(logFile, "");
  const print = (text) => { if (!quiet) console.log(`${new Date().toLocaleTimeString([], { hour12: false })}  ${text}`); };

  // MARK: The files and their changes

  // What's never part of a change: hidden files and folders, what tools keep beside the code, and Lamp's own two files.
  const ignored = (path) => path.split("/").some((part) => part.startsWith(".") || part === "node_modules") || path.endsWith("~")
    || path === DEVICE_FILE || path === BUILD_FILE;
  const filesUnder = (dir = root, prefix = "", found = []) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = prefix + entry.name;
      if (ignored(path)) continue;
      if (entry.isDirectory()) filesUnder(join(dir, entry.name), path + "/", found);
      else if (entry.isFile()) found.push(path);
    }
    return found;
  };
  // A file as it last was, to tell a real change from a save that changed nothing: its size and when it was written.
  const stamp = (path) => { try { const s = statSync(join(root, path)); return s.isFile() ? `${s.size}:${s.mtimeMs}` : null; } catch { return null; } };
  const known = new Map(filesUnder().map((path) => [path, stamp(path)]));
  // A name for the page's files as they are, so a copy opened after a change knows it's a newer build.
  const buildName = () => {
    const hash = createHash("sha256");
    for (const path of [...known.keys()].sort()) hash.update(path).update(known.get(path) ?? "");
    return hash.digest("hex").slice(0, 16);
  };

  let gen = 0, lastLookGen = 0;
  const changes = [];             // the last changes: { gen, changed, removed, said: Map(tab → { state, why }) }
  const pages = new Map();        // page id → { response, tab, at: the change it has taken, ready, since }
  const reopening = new Map();    // tab → when the page it said it's opening again is given up on
  const early = new Map();        // what a page said before its line for changes was open
  const printed = new Set();

  const named = (change) => {
    const what = [...change.changed, ...change.removed.map((path) => `${path} (removed)`)];
    return what.length > 4 ? `${what.slice(0, 3).join(", ")} and ${what.length - 3} more` : what.join(", ");
  };
  const tell = (page, event, data, id) => page.response.write(`${id === undefined ? "" : `id: ${id}\n`}event: ${event}\ndata: ${data}\n\n`);

  function broadcast(changed, removed) {
    gen += 1;
    const change = { gen, changed, removed, said: new Map() };
    changes.push(change);
    if (changes.length > 40) changes.shift();
    const data = JSON.stringify({ gen, changed, removed, now: false, pill: true });
    for (const page of pages.values()) { page.told = Date.now(); tell(page, "change", data, gen); }
    if (!pages.size) print(`${named(change)}: no page is open; it's in the next one opened`);
  }

  /** Hands the pages whichever of these files have changed or gone since they were last seen. */
  function check(paths) {
    const changed = [], removed = [];
    for (const path of paths) {
      const now = stamp(path), before = known.get(path);
      if (now === before || (now === null && before === undefined)) continue;
      if (now === null) { known.delete(path); removed.push(path); }
      else { known.set(path, now); changed.push(path); }
    }
    if (changed.length || removed.length) broadcast(changed.sort(), removed.sort());
  }
  // Saves are gathered for a moment, so a change of several files goes to the pages as one.
  let pending = new Set(), timer = null;
  function noticed(path) {
    if (!path) return;
    path = path.split(sep).join("/");
    if (ignored(path)) return;
    pending.add(path);
    clearTimeout(timer);
    timer = setTimeout(() => { timer = null; const paths = pending; pending = new Set(); check(paths); }, 120);
  }
  // A look straight after a save can come before the system says the file changed: every file is checked then.
  function checkAll() {
    clearTimeout(timer);
    timer = null;
    pending = new Set();
    check(new Set([...known.keys(), ...filesUnder()]));
  }
  const watcher = watch(root, { recursive: true }, (_event, name) => noticed(name));
  // A folder taken away while it's watched ends the watching, not lamp: a look still checks every file.
  watcher.on("error", () => {});
  // The page's files are those in its folder: a link in it to somewhere else isn't followed out.
  const rootReal = realpathSync(root);

  // MARK: What the pages say

  // The log: the last lines kept here, each with its number, and all of it in the file.
  const log = [];
  let logCount = 0, lastLookLine = 0, errorsPrinted = 0, errorsFrom = 0, lastErrorAt = 0;
  let takenOver = null;           // why the person has the game's controller back, when they took it from lamp
  function logged(lines) {
    for (const line of lines) {
      const entry = { n: ++logCount, level: String(line.level || "log"), text: String(line.text ?? "") };
      log.push(entry);
      if (isError(entry)) {
        lastErrorAt = Date.now();
        // A page stuck on an error says it every frame: a few a second are enough here, and all are in the file.
        const now = Date.now();
        if (now - errorsFrom > 1000) { errorsFrom = now; errorsPrinted = 0; }
        if (++errorsPrinted <= 3) print(`  ! ${entry.text.split("\n")[0].slice(0, 300)}`);
      }
    }
    if (log.length > 600) log.splice(0, log.length - 600);
    try { appendFileSync(logFile, lines.map((line) => `${line.level && line.level !== "log" ? line.level + ": " : ""}${line.text}\n`).join("")); } catch {}
  }

  function said(message) {
    const { page: id, gen: about, state, why, pause } = message;
    if (state === "taken-over") { takenOver = why || "the person played"; return; }
    const page = pages.get(id);
    if (!page && id) {
      // Its line for changes isn't open yet: this is heard once it is.
      if (early.size > 20) early.clear();
      early.set(id, [...(early.get(id) ?? []), message].slice(-10));
      return;
    }
    if (page) {
      // A page on Lamp's runtime says so as the runtime loads, and says when the game is playing; any other page is
      // taken as open once it has loaded, which is all it can say.
      if (state === "page-loading") page.runtime = true;
      if ((READY.has(state) || (state === "page-loaded" && !page.runtime)) && !page.ready) { page.ready = true; page.readyAt = Date.now(); }
      if (DONE.has(state)) { page.at = typeof about === "number" ? Math.max(page.at, about) : gen; page.rerunning = 0; }
      if (state === "rerun") page.rerunning = Date.now() + 15_000;
      if (state === "reloading") reopening.set(page.tab, Date.now() + 30_000);
    }
    const change = changes.find((change) => change.gen === about);
    // How the change went in a tab is the last such thing its page said of it (code that couldn't run again opens the
    // page again), with the first reason it gave: why it wasn't simply swapped in.
    if (change && OUTCOMES[state] && page) change.said.set(page.tab, { state, pause: !!pause, why: change.said.get(page.tab)?.why || why || "" });
    if (!OUTCOMES[state] && state !== "restored" && state !== "fresh") return;
    const key = `${about}:${state}`;
    if (printed.has(key)) return;
    printed.add(key);
    if (printed.size > 400) printed.clear();
    const words = state === "held" && pause ? HELD_FOR_A_PAUSE : OUTCOMES[state]?.[1] ?? (state === "restored" ? "back where the player was" : "started fresh");
    print(`${change ? named(change) + " → " : ""}${words}${why ? ` (${why})` : ""}`);
  }

  /**
   * What's still under way, in words, or null once the page has taken the last change and is past opening: the page
   * in this tab when one is named (the one being looked at), else every open page.
   */
  function underWay(tab) {
    const now = Date.now();
    for (const [one, until] of reopening) if (until < now) reopening.delete(one);
    if (timer || pending.size) return "a save was just made";
    if (tab ? reopening.has(tab) : reopening.size) return "the page was opening again";
    const mine = [...pages.values()].filter((page) => !tab || page.tab === tab);
    if (tab && !mine.length) return "the page was opening";
    for (const page of mine) {
      // A page that logged an error and then went quiet isn't going to say more: what it shows is looked at as it is.
      const failed = (since) => lastErrorAt > since && now - lastErrorAt > 1500;
      // A game with an older runtime never says it's playing: it's taken as open after a while.
      if (!page.ready && now - page.since < 25_000 && !failed(page.since)) return page.runtime ? "the game was still loading" : "the page was still opening";
      if (page.at < gen && now - page.told < 20_000 && !failed(page.told)) return "the page hadn't said how the last change went";
      if (page.rerunning > now && !failed(page.told)) return "the game's code was running again";
    }
    return null;
  }
  async function waitUntilSettled(ms, tab) {
    const until = Date.now() + ms;
    while (Date.now() < until) { if (!underWay(tab)) return null; await sleep(50); }
    return underWay(tab);
  }

  // MARK: The browser

  let address = "";
  let windowBrowser = null;       // the window the person uses
  let copyBrowser = null;         // a copy with no window, looked at when there's none
  let copyTimer = null, lastUsed = Date.now(), pictures = 0;
  // The pictures of an earlier run are no use to this one.
  for (const name of readdirSync(state)) if (/^look(-\d+)?\.png$/.test(name)) rmSync(join(state, name), { force: true });
  const lookers = new Map();      // a look asked of a page itself → who's waiting for it

  async function openWindow() {
    lastUsed = Date.now();
    if (windowBrowser?.alive) { (await windowBrowser.page(address))?.front(); return "window"; }
    const path = findBrowser();
    if (!path) {
      // No browser lamp can look into: the person's own opens the page, and looks are the page's own words.
      const opener = process.platform === "darwin" ? "open" : process.platform === "win32" ? "start" : "xdg-open";
      spawn(opener, [address], { stdio: "ignore", shell: process.platform === "win32", detached: true }).unref();
      return "browser";
    }
    const browser = await launch({ path, url: address, profile: join(state, "browser"), window: true });
    windowBrowser = browser;
    browser.onGone(() => { if (windowBrowser === browser) windowBrowser = null; });
    // The window is what's looked at from now on: a copy running the same game beside it would only slow it.
    copyBrowser?.close();
    return "window";
  }

  /** The page lamp looks at and uses: the person's window when it's open, else the copy. Null with no browser to drive. */
  async function watched() {
    lastUsed = Date.now();
    if (windowBrowser?.alive) {
      const page = await windowBrowser.page(address);
      if (page) return { page, where: "window", fresh: false };
    }
    const fresh = !copyBrowser?.alive;
    if (fresh) {
      const path = findBrowser();
      if (!path) return null;
      const browser = await launch({ path, url: address, profile: join(state, "browser-copy"), window: false });
      copyBrowser = browser;
      browser.onGone(() => { if (copyBrowser === browser) copyBrowser = null; });
    }
    // The copy runs the page for as long as it's looked at, and a while after.
    clearTimeout(copyTimer);
    copyTimer = setTimeout(() => copyBrowser?.close(), 10 * 60_000);
    copyTimer.unref();
    const page = await copyBrowser.page(address);
    return page ? { page, where: "copy", fresh } : null;
  }

  /** What the page shows now: how the changes since the last look went, a picture, the screen as text, and the log. */
  async function look({ wait = 20, reopen = false } = {}) {
    checkAll();
    let target = null, problem = null;
    try { target = await watched(); } catch (error) { problem = error.message; }
    // Which tab that is, which lasts through the page opening again: only its page is waited for.
    let tab = null;
    for (let tries = 0; target && !tab && tries < 40; tries++) {
      tab = await target.page.evaluate("window.__lampTab || null", { timeout: 1000 });
      if (!tab) await sleep(100);
    }
    let unfinished = await waitUntilSettled(Math.max(0, wait) * 1000, tab);
    if (reopen) {
      // The page opens again from its beginning, a game with its saves kept: what a person opening it sees. A copy
      // only just started is opened again too, since a game puts back the place it was last left in.
      const open = [...pages.values()].filter((page) => !tab || page.tab === tab);
      for (const page of open) { reopening.set(page.tab, Date.now() + 30_000); page.calm = false; tell(page, "reload", "fresh"); }
      if (open.length) unfinished = await waitUntilSettled(Math.max(0, wait) * 1000, tab);
    }
    // A page that has only just opened is still putting its loading screen away.
    const mine = [...pages.values()].filter((page) => !tab || page.tab === tab);
    const opened = Math.max(0, ...mine.map((page) => page.readyAt ?? 0));
    if (Date.now() - opened < 1000) await sleep(1000 - (Date.now() - opened));
    // A page that isn't on Lamp's runtime can't say when what it loads after opening is in: the first look at it
    // waits for its screen to stop changing, for a while. A screen that's the same twice running has stopped; one
    // where only numbers change may be a counter of what's loading or a game's own (its frame rate, a clock), so it's
    // given a few seconds of that before it's taken as it is.
    const plain = target && !unfinished ? mine.find((page) => !page.runtime && !page.calm) : null;
    if (plain) {
      const words = async () => String((await target.page.evaluate("window.__lampLook ? window.__lampLook().screen : ''")) ?? "");
      const shape = (text) => text.replace(/[\d.,:%]+/g, "#");
      const until = Date.now() + Math.min(12_000, Math.max(0, wait) * 1000);
      let before = await words(), sameShapeSince = Date.now();
      while (Date.now() < until) {
        await sleep(700);
        const now = await words();
        if (now === before) break;
        if (shape(now) !== shape(before)) sameShapeSince = Date.now();
        else if (Date.now() - sameShapeSince > 5000) break;
        before = now;
      }
      plain.calm = true;
    }
    let seen = null, picture = null, where = target?.where ?? null;
    if (target) {
      // Two frames on, so what's pictured has the change drawn, and long enough for what the page just logged to come.
      await Promise.all([sleep(300), target.page.evaluate("new Promise(done => { setTimeout(done, 400); requestAnimationFrame(() => requestAnimationFrame(done)); })", { timeout: 1500 })]);
      seen = await target.page.evaluate("window.__lampLook ? window.__lampLook() : null");
      try {
        // Each look's picture is a file of its own, so one already read is never taken for the next; a few are kept.
        const bytes = await target.page.picture(seen ?? {});
        picture = join(state, `look-${++pictures}.png`);
        writeFileSync(picture, bytes);
        rmSync(join(state, `look-${pictures - 40}.png`), { force: true });
      } catch (error) { problem = `No picture: ${error.message}.`; }
    } else if (pages.size) {
      // Any open page says what's on it; there's no picture without a browser lamp can look into.
      const ask = randomBytes(4).toString("hex"), page = [...pages.values()].pop();
      seen = await new Promise((resolve) => {
        lookers.set(ask, resolve);
        setTimeout(() => { lookers.delete(ask); resolve(null); }, 3000);
        tell(page, "look", ask);
      });
      where = "page";
      problem ??= "No picture: lamp found no browser it can look into (Chrome, Edge, Brave or Chromium).";
    } else {
      problem ??= "No page is open, and lamp found no browser it can open one in (Chrome, Edge, Brave or Chromium). Open the address in a browser and look again.";
    }
    // How each change since the last look went in the page looked at, or in any page when that one never said. A
    // change a look said was held is said again once it has gone in.
    const since = changes.map((change) => {
      const answer = change.said.get(seen?.tab ?? tab) ?? [...change.said.values()][0];
      const state = answer?.state ?? null;
      if (change.gen <= lastLookGen && !(change.shown === "held" && state !== "held")) return null;
      const wasHeld = change.shown === "held";
      change.shown = state;
      if (answer) {
        const means = state === "held" && answer.pause ? HELD_FOR_A_PAUSE : OUTCOMES[state][1];
        return { files: named(change), outcome: OUTCOMES[state][0], means: wasHeld ? `${means}; it was held, and has gone in now` : means, why: answer.why };
      }
      return pages.size ? { files: named(change), outcome: "unanswered", means: "the page hasn't said how it went", why: "" }
        : { files: named(change), outcome: "opened", means: "no page was open; it's in the one opened now", why: "" };
    }).filter(Boolean);
    const fresh = log.filter((line) => line.n > lastLookLine);
    // An error said over and over is said once, with how many times.
    const counts = new Map();
    for (const line of fresh.filter(isError)) counts.set(line.text, (counts.get(line.text) ?? 0) + 1);
    const errors = [...counts].map(([text, times]) => (times > 1 ? `${text} (${times} times)` : text));
    lastLookGen = gen;
    lastLookLine = logCount;
    return {
      where, opened: !!target?.fresh, address, picture, title: seen?.title ?? null, width: seen?.width ?? null, height: seen?.height ?? null,
      screen: seen?.screen ?? null, game: layout.game, unfinished, changes: since, errors: errors.slice(-20),
      // What the page logged since the last look: the end of it when there's a lot.
      log: collapsed(fresh).slice(-25), logLines: fresh.length, logFile, problem,
    };
  }

  /** Things done in the page as a person would, one after another with nothing between them, then a look. */
  async function use(asked) {
    const moves = Array.isArray(asked?.moves) ? asked.moves : [asked];
    const target = await watched();
    if (!target) throw new Problem("lamp found no browser it can use the page in (Chrome, Edge, Brave or Chromium)");
    await target.page.focus();
    const did = [];
    for (const move of moves) {
      did.push(await act(target.page, move));
      // The game is the person's again: nothing more is pressed in it.
      if (takenOver) { if (did.length < moves.length) did.push(`Left the other ${moves.length - did.length} undone.`); break; }
    }
    return { did: did.join("\n"), ...(await look({ wait: 5 })) };
  }

  async function act(page, action) {
    let did;
    const number = (value, what) => { const n = Number(value); if (!Number.isFinite(n)) throw new Problem(what); return n; };
    if (action.kind === "key") {
      const seconds = Math.min(Math.max(Number(action.seconds) || 0, 0), 10);
      for (const one of String(action.key).split("+")) keyNamed(one);
      await page.key(action.key, seconds);
      did = seconds ? `Held ${action.key} for ${seconds} s.` : `Pressed ${action.key}.`;
    } else if (action.kind === "stick" || action.kind === "button") {
      // Lamp's own controller in the game (lamp-game.js, "Lamp's hands on the controller"): the first player's, held
      // in place of the person's own until the hold ends or they play.
      const buttons = await page.evaluate("import(new URL('lamp-game.js', document.baseURI).href).then(m => window.__lampDrive ? m.BUTTON : null, () => null)");
      if (!buttons) throw new Problem("this page has no controller of Lamp's to hold (it isn't a game on Lamp's runtime): use key");
      const pad = { lx: 0, ly: 0, rx: 0, ry: 0, lt: 0, rt: 0, down: 0 };
      const held = String(action.kind === "button" ? action.buttons ?? "" : action.buttons ?? "").toLowerCase().split("+").filter(Boolean);
      for (const one of held) {
        if (one === "lt" || one === "rt") pad[one] = 1;
        else if (buttons[one.toUpperCase()]) pad.down |= buttons[one.toUpperCase()];
        else throw new Problem(`${one} isn't a button: ${Object.keys(buttons).map((name) => name.toLowerCase()).join(", ")}, lt, rt`);
      }
      let words;
      if (action.kind === "stick") {
        const side = String(action.side ?? "").toLowerCase();
        const x = number(action.x, "stick takes left or right, then x and y from -1 to 1 (right and up are 1): lamp use stick left 0 1 2");
        const y = number(action.y, "stick takes left or right, then x and y from -1 to 1 (right and up are 1): lamp use stick left 0 1 2");
        if ((side !== "left" && side !== "right") || Math.abs(x) > 1 || Math.abs(y) > 1) throw new Problem("stick takes left or right, then x and y from -1 to 1 (right and up are 1): lamp use stick left 0 1 2");
        pad[side === "left" ? "lx" : "rx"] = x;
        pad[side === "left" ? "ly" : "ry"] = y;
        words = `the ${side} stick at ${x}, ${y}${held.length ? ` with ${held.join(" and ").toUpperCase()}` : ""}`;
      } else {
        if (!held.length) throw new Problem("button takes a button's name: lamp use button a");
        words = held.join(" and ").toUpperCase();
      }
      const seconds = Math.min(Math.max(Number(action.seconds) || (action.kind === "stick" ? 1 : 0.15), 0.05), 10);
      const batch = randomBytes(4).toString("hex"), name = `${batch}-1`, quoted = JSON.stringify;
      takenOver = null;
      await page.evaluate(`(() => { window.__lampOwn && window.__lampOwn(${seconds + 1}, ${quoted(batch)}); return window.__lampDrive(${quoted({ ...pad, seconds })}, ${quoted(name)}, ${quoted(batch)}); })()`);
      const until = Date.now() + seconds * 1000;
      while (Date.now() < until && !takenOver) await sleep(40);
      await page.evaluate(`(() => { window.__lampDrive && window.__lampDrive(null, ${quoted(name)}); window.__lampOwn && window.__lampOwn(null, ${quoted(batch)}); })()`);
      did = takenOver ? `Let go of ${words}: the person took the controller back (${takenOver}). The game is theirs; don't take it again unless they ask.`
        : `Held ${words} for ${seconds} s.`;
    } else if (action.kind === "drag") {
      const usage = "drag takes where it starts and where it ends: lamp use drag 400 300 700 300";
      const [x, y, toX, toY] = [action.x, action.y, action.toX, action.toY].map((value) => number(value, usage));
      await page.drag(x, y, toX, toY);
      did = `Dragged from ${x},${y} to ${toX},${toY}.`;
    } else if (action.kind === "scroll") {
      const points = number(action.points, "scroll takes how far, down being positive: lamp use scroll 600");
      const size = (await page.evaluate("({ w: innerWidth, h: innerHeight })")) ?? { w: 800, h: 600 };
      await page.scroll(Number.isFinite(Number(action.x)) ? Number(action.x) : size.w / 2, Number.isFinite(Number(action.y)) ? Number(action.y) : size.h / 2, points);
      await sleep(250);
      did = `Scrolled ${points > 0 ? "down" : "up"} ${Math.abs(points)}.`;
    } else if (action.kind === "click") {
      const x = Number(action.x), y = Number(action.y);
      if (!Number.isFinite(x) || !Number.isFinite(y)) throw new Problem("click takes a point: lamp use click 640 400");
      const at = await page.evaluate(`window.__lampAt ? window.__lampAt(${x}, ${y}) : null`);
      await page.click(x, y);
      did = `Clicked ${x},${y}${at ? `: ${at}` : ""}.`;
    } else if (action.kind === "type") {
      await page.type(String(action.text ?? ""));
      did = `Typed "${action.text}".`;
    } else if (action.kind === "wait") {
      const asked = Math.max(Number(action.seconds) || 1, 0), seconds = Math.min(asked, 30);
      await sleep(seconds * 1000);
      did = `Waited ${seconds} s${asked > seconds ? " (the most one wait takes: wait again for longer)" : ""}.`;
    } else {
      throw new Problem("use takes key, click, type, drag, scroll, stick, button or wait");
    }
    return did;
  }

  // One look or use at a time: two at once would each start a copy of the page, and press keys over each other.
  let turns = Promise.resolve();
  const inTurn = (work) => {
    const mine = turns.then(work, work);
    turns = mine.catch(() => {});
    return mine;
  };

  // MARK: The server

  // Whose requests are answered: this computer's own name for itself, and with `lan` its names on the network. A page
  // elsewhere that points a name of its own at this computer is refused.
  const hosts = new Set(["localhost", "127.0.0.1"]);
  const lanAddresses = [];
  if (lan) {
    for (const list of Object.values(networkInterfaces())) {
      for (const one of list ?? []) if (one.family === "IPv4" && !one.internal) { hosts.add(one.address); lanAddresses.push(one.address); }
    }
    const name = hostname().toLowerCase();
    hosts.add(name);
    hosts.add(name.endsWith(".local") ? name : `${name}.local`);
  }

  async function body(request) {
    const chunks = [];
    let size = 0;
    for await (const chunk of request) { chunks.push(chunk); size += chunk.length; if (size > 4_000_000) return null; }
    try { return JSON.parse(Buffer.concat(chunks).toString("utf8")); } catch { return null; }
  }

  const server = createServer((request, response) => {
    // Nothing a request holds ends lamp: what can't be answered is refused.
    answer(request, response).catch(() => { try { if (!response.headersSent) response.writeHead(400); response.end(); } catch {} });
  });
  async function answer(request, response) {
    const url = new URL(request.url, "http://localhost");
    const headers = { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff" };
    const send = (status, type, content) => {
      response.writeHead(status, { "Content-Type": type, ...headers });
      response.end(request.method === "HEAD" ? undefined : content);
    };
    const json = (status, value) => send(status, TYPES[".json"], JSON.stringify(value));
    const host = String(request.headers.host || "").replace(/:\d+$/, "").toLowerCase();
    if (!hosts.has(host)) return send(403, "text/plain", "Not this page's server");
    // Nothing is changed here by a page of another site.
    if (request.method !== "GET" && request.method !== "HEAD" && request.headers.origin && request.headers.origin !== `http://${request.headers.host}`) {
      return send(403, "text/plain", "Not this page's server");
    }

    // lamp's own commands: they hold the token this server wrote for them.
    if (url.pathname.startsWith("/__lamp/cli/")) {
      if (request.headers["x-lamp-token"] !== token) return json(403, { problem: "that isn't lamp's own command" });
      const what = url.pathname.slice("/__lamp/cli/".length);
      try {
        if (what === "hello") return json(200, { folder, url: address, pid: process.pid, run, own: idle > 0 && !windowBrowser?.alive });
        if (request.method !== "POST") return json(405, { problem: "not a thing to ask that way" });
        const asked = (await body(request)) ?? {};
        if (what === "look") return json(200, await inTurn(() => look(asked)));
        if (what === "use") return json(200, await inTurn(() => use(asked)));
        if (what === "open") return json(200, { opened: await openWindow(), url: address });
        if (what === "reload") { for (const page of pages.values()) tell(page, "reload", asked.fresh ? "fresh" : "now"); return json(200, { pages: pages.size }); }
        if (what === "stop") { json(200, { stopped: true }); setTimeout(() => close().then(() => process.exit(0)), 50); return; }
        return json(404, { problem: `lamp dev doesn't know "${what}"` });
      } catch (error) {
        return json(error instanceof Problem ? 400 : 500, { problem: error.message });
      }
    }

    if (url.pathname === "/__lamp/page.js") return send(200, TYPES[".js"], `const LAMP = ${JSON.stringify({ gen, run })};\n${PAGE_SCRIPT}`);
    if (url.pathname === "/__lamp/events") {
      const id = url.searchParams.get("page") || randomBytes(4).toString("hex"), tab = url.searchParams.get("tab") || id;
      // The last change this page has: what its files were served at, or what it last heard when the line broke.
      const since = Math.max(Number(url.searchParams.get("since")) || 0, Number(request.headers["last-event-id"]) || 0);
      response.writeHead(200, { "Content-Type": "text/event-stream", "Cache-Control": "no-store", Connection: "keep-alive" });
      const page = { response, tab, at: Math.min(since, gen), ready: false, since: Date.now(), told: Date.now(), rerunning: 0 };
      pages.set(id, page);
      reopening.delete(tab);
      for (const message of early.get(id) ?? []) said(message);
      early.delete(id);
      tell(page, "hello", run);
      // What was saved while it was opening, as one change.
      const missed = changes.filter((change) => change.gen > since);
      if (missed.length && missed[0].gen === since + 1) {
        const removed = new Set(), changed = new Set();
        for (const change of missed) {
          for (const path of change.changed) { changed.add(path); removed.delete(path); }
          for (const path of change.removed) { removed.add(path); changed.delete(path); }
        }
        tell(page, "change", JSON.stringify({ gen, changed: [...changed], removed: [...removed], now: false, pill: true }), gen);
      } else if (missed.length) {
        // More was saved than is remembered: the page opens again from the files as they are.
        tell(page, "reload", "now");
      }
      const beat = setInterval(() => response.write(": still here\n\n"), 20_000);
      request.on("close", () => { clearInterval(beat); if (pages.get(id) === page) pages.delete(id); });
      return;
    }
    if (request.method === "POST" && url.pathname.startsWith("/__lamp/")) {
      const message = await body(request);
      if (message && url.pathname === "/__lamp/said") said(message);
      else if (message && url.pathname === "/__lamp/log" && Array.isArray(message.lines)) logged(message.lines.slice(0, 500));
      else if (message && url.pathname === "/__lamp/looked") { lookers.get(message.ask)?.(message.seen ?? null); lookers.delete(message.ask); }
      return send(204, "text/plain", "");
    }
    if (request.method !== "GET" && request.method !== "HEAD") return send(405, "text/plain", "Method not allowed");

    let path;
    try { path = decodeURIComponent(url.pathname); } catch { return send(400, "text/plain", "Bad path"); }
    if (path.endsWith("/")) path += "index.html";
    let file = resolve(join(root, path));
    if (file !== root && !file.startsWith(root + sep)) return send(403, "text/plain", "Outside the page");
    const name = relative(root, file).split(sep).join("/");
    // Hidden files (.git, .lamp, .env) are no part of the page.
    if (name.split("/").some((part) => part.startsWith("."))) return send(404, "text/plain", "Not found");
    let info;
    try {
      info = await stat(file);
      const real = await realpath(file);
      if (real !== rootReal && !real.startsWith(rootReal + sep)) return send(404, "text/plain", "Not found");
    } catch {
      // A file the page asks for and the folder doesn't have is an error the page itself often can't say: a module
      // that imports one never runs, with nothing in the page's log.
      const missing = () => {
        if (!/(^|\/)favicon\.ico$|\.map$/.test(name)) logged([{ level: "error", text: `${name} isn't in the folder, and the page asked for it.` }]);
        return send(404, "text/plain", "Not found");
      };
      if (!layout.game) return missing();
      if (name === DEVICE_FILE) return send(200, TYPES[".js"], ANY_BROWSER);
      if (name === BUILD_FILE) return send(200, TYPES[".js"], `export default "${buildName()}";\n`);
      if (name === "lamp.js") return send(200, TYPES[".js"], LAMP_JS);
      const own = lampsCopy(name);
      try { info = own ? await stat(own) : null; } catch { info = null; }
      if (!info) return missing();
      file = own;
    }
    if (info.isDirectory()) { response.writeHead(302, { Location: url.pathname + "/" + url.search, ...headers }); return response.end(); }
    const type = TYPES[extname(file).toLowerCase()] ?? "application/octet-stream";
    if (type.startsWith("text/html")) {
      // lamp's script first in the page, before any script of its own.
      let html;
      try { html = await readFile(file, "utf8"); } catch { return send(404, "text/plain", "Not found"); }
      const tag = '<script src="/__lamp/page.js"></script>';
      return send(200, type, /<head[^>]*>/i.test(html) ? html.replace(/<head[^>]*>/i, (found) => found + tag) : tag + html);
    }
    // The rest is sent as it's read, a part of it when a part is asked for (sound and video are).
    const range = /^bytes=(\d*)-(\d*)$/.exec(request.headers.range || "");
    let start = 0, end = info.size - 1, status = 200;
    if (range && info.size && (range[1] || range[2])) {
      start = range[1] ? Number(range[1]) : Math.max(0, info.size - Number(range[2]));
      end = range[1] && range[2] ? Math.min(Number(range[2]), info.size - 1) : info.size - 1;
      if (start > end || start >= info.size) { response.writeHead(416, { "Content-Range": `bytes */${info.size}`, ...headers }); return response.end(); }
      status = 206;
    }
    response.writeHead(status, {
      "Content-Type": type, "Content-Length": info.size ? end - start + 1 : 0, "Accept-Ranges": "bytes", ...headers,
      ...(status === 206 ? { "Content-Range": `bytes ${start}-${end}/${info.size}` } : {}),
    });
    if (request.method === "HEAD" || !info.size) return response.end();
    const stream = createReadStream(file, { start, end });
    stream.on("error", () => response.destroy());
    stream.pipe(response);
  }

  // The port: the one asked for and no other, else the folder's last when it's free, else the folder's own and the
  // ones after it.
  const portFile = join(state, "port");
  const remembered = Number((() => { try { return readFileSync(portFile, "utf8"); } catch { return ""; } })()) || 0;
  const first = firstPortOf(folder);
  const tries = asked ? [asked] : [...new Set([remembered || first, ...Array.from({ length: 30 }, (_, i) => first + i)])];
  let port = 0;
  for (const candidate of tries) {
    try {
      await new Promise((resolve, reject) => {
        server.once("error", reject);
        server.listen(candidate, lan ? "0.0.0.0" : "127.0.0.1", () => { server.off("error", reject); resolve(); });
      });
      port = candidate;
      break;
    } catch (error) {
      if (error.code !== "EADDRINUSE") throw new Problem(error.message);
    }
  }
  if (!port) throw new Problem(asked ? `port ${asked} is in use; leave --port out and lamp finds one` : `no port from ${first} to ${first + 29} is free`);
  address = `http://localhost:${port}/`;
  writeFileSync(portFile, String(port));
  writeFileSync(serverFileOf(folder), JSON.stringify({ port, pid: process.pid, token, folder }), { mode: 0o600 });

  let closed = false;
  async function close() {
    if (closed) return;
    closed = true;
    clearInterval(idleTimer);
    clearTimeout(copyTimer);
    clearTimeout(timer);
    watcher.close();
    windowBrowser?.close();
    copyBrowser?.close();
    for (const page of pages.values()) page.response.end();
    try { if (JSON.parse(readFileSync(serverFileOf(folder), "utf8")).pid === process.pid) rmSync(serverFileOf(folder)); } catch {}
    server.closeAllConnections?.();
    await new Promise((done) => server.close(done));
  }
  // As lamp goes, however it goes, the browsers it started go with it.
  process.on("exit", () => { windowBrowser?.kill(); copyBrowser?.kill(); });

  // A server `lamp look` started for itself ends once nothing has used it for a while and no window is open.
  const idleTimer = setInterval(() => {
    if (!idle || windowBrowser?.alive || Date.now() - lastUsed < idle * 60_000) return;
    if (pages.size > (copyBrowser?.alive ? 1 : 0)) return;
    close().then(() => process.exit(0));
  }, 30_000);
  idleTimer.unref();

  if (!quiet) {
    console.log(`lamp dev  ${layout.game ? "a game" : "a page"} in ${root}`);
    console.log(`  Open  ${address}`);
    for (const one of lanAddresses) console.log(`        http://${one}:${port}/  (other devices on this network)`);
    console.log(`  Look  lamp look   how a change went, a picture, the screen as text and the log`);
    console.log(`  Log   ${logFile}`);
    console.log(`  Each save goes into the open page.${layout.game ? " A game keeps the player's place." : ""}\n`);
  }
  return { url: address, port, token, folder, state, logFile, look: (options) => inTurn(() => look(options)), use: (action) => inTurn(() => use(action)), openWindow, close };
}
