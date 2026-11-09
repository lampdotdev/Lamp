#!/usr/bin/env node
// lamp: runs a web app or web game from its folder and puts each saved change into the open page, for whoever is
// making it, a person or a coding agent. It needs no Mac app and no build step. No dependencies: Node 20 or later.
//
//   lamp new <folder>     a new web game's folder, from Lamp's starting files
//   lamp dev [folder]     run it, each save going into the open page
//   lamp open [folder]    show it in a window, running it if it isn't
//   lamp look [folder]    how the last change went, a picture, the screen as text and the log
//   lamp use [folder] …   try it: a key, a click, some typing
//   lamp stop [folder]    stop running it
//   lamp setup            teach the coding agents on this computer to work this way
//   lamp skills           Lamp's guidance for each kind of work; lamp skill <name> reads one

import { spawn, spawnSync } from "node:child_process";
import { cpSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, rmSync, rmdirSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, layoutOf, stateOf, running, ask } from "./state.mjs";
import { serve } from "./dev.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

const USAGE = `lamp runs the web app or game in a folder and puts each saved change into the open page.

  lamp new <folder> [--name "Its Name"]
      Make a new web game's folder from Lamp's starting files: the game runtime, three.js and a page to build on.
  lamp dev [folder] [--open] [--port N] [--lan]
      Run it, saying how each change went. --open opens a window for it; --lan lets other devices on the
      network open it too.
  lamp open [folder]
      Show it in a window, running it in the background if it isn't running. Returns at once.
  lamp look [folder] [--wait seconds] [--json]
      How the changes since the last look went, a picture of the page, its screen as text, and its log.
  lamp use [folder] <one of these>
      Try it as a person would, then look:
        click <x> <y>                         a point of the picture
        type <text>                           into whatever has the keyboard
        key <name> [seconds]                  a key, or several at once (w+a), held
        drag <x> <y> <to x> <to y>            press, move and let go
        scroll <points> [x y]                 down is positive
        stick <left|right> <x> <y> [seconds] [buttons]
                                              a game's controller: x and y from -1 to 1, right and up being 1
        button <name> [seconds]               a game's controller: a, b, x, y, lb, rb, lt, rt, menu, view, up… (a+rt)
        wait <seconds>
  lamp reload [folder]    Open the page again from its files, a game from where the player is.
  lamp stop [folder]      Stop running it.
  lamp setup [--remove]   Teach Claude Code and Codex on this computer to work this way (a skill for each).
  lamp guide              What that skill says, for any other agent.
  lamp skills [word]      Lamp's guidance for each kind of work, those about a word; lamp skill <name> reads one.

The folder is one Lamp made (its page is in Web/) or any folder with an index.html; without one, the folder you're in.`;

// What tells a coding agent how to work with lamp: one file, installed as a skill by `lamp setup` and printed by
// `lamp guide`. `{{lamp}}` in it is how lamp is run on this computer.
const SKILL_MARK = "<!-- Written by lamp setup: run it again to update, or with --remove to take it away. -->";
function skillText() {
  // `lamp` when that name runs this very file, else the file itself.
  const me = fileURLToPath(import.meta.url);
  const found = spawnSync(process.platform === "win32" ? "where" : "which", ["lamp"], { encoding: "utf8" });
  const onPath = found.status === 0 && found.stdout.trim().split("\n").some((path) => { try { return realpathSync(path.trim()) === realpathSync(me); } catch { return false; } });
  const lamp = onPath ? "lamp" : `node ${/\s/.test(me) ? JSON.stringify(me) : me}`;
  return readFileSync(join(here, "skill", "SKILL.md"), "utf8").replaceAll("{{lamp}}", lamp);
}

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
  copy: "lamp's own copy of the page, which nobody sees (no window is open)",
  page: "a page open in a browser lamp can't look into",
};

