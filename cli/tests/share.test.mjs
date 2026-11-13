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
import { createAccountHandler } from "../../site/lib/accounts.js";

const home = mkdtempSync(join(tmpdir(), "lamp-share-test-"));
process.env.LAMP_DEV_HOME = join(home, "state");
process.env.LAMP_BROWSER = "";
const { share, unshare, ideas, finishIdea, readLink, githubRepoOf, keepAccount } = await import("../share.mjs");
const { askAccount, accountName } = await import("../link.mjs");
const { layoutOf } = await import("../state.mjs");

const store = memoryStore();
// The emails the site sends, kept to read their links.
const mail = [];
const handlers = {
  "/api/accounts": createAccountHandler({ store, limited: false, env: { RESEND_API_KEY: "test", LAMP_IDEAS_FROM: "Lamp <ideas@lamp.dev>" },
    fetcher: async (url, request) => { mail.push(JSON.parse(request.body)); return new Response("{}"); } }),
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
  const headers = Object.fromEntries(["authorization", "content-type", "origin", "x-lamp-account"].filter((name) => incoming.headers[name]).map((name) => [name, incoming.headers[name]]));
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
  const sent = await share({ layout, words, shape: 1.7778, github: "someone/harbor-racer" });
  const link = readLink(layout.folder);
  assert.equal(sent.version, 1);
  assert.equal(store.records.get(link.id).github, "someone/harbor-racer", "the page links to the folder's public repository");
  assert.deepEqual(["git@github.com:someone/harbor-racer.git", "https://github.com/someone/harbor-racer", "https://gitlab.com/someone/harbor-racer"].map(githubRepoOf),
    ["someone/harbor-racer", "someone/harbor-racer", null]);
  assert.match(sent.url, /\/w\/[A-Za-z0-9]{10}-harbor-racer$/);
  const record = store.records.get(link.id);
  assert.deepEqual([record.name, record.by, record.asks, record.shape], [words.name, words.by, words.asks, 1.7778]);
  assert.ok(sent.file && record.file?.version >= 1, "the app's own file goes with the link, for anyone to open in Lamp");
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

test("a copy shared from the link is listed, held beside the app by its own files, and credited once", async () => {
  const { copiesOf, latestOf } = await import("../link.mjs");
  const { creditCopy, differences, fetchCopy } = await import("../copies.mjs");
  const { unpack } = await import("../lampapp.mjs");
  const source = readLink(layout.folder);
  // Someone's copy: the link's file unpacked, changed, and shared as a link of its own.
  const file = join(home, "racer.lampapp"), theirs = join(home, "their-racer");
  writeFileSync(file, Buffer.from(await (await fetch((await latestOf({ id: source.id })).file)).arrayBuffer()));
  unpack(file, theirs);
  writeFileSync(join(theirs, "Web", "game.js"), readFileSync(join(theirs, "Web", "game.js"), "utf8") + "\n// a stadium\n");
  writeFileSync(join(theirs, "Web", "stadium.js"), "export const seats = 400;\n");
  const copy = await share({ layout: layoutOf(theirs), words: { ...words, name: "Harbor Racer Stadium", by: "Sam Lee" }, github: null });
  assert.deepEqual((await copiesOf({ site: origin, id: source.id })).map((one) => [one.name, one.by, one.url]), [["Harbor Racer Stadium", "Sam Lee", copy.url]]);

  const id = readLink(layoutOf(theirs).folder).id, latest = await latestOf({ id });
  const opened = await fetchCopy(folder, latest);
  assert.ok(opened.folder.startsWith(process.env.LAMP_DEV_HOME), "a copy is laid out in lamp's state, never in the person's folders");
  const found = differences(folder, opened.folder);
  assert.deepEqual([found.onlyTheirs.map((one) => one.path), found.onlyYours, found.changed.map((one) => [one.path, one.about])],
    [["Web/stadium.js"], [], [["Web/game.js", "+2 -0 lines in theirs"]]], "Lamp's own files beside the page count in neither");
  const credit = { name: latest.name, by: latest.by, url: `${origin}/w/${id}`, id };
  assert.deepEqual([creditCopy(folder, credit), creditCopy(folder, credit)], ["added", "already"]);
  assert.deepEqual(JSON.parse(readFileSync(join(folder, "credits.json"), "utf8")).upstream.filter((one) => one.url === credit.url),
    [{ name: "Harbor Racer Stadium", author: "Sam Lee", url: credit.url }]);
  // Its next share names the copy it took changes from (here a link on a site that isn't lamp.dev, so its license is asked).
  await share({ layout, words, github: null, anyway: true });
  assert.deepEqual(store.records.get(source.id).with, [id]);
  rmSync(join(folder, "credits.json"));
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
  assert.deepEqual([again.version, again.url, store.records.get(link.id).line], [3, link.url, "Now with a lighthouse."]);
  assert.match(await (await played(link.id, 3, "game.js")).text(), /a lighthouse/);

  await unshare(layout.folder);
  assert.equal(store.records.has(link.id), false);
  assert.equal(readLink(layout.folder), null);
  assert.equal(existsSync(join(process.env.LAMP_DEV_HOME)), true);
});

test("Lamp's app shares a wish's link, sends its file, reads it back, and takes it down through lamp's calls", async () => {
  const { CALLS } = await import("../calls.mjs");
  const body = { name: "Tide Clock", line: "When the tide turns.", words: "A clock for the harbor's tides.", releases: [], picture: null, icon: null };
  const link = await CALLS.linkPublish({ site: origin, body });
  assert.ok(link.url.startsWith(origin) && link.secret && link.id);
  // Changed in place, under the same secret; one the site no longer has is made again.
  assert.equal((await CALLS.linkPublish({ site: origin, body: { ...body, name: "Tide Clock 2" }, earlier: link })).id, link.id);
  // A wish's file as Share… makes one: a zip with lamp-app.json in it, bigger than a part.
  const { zipOf } = await import("../share.mjs");
  const { randomBytes } = await import("node:crypto");
  const file = join(home, "wish.lampapp");
  writeFileSync(file, zipOf([["lamp-app.json", Buffer.from("{}")], ["Sources/big.bin", randomBytes(3_100_000)]]));
  const parts = [];
  await CALLS.linkUpload({ site: origin, id: link.id, secret: link.secret, file }, { event: (said) => parts.push(said.said) });
  assert.equal(parts.length, 2, "a file bigger than a part goes in parts");
  const latest = (await CALLS.linkLatest({ site: origin, id: link.id })).latest;
  assert.equal(latest.name, "Tide Clock 2");
  assert.ok(latest.version >= 1 && latest.file);
  assert.deepEqual((await CALLS.linkIdeas({ site: origin, id: link.id, secret: link.secret })).ideas, []);
  // Only its secret takes it down: another changes nothing.
  await CALLS.linkRemove({ site: origin, id: link.id, secret: "not-its-secret" }).catch(() => {});
  assert.notEqual((await CALLS.linkLatest({ site: origin, id: link.id })).latest, null);
  await CALLS.linkRemove({ site: origin, id: link.id, secret: link.secret });
  assert.equal((await CALLS.linkLatest({ site: origin, id: link.id })).latest, null);
  const again = await CALLS.linkPublish({ site: origin, body, earlier: link });
  assert.notEqual(again.id, link.id, "a link that was taken down is made again");
});

test("with an account, a link goes under its maker's username, and moves there at its next share", async () => {
  const before = readLink(layout.folder) ?? (await share({ layout, words, shape: 1.7778 }), readLink(layout.folder));
  assert.match(before.url, /\/w\//);
  const asked = await askAccount({ site: origin, username: "alex-kim", email: "alex@example.com" });
  keepAccount(origin, { username: asked.username, key: asked.key });
  assert.equal(await accountName({ site: origin, key: asked.key }), null, "not until the email's link is opened");
  await fetch(/https?:\S+confirm=[0-9a-f]+/.exec(mail.at(-1).text)[0].replace(/^https?:\/\/[^/]+/, origin));
  assert.equal(await accountName({ site: origin, key: asked.key }), "alex-kim");
  const again = await share({ layout, words, shape: 1.7778 });
  assert.equal(again.url, `${origin}/alex-kim/harbor-racer`);
  await unshare(layout.folder);
});
