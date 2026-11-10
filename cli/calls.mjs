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
import { Away, OffNetwork, Refused, Rejected, Runner, StillWorking, answersOn, bonjour, pinsAt, searchNetwork, send, ssdp } from "./devices.mjs";
import { Unreachable, ideasOf, latestOf, publishLink, removeFile, removeIdea, removeLink, sendFile } from "./link.mjs";
import { defaultRoute, homeNetwork, neighbours, samsungAt, subnetOn, tvsIn } from "./network.mjs";
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

/**
 * The runner for an integration's device, as Lamp's app hands it over: the integration (its JSON), the device (its
 * id, name and address), the values to fill in (what the person typed among them, kept by Lamp's app), the file its
 * certificates are kept in, and where a key it gives is kept. `event` tells whoever asked each time the device is
 * waited on; `stopped` ends the run.
 */
function runnerOf(given, { stopped, event = () => {} } = {}) {
  if (typeof given.integration?.id !== "string" || typeof given.device?.id !== "string") throw new Error('the call needs "integration" and "device"');
  return new Runner({ integration: given.integration, device: { id: given.device.id, name: String(given.device.name ?? "The device"), address: given.device.address },
    values: given.values ?? {}, pins: pinsAt(text(given, "pins")), keyFile: typeof given.keyFile === "string" ? given.keyFile : undefined,
    stopped, onWaiting: () => event({ waiting: true }) });
}

/** What a sequence gave back, as Lamp's app reads it: a picture in base64, and the cookies its next part sends back. */
const outcomeOf = (outcome) => ({ ...outcome, picture: outcome.picture ? Buffer.from(outcome.picture).toString("base64") : null });

/** A shared link as Lamp's app keeps it: its id and secret, and the site it's on. */
const linkOf = (given) => ({ id: text(given, "id"), secret: text(given, "secret") });
const siteOf = (given) => text(given, "site").replace(/\/+$/, "");

