#!/usr/bin/env node
// lamp: runs a web app or web game from its folder and puts each saved change into the open page, for whoever is
// making it, a person or a coding agent. It needs no Mac app and no build step. No dependencies: Node 20 or later.
//
//   lamp dev [folder]     run it, each save going into the open page
//   lamp look [folder]    how the last change went, a picture, the screen as text and the log
//   lamp use [folder] …   try it: a key, a click, some typing
//   lamp stop [folder]    stop running it
//   lamp guide            what a coding agent needs to know to work this way
//   lamp skills           Lamp's guidance for each kind of work; lamp skill <name> reads one

import { spawn } from "node:child_process";
import { existsSync, mkdirSync, openSync, readdirSync, readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, layoutOf, stateOf, logFileOf, running, ask } from "./state.mjs";
import { serve } from "./dev.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

const USAGE = `lamp runs the web app or game in a folder and puts each saved change into the open page.

  lamp dev [folder] [--open] [--port N] [--lan]
      Run it. --open opens a window for it; --lan lets other devices on the network open it too.
  lamp look [folder] [--wait seconds] [--json]
      How the changes since the last look went, a picture of the page, its screen as text, and its log.
  lamp use [folder] key <name> [seconds] | click <x> <y> | type <text> | wait <seconds>
      Try it as a person would, then look.
  lamp reload [folder]    Open the page again from its files, a game from where the player is.
  lamp stop [folder]      Stop running it.
  lamp guide              What a coding agent needs to know to work this way.
  lamp skills             Lamp's guidance for each kind of work; lamp skill <name> reads one.

The folder is one Lamp made (its page is in Web/) or any folder with an index.html; without one, the folder you're in.`;

const GUIDE = (log) => `Working on a web app or game with lamp

lamp runs the page from this folder and puts each change into it while it's open. Save files and the change goes in:
nothing is built, restarted or reloaded by hand.

  lamp dev --open      Run it in a window the person can use and play. Leave it running.
  lamp look            After a change: how it went in, a picture of the page (a file to read), its screen as text,
                       new errors and the log. It waits for the change to finish going in.
  lamp use key w 2     Try it: hold a key for some seconds, \`click 640 400\` a point of the picture, \`type hello\`.
                       It answers with a look. With a window open the person sees it happen.
  lamp skills          Lamp's guidance for each kind of work. Read the ones that fit with \`lamp skill <name>\` before
                       changing what they cover: they say which of Lamp's building blocks to use and how.

How a change goes in. A plain page opens again. A game made with Lamp's runtime keeps the player's place: a module
that ends with hot(import.meta).accept() is swapped in while the game runs ("live"), other code is run again with the
player where they were ("reran"), and what can't go in either way opens the page again from the player's place
("reopened"). "held" means the game is at a moment it can't be interrupted and waits for the person's Reload.
Prefer changes that go in live: keep what changes as the game is played in modules that accept their changes.

Look after every change, and read the errors before saying it works. The page's log is at
${log}

Lamp's own files in the folder are rewritten by Lamp and never edited: lamp.js, lamp-game.js, lamp-phaser.js,
lamp-controllers.js, and the three/ and phaser/ folders.

Where a skill names one of Lamp's own tools: look_at_app is \`lamp look\`, use_app is \`lamp use\`, and a change needs no
tool at all. What lamp doesn't do yet: phones, TVs and consoles, sharing, and anything that needs Lamp's Mac app around
the page.`;

function fail(problem) {
  console.error(`lamp: ${problem}`);
  process.exit(1);
}

/** The command's options and what's left: `--name value` for those that take one, `--name` for the rest. */
function parse(args, valued) {
  const options = {}, rest = [];
  for (let i = 0; i < args.length; i++) {
    const arg = args[i];
    if (arg === "--help" || arg === "-h") { console.log(USAGE); process.exit(0); }
    if (!arg.startsWith("--")) { rest.push(arg); continue; }
    const name = arg.slice(2);
    if (valued.includes(name)) {
      if (i + 1 >= args.length) throw new Problem(`--${name} takes a value`);
      options[name] = args[++i];
    } else options[name] = true;
  }
  return { options, rest };
}

/** The server for the folder: the one running, or one started for this command that ends when nothing uses it. */
async function serverFor(folder) {
  const live = await running(folder);
  if (live) return live;
  const state = stateOf(folder);
  mkdirSync(state, { recursive: true });
  const out = openSync(join(state, "server.log"), "a");
  spawn(process.execPath, [fileURLToPath(import.meta.url), "dev", folder, "--quiet", "--idle", "30"], { detached: true, stdio: ["ignore", out, out] }).unref();
  for (let tries = 0; tries < 60; tries++) {
    await sleep(100);
    const started = await running(folder);
    if (started) return started;
  }
  throw new Problem(`lamp dev didn't start for this folder; see ${join(state, "server.log")}`);
}

const WHERE = {
  window: "the window the person has open",
  copy: "lamp's own copy of the page (no window is open, so it starts where the page starts)",
  page: "a page open in a browser lamp can't look into",
};

