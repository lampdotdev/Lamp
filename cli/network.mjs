// Everything on the person's home network, one record per address, for when they're looking for devices: SSDP and the
// integrations find what Lamp can work with (devices.mjs); this finds the rest, so a list can say what else is there.
// It only reads: one small datagram to each address of this computer's own subnet, so its neighbor table fills (a
// phone that ignores everything else still answers ARP), that table, and every Bonjour service on the network
// (mdns.mjs). And the TVs: what a Samsung or an LG TV says of itself. Nothing is kept on disk: the names a network
// holds are often people's ("…'s iPhone").

import { execFile } from "node:child_process";
import dgram from "node:dgram";
import { readFileSync } from "node:fs";
import { networkInterfaces } from "node:os";
import { isPrivate, onNetwork, ownAddresses, send, xmlAt } from "./devices.mjs";
import { everything } from "./mdns.mjs";

const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

/** What a system program says, or "" when it says nothing (it isn't there, or it failed). Never through a shell. */
const said = (file, args) => new Promise((done) => execFile(file, args, { timeout: 5000 }, (error, out) => done(error ? "" : String(out))));

// MARK: The subnet

/** An IPv4 address as a number, or null. */
export function valueOf(address) {
  const parts = String(address).split(".");
  if (parts.length !== 4 || !parts.every((part) => /^\d{1,3}$/.test(part) && Number(part) < 256)) return null;
  return parts.reduce((value, part) => (value * 256) + Number(part), 0);
}
const textOf = (value) => [24, 16, 8, 0].map((shift) => Math.floor(value / 2 ** shift) % 256).join(".");

/**
 * The subnet to sweep for an address and its mask: no more than the 256 addresses around this computer's on a bigger
 * network, and none for an address that isn't on a home network.
 */
export function subnetOf(address, netmask) {
  const mine = valueOf(address), mask = valueOf(netmask);
  if (mine === null || mask === null) return null;
  const actual = [...mask.toString(2)].filter((bit) => bit === "1").length;
  if (actual < 8 || actual > 30 || !onNetwork(address)) return null;
  const prefix = Math.max(actual, 24), size = 2 ** (32 - prefix);
  return { network: textOf(mine - (mine % size)), prefix, actualPrefix: actual, mine: address };
}

const inSubnet = (subnet, address) => {
  const value = valueOf(address), size = 2 ** (32 - subnet.prefix);
  return value !== null && value - (value % size) === valueOf(subnet.network);
};

/** The default route: the interface it uses and the gateway it goes through. Null when there's none. */
export async function defaultRoute() {
  if (process.platform === "darwin") {
    const text = await said("/sbin/route", ["-n", "get", "default"]);
    const gateway = /^\s*gateway:\s*(\S+)/m.exec(text)?.[1], name = /^\s*interface:\s*(\S+)/m.exec(text)?.[1];
    return name ? { interface: name, gateway: valueOf(gateway) === null ? null : gateway } : null;
  }
  if (process.platform === "linux") {
    let table = "";
    try { table = readFileSync("/proc/net/route", "utf8"); } catch { return null; }
    for (const line of table.split("\n").slice(1)) {
      const [name, destination, gateway, flags] = line.trim().split(/\s+/);
      if (destination !== "00000000" || !(parseInt(flags, 16) & 2)) continue;
      const bytes = gateway.match(/../g)?.reverse().map((byte) => parseInt(byte, 16));
      return { interface: name, gateway: bytes?.length === 4 ? bytes.join(".") : null };
    }
  }
  return null;
}

/** The subnet of the interface the default route uses, when it's a home network's. */
export function subnetOn(name) {
  const entry = (networkInterfaces()[name] ?? []).find((address) => address.family === "IPv4" && !address.internal);
  return entry ? subnetOf(entry.address, entry.netmask) : null;
}

