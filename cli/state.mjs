// Where a folder's page is, where lamp keeps what it needs for it, and how one lamp command finds the server another
// started for the same folder.

import { createHash } from "node:crypto";
import { existsSync, statSync, readFileSync, readdirSync, realpathSync } from "node:fs";
import { homedir } from "node:os";
import { basename, join, resolve } from "node:path";

/** Something the person or agent can put right, said in plain words and shown without a stack. */
export class Problem extends Error {}

/** The runtime whose presence makes a page a game's (`GamePage.runtimeFile`). */
export const RUNTIME_FILE = "lamp-game.js";

/**
 * How the folder is laid out: an app Lamp made keeps its page in Web/, and any other folder with an index.html is a
 * plain site whose page is the folder itself.
 */
export function layoutOf(given) {
  let folder = resolve(given);
  if (!existsSync(folder) || !statSync(folder).isDirectory()) throw new Problem(`${folder} isn't a folder`);
  folder = realpathSync(folder);
  const root = [join(folder, "Web"), folder].find((candidate) => existsSync(join(candidate, "index.html")));
  if (!root) throw new Problem(`${folder} has no page: no Web/index.html and no index.html`);
  return { folder, root, lamps: root !== folder, game: existsSync(join(root, RUNTIME_FILE)) };
}

/**
 * What Lamp's own record in the folder says it is (`lamp-app.json`, which an app Lamp shared or put on GitHub carries
 * at its top, or a site in `.lamp-wish/`): its kind (`platform`), its name and the wish's other apps (`parts`). Null in
 * a folder without one.
 */
export function manifestOf(folder) {
  for (const at of ["lamp-app.json", join(".lamp-wish", "lamp-app.json")]) {
    try {
      const said = JSON.parse(readFileSync(join(folder, at), "utf8"));
      if (said && typeof said === "object" && !Array.isArray(said)) return said;
    } catch {}
  }
  return null;
}

/** Whether some Swift of the app's own imports RealityKit (`Template.importsRealityKit`), which Lamp builds a scene around. */
function importsRealityKit(folder) {
  let entries;
  try { entries = readdirSync(folder, { withFileTypes: true }); } catch { return false; }
  return entries.some((entry) => entry.isDirectory() ? importsRealityKit(join(folder, entry.name))
    : entry.name.endsWith(".swift") && entry.name !== "LampSupport.swift" && entry.name !== "LampScene.swift"
      && /^\s*(@\w+\s+)?import\s+RealityKit\b/m.test(readFileSync(join(folder, entry.name), "utf8")));
}

// The kinds Lamp makes that lamp doesn't build or run, in the words a person knows them by (`Platform`'s kinds).
const ELSEWHERE = {
  iphone: "an iPhone app", universal: "an app for both the Mac and the iPhone", android: "an Android app",
  "android-tv": "an Android TV app", tv: "a TV app", device: "an app for a device through its integration",
};

/**
 * What the folder is to lamp: a page (as `layoutOf` reads it), or an app Lamp made in Swift for the Mac (its code in
 * Sources/; `missing` lists Lamp's own files it lacks, which a shared file never carries and lamp writes before it
 * builds). A folder in Lamp's format is read by what its `lamp-app.json` says it is: a web app, a game or a screen is
 * its page (a game Lamp made has the Mac app around its page too), a Mac app its code, and a kind lamp doesn't run, or
 * a wish of several apps, is said so rather than taken for another.
 */
