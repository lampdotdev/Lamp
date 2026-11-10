// The person's devices, for lamp's command line: finding them on the home network, setting one up, and running what
// its integration says an app goes on it by. An integration is data (Resources/Devices/*.json, the same files Lamp's
// app reads): how the device is found, its setup steps, and the requests that install, open, picture and remove an app.
// Nothing in one is code that runs: lamp makes each request itself, held to the guards here, as `DeviceHTTP`,
// `DeviceTLS` and `IntegrationRunner` hold them in Lamp's app.
//
// The guards: a request goes only to the address the device was found at, which must be on the home network and
// never this computer; no redirect is followed; over HTTPS the device's own certificate is kept the first time and a
// different one refused from then on, as SSH keeps a host's key; and what the person typed (a password) goes only to
// a device whose certificate is kept, and only in answer to the device's own request for it.

import { createHash, randomUUID, X509Certificate } from "node:crypto";
import dgram from "node:dgram";
import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, renameSync, rmSync, writeFileSync } from "node:fs";
import net from "node:net";
import { homedir, networkInterfaces } from "node:os";
import { basename, dirname, join } from "node:path";
import tls from "node:tls";
import { fileURLToPath } from "node:url";
import { bonjour } from "./mdns.mjs";
import { Problem, RESOURCES } from "./state.mjs";

export { bonjour, servicesIn } from "./mdns.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** Where lamp keeps what it knows of the person's devices: outside every app's folder, read by the person alone. */
export const devicesHome = () => process.env.LAMP_DEVICES_HOME || join(homedir(), ".lamp", "devices");

// MARK: Integrations

/** The integrations Lamp ships, as its app reads them. */
export function integrations() {
  const folder = join(RESOURCES, "Devices");
  return readdirSync(folder).filter((name) => name.endsWith(".json")).sort().map((name) => JSON.parse(readFileSync(join(folder, name), "utf8")));
}

export const integrationOf = (id) => integrations().find((integration) => integration.id === id);

/** Whether lamp puts a page on this integration's devices: where it packages pages for the device's host, the Xbox's so far. */
export const takesPages = (integration) => integration?.app?.declared?.wrap === "msix" && integration.app.declared.host === "webview2";

// MARK: Addresses

/** This computer's own addresses, read each time: they change as it moves between networks. */
export const ownAddresses = () => new Set(Object.values(networkInterfaces()).flat().map((entry) => entry.address.split("%")[0].toLowerCase()));

/** A private or link-local address: where a device in the person's home is. */
export function onNetwork(address) {
  if (net.isIPv4(address)) {
    const [a, b] = address.split(".").map(Number);
    return a === 10 || (a === 172 && b >= 16 && b <= 31) || (a === 192 && b === 168) || (a === 169 && b === 254);
  }
  if (net.isIPv6(address)) {
    const first = parseInt(address.split(":")[0] || "0", 16);
    return (first & 0xfe00) === 0xfc00 || (first & 0xffc0) === 0xfe80;
  }
  return false;
}

/** On the home network and not this computer itself, by loopback or by any of its own addresses; never a name, which could be made to lead anywhere. */
export const isPrivate = (address) => onNetwork(address) && !ownAddresses().has(address.toLowerCase());

/** This computer's address on the device's network: the one that shares the most of its leading numbers. */
function nearest(address) {
  const mine = Object.values(networkInterfaces()).flat().filter((entry) => entry.family === "IPv4" && !entry.internal).map((entry) => entry.address);
  const shared = (other) => { const a = other.split("."), b = String(address ?? "").split("."); let n = 0; while (n < 4 && a[n] === b[n]) n++; return n; };
  return mine.sort((a, b) => shared(b) - shared(a))[0];
}

// MARK: Looking

/** One SSDP answer's headers, as the device at `address` sent them. */
export function answerOf(text, address) {
  const headers = {};
  for (const line of text.split(/\r?\n/)) {
    const colon = line.indexOf(":");
    if (colon > 0) headers[line.slice(0, colon).trim().toLowerCase()] = line.slice(colon + 1).trim();
  }
  return { address, server: headers.server ?? "", location: headers.location, target: headers.st ?? "", usn: headers.usn ?? "" };
}

/** One SSDP search of the home network, for a few seconds: who answered, and what each said of itself. */
export function ssdp(target = "ssdp:all", seconds = 3) {
  return new Promise((done) => {
    const socket = dgram.createSocket({ type: "udp4", reuseAddr: true }), answers = new Map();
    const message = Buffer.from(`M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: ${target.replace(/[\r\n]/g, "")}\r\n\r\n`);
    const ask = () => socket.send(message, 1900, "239.255.255.250", () => {});
    socket.on("error", () => { try { socket.close(); } catch {} done([...answers.values()]); });
    socket.on("message", (data, from) => {
      const answer = answerOf(data.toString("utf8"), from.address);
      answers.set(`${answer.address} ${answer.target} ${answer.usn}`, answer);
    });
    socket.bind(0, () => {
      try { socket.setMulticastTTL(2); } catch {}
      ask(); ask();
      // Asked again partway through: a device that was asleep or busy misses the first search more often than not.
      setTimeout(ask, (seconds * 1000) / 2);
      setTimeout(() => { try { socket.close(); } catch {} done([...answers.values()]); }, seconds * 1000);
    });
  });
}

const sameWords = (a, b) => String(a).toLowerCase() === String(b).toLowerCase();
const holds = (text, part) => String(text ?? "").toLowerCase().includes(String(part).toLowerCase());

/**
 * The addresses an integration's device answers at, by what its `find` says: the search's answers for its search
 * target (with the server's words holding `contains`), a Bonjour service, or a page on the device holding words.
 */
export async function addressesOf(integration, answers, { reach = isPrivate, timeout = 4000 } = {}) {
  const addresses = new Set();
  for (const find of integration.find ?? []) {
    if (find.ssdp) {
      for (const answer of answers) {
        if ((find.ssdp === "ssdp:all" || sameWords(answer.target, find.ssdp)) && (!find.contains || holds(answer.server, find.contains))) addresses.add(answer.address);
      }
    }
    if (find.bonjour) for (const found of await bonjour(find.bonjour)) if (!find.contains || holds(found.name, find.contains)) addresses.add(found.address);
    if (find.http) {
      const asked = [...new Set(answers.map((answer) => answer.address))].filter(reach);
      const answered = await Promise.all(asked.map((address) => send({ port: find.http.port, path: find.http.path }, address, {}, { timeout, reach })
        .then((answer) => answer.ok && answer.text.includes(find.http.contains), () => false)));
      asked.forEach((address, index) => { if (answered[index]) addresses.add(address); });
    }
  }
  return [...addresses].filter(reach).sort();
}

/**
 * What the device at an address says of itself, read as its integration's `identity` says: its serial and model, and
 * its model's number, name and system's version where it says them. Null when it doesn't answer as one.
 */
