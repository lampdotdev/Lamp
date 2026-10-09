import test from "node:test";
import assert from "node:assert/strict";
import { createIdeaHandler, readConversation, buildPrompt, plain, DEFAULT_MODEL, RULES, QUOTAS, MAX_BODY_BYTES } from "../lib/first-idea.js";
import { createEventHandler, fieldFor, EVENTS } from "../lib/idea-events.js";
import { SITUATIONS, ROUNDS, SCRIPT, SHAPES } from "../lib/situations.js";

const ENV = { UPSTASH_REDIS_REST_URL: "https://redis.test", UPSTASH_REDIS_REST_TOKEN: "token", OPENROUTER_API_KEY: "or-key" };

// Stands in for Upstash and OpenRouter: counts quota keys like the Lua script would, and answers the model
// call with whatever the test gives it. Any other destination fails the test.
function stand({ answer = { kind: "question", question: "Which site?", options: ["News", "Prices"], lead: "", request: "" },
  status = 200, finish = "stop", limits } = {}) {
  const counts = new Map();
  const calls = { model: [], redis: [] };
  const fetcher = async (url, init) => {
    if (url === ENV.UPSTASH_REDIS_REST_URL) {
      const command = JSON.parse(init.body);
      calls.redis.push(command);
      const [, script, n, ...rest] = command;
      const keys = rest.slice(0, Number(n));
      if (script.includes("HINCRBY")) { counts.set(rest[1] + "|" + rest[3], (counts.get(rest[1] + "|" + rest[3]) ?? 0) + 1); return Response.json({ result: 1 }); }
      const caps = (limits ?? rest.slice(Number(n), Number(n) * 2)).map(Number);
      if (keys.some((k, i) => (counts.get(k) ?? 0) >= caps[i])) return Response.json({ result: 60 });
      keys.forEach((k) => counts.set(k, (counts.get(k) ?? 0) + 1));
      return Response.json({ result: 0 });
    }
    if (url === "https://openrouter.ai/api/v1/chat/completions") {
      calls.model.push(JSON.parse(init.body));
      if (status !== 200) return new Response("nope", { status });
      const next = typeof answer === "function" ? answer(calls.model.length) : answer;
      return Response.json({ choices: [{ finish_reason: typeof finish === "function" ? finish(calls.model.length) : finish, message: { content: JSON.stringify(next) } }] });
    }
    throw new Error(`Unexpected destination ${url}`);
  };
  return { fetcher, calls, counts };
}

function post(body, { ip = "192.0.2.1", headers = {}, path = "/api/first-idea" } = {}) {
  return new Request(`https://lamp.dev${path}`, { method: "POST",
    headers: { "content-type": "application/json", "x-vercel-forwarded-for": ip, ...headers },
    body: typeof body === "string" ? body : JSON.stringify(body) });
}

test("the situations, rounds and fallback questions fit together", () => {
  const all = ROUNDS.flat();
  assert.equal(new Set(all).size, all.length, "No situation repeats across rounds");
  assert.deepEqual([...all].sort(), Object.keys(SITUATIONS).sort(), "Every situation is shown in some round");
  for (const round of ROUNDS) assert.equal(new Set(round.map((id) => SITUATIONS[id].shape)).size, 4, "A round shows four different shapes");
  for (const shape of Object.keys(SHAPES)) {
    const [q, options, write] = SCRIPT[shape];
    assert.ok(q && options.length >= 2 && write("x").includes("x"));
  }
});

test("a picked situation gets a question back, asked of the configured model with the rules as the system message", async () => {
  const { fetcher, calls } = stand();
  const response = await createIdeaHandler({ env: ENV, fetcher })(post({ situation: "checking-1", passed: ["copying-1", "tidying-1"] }));
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { question: "Which site?", options: ["News", "Prices"] });
  const sent = calls.model[0];
  assert.equal(sent.model, DEFAULT_MODEL);
  assert.equal(sent.messages[0].role, "system");
  assert.equal(sent.messages[0].content, RULES);
  assert.match(sent.messages[1].content, /open the same website most days/);
  assert.match(sent.messages[1].content, /passed over[\s\S]*copy numbers[\s\S]*Downloads folder/);
  assert.equal(sent.response_format.json_schema.strict, true);

  const other = stand();
  await createIdeaHandler({ env: { ...ENV, FIRST_IDEA_MODEL: " openai/gpt-6-mini " }, fetcher: other.fetcher })(post({ situation: "checking-1" }));
  assert.equal(other.calls.model[0].model, "openai/gpt-6-mini");
});

test("after two answers the model is told to write, and a third question is never passed on", async () => {
  const turns = [{ q: "Which site?", a: "My kid's school page" }, { q: "What are you looking for?", a: "New grades" }];
  assert.match(buildPrompt(readConversation({ situation: "checking-1", turns })), /write the request now/);
  const { fetcher } = stand();
  const response = await createIdeaHandler({ env: ENV, fetcher })(post({ situation: "checking-1", turns }));
  assert.equal(response.status, 502, "A question when a request was due is an unusable answer");

  const written = stand({ answer: { kind: "request", question: "", options: [], lead: "Here it is.", request: "Every morning, check my kid's school page…" } });
  const ok = await createIdeaHandler({ env: ENV, fetcher: written.fetcher })(post({ words: "I check the school portal daily", turns }));
  assert.deepEqual(await ok.json(), { lead: "Here it is.", request: "Every morning, check my kid's school page…" });
});

