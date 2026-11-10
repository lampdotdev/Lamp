// Bonjour without a Bonjour library: mDNS questions asked from a port of lamp's own, which each device answers there and
// only there (a one-shot query, RFC 6762 6.7), so nothing listens on mDNS's own port, which is this computer's own
// responder's. Enough of the format to find a type's services, and every service on the network with its host, its
// address and the few words of its record that say what the device is.

import dgram from "node:dgram";

/** A name as records are kept by: its labels in small letters, a dot inside one escaped, so a service called "Mr. Lee's TV" stays one label. */
const keyOf = (labels) => labels.map((label) => label.toLowerCase().replaceAll("\\", "\\\\").replaceAll(".", "\\.")).join(".");

/** An mDNS name in a packet at `at`, its pointers followed, and where it ends there; null when it can't be read. */
function nameAt(packet, at) {
  const labels = [];
  let end = null;
  for (let jumps = 0; ; ) {
    if (at >= packet.length) return null;
    const length = packet[at];
    if (length === 0) return { labels, end: end ?? at + 1 };
    if ((length & 0xc0) === 0xc0) {
      if (at + 1 >= packet.length || ++jumps > 32) return null;
      end ??= at + 2;
      at = ((length & 0x3f) << 8) | packet[at + 1];
    } else {
      if (length > 63 || at + 1 + length > packet.length) return null;
      labels.push(packet.toString("utf8", at + 1, at + 1 + length));
      at += 1 + length;
    }
  }
}

/**
 * A TXT record's entries: each a length and "key=value", or a bare key, which is an empty value. The first value for a
 * key wins, as the record format says.
 */
export function entriesOf(data) {
  const entries = {};
  for (let at = 0; at < data.length; ) {
    const length = data[at];
    at += 1;
    if (at + length > data.length) break;
    if (length === 0) continue;
    const entry = data.subarray(at, at + length), equals = entry.indexOf(0x3d);
    at += length;
    const key = entry.toString("utf8", 0, equals < 0 ? entry.length : equals);
    if (key && !(key in entries)) entries[key] = equals < 0 ? "" : entry.toString("utf8", equals + 1);
  }
  return entries;
}

/** Every record of an mDNS answer: its name (as `keyOf` keeps it, and its labels), and for a pointer, a service, an address or a TXT record what it says. */
export function recordsOf(packet) {
  if (packet.length < 12) return [];
  const count = (index) => packet.readUInt16BE(4 + index * 2), records = [];
  let at = 12;
  for (let question = 0; question < count(0); question++) {
    const name = nameAt(packet, at);
    if (!name) return [];
    at = name.end + 4;
  }
  for (let left = count(1) + count(2) + count(3); left > 0; left--) {
    const name = nameAt(packet, at);
    if (!name || name.end + 10 > packet.length) break;
    const type = packet.readUInt16BE(name.end), length = packet.readUInt16BE(name.end + 8), data = name.end + 10;
    if (data + length > packet.length) break;
    const record = { name: keyOf(name.labels), labels: name.labels, type };
    if (type === 12) record.target = nameAt(packet, data)?.labels;
    else if (type === 33 && length >= 6) { record.port = packet.readUInt16BE(data + 4); record.target = nameAt(packet, data + 6)?.labels; }
    else if (type === 1 && length === 4) record.address = [...packet.subarray(data, data + 4)].join(".");
    else if (type === 16) record.txt = entriesOf(packet.subarray(data, data + length));
    records.push(record);
    at = data + length;
  }
  return records;
}

/**
 * The services of a type an mDNS answer offers, each by its name, at the address of the host it names when the
 * answer gives one, else at the address the answer came from.
 */
export function servicesIn(packet, type, from) {
  const wanted = keyOf(`${type}.local`.split(".")), records = recordsOf(packet), found = [];
  for (const offered of records) {
    if (offered.type !== 12 || offered.name !== wanted || !offered.target?.length) continue;
    const instance = keyOf(offered.target);
    const host = records.find((record) => record.type === 33 && record.name === instance)?.target;
    const address = (host && records.find((record) => record.type === 1 && record.name === keyOf(host))?.address) || from;
    found.push({ name: offered.target[0], address });
  }
  return found;
}

/** A question for a name's records of one type, asking for the answer to come back here. */
function question(labels, type) {
  const header = Buffer.alloc(12);
  header.writeUInt16BE(1 + Math.floor(Math.random() * 0xfffe), 0);
  header.writeUInt16BE(1, 4);
  const name = labels.map((label) => { const bytes = Buffer.from(label); return Buffer.concat([Buffer.from([bytes.length]), bytes]); });
  return Buffer.concat([header, ...name, Buffer.from([0, (type >> 8) & 0xff, type & 0xff, 0x80, 1])]);
}

const TYPE = /^_[A-Za-z0-9-]{1,40}\._(tcp|udp)$/;
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/**
 * A socket that asks questions and keeps every record any answer gives, each with the address it came from; `close`
 * when done. Nothing is sent but the questions.
 */
async function asking() {
  const socket = dgram.createSocket({ type: "udp4", reuseAddr: true }), records = [];
  socket.on("error", () => {});
  socket.on("message", (packet, from) => { for (const record of recordsOf(packet)) records.push({ ...record, from: from.address }); });
  await new Promise((done) => socket.bind(0, done));
  try { socket.setMulticastTTL(1); } catch {}
  return {
    records,
    ask(labels, type) { socket.send(question(labels, type), 5353, "224.0.0.251", () => {}); },
    close() { try { socket.close(); } catch {} },
  };
}

