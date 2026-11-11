import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, chatgptLink, claudeLink, CLAUDE_LINK_MAX } from "../src/lib/change-words.ts";

const HANDOFF = { guide: "https://lamp.dev/change-guide.md", address: "https://lamp.dev/r/room1/game", key: "k_test", page: "https://lamp.dev/change?with=app&w=abcdefghij", name: "Pong" };

// Each app's link has to hand over the very words Copy copies, line breaks, quotes and all, read back as a URL is.
test("each app's link carries the words exactly", () => {
  const chatgpt = new URL(chatgptLink(changeWords(HANDOFF)));
  assert.equal(chatgpt.protocol, "codex:");
  assert.equal(chatgpt.host + chatgpt.pathname, "new");
  assert.equal(chatgpt.searchParams.get("prompt"), changeWords(HANDOFF));
  const words = changeWords({ ...HANDOFF, app: "claude", idea: "add a timer" });
  const claude = new URL(claudeLink(words));
  assert.equal(claude.protocol, "claude-cli:");
  assert.equal(claude.host + claude.pathname, "open");
  assert.equal(claude.searchParams.get("q"), words);
});

// The destination comes before the guide, so an app that reads no further still sends only to the room; the guide is
// fetched so a missing one stops the run; and the room, its key, the game and the request are all there.
test("the words name the destination first, then the guide, the room and the request", () => {
  const words = changeWords({ ...HANDOFF, app: "claude", idea: "add a timer" });
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  assert.ok(at("only to the game address") < at("Read the guide first"));
  assert.ok(at("curl -fsS https://lamp.dev/change-guide.md") > 0);
  at("Game address: https://lamp.dev/r/room1/game");
  at("Key: k_test");
  at('"Pong"');
  at(HANDOFF.page);
  at("My request: add a timer");
  assert.doesNotMatch(words, /Codex/, "Claude Code is never told to switch to Codex");
  assert.match(changeWords(HANDOFF), /switch to Codex/);
  assert.match(changeWords({ ...HANDOFF, name: null }), /Change the game,/, "a room without a name");
  assert.match(changeWords(HANDOFF), /Ask me what to change/, "no request: the app asks");
});

// The longest idea the game's page takes still fits in what Claude Code takes from a link.
test("the words with the longest idea stay within Claude Code's limit", () => {
  const idea = "Make the ball \"blue\" & faster ".repeat(40).slice(0, 1000);
  const words = changeWords({ ...HANDOFF, name: "N".repeat(80), app: "claude", idea });
  assert.ok(words.length <= CLAUDE_LINK_MAX, `${words.length} characters`);
  assert.ok(words.includes(idea.trim().replace(/\s+/g, " ")));
});
