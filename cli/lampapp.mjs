// A Lamp app file (`.lampapp`, what Lamp's Share… makes and a lamp.dev link carries): a zip of the app's own files and
// lamp-app.json, which says what it is, with none of Lamp's own files in it (the Mac that opens it writes its own).
// Unpacked into a folder lamp runs; Lamp's app reads the same file with its review and checks (`Sharing.open`).

import { randomUUID } from "node:crypto";
import { existsSync, mkdirSync, readFileSync, readdirSync, statSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";
import { inflateRawSync } from "node:zlib";
import { Problem, manifestOf, projectOf, stateOf } from "./state.mjs";
import { nameOf, zipOf } from "./share.mjs";

// What another Lamp accepts in a file (`Sharing.maxFiles`, `maxUnpackedBytes`, `maxArchiveBytes`).
export const MAX_FILES = 2000, MAX_UNPACKED = 256 * 1024 * 1024, MAX_ARCHIVE = 64 * 1024 * 1024;

/**
 * The files of a zip, by path: each a regular file's bytes, in the folder it names. A path that leaves the folder, a
 * link, or a file packed some way other than stored or deflated isn't taken; nor is a zip bigger than a Lamp app file
 * is let be, unpacked or not.
 */
export function unzipped(zip) {
  if (zip.length > MAX_ARCHIVE) throw new Problem("it's bigger than a Lamp app file is let be");
  let end = -1;
  for (let at = zip.length - 22; at >= Math.max(0, zip.length - 22 - 0xffff); at--) if (zip.readUInt32LE(at) === 0x06054b50) { end = at; break; }
  if (end < 0) throw new Problem("it isn't a Lamp app file: it isn't a zip");
  const count = zip.readUInt16LE(end + 10);
  let at = zip.readUInt32LE(end + 16), total = 0;
  if (count > MAX_FILES) throw new Problem(`it holds more than a Lamp app would (over ${MAX_FILES} files)`);
  const files = new Map();
  for (let n = 0; n < count; n++) {
    if (zip.readUInt32LE(at) !== 0x02014b50) throw new Problem("it isn't a Lamp app file: its zip can't be read");
    const method = zip.readUInt16LE(at + 10), packed = zip.readUInt32LE(at + 20), size = zip.readUInt32LE(at + 24);
    const nameLength = zip.readUInt16LE(at + 28), extra = zip.readUInt16LE(at + 30), comment = zip.readUInt16LE(at + 32);
    const unix = zip.readUInt32LE(at + 38) >>> 16, local = zip.readUInt32LE(at + 42);
    const name = zip.toString("utf8", at + 46, at + 46 + nameLength);
    at += 46 + nameLength + extra + comment;
    // A folder is made with its files, and a Mac's own records (__MACOSX, .DS_Store) aren't the app's.
    if (name.endsWith("/") || name.startsWith("__MACOSX/") || basename(name) === ".DS_Store") continue;
    const parts = name.split("/");
    if (name.startsWith("/") || name.includes("\\") || parts.some((part) => part === ".." || part === "" || part === ".")) throw new Problem(`it names a file outside its folder (${name})`);
    if ((unix & 0o170000) === 0o120000) continue;
    total += size;
    if (total > MAX_UNPACKED) throw new Problem("it holds more than a Lamp app would (over 256 MB unpacked)");
    const start = local + 30 + zip.readUInt16LE(local + 26) + zip.readUInt16LE(local + 28), data = zip.subarray(start, start + packed);
    const bytes = method === 0 ? Buffer.from(data) : method === 8 ? inflateRawSync(data, { maxOutputLength: size + 1 }) : null;
    if (!bytes || bytes.length !== size) throw new Problem(`it holds a file lamp can't unpack (${name})`);
    files.set(name, bytes);
  }
  return files;
}

/**
 * Unpacks a Lamp app file into `folder` (a new folder beside the file, named for it, when none is given), and answers
 * what the folder is to lamp. The folder must be new or empty: nothing of anyone's is written over. A file of a kind
 * lamp doesn't run is unpacked all the same, with the reason, so it can be opened in Lamp's app.
 */
export function unpack(file, folder = null) {
  const path = resolve(file);
  let zip;
  try { zip = readFileSync(path); } catch { throw new Problem(`${path} can't be read`); }
  const files = unzipped(zip);
  // A file Lamp made holds its app at its top, or (from some Macs) inside one folder.
  const tops = new Set([...files.keys()].map((name) => name.split("/")[0]));
  const inner = !files.has("lamp-app.json") && tops.size === 1 && files.has(`${[...tops][0]}/lamp-app.json`) ? `${[...tops][0]}/` : "";
  if (!files.has(`${inner}lamp-app.json`)) throw new Problem("it isn't a Lamp app file: it has no lamp-app.json");
  const target = resolve(folder ?? join(dirname(path), basename(path).replace(/\.lampapp$/i, "")));
  if (existsSync(target) && readdirSync(target).length) throw new Problem(`${target} already has things in it`);
  for (const [name, bytes] of files) {
    if (!name.startsWith(inner)) continue;
    const out = join(target, ...name.slice(inner.length).split("/"));
    if (!out.startsWith(target + sep)) continue;
    mkdirSync(dirname(out), { recursive: true });
    writeFileSync(out, bytes);
  }
  const manifest = manifestOf(target);
  let project = null, refused = null;
  try { project = projectOf(target); } catch (error) { if (!(error instanceof Problem)) throw error; refused = error.message; }
  return { folder: target, name: typeof manifest?.name === "string" ? manifest.name : basename(target), project, refused };
}

// MARK: Making one

// Lamp's own files beside a page, by their path in the page: the Mac that opens the file writes its own
// (`GameFiles.isLamps`, `ScreenFiles.isLamps`).
const GAME_LAMPS = (path) => ["lamp-game.js", "lamp.js", "lamp-controllers.js", "lamp-phaser.js", "lamp-device.js", "lamp-build.js"].includes(path)
  || path.startsWith("phaser/") || path.startsWith("three/");
const SCREEN_LAMPS = (path) => path === "lamp.js";
// What sits beside a page at a folder's top that's the wish's, not the page's: it goes as itself, or not at all.
const WISH_FILES = new Set(["APP.md", "about.json", "icon.json", "icon-glass.json", "icon-art.png", "icon.png", "credits.json", "lamp-app.json", "capabilities.json", "Assets"]);
// The hidden files at a page's top that a web server reads, which go with a site (`ScreenFiles.servedHidden`).
const SERVED_HIDDEN = new Set([".nojekyll", ".well-known"]);
// The Mac app's own Swift beside Lamp's (`Template`'s support files), which stays behind.
const SWIFT_LAMPS = new Set(["LampSupport.swift", "LampScene.swift", "LampWidgetSupport.swift", "LampShareSupport.swift"]);

// Shapes of keys and tokens whoever's they are (`ShareCheck.tokenShapes`).
const TOKEN_SHAPES = [
  /-----BEGIN [A-Z ]*PRIVATE KEY-----/, /\bsk-(or-v1-|ant-|proj-)?[A-Za-z0-9_\-]{32,}/, /\bgh[pousr]_[A-Za-z0-9]{36,}/, /\bgithub_pat_[A-Za-z0-9_]{60,}/,
  /\bAKIA[0-9A-Z]{16}\b/, /\bAIza[0-9A-Za-z_\-]{35}\b/, /\bxox[abprs]-[A-Za-z0-9\-]{20,}/, /\b(sk|rk)_live_[A-Za-z0-9]{20,}/,
];

/** A license text by its name (`Credits.isLicenceFile`): LICENSE, LICENCE, COPYING, NOTICE or UNLICENSE, never code. */
export function isLicenceFile(path) {
  if (typeof path !== "string" || !path || path.startsWith("/") || path.split("/").some((part) => !part || part === ".." || part === ".")) return false;
  const name = path.split("/").pop(), dot = name.lastIndexOf("."), ext = dot > 0 ? name.slice(dot + 1).toLowerCase() : "";
  return ["LICENSE", "LICENCE", "COPYING", "NOTICE", "UNLICENSE"].some((start) => name.toUpperCase().startsWith(start))
    && ext.length <= 10 && /^[a-z0-9]*$/.test(ext) && !["sh", "command", "app", "js", "py", "rb", "pl", "swift", "html", "htm"].includes(ext);
}

/** Every regular file under `dir`, by its path from `dir` (`prefix` before it), none hidden unless `hidden` lets it, no link followed. */
function filesUnder(dir, prefix = "", { hidden = () => false, skip = () => false } = {}) {
  const found = [];
  let entries;
  try { entries = readdirSync(dir, { withFileTypes: true }); } catch { return found; }
  for (const entry of entries) {
    const path = prefix + entry.name;
    if ((entry.name.startsWith(".") && !hidden(path)) || skip(path)) continue;
    if (entry.isDirectory()) found.push(...filesUnder(join(dir, entry.name), path + "/", { hidden: () => false, skip }));
    else if (entry.isFile()) found.push(path);
  }
  return found;
}

/**
 * Which app this is, the same in every file made from it (`Sharing.identity`): Lamp's app's for a folder it made,
 * else the one lamp keeps for the folder, else the one the folder came with in its lamp-app.json, kept from then on.
 */
function identityOf(folder) {
  const uuid = (text) => /^[0-9A-F]{8}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{4}-[0-9A-F]{12}$/i.test(String(text ?? "").trim()) ? String(text).trim().toUpperCase() : null;
  const read = (path) => { try { return uuid(readFileSync(path, "utf8")); } catch { return null; } };
  const kept = join(stateOf(folder), "share-id");
  const known = read(join(folder, ".lamp", "share-id")) ?? read(kept);
  if (known) return known;
  const id = uuid(manifestOf(folder)?.app) ?? randomUUID().toUpperCase();
  mkdirSync(stateOf(folder), { recursive: true });
  writeFileSync(kept, id);
  return id;
}

/**
 * The app in the folder as a Lamp app file (`Sharing.export`), as bytes, with its name: its own files as its kind
 * travels (a page's in Web/, a Mac app's Swift in Sources/ and its widget's and share extension's), Assets/, APP.md and
 * what it declares, its credits with this app added to the chain it came by, each license they name, its icon's design,
 * and lamp-app.json, which says what it is. Never Lamp's own files, which the Mac that opens it writes, nor anything
 * hidden. Refused when a license its credits name is gone, when something in it is shaped like a key, or when it's
 * more than another Lamp opens. Work its credits give no license for goes only with `anyway`: its author may not want
 * it passed on.
 */
export function exportApp(given, { anyway = false } = {}) {
  const project = projectOf(given), folder = project.folder, manifest = manifestOf(folder);
  const credits = (() => { try { return JSON.parse(readFileSync(join(folder, "credits.json"), "utf8")); } catch { return {}; } })();
  const upstream = Array.isArray(credits?.upstream) ? credits.upstream.filter((source) => source && typeof source.name === "string") : [];
  const terms = (source) => [source.licenseFile, ...(Array.isArray(source.noticeFiles) ? source.noticeFiles : [])].filter((path) => typeof path === "string");
  const name = String((typeof manifest?.name === "string" && manifest.name.trim()) || (project.kind === "page" ? nameOf(project) : basename(folder))).replace(/[\r\n/:]+/g, " ").trim().slice(0, 60) || "App";
  for (const source of upstream) {
    const gone = terms(source).find((path) => !existsSync(join(folder, path)));
    if (gone) throw new Problem(`${name} can't be shared: the license of ${source.name} is missing from it. Put ${gone} back.`);
  }
  const unlicensed = upstream.filter((source) => !source.license);
  if (unlicensed.length && !anyway) {
    throw new Problem(`${name} uses work that came with no license (${unlicensed.map((source) => source.author ? `${source.name} by ${source.author}` : source.name).join(", ")}). Ask the person whether they're comfortable sharing it; --anyway shares it all the same.`);
  }

  const files = new Map(), from = (path) => readFileSync(join(folder, path));
  let kind, site = false, flags = {};
  if (project.kind === "page") {
    kind = typeof manifest?.platform === "string" ? manifest.platform : project.game ? "game" : "web-app";
    const lamps = kind === "game" ? GAME_LAMPS : SCREEN_LAMPS;
    // A page in Web/ goes as it is; a page at the folder's top (a plain site, or a page lamp made) is a site, whose
    // page is Web/ in the file and whose own files beside it go as themselves.
    site = !project.lamps && kind === "web-app";
    for (const path of filesUnder(project.root, "", { hidden: (path) => site && SERVED_HIDDEN.has(path), skip: (path) => path === "node_modules" || (!project.lamps && (WISH_FILES.has(path) || isLicenceFile(path) || path === ".lamp-wish")) })) {
      if (!lamps(path)) files.set(`Web/${path}`, readFileSync(join(project.root, path)));
    }
    if (project.lamps) {
      // The Swift beside the page that answers its calls of the device, and a game's phone page.
      for (const path of filesUnder(join(folder, "Sources"), "Sources/")) if (path.endsWith(".swift") && (kind === "game" ? path === "Sources/Native.swift" : !["Sources/LampSupport.swift", "Sources/LampPage.swift", "Sources/LampControllerKit.swift", "Sources/LampScreen.swift", "Sources/LampWebApp.swift"].includes(path))) files.set(path, from(path));
      if (kind === "game") for (const path of [...filesUnder(join(folder, "Phone"), "Phone/"), ...filesUnder(join(folder, "src"), "src/")]) files.set(path, from(path));
    }
  } else {
    kind = "mac";
    for (const path of filesUnder(join(folder, "Sources"), "Sources/")) if (path.endsWith(".swift") && !SWIFT_LAMPS.has(basename(path))) files.set(path, from(path));
    for (const [extra, flag] of [["Widget", "widget"], ["Share", "share"]]) {
      const code = filesUnder(join(folder, extra), `${extra}/`).filter((path) => path.endsWith(".swift") && !SWIFT_LAMPS.has(basename(path)));
      for (const path of code) files.set(path, from(path));
      flags[flag] = code.length > 0;
    }
    flags.scene = [...files.keys()].some((path) => path.startsWith("Sources/") && /^\s*(@\w+\s+)?import\s+RealityKit\b/m.test(files.get(path).toString("utf8")));
  }
  if (![...files.keys()].some((path) => path.startsWith("Sources/") || path.startsWith("Web/"))) throw new Problem(`${name} has no code in it to share`);
  // Code that isn't text can't be read by Lamp's checks on the way in, and Lamp never writes any.
  for (const [path, bytes] of files) if (path.endsWith(".swift") && bytes.includes(0)) throw new Problem(`${name} can't be shared: ${path} isn't plain text`);

  // The app's own files, capped so a file stays small enough to send (`Sharing.maxAttachedBytes`).
  let attached = 0;
  for (const path of filesUnder(join(folder, "Assets"), "Assets/")) {
    attached += statSync(join(folder, path)).size;
    if (attached > MAX_ARCHIVE - 8 * 1024 * 1024) throw new Problem(`${name} is too big to share: its pictures and other files come to over ${Math.floor((MAX_ARCHIVE - 8 * 1024 * 1024) / 1_000_000)} MB`);
    files.set(path, from(path));
  }
  if (existsSync(join(folder, "APP.md"))) files.set("APP.md", from("APP.md"));
  // What the app declares; the Lamp that opens the file checks each of it again as it reads it.
  let declares = false;
  try { const said = JSON.parse(readFileSync(join(folder, "capabilities.json"), "utf8")); if (said && typeof said === "object" && !Array.isArray(said) && Object.keys(said).length) { files.set("capabilities.json", Buffer.from(JSON.stringify(said, null, 2))); declares = true; } } catch {}
  // Its icon's design, and the artwork drawn for it where the folder keeps it at its top (a file Lamp made does).
  for (const icon of ["icon.json", "icon-glass.json", "icon-art.png", "icon.png"]) if (existsSync(join(folder, icon))) files.set(icon, from(icon));

  // Whoever opens the file is remixing this app: it's added to the chain its credits carry, as one link if it's
  // already the last (`Credits.remixed`).
  const me = { name, wish: identityOf(folder) }, chain = Array.isArray(credits?.remixOf) ? credits.remixOf.filter((link) => link && typeof link.name === "string") : [];
  const last = chain.at(-1);
  if (last && (last.wish ? last.wish === me.wish : !last.starter && last.name === me.name)) chain[chain.length - 1] = { ...last, ...me, url: last.url, commit: last.commit };
  else chain.push(me);
  const carried = { remixOf: chain.slice(0, 32).map((link) => Object.fromEntries(Object.entries(link).filter(([, value]) => value != null))), upstream: upstream.slice(0, 32) };
  if (Array.isArray(credits?.generated) && credits.generated.length) carried.generated = credits.generated.filter((entry) => typeof entry?.file === "string" && existsSync(join(folder, entry.file)));
  files.set("credits.json", Buffer.from(JSON.stringify(sortedKeys(carried), null, 2)));
  // Each license and notice the credits name goes with the work it covers.
  for (const source of upstream) for (const path of terms(source)) if (isLicenceFile(path) && !files.has(path)) files.set(path, from(path));

  let description = null;
  try { const said = JSON.parse(readFileSync(join(folder, "about.json"), "utf8")).description; if (typeof said === "string" && said.trim() && !/[\r\n]/.test(said.trim())) description = said.trim(); } catch {}
  // The number a Lamp that opens it reads it by (`Sharing.format`): a web app or screen 12, a game 11, a Mac app by what it has.
  const format = kind === "web-app" || kind === "screen" ? 12 : kind === "game" ? 11 : flags.scene ? 8 : flags.share ? 7 : declares ? 4 : flags.widget ? 3 : 2;
  files.set("lamp-app.json", Buffer.from(JSON.stringify(sortedKeys({
    app: me.wish, ...(description ? { description } : {}), exportedAt: new Date().toISOString().replace(/\.\d+Z$/, "Z"),
    format, name, platform: kind, ...(site ? { site: true } : {}),
  }), null, 2)));

  // Nothing of the person's goes with it: the app's own token and anything shaped like a key.
  const known = [join(folder, ".lamp", "token"), join(stateOf(folder), "app-token")].map((path) => { try { return readFileSync(path, "utf8").trim(); } catch { return ""; } }).filter((value) => value.length >= 16);
  const leaks = [...files].filter(([, bytes]) => { const text = bytes.toString("utf8"); return known.some((value) => text.includes(value)) || TOKEN_SHAPES.some((shape) => shape.test(text)); }).map(([path]) => path).sort();
  if (leaks.length) throw new Problem(`${name} can't be shared: it holds a key or a password, in ${leaks[0]}${leaks.length > 1 ? ` and ${leaks.length - 1} more` : ""}. Take it out and keep it out of the code.`);

  // Counted as another Lamp counts it on the way in: files and the folders they're in, and bytes unpacked.
  const folders = new Set([...files.keys()].flatMap((path) => path.split("/").slice(0, -1).map((_, n, parts) => parts.slice(0, n + 1).join("/"))));
  if (files.size + folders.size > MAX_FILES) throw new Problem(`${name} has too many files to share`);
  if ([...files.values()].reduce((sum, bytes) => sum + bytes.length, 0) > MAX_UNPACKED) throw new Problem(`${name} is too big to share`);
  const bytes = zipOf([...files].sort(([a], [b]) => a.localeCompare(b)));
  if (bytes.length > MAX_ARCHIVE) throw new Problem(`${name} is too big to share`);
  return { name, kind, bytes, files: files.size };
}

/** An object with its keys in order, at every level, as Lamp's own encoder writes its files. */
function sortedKeys(value) {
  if (Array.isArray(value)) return value.map(sortedKeys);
  if (!value || typeof value !== "object") return value;
  return Object.fromEntries(Object.keys(value).sort().map((key) => [key, sortedKeys(value[key])]));
}