export async function identify(integration, address, answers, { reach = isPrivate, timeout = 4000 } = {}) {
  const got = new Map();
  const read = async (how) => {
    if (!how) return null;
    let request = how.http;
    if (how.description) {
      // Where the device says its UPnP description is, in its answer to the integration's own search: only a
      // description on the device itself, over plain HTTP.
      request = null;
      for (const find of integration.find ?? []) {
        for (const answer of answers) {
          if (request || answer.address !== address || !find.ssdp || !(find.ssdp === "ssdp:all" || sameWords(answer.target, find.ssdp)) || !answer.location) continue;
          let url;
          try { url = new URL(answer.location); } catch { continue; }
          if (url.protocol === "http:" && url.hostname === address) request = { port: Number(url.port) || 80, path: (url.pathname || "/") + url.search };
        }
      }
    }
    if (!request) return null;
    const key = JSON.stringify(request);
    if (!got.has(key)) {
      const answer = await send(request, address, {}, { timeout, reach }).catch(() => null);
      if (answer?.ok) got.set(key, answer);
    }
    const answer = got.get(key), value = answer && (how.json ? jsonAt(answer.body, how.json) : how.xml ? xmlAt(answer.body, how.xml) : null)?.trim();
    if (how.contains && !holds(value, how.contains)) return null;
    return value || null;
  };
  const identity = integration.identity ?? {};
  const serial = await read(identity.id), model = serial && (await read(identity.model));
  if (!serial || !model) return null;
  return { integration: integration.id, address, serial, model, modelID: await read(identity.modelID), name: await read(identity.name), osVersion: await read(identity.osVersion) };
}

// The kinds of device that answer every search and that nobody makes apps for: a router and its parts.
const PLUMBING = ["InternetGatewayDevice", "WANDevice", "WFADevice"];

/**
 * A device that answered the search, read from the UPnP descriptions its answers point at, for one that no
 * integration knows. A device often answers for several services, each with a description of its own, and the first
 * to answer may say nothing of the device (a TV's streaming service answers a few bytes of "status=ok"), so each is
 * tried until one names it. Null when none does, and for a router. `get` is how a description is read; tests answer
 * with recorded ones.
 */
export async function describe(address, answers, { reach = isPrivate, timeout = 4000, get = (request) => send(request, address, {}, { timeout, reach }) } = {}) {
  const locations = [];
  for (const answer of answers) {
    let url;
    try { url = new URL(answer.location); } catch { continue; }
    if (url.hostname === address && !locations.includes(answer.location)) locations.push(answer.location);
  }
  for (const location of locations) {
    const url = new URL(location);
    if (url.protocol !== "http:") continue;
    const answer = await get({ port: Number(url.port) || 80, path: (url.pathname || "/") + url.search }).catch(() => null);
    if (!answer?.ok) continue;
    const said = (path) => xmlAt(answer.body, path) || null;
    const name = said("friendlyName"), maker = said("manufacturer") ?? "", model = said("modelName") ?? said("modelDescription") ?? "";
    if (PLUMBING.some((kind) => (said("deviceType") ?? "").includes(kind))) return null;
    if (!name || (!maker && !model)) continue;
    return { address, name, maker, model: model || maker, modelID: said("modelNumber") ?? "", discovery: answers.map((each) => `${each.target} (${each.server})`).join("; ") };
  }
  return null;
}

/**
 * One look at the home network for the integrations given: a search for everything (or the `answers` of one just
 * made), then each integration's devices found and read, all at once (where two find one address, the first given
 * has it), and with `unknown` the devices no integration knows, each read from its own description.
 */
export async function searchNetwork({ integrations: list = integrations(), seconds = 2.5, unknown = false, reach = isPrivate, answers } = {}) {
  answers ??= await ssdp("ssdp:all", seconds);
  const each = await Promise.all(list.map(async (integration) => {
    const read = [];
    for (const address of await addressesOf(integration, answers, { reach })) {
      const device = await identify(integration, address, answers, { reach });
      if (device) read.push(device);
    }
    return read;
  }));
  const found = [];
  for (const read of each) for (const device of read) if (!found.some((other) => other.address === device.address)) found.push(device);
  const others = new Map();
  if (unknown) {
    const taken = new Set(found.map((device) => device.address));
    for (const answer of answers) if (!taken.has(answer.address) && reach(answer.address)) others.set(answer.address, [...(others.get(answer.address) ?? []), answer]);
  }
  const described = (await Promise.all([...others].map(([address, said]) => describe(address, said, { reach })))).filter(Boolean);
  return { answers, found, unknown: described.sort((a, b) => a.name.localeCompare(b.name)) };
}

/**
 * The devices the integrations find on the network now, each read from its own answers as its integration says, with
 * the ones lamp keeps that didn't answer after them (`found: false`, at the address they were last at).
 */
export async function look({ seconds = 3, reach = isPrivate } = {}) {
  const shipped = integrations(), { found } = await searchNetwork({ integrations: shipped, seconds, reach });
  const devices = found.map((read) => {
    const integration = shipped.find((each) => each.id === read.integration);
    return { id: `${integration.id}:${read.serial}`, integration: integration.id, what: integration.kind, maker: integration.maker, model: read.model,
      name: read.name ?? `${integration.maker} ${read.model}`, address: read.address, found: true };
  });
  for (const device of devices) {
    const mine = kept(device.id);
    device.kept = !!mine;
    if (mine) keep({ ...mine, name: device.name, address: device.address });
    if (mine?.model) device.model = mine.model;
  }
  for (const mine of allKept()) if (!devices.some((device) => device.id === mine.id)) devices.push({ ...mine, kept: true, found: false });
  return devices;
}

// MARK: What's kept of a device

const folderOf = (id) => join(devicesHome(), createHash("sha256").update(id).digest("hex").slice(0, 16));
function readJSON(file) { try { return JSON.parse(readFileSync(file, "utf8")); } catch { return null; } }
function writeKept(id, name, value) {
  mkdirSync(folderOf(id), { recursive: true, mode: 0o700 });
  const file = join(folderOf(id), name);
  writeFileSync(file, JSON.stringify(value, null, 2), { mode: 0o600 });
  chmodSync(file, 0o600);
}

/** A device lamp set up: its record, kept once a setup step has passed on it. */
export const kept = (id) => readJSON(join(folderOf(id), "device.json"));
export const keep = (device) => writeKept(device.id, "device.json", { id: device.id, integration: device.integration, name: device.name, model: device.model, address: device.address, passed: device.passed ?? [], reads: device.reads ?? {} });
export function allKept() {
  let names = [];
  try { names = readdirSync(devicesHome()); } catch {}
  return names.map((name) => readJSON(join(devicesHome(), name, "device.json"))).filter(Boolean).sort((a, b) => a.name.localeCompare(b.name));
}

