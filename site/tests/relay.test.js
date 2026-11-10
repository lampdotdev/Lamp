// The relay prototype (relay/relay.mjs), over real HTTP: who may pair, who may send, and what a build may hold.

import assert from "node:assert/strict";
import { createServer, get } from "node:http";
import { test } from "node:test";
import { RELAY_LIMITS, createRelay } from "../relay/relay.mjs";
import { zipOf } from "../../cli/share.mjs";

// A GET to the play host as a browser asks for a room's host by name (fetch won't set Host).
const playGet = (port, host, path) => new Promise((done, failed) => {
  get({ host: "127.0.0.1", port, path, headers: { Host: `${host}:${port}` } }, (response) => {
    const parts = [];
    response.on("data", (part) => parts.push(part));
    response.on("end", () => done({ status: response.statusCode, headers: response.headers, text: Buffer.concat(parts).toString() }));
  }).on("error", failed);
});

async function started({ clock = { now: Date.now() } } = {}) {
  const game = new Map([["index.html", Buffer.from("<!doctype html><p>red</p>")]]);
  const page = createServer(), play = createServer();
  await Promise.all([new Promise((done) => page.listen(0, "127.0.0.1", done)), new Promise((done) => play.listen(0, "127.0.0.1", done))]);
  const pageOrigin = `http://127.0.0.1:${page.address().port}`, playOrigin = `http://localhost:${play.address().port}`;
  const lines = [];
  const relay = createRelay({ game, pageOrigin, playOrigin, now: () => clock.now, log: (line) => lines.push(line), limits: { ...RELAY_LIMITS, codeMs: 60_000 } });
  page.on("request", relay.request);
  play.on("request", relay.play);
  const call = async (method, path, { origin, secret, body, raw } = {}) => {
    const response = await fetch(pageOrigin + path, {
      method, body: raw ?? (body ? JSON.stringify(body) : undefined),
      headers: { ...(origin ? { Origin: origin } : {}), ...(secret ? { Authorization: `Bearer ${secret}` } : {}) },
    });
    return { status: response.status, body: await response.json().catch(() => null) };
  };
  const close = () => { page.closeAllConnections(); play.closeAllConnections(); page.close(); play.close(); };
  return { call, close, pageOrigin, playOrigin, lines, clock };
}

test("a code pairs once, and not after it runs out", async () => {
  const relay = await started({ clock: { now: 1_000_000 } });
  try {
    const room = (await relay.call("POST", "/api/rooms", { origin: relay.pageOrigin })).body;
    const paired = await relay.call("POST", "/api/pair", { body: { code: room.code } });
    assert.equal(paired.status, 200);
    assert.ok(paired.body.secret && paired.body.secret !== room.secret);
    assert.equal((await relay.call("POST", "/api/pair", { body: { code: room.code } })).status, 404);

    const other = (await relay.call("POST", "/api/rooms", { origin: relay.pageOrigin })).body;
    relay.clock.now += 60_001;
    assert.equal((await relay.call("POST", "/api/pair", { body: { code: other.code } })).status, 404);
    assert.ok(relay.lines.some((line) => line.endsWith(`code ${other.code}: expired`)));
  } finally { relay.close(); }
});

test("pairing is refused from a browser, and slowed after a few tries", async () => {
  const relay = await started();
  try {
    const room = (await relay.call("POST", "/api/rooms", { origin: relay.pageOrigin })).body;
    assert.equal((await relay.call("POST", "/api/pair", { origin: "http://evil.example", body: { code: room.code } })).status, 403);
    for (let n = 0; n < RELAY_LIMITS.pairsPerMinute; n++) assert.equal((await relay.call("POST", "/api/pair", { body: { code: "AAAAAA" } })).status, 404);
    assert.equal((await relay.call("POST", "/api/pair", { body: { code: room.code } })).status, 429);
  } finally { relay.close(); }
});

test("only the page with its secret, from its own origin, sends a request; the same id is taken once", async () => {
  const relay = await started();
  try {
    const room = (await relay.call("POST", "/api/rooms", { origin: relay.pageOrigin })).body;
    await relay.call("POST", "/api/pair", { body: { code: room.code } });
    const request = { id: "request-0001", prompt: "make it green" };
    const game = `http://${room.room}.localhost:${new URL(relay.playOrigin).port}`;
    assert.equal((await relay.call("POST", "/api/page/requests", { origin: game, secret: room.secret, body: request })).status, 403);
    assert.equal((await relay.call("POST", "/api/page/requests", { origin: relay.pageOrigin, body: request })).status, 401);
    assert.equal((await relay.call("POST", "/api/page/requests", { origin: relay.pageOrigin, secret: "guess", body: request })).status, 401);
    const sent = await relay.call("POST", "/api/page/requests", { origin: relay.pageOrigin, secret: room.secret, body: request });
    assert.equal(sent.body.state, "queued");
    const again = await relay.call("POST", "/api/page/requests", { origin: relay.pageOrigin, secret: room.secret, body: request });
    assert.deepEqual(again.body, sent.body);
  } finally { relay.close(); }
});

test("a build that steps out of its folder isn't published; a page is, once, and the game's host serves it", async () => {
  const relay = await started();
  try {
    const room = (await relay.call("POST", "/api/rooms", { origin: relay.pageOrigin })).body;
    const helper = (await relay.call("POST", "/api/pair", { body: { code: room.code } })).body.secret;
    await relay.call("POST", "/api/page/requests", { origin: relay.pageOrigin, secret: room.secret, body: { id: "request-0002", prompt: "green" } });
    await relay.call("POST", "/api/helper/status", { secret: helper, body: { id: "request-0002", state: "running" } });
    const bad = zipOf([["index.html", Buffer.from("x")], ["../escape.js", Buffer.from("x")]]);
    assert.equal((await relay.call("PUT", "/api/helper/build?request=request-0002", { secret: helper, raw: bad })).status, 422);
    assert.equal((await relay.call("PUT", "/api/helper/build?request=request-0002", { secret: room.secret, raw: bad })).status, 401);
    const good = zipOf([["index.html", Buffer.from("<p>green</p>")]]);
    const done = await relay.call("PUT", "/api/helper/build?request=request-0002", { secret: helper, raw: good });
    assert.deepEqual([done.status, done.body.version], [200, 2]);
    assert.equal((await relay.call("PUT", "/api/helper/build?request=request-0002", { secret: helper, raw: good })).body.version, 2);
    const port = new URL(relay.playOrigin).port;
    const served = await playGet(port, `${room.room}.localhost`, "/v/2/");
    assert.equal(served.text, "<p>green</p>");
    assert.equal(served.headers["content-security-policy"], `frame-ancestors ${relay.pageOrigin}`);
    assert.equal((await playGet(port, "someone-else.localhost", "/v/2/")).status, 404);
  } finally { relay.close(); }
});
