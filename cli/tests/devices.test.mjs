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
});
