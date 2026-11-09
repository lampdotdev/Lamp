// A browser lamp opens and can see into: the window the person uses, or a copy with no window that's only looked at.
// It's a Chromium-family browser already on the computer, started with files of its own (never the person's own
// browser profile) and spoken to over a pipe only this process holds, so nothing else on the computer can drive it.

import { spawn, spawnSync } from "node:child_process";
import { existsSync, mkdirSync } from "node:fs";
import { homedir } from "node:os";
import { join } from "node:path";
import { Problem } from "./state.mjs";

const MAC = ["Google Chrome", "Chromium", "Microsoft Edge", "Brave Browser", "Google Chrome Canary"];
const LINUX = ["google-chrome", "google-chrome-stable", "chromium", "chromium-browser", "microsoft-edge", "brave-browser"];
const WINDOWS = ["Google\\Chrome\\Application\\chrome.exe", "Microsoft\\Edge\\Application\\msedge.exe", "BraveSoftware\\Brave-Browser\\Application\\brave.exe"];

/** A browser lamp can drive, or null: LAMP_BROWSER names one, else the first of the usual ones found. */
export function findBrowser() {
  const named = process.env.LAMP_BROWSER;
  if (named !== undefined) return named && existsSync(named) ? named : null;
  if (process.platform === "darwin") {
    for (const apps of ["/Applications", join(homedir(), "Applications")]) {
      for (const name of MAC) {
        const path = join(apps, `${name}.app`, "Contents", "MacOS", name);
        if (existsSync(path)) return path;
      }
    }
    return null;
  }
  if (process.platform === "win32") {
    for (const base of [process.env.PROGRAMFILES, process.env["PROGRAMFILES(X86)"], process.env.LOCALAPPDATA]) {
      for (const name of WINDOWS) if (base && existsSync(join(base, name))) return join(base, name);
    }
    return null;
  }
  for (const name of LINUX) {
    const found = spawnSync("which", [name], { encoding: "utf8" });
    if (found.status === 0 && found.stdout.trim()) return found.stdout.trim();
  }
  return null;
}

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

// The keys a person names, as the browser is told them: the key, its place on the keyboard, its number, and what it
// types if anything.
const NAMED = {
  enter: ["Enter", "Enter", 13, "\r"], return: ["Enter", "Enter", 13, "\r"], escape: ["Escape", "Escape", 27], esc: ["Escape", "Escape", 27],
  space: [" ", "Space", 32, " "], tab: ["Tab", "Tab", 9], backspace: ["Backspace", "Backspace", 8], delete: ["Delete", "Delete", 46],
  up: ["ArrowUp", "ArrowUp", 38], down: ["ArrowDown", "ArrowDown", 40], left: ["ArrowLeft", "ArrowLeft", 37], right: ["ArrowRight", "ArrowRight", 39],
  shift: ["Shift", "ShiftLeft", 16], control: ["Control", "ControlLeft", 17], ctrl: ["Control", "ControlLeft", 17],
  alt: ["Alt", "AltLeft", 18], option: ["Alt", "AltLeft", 18], command: ["Meta", "MetaLeft", 91], meta: ["Meta", "MetaLeft", 91],
};

export function keyNamed(name) {
  const lower = String(name).toLowerCase();
  const named = NAMED[lower] ?? NAMED[lower.replace(/^arrow/, "")];
  if (named) return { key: named[0], code: named[1], number: named[2], text: named[3] };
  if (/^[a-z]$/.test(lower)) return { key: lower, code: `Key${lower.toUpperCase()}`, number: lower.toUpperCase().charCodeAt(0), text: lower };
  if (/^[0-9]$/.test(lower)) return { key: lower, code: `Digit${lower}`, number: 48 + Number(lower), text: lower };
  const f = /^f([1-9]|1[0-2])$/.exec(lower);
  if (f) return { key: `F${f[1]}`, code: `F${f[1]}`, number: 111 + Number(f[1]) };
  throw new Problem(`lamp doesn't know the key "${name}": a letter, a digit, F1 to F12, or one of ${Object.keys(NAMED).join(", ")}`);
}

/** One page of the browser, as lamp looks at it and uses it. */
class Page {
  constructor(browser, target, session) { this.browser = browser; this.target = target; this.session = session; }

