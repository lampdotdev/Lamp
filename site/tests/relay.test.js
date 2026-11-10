// The relay (lib/relay.js) with its Redis and Blob in memory: who may pair and send, one change at a time, what a
// version may hold, and what the cleanup removes.

import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import { test } from "node:test";
import { RELAY_LIMITS, cleanupRelay, createRelayHandler, createRelayPlayHandler } from "../lib/relay.js";
import { memoryBlobs, memoryRedis } from "../lib/relay-store.js";
import { memoryStore } from "../lib/shared-wishes.js";

const SITE = "https://lamp.dev", PLAY = "https://play.lamp.dev", WISH = "abcdefghij";
const sha = (text) => createHash("sha256").update(text).digest("hex");

async function started() {
  const clock = { now: 1_800_000_000_000 };
  const now = () => clock.now;
  const db = memoryRedis({ now }), blobs = memoryBlobs({ origin: "https://blob.test", now }), wishes = memoryStore();
  const at = await wishes.putPageFile(WISH, "t", "index.html", Buffer.from("<p>red</p>"));
  wishes.records.set(WISH, { id: WISH, page: { version: 1, files: { "index.html": at } } });
  const options = { db, blobs, wishes, now, site: SITE, playBase: PLAY, env: {} };
  const relay = createRelayHandler(options), play = createRelayPlayHandler(options);
  const call = async (op, { method = "POST", origin, token, body, query = "", ip = "1.1.1.1" } = {}) => {
    const response = await relay(new Request(`${SITE}/api/relay?op=${op}${query}`, {
      method, body: body ? JSON.stringify(body) : undefined,
      headers: { "x-forwarded-for": ip, ...(origin ? { Origin: origin } : {}), ...(token ? { Authorization: `Bearer ${token}` } : {}) },
    }));
    return { status: response.status, body: await response.json().catch(() => null) };
  };
  const page = async () => (await call("open", { origin: SITE, body: { wish: WISH } })).body;
  const played = async (room, version, host = `r-${room}.play.lamp.dev`) => {
    const response = await play(new Request(`https://${host}/x?room=${room}&v=${version}&path=`));
    return { status: response.status, csp: response.headers.get("content-security-policy"), text: response.status === 200 ? await response.text() : null };
  };
  return { clock, db, blobs, call, page, played };
}

test("a code pairs once, runs out after five minutes, and is traded for a credential of the helper's own", async () => {
  const relay = await started();
  const room = await relay.page();
  const paired = await relay.call("pair", { body: { code: room.code } });
  assert.equal(paired.status, 200);
  assert.notEqual(paired.body.token, room.token);
  assert.equal((await relay.call("pair", { body: { code: room.code } })).status, 404);
  // The helper's credential doesn't open the page's side, nor the page's the helper's.
  assert.equal((await relay.call("state", { method: "GET", token: paired.body.token })).status, 401);
  assert.equal((await relay.call("next", { method: "GET", token: room.token })).status, 401);

  const other = await relay.page();
  relay.clock.now += RELAY_LIMITS.codeMs + 1;
  assert.equal((await relay.call("pair", { body: { code: other.code } })).status, 404);
});

test("pairing is refused from a browser and slowed after five tries a minute", async () => {
  const relay = await started();
  const room = await relay.page();
  assert.equal((await relay.call("pair", { origin: SITE, body: { code: room.code } })).status, 403);
  for (let n = 0; n < 5; n++) assert.equal((await relay.call("pair", { ip: "2.2.2.2", body: { code: "AAAAAA" } })).status, 404);
  assert.equal((await relay.call("pair", { ip: "2.2.2.2", body: { code: room.code } })).status, 429);
});

