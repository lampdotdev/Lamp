import { test } from "node:test";
import assert from "node:assert/strict";
import { CLAUDE_LINK_MAX } from "../src/lib/change-words.ts";
import { CHATGPT_LINK, CHATGPT_SETUP_PROMPT, CLAUDE_LINK, CLAUDE_SETUP_PROMPT } from "../src/lib/setup-prompts.ts";
import { RUN_HERE_CHATGPT, RUN_HERE_CLAUDE } from "../src/lib/lamp-cli-words.ts";

// Each link has to hand its app the very words of its prompt, line breaks and all, read back as a URL is.
test("the ChatGPT link carries the ChatGPT prompt exactly", () => {
  const link = new URL(CHATGPT_LINK);
  assert.equal(link.protocol, "codex:");
  assert.equal(link.host + link.pathname, "new");
  assert.equal(link.searchParams.get("prompt"), CHATGPT_SETUP_PROMPT);
});

test("the Claude link carries the Claude prompt exactly, in q alone, under Claude's cut-off", () => {
  const link = new URL(CLAUDE_LINK);
  assert.equal(link.protocol, "claude:");
  assert.equal(link.host + link.pathname, "code/new");
  assert.deepEqual([...link.searchParams.keys()], ["q"]);
  assert.equal(link.searchParams.get("q"), CLAUDE_SETUP_PROMPT);
  assert.ok(CLAUDE_SETUP_PROMPT.length < CLAUDE_LINK_MAX);
});

// The two prompts differ only in where the commands run; asking first, Node, the install, setup and the guide are
// the same words in each.
test("the two prompts are the same but for where the commands run", () => {
  const prompts = { chatgpt: [CHATGPT_SETUP_PROMPT, RUN_HERE_CHATGPT], claude: [CLAUDE_SETUP_PROMPT, RUN_HERE_CLAUDE] };
  const shared = Object.values(prompts).map(([prompt, runHere]) => {
    assert.ok(prompt.includes(runHere));
    return prompt.replace(runHere, "");
  });
  assert.equal(new Set(shared).size, 1);
  assert.doesNotMatch(CLAUDE_SETUP_PROMPT, /ChatGPT|Codex/);
});
