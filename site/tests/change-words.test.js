import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, chatgptLink, claudeLink, CLAUDE_LINK_MAX } from "../src/lib/change-words.ts";

const ADDRESS = "https://lamp.dev/r/room1/game", KEY = "k_test";

// The ChatGPT link has to hand over the very words Copy copies, line breaks, quotes and all, read back as a URL is.
test("the ChatGPT link carries the room words exactly", () => {
  const words = changeWords(ADDRESS, KEY);
  const link = new URL(chatgptLink(words));
  assert.equal(link.protocol, "codex:");
  assert.equal(link.host + link.pathname, "new");
  assert.equal(link.searchParams.get("prompt"), words);
});

// Nothing is changed or sent before the player says what they want: read, ask, wait, then change and send.
test("the words read the game, ask and wait before changing and sending it", () => {
  const words = changeWords(ADDRESS, KEY);
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  const read = at('-o "<folder>/game.html"'), ask = at("Ask me what I'd like to change, and wait"), send = at("-X POST");
  assert.ok(read < ask && ask < send);
  for (const command of words.split("\n").filter((line) => line.includes("curl "))) assert.match(command, /--fail-with-body/);
});

// The idea the player brought from the game's page goes to Claude Code exactly, and the longest one the page takes still
// fits in what Claude Code takes from a link.
test("the Claude Code link carries the words, with the idea, within Claude Code's limit", () => {
  const idea = "Make the ball \"blue\" & faster ".repeat(40).slice(0, 1000);
  const words = changeWords(ADDRESS, KEY, { app: "claude", idea });
  const link = new URL(claudeLink(words));
  assert.equal(link.protocol, "claude-cli:");
  assert.equal(link.host + link.pathname, "open");
  assert.equal(link.searchParams.get("q"), words);
  assert.ok(words.length <= CLAUDE_LINK_MAX, `${words.length} characters`);
  assert.ok(words.includes(idea.trim().replace(/\s+/g, " ")));
  assert.doesNotMatch(words, /Codex/, "Claude Code is never told to switch to Codex");
  assert.match(changeWords(ADDRESS, KEY), /switch to Codex/);
});

// With an idea, the app still checks with the player before it changes or sends anything; and every file it writes
// goes in a new folder of its own, made before anything is read.
test("the words make a folder first, and confirm the idea before sending", () => {
  const words = changeWords(ADDRESS, KEY, { app: "claude", idea: "add a timer" });
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  assert.ok(at("mktemp -d") < at("curl "));
  assert.ok(at('"add a timer"') < at("wait for my OK") && at("wait for my OK") < at("-X POST"));
  const commands = words.split("\n").filter((line) => line.includes("curl ")).join("\n");
  assert.match(commands, /-D "<folder>\/headers.txt" -o "<folder>\/game.html"/);
  assert.match(commands, /--data-binary @"<folder>\/game.html"/);
});
