// `lamp ai`: a page shared on lamp.dev uses the person's AI on their computer only once they've allowed that page, and
// nothing else gets an answer. The AI itself is a stand-in here.

import { test } from "node:test";
import assert from "node:assert/strict";
import { request } from "node:http";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = mkdtempSync(join(tmpdir(), "lamp-local-ai-test-"));
process.env.LAMP_DEV_HOME = home;
const { serveLocalAI, linkOf, allowed } = await import("../local-ai.mjs");

const page = `https://${Buffer.from("CbjuQkzDtz").toString("hex")}.play.lamp.dev`;
const other = `https://${Buffer.from("D4vNNnfErs").toString("hex")}.play.lamp.dev`;

test("only a shared page the person allowed has its AI answered", async (t) => {
  const asked = [];
  let yes = false;
  const server = await serveLocalAI({
    port: 0, said: () => {},
    ask: async (question) => { asked.push(question); return yes; },
    answer: async (path, body) => [200, path === "/ai/status" ? { text: true } : { text: `answered ${body.prompt}` }],
  });
  t.after(() => { server.close(); rmSync(home, { recursive: true, force: true }); });
  const port = server.address().port;
  const call = (path, { origin = page, host = `127.0.0.1:${port}`, token, body = {}, method = "POST" } = {}) => new Promise((done, fail) => {
    const headers = { host, origin, "content-type": "application/json" };
    if (token) headers.authorization = `Bearer ${token}`;
    const req = request({ port, path, method, headers }, (res) => {
      let text = "";
      res.on("data", (chunk) => (text += chunk));
      res.on("end", () => done({ status: res.statusCode, headers: res.headers, reply: text ? JSON.parse(text) : null }));
    });
    req.on("error", fail);
    req.end(method === "POST" ? JSON.stringify(body) : undefined);
  });

  assert.deepEqual([page, other, "https://lamp.dev", "http://43626a75516b7a44747a.play.lamp.dev", "https://evil.com"].map(linkOf), ["CbjuQkzDtz", "D4vNNnfErs", null, null, null]);
  // Another site, and a name of another site's pointed at this computer, get nothing.
  assert.equal((await call("/ai/status", { origin: "https://evil.com" })).status, 403);
  assert.equal((await call("/ai/status", { host: `rebound.example:${port}` })).status, 403);
  // A browser asks first whether it may call here at all.
  const preflight = await call("/ai", { method: "OPTIONS" });
  assert.equal(preflight.status, 204);
  assert.equal(preflight.headers["access-control-allow-origin"], page);
  assert.equal(preflight.headers["access-control-allow-private-network"], "true");

  // What there is is said before anyone's asked; using it isn't.
  assert.deepEqual((await call("/ai/status")).reply, { text: true });
  assert.equal((await call("/ai", { body: { prompt: "hi" } })).status, 401);
  assert.equal(asked.length, 0);

  // Said no: not asked again while it runs.
  assert.equal((await call("/pair", { body: { name: "Bricks" } })).status, 403);
  assert.equal((await call("/pair", { body: { name: "Bricks" } })).status, 403);
  assert.equal(asked.length, 1);
  assert.match(asked[0], /"Bricks" shared at lamp\.dev\/w\/CbjuQkzDtz/);

  // Allowed: the page's token answers for it, and for no other page.
  yes = true;
  const allowedPage = await call("/pair", { origin: other, body: { name: "Harbor\u0007 Racer" } });
  assert.equal(allowedPage.status, 200);
  const { token } = allowedPage.reply;
  assert.deepEqual((await call("/ai", { origin: other, token, body: { prompt: "hi" } })).reply, { text: "answered hi" });
  assert.equal((await call("/ai", { origin: page, token, body: { prompt: "hi" } })).status, 401);
  assert.equal((await call("/ai", { origin: other, token: "wrong", body: { prompt: "hi" } })).status, 401);
  // Kept for the next run, and asked for again it's the same.
  assert.equal(allowed()[other].name, "Harbor  Racer");
  assert.equal((await call("/pair", { origin: other })).reply.token, token);
  assert.equal(asked.length, 2);
});
