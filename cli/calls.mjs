#!/usr/bin/env node
// What Lamp's app asks of lamp. The work that's lamp's own (this folder) is done here once, and Lamp's app has it done
// (`LampCLI`, in Swift) rather than doing it a second time itself. Each call is one run of this file: the call's name
// is its one argument, what it's given is one JSON object on standard input (never in the arguments, which any
// process on the computer can list), and its answer is the last line it prints, one JSON object: {"done": …}, or
// {"problem": "…"} for something the person can put right, said in a sentence. Anything else that goes wrong ends
// the run with its own words on standard error.
//
// A call works on what Lamp's app hands it from Lamp's own folders, by path. It's never pointed at an app's folder:
// what's there is the agent's to write, and Lamp's app reads it its own way before anything comes here.
//
// Lamp's app runs this on the JavaScript runtime it carries (the Bun its bundled agent is built on), and a test run on
// Node: what's imported here, and by what it imports, has to run on both.

import { lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { PUBLISHER, identityName, keptSigner, namesOf, packageOf, versionAfter } from "./msix.mjs";
import { tile } from "./png.mjs";
import { Problem } from "./state.mjs";

const text = (given, name) => {
  if (typeof given[name] !== "string" || !given[name]) throw new Error(`the call needs "${name}"`);
  return given[name];
};

/** Every file in a folder, by its path from the folder's top, in a settled order. A link is never followed: it's refused. */
function filesIn(folder) {
  const files = [];
  const walk = (at, prefix) => {
    for (const name of readdirSync(at).sort()) {
      const file = join(at, name), kind = lstatSync(file);
      if (kind.isSymbolicLink()) throw new Problem(`${prefix}${name} is a shortcut to another file. Put the file itself in its place`);
      if (kind.isDirectory()) walk(file, `${prefix}${name}/`);
      else if (kind.isFile()) files.push([prefix + name, readFileSync(file)]);
    }
  };
  walk(folder, "");
  return files;
}

/** Written whole or not at all: beside its place, then moved in. */
function write(file, bytes, mode) {
  mkdirSync(dirname(file), { recursive: true });
  const beside = `${file}.writing`;
  writeFileSync(beside, bytes, mode ? { mode } : undefined);
  renameSync(beside, file);
}

export const CALLS = {
  /**
   * A signed Windows package (msix.mjs) of the files in `payload`, a folder Lamp's app laid out, written to `out`, with
   * the certificate a device installs beside it at `certificate`. The package is named for the app (`slug`) and is a
   * newer version than `after`, the last one made; `entry` is what it starts ("webHost", {page} or {program}), `icon`
   * a picture of the app for its tiles, and `signer` the folder lamp's key for packages is kept in, made the first time.
   */
  msix(given) {
    const entry = given.entry === "webHost" || typeof given.entry?.page === "string" || typeof given.entry?.program === "string" ? given.entry : null;
    if (!entry) throw new Error('the call needs "entry": "webHost", {page} or {program}');
    const identity = { name: identityName(text(given, "slug")), publisher: PUBLISHER, version: versionAfter(typeof given.after === "string" ? given.after : undefined) };
    if (typeof given.architecture === "string") identity.architecture = given.architecture;
    let icon = null;
    if (typeof given.icon === "string") { try { icon = readFileSync(given.icon); } catch { /* the tile's color alone */ } }
    const payload = filesIn(text(given, "payload")), signer = keptSigner(text(given, "signer"));
    const made = packageOf({ payload, displayName: text(given, "displayName"), identity, entry, logo: (width, height) => tile(icon, width, height), signer });
    write(text(given, "out"), made);
    write(text(given, "certificate"), signer.certificate);
    return { identity, ...namesOf(identity), bytes: made.length, files: payload.length };
  },
};

/** A problem as Lamp's app shows one: a sentence. */
const sentence = (words) => `${words[0].toUpperCase()}${words.slice(1)}${/[.!?]$/.test(words) ? "" : "."}`;

async function main() {
  const call = CALLS[process.argv[2]];
  if (!call) throw new Error(`lamp has no call named "${process.argv[2] ?? ""}"`);
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const given = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  try {
    console.log(JSON.stringify({ done: await call(given) }));
  } catch (error) {
    if (!(error instanceof Problem)) throw error;
    console.log(JSON.stringify({ problem: sentence(error.message) }));
    process.exitCode = 1;
  }
}

const here = () => { try { return realpathSync(process.argv[1] ?? "") === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } };
if (here()) await main();
