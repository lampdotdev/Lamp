// lamp share against the site's own handlers (site/lib/shared-wishes.js), kept in memory: what goes up is what the
// site takes and plays, the link's secret stays out of the folder, and ideas come back to whoever shared it. Nothing
// here reaches lamp.dev.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";
import { existsSync, mkdtempSync, readFileSync, readdirSync, rmSync, writeFileSync } from "node:fs";
import { createServer } from "node:http";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { createShareHandler, createFileHandler, createIdeasHandler, createPlayHandler, memoryStore } from "../../site/lib/shared-wishes.js";

const home = mkdtempSync(join(tmpdir(), "lamp-share-test-"));
process.env.LAMP_DEV_HOME = join(home, "state");
process.env.LAMP_BROWSER = "";
const { share, unshare, ideas, finishIdea, readLink } = await import("../share.mjs");
const { layoutOf } = await import("../state.mjs");

const store = memoryStore();
const handlers = {
  "/api/wishes": createShareHandler({ store, limited: false }),
  "/api/wish-file": createFileHandler({ store, limited: false }),
  "/api/wish-ideas": createIdeasHandler({ store, limited: false, env: {} }),
  "/api/wish-play": createPlayHandler({ store, anyHost: true, env: {} }),
};
// The site's handlers take and give the web's own requests and answers: this stands between them and a socket.
const site = createServer(async (incoming, outgoing) => {
  const url = new URL(incoming.url, `http://${incoming.headers.host}`);
  const handler = handlers[url.pathname];
  if (!handler) { outgoing.writeHead(404); outgoing.end(); return; }
  const chunks = [];
  for await (const chunk of incoming) chunks.push(chunk);
  const headers = Object.fromEntries(["authorization", "content-type", "origin"].filter((name) => incoming.headers[name]).map((name) => [name, incoming.headers[name]]));
  const answer = await handler(new Request(url, { method: incoming.method, headers, body: chunks.length ? Buffer.concat(chunks) : undefined }));
  outgoing.writeHead(answer.status, Object.fromEntries(answer.headers));
  outgoing.end(Buffer.from(await answer.arrayBuffer()));
});

let origin, folder, layout;
const words = { name: "Harbor Racer", words: "Steer a little boat around the harbor and collect the buoys.", by: "Alex Kim", asks: ["Found a bug?"] };
const played = async (id, version, path) => fetch(`${origin}/api/wish-play?id=${id}&v=${version}&path=${encodeURIComponent(path)}`);

before(async () => {
  await new Promise((done) => site.listen(0, "127.0.0.1", done));
  origin = `http://127.0.0.1:${site.address().port}`;
  process.env.LAMP_SITE = origin;
  folder = join(home, "harbor-racer");
  const made = spawnSync(process.execPath, [join(import.meta.dirname, "..", "lamp.mjs"), "new", folder, "--name", words.name], { encoding: "utf8" });
  assert.equal(made.status, 0, made.stderr);
  // A game whose folder has none of Lamp's own files is whole on the link all the same.
  for (const file of ["lamp-controllers.js", "lamp-device.js", "lamp.js"]) rmSync(join(folder, file));
  layout = layoutOf(folder);
});

after(async () => {
  site.closeAllConnections?.();
  await new Promise((done) => site.close(done));
  rmSync(home, { recursive: true, force: true });
});

test("a shared game plays from its link whole, and its secret stays out of its folder", async () => {
  const sent = await share({ layout, words, shape: 1.7778 });
  const link = readLink(layout.folder);
  assert.equal(sent.version, 1);
  assert.match(sent.url, /\/w\/[A-Za-z0-9]{10}-harbor-racer$/);
  const record = store.records.get(link.id);
  assert.deepEqual([record.name, record.by, record.asks, record.shape], [words.name, words.by, words.asks, 1.7778]);
  // What the page and the runtime ask for is all there; the app's notes aren't part of the page.
  for (const path of ["index.html", "game.js", "lamp-game.js", "lamp-controllers.js", "lamp-device.js", "lamp-build.js", "lamp.js", "three/three.module.js"]) {
    assert.equal((await played(link.id, 1, path)).status, 200, path);
  }
  assert.match(await (await played(link.id, 1, "index.html")).text(), /<title>Harbor Racer<\/title>/);
  assert.equal((await played(link.id, 1, "APP.md")).status, 404);
  // The secret is whoever shared it's alone: with lamp's own state, never in the folder that's committed and sent.
  assert.match(link.secret, /^[A-Za-z0-9_-]{43}$/);
  const inFolder = (dir) => readdirSync(dir, { withFileTypes: true }).flatMap((entry) => (entry.isDirectory() ? (entry.name === "three" || entry.name === "phaser" ? [] : inFolder(join(dir, entry.name))) : [join(dir, entry.name)]));
  assert.ok(inFolder(folder).every((file) => !readFileSync(file).includes(link.secret)));
});

test("ideas sent to the link come back to whoever shared it, and sharing again keeps the link", async () => {
  const link = readLink(layout.folder);
  const posted = await fetch(`${origin}/api/wish-ideas?id=${link.id}`, { method: "POST", headers: { "content-type": "application/json" }, body: JSON.stringify({ text: "Add a lighthouse." }) });
  assert.equal(posted.status, 201);
  assert.deepEqual((await ideas(layout.folder)).ideas.map((idea) => [idea.n, idea.text]), [[1, "Add a lighthouse."]]);
  assert.deepEqual(await finishIdea(layout.folder, 1, true), { notified: false });
  assert.deepEqual((await ideas(layout.folder)).ideas, []);

  writeFileSync(join(folder, "game.js"), readFileSync(join(folder, "game.js"), "utf8") + "\n// a lighthouse\n");
  const again = await share({ layout, words: { ...words, line: "Now with a lighthouse." }, shape: 1.7778 });
  assert.deepEqual([again.version, again.url, store.records.get(link.id).line], [2, link.url, "Now with a lighthouse."]);
  assert.match(await (await played(link.id, 2, "game.js")).text(), /a lighthouse/);

  await unshare(layout.folder);
  assert.equal(store.records.has(link.id), false);
  assert.equal(readLink(layout.folder), null);
  assert.equal(existsSync(join(process.env.LAMP_DEV_HOME)), true);
});
