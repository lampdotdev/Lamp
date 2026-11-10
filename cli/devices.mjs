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
import { chmodSync, existsSync, mkdirSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import http from "node:http";
import net from "node:net";
import { homedir, networkInterfaces } from "node:os";
import { basename, dirname, join } from "node:path";
import tls from "node:tls";
import { fileURLToPath } from "node:url";
import { Problem } from "./state.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** Where lamp keeps what it knows of the person's devices: outside every app's folder, read by the person alone. */
export const devicesHome = () => process.env.LAMP_DEVICES_HOME || join(homedir(), ".lamp", "devices");

// MARK: Integrations

/** The integrations Lamp ships, as its app reads them. */
export function integrations() {
  const folder = join(HERE, "..", "Resources", "Devices");
  return readdirSync(folder).filter((name) => name.endsWith(".json")).sort().map((name) => JSON.parse(readFileSync(join(folder, name), "utf8")));
}

export const integrationOf = (id) => integrations().find((integration) => integration.id === id);

/** Whether lamp puts a page on this integration's devices: where it packages pages for the device's host, the Xbox's so far. */
export const takesPages = (integration) => integration?.app?.declared?.wrap === "msix" && integration.app.declared.host === "webview2";

// MARK: Addresses

/** This computer's own addresses, read each time: they change as it moves between networks. */
const ownAddresses = () => new Set(Object.values(networkInterfaces()).flat().map((entry) => entry.address.split("%")[0].toLowerCase()));

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

/** One SSDP search of the home network, for a few seconds: who answered, and what each said of itself. */
export function ssdp(target = "ssdp:all", seconds = 3) {
  return new Promise((done) => {
    const socket = dgram.createSocket({ type: "udp4", reuseAddr: true }), answers = new Map();
    const message = Buffer.from(`M-SEARCH * HTTP/1.1\r\nHOST: 239.255.255.250:1900\r\nMAN: "ssdp:discover"\r\nMX: 1\r\nST: ${target.replace(/[\r\n]/g, "")}\r\n\r\n`);
    const ask = () => socket.send(message, 1900, "239.255.255.250", () => {});
    socket.on("error", () => { try { socket.close(); } catch {} done([...answers.values()]); });
    socket.on("message", (data, from) => {
      const headers = {};
      for (const line of data.toString("utf8").split(/\r?\n/)) {
        const colon = line.indexOf(":");
        if (colon > 0) headers[line.slice(0, colon).toLowerCase()] = line.slice(colon + 1).trim();
      }
      const answer = { address: from.address, server: headers.server ?? "", location: headers.location, target: headers.st ?? "", usn: headers.usn ?? "" };
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
 * The devices the integrations find on the network now, each read from its own answers as its integration says, with
 * the ones lamp keeps that didn't answer after them (`found: false`, at the address they were last at).
 */
export async function look({ seconds = 3, reach = isPrivate } = {}) {
  const answers = await ssdp("ssdp:all", seconds), devices = [];
  for (const integration of integrations()) {
    const addresses = new Set();
    for (const find of integration.find ?? []) {
      if (!find.ssdp) continue;
      for (const answer of answers) {
        if (sameWords(answer.target, find.ssdp) && (!find.contains || holds(answer.server, find.contains)) && reach(answer.address)) addresses.add(answer.address);
      }
    }
    for (const address of [...addresses].sort()) {
      if (devices.some((device) => device.address === address)) continue;
      const device = await identify(integration, address, answers, reach);
      if (device) devices.push(device);
    }
  }
  for (const device of devices) {
    const mine = kept(device.id);
    device.kept = !!mine;
    if (mine) keep({ ...mine, name: device.name, address: device.address });
    if (mine?.model) device.model = mine.model;
  }
  for (const mine of allKept()) if (!devices.some((device) => device.id === mine.id)) devices.push({ ...mine, kept: true, found: false });
  return devices;
}

/** The device at an address, read from its own answers as the integration says; null when it doesn't answer as one. */
async function identify(integration, address, answers, reach) {
  const got = new Map();
  const read = async (how) => {
    if (!how) return null;
    let request = how.http;
    if (how.description) {
      // Where the device says its UPnP description is, in its answer to the integration's own search: only a
      // description on the device itself, over plain HTTP.
      for (const find of integration.find ?? []) {
        for (const answer of answers) {
          if (request || answer.address !== address || !find.ssdp || !sameWords(answer.target, find.ssdp) || !answer.location) continue;
          let url;
          try { url = new URL(answer.location); } catch { continue; }
          if (url.protocol === "http:" && url.hostname === address) request = { port: Number(url.port) || 80, path: (url.pathname || "/") + url.search };
        }
      }
    }
    if (!request) return null;
    const key = JSON.stringify(request);
    if (!got.has(key)) {
      const answer = await send(request, address, {}, { timeout: 4000, reach }).catch(() => null);
      if (answer?.ok) got.set(key, answer);
    }
    const answer = got.get(key), value = answer && (how.json ? jsonAt(answer.body, how.json) : how.xml ? xmlAt(answer.body, how.xml) : null)?.trim();
    if (how.contains && !holds(value, how.contains)) return null;
    return value || null;
  };
  const identity = integration.identity ?? {};
  const serial = await read(identity.id), model = await read(identity.model);
  if (!serial || !model) return null;
  return {
    id: `${integration.id}:${serial}`, integration: integration.id, what: integration.kind, maker: integration.maker, model,
    name: (await read(identity.name)) ?? `${integration.maker} ${model}`, address, found: true,
  };
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
export function pinsOf(id) {
  const file = join(folderOf(id), "certificates.json");
  const read = () => (existsSync(file) ? readJSON(file) : {});
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
      try { writeKept(id, "certificates.json", { ...pins, [port]: fingerprint }); } catch { return UNSAVED; }
      return null;
    },
    root: (port) => { const root = read()?.[`root:${port}`]; return root ? Buffer.from(root, "base64") : null; },
    /** Keeps the device's root for a port, only when it signed the certificate kept there, so the root is the device's own. */
    keepRoot(root, leaf, port) {
      const pins = read();
      if (!pins || pins[port] !== fingerprintOf(leaf) || pins[`root:${port}`] || !signs(root, leaf)) return false;
      writeKept(id, "certificates.json", { ...pins, [`root:${port}`]: root.toString("base64") });
      return true;
    },
  };
}

// MARK: Placeholders

// The values lamp puts into an integration's requests: `{name}`, `{field:<key>}`, `{cookie:<name>}`, `{base64:<name>}`.
// A word in braces and nothing else, so a brace that opens JSON is the template's own text.
const PLACEHOLDER = /\{([A-Za-z][A-Za-z0-9]*(?::[A-Za-z0-9-]+)?)\}/g;
const SAFE = /^[A-Za-z0-9._\-:/@+=,]*$/;

/**
 * The template with each placeholder filled. A value outside the safe alphabet is refused, except what the person
 * typed, which only reaches places that are encoded (a sign-in, a form, a header, a body); in a path a value is
 * percent-encoded so it can't change the path.
 */
export function fill(template, values, place) {
  return template.replace(PLACEHOLDER, (whole, name) => {
    const value = name.startsWith("base64:") ? (values[name.slice(7)] === undefined ? undefined : Buffer.from(values[name.slice(7)]).toString("base64")) : values[name];
    if (value === undefined) throw new Problem(`lamp has nothing to put in {${name}}`);
    const typed = name.startsWith("field:");
    if (typed && !["auth", "form", "header", "body"].includes(place)) throw new Problem(`{${name}} can't go in a ${place}: what the person types goes only in a sign-in, a form, a header or a body`);
    if (name.startsWith("cookie:") && place !== "header") throw new Problem(`{${name}} goes only in a header`);
    if (!typed && (!SAFE.test(value) || value.length > 512)) throw new Problem(`the value for {${name}} has characters lamp doesn't send to a device`);
    return place === "path" ? encodeURIComponent(value).replace(/%2F/g, "/").replace(/%3A/g, ":").replace(/%40/g, "@").replace(/%2C/g, ",") : value;
  });
}

const namesIn = (template) => [...String(template ?? "").matchAll(PLACEHOLDER)].map((match) => match[1]);

/** Whether a request carries what the person typed, which goes only where lamp knows the device. */
function carriesSecret(request) {
  if (request.auth) return true;
  return [request.path, request.body, ...Object.values(request.headers ?? {}), ...Object.values(request.form ?? {})].flatMap(namesIn).some((name) => name.startsWith("field:"));
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
export async function send(request, address, values, { files = {}, pins, timeout = 30_000, session = {}, reach = isPrivate } = {}) {
  const https = request.https === true;
  if (https && !pins && carriesSecret(request)) throw new Problem("lamp sends a password over HTTPS only to a device whose certificate it keeps");
  if (!reach(address)) throw new Problem(`lamp only talks to devices on your own network, and ${address} isn't one`);
  if (!Number.isInteger(request.port) || request.port < 1 || request.port > 65535) throw new Problem(`${request.port} isn't a port`);
  const path = fill(request.path, values, "path"), problem = pathProblem(path.split("?")[0]);
  if (problem) throw new Problem(`the path ${problem}`);
  const method = (request.method ?? "GET").toUpperCase(), headers = {};
  for (const [name, value] of Object.entries(request.headers ?? {})) if (name.toLowerCase() !== "host") headers[name] = fill(value, values, "header");
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
    let socket = null, certificate = null;
    if (https) ({ socket, certificate } = await connect(address, request.port, pins, timeout));
    return await new Promise((done, failed) => {
      const options = { host: address, port: request.port, method, path, headers: authorization ? { ...headers, Authorization: authorization } : headers };
      if (socket) options.createConnection = () => socket; else options.agent = false;
      const asked = http.request(options, (answer) => {
        const chunks = [];
        let size = 0;
        answer.on("data", (chunk) => {
          size += chunk.length;
          if (size > ANSWER_LIMIT) asked.destroy(new Problem("the device's answer was bigger than lamp takes"));
          else chunks.push(chunk);
        });
        answer.on("end", () => {
          const cookies = {};
          for (const cookie of answer.headers["set-cookie"] ?? []) {
            const pair = cookie.split(";")[0], equals = pair.indexOf("=");
            if (equals > 0) cookies[pair.slice(0, equals).trim()] = pair.slice(equals + 1).trim();
          }
          const bytes = Buffer.concat(chunks);
          done({ status: answer.statusCode, ok: answer.statusCode >= 200 && answer.statusCode < 300, body: bytes, text: bytes.toString("utf8"), cookies, certificate, asks: answer.headers["www-authenticate"] ?? "" });
        });
        answer.on("error", (error) => failed(error instanceof Problem ? error : new Away(address, error)));
      });
      asked.setTimeout(timeout, () => asked.destroy(timedOut()));
      asked.on("error", (error) => failed(error instanceof Problem ? error : new Away(address, error)));
      asked.end(body ?? undefined);
    });
  };

  // The sign-in goes only in answer to the device's own request for it, with the scheme the integration declared.
  let authorization = null;
  if (request.auth) {
    if (request.auth.digest) throw new Problem("lamp's command line doesn't sign in to a device that asks for a digest yet");
    authorization = "Basic " + Buffer.from(`${request.auth.user}:${fill(request.auth.password, values, "auth")}`).toString("base64");
  }
  session.asked ??= new Set();
  const door = `${address}:${request.port}`;
  let answer = await once(authorization && session.asked.has(door) ? authorization : null);
  if (answer.status === 401 && authorization && !session.asked.has(door) && /^\s*basic\b/i.test(answer.asks)) {
    session.asked.add(door);
    answer = await once(authorization);
  }
  return answer;
}

/** The device's certificate isn't one lamp takes: waiting won't mend it. */
export class Refused extends Problem {}

/** The device didn't answer, or let the connection go: it's off, asleep, somewhere else on the network, or busy. */
export class Away extends Problem {
  constructor(address, cause) {
    super(`the device at ${address} ${cause?.timedOut ? "didn't answer in time" : "isn't answering"}: make sure it's on, then try again`);
    this.code = cause?.code;
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
  constructor() { super("the device rejected the sign-in: check the password, then try again"); }
}

/** The device was still at what it was sent when lamp stopped waiting: a moment later it may be done. */
export class StillWorking extends Problem {}

/**
 * Runs an integration's setup checks and its sequences (install, launch, look…) on one device. `pause` and `reach`
 * are how it waits and what it takes for an address on the home network, which a test gives its own.
 */
export class Runner {
  constructor({ integration, device, onWaiting = () => {}, pause = sleep, reach = isPrivate }) {
    Object.assign(this, { integration, device, onWaiting, pause, reach });
  }

  get address() {
    if (!this.device.address || !this.reach(this.device.address)) throw new Problem(`lamp doesn't know where ${this.device.name} is on your network: make sure it's on, then run lamp devices`);
    return this.device.address;
  }

  /** lamp's values for this device, and the caller's (an app's names, whether it's a game). */
  values(extra = {}) {
    const values = { ...extra, address: this.device.address, deviceID: this.device.id.split(":").slice(1).join(":") };
    const mine = nearest(this.device.address);
    if (mine) values.mac = mine;
    for (const [key, value] of Object.entries(fields.read(this.device.id))) values[`field:${key}`] = value;
    for (const [step, value] of Object.entries(kept(this.device.id)?.reads ?? {})) values[`read:${step}`] = value;
    return values;
  }

  #send(request, values, more = {}) {
    return send(request, this.address, values, { pins: pinsOf(this.device.id), reach: this.reach, ...more });
  }

  /**
   * The first time the device's certificate is kept for a port, the root the integration says signs it is read from
   * the device over that same connection and kept with it, so a certificate the device makes later is still known as
   * its own.
   */
  async #learnRoot(request, answer) {
    const path = this.integration.certificateRoot, pins = pinsOf(this.device.id);
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
  async run(sequence, { extra = {}, files = {}, changed } = {}) {
    const settings = changed ?? [];
    try { return await this.#run(sequence, extra, files, settings); } finally { if (!changed) await this.putBack(settings); }
  }

  /** Each setting as it was before a sequence changed it, last changed first. */
  async putBack(changed) {
    for (const restore of changed.splice(0).reverse()) {
      const back = { ...restore.request, body: JSON.stringify({ [restore.request.restore]: restore.was }) };
      const answer = await this.#send(back, restore.values, { session: restore.session }).catch(() => null);
      if (!answer?.ok) process.stderr.write(`lamp couldn't set ${restore.request.path} on ${this.device.name} back to ${restore.was}\n`);
    }
  }

  async #run(sequence, extra, files, changed) {
    const outcome = { answers: [] }, cookies = {}, session = {};
    for (const action of sequence) {
      const values = { ...this.values(extra), ...Object.fromEntries(Object.entries(cookies).map(([name, value]) => [`cookie:${name}`, value])) };
      const request = action.http;
      if (action.wait) { await this.pause(Math.min(Math.max(action.wait, 1), 30) * 1000); continue; }
      if (!request) throw new Problem(`${this.device.name}'s integration asks for something lamp's command line doesn't do yet (${Object.keys(action).join(", ")})`);
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
        if (!changed.some((restore) => `${restore.request.port}${restore.request.path}` === setting) && was !== wanted) changed.push({ request, was, values, session });
      }
      const transfer = () => this.#send(request, values, { files, session });
      let asked = Date.now(), answer = await transfer();
      // A device still working on what it was sent says so with 204 until it's done.
      if (request.poll) {
        const until = Date.now() + Math.min(Math.max(request.poll, 2), 600) * 1000;
        while (answer.status === 204 && Date.now() < until) {
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
      else outcome.answers.push(answer.text.slice(0, 64 << 10));
    }
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
      this.onWaiting();
      await this.pause(wait);
      wait = Math.min(wait * 2, 8000);
    }
    return { opened: false, launched, refused };
  }

  /**
   * Whether a setup step's check passes now: `passed`, what it read from the device, and when it didn't pass, why,
   * with `failed` for a reason waiting won't mend (the certificate changed, or the device rejected the sign-in).
   */
  async check(step) {
    const values = this.values(), waiting = `waiting for ${this.device.name}`;
    let read;
    for (const condition of step.check ?? []) {
      if (condition.field) {
        if (!values[`field:${condition.field}`]) return { passed: false, needs: condition.field, why: "waiting for what you type" };
      } else if (condition.tcp) {
        if (!(await answersOn(this.device.address, condition.tcp, { reach: this.reach }))) return { passed: false, why: waiting };
      } else if (condition.http) {
        let answer;
        try {
          answer = await this.#send(condition.http, values);
          if (answer.ok) await this.#learnRoot(condition.http, answer);
        } catch (error) {
          if (error instanceof Refused) return { passed: false, why: error.message, failed: true };
          return { passed: false, why: waiting };
        }
        if (condition.http.auth && answer.status === 401) return { passed: false, why: new Rejected().message, failed: true, rejected: true };
        if (!answer.ok) return { passed: false, why: waiting };
        if (condition.json || condition.xml) {
          const value = condition.json ? jsonAt(answer.body, condition.json) : xmlAt(answer.body, condition.xml);
          if (value === undefined) return { passed: false, why: `${this.device.name} doesn't say yet` };
          if (condition.equals && !sameWords(value, condition.equals)) return { passed: false, why: waiting };
          if (condition.contains && !holds(value, condition.contains)) return { passed: false, why: waiting };
          read ??= value;
        }
      }
    }
    return { passed: true, read };
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

/** Whether an answer says what `expect` asks, of any element where its path has `*`. */
function meets(expect, answer, values) {
  const found = expect.json ? jsonValues(answer.body, expect.json) : expect.xml ? [xmlAt(answer.body, expect.xml) ?? ""] : [];
  if (expect.equals != null) { const wanted = fill(expect.equals, values, "shown"); return found.some((value) => sameWords(value, wanted)); }
  if (expect.contains != null) { const wanted = fill(expect.contains, values, "shown"); return found.some((value) => holds(value, wanted)); }
  return true;
}

/** Whether every setup step has passed on a kept device. */
export const isReady = (device, integration) => !!device && (integration?.steps ?? []).every((step) => (kept(device.id)?.passed ?? []).includes(step.id));