/** The devices offering a Bonjour service of this type ("_airplay._tcp") on the home network, by name and address, asked twice. */
export async function bonjour(type, seconds = 3) {
  if (!/^_[a-z0-9-]{1,40}\._(tcp|udp)$/.test(type)) return [];
  const mdns = await asking(), labels = [...type.split("."), "local"], wanted = keyOf(labels);
  try {
    mdns.ask(labels, 12);
    await sleep((seconds * 1000) / 2);
    mdns.ask(labels, 12);
    await sleep((seconds * 1000) / 2);
  } finally { mdns.close(); }
  const found = new Map();
  for (const offered of mdns.records) {
    if (offered.type !== 12 || offered.name !== wanted || !offered.target?.length) continue;
    const host = mdns.records.find((record) => record.type === 33 && record.name === keyOf(offered.target))?.target;
    const address = (host && mdns.records.find((record) => record.type === 1 && record.name === keyOf(host))?.address) || offered.from;
    found.set(`${offered.target[0]} ${address}`, { name: offered.target[0], address });
  }
  return [...found.values()];
}

// Browsed whether or not the network names them: a device that's asleep often misses that one answer, and these are
// the services that say most about what a quiet device is (a Cast device, a printer, a gadget's web page).
const ALWAYS = ["_googlecast._tcp", "_androidtvremote2._tcp", "_ipp._tcp", "_printer._tcp", "_http._tcp", "_esphomelib._tcp"];

// The words of a service's record kept: those that say what the device is, and nothing that says more of it or its person.
const MODEL_KEYS = new Set(["md", "model", "am", "ty", "usb_MFG", "usb_MDL", "product", "manufacturer", "fn"]);

/**
 * Every Bonjour service on the network: the types it offers (`_services._dns-sd._udp`), the services of each, each
 * one's host and record, and each host's addresses, a round of questions at a time, each asked twice in its round.
 * Each service comes with its type, its name, its host ("Kitchen-Speaker.local."), the words of its record that say
 * what the device is, and its addresses.
 */
export async function everything({ seconds = 3 } = {}) {
  const mdns = await asking(), round = (seconds * 1000) / 3;
  const twice = async (asked) => { for (const [labels, type] of asked) mdns.ask(labels, type); await sleep(round / 2); for (const [labels, type] of asked) mdns.ask(labels, type); await sleep(round / 2); };
  const targets = (name, type = 12) => mdns.records.filter((record) => record.type === type && record.name === name && record.target?.length).map((record) => record.target);
  try {
    const meta = ["_services", "_dns-sd", "_udp", "local"];
    await twice([[meta, 12]]);
    // The network's answers name types as "_airplay._tcp.local".
    const named = targets(keyOf(meta)).map((labels) => labels.slice(0, 2).join("."));
    const types = [...new Set([...named, ...ALWAYS])].filter((type) => TYPE.test(type)).slice(0, 60);
    await twice(types.map((type) => [[...type.split("."), "local"], 12]));
    const services = [];
    for (const type of types) {
      const seen = new Set();
      for (const labels of targets(keyOf([...type.split("."), "local"]))) {
        if (seen.has(keyOf(labels)) || seen.size >= 40) continue;
        seen.add(keyOf(labels));
        services.push({ type, labels });
      }
    }
    // Each service's host and record, where the answers so far didn't give them.
    const has = (labels, type) => mdns.records.some((record) => record.type === type && record.name === keyOf(labels));
    await twice(services.flatMap(({ labels }) => [...(has(labels, 33) ? [] : [[labels, 33]]), ...(has(labels, 16) ? [] : [[labels, 16]])]));
    // Each host's address, asked once for all its services: a device with many answered some and not others.
    const hostOf = (labels) => targets(keyOf(labels), 33)[0];
    const hosts = new Map();
    for (const { labels } of services) { const host = hostOf(labels); if (host) hosts.set(keyOf(host), host); }
    await twice([...hosts.values()].filter((host) => !has(host, 1)).map((host) => [host, 1]));
    const found = [];
    for (const { type, labels } of services) {
      const host = hostOf(labels);
      if (!host) continue;
      const addresses = [...new Set(mdns.records.filter((record) => record.type === 1 && record.name === keyOf(host)).map((record) => record.address))];
      if (!addresses.length) {
        // A host whose address wasn't said is the one that said where its service is.
        const from = mdns.records.find((record) => record.type === 33 && record.name === keyOf(labels))?.from;
        if (from) addresses.push(from);
      }
      if (!addresses.length) continue;
      const txt = {};
      for (const [key, value] of Object.entries(mdns.records.find((record) => record.type === 16 && record.name === keyOf(labels))?.txt ?? {})) {
        // A Cast device's "md" is its model, and its "fn" the name the person gave it; AirPlay's "md" is the kinds of
        // metadata it takes.
        if (!MODEL_KEYS.has(key) || ((key === "md" || key === "fn") && type !== "_googlecast._tcp")) continue;
        const text = value.trim();
        if (text && [...text].length <= 80 && !/[\u0000-\u001f\u007f-\u009f]/.test(text)) txt[key] = text;
      }
      found.push({ service: { type, name: labels[0], host: `${host.join(".")}.`, txt }, addresses });
    }
    return found;
  } finally { mdns.close(); }
}