  send(method, params, timeout) { return this.browser.send(method, params, this.session, timeout); }

  /** What an expression gives in the page, as JSON; null when the page can't answer in time. */
  async evaluate(expression, { timeout = 5000 } = {}) {
    const answer = await this.send("Runtime.evaluate", { expression, returnByValue: true, awaitPromise: true }, timeout).catch(() => null);
    return answer?.result?.value ?? null;
  }

  /** A picture of the page as it is, one pixel of it for each point of the page, so a point of the picture is a point to click. */
  async picture({ width, height, dpr = 1 }) {
    const clip = width && height ? { x: 0, y: 0, width, height, scale: 1 / dpr } : undefined;
    const shot = await this.send("Page.captureScreenshot", { format: "png", ...(clip ? { clip } : {}) }, 8000);
    return Buffer.from(shot.data, "base64");
  }

  /** The page answers as the page in front, with the keyboard its own, however it's shown. */
  async focus() { await this.send("Emulation.setFocusEmulationEnabled", { enabled: true }).catch(() => {}); }

  /** Holds a key, or several at once (`w+a`), for some seconds. */
  async key(names, seconds = 0) {
    const keys = String(names).split("+").filter(Boolean).map(keyNamed).map(({ key, code, number, text }) => ({ text, common: { key, code, windowsVirtualKeyCode: number, nativeVirtualKeyCode: number } }));
    for (const { text, common } of keys) {
      await this.send("Input.dispatchKeyEvent", { type: text ? "keyDown" : "rawKeyDown", ...common, ...(text ? { text, unmodifiedText: text } : {}) });
    }
    await sleep(Math.max(40, seconds * 1000));
    for (const { common } of keys.reverse()) await this.send("Input.dispatchKeyEvent", { type: "keyUp", ...common });
  }

  async click(x, y) {
    await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    await this.send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", buttons: 1, clickCount: 1 });
    await this.send("Input.dispatchMouseEvent", { type: "mouseReleased", x, y, button: "left", buttons: 0, clickCount: 1 });
  }

  async type(text) { await this.send("Input.insertText", { text }); }

  /** Presses at one point, moves to another and lets go, as a hand would: in steps. */
  async drag(x, y, toX, toY) {
    await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x, y });
    await this.send("Input.dispatchMouseEvent", { type: "mousePressed", x, y, button: "left", buttons: 1, clickCount: 1 });
    for (let step = 1; step <= 12; step++) {
      await this.send("Input.dispatchMouseEvent", { type: "mouseMoved", x: x + ((toX - x) * step) / 12, y: y + ((toY - y) * step) / 12, button: "left", buttons: 1 });
      await sleep(16);
    }
    await this.send("Input.dispatchMouseEvent", { type: "mouseReleased", x: toX, y: toY, button: "left", buttons: 0, clickCount: 1 });
  }

  async scroll(x, y, points) { await this.send("Input.dispatchMouseEvent", { type: "mouseWheel", x, y, deltaX: 0, deltaY: points }); }

  async front() { await this.send("Page.bringToFront").catch(() => {}); }

  /** Shows the page at another size, as a window of that size would, or at its own again with none given. */
  async size(width, height) {
    if (width && height) await this.send("Emulation.setDeviceMetricsOverride", { width, height, deviceScaleFactor: 0, mobile: false });
    else await this.send("Emulation.clearDeviceMetricsOverride").catch(() => {});
  }
}

class Browser {
  constructor(child) {
    this.child = child;
    this.alive = true;
    this.count = 0;
    this.waiting = new Map();
    this.pages = new Map();     // target id → Page
    this.gone = [];
    let held = "";
    // The pipe's messages are JSON, each ended by a zero byte.
    child.stdio[4].setEncoding("utf8");
    child.stdio[4].on("data", (chunk) => {
      held += chunk;
      let end;
      while ((end = held.indexOf("\0")) >= 0) {
        const text = held.slice(0, end);
        held = held.slice(end + 1);
        let message;
        try { message = JSON.parse(text); } catch { continue; }
        this.heard(message);
      }
    });
    child.stdio[3].on("error", () => {});
    child.stdio[4].on("error", () => {});
    child.on("exit", () => this.ended());
    child.on("error", () => this.ended());
  }

