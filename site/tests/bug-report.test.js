import test from "node:test";
import assert from "node:assert/strict";
import { spawn, execFileSync } from "node:child_process";
import net from "node:net";
import { setTimeout as delay } from "node:timers/promises";
import { createReportHandler, MAX_REPORT_BYTES } from "../lib/bug-report.js";
import { slackPayload } from "../lib/report-destination.js";
import { limitScript } from "../lib/report-limit.js";
import { standIn, displayedReport } from "./receivers.js";

function request(text = "A reviewed report", ip = "192.0.2.1", headers = {}) {
  return new Request("https://lamp.dev/api/bug-report", { method: "POST",
    headers: { "content-type": "text/plain; charset=utf-8", "x-vercel-forwarded-for": ip, ...headers }, body: text });
}

test("HTTP stand-in gets exactly the reviewed Unicode text, without mention parsing or unfurls", async () => {
  const receiver = await standIn();
  try {
    const report = "\uFEFF  My edited report → café 🪔\n<!channel> <@U123> &lt;button&gt; &amp; https://example.com\n";
    const response = await fetch(`${receiver.url}/api/bug-report`, {
      method: "POST", headers: { "content-type": "text/plain; charset=utf-8" }, body: report,
    });
    assert.equal(response.status, 200);
    assert.deepEqual(await response.json(), { sent: true });
    const payload = receiver.payloads[0];
    assert.equal(displayedReport(payload), report);
    assert.ok(payload.blocks[0].text.text.includes("&amp;lt;button&amp;gt;"));
    assert.ok(payload.blocks.every((b) => b.text.type === "plain_text" && b.text.emoji === false));
    assert.equal(payload.mrkdwn, false);
    assert.equal(payload.unfurl_links, false);
    assert.equal(payload.unfurl_media, false);
  } finally { await receiver.close(); }
});

test("long Unicode reports split safely inside Slack's block limits", () => {
  const report = "a".repeat(2999) + "<&>" + "🪔".repeat(2000) + "終わり";
  const payload = slackPayload(report);
  assert.equal(displayedReport(payload), report);
  assert.ok(payload.blocks.every((b) => b.text.text.length <= 3000 && b.text.text.isWellFormed()));
  assert.ok(payload.blocks.every((b) => !/&(?:a|am|amp|l|lt|g|gt)?$/.test(b.text.text)), "Partial entity at a block boundary");
  const worstCase = slackPayload("&".repeat(MAX_REPORT_BYTES));
  assert.equal(displayedReport(worstCase), "&".repeat(MAX_REPORT_BYTES));
  assert.ok(worstCase.blocks.length <= 50 && worstCase.blocks.every((b) => b.text.text.length <= 3000));
});

test("method, origin, encoding, empty and oversize requests never reach forwarding", async () => {
  let calls = 0;
  const handler = createReportHandler({ env: {}, fetcher: () => { calls++; throw new Error(); } });
  const cases = [
    [new Request("https://lamp.dev/api/bug-report"), 405],
    [request("text", "192.0.2.1", { origin: "https://stranger.example" }), 403],
    [request("{}", "192.0.2.1", { "content-type": "application/json" }), 415],
    [request(" \n"), 400],
    [request("x".repeat(MAX_REPORT_BYTES + 1)), 413],
    [request("x", "192.0.2.1", { "content-length": String(MAX_REPORT_BYTES + 1) }), 413],
    [request(new Uint8Array([0xff, 0xfe])), 400],
  ];
  for (const [req, expected] of cases) {
    const response = await handler(req);
    assert.equal(response.status, expected);
    assert.equal(response.headers.get("cache-control"), "no-store");
  }
  assert.equal(calls, 0);
});

test("oversize chunked bodies stop at the cap even without Content-Length", async () => {
  let cancelled = false;
  const stream = new ReadableStream({
    start(controller) { controller.enqueue(new Uint8Array(MAX_REPORT_BYTES)); controller.enqueue(new Uint8Array(1)); },
    cancel() { cancelled = true; },
  });
  const req = new Request("https://lamp.dev/api/bug-report", { method: "POST", duplex: "half", body: stream,
    headers: { "content-type": "text/plain" } });
  assert.equal((await createReportHandler({ env: {} })(req)).status, 413);
  assert.equal(cancelled, true);
});

