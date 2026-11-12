// What an app's AI is told and how its answers are read (app-ai.mjs), for Lamp's app and lamp alike. The recorded
// answers in Tests/Fixtures are real models' own: openrouter-act is anthropic/claude-sonnet-5.5 through OpenRouter
// (recorded 2026-10-27), claude-code-act and codex-act are Claude Code's and Codex's (2026-10-29), each asked as Lamp
// asks a step.

import { test } from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { join } from "node:path";
import { MAX_CALLS, chatBody, decidePrompt, planPrompt, planSchema, readDecision, readMessage, readPlan, readStep } from "../app-ai.mjs";

const fixtures = join(import.meta.dirname, "..", "..", "Tests", "Fixtures");
const recorded = (folder, file) => JSON.parse(readFileSync(join(fixtures, folder, file), "utf8"));

const groceries = { name: "groceries", about: "The shopping list.", reads: true, args: {} };
const addGrocery = { name: "addGrocery", about: "Put something on the list.",
  args: { name: { type: "string" }, qty: { type: "integer", min: 1, max: 99, optional: true }, store: { type: "string", oneOf: ["grocer", "costco"], optional: true } } };
const step = (extra = {}) => readStep(JSON.stringify({ request: "Add milk", tools: [groceries, addGrocery], ...extra }));
const refusal = (body) => { try { readStep(JSON.stringify(body)); return null; } catch (error) { return error.message; } };
const earlier = (n) => ({ calls: [{ id: `s${n}c1`, name: "groceries", args: {} }], results: [{ id: `s${n}c1`, ok: true, value: [] }] });
const bananas = { calls: [{ id: "s1c1", name: "addGrocery", args: { name: "Bananas" } }], results: [{ id: "s1c1", ok: true, value: { added: "Bananas", qty: 1, store: "grocer" } }] };

test("a step's tools are Lamp's to check: reply is Lamp's, names and ids are once, shapes have only what a shape can", () => {
  assert.ok(refusal({ request: "x", tools: [{ name: "reply", args: {} }] }));
  assert.ok(refusal({ request: "x", tools: [groceries, groceries] }));
  const twice = { calls: [{ id: "s1c1", name: "groceries", args: {} }], results: [] };
  assert.ok(refusal({ request: "x", tools: [groceries], steps: [twice, twice] }));
  assert.match(refusal({ request: "x", tools: [{ name: "x", args: { a: { type: "string", pattern: ".*" } } }] }), /`pattern`/);
  assert.ok(refusal({ request: "x", tools: [{ name: "x", args: { a: { type: "integer", oneOf: ["1"] } } }] }));
  assert.ok(refusal({ request: "x", tools: [{ name: "x", args: { a: { type: "list" } } }] }));
  assert.equal(step({ steps: [earlier(1), earlier(2)] }).final, false);
  assert.equal(step({ steps: [earlier(1), earlier(2), earlier(3)] }).final, true);
  assert.ok(refusal({ request: "x", tools: [groceries], steps: [earlier(1), earlier(2), earlier(3), earlier(4)] }));
});

test("OpenRouter's recorded answers become one checked call with Lamp's own id, then the reply", () => {
  const add = recorded("openrouter-act", "add-milk.json");
  const call = readMessage(add.call, step());
  assert.deepEqual(call.answer.calls.map((c) => [c.id, c.name, c.args.name]), [["s1c1", "addGrocery", "milk"]]);
  const added = { calls: [{ id: "s1c1", name: "addGrocery", args: { name: "milk" } }], results: [{ id: "s1c1", ok: true, value: { added: "Milk" } }] };
  const reply = readMessage(add.reply, step({ steps: [added] }));
  assert.match(reply.answer.reply, /Milk/);
  assert.equal(reply.answer.ask, false);
  // Words with no call are the reply, a question when they end with one.
  assert.equal(readMessage({ content: "Which store, the grocer or Costco?" }, step()).answer.ask, true);
});

test("calls that don't fit are asked again, never handed on", () => {
  const r = step();
  const call = (name, args) => ({ function: { name, arguments: args } });
  for (const calls of [
    [call("addGrocery", '{"name":"milk","qty":0}')],
    [call("addGrocery", '{"name":"milk","aisle":"Dairy"}')],
    [call("addGrocery", "{}")],
    [call("addGrocery", '{"name":"milk","store":"market"}')],
    [call("removeEverything", "{}")],
    [call("addGrocery", '{"name":"milk"}'), call("reply", '{"text":"Done","ask":false}')],
    Array.from({ length: MAX_CALLS + 1 }, () => call("groceries", "{}")),
  ]) assert.ok(readMessage({ tool_calls: calls }, r).problem, JSON.stringify(calls));
  const last = step({ steps: [earlier(1), earlier(2), earlier(3)] });
  assert.match(readMessage({ tool_calls: [call("groceries", "{}")] }, last).problem, /Only `reply`/);
});