/** Lets a device go: its record, its certificates and what was typed for it. */
export const forget = (id) => rmSync(folderOf(id), { recursive: true, force: true });

/** What the person typed for a device's setup (a password), kept beside its record and read by them alone. */
export const fields = {
  read: (id) => readJSON(join(folderOf(id), "fields.json")) ?? {},
  save(id, key, value) { writeKept(id, "fields.json", { ...fields.read(id), [key]: value }); },
  remove(id, key) { const all = fields.read(id); delete all[key]; writeKept(id, "fields.json", all); },
};

// MARK: HTTPS

const fingerprintOf = (certificate) => createHash("sha256").update(certificate).digest("hex");

const CHANGED = "this isn't the device lamp set up at that address: its certificate has changed. If you reset it or turned its developer mode on again, forget it (lamp devices forget) and add it again.";
const UNSAVED = "lamp couldn't keep this device's certificate on this computer, so it sent nothing to it";

/** Whether `root` signed `leaf`: the leaf checked against that root alone. */
function signs(root, leaf) {
  try {
    const signer = new X509Certificate(root), signed = new X509Certificate(leaf);
    return signed.checkIssued(signer) && signed.verify(signer.publicKey);
  } catch { return false; }
}

/** A certificate as a device serves it, PEM or DER, as DER; null when it isn't one. */
function certificateFrom(bytes) {
  const text = bytes.toString("latin1");
  let certificate = bytes;
  if (text.includes("-----BEGIN CERTIFICATE-----")) {
    const body = text.split("-----BEGIN CERTIFICATE-----")[1]?.split("-----END CERTIFICATE-----")[0] ?? "";
    certificate = Buffer.from(body.replace(/\s+/g, ""), "base64");
  }
  try { new X509Certificate(certificate); return certificate; } catch { return null; }
}

/**
 * One device's kept certificates: the one it showed first, by port, and, for a device that makes itself a new one
 * from a root of its own (an Xbox's Device Portal does, whenever it restarts), that root, under "root:<port>". A
 * certificate other than the kept one is taken only when the kept root signed it, and is kept in its place.
 */
export const pinsOf = (id) => pinsAt(join(folderOf(id), "certificates.json"));

/** The same, kept in a file the caller names: Lamp's app keeps each device's in its own folder for the device. */
export function pinsAt(file) {
  // A store that's there but isn't one (not JSON, not names with words for values) is never read as empty.
  const read = () => {
    if (!existsSync(file)) return {};
    const pins = readJSON(file);
    return pins && typeof pins === "object" && !Array.isArray(pins) && Object.values(pins).every((value) => typeof value === "string") ? pins : null;
  };
  // Written whole or not at all, for the person alone to read.
  const write = (pins) => {
    mkdirSync(dirname(file), { recursive: true, mode: 0o700 });
    const beside = `${file}.writing`;
    writeFileSync(beside, JSON.stringify(pins, null, 2), { mode: 0o600 });
    renameSync(beside, file);
  };
  return {
    /** Why a certificate isn't taken, or null when it is: it's the one kept, or the first, kept now. It fails closed. */
    admit(fingerprint, port, certificate) {
      const pins = read();
      if (!pins) return UNSAVED;
      if (pins[port] === fingerprint) return null;
      if (pins[port]) {
        const root = pins[`root:${port}`];
        if (!certificate || !root || !signs(Buffer.from(root, "base64"), certificate)) return CHANGED;
      }
      try { write({ ...pins, [port]: fingerprint }); } catch { return UNSAVED; }
      return null;
    },
    root: (port) => { const root = read()?.[`root:${port}`]; return root ? Buffer.from(root, "base64") : null; },
    /** Keeps the device's root for a port, only when it signed the certificate kept there, so the root is the device's own. */
    keepRoot(root, leaf, port) {
      const pins = read();
      if (!pins || pins[port] !== fingerprintOf(leaf) || pins[`root:${port}`] || !signs(root, leaf)) return false;
      write({ ...pins, [`root:${port}`]: root.toString("base64") });
      return true;
    },
  };
}

// MARK: Placeholders

// The values lamp puts into an integration's requests: `{name}`, `{field:<key>}`, `{cookie:<name>}`, `{base64:<name>}`.
// A word in braces and nothing else, so a brace that opens JSON is the template's own text.
const PLACEHOLDER = /\{([A-Za-z][A-Za-z0-9]*(?::[A-Za-z0-9-]+)?)\}/g;
const SAFE = /^[A-Za-z0-9._\-:/@+=,]*$/;

/** What's secret among the values: what the person typed for the device, and what a maker's sign-in gave for it. */
const isSecret = (name) => name.startsWith("field:") || name === "signIn";

/**
 * The template with each placeholder filled, as `Placeholders` holds an integration to in Lamp's app. A value outside
 * the safe alphabet is refused, except a secret, which only reaches places that are encoded or apart from the address
 * (a sign-in, a form, a header, a body) and is never put in base64; Lamp's own public key, which has spaces; and text
 * being typed on the device, which may be anything and so goes only in a form, a body, or a path, there encoded down
 * to letters and digits. In a path every value is percent-encoded so it can't change the path.
 */
export function fill(template, values, place) {
  return template.replace(PLACEHOLDER, (whole, name) => {
    const inner = name.startsWith("base64:") ? name.slice(7) : null;
    if (inner !== null && isSecret(inner)) throw new Problem(`{${name}} must be base64 of a value that isn't secret`);
    const value = inner !== null ? (values[inner] === undefined ? undefined : Buffer.from(values[inner]).toString("base64")) : values[name];
    if (value === undefined) throw new Problem(`lamp has nothing to put in {${name}}`);
    const secret = isSecret(name), text = name === "text";
    if (secret && !["auth", "form", "header", "body"].includes(place)) throw new Problem(`{${name}} can't go in a ${place}: ${name === "signIn" ? "a sign-in" : "what the person types"} goes only in a sign-in, a form, a header or a body`);
    if (name.startsWith("cookie:") && place !== "header") throw new Problem(`{${name}} goes only in a header`);
    if (text && !["path", "form", "body"].includes(place)) throw new Problem("{text} goes only in a path, a form or a body");
    if (!secret && !text && name !== "sshKey" && (!SAFE.test(value) || value.length > 512)) throw new Problem(`the value for {${name}} has characters lamp doesn't send to a device`);
    if (text && place === "path") return [...Buffer.from(value)].map((byte) => (/[A-Za-z0-9]/.test(String.fromCharCode(byte)) ? String.fromCharCode(byte) : `%${byte.toString(16).toUpperCase().padStart(2, "0")}`)).join("");
    return place === "path" ? encodeURIComponent(value).replace(/%2F/g, "/").replace(/%3A/g, ":").replace(/%40/g, "@").replace(/%2C/g, ",") : value;
  });
}

