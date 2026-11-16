// A lost terminal reply must be replayable by lamp dev and lamp ai, which both use ai.mjs's act responder.

import { test } from "node:test";
import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { act } from "../ai.mjs";

const tools = [{ name: "addGrocery", about: "Put something on the list.", args: {
  name: { type: "string" }, qty: { type: "integer", optional: true }, store: { type: "string", optional: true },
} }];

function isolatedEngine(t) {
  const folder = mkdtempSync(join(tmpdir(), "lamp-act-retry-"));
  const path = process.env.PATH;
  // Only the stand-in can be found: the tests never run an installed engine or use its sign-in.
  process.env.PATH = folder;
  t.after(() => {
    if (path === undefined) delete process.env.PATH; else process.env.PATH = path;
    rmSync(folder, { recursive: true, force: true });
  });
  return folder;
}

async function finished() {
  let answer = await act({ request: "Add bananas", tools, stream: true }, ["claude"]);
  const calls = [];
  while (answer[1].more) {
    calls.push(...answer[1].calls);
    answer = await act({ follow: answer[1].stream, have: calls.length });
  }
  return { answer, calls, follow: { follow: answer[1].stream, have: calls.length } };
}

test("a lost streamed answer is replayed for the same have, with calls rebuilt for another have", async (t) => {
  const folder = isolatedEngine(t);
  // The plan is the recorded Claude Code answer used by app-ai.test.mjs (2026-10-29).
  const recorded = JSON.parse(readFileSync(new URL("../../Tests/Fixtures/claude-code-act/add-bananas.json", import.meta.url), "utf8"));
  writeFileSync(join(folder, "answer"), JSON.stringify({ type: "result", result: recorded.call }) + "\n");
  writeFileSync(join(folder, "claude"), `#!/bin/sh
printf x >> "\${0%/*}/runs"
exec /bin/cat "\${0%/*}/answer"
`, { mode: 0o755 });

  const { answer, calls, follow } = await finished();
  assert.equal(answer[0], 200);
  assert.equal(answer[1].more, false);
  assert.equal(follow.have, 1, "the call reached the page before the terminal follow");
  assert.deepEqual([...calls, ...answer[1].calls], [{ id: "s1c1", name: "addGrocery", args: { name: "bananas" } }]);
  // Discard the terminal answer as if its connection was lost, then send exactly the same follow.
  assert.deepEqual(await act(follow), answer);
  // A route that missed the released call must get it too; one that has it must not run it twice.
  const all = await act({ follow: follow.follow, have: 0 });
  assert.deepEqual(all, [200, { ...answer[1], calls: [...calls, ...answer[1].calls] }]);
  assert.deepEqual(await act({ follow: follow.follow, have: 1 }), [200, { ...answer[1], calls: [] }]);
  assert.equal(readFileSync(join(folder, "runs"), "utf8"), "x", "following never asks the model again");
});

test("a lost terminal error is replayed with its status and cost", async (t) => {
  isolatedEngine(t);
  // The executable is absent, so the responder gets a real spawn failure without contacting an AI service.
  const { answer, follow } = await finished();
  assert.equal(answer[0], 502);
  assert.equal(answer[1].more, false);
  assert.equal(answer[1].cost, 0);
  assert.equal(typeof answer[1].error, "string");
  assert.ok(answer[1].error.length);
  assert.deepEqual(answer[1].calls, []);
  assert.deepEqual(await act(follow), answer);
});
