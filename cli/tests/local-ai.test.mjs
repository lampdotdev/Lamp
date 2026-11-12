// `lamp ai`: a page shared on lamp.dev uses the person's AI on their computer only once they've allowed that page, and
// nothing else gets an answer. The AI itself is a stand-in here.

import { test, after } from "node:test";
import assert from "node:assert/strict";
import { request } from "node:http";
import { mkdtempSync, rmSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";

const home = mkdtempSync(join(tmpdir(), "lamp-local-ai-test-"));
process.env.LAMP_DEV_HOME = home;
const { serveLocalAI, linkOf, allowed } = await import("../local-ai.mjs");

const page = `https://${Buffer.from("CbjuQkzDtz").toString("hex")}.play.lamp.dev`;
after(() => rmSync(home, { recursive: true, force: true }));
const other = `https://${Buffer.from("D4vNNnfErs").toString("hex")}.play.lamp.dev`;

test("only a shared page the person allowed has its AI answered", async (t) => {
  const asked = [];
  let yes = false;
  const server = await serveLocalAI({
    port: 0, said: () => {},
    ask: async (question) => { asked.push(question); return yes; },
    answer: async (path, body) => {
      if (path === "/ai/status") return [200, { text: true }];
      if (body.probe) return [200, { act: true }];
      await new Promise((done) => setTimeout(done, 20));
      return [200, { text: `answered ${body.prompt}` }];
    },
  });
  t.after(() => server.close());
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
  assert.deepEqual((await call("/ai/act", { body: { probe: true } })).reply, { act: true });
  assert.equal((await call("/ai", { body: { prompt: "hi" } })).status, 401);
  // A probe is only a probe where it asks no model.
  assert.equal((await call("/ai", { body: { prompt: "hi", probe: true } })).status, 401);
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
  assert.equal((await call("/ai", { origin: other, token: "é".repeat(token.length), body: { prompt: "hi" } })).status, 401);
  // Many at once, as LampAI.decideEach asks: each waits its turn and is answered.
  const many = await Promise.all(Array.from({ length: 12 }, (_, n) => call("/ai", { origin: other, token, body: { prompt: String(n) } })));
  assert.deepEqual(many.map((one) => one.reply.text), Array.from({ length: 12 }, (_, n) => `answered ${n}`));
  // Kept for the next run, and asked for again it's the same.
  assert.equal(allowed()[other].name, "Harbor  Racer");
  assert.equal((await call("/pair", { origin: other })).reply.token, token);
  assert.equal(asked.length, 2);
});

test("Lamp's app answers through the same server: it's asked about the page, and gives the AI's answer", async () => {
  const { CALLS } = await import("../calls.mjs");
  const stopped = new AbortController(), heard = [];
  const event = (said) => {
    heard.push(said);
    if (said.ask) CALLS.sharedPagesReply({ n: said.ask, yes: true });
    if (said.answer) CALLS.sharedPagesReply({ n: said.answer, status: 200, reply: { text: `Lamp answered ${said.body.prompt}` } });
  };
  const running = CALLS.sharedPages({ port: 47499 }, { stopped: stopped.signal, event });
  await new Promise((done) => setTimeout(done, 100));
  const post = (path, body, token) => new Promise((done, fail) => {
    const headers = { host: "127.0.0.1:47499", origin: page, "content-type": "application/json", ...(token ? { authorization: `Bearer ${token}` } : {}) };
    const req = request({ port: 47499, path, method: "POST", headers }, (res) => { let text = ""; res.on("data", (c) => (text += c)); res.on("end", () => done(JSON.parse(text))); });
    req.on("error", fail);
    req.end(JSON.stringify(body));
  });
  const { token } = await post("/pair", { name: "Bricks" });
  assert.deepEqual(await post("/ai", { prompt: "hi" }, token), { text: "Lamp answered hi" });
  assert.deepEqual(heard.map((said) => Object.keys(said)[0]), ["ask", "answer"]);
  assert.equal(heard[0].name, "Bricks");
  stopped.abort();
  assert.deepEqual(await running, {});
});
