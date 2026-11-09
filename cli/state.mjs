// Where a folder's page is, where lamp keeps what it needs for it, and how one lamp command finds the server another
// started for the same folder.

import { createHash } from "node:crypto";
import { existsSync, statSync, readFileSync, realpathSync } from "node:fs";
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
 * Where lamp keeps what it needs for a folder: the browser's own files (so a game's saves last from one run to the
 * next), the picture of the last look, and which server is running. Outside the folder, so nothing of lamp's is
 * published or committed with a plain site.
 */
export function stateOf(folder) {
  const home = process.env.LAMP_DEV_HOME || join(homedir(), ".lamp", "dev");
  const name = basename(folder).replace(/[^\w.-]+/g, "-").slice(0, 40) || "app";
  return join(home, `${name}-${createHash("sha256").update(folder).digest("hex").slice(0, 8)}`);
}

/**
 * The page's log. In an app Lamp made it's where Lamp keeps it (.lamp/runtime/log.txt), so whatever is told to read
 * it there finds it; a plain site's is kept with the rest of lamp's state.
 */
export function logFileOf(layout) {
  return layout.lamps ? join(layout.folder, ".lamp", "runtime", "log.txt") : join(stateOf(layout.folder), "log.txt");
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

/** The server running for this folder, if one is: what it wrote when it started, checked by asking it. */
export async function running(folder) {
  let server;
  try { server = JSON.parse(readFileSync(serverFileOf(folder), "utf8")); } catch { return null; }
  try {
    const hello = await ask(server, "hello", undefined, { timeout: 1500 });
    return hello.folder === folder ? { ...server, url: hello.url, own: !!hello.own } : null;
  } catch { return null; }
}
