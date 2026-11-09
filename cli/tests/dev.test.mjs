// What lamp dev must never get wrong: which requests it answers, and that a saved change reaches the open page.
// No browser is used: a page's line for changes is read as a browser reads it.

import { test, before, after } from "node:test";
import assert from "node:assert/strict";
import { existsSync, mkdtempSync, mkdirSync, readFileSync, writeFileSync, rmSync } from "node:fs";
import { spawnSync } from "node:child_process";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { request } from "node:http";

const home = mkdtempSync(join(tmpdir(), "lamp-dev-test-"));
process.env.LAMP_DEV_HOME = join(home, "state");
// No browser: looks are the page's own words, and nothing is started on the computer running the tests.
process.env.LAMP_BROWSER = "";
const { serve } = await import("../dev.mjs");

let server, folder;

before(async () => {
  folder = join(home, "app");
  mkdirSync(join(folder, "Web", ".hidden"), { recursive: true });
  writeFileSync(join(folder, "Web", "index.html"), "<!doctype html><html><head><title>T</title></head><body>One</body></html>");
  writeFileSync(join(folder, "Web", "main.js"), "export const n = 1;\n");
  writeFileSync(join(folder, "Web", ".hidden", "secret.txt"), "secret");
  writeFileSync(join(folder, "outside.txt"), "outside the page");
  server = await serve({ folder, quiet: true });
});

after(async () => {
  await server.close();
  rmSync(home, { recursive: true, force: true });
});

/** A page's line for changes: gives each event as it comes. */
async function line(since) {
  const answer = await fetch(`${server.url}__lamp/events?page=p${Math.random()}&since=${since}`);
  const reader = answer.body.getReader(), decoder = new TextDecoder();
  let held = "";
  return {
    async next(event) {
      for (;;) {
        const found = new RegExp(`event: ${event}\\ndata: (.*)\\n\\n`).exec(held);
        if (found) { held = held.slice(found.index + found[0].length); return found[1]; }
        const { value, done } = await reader.read();
        if (done) throw new Error("the line closed");
        held += decoder.decode(value, { stream: true });
      }
    },
    close: () => reader.cancel(),
  };
}

test("serves the page with lamp's script first, and nothing that isn't the page", async () => {
  const page = await (await fetch(server.url)).text();
  assert.match(page, /<head><script src="\/__lamp\/page\.js"><\/script><title>/);
  assert.equal((await fetch(`${server.url}main.js?lamp=3`)).status, 200);
  assert.equal((await fetch(`${server.url}.hidden/secret.txt`)).status, 404);
  assert.equal((await fetch(`${server.url}%2e%2e/outside.txt`)).status, 404);
});

test("answers only this computer's own pages and lamp's own commands", async () => {
  // A name of someone else's pointed at this computer.
  const elsewhere = await new Promise((resolve, reject) => {
    request({ host: "127.0.0.1", port: server.port, path: "/", headers: { host: "example.com" } }, (answer) => { answer.resume(); resolve(answer.statusCode); }).on("error", reject).end();
  });
  assert.equal(elsewhere, 403);
  const other = await fetch(`http://127.0.0.1:${server.port}/__lamp/log`, { method: "POST", headers: { origin: "https://example.com" }, body: "{}" });
  assert.equal(other.status, 403);
  const untold = await fetch(`${server.url}__lamp/cli/look`, { method: "POST", body: "{}" });
  assert.equal(untold.status, 403);
  const told = await fetch(`${server.url}__lamp/cli/hello`, { headers: { "x-lamp-token": server.token } });
  assert.equal((await told.json()).folder, server.folder);
});

test("a new game is given what only Lamp's app writes, and a file that isn't there is an error", async () => {
  const made = join(home, "new-game");
  const run = spawnSync(process.execPath, [join(import.meta.dirname, "..", "lamp.mjs"), "new", made, "--name", "Harbor <Racer>"], { encoding: "utf8" });
  assert.equal(run.status, 0, run.stderr);
  assert.match(readFileSync(join(made, "index.html"), "utf8"), /<title>Harbor &lt;Racer&gt;<\/title>/);
  // The folder is a whole site: every file its page and the runtime name is in it.
  for (const file of ["game.js", "lamp-game.js", "lamp-controllers.js", "lamp-device.js", "lamp.js", "three/three.module.js"]) assert.ok(existsSync(join(made, file)), file);
  // A game whose folder has none of Lamp's own files is given them all the same.
  for (const file of ["lamp-controllers.js", "lamp-device.js", "lamp.js"]) rmSync(join(made, file));
  const game = await serve({ folder: made, quiet: true });
  try {
    // The runtime imports the first, and can't load without it; the rest are what a game's page may name.
    for (const file of ["lamp-controllers.js", "lamp-device.js", "lamp-build.js", "lamp.js", "three/three.module.js", "phaser/phaser.esm.min.js"]) {
      assert.equal((await fetch(game.url + file)).status, 200, file);
    }
    assert.match(await (await fetch(`${game.url}lamp-controllers.js`)).text(), /export default \{"base":/);
    assert.equal((await fetch(`${game.url}missing.js`)).status, 404);
    assert.match(readFileSync(game.logFile, "utf8"), /error: missing\.js isn't in the folder/);
  } finally {
    await game.close();
  }
});

test("a saved change reaches the open page, and one saved while a page was opening reaches it too", async () => {
  const open = await line(0);
  await open.next("hello");
  writeFileSync(join(folder, "Web", "main.js"), "export const n = 2;\n");
  const first = JSON.parse(await open.next("change"));
  assert.deepEqual([first.gen, first.changed, first.removed], [1, ["main.js"], []]);
  rmSync(join(folder, "Web", "main.js"));
  const second = JSON.parse(await open.next("change"));
  assert.deepEqual([second.changed, second.removed], [[], ["main.js"]]);
  open.close();
  // A page whose files were served before both changes hears of them as one when its line opens.
  const late = await line(0);
  const missed = JSON.parse(await late.next("change"));
  assert.deepEqual([missed.gen, missed.changed, missed.removed], [2, [], ["main.js"]]);
  late.close();
});