function report(seen) {
  const lines = [];
  if (seen.did) lines.push(seen.did);
  if (seen.where) lines.push(`Looked at ${WHERE[seen.where]}${seen.title ? `: "${seen.title}"` : ""}${seen.width ? `, ${seen.width}×${seen.height}` : ""}.`);
  if (seen.problem) lines.push(seen.problem);
  if (seen.unfinished) lines.push(`Taken while ${seen.unfinished}: look again.`);
  if (seen.picture) lines.push(`Picture   ${seen.picture}`);
  if (seen.changes.length) {
    lines.push("Changes since the last look");
    for (const change of seen.changes) lines.push(`  ${change.files} → ${change.outcome}: ${change.means}${change.why ? ` (${change.why})` : ""}`);
  }
  lines.push(seen.errors.length ? "Errors since the last look" : "Errors since the last look: none");
  for (const error of seen.errors) lines.push(`  ${error.split("\n").join("\n    ")}`);
  if (seen.screen) lines.push("Screen", ...seen.screen.split("\n").map((line) => `  ${line}`));
  if (seen.log.length) lines.push(`Log (the last ${seen.log.length} lines; all of it: ${seen.logFile})`, ...seen.log.map((line) => `  ${line.split("\n")[0].slice(0, 300)}`));
  return lines.join("\n");
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h" || command === "help") { console.log(USAGE); return; }

  if (command === "dev") {
    const { options, rest } = parse(args, ["port", "idle"]);
    const layout = layoutOf(rest[0] ?? ".");
    const port = options.port === undefined ? undefined : Number(options.port);
    if (port !== undefined && !(Number.isInteger(port) && port > 0 && port < 65536)) throw new Problem("--port takes a number from 1 to 65535");
    const live = await running(layout.folder);
    if (live?.own) {
      // One `lamp look` started for itself, with nobody watching it: this one takes its place.
      await ask(live, "stop", {}).catch(() => {});
      for (let tries = 0; tries < 30 && (await running(layout.folder)); tries++) await sleep(100);
    } else if (live) {
      // One server a folder: this one says where it is, and opens the window when asked.
      if (options.open) await ask(live, "open", {}, { timeout: 20_000 });
      console.log(`lamp dev is already running for this folder: ${live.url}`);
      return;
    }
    const server = await serve({ folder: layout.folder, port, lan: !!options.lan, quiet: !!options.quiet, idle: Number(options.idle) || 0 });
    for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => server.close().then(() => process.exit(0)));
    if (options.open) await server.openWindow();
    return;
  }

  if (command === "look") {
    const { options, rest } = parse(args, ["wait"]);
    const layout = layoutOf(rest[0] ?? ".");
    const wait = options.wait === undefined ? 20 : Math.min(Math.max(Number(options.wait) || 0, 0), 120);
    const seen = await ask(await serverFor(layout.folder), "look", { wait }, { timeout: (wait + 60) * 1000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "use") {
    const { options, rest } = parse(args, []);
    const kinds = ["key", "click", "type", "wait"];
    const folder = rest.length && !kinds.includes(rest[0]) ? rest.shift() : ".";
    const [kind, ...values] = rest;
    if (!kinds.includes(kind)) throw new Problem("use takes key <name> [seconds], click <x> <y>, type <text> or wait <seconds>");
    const action = kind === "key" ? { kind, key: values[0], seconds: values[1] }
      : kind === "click" ? { kind, x: values[0], y: values[1] }
      : kind === "type" ? { kind, text: values.join(" ") }
      : { kind, seconds: values[0] };
    if (kind === "key" && !values[0]) throw new Problem("key takes a key's name: lamp use key w 2");
    const layout = layoutOf(folder);
    const seen = await ask(await serverFor(layout.folder), "use", action, { timeout: 120_000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "reload" || command === "stop") {
    const { rest } = parse(args, []);
    const layout = layoutOf(rest[0] ?? ".");
    const live = await running(layout.folder);
    if (!live) { console.log("lamp dev isn't running for this folder."); return; }
    const answer = await ask(live, command, {});
    console.log(command === "stop" ? "Stopped." : answer.pages ? "The page is opening again." : "No page is open.");
    return;
  }

  if (command === "guide") {
    const { rest } = parse(args, []);
    let log = ".lamp/runtime/log.txt in the folder (a plain site's is named by `lamp look`)";
    try { log = logFileOf(layoutOf(rest[0] ?? ".")); } catch {}
    console.log(GUIDE(log));
    return;
  }

  if (command === "skills" || command === "skill") {
    // Lamp's skills, where they are beside this command in Lamp's own folder: the one place that says which of
    // Lamp's building blocks to use and how.
    const skills = join(here, "..", "Resources", "skills");
    if (!existsSync(skills)) throw new Problem("Lamp's skills aren't beside this copy of lamp");
    const name = command === "skill" ? args[0] : null;
    if (command === "skill" && !name) throw new Problem("skill takes a name: lamp skills lists them");
    if (name) {
      const file = join(skills, name, "SKILL.md");
      if (!/^[\w-]+$/.test(name) || !existsSync(file)) throw new Problem(`there's no skill "${name}": lamp skills lists them`);
      console.log(readFileSync(file, "utf8"));
      return;
    }
    for (const entry of readdirSync(skills, { withFileTypes: true }).filter((entry) => entry.isDirectory()).sort((a, b) => a.name.localeCompare(b.name))) {
      let text = "";
      try { text = readFileSync(join(skills, entry.name, "SKILL.md"), "utf8"); } catch { continue; }
      const description = /^description:\s*(.+)$/m.exec(text.split("\n---")[0] ?? "")?.[1] ?? "";
      console.log(`${entry.name}: ${description}`);
    }
    return;
  }

  throw new Problem(`there's no "${command}"\n\n${USAGE}`);
}

main().catch((error) => {
  if (error instanceof Problem) fail(error.message);
  throw error;
});