const namesIn = (template) => [...String(template ?? "").matchAll(PLACEHOLDER)].map((match) => match[1]);

/** Whether a request carries a secret or a sign-in, which goes only where lamp knows the device. */
function carriesSecret(request) {
  if (request.auth) return true;
  return [request.path, request.body, ...Object.values(request.headers ?? {}), ...Object.values(request.form ?? {})].flatMap(namesIn).some(isSecret);
}

function pathProblem(path) {
  if (!path.startsWith("/") || path.startsWith("//")) return "must start with one /";
  if (path.includes("..")) return "can't hold ..";
  if (path.includes("://") || path.includes("@") || path.includes("#") || path.includes("\\")) return "must be a path on the device, not an address";
  if (/[\s\u0000-\u001f\u007f]/.test(path)) return "can't hold spaces";
  return null;
}

// MARK: One request

// Answers are cut off here: a device's answers are small, and a picture is a few megabytes.
const ANSWER_LIMIT = 16 << 20;

/**
 * Makes one request of an integration to a device, with lamp's values filled in. `session` remembers, for one
 * sequence of requests, that the device has asked for the sign-in, so the requests after it carry it and a package
 * isn't sent twice.
 */
export async function send(request, address, values, { files = {}, pins, timeout = 30_000, session = {}, reach = isPrivate, stopped } = {}) {
  const https = request.https === true;
  if (https && !pins && carriesSecret(request)) throw new Problem("lamp sends a password over HTTPS only to a device whose certificate it keeps");
  if (!reach(address)) throw new OffNetwork(`lamp only talks to devices on your own network, and ${address} isn't one`);
  if (!Number.isInteger(request.port) || request.port < 1 || request.port > 65535) throw new Problem(`${request.port} isn't a port`);
  const path = fill(request.path, values, "path"), problem = pathProblem(path.split("?")[0]);
  if (problem) throw new Problem(`the path ${problem}`);
  // lamp writes the request itself, so nothing in it may end a line or start another: the path whole, each header.
  if (!/^[\x21-\x7e]+$/.test(path)) throw new Problem("the path can't hold spaces");
  const method = (request.method ?? "GET").toUpperCase(), headers = {};
  if (!/^[A-Z]{1,16}$/.test(method)) throw new Problem(`${method} isn't a way to ask a device`);
  for (const [name, value] of Object.entries(request.headers ?? {})) {
    if (name.toLowerCase() === "host") continue;
    const filled = fill(value, values, "header");
    if (!/^[A-Za-z0-9!#$%&'*+.^_`|~-]+$/.test(name) || /[\r\n\0]/.test(filled)) throw new Problem(`the header ${name} can't be sent as it is`);
    headers[name] = filled;
  }
  let body = null;
  if (request.body != null) body = Buffer.from(fill(request.body, values, "body"));
  if (request.form) {
    const boundary = "lamp-" + randomUUID(), parts = [];
    for (const [name, value] of Object.entries(request.form).sort(([a], [b]) => (a < b ? -1 : 1))) {
      parts.push(Buffer.from(`--${boundary}\r\n`));
      if (value === "@{package}" || value === "@{certificate}") {
        const file = files[value.slice(2, -1)];
        if (!file || !existsSync(file)) throw new Problem(`there's no ${value.slice(2, -1)} to send yet`);
        // A field named like a file ("app.msix") is sent under that name: some devices go by the file's name.
        parts.push(Buffer.from(`Content-Disposition: form-data; name="${name}"; filename="${name.includes(".") ? name : basename(file)}"\r\nContent-Type: application/octet-stream\r\n\r\n`), readFileSync(file));
      } else {
        parts.push(Buffer.from(`Content-Disposition: form-data; name="${name}"\r\n\r\n`), Buffer.from(fill(value, values, "form")));
      }
      parts.push(Buffer.from("\r\n"));
    }
    parts.push(Buffer.from(`--${boundary}--\r\n`));
    body = Buffer.concat(parts);
    headers["Content-Type"] = `multipart/form-data; boundary=${boundary}`;
  }
  // Some devices refuse a POST that says nothing of its length (Device Portal answers 411), so an empty one says 0.
  if (!body && ["POST", "PUT"].includes(method)) body = Buffer.alloc(0);
  if (body) headers["Content-Length"] = String(body.length);

  const once = async (authorization) => {
    if (stopped?.aborted) throw new Problem("stopped");
    const { socket, certificate } = https ? await connect(address, request.port, pins, timeout) : await plain(address, request.port, timeout);
    // Stopped by whoever asked (`stopped`, an AbortSignal): the connection is let go, whatever was under way on it.
    const stop = () => socket.destroy(new Problem("stopped"));
    stopped?.addEventListener("abort", stop, { once: true });
    const host = `${address.includes(":") ? `[${address}]` : address}:${request.port}`;
    let answer;
    try { answer = await exchange(socket, { method, path, host, headers: authorization ? { ...headers, Authorization: authorization } : headers, body, timeout, address }); }
    finally { stopped?.removeEventListener("abort", stop); }
    const cookies = {};
    for (const cookie of answer.headers["set-cookie"] ?? []) {
      const pair = cookie.split(";")[0], equals = pair.indexOf("=");
      if (equals > 0) cookies[pair.slice(0, equals).trim()] = pair.slice(equals + 1).trim();
    }
    return { status: answer.status, ok: answer.status >= 200 && answer.status < 300, body: answer.body, text: answer.body.toString("utf8"), cookies, certificate,
      asks: (answer.headers["www-authenticate"] ?? []).join(", ") };
  };

  // The sign-in goes only in answer to the device's own request for it, once, with the scheme the integration
  // declared: a password to a device that asks for it plainly, and to one that asks for a digest never the password
  // itself, only what the device's own challenge makes of it.
  if (!request.auth) return once(null);
  const user = request.auth.user, password = fill(request.auth.password, values, "auth"), door = `${address}:${request.port}`;
  // A session that came back from Lamp's app as JSON holds its doors as a list.
  if (!(session.asked instanceof Set)) session.asked = new Set(Array.isArray(session.asked) ? session.asked : []);
  if (request.auth.digest) {
    const first = await once(null), challenge = digestChallenge(first.asks);
    return first.status === 401 && challenge ? once(digestAnswer(challenge, { user, password, method, path })) : first;
  }
  const basic = "Basic " + Buffer.from(`${user}:${password}`).toString("base64");
  if (session.asked.has(door)) return once(basic);
  const first = await once(null);
  if (first.status !== 401 || !/(^|,)\s*basic\b/i.test(first.asks)) return first;
  session.asked.add(door);
  return once(basic);
}

// MARK: The request itself

/** A connection to the device with nothing over it. */
function plain(address, port, timeout) {
  return new Promise((done, failed) => {
    const socket = net.connect({ host: address, port, timeout });
    socket.once("connect", () => done({ socket, certificate: null }));
    socket.once("timeout", () => socket.destroy(timedOut()));
    socket.once("error", (error) => failed(error instanceof Problem ? error : new Away(address, error)));
  });
}

/** An answer's head: its status and its headers, each name in small letters with every value it was given. */
function headOf(text) {
  const [first, ...lines] = text.split("\r\n"), status = Number(/^HTTP\/1\.[01] (\d{3})/.exec(first)?.[1]);
  if (!status) return null;
  const headers = {};
  for (const line of lines) {
    const colon = line.indexOf(":");
    if (colon > 0) (headers[line.slice(0, colon).trim().toLowerCase()] ??= []).push(line.slice(colon + 1).trim());
  }
  return { status, headers };
}

/** A body sent in chunks, put back together; null while its last chunk hasn't come. */
function unchunked(bytes) {
  const parts = [];
  for (let at = 0; ;) {
    const line = bytes.indexOf("\r\n", at);
    if (line < 0) return null;
    const size = parseInt(bytes.toString("latin1", at, line).split(";")[0].trim(), 16);
    if (!Number.isInteger(size) || size < 0) throw new Problem("the device's answer couldn't be read");
    if (size === 0) return Buffer.concat(parts);
    if (bytes.length < line + 2 + size + 2) return null;
    parts.push(bytes.subarray(line + 2, line + 2 + size));
    at = line + 2 + size + 2;
  }
}

/**
 * One request on a connection lamp opened, and its answer read to its end: HTTP/1.1 written out by hand, so the
 * request goes down the very connection whose certificate was just checked, the same way on Node and on Bun (whose
 * own client can't be handed a connection). No redirect is followed: an answer that names another place is the answer.
 */
function exchange(socket, { method, path, host, headers, body, timeout, address }) {
  return new Promise((done, failed) => {
    let settled = false, head = null, kept = [], size = 0, pending = Buffer.alloc(0);
    const finish = (error, answer) => {
      if (settled) return;
      settled = true;
      socket.destroy();
      if (error) failed(error instanceof Problem ? error : new Away(address, error)); else done(answer);
    };
    const tooBig = () => finish(new Problem("the device's answer was bigger than lamp takes"));
    /** The answer, once all of it is here; `ended` says the device has closed its side. */
    const read = (ended) => {
      while (!head) {
        const end = pending.indexOf("\r\n\r\n");
        if (end < 0) { if (pending.length > 65536) tooBig(); else if (ended) finish(Object.assign(new Error("cut short"), { code: "ECONNRESET" })); return; }
        const parsed = headOf(pending.toString("latin1", 0, end));
        if (!parsed) return finish(new Problem("the device's answer couldn't be read"));
        pending = pending.subarray(end + 4);
        // A word to go on (100 Continue) isn't the answer: the answer follows it.
        if (parsed.status >= 100 && parsed.status < 200 && parsed.status !== 101) continue;
        head = parsed;
        kept = [pending];
        size = pending.length;
      }
      const none = method === "HEAD" || head.status === 204 || head.status === 304;
      const chunked = (head.headers["transfer-encoding"] ?? []).join(",").toLowerCase().includes("chunked");
      const length = Number(head.headers["content-length"]?.[0]);
      if (size > ANSWER_LIMIT + 65536) return tooBig();
      let bytes = null;
      if (none) bytes = Buffer.alloc(0);
      else if (chunked) { try { bytes = unchunked(Buffer.concat(kept)); } catch (error) { return finish(error); } }
      else if (Number.isInteger(length) && length >= 0) { if (size >= length) bytes = Buffer.concat(kept).subarray(0, length); }
      else if (ended) bytes = Buffer.concat(kept);
      if (bytes && bytes.length > ANSWER_LIMIT) return tooBig();
      if (bytes) return finish(null, { status: head.status, headers: head.headers, body: bytes });
      if (ended) finish(Object.assign(new Error("cut short"), { code: "ECONNRESET" }));
    };
    socket.setTimeout(timeout, () => finish(timedOut()));
    socket.on("data", (chunk) => {
      if (head) { kept.push(chunk); size += chunk.length; } else pending = Buffer.concat([pending, chunk]);
      read(false);
    });
    socket.on("end", () => read(true));
    socket.on("close", () => read(true));
    socket.on("error", (error) => finish(error));
    const lines = [`${method} ${path} HTTP/1.1`, `Host: ${host}`, ...Object.entries(headers).map(([name, value]) => `${name}: ${value}`), "Connection: close", "", ""];
    socket.write(Buffer.from(lines.join("\r\n"), "latin1"));
    if (body?.length) socket.write(body);
  });
}

// MARK: A digest sign-in

const quoted = (value) => String(value).replaceAll("\\", "\\\\").replaceAll('"', '\\"');

/** What a device asks of a digest sign-in, from its challenge; null when the challenge isn't one lamp answers. */
function digestChallenge(asks) {
  const at = /(^|,)\s*digest\s/i.exec(asks);
  if (!at) return null;
  const challenge = {};
  for (const [, name, inQuotes, bare] of asks.slice(at.index + at[0].length).matchAll(/([A-Za-z]+)\s*=\s*(?:"((?:[^"\\]|\\.)*)"|([^\s,]+))/g)) {
    challenge[name.toLowerCase()] ??= inQuotes !== undefined ? inQuotes.replace(/\\(.)/g, "$1") : bare;
  }
  const algorithm = (challenge.algorithm ?? "MD5").toUpperCase();
  if (!challenge.realm || !challenge.nonce || !["MD5", "SHA-256"].includes(algorithm)) return null;
  const ways = (challenge.qop ?? "").split(",").map((way) => way.trim().toLowerCase()).filter(Boolean);
  if (ways.length && !ways.includes("auth")) return null;
  return { ...challenge, algorithm, qop: ways.length ? "auth" : null };
}

/** The Authorization header that answers a digest challenge (RFC 7616): the password itself is never in it. */
function digestAnswer(challenge, { user, password, method, path }) {
  const hash = (text) => createHash(challenge.algorithm === "MD5" ? "md5" : "sha256").update(text).digest("hex");
  const cnonce = randomUUID().replaceAll("-", ""), count = "00000001";
  const one = hash(`${user}:${challenge.realm}:${password}`), two = hash(`${method}:${path}`);
  const response = challenge.qop ? hash(`${one}:${challenge.nonce}:${count}:${cnonce}:auth:${two}`) : hash(`${one}:${challenge.nonce}:${two}`);
  const parts = [`username="${quoted(user)}"`, `realm="${quoted(challenge.realm)}"`, `nonce="${quoted(challenge.nonce)}"`, `uri="${path}"`, `response="${response}"`, `algorithm=${challenge.algorithm}`];
  if (challenge.qop) parts.push("qop=auth", `nc=${count}`, `cnonce="${cnonce}"`);
  if (challenge.opaque !== undefined) parts.push(`opaque="${quoted(challenge.opaque)}"`);
  return "Digest " + parts.join(", ");
}

/** The device's certificate isn't one lamp takes: waiting won't mend it. */
export class Refused extends Problem {
  constructor(why) {
    super(why);
    this.kind = why === CHANGED ? "changed" : "unsaved";
  }
}

/** The address isn't a device on the person's own network: nothing is sent there. */
export class OffNetwork extends Problem {}

/** The device didn't answer, or let the connection go: it's off, asleep, somewhere else on the network, or busy. */
export class Away extends Problem {
  constructor(address, cause) {
    super(`the device at ${address} ${cause?.timedOut ? "didn't answer in time" : "isn't answering"}: make sure it's on, then try again`);
    this.code = cause?.code;
    this.timedOut = !!cause?.timedOut;
  }
}
const timedOut = () => Object.assign(new Error("timed out"), { timedOut: true });

/** A connection to the device over TLS, taken only once its certificate is the one kept (or the first, kept now). */
function connect(address, port, pins, timeout) {
  return new Promise((done, failed) => {
    const socket = tls.connect({ host: address, port, rejectUnauthorized: false, timeout });
    socket.once("secureConnect", () => {
      const certificate = socket.getPeerX509Certificate?.()?.raw ?? socket.getPeerCertificate(true)?.raw;
      if (!certificate) { socket.destroy(); return failed(new Problem(`${address} showed no certificate`)); }
      // Kept and compared before anything is sent; without pins (a read while finding) nothing secret is in the request.
      const refused = pins?.admit(fingerprintOf(certificate), String(port), certificate);
      if (refused) { socket.destroy(); return failed(new Refused(refused)); }
      done({ socket, certificate });
    });
    socket.once("timeout", () => socket.destroy(timedOut()));
    socket.once("error", (error) => failed(error instanceof Problem ? error : new Away(address, error)));
  });
}

/** Whether the device accepts a connection on a port, within a few seconds. Connects and closes; sends nothing. */
export function answersOn(address, port, { timeout = 3000, reach = isPrivate } = {}) {
  if (!reach(address)) return Promise.resolve(false);
  return new Promise((done) => {
    const socket = net.connect({ host: address, port, timeout });
    const end = (open) => { socket.destroy(); done(open); };
    socket.once("connect", () => end(true)).once("timeout", () => end(false)).once("error", () => end(false));
  });
}

// MARK: Reading a value out of an answer

const textOf = (value) => (value === null || value === undefined ? undefined : typeof value === "string" ? value : typeof value === "object" ? JSON.stringify(value) : String(value));

/** Every value at a dotted JSON path ("Platform", "items.0.id"), where `*` stands for each element of a list. */
export function jsonValues(body, path) {
  let values;
  try { values = [JSON.parse(body.toString("utf8"))]; } catch { return []; }
  for (const part of path.split(".")) {
    values = values.flatMap((value) => {
      if (part === "*") return Array.isArray(value) ? value : [];
      if (Array.isArray(value)) return /^\d+$/.test(part) && Number(part) < value.length ? [value[Number(part)]] : [];
      return value && typeof value === "object" && part in value ? [value[part]] : [];
    });
  }
  return values.map(textOf).filter((text) => text !== undefined);
}
export const jsonAt = (body, path) => jsonValues(body, path)[0];

const ENTITIES = { amp: "&", lt: "<", gt: ">", quot: '"', apos: "'" };
const plainText = (text) => text.replace(/&(#x?[0-9a-fA-F]+|[a-z]+);/g, (whole, name) =>
  (name[0] === "#" ? String.fromCodePoint(name[1] === "x" ? parseInt(name.slice(2), 16) : Number(name.slice(1))) : ENTITIES[name] ?? whole));

/** The text of the first element at an XML path ("model-name", or "device/modelName" for one inside another). */
export function xmlAt(body, path) {
  const wanted = path.split("/"), stack = [];
  const matches = () => stack.length >= wanted.length && wanted.every((name, index) => stack[stack.length - wanted.length + index] === name);
  const token = /<!--[\s\S]*?-->|<\?[\s\S]*?\?>|<!\[CDATA\[([\s\S]*?)\]\]>|<!(?:[^>]*)>|<\/([^\s>]+)\s*>|<([^\s>/]+)(?:\s[^>]*?)?(\/?)>|([^<]+)/g;
  let text = "";
  for (const [, cdata, closed, opened, empty, plain] of body.toString("utf8").matchAll(token)) {
    if (opened) {
      stack.push(opened);
      if (matches()) text = "";
      if (empty) { if (matches()) return ""; stack.pop(); }
    } else if (closed) {
      if (matches()) return text.trim();
      stack.pop();
    } else if (matches()) text += cdata ?? plainText(plain ?? "");
  }
  return undefined;
}

/** A device's answer as plain words: an HTML page's text without its tags and scripts, cut to a few lines. */
export function plainAnswer(answer) {
  const text = answer.replace(/<(script|style)[^>]*>[\s\S]*?<\/\1>/g, " ").replace(/<[^>]+>/g, "\n");
  return text.split(/\r?\n/).map((line) => line.trim()).filter(Boolean).join("\n").slice(0, 1500);
}

// MARK: Running an integration

/** The device turned the sign-in away: waiting won't mend it, the person has to type it again. */
export class Rejected extends Problem {
  constructor() { super("the device rejected the sign-in. Check the user name and password, then try again"); }
}

/** The device was still at what it was sent when lamp stopped waiting: a moment later it may be done. */
export class StillWorking extends Problem {}

/**
 * Runs an integration's setup checks and its sequences (install, launch, look…) on one device. `pause` and `reach`
 * are how it waits and what it takes for an address on the home network, which a test gives its own.
 */
export class Runner {
  /**
   * `values` and `pins`, when given, are another keeper's (Lamp's app keeps what the person typed for a device in its
   * own store, and names the file its certificates are kept in); `keyFile` is where a key the device gives is kept,
   * and `stopped` ends the run between requests once whoever asked no longer wants it.
   */
  constructor({ integration, device, onWaiting = () => {}, pause = sleep, reach = isPrivate, values, pins, keyFile, stopped }) {
    Object.assign(this, { integration, device, onWaiting, pause, reach, given: values, pins: pins ?? pinsOf(device.id), keyFile, stopped });
  }

  #stillWanted() { if (this.stopped?.aborted) throw new Problem("stopped"); }

  get address() {
    if (!this.device.address || !this.reach(this.device.address)) throw new Problem(`lamp doesn't know where ${this.device.name} is on your network: make sure it's on, then run lamp devices`);
    return this.device.address;
  }

  /** lamp's values for this device, and the caller's (an app's names, whether it's a game), or those given whole. */
  values(extra = {}) {
    if (this.given) return { ...this.given, ...extra };
    const values = { ...extra, address: this.device.address, deviceID: this.device.id.split(":").slice(1).join(":") };
    const mine = nearest(this.device.address);
    if (mine) values.mac = mine;
    for (const [key, value] of Object.entries(fields.read(this.device.id))) values[`field:${key}`] = value;
    for (const [step, value] of Object.entries(kept(this.device.id)?.reads ?? {})) values[`read:${step}`] = value;
    return values;
  }

  #send(request, values, more = {}) {
    return send(request, this.address, values, { pins: this.pins, reach: this.reach, stopped: this.stopped, ...more });
  }

  /**
   * The first time the device's certificate is kept for a port, the root the integration says signs it is read from
   * the device over that same connection and kept with it, so a certificate the device makes later is still known as
   * its own.
   */
  async #learnRoot(request, answer) {
    const path = this.integration.certificateRoot, pins = this.pins;
    if (!request.https || !path || !answer.certificate || pins.root(String(request.port))) return;
    const got = await this.#send({ port: request.port, path, https: true }, {}).catch(() => null);
    const root = got?.ok && certificateFrom(got.body);
    if (root) pins.keepRoot(root, answer.certificate, String(request.port));
  }

  /**
   * Runs a sequence in order, stopping at the first failure. A setting it changes only for itself (`restore`) is put
   * back as it ends; or, given `changed`, once the caller is done (`putBack`): an Xbox settles an installed package's
   * type only as it's opened, after the install's own sequence.
   */
  async run(sequence, { extra = {}, files = {}, changed, cookies = {} } = {}) {
    const settings = changed ?? [];
    try { return await this.#run(sequence, extra, files, settings, cookies); } finally { if (!changed) await this.putBack(settings); }
  }

  /**
   * Each setting as it was before a sequence changed it, last changed first, sent with the cookies its change went
   * with (a CSRF token). A device that can't be reached by then keeps what the sequence set: there's nothing more to
   * do from here. Answers the settings it couldn't put back.
   */
  async putBack(changed) {
    const missed = [];
    for (const restore of changed.splice(0).reverse()) {
      const back = { ...restore.request, body: JSON.stringify({ [restore.request.restore]: restore.was }) };
      const values = { ...this.values(), ...Object.fromEntries(Object.entries(restore.cookies ?? {}).map(([name, value]) => [`cookie:${name}`, value])) };
      // Put back even once the run was stopped: a setting left changed is the device's for good. Each is given a while, not forever.
      const answer = await this.#send(back, values, { session: { ...(restore.session ?? {}) }, stopped: undefined, timeout: 15_000 }).catch(() => null);
      if (!answer?.ok) missed.push(`lamp couldn't set ${restore.request.path} on ${this.device.name} back to ${restore.was}`);
    }
    return missed;
  }

  async #run(sequence, extra, files, changed, given) {
    const outcome = { answers: [] }, cookies = { ...given }, session = {};
    for (const action of sequence) {
      this.#stillWanted();
      const values = { ...this.values(extra), ...Object.fromEntries(Object.entries(cookies).map(([name, value]) => [`cookie:${name}`, value])) };
      const request = action.http;
      if (action.wait) { await this.pause(Math.min(Math.max(action.wait, 1), 30) * 1000); continue; }
      if (action.probe) {
        if (!(await present(this.address, action.probe, { reach: this.reach }))) throw new Problem(`${this.device.name} didn't answer (${action.probe})`);
        continue;
      }
      if (!request) throw new Problem(`${this.device.name}'s integration asks for something lamp's command line doesn't do (${Object.keys(action).join(", ")})`);
      // A setting changed only for this sequence: what it is now, to put back after. Read as it's written, with the
      // same sign-in and headers, but for a cookie the device sets only now.
      if (request.restore) {
        const headers = Object.fromEntries(Object.entries(request.headers ?? {}).filter(([name, value]) => name.toLowerCase() !== "content-type" && !value.includes("{cookie:")));
        const now = await this.#send({ port: request.port, path: request.path, headers, auth: request.auth, https: request.https }, values, { session });
        const was = now.ok ? jsonAt(now.body, request.restore) : undefined;
        if (was === undefined || !SAFE.test(was)) throw new Problem(`${this.device.name} didn't say what ${request.path} is set to, so lamp left it as it was`);
        // Put back only once, as it was first: a sequence tried again finds its own change there.
        const setting = `${request.port}${request.path}`;
        let wanted;
        try { wanted = jsonAt(Buffer.from(fill(request.body ?? "", values, "body")), request.restore); } catch {}
        if (!changed.some((restore) => `${restore.request.port}${restore.request.path}` === setting) && was !== wanted) changed.push({ request, was, cookies: { ...cookies }, session: { asked: [...(session.asked ?? [])] } });
      }
      const transfer = () => this.#send(request, values, { files, session });
      let asked = Date.now(), answer = await transfer();
      // A device still working on what it was sent says so with 204 until it's done.
      if (request.poll) {
        const until = Date.now() + Math.min(Math.max(request.poll, 2), 600) * 1000;
        while (answer.status === 204 && Date.now() < until) {
          this.#stillWanted();
          this.onWaiting();
          await this.pause(2000);
          asked = Date.now();
          answer = await transfer();
        }
        if (answer.status === 204) throw new StillWorking(`${this.device.name} was still working on ${request.path} after ${request.poll} seconds`);
      }
      Object.assign(cookies, answer.cookies);
      if (request.auth && answer.status === 401) throw new Rejected();
      if (answer.ok) await this.#learnRoot(request, answer);
      if (!answer.ok) {
        const said = plainAnswer(answer.text);
        throw new Problem(`${this.device.name} answered ${answer.status} to ${request.path}${said ? ": " + said : ""}`);
      }
      if (request.expect) {
        // Asked again while the answer doesn't say it yet, for up to `until` seconds, counting the time each request
        // took as well as each pause.
        let spent = (Date.now() - asked) / 1000;
        while (!meets(request.expect, answer, values)) {
          if (!request.until) throw new Problem(`${this.device.name} said: ${plainAnswer(answer.text)}`);
          if (spent >= request.until) throw new StillWorking(`${this.device.name} still wasn't ready at ${request.path} after ${request.until} seconds`);
          this.#stillWanted();
          this.onWaiting();
          await this.pause(2000);
          asked = Date.now();
          answer = await transfer();
          spent += 2 + (Date.now() - asked) / 1000;
          Object.assign(cookies, answer.cookies);
          if (!answer.ok) throw new Problem(`${this.device.name} answered ${answer.status} to ${request.path}`);
        }
      }
      if (request.keep === "picture") outcome.picture = answer.body;
      else if (request.keep === "screen") outcome.screen = answer.body.subarray(0, 512 << 10).toString("utf8");
      else if (request.keep === "log") outcome.log = answer.body.subarray(Math.max(0, answer.body.length - (256 << 10))).toString("utf8");
      else if (request.keep === "key") {
        // A key the device gives this computer to sign in to it with, kept where the caller says, for its person alone.
        if (!this.keyFile) throw new Problem(`${this.device.name} gave a key, and lamp has nowhere to keep it`);
        mkdirSync(dirname(this.keyFile), { recursive: true, mode: 0o700 });
        writeFileSync(this.keyFile, answer.body, { mode: 0o600 });
        chmodSync(this.keyFile, 0o600);
      } else outcome.answers.push(answer.text.slice(0, 64 << 10));
    }
    outcome.cookies = cookies;
    return outcome;
  }

  /**
   * Opens an app just put on the device: `launch`, and then, where the bridge says how (`running`), a check that it's
   * running. A device only just done installing a package can refuse to open it for a while, or take the launch and
   * not open the app yet; so a refused launch is asked again after a pause that grows, and one that didn't open is
   * launched again, until `tries` launches have gone. Answers whether it opened, and what the device last refused with.
   */
  async open(launch, running, { extra = {}, changed, tries = 8 } = {}) {
    let launched = false, refused = null, wait = 2000;
    for (let attempt = 1; attempt <= tries; attempt++) {
      try {
        await this.run(launch, { extra, changed });
        launched = true;
        if (!running?.length) return { opened: true };
        try { await this.run(running, { extra, changed }); return { opened: true }; } catch (error) { if (!(error instanceof Problem) || error instanceof Away) throw error; }
      } catch (error) {
        if (!(error instanceof Problem) || error instanceof Rejected || error instanceof Away) throw error;
        refused = error.message;
      }
      if (attempt === tries) break;
      this.#stillWanted();
      this.onWaiting();
      await this.pause(wait);
      wait = Math.min(wait * 2, 8000);
    }
    return { opened: false, launched, refused };
  }

  /**
   * What a check of these conditions finds, told apart the way a setup needs it told: `holds` (with the first value
   * read), `waiting` (the device answered otherwise, or the person hasn't typed what's needed yet), `away` (the device
   * didn't answer), or `rejected` (it answered, but its certificate isn't the one kept, or it turned the sign-in away).
   * `needs` names the field a condition waits for.
   */
  async evaluate(conditions) {
    const values = this.values(), waiting = `Waiting for ${this.device.name}…`;
    let read;
    for (const condition of conditions ?? []) {
      if (condition.field) {
        if (!values[`field:${condition.field}`]) return { verdict: "waiting", why: "Waiting for what you type.", needs: condition.field };
      } else if (condition.signedIn) {
        if (!values.signIn) return { verdict: "waiting", why: "Waiting for you to sign in." };
      } else if (condition.tcp) {
        if (!this.device.address || !(await answersOn(this.device.address, condition.tcp, { reach: this.reach }))) return { verdict: "away", why: waiting };
      } else if (condition.http) {
        let answer;
        try {
          answer = await this.#send(condition.http, values);
          if (answer.ok) await this.#learnRoot(condition.http, answer);
        } catch (error) {
          if (error instanceof Refused) return { verdict: "rejected", why: sentence(error.message), refused: error.kind };
          return { verdict: "away", why: waiting };
        }
        // A device that turns the password away keeps doing so however long one waits: the person has to type it again.
        if (condition.http.auth && answer.status === 401) return { verdict: "rejected", why: sentence(new Rejected().message), rejected: true };
        if (!answer.ok) return { verdict: "waiting", why: waiting };
        if (condition.json || condition.xml) {
          const value = condition.json ? jsonAt(answer.body, condition.json) : xmlAt(answer.body, condition.xml);
          if (value === undefined) return { verdict: "waiting", why: `${this.device.name} doesn't say yet.` };
          if (condition.equals && !sameWords(value, condition.equals)) return { verdict: "waiting", why: waiting };
          if (condition.contains && !holds(value, condition.contains)) return { verdict: "waiting", why: waiting };
          read ??= value;
        }
      }
    }
    return { verdict: "holds", read: read ?? null };
  }

  /**
   * Whether a setup step's check passes now: `passed`, what it read from the device, and when it didn't pass, why,
   * with `failed` for a reason waiting won't mend (the certificate changed, or the device rejected the sign-in).
   */
  async check(step) {
    const found = await this.evaluate(step.check);
    if (found.verdict === "holds") return { passed: true, read: found.read ?? undefined };
    return { passed: false, why: found.why, needs: found.needs, failed: found.verdict === "rejected", rejected: !!found.rejected };
  }

  /** A step passed on this device: it's kept, with the step and what the step read. */
  passed(step, read) {
    const mine = kept(this.device.id) ?? { ...this.device, passed: [], reads: {} };
    if (!mine.passed.includes(step.id)) mine.passed.push(step.id);
    if (read) mine.reads[step.id] = read;
    // What the model step read is the device's model from now on, finer than what it said of itself when found.
    if (step.model && read?.trim()) mine.model = read.trim();
    keep(mine);
    Object.assign(this.device, { model: mine.model, kept: true });
  }
}

