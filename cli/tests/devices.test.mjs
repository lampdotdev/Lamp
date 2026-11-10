// A page goes on an Xbox through its Device Portal exactly as the Xbox's integration says (Resources/Devices/
// xbox-one.json, the file Lamp's app reads too): set up with the password the person typed, packaged, installed,
// opened, looked at, stopped and taken off. The console here is a stand-in that answers as Device Portal does,
// refusing what a real one refuses: a request with no sign-in, a change without the token it handed out, a package
// it can't find its manifest in.

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import https from "node:https";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { Runner, fields, integrationOf, isReady, kept, pinsOf } from "../devices.mjs";
import { namesOf, newSigner, PUBLISHER } from "../msix.mjs";
import { encode } from "../png.mjs";
import { lookOn, putOn, removeFrom, stopOn } from "../place.mjs";
import { layoutOf } from "../state.mjs";

const pem = (label, der) => `-----BEGIN ${label}-----\n${der.toString("base64").match(/.{1,64}/g).join("\n")}\n-----END ${label}-----\n`;

/** A console's Device Portal, as much of it as the Xbox's integration asks of one. */
async function portal(password) {
  const made = newSigner(), token = "csrf-1234", state = { installed: [], running: null, game: "false", installing: 0, launches: 0, sent: null, settings: [] };
  const server = https.createServer({ key: pem("RSA PRIVATE KEY", made.key), cert: pem("CERTIFICATE", made.certificate) }, (asked, answer) => {
    const chunks = [];
    asked.on("data", (chunk) => chunks.push(chunk));
    asked.on("end", () => {
      const body = Buffer.concat(chunks), url = new URL(asked.url, "https://console"), route = `${asked.method} ${url.pathname}`;
      const say = (status, value, headers = {}) => { answer.writeHead(status, headers); answer.end(value === undefined ? "" : Buffer.isBuffer(value) ? value : JSON.stringify(value)); };
      if (asked.headers.authorization !== "Basic " + Buffer.from(`lamp:${password}`).toString("base64")) return say(401, undefined, { "WWW-Authenticate": 'Basic realm="Device Portal"' });
      if (asked.method !== "GET" && asked.headers["x-csrf-token"] !== token) return say(403, { Reason: "no token" });
      const unpacked = (name) => Buffer.from(url.searchParams.get(name) ?? "", "base64").toString("utf8");
      switch (route) {
        case "GET /api/os/info": return say(200, { Platform: "Xbox Series X", OsVersion: "10.0.26100" }, { "Set-Cookie": `CSRF-Token=${token}; Path=/` });
        case "GET /ext/settings/DefaultUWPContentTypeToGame": return say(200, { Value: state.game });
        case "PUT /ext/settings/DefaultUWPContentTypeToGame": state.game = JSON.parse(body).Value; state.settings.push(state.game); return say(200, {});
        case "POST /api/app/packagemanager/package": {
          // The package's own manifest says which package it is, as Windows reads it.
          const identity = /<Identity Name="([^"]+)" Publisher="[^"]+" Version="([^"]+)" ProcessorArchitecture="([^"]+)"/.exec(body.toString("latin1"));
          if (!identity || !/filename="app\.msix"/.test(body.toString("latin1")) || !/filename="lamp\.cer"/.test(body.toString("latin1"))) return say(400, { Reason: "not a package and its certificate" });
          state.sent = { name: identity[1], publisher: PUBLISHER, version: identity[2], architecture: identity[3], asGame: state.game };
          state.installing = 1;
          return say(202, {});
        }
        case "GET /api/app/packagemanager/state":
          // Still at it the first time it's asked, as a console is.
          if (state.installing-- > 0) return say(204);
          state.installed.push(namesOf(state.sent).fullName);
          return say(200, { Success: true });
        case "GET /api/app/packagemanager/packages": return say(200, { InstalledPackages: state.installed.map((name) => ({ PackageFullName: name })) });
        case "POST /api/taskmanager/app":
          // A console only just done installing refuses the first launch.
          if (state.launches++ === 0) return say(500, { Reason: "0x8D160120" });
          if (!state.installed.includes(unpacked("package")) || unpacked("appid") !== namesOf(state.sent).appUserModelID) return say(404, { Reason: "no such app" });
          state.running = unpacked("package");
          return say(200, {});
        case "GET /api/resourcemanager/processes": return say(200, { Processes: state.running ? [{ PackageFullName: state.running }] : [] });
        case "GET /ext/screenshot": return say(200, encode(2, 2, Buffer.alloc(16, 200)));
        case "GET /api/filesystem/apps/file": return state.installed.includes(url.searchParams.get("packagefullname")) ? say(200, Buffer.from("Lamp: 60 frames a second\n")) : say(404, {});
        case "DELETE /api/taskmanager/app": if (state.running === unpacked("package")) state.running = null; return say(200, {});
        case "DELETE /api/app/packagemanager/package": state.installed = state.installed.filter((name) => name !== url.searchParams.get("package")); return say(200, {});
        default: return say(404, {});
      }
    });
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  return { server, state, port: server.address().port };
}

test("a page goes on an Xbox, is looked at there, stopped and taken off", async () => {
  const home = mkdtempSync(join(tmpdir(), "lamp-devices-test-"));
  process.env.LAMP_DEVICES_HOME = join(home, "devices");
  process.env.LAMP_DEV_HOME = join(home, "dev");
  const console_ = await portal("made-up-password");
  try {
    // The Xbox's integration as it ships, at the stand-in's port.
    const integration = JSON.parse(JSON.stringify(integrationOf("xbox-one")).replaceAll('"port":11443', `"port":${console_.port}`).replaceAll('"tcp":11443', `"tcp":${console_.port}`));
    const device = { id: "xbox-one:uuid:made-up", integration: "xbox-one", name: "Den Xbox", model: "Xbox One", address: "127.0.0.1" };
    const runner = new Runner({ integration, device, reach: () => true, pause: async () => {} });

    // Setup: Developer Mode answers, then the password, which the console turns away until it's the right one.
    const [developerMode, password] = integration.steps;
    assert.equal((await runner.check(developerMode)).passed, true);
    runner.passed(developerMode);
    assert.equal((await runner.check(password)).needs, "password");
    fields.save(device.id, "password", "a-wrong-one");
    assert.equal((await runner.check(password)).rejected, true);
    fields.save(device.id, "password", "made-up-password");
    const checked = await runner.check(password);
    assert.equal(checked.passed, true);
    runner.passed(password, checked.read);
    assert.equal(kept(device.id).model, "Xbox Series X", "the model its Device Portal gives, finer than what it said when found");
    assert.equal(isReady(device, integration), true);

    // A game's page: its own files, with Lamp's runtime beside it.
    const folder = join(home, "harbor-racer");
    mkdirSync(folder);
    writeFileSync(join(folder, "index.html"), "<!doctype html><title>Harbor Racer</title><script type=module src=game.js></script>");
    writeFileSync(join(folder, "lamp-game.js"), "export const game = {};\n");
    writeFileSync(join(folder, "game.js"), "import './lamp-game.js';\n");
    const layout = layoutOf(folder), said = [];
    const put = await putOn(layout, device, { runner, said: (line) => said.push(line) });

    assert.equal(put.game, true);
    assert.equal(console_.state.sent.asGame, "true", "installed as a game, which the console gives more to");
    assert.deepEqual(console_.state.settings, ["true", "false"], "and the console's setting put back as it was once the game had opened");
    assert.equal(console_.state.running, namesOf(put.identity).fullName, "open, launched again after the console refused the first time");
    const sent = readFileSync(join(put.folder, "package.msix")).toString("latin1");
    assert.match(sent, /Web\/lamp-device\.js/);
    assert.match(sent, /for the device this copy of the game is on \(xbox-one\)/, "the game is told it's on an Xbox");
    assert.match(sent, /Web\/index\.html/);

    const seen = await lookOn(layout, device, { runner });
    assert.equal(seen.running, true);
    assert.deepEqual(seen.size, { width: 2, height: 2 });
    assert.match(seen.log, /60 frames a second/);

    // A change goes on as a newer version, which replaces the copy there.
    const again = await putOn(layout, device, { runner });
    assert.notEqual(again.identity.version, put.identity.version);
    assert.equal(console_.state.running, namesOf(again.identity).fullName);

    assert.equal(await stopOn(layout, device, { runner }), true);
    assert.equal(console_.state.running, null);
    assert.equal(await removeFrom(layout, device, { runner }), true);
    assert.ok(!console_.state.installed.includes(namesOf(again.identity).fullName));
    assert.equal(await removeFrom(layout, device, { runner }), false, "nothing of lamp's left to take off");

    // A console showing another certificate than the one lamp keeps for it gets nothing: not the password, not a package.
    const impostor = await portal("made-up-password");
    try {
      const other = JSON.parse(JSON.stringify(integration).replaceAll(`"port":${console_.port}`, `"port":${impostor.port}`));
      pinsOf(device.id).admit("0".repeat(64), String(impostor.port));
      const refused = await new Runner({ integration: other, device, reach: () => true, pause: async () => {} }).check(other.steps[1]);
      assert.equal(refused.passed, false);
      assert.equal(refused.failed, true);
      assert.match(refused.why, /certificate has changed/);
    } finally { impostor.server.close(); impostor.server.closeAllConnections(); }
  } finally {
    console_.server.close();
    console_.server.closeAllConnections?.();
    rmSync(home, { recursive: true, force: true });
  }
});

test("a device that asks for a digest is answered with what its challenge makes of the password, never the password", async () => {
  const { createHash } = await import("node:crypto");
  const http = await import("node:http");
  const { send } = await import("../devices.mjs");
  const md5 = (text) => createHash("md5").update(text).digest("hex"), seen = [];
  const server = http.createServer((asked, answer) => {
    const given = asked.headers.authorization ?? "";
    seen.push(given);
    const part = (name) => new RegExp(`${name}="?([^",]+)"?`).exec(given)?.[1];
    const right = md5(`${md5("rokudev:Made Up TV:made-up-password")}:abc123:${part("nc")}:${part("cnonce")}:auth:${md5(`GET:${asked.url}`)}`);
    if (given.startsWith("Digest ") && part("response") === right && part("opaque") === "o1") { answer.writeHead(200); return answer.end("in"); }
    answer.writeHead(401, { "WWW-Authenticate": 'Digest realm="Made Up TV", nonce="abc123", qop="auth", opaque="o1", algorithm=MD5' });
    answer.end();
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  try {
    const request = { port: server.address().port, path: "/plugin_install?x=1", auth: { user: "rokudev", password: "{field:password}", digest: true } };
    const answer = await send(request, "127.0.0.1", { "field:password": "made-up-password" }, { reach: () => true });
    assert.equal(answer.text, "in");
    assert.equal(seen[0], "", "nothing of the sign-in before the device asks");
    assert.ok(!seen.join(" ").includes("made-up-password") && !seen.join(" ").includes(Buffer.from("rokudev:made-up-password").toString("base64")));
    assert.equal((await send(request, "127.0.0.1", { "field:password": "a-wrong-one" }, { reach: () => true })).status, 401);
  } finally { server.close(); server.closeAllConnections?.(); }

  // A device that asks plainly when a digest was declared doesn't get the password in the clear, one that asks for a
  // digest when a plain sign-in was declared gets nothing, and an answer that points elsewhere is the answer.
  const asked = [];
  const other = http.createServer((request, answer) => {
    asked.push(`${request.url} ${request.headers.authorization ?? ""}`);
    if (request.url === "/moved") { answer.writeHead(302, { Location: "http://example.com/" }); return answer.end(); }
    answer.writeHead(401, { "WWW-Authenticate": request.url === "/plain" ? 'Basic realm="x"' : 'Digest realm="x", nonce="n", qop="auth"' });
    answer.end();
  });
  await new Promise((done) => other.listen(0, "127.0.0.1", done));
  try {
    const port = other.address().port, values = { "field:password": "made-up-password" }, options = { reach: () => true };
    assert.equal((await send({ port, path: "/plain", auth: { user: "u", password: "{field:password}", digest: true } }, "127.0.0.1", values, options)).status, 401);
    assert.equal((await send({ port, path: "/digest", auth: { user: "u", password: "{field:password}" } }, "127.0.0.1", values, options)).status, 401);
    assert.equal((await send({ port, path: "/moved" }, "127.0.0.1", {}, options)).status, 302);
    assert.deepEqual(asked, ["/plain ", "/digest ", "/moved "], "each asked once, with nothing of the sign-in");
  } finally { other.close(); other.closeAllConnections?.(); }
});

test("a device's certificate is kept the first time, and another is taken only when the device's own root signed it", async () => {
  const { createHash } = await import("node:crypto");
  const { pinsAt } = await import("../devices.mjs");
  const home = mkdtempSync(join(tmpdir(), "lamp-pins-test-")), file = join(home, "certificates.json");
  const fingerprint = (certificate) => createHash("sha256").update(certificate).digest("hex");
  try {
    // Each port keeps its own, another request finds it kept, and one that differs is refused with the store as it was.
    assert.equal(pinsAt(file).admit("first", "443"), null);
    assert.equal(pinsAt(file).admit("other", "11443"), null);
    assert.equal(pinsAt(file).admit("first", "443"), null);
    const saved = readFileSync(file);
    assert.match(pinsAt(file).admit("replacement", "443"), /certificate has changed/);
    assert.deepEqual(readFileSync(file), saved);

    // A store that's there but can't be read as one takes nothing, and is left as it is.
    for (const text of ["not json", '{"443":42}', "[]"]) {
      writeFileSync(file, text);
      assert.match(pinsAt(file).admit("first", "443"), /couldn't keep/);
      assert.equal(readFileSync(file, "utf8"), text);
    }
    rmSync(file);

    // Made with openssl for this test: two roots, leaves a and b from the first, c from the second.
    const [root, otherRoot, a, b, c] = ["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"].map((text) => Buffer.from(text, "base64"));
    const pins = pinsAt(file);
    assert.equal(pins.admit(fingerprint(a), "11443", a), null);
    assert.match(pins.admit(fingerprint(b), "11443", b), /changed/, "no root kept yet");
    assert.equal(pins.keepRoot(otherRoot, a, "11443"), false, "a root that didn't sign the kept certificate");
    assert.equal(pins.keepRoot(root, b, "11443"), false, "only for the certificate that's kept");
    assert.equal(pins.keepRoot(root, a, "11443"), true);
    assert.equal(pins.admit(fingerprint(b), "11443", b), null, "the same device, with a certificate its root made since");
    assert.match(pins.admit(fingerprint(c), "11443", c), /changed/);
    assert.match(pins.admit(fingerprint(c), "11443"), /changed/, "nothing to check it against");
    assert.equal(JSON.parse(readFileSync(file, "utf8"))["11443"], fingerprint(b));
  } finally { rmSync(home, { recursive: true, force: true }); }
});

test("a request goes only to a device on the person's network, by a path that stays on it", async () => {
  const { send, isPrivate, OffNetwork } = await import("../devices.mjs");
  for (const address of ["192.168.1.20", "10.0.0.5", "172.20.1.1", "169.254.3.4", "fd12::1", "fe80::1:2:3:4"]) assert.equal(isPrivate(address), true, address);
  // Never this computer, the internet, or a name that could lead anywhere.
  for (const address of ["127.0.0.1", "::1", "8.8.8.8", "172.32.0.1", "roku.local", "example.com", "0.0.0.0", "::ffff:127.0.0.1"]) {
    assert.equal(isPrivate(address), false, address);
    await assert.rejects(send({ port: 80, path: "/" }, address, {}), OffNetwork, address);
  }
  for (const path of ["//evil.example/", "/a/../b", "/x@evil.example", "x", "/a b", "/a?b=1 HTTP/1.1\r\nX: y"]) {
    await assert.rejects(send({ port: 80, path }, "192.168.1.20", {}, { reach: () => true, timeout: 200 }), /the path/, path);
  }
  await assert.rejects(send({ port: 80, path: "/", headers: { "X-A": "b\r\nX-C: d" } }, "192.168.1.20", {}, { reach: () => true, timeout: 200 }), /header X-A/);
  // What the person typed goes over HTTPS only to a device whose certificate is kept, and so does a maker's sign-in.
  const signIn = { https: true, port: 11443, path: "/api/os/info", auth: { user: "lamp", password: "{field:password}" } };
  await assert.rejects(send(signIn, "192.168.1.20", { "field:password": "made-up-password" }, { reach: () => true, timeout: 200 }), /whose certificate it keeps/);
  await assert.rejects(send({ https: true, port: 443, path: "/", headers: { Authorization: "Bearer {signIn}" } }, "192.168.1.20", { signIn: "made-up token" }, { reach: () => true, timeout: 200 }), /whose certificate it keeps/);

  // Each value goes only where it can do no more than be a value.
  const { fill } = await import("../devices.mjs");
  assert.equal(fill("/keypress/Lit_{text}", { text: "a b/é?" }, "path"), "/keypress/Lit_a%20b%2F%C3%A9%3F", "text being typed can't change the path");
  assert.equal(fill("/app?package={base64:packageFullName}", { packageFullName: "Lamp.x_1.0_x64__abc" }, "path"), "/app?package=TGFtcC54XzEuMF94NjRfX2FiYw%3D%3D");
  assert.equal(fill("Bearer {signIn}", { signIn: "made-up token" }, "header"), "Bearer made-up token");
  assert.throws(() => fill("/x?token={signIn}", { signIn: "t" }, "path"), /goes only in a sign-in/);
  assert.throws(() => fill("/x?token={base64:signIn}", { signIn: "t" }, "path"), /isn't secret/);
  assert.throws(() => fill("X: {text}", { text: "a" }, "header"), /goes only in a path, a form or a body/);
  assert.throws(() => fill("/x/{appID}", { appID: "a b" }, "path"), /characters lamp doesn't send/);
});

test("a look finds an integration's device in its one search, and reads one nobody knows from the description that names it", async () => {
  const { addressesOf, answerOf, bonjour, describe, identify, servicesIn } = await import("../devices.mjs");
  const http = await import("node:http");
  const xbox = { id: "xbox-test", name: "Xbox", maker: "Microsoft", find: [{ ssdp: "urn:schemas-upnp-org:device:MediaRenderer:1", contains: "UPnP-Device-Host" }],
    identity: { os: "Xbox OS", id: { description: true, xml: "device/UDN" }, model: { description: true, xml: "device/modelName", contains: "Xbox" } } };
  const said = (address, target, server, location) => answerOf(`HTTP/1.1 200 OK\r\nST: ${target}\r\nSERVER: ${server}\r\nLOCATION: ${location}\r\n`, address);
  const windows = "Microsoft-Windows/10.0 UPnP/1.0 UPnP-Device-Host/1.0";
  const answers = [
    said("192.168.1.30", "upnp:rootdevice", windows, "http://192.168.1.30:1/root.xml"),
    said("192.168.1.30", "urn:schemas-upnp-org:device:mediarenderer:1", windows, "http://192.168.1.30:10247/renderer.xml"),
    said("192.168.1.40", "urn:schemas-upnp-org:device:MediaRenderer:1", "Linux UPnP/1.0 Sonos/86.10", "http://192.168.1.40:1400/xml"),
  ];
  assert.deepEqual(await addressesOf(xbox, answers), ["192.168.1.30"], "its search target, whatever its case, and its server's words");

  // Read from the description its answer to that search points at: not the root device's, which answered first.
  const server = http.createServer((asked, answer) => {
    answer.writeHead(asked.url === "/renderer.xml" ? 200 : 404);
    answer.end(asked.url === "/renderer.xml" ? "<root><device><UDN>uuid:made-up</UDN><modelName>Xbox Series X</modelName><friendlyName>Den Xbox</friendlyName></device></root>" : "");
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  try {
    const here = [said("127.0.0.1", "upnp:rootdevice", windows, "http://127.0.0.1:1/root.xml"),
      said("127.0.0.1", "urn:schemas-upnp-org:device:MediaRenderer:1", windows, `http://127.0.0.1:${server.address().port}/renderer.xml`)];
    const read = await identify(xbox, "127.0.0.1", here, { reach: () => true });
    assert.deepEqual({ serial: read.serial, model: read.model, name: read.name }, { serial: "uuid:made-up", model: "Xbox Series X", name: null });
  } finally { server.close(); server.closeAllConnections?.(); }

  // An LG TV, as recorded (Tests/Fixtures/lg-webos-tv): its first answer's description says nothing of it, a later one names it.
  const recorded = new URL("../../Tests/Fixtures/lg-webos-tv/", import.meta.url);
  const lg = readFileSync(new URL("ssdp.txt", recorded), "utf8").split("\n\n").map((text) => answerOf(text, "192.168.1.20"));
  const tv = await describe("192.168.1.20", lg, { get: async ({ port }) => {
    try { const body = readFileSync(new URL(`${port}.xml`, recorded)); return { ok: true, status: 200, body, text: body.toString("utf8") }; } catch { return { ok: false, status: 404 }; }
  } });
  assert.equal(tv.name, "[LG] webOS TV NANO80ASA");
  assert.equal(tv.address, "192.168.1.20");
  // A router answers every search, and nobody makes apps for it.
  const router = await describe("192.168.1.1", [said("192.168.1.1", "upnp:rootdevice", "Linux UPnP/1.0", "http://192.168.1.1:5000/rootDesc.xml")], {
    get: async () => ({ ok: true, body: Buffer.from("<root><device><deviceType>urn:schemas-upnp-org:device:InternetGatewayDevice:1</deviceType><friendlyName>Router</friendlyName><manufacturer>Made Up</manufacturer></device></root>") }) });
  assert.equal(router, null);

  // A Bonjour answer: the service's name, at the address of the host it names (its name written once and pointed to after).
  const name = (labels) => Buffer.concat([...labels.map((label) => Buffer.concat([Buffer.from([Buffer.byteLength(label)]), Buffer.from(label)])), Buffer.from([0])]);
  const record = (owner, type, data) => { const fixed = Buffer.alloc(10); fixed.writeUInt16BE(type, 0); fixed.writeUInt16BE(1, 2); fixed.writeUInt32BE(10, 4); fixed.writeUInt16BE(data.length, 8); return Buffer.concat([owner, fixed, data]); };
  const header = Buffer.alloc(12); header.writeUInt16BE(0x8400, 2); header.writeUInt16BE(1, 6); header.writeUInt16BE(2, 10);
  const instance = name(["Den Speaker", "_sonos", "_tcp", "local"]), srv = Buffer.concat([Buffer.from([0, 0, 0, 0, 5, 0x78]), name(["speaker-2", "local"])]);
  const packet = Buffer.concat([header, record(name(["_sonos", "_tcp", "local"]), 12, instance), record(instance, 33, srv), record(name(["speaker-2", "local"]), 1, Buffer.from([192, 168, 1, 40]))]);
  assert.deepEqual(servicesIn(packet, "_sonos._tcp", "192.168.1.99"), [{ name: "Den Speaker", address: "192.168.1.40" }]);
  // The type written once, in the question, and pointed to after: from the answer's owner and from inside the service's name.
  const asking = Buffer.alloc(12); asking.writeUInt16BE(0x8400, 2); asking.writeUInt16BE(1, 4); asking.writeUInt16BE(1, 6);
  const question = Buffer.concat([name(["_sonos", "_tcp", "local"]), Buffer.from([0, 12, 0, 1])]);
  const kitchen = Buffer.concat([Buffer.from([7]), Buffer.from("Kitchen"), Buffer.from([0xc0, 12])]);
  const pointed = Buffer.concat([asking, question, record(Buffer.from([0xc0, 12]), 12, kitchen)]);
  assert.deepEqual(servicesIn(pointed, "_sonos._tcp", "192.168.1.41"), [{ name: "Kitchen", address: "192.168.1.41" }],
    "a name pointed to, and the address the answer came from when it names no host");
  const looping = Buffer.concat([asking.subarray(0, 4), Buffer.from([0, 0, 0, 1, 0, 0, 0, 0]), Buffer.from([0xc0, 12]), Buffer.alloc(10)]);
  assert.deepEqual(servicesIn(looping, "_sonos._tcp", "192.168.1.41"), [], "a name that points at itself ends");
  assert.deepEqual(servicesIn(Buffer.from([1, 2, 3]), "_sonos._tcp", "192.168.1.41"), [], "an answer that can't be read says nothing");
  assert.deepEqual(await bonjour("not a type"), [], "only a service type is asked for");
});

test("an Xbox's install is waited for, and its app launched again until it runs, or said not to have opened", async () => {
  const http = await import("node:http");
  const { Runner, integrationOf } = await import("../devices.mjs");
  const names = { packageFullName: "Lamp.test_1.0.0.0_x64__abc", appUserModelID: "Lamp.test_abc!App" };
  // A made-up console answering each path from its own script, in turn, the last answer over and over.
  let script = {}, asked = {};
  const server = http.createServer((request, answer) => {
    const path = request.url.split("?")[0], list = script[path] ?? [[200, {}]];
    asked[path] = (asked[path] ?? 0) + 1;
    const [status, body] = list.length > 1 ? list.shift() : list[0];
    // It hands out the token a change must carry, as a console does.
    answer.writeHead(status, { "content-type": "application/json", "set-cookie": "CSRF-Token=made-up; Path=/" });
    answer.end(JSON.stringify(body));
  });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  try {
    // The console's sequences as it ships them, over plain HTTP to the stand-in, with no sign-in.
    const plain = (bridge) => Object.fromEntries(Object.entries(bridge).map(([name, actions]) => [name, Array.isArray(actions)
      ? actions.map((action) => (action.http ? { ...action, http: { ...action.http, https: false, port: server.address().port, auth: undefined } } : action)) : actions]));
    const bridge = plain(integrationOf("xbox-one").bridge);
    const runner = new Runner({ integration: integrationOf("xbox-one"), device: { id: "xbox-one:made-up", name: "Den Xbox", address: "127.0.0.1" },
      values: { "field:password": "made-up-password" }, pins: { admit: () => null, root: () => null, keepRoot: () => false }, reach: () => true, pause: async () => {} });
    const listing = (key, has) => [200, { [key]: [...(has ? [{ PackageFullName: names.packageFullName }] : []), { PackageFullName: "Other.app_1.0.0.0_x64__xyz" }] }];

    // Installed: the state says so, and the package is listed on the second ask.
    script = { "/api/app/packagemanager/state": [[200, { Success: true }]], "/api/app/packagemanager/packages": [listing("InstalledPackages", false), listing("InstalledPackages", true)] };
    asked = {};
    await runner.run(bridge.install.slice(-2), { extra: names });
    assert.equal(asked["/api/app/packagemanager/packages"], 2);

    // Refused twice, then opened and running.
    const refused = [400, { ErrorMessage: "Failed to launch the application.", ErrorCode: -1927937760 }];
    script = { "/api/taskmanager/app": [refused, refused, [200, {}]], "/api/resourcemanager/processes": [listing("Processes", true)] };
    asked = {};
    assert.equal((await runner.open(bridge.launch, bridge.running, { extra: names })).opened, true);
    assert.equal(asked["/api/taskmanager/app"], 3);

    // Taken, but not running through the whole check, so launched again; then running.
    script = { "/api/resourcemanager/processes": [...Array(9).fill(listing("Processes", false)), listing("Processes", true)] };
    asked = {};
    assert.equal((await runner.open(bridge.launch, bridge.running, { extra: names })).opened, true);
    assert.equal(asked["/api/taskmanager/app"], 2);

    // Never running: said, not claimed open.
    script = { "/api/resourcemanager/processes": [listing("Processes", false)] };
    assert.deepEqual(await runner.open(bridge.launch, bridge.running, { extra: names, tries: 3 }), { opened: false, launched: true, refused: null });

    // Stopped by whoever asked: the launches end between tries.
    const stopping = new AbortController();
    const stopped = new Runner({ ...runner, integration: runner.integration, device: runner.device, values: runner.given, pins: runner.pins, reach: () => true,
      pause: async () => { stopping.abort(); }, stopped: stopping.signal });
    await assert.rejects(stopped.open(bridge.launch, bridge.running, { extra: names, tries: 5 }), /stopped/);
  } finally { server.close(); server.closeAllConnections?.(); }
});

test("a setup's check tells a device that holds from one that answers otherwise, one away, and one that turns the sign-in away", async () => {
  const http = await import("node:http");
  const { Runner } = await import("../devices.mjs");
  let status = 200, body = "<device-info><developer-enabled>true</developer-enabled></device-info>";
  const server = http.createServer((request, answer) => { answer.writeHead(status); answer.end(body); });
  await new Promise((done) => server.listen(0, "127.0.0.1", done));
  try {
    const port = server.address().port, device = { id: "roku:made-up", name: "Den Roku", address: "127.0.0.1" };
    const runner = (values = {}) => new Runner({ integration: { id: "roku", steps: [] }, device, values, pins: { admit: () => null, root: () => null }, reach: () => true });
    const enabled = [{ http: { port, path: "/query/device-info" }, xml: "developer-enabled", equals: "true" }];
    assert.deepEqual(await runner().evaluate(enabled), { verdict: "holds", read: "true" });
    body = "<device-info><developer-enabled>false</developer-enabled></device-info>";
    assert.deepEqual(await runner().evaluate(enabled), { verdict: "waiting", why: "Waiting for Den Roku…" });
    assert.equal((await runner().evaluate([{ tcp: 1 }])).verdict, "away");
    assert.deepEqual(await runner().evaluate([{ field: "password" }]), { verdict: "waiting", why: "Waiting for what you type.", needs: "password" });
    assert.equal((await runner().evaluate([{ signedIn: true }])).why, "Waiting for you to sign in.");
    status = 401;
    const signIn = [{ field: "password" }, { http: { port, path: "/plugin_install", auth: { user: "rokudev", password: "{field:password}" } } }];
    const rejected = await runner({ "field:password": "a-wrong-one" }).evaluate(signIn);
    assert.equal(rejected.verdict, "rejected");
    assert.equal(rejected.why, "The device rejected the sign-in. Check the user name and password, then try again.");
    status = 200;
    assert.equal((await runner({ "field:password": "made-up-password" }).evaluate(signIn)).verdict, "holds");
  } finally { server.close(); server.closeAllConnections?.(); }
});
