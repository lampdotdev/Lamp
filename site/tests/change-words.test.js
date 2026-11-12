import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, chatgptLink, claudeLink, CLAUDE_LINK_MAX, fileName, gamesFolder } from "../src/lib/change-words.ts";
import { SETUP_PROMPT } from "../src/lib/chatgpt.ts";

const HANDOFF = { name: "Pong", page: "https://lamp.dev/w/abcdefghij", file: "https://store.example/w/abcdefghij/Pong.lampapp" };

// Each app's link has to hand over the very words, line breaks, quotes and all, read back as a URL is.
test("each app's link carries the words exactly", () => {
  const chatgpt = new URL(chatgptLink(changeWords(HANDOFF)));
  assert.equal(chatgpt.protocol, "codex:");
  assert.equal(chatgpt.host + chatgpt.pathname, "new");
  assert.equal(chatgpt.searchParams.get("prompt"), changeWords(HANDOFF));
  const words = changeWords({ ...HANDOFF, app: "claude", idea: "add a timer" });
  const claude = new URL(claudeLink(words, "/Users/sam/My Games"));
  assert.equal(claude.protocol, "claude-cli:");
  assert.equal(claude.host + claude.pathname, "open");
  assert.equal(claude.searchParams.get("q"), words);
  assert.equal(claude.searchParams.get("cwd"), "/Users/sam/My Games", "Claude Code opens in the games folder, never the home folder");
});

// The order the brief set: ask before installing, check Node, install and read the guide (or reuse a lamp that works),
// then unpack the game's own file, open it, change it and look.
test("the words ask before installing, then unpack, open, change and look, in that order", () => {
  const words = changeWords({ ...HANDOFF, idea: "add a timer" });
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  assert.ok(at("offer right away to continue in ChatGPT Work") < at("already work here"));
  assert.ok(at("already work here") < at("Would you like me to install"));
  assert.ok(at("Wait for my explicit yes") < at("node --version"));
  assert.ok(at("node --version") < at("npm install -g @lampdotdev/lamp, then lamp setup, then lamp guide"));
  assert.ok(at("lamp guide prints") < at(`curl -fsSL -o "Pong.lampapp" "${HANDOFF.file}"`));
  assert.ok(at('lamp unpack "Pong.lampapp"') < at("lamp open"));
  assert.ok(at("lamp open") < at("lamp look"));
  at("~/Lamp Games");
  at("credits.json");
  at("don't copy the game from its web page or remake it from its description");
  at(HANDOFF.page);
  at("My request: add a timer");
  assert.match(changeWords(HANDOFF), /My request: none yet\.[\s\S]*Ask me what to change/, "no request: the app asks");
});

test("Claude Code works in the folder it's opened in and is never told about ChatGPT", () => {
  const words = changeWords({ ...HANDOFF, app: "claude" });
  assert.match(words, /You were opened in my games folder/);
  assert.doesNotMatch(words, /ChatGPT|Codex|Lamp Games/);
});

// The homepage's prompt and Make it myself share the install steps, so they ask the same way.
test("the homepage prompt asks before installing in the same words", () => {
  for (const part of ["Would you like me to install and set up Lamp's command-line tools?", "Wait for my explicit yes", "ChatGPT Work"])
    assert.ok(SETUP_PROMPT.includes(part) && changeWords(HANDOFF).includes(part), part);
});

// The file's name goes into a shell command in double quotes: nothing that could end the quotes or expand in them.
test("the game's file is named safely for a shell", () => {
  assert.equal(fileName('Rock "n" $(roll) `x` \\ Me!'), "Rock n roll x Me");
  assert.equal(fileName("Café Ünder 2"), "Café Ünder 2");
  assert.equal(fileName("***"), "Game");
  assert.ok(fileName("N".repeat(200)).length <= 60);
});

// The longest idea the game's page takes still fits in what Claude Code takes from a link.
test("the words with the longest idea stay within Claude Code's limit", () => {
  const idea = "Make the ball \"blue\" & faster ".repeat(40).slice(0, 1000);
  const words = changeWords({ ...HANDOFF, name: "N".repeat(80), app: "claude", idea });
  const link = new URL(claudeLink(words, "/Users/sam/Games"));
  assert.ok(link.searchParams.get("q").length <= CLAUDE_LINK_MAX, `${words.length} characters`);
  assert.ok(words.includes(idea.trim().replace(/\s+/g, " ")));
});

// A folder Claude Code would refuse, or none, is said plainly instead of making a link that does nothing.
test("the games folder must be a whole path Claude Code takes", () => {
  const problem = (typed) => gamesFolder(typed).problem;
  assert.match(problem(""), /Write the path/);
  assert.match(problem("Games"), /isn't a whole path/);
  assert.match(problem("~/Games"), /not ~/);
  assert.match(problem("//server/share/Games"), /network/);
  assert.match(problem("/Users/sam/../Games"), /\.\./);
  assert.match(problem("/Users/sam/Ga​mes"), /characters/);
  assert.match(problem("/Users/sam"), /folder of its own/, "never the home folder itself");
  assert.match(problem("/"), /folder of its own/);
  assert.match(problem("/Users/" + "a".repeat(4100)), /too long/);
  assert.deepEqual(gamesFolder(" /Users/sam/My\\ Games/ "), { folder: "/Users/sam/My Games" });
  assert.deepEqual(gamesFolder("'/Users/sam/My Games'"), { folder: "/Users/sam/My Games" });
});
