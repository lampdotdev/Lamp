// lamp play (prototype): the guard that keeps the agent's file tools in the game's folder, and what goes back to
// the page after a change.

import assert from "node:assert/strict";
import { mkdirSync, mkdtempSync, rmSync, symlinkSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { test } from "node:test";
import { verdict } from "../play-guard.mjs";
import { packed } from "../play.mjs";

function folders() {
  const top = mkdtempSync(join(tmpdir(), "lamp-play-"));
  const game = join(top, "game"), outside = join(top, "outside");
  mkdirSync(game); mkdirSync(outside);
  writeFileSync(join(game, "index.html"), "<p>game</p>");
  writeFileSync(join(outside, "private.txt"), "private");
  return { top, game, outside };
}

test("the file tools reach only into the game's folder", () => {
  const { top, game, outside } = folders();
  try {
    assert.equal(verdict(game, { tool_name: "Read", tool_input: { file_path: join(game, "index.html") } }), null);
    assert.equal(verdict(game, { tool_name: "Write", tool_input: { file_path: "new/level.js" } }), null);
    assert.equal(verdict(game, { tool_name: "Glob", tool_input: { pattern: "**/*.js" } }), null);
    assert.match(verdict(game, { tool_name: "Read", tool_input: { file_path: join(outside, "private.txt") } }), /outside/);
    assert.match(verdict(game, { tool_name: "Write", tool_input: { file_path: "../outside/copy.html" } }), /outside/);
    assert.match(verdict(game, { tool_name: "Read", tool_input: { file_path: "~/.ssh/id_ed25519" } }), /outside/);
    assert.match(verdict(game, { tool_name: "Glob", tool_input: { pattern: "../**/*" } }), /outside/);
    assert.match(verdict(game, { tool_name: "Grep", tool_input: { pattern: "x", path: "/" } }), /outside/);
    assert.match(verdict(game, { tool_name: "Bash", tool_input: { command: "ls" } }), /isn't one of/);
    // A link inside the folder that leads out of it is where it leads.
    symlinkSync(outside, join(game, "door"));
    assert.match(verdict(game, { tool_name: "Read", tool_input: { file_path: "door/private.txt" } }), /outside/);
    assert.match(verdict(game, { tool_name: "Write", tool_input: { file_path: "door/new.txt" } }), /outside/);
  } finally { rmSync(top, { recursive: true, force: true }); }
});

test("a change goes back without an agent's files, and never with a link or a key", () => {
  const { top, game, outside } = folders();
  try {
    mkdirSync(join(game, ".claude"));
    writeFileSync(join(game, ".claude", "settings.json"), "{}");
    writeFileSync(join(game, "CLAUDE.md"), "notes");
    writeFileSync(join(game, "game.js"), "let green = 1;");
    assert.deepEqual(packed(game).files.map(([path]) => path), ["game.js", "index.html"]);

    symlinkSync(join(outside, "private.txt"), join(game, "private.txt"));
    assert.throws(() => packed(game), /is a link/);
    rmSync(join(game, "private.txt"));

    writeFileSync(join(game, "config.js"), `const key = "sk-ant-${"a".repeat(40)}";`);
    assert.throws(() => packed(game), /shaped like a key/);
  } finally { rmSync(top, { recursive: true, force: true }); }
});