function report(seen) {
  const lines = [];
  if (seen.did) lines.push(seen.did);
  if (seen.where) lines.push(`Looked at ${WHERE[seen.where]}${seen.title ? `: "${seen.title}"` : ""}${seen.width ? `, ${seen.width}×${seen.height}` : ""}.${seen.opened ? " It was opened just now, from the files as they are." : ""}`);
  if (seen.problem) lines.push(seen.problem);
  if (seen.unfinished) lines.push(`Taken while ${seen.unfinished}: look again.`);
  if (seen.picture) lines.push(`Picture   ${seen.picture}`);
  if (seen.changes.length) {
    lines.push("Changes since the last look");
    for (const change of seen.changes) lines.push(`  ${change.files} → ${change.outcome}: ${change.means}${change.why ? ` (${change.why})` : ""}`);
  } else {
    lines.push(`Changes since the last look: none${seen.opened ? " to put in (the page opened with every file as it is now)" : ""}`);
  }
  lines.push(seen.errors.length ? "Errors since the last look" : "Errors since the last look: none");
  for (const error of seen.errors) lines.push(`  ${error.split("\n").join("\n    ")}`);
  if (seen.screen) lines.push("Screen", ...seen.screen.split("\n").map((line) => `  ${line}`));
  if (seen.log.length) {
    lines.push(`Log since the last look${seen.logLines > seen.log.length ? ` (the last ${seen.log.length} of ${seen.logLines} lines)` : ""}; all of it: ${seen.logFile}`, ...seen.log.map((line) => `  ${line.split("\n")[0].slice(0, 300)}`));
  } else {
    lines.push(`Log since the last look: nothing; all of it: ${seen.logFile}`);
  }
  return lines.join("\n");
}