export function projectOf(given) {
  const folder = resolve(given);
  if (!existsSync(folder) || !statSync(folder).isDirectory()) throw new Problem(`${folder} isn't a folder`);
  const real = realpathSync(folder);
  const hasPage = [join(real, "Web"), real].some((candidate) => existsSync(join(candidate, "index.html")));
  const owned = ["Package.swift", "build.sh", join("Sources", "LampSupport.swift")];
  const manifest = manifestOf(real);
  if (manifest) {
    const parts = Array.isArray(manifest.parts) ? manifest.parts.length : 0;
    if (parts) throw new Problem(`${real} is a wish of ${parts + 1} apps, and lamp works on one app in a folder: open it in Lamp's app`);
    const kind = typeof manifest.platform === "string" ? manifest.platform : "mac";
    if (ELSEWHERE[kind]) throw new Problem(`${real} is ${ELSEWHERE[kind]}, which lamp doesn't build or run: open it in Lamp's app`);
    if (["web-app", "game", "screen"].includes(kind)) {
      if (!hasPage) throw new Problem(kind === "game" ? `${real} is a game written in C++, which lamp doesn't run: open it in Lamp's app` : `${real} has no page: no Web/index.html and no index.html`);
      return { kind: "page", ...layoutOf(real) };
    }
    if (kind === "mac") {
      if (!existsSync(join(real, "Sources"))) throw new Problem(`${real} is a Mac app with no code: no Sources/`);
      const missing = owned.filter((path) => !existsSync(join(real, path)));
      // Lamp's starting files build an app alone: a widget, a share extension or a 3D scene is built with files of
      // Lamp's that only its app writes (`Template.writeSwiftOwnedFiles`).
      const more = missing.length && (["Widget", "Share"].find((extra) => existsSync(join(real, extra))) ?? (importsRealityKit(join(real, "Sources")) ? "a 3D scene" : null));
      if (more) throw new Problem(`${real} is a Mac app with ${more.includes(" ") ? more : `a ${more === "Widget" ? "widget" : "share extension"}`}, which only Lamp's app builds from a shared file: open it in Lamp's app first`);
      return { kind: "mac", folder: real, missing };
    }
    throw new Problem(`${real} is a kind of app this lamp doesn't know ("${kind}"): a newer Lamp made it`);
  }
  if (hasPage) return { kind: "page", ...layoutOf(real) };
  if (existsSync(join(real, "Package.swift")) && existsSync(join(real, "build.sh")) && existsSync(join(real, "Sources"))) return { kind: "mac", folder: real, missing: [] };
  throw new Problem(`${real} has no page (no Web/index.html and no index.html), and isn't a Mac app Lamp made (no Package.swift with its build.sh, and no lamp-app.json)`);
}

/**
 * Where lamp keeps what it needs for a folder: the browser's own files (so a game's saves last from one run to the
 * next), the picture of the last look, and which server is running. Outside the folder, so nothing of lamp's is
 * published or committed with a plain site.
 */
export function stateOf(folder) {
  const home = process.env.LAMP_DEV_HOME || join(homedir(), ".lamp", "dev");
  const name = basename(folder).replace(/[^\w.-]+/g, "-").slice(0, 40) || "app";
  return join(home, `${name}-${hashOf(folder).slice(0, 8)}`);
}

const hashOf = (folder) => createHash("sha256").update(folder).digest("hex");

/**
 * The port a folder's page is first served on: its own, from its path, so two apps run side by side and each keeps
 * its address (a game's saves belong to the address) from the first run on.
 */
export const firstPortOf = (folder) => 4400 + (parseInt(hashOf(folder).slice(0, 6), 16) % 500);

/**
 * The page's log, with the rest of lamp's state: lamp writes nothing in the app's folder, which may be one Lamp's app
 * is running too, with a log of its own where an app made by Lamp keeps it.
 */
export function logFileOf(layout) {
  return join(stateOf(layout.folder), "log.txt");
}

export const serverFileOf = (folder) => join(stateOf(folder), "server.json");

/** Asks a running server something only lamp's own commands may ask: they hold the token it wrote for them. */
export async function ask(server, path, body, { timeout = 10_000 } = {}) {
  let answer;
  try {
    answer = await fetch(`http://127.0.0.1:${server.port}/__lamp/cli/${path}`, {
      method: body === undefined ? "GET" : "POST",
      headers: { "x-lamp-token": server.token, "content-type": "application/json" },
      body: body === undefined ? undefined : JSON.stringify(body),
      signal: AbortSignal.timeout(timeout),
    });
  } catch (error) {
    throw new Problem(error.name === "TimeoutError" ? "lamp dev didn't answer in time" : "lamp dev isn't running for this folder");
  }
  const said = await answer.json().catch(() => null);
  if (!answer.ok) throw new Problem(said?.problem || `lamp dev answered ${answer.status}`);
  return said;
}

/**
 * The server running for this folder, if one is: what it wrote when it started, checked by asking it. `own` is one a
 * lamp command started for itself that has no window open: a `lamp dev` run by hand takes its place.
 */
export async function running(folder) {
  let server;
  try { server = JSON.parse(readFileSync(serverFileOf(folder), "utf8")); } catch { return null; }
  try {
    const hello = await ask(server, "hello", undefined, { timeout: 1500 });
    return hello.folder === folder ? { ...server, url: hello.url, own: !!hello.own } : null;
  } catch { return null; }
}