/** One datagram to each address of the subnet (one byte to the discard port, which nothing answers), a few at a time, paced, then a moment for the answers to ARP. */
export async function sweep(subnet, { batch = 16, pause = 25, settle = 1500 } = {}) {
  const socket = dgram.createSocket("udp4"), size = 2 ** (32 - subnet.prefix), network = valueOf(subnet.network);
  socket.on("error", () => {});
  await new Promise((done) => socket.bind(0, done));
  const addresses = [];
  for (let offset = 1; offset < size - 1; offset++) if (textOf(network + offset) !== subnet.mine) addresses.push(textOf(network + offset));
  try {
    for (let start = 0; start < addresses.length; start += batch) {
      for (const address of addresses.slice(start, start + batch)) socket.send(Buffer.from([0]), 9, address, () => {});
      await sleep(pause);
    }
    await sleep(settle);
  } finally { try { socket.close(); } catch {} }
}

/** A hardware address with two digits to each part ("ae:b0:a9:01:eb:44"); null for a multicast or broadcast one, or none. */
function hardware(text) {
  const parts = String(text).toLowerCase().split(":");
  if (parts.length !== 6 || !parts.every((part) => /^[0-9a-f]{1,2}$/.test(part))) return null;
  const mac = parts.map((part) => part.padStart(2, "0"));
  if (parseInt(mac[0], 16) & 1 || mac.every((part) => part === "ff")) return null;
  return mac.join(":");
}

/**
 * This computer's neighbor table: each neighbor's IPv4 address and hardware address, for those that answered. macOS
 * shows it only to a process it lets on the local network: run on the runtime Lamp's app carries, it's empty, so
 * Lamp's app reads its own (`Neighbours`).
 */
export async function neighbours() {
  const table = {};
  if (process.platform === "darwin") {
    for (const [, address, mac] of (await said("/usr/sbin/arp", ["-an"])).matchAll(/\((\d+\.\d+\.\d+\.\d+)\) at ([0-9a-fA-F:]+) on /g)) {
      const known = hardware(mac);
      if (known) table[address] = known;
    }
  } else if (process.platform === "linux") {
    let text = "";
    try { text = readFileSync("/proc/net/arp", "utf8"); } catch {}
    for (const line of text.split("\n").slice(1)) {
      const [address, , flags, mac] = line.trim().split(/\s+/);
      const known = (parseInt(flags, 16) & 2) && hardware(mac);
      if (known && valueOf(address) !== null) table[address] = known;
    }
  }
  return table;
}

/**
 * The hosts of this computer's subnet, each with its hardware address and its Bonjour services, from a sweep, the
 * neighbor table and every Bonjour service, browsed while the sweep runs. `swept` says which subnet was swept: on a
 * network bigger than a /24 only the 256 addresses around this computer's are.
 */
export async function homeNetwork({ seconds = 3 } = {}) {
  const services = everything({ seconds });
  const route = await defaultRoute(), subnet = route ? subnetOn(route.interface) : null;
  if (subnet) await sweep(subnet);
  const table = await neighbours(), mine = ownAddresses();
  const inside = (address) => (subnet ? inSubnet(subnet, address) : isPrivate(address)) || mine.has(address);
  const hosts = new Map(), hostAt = (address) => hosts.get(address) ?? hosts.set(address, { address, mac: null, services: [] }).get(address);
  for (const [address, mac] of Object.entries(table)) if (inside(address)) hostAt(address).mac = mac;
  for (const { service, addresses } of await services) for (const address of addresses) if (inside(address)) hostAt(address).services.push(service);
  for (const host of hosts.values()) {
    host.isThisMac = mine.has(host.address);
    host.isGateway = host.address === route?.gateway;
  }
  return { hosts: [...hosts.values()].sort((a, b) => (valueOf(a.address) ?? Infinity) - (valueOf(b.address) ?? Infinity)), swept: subnet, gateway: route?.gateway ?? null };
}

// MARK: TVs

/** The service an LG TV announces for itself; the description it points at is the TV's own. */
export const LG_TV = "urn:lge:device:tv:1";

/** A page on the TV, read with every guard a request to a device has: its body, or null. */
const fetched = (address) => (request) => send(request, address, {}, { timeout: 3000 }).then((answer) => (answer.status === 200 ? answer.body : null), () => null);