test("missing/failed limiter, malformed client IP and upstream failures fail closed", async () => {
  const receiver = await standIn();
  try {
    assert.equal((await createReportHandler({ env: {} })(request())).status, 503);
    const broken = createReportHandler({ env: receiver.env, fetcher: async () => new Response("error", { status: 500 }) });
    assert.equal((await broken(request())).status, 503);
    assert.equal(receiver.payloads.length, 0);
    assert.equal((await receiver.handle(request("text", "not-an-ip"))).status, 503);
    receiver.setFailure(true);
    const response = await receiver.handle(request());
    assert.equal(response.status, 502);
    assert.deepEqual(await response.json(), { error: "delivery_failed" });
    assert.equal(receiver.payloads.length, 1);
  } finally { await receiver.close(); }
});

test("per-IP quota rejects the fourth attempt with Retry-After", async () => {
  const receiver = await standIn();
  try {
    for (let i = 0; i < 3; i++) assert.equal((await receiver.handle(request())).status, 200);
    const response = await receiver.handle(request());
    assert.equal(response.status, 429);
    assert.ok(Number(response.headers.get("retry-after")) > 0);
    assert.equal(receiver.payloads.length, 3);
  } finally { await receiver.close(); }
});

function redisBinary(variable, name) {
  if (process.env[variable]) return process.env[variable];
  try { execFileSync(name, ["--version"], { stdio: "ignore" }); return name; } catch { return undefined; }
}
const redisServer = redisBinary("REDIS_SERVER", "redis-server");
const redisCLI = redisBinary("REDIS_CLI", "redis-cli");
test("actual Redis Lua: concurrent IP/global quotas, expiry and persistence across handlers", { skip: !redisServer || !redisCLI }, async () => {
  const socket = net.createServer();
  await new Promise((resolve) => socket.listen(0, "127.0.0.1", resolve));
  const port = socket.address().port;
  await new Promise((resolve) => socket.close(resolve));
  const redis = spawn(redisServer, ["--bind", "127.0.0.1", "--port", String(port), "--save", "", "--appendonly", "no"], { stdio: "ignore" });
  const cli = (...args) => execFileSync(redisCLI, ["-p", String(port), "--raw", ...args.map(String)], { stdio: ["ignore", "pipe", "ignore"], encoding: "utf8" }).trim();
  let receiver;
  try {
    for (let i = 0; i < 100; i++) { try { if (cli("PING") === "PONG") break; } catch {} await delay(20); }
    assert.equal(cli("PING"), "PONG");
    receiver = await standIn({ evaluate: async (command) => Number(cli(...command)) });
    const statuses = await Promise.all(Array.from({ length: 20 }, () => receiver.handle(request()).then((r) => r.status)));
    assert.equal(statuses.filter((s) => s === 200).length, 3);
    assert.equal(statuses.filter((s) => s === 429).length, 17);
    const newHandler = createReportHandler({ env: receiver.env, fetcher: receiver.fetcher });
    assert.equal((await newHandler(request())).status, 429);
    cli("FLUSHDB");
    const global = await Promise.all(Array.from({ length: 40 }, (_, i) => receiver.handle(request("text", `192.0.2.${i + 1}`)).then((r) => r.status)));
    assert.equal(global.filter((s) => s === 200).length, 10);
    const keys = cli("KEYS", "*").split("\n");
    assert.ok(keys.every((key) => Number(cli("TTL", key)) > 0 && !key.includes("192.0.2")));
    const day = keys.find((key) => key.endsWith(":day"));
    cli("SET", day, "30", "EX", "60");
    cli("DEL", keys.find((key) => key.endsWith(":hour")));
    assert.equal((await receiver.handle(request("text", "198.51.100.1"))).status, 429);
    cli("FLUSHDB");
    cli("SET", "ip", "3");
    assert.ok(Number(cli("EVAL", limitScript, 3, "ip", "hour", "day")) > 0, "A missing TTL must not bypass quota");
    cli("EXPIRE", "ip", "1");
    await delay(1100);
    assert.equal(Number(cli("EVAL", limitScript, 3, "ip", "hour", "day")), 0);
  } finally {
    if (receiver) await receiver.close();
    const stopped = new Promise((resolve) => redis.once("exit", resolve));
    redis.kill("SIGTERM");
    await stopped;
  }
});
