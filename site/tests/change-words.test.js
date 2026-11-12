import { test } from "node:test";
import assert from "node:assert/strict";
import { changeWords, chatgptLink, claudeLink, CLAUDE_FOLDER_FIRST, CLAUDE_LINK_MAX, fileName } from "../src/lib/change-words.ts";
import { SETUP_PROMPT } from "../src/lib/chatgpt.ts";

const HANDOFF = { name: "Pong", page: "https://lamp.dev/w/abcdefghij", file: "https://store.example/w/abcdefghij/Pong.lampapp" };

// Each app's link has to hand over the very words, line breaks, quotes and all, read back as a URL is.
test("each app's link carries the words exactly", () => {
  const chatgpt = new URL(chatgptLink(changeWords(HANDOFF)));
  assert.equal(chatgpt.protocol, "codex:");
  assert.equal(chatgpt.host + chatgpt.pathname, "new");
  assert.equal(chatgpt.searchParams.get("prompt"), changeWords(HANDOFF));
  const words = changeWords({ ...HANDOFF, app: "claude", idea: "add a timer" });
  const claude = new URL(claudeLink(words));
  assert.equal(claude.protocol, "claude:");
  assert.equal(claude.host + claude.pathname, "code/new");
  assert.equal(claude.searchParams.get("q"), words);
  assert.deepEqual([...claude.searchParams.keys()], ["q"], "no folder: the words say where the copy goes");
});

// The order the brief set: ask before installing, check Node, install and read the guide (or reuse a lamp that works),
// then unpack the game's own file, open it, change it and look.
test("the words ask before installing, then unpack, open, change and look, in that order", () => {
  const words = changeWords({ ...HANDOFF, idea: "add a timer" });
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  assert.ok(at("offer right away to continue in ChatGPT Work") < at("already here"));
  assert.ok(at("already here") < at("Would you like me to install"));
  assert.ok(at("Wait for my explicit yes") < at("node --version"));
  assert.ok(at("node --version") < at("npm install -g @lampdotdev/lamp@latest, then lamp setup, then lamp guide"));
  assert.ok(at("lamp guide prints") < at(`curl -fsSL -o "Pong.lampapp" "${HANDOFF.file}"`));
  assert.ok(at('lamp unpack "Pong.lampapp"') < at("Open my copy with lamp open"));
  assert.ok(at("Open my copy with lamp open") < at("check it with lamp look"));
  at("~/Lamp Games");
  at("credits.json");
  at("don't copy the game from its web page or remake it from its description");
  at(HANDOFF.page);
  at("My request: add a timer");
  assert.match(changeWords(HANDOFF), /My request: none yet\.[\s\S]*Ask me what to change/, "no request: the app asks");
});

// A lamp that's there but older than unpack, open and look is updated, and only after the person says yes, as an
// install is; a working one is used as it is.
test("an old lamp is updated only after asking, and a new enough one is used as it is", () => {
  for (const app of ["chatgpt", "claude"]) {
    const words = changeWords({ ...HANDOFF, app });
    const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, `${app}: ${part}`); return i; };
    assert.ok(at("lamp help") < at("lists lamp unpack, lamp open and lamp look"));
    assert.ok(at("skip installing and updating") < at("too old for this"));
    assert.ok(at("too old for this") < at("Would you like me to update Lamp's command-line tools?"));
    assert.ok(at("Would you like me to update") < at("Wait for my explicit yes before updating anything"));
    assert.ok(at("Wait for my explicit yes before updating anything") < at("npm install -g @lampdotdev/lamp@latest"), "the yes comes before npm runs");
    assert.ok(at("npm install -g @lampdotdev/lamp@latest") < at("If it still doesn't"));
  }
});

// Claude is opened in no folder of the person's, so before it runs anything it's told where the copy goes and to ask
// for that folder if its session can't reach it.
test("Claude is told where the copy goes, and to ask for access, before any command, and never about ChatGPT", () => {
  const words = changeWords({ ...HANDOFF, app: "claude" });
  assert.equal(CLAUDE_FOLDER_FIRST, "Work locally on this Mac. Put my copy in ~/Lamp Games (create it if needed), and keep the game files there. If this session can't access that folder, ask me to choose it or grant access before downloading or unpacking.");
  const at = (part) => { const i = words.indexOf(part); assert.ok(i >= 0, part); return i; };
  for (const command of ["lamp help", "npm install", "curl -fsSL", "lamp unpack", "lamp open"])
    assert.ok(at(CLAUDE_FOLDER_FIRST) < at(command), command);
  assert.doesNotMatch(words, /ChatGPT|Codex/);
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

// The longest idea the game's page takes, with a long name, still fits whole in what Claude takes from its link: it
// cuts the words at 14,336 UTF-16 units.
test("the words with the longest idea stay within Claude's limit", () => {
  assert.equal(CLAUDE_LINK_MAX, 14336);
  const idea = "Make the ball \"blue\" & faster ".repeat(40).slice(0, 1000);
  const words = changeWords({ ...HANDOFF, name: "N".repeat(80), app: "claude", idea });
  const q = new URL(claudeLink(words)).searchParams.get("q");
  assert.equal(q, words);
  assert.ok(q.length <= CLAUDE_LINK_MAX, `${q.length} UTF-16 units`);
  assert.ok(words.includes(idea.trim().replace(/\s+/g, " ")));
});
