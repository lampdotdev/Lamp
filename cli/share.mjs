// A link to the page on lamp.dev: anyone who opens it plays the page there, and can send its maker an idea. This is
// Lamp's side of the site's API (site/lib/shared-wishes.js, which the limits here are read from), as
// Sources/Lamp/WishLink.swift is in Lamp's app: the link's words and picture, then the page, zipped and sent in parts.
//
// The link's secret, which is what lets it be changed or taken down, is kept with lamp's own state for the folder,
// never in the folder: a folder is committed and published, and the secret is whoever shared it's alone.

import { createHash } from "node:crypto";
import { existsSync, lstatSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { basename, join } from "node:path";
import { deflateRawSync } from "node:zlib";
import { Problem, stateOf } from "./state.mjs";
import { ANY_BROWSER, CONTROLLERS, CONTROLLERS_FILE, DEVICE_FILE, lampJS, LIBRARIES } from "./dev.mjs";
import { LIMITS, FILE_LIMITS, PAGE_LIMITS } from "../site/lib/shared-wishes.js";

/** The site links are made on: lamp.dev, or another given for trying this against a copy of the site. */
export const siteOrigin = () => (process.env.LAMP_SITE || "https://lamp.dev").replace(/\/+$/, "");

const linkFileOf = (folder) => join(stateOf(folder), "link.json");

/** The folder's link, as it was last shared: its address, its secret and the words it went out with. */
export function readLink(folder) {
  try { return JSON.parse(readFileSync(linkFileOf(folder), "utf8")); } catch { return null; }
}
function writeLink(folder, link) {
  mkdirSync(stateOf(folder), { recursive: true });
  writeFileSync(linkFileOf(folder), JSON.stringify(link, null, 2), { mode: 0o600 });
}

// MARK: The page, as a zip

const CRC = Array.from({ length: 256 }, (_, n) => { let c = n; for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1; return c >>> 0; });
function crc32(bytes) {
  let c = 0xffffffff;
  for (let i = 0; i < bytes.length; i++) c = CRC[(c ^ bytes[i]) & 0xff] ^ (c >>> 8);
  return (c ^ 0xffffffff) >>> 0;
}

/** A zip of these files (`[path, bytes]`), each packed where that makes it smaller. */
export function zipOf(files) {
  const parts = [], listing = [];
  let offset = 0;
  for (const [path, bytes] of files) {
    const name = Buffer.from(path, "utf8"), packed = deflateRawSync(bytes), stored = packed.length >= bytes.length;
    const data = stored ? bytes : packed, sum = crc32(bytes);
    const head = Buffer.alloc(30);
    head.writeUInt32LE(0x04034b50, 0);
    head.writeUInt16LE(20, 4);
    head.writeUInt16LE(0x0800, 6);              // the name is UTF-8
    head.writeUInt16LE(stored ? 0 : 8, 8);
    head.writeUInt32LE(sum, 14);
    head.writeUInt32LE(data.length, 18);
    head.writeUInt32LE(bytes.length, 22);
    head.writeUInt16LE(name.length, 26);
    const entry = Buffer.alloc(46);
    entry.writeUInt32LE(0x02014b50, 0);
    entry.writeUInt16LE(20, 4);
    entry.writeUInt16LE(20, 6);
    head.copy(entry, 8, 6, 30);                 // the same flags, method, sum, sizes and name length
    entry.writeUInt32LE(offset, 42);
    parts.push(head, name, data);
    listing.push(entry, name);
    offset += 30 + name.length + data.length;
  }
  const directory = Buffer.concat(listing), end = Buffer.alloc(22);
  end.writeUInt32LE(0x06054b50, 0);
  end.writeUInt16LE(files.length, 8);
  end.writeUInt16LE(files.length, 10);
  end.writeUInt32LE(directory.length, 12);
  end.writeUInt32LE(offset, 16);
  return Buffer.concat([...parts, directory, end]);
}

/**
 * Every file of the page as it's played from the link: what's in its folder (nothing hidden, no link followed, the
 * app's notes left out), and for a game Lamp's own files beside it, as Lamp's app puts them in a copy it publishes
 * (`GamePage.stage`): the device a browser on any device is, the build's name, and what the folder has none of.
 */
export function pageFiles(layout) {
  const files = new Map();
  const walk = (dir, prefix) => {
    for (const entry of readdirSync(dir, { withFileTypes: true })) {
      const path = prefix + entry.name;
      if (entry.name.startsWith(".") || entry.name === "node_modules" || path === "APP.md") continue;
      if (entry.isDirectory()) walk(join(dir, entry.name), path + "/");
      else if (entry.isFile()) files.set(path, readFileSync(join(dir, entry.name)));
    }
  };
  walk(layout.root, "");
  if (layout.game) {
    files.set(DEVICE_FILE, Buffer.from(ANY_BROWSER));
    if (!files.has(CONTROLLERS_FILE)) files.set(CONTROLLERS_FILE, readFileSync(CONTROLLERS));
    if (!files.has("lamp.js")) files.set("lamp.js", Buffer.from(lampJS()));
    // A library the page's import map names from beside it and the folder has none of: Lamp's copy.
    const map = /<script[^>]*type=["']importmap["'][^>]*>([\s\S]*?)<\/script>/i.exec(String(files.get("index.html") ?? ""))?.[1] ?? "";
    for (const name of ["three", "phaser", "rapier"]) {
      if (!new RegExp(`:\\s*["'](?:\\./)?${name}/`).test(map) || [...files.keys()].some((path) => path.startsWith(`${name}/`))) continue;
      const from = join(LIBRARIES, name);
      if (!existsSync(from)) continue;
      const copy = (dir, prefix) => {
        for (const entry of readdirSync(dir, { withFileTypes: true })) {
          if (entry.isDirectory()) copy(join(dir, entry.name), `${prefix}${entry.name}/`);
          else if (entry.isFile() && !lstatSync(join(dir, entry.name)).isSymbolicLink()) files.set(prefix + entry.name, readFileSync(join(dir, entry.name)));
        }
      };
      copy(from, `${name}/`);
    }
    // The build's name, for the runtime to tell a newer copy of the game by: named for the files as they are.
    files.delete("lamp-build.js");
    const hash = createHash("sha256");
    for (const path of [...files.keys()].sort()) hash.update(path).update(files.get(path));
    files.set("lamp-build.js", Buffer.from(`export default "${hash.digest("hex").slice(0, 16)}";\n`));
  }
  return [...files].sort(([a], [b]) => a.localeCompare(b));
}

// MARK: The site

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const megabytes = (bytes) => `${(bytes / 1_000_000).toFixed(bytes < 10_000_000 ? 1 : 0)} MB`;

// What the site says when it turns something down, in plain words.
const REFUSALS = {
  invalid_wish: `the site didn't take the link's words or picture (a name of at most ${LIMITS.name} characters, words of at most ${LIMITS.words}, a line of at most ${LIMITS.line})`,
  invalid_page: `the site didn't take the page: it needs index.html at its top, at most ${PAGE_LIMITS.files} files and ${megabytes(PAGE_LIMITS.total)}`,
  invalid_part: "the site didn't take a part of the page",
  parts_missing: "a part of the page didn't reach the site: share again",
  file_too_large: `the page is more than the ${megabytes(FILE_LIMITS.total)} a link carries, packed`,
  rate_limited: "the site has taken as many as it takes for now: try again in a while",
  service_unavailable: "the site can't keep it just now: try again in a moment",
  not_found: "the link is no longer there",
};

/** One request to the site, tried again when it can't be reached or can't answer just now. */
async function call(method, url, { secret, json, bytes, tries = 3 } = {}) {
  const headers = {
    ...(secret ? { authorization: `Bearer ${secret}` } : {}),
    ...(json ? { "content-type": "application/json" } : bytes ? { "content-type": "application/octet-stream" } : {}),
  };
  for (let attempt = 0; ; attempt++) {
    let answer = null;
    try { answer = await fetch(url, { method, headers, body: json ? JSON.stringify(json) : bytes, signal: AbortSignal.timeout(120_000) }); } catch {}
    if (answer && answer.status < 500) {
      const said = await answer.json().catch(() => null);
      if (answer.ok) return said ?? {};
      const problem = new Problem(REFUSALS[said?.error] ?? `the site answered ${answer.status}`);
      problem.status = answer.status;
      throw problem;
    }
    if (attempt === tries - 1) throw new Problem(answer ? REFUSALS.service_unavailable : `couldn't reach ${new URL(url).host}`);
    await sleep(600 * 2 ** attempt);
  }
}

/**
 * Shares the page, or sends it again to the link the folder has: the link's words and picture, then the page. `words`
 * are what the link says (`name`, `words`, and `line`, `by` and `asks` when given), `picture` a PNG or JPEG of the
 * page or null, `shape` "fill" or the page's width over its height. Answers the link and what went up.
 */
export async function share({ layout, words, picture = null, shape = "fill", site = siteOrigin(), said = () => {} }) {
  const files = pageFiles(layout);
  const unpacked = files.reduce((total, [, bytes]) => total + bytes.length, 0);
  if (!files.some(([path]) => path === "index.html")) throw new Problem("the page has no index.html at its top");
  if (files.length > PAGE_LIMITS.files) throw new Problem(`the page is ${files.length} files, and a link carries ${PAGE_LIMITS.files} at most`);
  if (unpacked > PAGE_LIMITS.total) throw new Problem(`the page is ${megabytes(unpacked)}, and a link carries ${megabytes(PAGE_LIMITS.total)} at most`);
  const zip = zipOf(files);
  if (zip.length > FILE_LIMITS.total) throw new Problem(`the page is ${megabytes(zip.length)} packed, and a link carries ${megabytes(FILE_LIMITS.total)} at most`);
  if (picture && picture.length > LIMITS.picture) picture = null;

  const body = {
    name: words.name, words: words.words, shape,
    ...(words.line ? { line: words.line } : {}), ...(words.by ? { by: words.by } : {}),
    ...(words.asks?.length ? { asks: words.asks } : {}), ...(picture ? { picture: picture.toString("base64") } : {}),
  };
  // The folder's own link when it has one on this site, changed in place; a link that's gone is made again.
  let link = readLink(layout.folder);
  if (link && link.site !== site) link = null;
  let made = null;
  if (link) {
    try { made = await call("PUT", `${site}/api/wishes?id=${link.id}`, { secret: link.secret, json: body }); }
    catch (error) { if (error.status !== 404) throw error; link = null; }
  }
  if (!link) {
    made = await call("POST", `${site}/api/wishes`, { json: body });
    link = { site, id: made.id, secret: made.secret };
  }
  link = { ...link, url: made.url, ...words, shape };
  // Kept before the page goes up: a link whose page didn't make it is still this folder's to send again or take down.
  writeLink(layout.folder, link);

  const count = Math.ceil(zip.length / FILE_LIMITS.part);
  for (let n = 0; n < count; n++) {
    said(`Sending the page: part ${n + 1} of ${count}`);
    await call("PUT", `${site}/api/wish-file?id=${link.id}&what=page&part=${n}&of=${count}`,
      { secret: link.secret, bytes: zip.subarray(n * FILE_LIMITS.part, (n + 1) * FILE_LIMITS.part), tries: 4 });
  }
  const page = await call("POST", `${site}/api/wish-file?id=${link.id}&what=page`, { secret: link.secret });
  link = { ...link, version: page.version, shared: new Date().toISOString() };
  writeLink(layout.folder, link);
  return { url: link.url, version: page.version, files: files.length, bytes: zip.length, picture: !!picture };
}

/** Takes the folder's link down, with its page and the ideas sent to it. */
export async function unshare(folder) {
  const link = readLink(folder);
  if (!link) throw new Problem("this folder has no link");
  try { await call("DELETE", `${link.site}/api/wishes?id=${link.id}`, { secret: link.secret }); }
  catch (error) { if (error.status !== 404) throw error; }
  rmSync(linkFileOf(folder), { force: true });
  return link.url;
}

/** The ideas people playing the link have sent its maker and that are still open: each with its number. */
export async function ideas(folder) {
  const link = readLink(folder);
  if (!link) throw new Problem("this folder has no link: lamp share makes one");
  return { url: link.url, ideas: (await call("GET", `${link.site}/api/wish-ideas?id=${link.id}`, { secret: link.secret })).ideas ?? [] };
}

/** Says what became of an idea: it's in (the site writes to whoever asked to hear), or it's let go. */
export async function finishIdea(folder, n, built) {
  const link = readLink(folder);
  if (!link) throw new Problem("this folder has no link");
  return call("DELETE", `${link.site}/api/wish-ideas?id=${link.id}&n=${n}${built ? "&built=1" : ""}`, { secret: link.secret });
}

/** The page's name where nothing gave one: its title, or its folder's name. */
export function nameOf(layout) {
  try {
    const title = /<title[^>]*>([^<]*)<\/title>/i.exec(readFileSync(join(layout.root, "index.html"), "utf8"))?.[1]?.trim();
    if (title) return title.replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&quot;/g, '"').slice(0, LIMITS.name);
  } catch {}
  return basename(layout.folder).slice(0, LIMITS.name);
}

export { LIMITS };