test("a wish comes back as one paragraph of plain text", () => {
  assert.equal(plain("Nothing changes.</br>"), "Nothing changes.");
  assert.equal(plain("Read it over.}"), "Read it over.");
  assert.equal(plain("A notification lets me know.\n\n(Nothing gets sent until I say so.)"), "A notification lets me know. Nothing gets sent until I say so.");
  assert.equal(plain("A widget\nthat  shows (a count) here."), "A widget that shows (a count) here.");
});

test("a filtered reply is asked once more; a failed or unusable one is a 502", async () => {
  const retry = stand({ finish: (n) => (n === 1 ? "content_filter" : "stop") });
  assert.equal((await createIdeaHandler({ env: ENV, fetcher: retry.fetcher })(post({ situation: "tidying-1" }))).status, 200);
  assert.equal(retry.calls.model.length, 2);
  assert.equal((await createIdeaHandler({ env: ENV, fetcher: stand({ status: 500 }).fetcher })(post({ situation: "tidying-1" }))).status, 502);
  assert.equal((await createIdeaHandler({ env: ENV, fetcher: stand({ answer: { kind: "question", question: "", options: [], lead: "", request: "" } }).fetcher })(post({ situation: "tidying-1" }))).status, 502);
  assert.equal((await createIdeaHandler({ env: { ...ENV, OPENROUTER_API_KEY: "" }, fetcher: stand().fetcher })(post({ situation: "tidying-1" }))).status, 502);
});

test("malformed, oversize, foreign and made-up requests never reach the model", async () => {
  const { fetcher, calls } = stand();
  const handler = createIdeaHandler({ env: ENV, fetcher });
  const cases = [
    [new Request("https://lamp.dev/api/first-idea"), 405],
    [post({ situation: "checking-1" }, { headers: { origin: "https://stranger.example" } }), 403],
    [post("{}", { headers: { "content-type": "text/plain" } }), 415],
    [post("not json"), 400],
    [post({}), 400],
    [post({ situation: "made-up" }), 400],
    [post({ situation: "checking-1", words: "both at once" }), 400],
    [post({ words: "x".repeat(501) }), 400],
    [post({ words: "   " }), 400],
    [post({ situation: "checking-1", passed: ["nope"] }), 400],
    [post({ situation: "checking-1", turns: [{ q: "Which?", a: "" }] }), 400],
    [post({ situation: "checking-1", turns: Array(4).fill({ q: "Which?", a: "That" }) }), 400],
    [post({ words: "x".repeat(MAX_BODY_BYTES) }), 413],
    [post({ situation: "checking-1" }, { ip: "not-an-ip" }), 503],
  ];
  for (const [req, expected] of cases) {
    const response = await handler(req);
    assert.equal(response.status, expected, `${expected} expected`);
    assert.equal(response.headers.get("cache-control"), "no-store");
  }
  assert.equal(calls.model.length, 0);
  assert.equal((await createIdeaHandler({ env: {}, fetcher })(post({ situation: "checking-1" }))).status, 503, "No limiter, no model");
});

test("the per-visitor quota stops the 31st call with Retry-After, and counts only a hash of the IP", async () => {
  const { fetcher, calls } = stand();
  const handler = createIdeaHandler({ env: ENV, fetcher });
  const perIP = QUOTAS.find((q) => q.perIP).limit;
  for (let i = 0; i < perIP; i++) assert.equal((await handler(post({ situation: "finding-1" }))).status, 200);
  const response = await handler(post({ situation: "finding-1" }));
  assert.equal(response.status, 429);
  assert.ok(Number(response.headers.get("retry-after")) > 0);
  assert.equal(calls.model.length, perIP);
  assert.ok(calls.redis.every((command) => !JSON.stringify(command).includes("192.0.2.1")));
  assert.equal((await handler(post({ situation: "finding-1" }, { ip: "192.0.2.2" }))).status, 200, "Another visitor still gets through");
});

test("events count only known names and details, never text, and are capped per visitor", async () => {
  assert.equal(fieldFor({ event: "pick", detail: "checking-1" }), "pick:checking-1");
  assert.equal(fieldFor({ event: "copy" }), "copy");
  assert.equal(fieldFor({ event: "pick", detail: "I check my bank every day" }), null);
  assert.equal(fieldFor({ event: "words", detail: "" }), null);
  assert.equal(fieldFor({ event: "round", detail: "9" }), null);
  for (const [event, details] of Object.entries(EVENTS)) for (const d of details) assert.ok(fieldFor({ event, detail: d }));

  const { fetcher, counts } = stand();
  const handler = createEventHandler({ env: ENV, fetcher, now: () => new Date("2026-10-09T12:00:00Z") });
  const beacon = (body, opts) => handler(post(JSON.stringify(body), { path: "/api/idea-event", headers: { "content-type": "text/plain;charset=UTF-8" }, ...opts }));
  assert.equal((await beacon({ event: "pick", detail: "checking-1" })).status, 204);
  assert.equal((await beacon({ event: "pick", detail: "free text" })).status, 400);
  assert.equal((await beacon({ event: "copy", pad: "x".repeat(300) })).status, 413);
  assert.equal((await beacon({ event: "copy" }, { headers: { origin: "https://stranger.example" } })).status, 403);
  const [key] = [...counts.keys()].filter((k) => k.includes("events:2026-10-09"));
  assert.equal(key, "lamp:first-idea:{preview}:events:2026-10-09|pick:checking-1");
});