test("only the page, from the site, asks; the same request is taken once, and one runs at a time", async () => {
  const relay = await started();
  const room = await relay.page();
  const helper = (await relay.call("pair", { body: { code: room.code } })).body.token;
  const first = { id: "request-0001", prompt: "make it green" };
  assert.equal((await relay.call("ask", { origin: `https://r-${room.room}.play.lamp.dev`, token: room.token, body: first })).status, 403);
  assert.equal((await relay.call("ask", { origin: SITE, body: first })).status, 401);
  await relay.call("ask", { origin: SITE, token: room.token, body: first });
  const again = await relay.call("ask", { origin: SITE, token: room.token, body: first });
  assert.equal(again.body.requests.length, 1);
  await relay.call("ask", { origin: SITE, token: room.token, body: { id: "request-0002", prompt: "make it blue" } });

  assert.equal((await relay.call("claim", { token: helper, body: { id: "request-0001" } })).status, 200);
  assert.equal((await relay.call("claim", { token: helper, body: { id: "request-0002" } })).status, 409);
  assert.equal((await relay.call("next", { method: "GET", token: helper })).body.next, null);

  // The helper comes back without having finished it: it's uncertain, said so, and never offered again.
  const settled = await relay.call("reconcile", { token: helper, body: { journal: { "request-0001": "interrupted" } } });
  assert.equal(settled.body.requests.find((one) => one.id === "request-0001").state, "uncertain");
  assert.equal((await relay.call("next", { method: "GET", token: helper })).body.next.id, "request-0002");
});

test("a version's files are checked before it plays; one that doesn't match leaves the game as it was", async () => {
  const relay = await started();
  const room = await relay.page();
  const helper = (await relay.call("pair", { body: { code: room.code } })).body.token;
  const send = async (id, text, sent = text) => {
    await relay.call("ask", { origin: SITE, token: room.token, body: { id, prompt: "green" } });
    await relay.call("claim", { token: helper, body: { id } });
    const asked = await relay.call("upload", { token: helper, body: { id, files: [{ path: "index.html", size: Buffer.byteLength(text), sha256: sha(text) }] } });
    for (const upload of asked.body.uploads) {
      await relay.blobs.upload(new Request(upload.url, { method: "PUT", headers: upload.headers, body: sent }));
    }
    return relay.call("commit", { token: helper, body: { id, build: asked.body.build } });
  };
  const id = "request-0003";
  await relay.call("ask", { origin: SITE, token: room.token, body: { id, prompt: "x" } });
  await relay.call("claim", { token: helper, body: { id } });
  assert.equal((await relay.call("upload", { token: helper, body: { id, files: [{ path: "../escape.js", size: 1, sha256: sha("x") }] } })).status, 422);
  assert.equal((await relay.call("upload", { token: helper, body: { id, files: [{ path: "game.js", size: 1, sha256: sha("x") }] } })).status, 422);
  await relay.call("finish", { token: helper, body: { id, state: "failed" } });

  assert.equal((await send("request-0004", "<p>green</p>", "<p>green!</p>")).status, 422);
  assert.equal((await relay.played(room.room, 1)).text, "<p>red</p>");
  await relay.call("finish", { token: helper, body: { id: "request-0004", state: "failed" } });

  const done = await send("request-0005", "<p>green</p>");
  assert.deepEqual([done.status, done.body.version], [200, 2]);
  const served = await relay.played(room.room, 2);
  assert.equal(served.text, "<p>green</p>");
  assert.equal(served.csp, `frame-ancestors ${SITE}`);
  assert.equal((await relay.played(room.room, 2, "r-0000000000000000.play.lamp.dev")).status, 404);
});

test("the cleanup removes the files of a room that's gone and those no version points at", async () => {
  const relay = await started();
  const room = await relay.page();
  relay.blobs.files.set(`relay/memory/${room.room}/aaaaaaaaaaaa/${sha("old")}`, { bytes: Buffer.from("old"), uploadedAt: relay.clock.now });
  relay.blobs.files.set(`relay/memory/0123456789abcdef/bbbbbbbbbbbb/${sha("gone")}`, { bytes: Buffer.from("gone"), uploadedAt: relay.clock.now });
  assert.equal((await cleanupRelay({ db: relay.db, blobs: relay.blobs, now: () => relay.clock.now })).removed, 1);
  relay.clock.now += RELAY_LIMITS.uploadMs * 2 + 1;
  assert.equal((await cleanupRelay({ db: relay.db, blobs: relay.blobs, now: () => relay.clock.now })).removed, 1);
  assert.equal(relay.blobs.files.size, 0);
});
