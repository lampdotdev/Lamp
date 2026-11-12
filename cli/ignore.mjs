// `.lampignore`: what an app's folder keeps out of what it shares (its page on lamp.dev, and the app's file that goes
// with its link): data only its maker's computer needs, too big to share, say (a 600 MB parts library a page fetches
// from elsewhere when it isn't there). The patterns are gitignore's simpler half: one a line, `#` for a note, `*`, `?` and
// `**`, a trailing `/` for a folder, a leading `/` (or any `/` inside) for a path from the folder's top, and otherwise a
// name matched at any depth. Nothing starting with `!`: what's left out stays out.

import { readFileSync } from "node:fs";
import { join, relative, sep } from "node:path";

export const IGNORE_FILE = ".lampignore";

/** A pattern as a regular expression over a path from the folder's top ("ldraw/parts/3001.dat"). */
function compile(line) {
  let pattern = line.trim();
  const folder = pattern.endsWith("/");
  if (folder) pattern = pattern.replace(/\/+$/, "");
  const anchored = pattern.startsWith("/") || pattern.includes("/");
  pattern = pattern.replace(/^\/+/, "");
  if (!pattern) return null;
  let source = "";
  for (let i = 0; i < pattern.length; i++) {
    const c = pattern[i];
    if (c === "*" && pattern[i + 1] === "*") {
      // `**/` matches any folders, none included; a lone `**` anything at all.
      if (pattern[i + 2] === "/") { source += "(?:.*/)?"; i += 2; } else { source += ".*"; i += 1; }
    } else if (c === "*") source += "[^/]*";
    else if (c === "?") source += "[^/]";
    else source += c.replace(/[.+^${}()|[\]\\]/g, "\\$&");
  }
  // What it names is left out with everything under it; a folder pattern names folders only, so it must have more after it.
  return new RegExp(`^${anchored ? "" : "(?:.*/)?"}${source}${folder ? "/" : "(?:/|$)"}`);
}

/**
 * Whether a path from the folder's top ("ldraw/parts/3001.dat"), a folder's when `folder` is true, is one its
 * `.lampignore` leaves out; never, with none.
 */
export function ignoredIn(folder) {
  let lines = [];
  try { lines = readFileSync(join(folder, IGNORE_FILE), "utf8").split(/\r?\n/); } catch {}
  const tests = lines.map((line) => line.trim()).filter((line) => line && !line.startsWith("#") && !line.startsWith("!")).map(compile).filter(Boolean);
  if (!tests.length) return () => false;
  // A folder's own path is asked about with a trailing slash too, so a folder-only pattern names it (and never a file).
  return (path, folder = false) => tests.some((test) => test.test(path) || (folder && test.test(`${path}/`)));
}

/**
 * Whether a path from a page's top is left out by the page's `.lampignore` or by its app's (`app`, the folder above it
 * when the page is in Web/, whose patterns count from its own top).
 */
export function ignoredFor(root, app = root) {
  const own = ignoredIn(root);
  if (app === root) return own;
  const outer = ignoredIn(app), under = relative(app, root).split(sep).join("/");
  return (path, folder = false) => own(path, folder) || outer(under ? `${under}/${path}` : path, folder);
}