test("OpenRouter is asked with the tools and Lamp's reply, for providers that take them, what the app shows fenced", () => {
  const sent = chatBody(step({ context: { list: ["eggs"] } }), "outside-text-1", null, "anthropic/claude-sonnet-5.5");
  assert.equal(sent.provider.require_parameters, true);
  assert.equal(sent.tool_choice, "auto");
  assert.deepEqual(sent.tools.map((t) => t.function.name), ["groceries", "addGrocery", "reply"]);
  assert.ok(sent.tools[2].function.parameters.properties.choices);
  assert.match(sent.messages[1].content, /<outside-text-1>[\s\S]*eggs/);
  assert.equal(chatBody(step({ steps: [earlier(1), earlier(2), earlier(3)] }), "t", null, "m").tool_choice, "none");
});

test("a question's choices are kept only as a short plain set", () => {
  const r = step();
  const offered = (args) => readMessage({ tool_calls: [{ function: { name: "reply", arguments: JSON.stringify(args) } }] }, r).answer.choices ?? [];
  assert.deepEqual(offered({ text: "Add one more?", ask: true, choices: [" Yes ", "No"] }), ["Yes", "No"]);
  assert.deepEqual(offered({ text: "Grocer or Costco?", ask: true, choices: ["Grocer", "Costco", "Either"] }), ["Grocer", "Costco", "Either"]);
  for (const [args, why] of [
    [{ text: "Added milk.", ask: false, choices: ["Yes", "No"] }, "not a question"],
    [{ text: "Which?", ask: true, choices: ["Yes"] }, "one isn't a choice"],
    [{ text: "Which?", ask: true, choices: ["a", "b", "c", "d", "e"] }, "five is too many"],
    [{ text: "Which?", ask: true, choices: ["**Yes**", "No"] }, "markup"],
    [{ text: "Which?", ask: true, choices: ["Yes", "yes"] }, "the same twice"],
    [{ text: "Which?", ask: true, choices: ["Yes", "x".repeat(25)] }, "too long"],
    [{ text: "Which?", ask: true, choices: ["Yes", 2] }, "not text"],
  ]) assert.deepEqual(offered(args), [], why);
});

test("Claude Code's and Codex's recorded plans are read into the same checked calls and replies", () => {
  const r = readStep(JSON.stringify({ request: "Add bananas", tools: [groceries, addGrocery], about: "A family dashboard with the shopping list." }));
  const after = readStep(JSON.stringify({ request: "Add bananas", tools: [groceries, addGrocery], about: "A family dashboard with the shopping list.", steps: [bananas] }));
  const claude = recorded("claude-code-act", "add-bananas.json"), codex = recorded("codex-act", "add-bananas.json");
  const call = readPlan(claude.call, r).answer.calls[0];
  assert.deepEqual([call.id, call.name, call.args.name.toLowerCase()], ["s1c1", "addGrocery", "bananas"]);
  assert.ok(Object.values(call.args).every((v) => v !== null), "an optional argument left null is left out");
  assert.deepEqual(readPlan(codex.call, r).answer.calls.map((c) => [c.id, c.name]), [["s1c1", "groceries"]]);
  for (const reply of [readPlan(claude.reply, after), readPlan(codex.reply, after)]) {
    assert.match(reply.answer.reply, /banana/i);
    assert.equal(reply.answer.ask, false);
  }
  assert.match(readPlan('{"calls": [{"name": "addGrocery", "args": {"name": "Bananas", "qty": 0, "store": null}}], "reply": null}', r).problem, /qty/);
  assert.match(readPlan('{"calls": [{"name": "groceries", "args": "all"}], "reply": null}', r).problem, /JSON object/);
  // The plan's prompt names the tools, and the last step has none to name.
  assert.match(planPrompt(r, "t", null).system, /addGrocery/);
  assert.equal(planSchema(readStep(JSON.stringify({ request: "x", tools: [groceries], final: true }))).required.join(), "reply");
});

test("a decision by a text model is held to its questions and read into answers", () => {
  const questions = { urgent: { type: "noul", instructions: "Is it urgent?" }, size: { type: "choice", criteria: { small: null, big: null } },
    mood: { type: "score", criteria: ["sad", "fine", "glad"] } };
  const { schema, prompt } = decidePrompt({ text: "Fire!" }, questions);
  assert.deepEqual(schema.required, ["mood", "size", "urgent"]);
  assert.deepEqual(schema.properties.size.properties.choice.enum, ["big", "small"]);
  assert.match(prompt, /Fire!/);
  const read = readDecision('```json\n{"urgent": {"noul": 1.4}, "size": {"probabilities": {"small": 0.2, "big": 0.6}}, "mood": {"probabilities": {"2": 1}}}\n```', questions);
  assert.deepEqual(read.answers.urgent, { noul: 1 });
  assert.equal(read.answers.size.choice, "big");
  assert.equal(read.answers.mood.score, 2);
  assert.match(readDecision('{"urgent": {}}', questions).problem, /urgent/);
});
