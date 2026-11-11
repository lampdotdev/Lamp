import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, chatgptLink } from "../src/lib/change-words.ts";

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
  const read = at("-o game.html"), ask = at("Ask me what I'd like to change, and wait"), send = at("-X POST");
  assert.ok(read < ask && ask < send);
  for (const command of words.split("\n").filter((line) => line.includes("curl "))) assert.match(command, /--fail-with-body/);
});