/** A problem's words as a sentence. */
export const sentence = (words) => `${words[0].toUpperCase()}${words.slice(1)}${/[.!?…]$/.test(words) ? "" : "."}`;

/** Whether the device at `address` is there now, as a probe says: a port it takes ("tcp:8060"), a search it answers ("ssdp:roku:ecp") or a Bonjour service it offers. */
export async function present(address, probe, { reach = isPrivate } = {}) {
  const [kind, ...rest] = String(probe).split(":"), value = rest.join(":");
  if (!value || !reach(address)) return false;
  if (kind === "tcp") return answersOn(address, Number(value), { reach });
  if (kind === "ssdp") return (await ssdp(value, 2)).some((answer) => answer.address === address);
  if (kind === "bonjour") return (await bonjour(value, 3)).some((found) => found.address === address);
  return false;
}

/** Whether an answer says what `expect` asks, of any element where its path has `*`. */
function meets(expect, answer, values) {
  const found = expect.json ? jsonValues(answer.body, expect.json) : expect.xml ? [xmlAt(answer.body, expect.xml) ?? ""] : [];
  if (expect.equals != null) { const wanted = fill(expect.equals, values, "shown"); return found.some((value) => sameWords(value, wanted)); }
  if (expect.contains != null) { const wanted = fill(expect.contains, values, "shown"); return found.some((value) => holds(value, wanted)); }
  return true;
}

/** Whether every setup step has passed on a kept device. */
export const isReady = (device, integration) => !!device && (integration?.steps ?? []).every((step) => (kept(device.id)?.passed ?? []).includes(step.id));
