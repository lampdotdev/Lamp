// A Lamp app file (`.lampapp`, what Lamp's Share… makes and a lamp.dev link carries): a zip of the app's own files and
// lamp-app.json, which says what it is, with none of Lamp's own files in it (the Mac that opens it writes its own).
// Unpacked into a folder lamp runs; Lamp's app reads the same file with its review and checks (`Sharing.open`).

import { existsSync, mkdirSync, readFileSync, readdirSync, writeFileSync } from "node:fs";
import { basename, dirname, join, resolve, sep } from "node:path";
import { inflateRawSync } from "node:zlib";
import { Problem, manifestOf, projectOf } from "./state.mjs";

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