async function main() {
  const [command, ...args] = process.argv.slice(2);
  if (!command || command === "--help" || command === "-h" || command === "help") { console.log(USAGE); return; }

  if (command === "new") {
    const { options, rest } = parse(args, ["name"]);
    if (!rest[0]) throw new Problem("new takes the folder to make: lamp new harbor-racer");
    const folder = resolve(rest[0]);
    if (existsSync(folder) && readdirSync(folder).length) throw new Problem(`${folder} already has things in it`);
    // What Lamp gives a new web game: its starting page, the game runtime and three.js, from Lamp's own folder.
    const lamps = join(here, "..", "Resources"), scaffold = join(lamps, "GameKit", "scaffold-web", "Web");
    const runtime = join(lamps, "GameKit", "web"), three = join(lamps, "WebLibraries", "three");
    if (![scaffold, runtime, three].every(existsSync)) throw new Problem("Lamp's starting files aren't beside this copy of lamp");
    const name = String(options.name ?? basename(folder).split(/[-_\s]+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" "));
    const inPage = name.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    mkdirSync(folder, { recursive: true });
    for (const file of readdirSync(scaffold)) {
      writeFileSync(join(folder, file), readFileSync(join(scaffold, file), "utf8").replaceAll("{{NAME}}", file.endsWith(".html") ? inPage : name.replace(/[\r\n]+/g, " ")));
    }
    for (const file of readdirSync(runtime)) cpSync(join(runtime, file), join(folder, file));
    cpSync(three, join(folder, "three"), { recursive: true });
    console.log(`Made ${folder}: a new game, "${name}", on Lamp's game runtime with three.js.\nShow it with: lamp open ${/\s/.test(folder) ? JSON.stringify(folder) : folder}`);
    return;
  }

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
    const kinds = ["key", "click", "type", "wait", "drag", "scroll", "stick", "button"];
    const folder = rest.length && !kinds.includes(rest[0]) ? rest.shift() : ".";
    const [kind, ...values] = rest;
    if (!kinds.includes(kind)) throw new Problem("use takes key, click, type, drag, scroll, stick, button or wait: lamp --help shows each");
    const action = kind === "key" ? { kind, key: values[0], seconds: values[1] }
      : kind === "click" ? { kind, x: values[0], y: values[1] }
      : kind === "type" ? { kind, text: values.join(" ") }
      : kind === "drag" ? { kind, x: values[0], y: values[1], toX: values[2], toY: values[3] }
      : kind === "scroll" ? { kind, points: values[0], x: values[1], y: values[2] }
      : kind === "stick" ? { kind, side: values[0], x: values[1], y: values[2], seconds: values[3], buttons: values[4] }
      : kind === "button" ? { kind, buttons: values[0], seconds: values[1] }
      : { kind, seconds: values[0] };
    if (kind === "key" && !values[0]) throw new Problem("key takes a key's name: lamp use key w 2");
    const layout = layoutOf(folder);
    const seen = await ask(await serverFor(layout.folder), "use", action, { timeout: 120_000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "open") {
    const { rest } = parse(args, []);
    const layout = layoutOf(rest[0] ?? ".");
    const opened = await ask(await serverFor(layout.folder), "open", {}, { timeout: 30_000 });
    console.log(opened.opened === "window" ? `Opened in a window: ${opened.url}` : `Opened in the browser: ${opened.url}\nlamp found no browser it can look into (Chrome, Edge, Brave or Chromium), so looks have no picture.`);
    return;
  }

  if (command === "setup") {
    const { options } = parse(args, []);
    const text = `${skillText().trimEnd()}\n\n${SKILL_MARK}\n`;
    let any = false;
    for (const [agent, home] of [["Claude Code", join(homedir(), ".claude")], ["Codex", join(homedir(), ".codex")]]) {
      const folder = join(home, "skills", "lamp"), file = join(folder, "SKILL.md");
      // Only a skill lamp wrote is replaced or taken away.
      const theirs = existsSync(file) && !readFileSync(file, "utf8").includes(SKILL_MARK);
      if (options.remove) {
        if (!existsSync(file) || theirs) continue;
        rmSync(file);
        try { rmdirSync(folder); } catch {}
        console.log(`Took lamp's skill away from ${agent}.`);
        any = true;
      } else if (theirs) {
        console.log(`${agent} has a skill called lamp that lamp didn't write, left as it is: ${file}`);
        any = true;
      } else if (existsSync(home)) {
        mkdirSync(folder, { recursive: true });
        writeFileSync(file, text);
        console.log(`${agent} knows how to work with lamp, from its next session: ${file}`);
        any = true;
      }
    }
    if (!any) console.log(options.remove ? "There was no skill of lamp's to take away." : "Neither Claude Code nor Codex is set up on this computer. `lamp guide` prints what to give another agent.");
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
    // The skill without what only a skill's file needs in front.
    console.log(skillText().replace(/^---\n[\s\S]*?\n---\n+/, "").trimEnd());
    return;
  }

  if (command === "skills" || command === "skill") {
    // Lamp's skills, where they are beside this command in Lamp's own folder: the one place that says which of
    // Lamp's building blocks to use and how.
    const skills = join(here, "..", "Resources", "skills");
    if (!existsSync(skills)) throw new Problem("Lamp's skills aren't beside this copy of lamp");
    const name = command === "skill" ? args[0] : null;
    if (command === "skill" && !name) throw new Problem("skill takes a name: lamp skills lists them");
    // `lamp skills game` lists only those about a word.
    const about = command === "skills" && args[0] ? args[0].toLowerCase() : null;
    let listed = 0;
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
      if (about && !`${entry.name} ${description}`.toLowerCase().includes(about)) continue;
      listed += 1;
      console.log(`${entry.name}: ${description.length > 170 ? description.slice(0, 170).replace(/\s+\S*$/, "") + "…" : description}`);
    }
    if (about && !listed) console.log(`No skill is about "${about}": lamp skills lists them all.`);
    else if (!about) console.log("\n`lamp skills <word>` lists only those about a word; `lamp skill <name>` prints one.");
    return;
  }

  throw new Problem(`there's no "${command}"\n\n${USAGE}`);
}

main().catch((error) => {
  if (error instanceof Problem) fail(error.message);
  throw error;
});
