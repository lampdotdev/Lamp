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
// Run with --serve in the place of a call's name, it stays: each line on standard input is {"id", "call", "given"},
// and each is answered, in whatever order they finish, by a line {"id", "done"} or {"id", "problem"}, or {"id",
// "failed"} with lamp's own words for anything else. A line {"stop": id} lets go of a call that hasn't answered, when
// whoever asked no longer wants it. It ends when its input does, which is when Lamp's app does. The many small things
// go this way (a request to a device), so each doesn't wait for a program to start.
//
// Lamp's app runs this on the JavaScript runtime it carries (the Bun its bundled agent is built on), and a test run on
// Node: what's imported here, and by what it imports, has to run on both.

import { lstatSync, mkdirSync, readdirSync, readFileSync, realpathSync, renameSync, writeFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Away, OffNetwork, Refused, answersOn, bonjour, pinsAt, searchNetwork, send, ssdp } from "./devices.mjs";
import { PUBLISHER, identityName, keptSigner, namesOf, packageOf, versionAfter } from "./msix.mjs";
import { tile } from "./png.mjs";
import { Problem } from "./state.mjs";

/** A number of seconds a call was given, within what it may take. */
const seconds = (given, standard, most = 10) => Math.min(Math.max(Number(given) > 0 ? Number(given) : standard, 0.5), most);

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

  /**
   * One request of an integration's to a device (devices.mjs's `send`, with every guard it has): `request` as the
   * integration writes one, to the device at `address`, with `values` filled in (what the person typed for the device
   * among them, which is why this comes on standard input), `files` it may send by path, and `pins`, the file the
   * device's certificates are kept in, without which nothing secret goes over HTTPS. The answer's body is in base64.
   */
  async send(given, { stopped } = {}) {
    const answer = await send(given.request ?? {}, text(given, "address"), given.values ?? {}, {
      files: given.files ?? {}, pins: typeof given.pins === "string" ? pinsAt(given.pins) : undefined,
      timeout: Math.round((Number(given.timeout) > 0 ? Number(given.timeout) : 30) * 1000), stopped,
    });
    return { status: answer.status, body: answer.body.toString("base64"), cookies: answer.cookies, certificate: answer.certificate?.toString("base64") ?? null };
  },

  /**
   * One look at the home network for the `integrations` Lamp's app has (each as its JSON): every answer to a search
   * for everything, what each integration found and read of its devices, and the devices none of them knows, read
   * from their own descriptions. Which of those Lamp keeps, and what it called them, is Lamp's app's.
   */
  async look(given) {
    const list = (Array.isArray(given.integrations) ? given.integrations : []).filter((integration) => typeof integration?.id === "string");
    return searchNetwork({ integrations: list, seconds: seconds(given.seconds, 2.5), unknown: given.unknown !== false });
  },

  /** A search of the home network for one search target, for a few seconds: every answer. */
  async search(given) {
    return { answers: await ssdp(typeof given.target === "string" ? given.target : "ssdp:all", seconds(given.seconds, 2)) };
  },

  /**
   * Whether the device at `address` is there now, as a step's check asks: it takes a connection on a port (`tcp`), it
   * answers a search for a target (`ssdp`), or it offers a Bonjour service (`bonjour`).
   */
  async probe(given) {
    const address = text(given, "address");
    if (Number.isInteger(given.tcp)) return { present: await answersOn(address, given.tcp, { timeout: seconds(given.seconds, 3) * 1000 }) };
    if (typeof given.ssdp === "string") return { present: (await ssdp(given.ssdp, seconds(given.seconds, 2))).some((answer) => answer.address === address) };
    if (typeof given.bonjour === "string") return { present: (await bonjour(given.bonjour, seconds(given.seconds, 3))).some((found) => found.address === address) };
    throw new Error('the call needs "tcp", "ssdp" or "bonjour"');
  },
};

/** A problem as Lamp's app shows one: a sentence, in which lamp is Lamp. */
const sentence = (words) => `${words[0].toUpperCase()}${words.slice(1)}${/[.!?]$/.test(words) ? "" : "."}`.replace(/\blamp\b/g, "Lamp");

/**
 * What went wrong, as the answer says it: a problem the person can put right, with its kind where Lamp's app does
 * something about that kind (a certificate that changed, a device that's away); null for anything else, lamp's own fault.
 */
function problemOf(error) {
  if (!(error instanceof Problem)) return null;
  const said = { problem: sentence(error.message) };
  if (error instanceof Refused) said.kind = error.kind;
  else if (error instanceof OffNetwork) said.kind = "off-network";
  else if (error instanceof Away) Object.assign(said, { kind: "away", code: error.code ?? null, timedOut: error.timedOut });
  return said;
}

/** One call, run to its end, as a single run of this file. */
async function once(name) {
  const call = CALLS[name];
  if (!call) throw new Error(`lamp has no call named "${name ?? ""}"`);
  const chunks = [];
  for await (const chunk of process.stdin) chunks.push(chunk);
  const given = JSON.parse(Buffer.concat(chunks).toString("utf8") || "{}");
  try {
    console.log(JSON.stringify({ done: await call(given) }));
  } catch (error) {
    const said = problemOf(error);
    if (!said) throw error;
    console.log(JSON.stringify(said));
    process.exitCode = 1;
  }
}

/** Calls answered as they come, for as long as there's someone to ask. */
async function serve() {
  const say = (line) => process.stdout.write(JSON.stringify(line) + "\n");
  const under = new Map();
  const answer = async (line) => {
    let asked;
    try { asked = JSON.parse(line); } catch { return; }
    if (asked?.stop !== undefined) return void under.get(asked.stop)?.abort();
    const id = asked?.id, call = CALLS[asked?.call], stopping = new AbortController();
    under.set(id, stopping);
    try {
      if (!call) throw new Error(`lamp has no call named "${asked?.call ?? ""}"`);
      say({ id, done: await call(asked.given ?? {}, { stopped: stopping.signal }) });
    } catch (error) {
      say({ id, ...(problemOf(error) ?? { failed: String(error?.stack ?? error) }) });
    } finally { under.delete(id); }
  };
  let waiting = [];
  for await (const chunk of process.stdin) {
    let from = 0;
    for (let end = chunk.indexOf(10, from); end >= 0; end = chunk.indexOf(10, from)) {
      const line = Buffer.concat([...waiting, chunk.subarray(from, end)]).toString("utf8");
      waiting = [];
      from = end + 1;
      if (line.trim()) answer(line);
    }
    if (from < chunk.length) waiting.push(chunk.subarray(from));
  }
  // Nobody is left to hear an answer.
  process.exit(0);
}

const here = () => { try { return realpathSync(process.argv[1] ?? "") === realpathSync(fileURLToPath(import.meta.url)); } catch { return false; } };
if (here()) await (process.argv[2] === "--serve" ? serve() : once(process.argv[2]));