  heard(message) {
    if (message.id !== undefined) {
      const waiter = this.waiting.get(message.id);
      if (!waiter) return;
      this.waiting.delete(message.id);
      clearTimeout(waiter.timer);
      if (message.error) waiter.reject(new Error(message.error.message)); else waiter.resolve(message.result);
      return;
    }
    if (message.method === "Target.targetDestroyed" || message.method === "Target.detachedFromTarget") {
      const id = message.params.targetId;
      if (id) this.pages.delete(id);
      // The person closed the window: on a Mac the browser would stay running with none, so it's closed with it.
      if (message.method === "Target.targetDestroyed") this.closeIfEmpty();
    }
  }

  async closeIfEmpty() {
    const targets = await this.send("Target.getTargets").catch(() => null);
    if (targets && !targets.targetInfos.some((target) => target.type === "page")) this.close();
  }

  ended() {
    if (!this.alive) return;
    this.alive = false;
    for (const waiter of this.waiting.values()) { clearTimeout(waiter.timer); waiter.reject(new Error("the browser closed")); }
    this.waiting.clear();
    this.pages.clear();
    for (const told of this.gone) told();
  }

  /** Called once the browser has gone, however it went. */
  onGone(told) { this.gone.push(told); }

  send(method, params = {}, session, timeout = 10_000) {
    if (!this.alive) return Promise.reject(new Error("the browser closed"));
    const id = ++this.count;
    return new Promise((resolve, reject) => {
      const timer = setTimeout(() => { this.waiting.delete(id); reject(new Error(`the browser didn't answer ${method}`)); }, timeout);
      this.waiting.set(id, { resolve, reject, timer });
      this.child.stdio[3].write(JSON.stringify({ id, method, params, ...(session ? { sessionId: session } : {}) }) + "\0");
    });
  }

  /** The page showing what's at this address, or null when the browser has none (the person went elsewhere in it). */
  async page(origin, timeout) {
    if (!this.alive) return null;
    const targets = await this.send("Target.getTargets", {}, undefined, timeout).catch(() => null);
    const target = targets?.targetInfos.find((info) => info.type === "page" && info.url.startsWith(origin));
    if (!target) return null;
    let page = this.pages.get(target.targetId);
    if (!page) {
      const attached = await this.send("Target.attachToTarget", { targetId: target.targetId, flatten: true });
      page = new Page(this, target.targetId, attached.sessionId);
      this.pages.set(target.targetId, page);
    }
    return page;
  }

  close() {
    if (!this.alive) return;
    this.send("Browser.close").catch(() => {});
    setTimeout(() => { try { this.child.kill(); } catch {} }, 1500).unref();
  }

  /** At once, as lamp itself goes. */
  kill() { try { this.child.kill(); } catch {} }
}

/**
 * Starts the browser at an address: `window` a window for the person, else a copy that's never shown. Its files are
 * kept in `profile`, apart from the person's own browser.
 */
export async function launch({ path, url, profile, window, size = [1280, 800] }) {
  mkdirSync(profile, { recursive: true });
  const args = [
    "--remote-debugging-pipe", `--user-data-dir=${profile}`, "--no-first-run", "--no-default-browser-check",
    "--disable-features=Translate,MediaRouter,OptimizationHints", "--disable-sync", "--disable-component-update", "--hide-crash-restore-bubble",
    `--window-size=${size[0]},${size[1]}`,
    // The page goes on running, and takes changes, while it's behind other windows.
    "--disable-backgrounding-occluded-windows", "--disable-renderer-backgrounding", "--disable-background-timer-throttling",
    ...(window ? [`--app=${url}`] : ["--headless=new", "--hide-scrollbars", "--mute-audio", url]),
  ];
  let child;
  try { child = spawn(path, args, { stdio: ["ignore", "ignore", "ignore", "pipe", "pipe"] }); }
  catch (error) { throw new Problem(`${path} didn't start: ${error.message}`); }
  const browser = new Browser(child);
  // Target ids come with what happens to them, so a closed window is noticed.
  await browser.send("Target.setDiscoverTargets", { discover: true }).catch(() => {});
  const origin = new URL(url).origin;
  const until = Date.now() + 15_000;
  while (browser.alive && Date.now() < until) {
    if (await browser.page(origin, 2000)) return browser;
    await sleep(100);
  }
  browser.kill();
  throw new Problem("the browser started but didn't open the page");
}