export const CALLS = {
  /**
   * Shares a wish's link, or changes what it shows (`earlier`: its id and secret), on `site`, with `body` as the site
   * takes it. Its id, address and secret.
   */
  async linkPublish(given) {
    const earlier = given.earlier && typeof given.earlier.id === "string" ? given.earlier : null;
    return publishLink({ site: siteOf(given), body: given.body ?? {}, earlier });
  },

  /** What a followed link has now, asked with nothing of the person's; `latest` null when it can't be asked or is gone. */
  async linkLatest(given) {
    return { latest: await latestOf({ site: siteOf(given), id: text(given, "id") }) };
  },

  /** The link's file (or with `page`, its playable page), from a file of Lamp's at `file`, sent in parts. */
  async linkUpload(given, how = {}) {
    return { version: await sendFile({ site: siteOf(given), link: linkOf(given), bytes: readFileSync(text(given, "file")), page: given.page === true,
      said: (line) => how.event?.({ said: line }) }) };
  },

  /** Takes the link's file away (with `page`, only its page). */
  async linkRemoveFile(given) {
    await removeFile({ site: siteOf(given), link: linkOf(given), page: given.page === true });
    return {};
  },

  /** The ideas sent to the link that are still open. */
  async linkIdeas(given) {
    return { ideas: await ideasOf({ site: siteOf(given), link: linkOf(given) }) };
  },

  /** Lets an idea go; with `built` it's in, and the site writes to whoever asked to hear. */
  async linkRemoveIdea(given) {
    return removeIdea({ site: siteOf(given), link: linkOf(given), n: Number(given.n), built: given.built === true });
  },

  /** Takes the link down. */
  async linkRemove(given) {
    await removeLink({ site: siteOf(given), link: linkOf(given) });
    return {};
  },


  /**
   * One part of an integration's sequence on a device (`sequence`: its requests, waits and probes; what only Lamp's
   * app does, a command on the device or a sign-in page, is between parts), with `cookies` from the part before. The
   * settings it changes for itself (`restore`) come back in `changed`, which Lamp's app hands to `putBack` once it's
   * done with them, or they're put back as the part ends when it asks for that (`putBack: true`).
   */
  async run(given, how = {}) {
    const runner = runnerOf(given, how), changed = Array.isArray(given.changed) ? given.changed : [], before = changed.length;
    try {
      const outcome = await runner.run(Array.isArray(given.sequence) ? given.sequence : [], { extra: given.extra ?? {}, files: given.files ?? {}, changed, cookies: given.cookies ?? {} });
      if (given.putBack === true) await runner.putBack(changed);
      return { outcome: outcomeOf(outcome), changed };
    } catch (error) {
      // A part that fails puts back what it changed itself: the answer that says so carries no settings to hand back.
      await runner.putBack(changed.splice(before));
      throw error;
    }
  },

  /** Puts back what parts of a sequence changed for themselves (`changed`, as `run` gave it), last first: the settings it couldn't. */
  async putBack(given, how = {}) {
    return { missed: await runnerOf(given, how).putBack(Array.isArray(given.changed) ? given.changed : []) };
  },

  /**
   * Opens an app just put on the device: `launch`, then `running` until it's seen running, launched again while the
   * device refuses or doesn't open it, up to `tries` launches. Whether it opened, whether it was ever launched, and
   * what the device last refused with.
   */
  async open(given, how = {}) {
    const changed = Array.isArray(given.changed) ? given.changed : [];
    const opened = await runnerOf(given, how).open(given.launch ?? [], given.running ?? null, { extra: given.extra ?? {}, changed, tries: Number.isInteger(given.tries) ? given.tries : 8 });
    return { ...opened, refused: opened.refused ?? null, changed };
  },

  /** What a check of a setup's `conditions` finds on the device now: holds, waiting, away or rejected, with why and what it read. */
  async check(given, how = {}) {
    return runnerOf(given, how).evaluate(Array.isArray(given.conditions) ? given.conditions : []);
  },

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
   * for everything, what each integration found and read of its devices, with `unknown` the devices none of them
   * knows, read from their own descriptions, and with `tvs` what each Samsung or LG TV that answered says of itself.
   * Which of those Lamp keeps, and what it called them, is Lamp's app's.
   */
  async look(given) {
    const list = (Array.isArray(given.integrations) ? given.integrations : []).filter((integration) => typeof integration?.id === "string");
    const answers = await ssdp("ssdp:all", seconds(given.seconds, 2.5));
    const [seen, tvs] = await Promise.all([searchNetwork({ integrations: list, answers, unknown: given.unknown === true }), given.tvs === true ? tvsIn(answers) : []]);
    return { ...seen, tvs };
  },

  /** What a Samsung TV at `address` says of itself now, as the look reads it; null when it doesn't answer as one. */
  async tv(given) {
    return { tv: await samsungAt(text(given, "address")) };
  },

  /**
   * Everything on this computer's subnet besides what the look finds: each host with its hardware address and its
   * Bonjour services, and which subnet was swept.
   */
  async network(given) {
    return homeNetwork({ seconds: seconds(given.seconds, 3) });
  },

  /**
   * The network as it is now, read with nothing sent: this computer's neighbor table (each neighbor's IPv4 address
   * and hardware address), its gateway, and the subnet a sweep would take.
   */
  async neighbours() {
    const route = await defaultRoute();
    return { table: await neighbours(), gateway: route?.gateway ?? null, subnet: route ? subnetOn(route.interface) : null };
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
  else if (error instanceof Rejected) said.kind = "rejected";
  else if (error instanceof StillWorking) said.kind = "still-working";
  else if (error instanceof OffNetwork) said.kind = "off-network";
  else if (error instanceof Unreachable) said.kind = "unreachable";
  else if (error instanceof Away) Object.assign(said, { kind: "away", code: error.code ?? null, timedOut: error.timedOut });
  if (Number.isInteger(error.status)) said.status = error.status;
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
      say({ id, done: await call(asked.given ?? {}, { stopped: stopping.signal, event: (said) => say({ id, event: said }) }) });
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