/** A Samsung TV's own description of itself, from its local API; null when it isn't one. */
export async function samsungAt(address, { get = fetched(address) } = {}) {
  let device;
  try { device = JSON.parse(String(await get({ port: 8001, path: "/api/v2/" }))).device; } catch { return null; }
  if (device?.OS !== "Tizen") return null;
  const modelID = typeof device.modelName === "string" ? device.modelName : "", frame = device.FrameTVSupport === "true";
  // The size is in the model code (QN50…, UN65…).
  const size = /^\d{2}$/.test(modelID.slice(2, 4)) ? modelID.slice(2, 4) : "";
  const model = frame ? `The Frame${size ? ` ${size}` : ""}` : size ? `Smart TV ${size}` : modelID;
  // The year is the first part of its internal model ("22_PONTUSM_FTV"), and each year has one Tizen.
  const year = Number(String(device.model ?? "").slice(0, 2)) || 0;
  const tizen = { 17: "3.0", 18: "4.0", 19: "5.0", 20: "5.5", 21: "6.0", 22: "6.5", 23: "7.0", 24: "8.0", 25: "9.0", 26: "10.0" }[year] ?? "";
  const id = String(device.id ?? device.duid ?? address).replace("uuid:", "");
  return { id: `samsung:${id}`, maker: "Samsung", name: typeof device.name === "string" ? device.name : "Samsung TV", model, modelID, address, os: "Tizen",
    osVersion: tizen, resolution: typeof device.resolution === "string" ? device.resolution : "", frame,
    developerIP: typeof device.developerIP === "string" ? device.developerIP : null, developerMode: device.developerMode === "1" };
}

/**
 * An LG TV, from the UPnP descriptions its answers point at. It answers for several services, each with a
 * description and an id of its own, and the first to answer is often one that says nothing of the TV (a streaming
 * service's, a few bytes of "status=ok"), so each is tried until one is an LG TV's: the TV's own service first, which
 * gives it the same id at every search. `udns` is every id it answered for, so a TV kept under another one is known.
 */
export async function lgAt(address, answers, { get = fetched(address) } = {}) {
  const locations = [];
  const own = answers.filter((answer) => String(answer.target).toLowerCase() === LG_TV).map((answer) => answer.location);
  for (const location of [...own, ...answers.map((answer) => answer.location)]) {
    let url;
    try { url = new URL(location); } catch { continue; }
    if (url.hostname === address && url.protocol === "http:" && !locations.includes(location)) locations.push(location);
  }
  // A USN is "uuid:<udn>" or "uuid:<udn>::<type>".
  const udns = new Set(answers.map((answer) => String(answer.usn)).filter((usn) => usn.toLowerCase().startsWith("uuid:")).map((usn) => usn.slice(5).split("::")[0]).filter(Boolean));
  for (const location of locations) {
    const url = new URL(location), body = await get({ port: Number(url.port) || 80, path: (url.pathname || "/") + url.search });
    if (!body) continue;
    const tag = (name) => xmlAt(body, name) ?? null;
    if (!(tag("manufacturer") ?? "").toUpperCase().startsWith("LG")) continue;
    const udn = (tag("UDN") ?? address).replace("uuid:", "");
    return { id: `lg:${udn}`, maker: "LG", name: tag("friendlyName") ?? "LG TV", model: tag("modelName") ?? "webOS TV", modelID: tag("modelNumber") ?? "",
      address, os: "webOS", osVersion: "", resolution: "", udns: [...new Set([...udns, udn])].sort() };
  }
  return null;
}

/** The TVs among a search's answers, each asked who it is: one whose answers say Samsung, or webOS or LG. */
export async function tvsIn(answers, { get } = {}) {
  const byAddress = new Map();
  for (const answer of answers) byAddress.set(answer.address, [...(byAddress.get(answer.address) ?? []), answer]);
  const read = await Promise.all([...byAddress].map(([address, said]) => {
    const words = said.map((answer) => `${answer.server}\n${answer.location ?? ""}\n${answer.target}`).join("\n").toLowerCase();
    if (words.includes("samsung")) return samsungAt(address, get ? { get } : {});
    if (words.includes("webos") || words.includes("lge")) return lgAt(address, said, get ? { get } : {});
    return null;
  }));
  return read.filter(Boolean).filter((tv, index, all) => all.findIndex((other) => other.id === tv.id) === index);
}
