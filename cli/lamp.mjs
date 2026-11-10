#!/usr/bin/env node
// lamp: runs a web app or web game from its folder and puts each saved change into the open page, for whoever is
// making it, a person or a coding agent. It needs no Mac app and no build step. No dependencies: Node 20 or later.
//
//   lamp new <folder>     a new web game's folder, from Lamp's starting files
//   lamp init [folder]    Lamp's game runtime, beside a page that's already there
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
import { serve, ANY_BROWSER, CONTROLLERS, CONTROLLERS_FILE, DEVICE_FILE, LAMP_JS } from "./dev.mjs";
import { allSkills } from "./skills.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

const USAGE = `lamp runs the web app or game in a folder and puts each saved change into the open page.

  lamp new <folder> [--name "Its Name"]
      Make a new web game's folder from Lamp's starting files: the game runtime, three.js and a page to build on.
  lamp init [folder] [--update]
      Give a page that's already there Lamp's game runtime: its own files beside the page, none of the page's
      changed. --update writes Lamp's files again, for a newer Lamp.
  lamp dev [folder] [--open] [--port N] [--lan]
      Run it, saying how each change went. --open opens a window for it; --lan lets other devices on the
      network open it too.
  lamp open [folder]
      Show it in a window, running it in the background if it isn't running. Returns at once.
  lamp look [folder] [--reopen] [--size 800x600] [--wait seconds] [--json]
      How the changes since the last look went, a picture of the page, its screen as text, and its log.
      --reopen opens the page again from its beginning first (a game's saves kept): what someone opening it sees.
      --size looks at it as a window of that size shows it, when no window of the person's is open.
  lamp use [folder] <one of these>
      Try it as a person would, then look:
        click <x> <y>                         a point of the picture
        type <text>                           into whatever has the keyboard
        key <name> [seconds]                  a key, or several at once (w+a), held: a letter, a digit, space,
                                              enter, escape, tab, backspace, delete, up, down, left, right,
                                              shift, control, alt, command, f1 to f12
        drag <x> <y> <to x> <to y>            press, move and let go
        scroll <points> [x y]                 down is positive
        stick <left|right> <x> <y> [seconds] [buttons]
                                              a game's controller: x and y from -1 to 1, right and up being 1
        button <name> [seconds]               a game's controller: a, b, x, y, lb, rb, lt, rt, menu, view, up… (a+rt)
        wait <seconds>
      Several at once, with "then" between them, go one after another with nothing in between and one look at the end:
        lamp use key space then stick left 1 0 3 then button a
  lamp reload [folder] [--fresh]
      Open the page again from its files, a game from where the player is, or with --fresh from its beginning.
  lamp stop [folder]      Stop running it.
  lamp setup [--remove]   Teach Claude Code and Codex on this computer to work this way (a skill for each).
  lamp guide              What that skill says, for any other agent.
  lamp skills [word]      Lamp's guidance for each kind of work, those about a word; lamp skill <name> reads one.

The folder is one Lamp made (its page is in Web/) or any folder with an index.html; without one, the folder you're in.`;

// What tells a coding agent how to work with lamp: one file, installed as a skill by `lamp setup` and printed by
// `lamp guide`. `{{lamp}}` in it is how lamp is run on this computer.
const SKILL_MARK = "<!-- Written by lamp setup: run it again to update, or with --remove to take it away. -->";
/** How lamp is run on this computer: `lamp` when that name runs this very file, else the file itself. */
function lampCommand() {
  const me = fileURLToPath(import.meta.url);
  const found = spawnSync(process.platform === "win32" ? "where" : "which", ["lamp"], { encoding: "utf8" });
  const onPath = found.status === 0 && found.stdout.trim().split("\n").some((path) => { try { return realpathSync(path.trim()) === realpathSync(me); } catch { return false; } });
  return onPath ? "lamp" : `node ${/\s/.test(me) ? JSON.stringify(me) : me}`;
}
/**
 * The skill as it's read on this computer. Where lamp isn't a command by its own name, the skill says once how it's
 * run and calls it lamp from there on: the whole path in every line would bury what the lines say.
 */
function skillText() {
  const text = readFileSync(join(here, "skill", "SKILL.md"), "utf8"), command = lampCommand();
  if (command === "lamp") return text.replaceAll("{{lamp}}", "lamp");
  const said = `**lamp isn't a command by that name on this computer. Wherever this says \`lamp\`, run:**\n\n    ${command}\n\n`;
  return text.replaceAll("{{lamp}}", "lamp").replace(/\n# [^\n]*\n\n/, (heading) => heading + said);
}
const quoted = (path) => (/\s/.test(path) ? JSON.stringify(path) : path);

/**
 * Copies in Lamp's libraries that the page's import map names and its folder has none of (three.js, Phaser, Rapier:
 * `Resources/WebLibraries`), as Lamp's app gives a game the ones its page uses. The names copied.
 */
function addLibraries(root) {
  const lamps = join(here, "..", "Resources", "WebLibraries");
  let map = "";
  try { map = /<script[^>]*type=["']importmap["'][^>]*>([\s\S]*?)<\/script>/i.exec(readFileSync(join(root, "index.html"), "utf8"))?.[1] ?? ""; } catch {}
  const added = [];
  for (const name of ["three", "phaser", "rapier"]) {
    // Named as a folder beside the page: one loaded from elsewhere (a CDN) is the page's own business.
    if (!new RegExp(`:\\s*["'](?:\\./)?${name}/`).test(map) || existsSync(join(root, name)) || !existsSync(join(lamps, name))) continue;
    cpSync(join(lamps, name), join(root, name), { recursive: true });
    added.push(`${name}/`);
  }
  return added;
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
  if (seen.where) lines.push(`Looked at ${WHERE[seen.where]}${seen.title ? `: "${seen.title}"` : ""}${seen.width ? `, ${seen.width}×${seen.height}` : ""}.${seen.opened ? " It was opened just now, from the files as they are." : ""}${seen.playing ? " The game says it's playing." : seen.playing === false ? " The game hasn't said it's playing yet." : ""}`);
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
    lines.push(`Log since the last look${seen.logLines > 25 ? ` (its end: all ${seen.logLines} lines are in ${seen.logFile})` : ""}`, ...seen.log.map((line) => `  ${line.split("\n")[0].slice(0, 300)}`));
  } else {
    lines.push("Log since the last look: nothing");
  }
  if (seen.opened) lines.push(`The whole log is kept in ${seen.logFile}`);
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
    if (![scaffold, runtime, three, CONTROLLERS].every(existsSync)) throw new Problem("Lamp's starting files aren't beside this copy of lamp");
    const name = String(options.name ?? basename(folder).split(/[-_\s]+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" "));
    const inPage = name.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
    mkdirSync(folder, { recursive: true });
    for (const file of readdirSync(scaffold)) {
      writeFileSync(join(folder, file), readFileSync(join(scaffold, file), "utf8").replaceAll("{{NAME}}", file.endsWith(".html") ? inPage : name.replace(/[\r\n]+/g, " ")));
    }
    for (const file of readdirSync(runtime)) cpSync(join(runtime, file), join(folder, file));
    addLibraries(folder);
    // Lamp's own files beside the page, which its app writes at every build: with them the folder is a whole site,
    // and runs wherever it's served from. lamp.js is the stand-in until Lamp's app takes the folder on.
    cpSync(CONTROLLERS, join(folder, CONTROLLERS_FILE));
    writeFileSync(join(folder, DEVICE_FILE), ANY_BROWSER);
    writeFileSync(join(folder, "lamp.js"), LAMP_JS);
    // The app's notes, which an app made by Lamp keeps and Lamp's skills write in.
    writeFileSync(join(folder, "APP.md"), `# ${name.replace(/[\r\n]+/g, " ")}\n\nA web game on Lamp's game runtime, not written yet.\n`);
    console.log(`Made ${folder}: a new game, "${name}", on Lamp's game runtime, with three.js and Phaser beside it.`);
    console.log("Yours to write: index.html (keep its head), game.js and modules beside it, and APP.md. world.js and making.js are the card it shows until then: the game replaces them.");
    console.log("Lamp's, never edited: lamp.js, lamp-game.js, lamp-phaser.js, lamp-controllers.js, lamp-device.js, three/ and phaser/.");
    console.log(`Write the game, then see its real opening with: ${lampCommand()} look ${quoted(folder)} --reopen`);
    return;
  }

  if (command === "init") {
    const { options, rest } = parse(args, []);
    const layout = layoutOf(rest[0] ?? ".");
    const runtime = join(here, "..", "Resources", "GameKit", "web");
    if (![runtime, CONTROLLERS].every(existsSync)) throw new Problem("Lamp's own files aren't beside this copy of lamp");
    // Lamp's own files beside a game's page: the runtime, and what its app writes at every build. Only those: the
    // page and its code are the project's, and taking up the runtime in them is the work that follows.
    const files = [
      ...readdirSync(runtime).map((name) => [name, () => readFileSync(join(runtime, name))]),
      [CONTROLLERS_FILE, () => readFileSync(CONTROLLERS)], [DEVICE_FILE, () => ANY_BROWSER],
    ];
    const wrote = [], kept = [];
    for (const [name, contents] of files) {
      const file = join(layout.root, name);
      if (existsSync(file) && !options.update) { kept.push(name); continue; }
      writeFileSync(file, contents());
      wrote.push(name);
    }
    // lamp.js is Lamp's building blocks, which only its app writes: a stand-in where there's none, never over one.
    if (!existsSync(join(layout.root, "lamp.js"))) { writeFileSync(join(layout.root, "lamp.js"), LAMP_JS); wrote.push("lamp.js"); }
    // And Lamp's libraries the page's import map names from beside it, where the folder has none.
    wrote.push(...addLibraries(layout.root));
    console.log(wrote.length ? `Lamp's own files are beside the page in ${layout.root}: ${wrote.join(", ")}.` : `Lamp's own files were beside the page already in ${layout.root}.`);
    if (kept.length) console.log(`Left as they were: ${kept.join(", ")} (lamp init --update writes them again).`);
    console.log(`The game takes the runtime up in its own code. Lamp's game-live skill says how (${lampCommand()} skill game-live), and lamp-game.js's own comments are the whole interface.`);
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
    const { options, rest } = parse(args, ["wait", "size"]);
    const layout = layoutOf(rest[0] ?? ".");
    const wait = options.wait === undefined ? 20 : Math.min(Math.max(Number(options.wait) || 0, 0), 120);
    const size = options.size === undefined ? null : /^(\d{3,4})x(\d{3,4})$/i.exec(options.size)?.slice(1).map(Number);
    if (options.size !== undefined && !size) throw new Problem("--size takes a width and a height: --size 800x600");
    const seen = await ask(await serverFor(layout.folder), "look", { wait, reopen: !!options.reopen, size }, { timeout: (wait + 60) * 1000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "use") {
    const { options, rest } = parse(args, []);
    const kinds = ["key", "click", "type", "wait", "drag", "scroll", "stick", "button"];
    const folder = rest.length && !kinds.includes(rest[0]) ? rest.shift() : ".";
    // Several moves, with "then" between them, are made one after another with nothing in between, and looked at once.
    const moves = [];
    for (let words = rest; words.length; ) {
      const next = words.indexOf("then");
      const [kind, ...values] = next < 0 ? words : words.slice(0, next);
      words = next < 0 ? [] : words.slice(next + 1);
      if (!kinds.includes(kind)) throw new Problem("use takes key, click, type, drag, scroll, stick, button or wait: lamp --help shows each");
      if (kind === "key" && !values[0]) throw new Problem("key takes a key's name: lamp use key w 2");
      moves.push(kind === "key" ? { kind, key: values[0], seconds: values[1] }
        : kind === "click" ? { kind, x: values[0], y: values[1] }
        : kind === "type" ? { kind, text: values.join(" ") }
        : kind === "drag" ? { kind, x: values[0], y: values[1], toX: values[2], toY: values[3] }
        : kind === "scroll" ? { kind, points: values[0], x: values[1], y: values[2] }
        : kind === "stick" ? { kind, side: values[0], x: values[1], y: values[2], seconds: values[3], buttons: values[4] }
        : kind === "button" ? { kind, buttons: values[0], seconds: values[1] }
        : { kind, seconds: values[0] });
    }
    if (!moves.length) throw new Problem("use takes key, click, type, drag, scroll, stick, button or wait: lamp --help shows each");
    const layout = layoutOf(folder);
    const seen = await ask(await serverFor(layout.folder), "use", moves.length === 1 ? moves[0] : { moves }, { timeout: 60_000 + moves.length * 35_000 });
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
    const { options, rest } = parse(args, []);
    const layout = layoutOf(rest[0] ?? ".");
    const live = await running(layout.folder);
    if (!live) { console.log("lamp dev isn't running for this folder."); return; }
    const answer = await ask(live, command, { fresh: !!options.fresh });
    console.log(command === "stop" ? "Stopped." : answer.pages ? "The page is opening again." : "No page is open.");
    return;
  }

  if (command === "guide") {
    // The skill without what only a skill's file needs in front.
    console.log(skillText().replace(/^---\n[\s\S]*?\n---\n+/, "").trimEnd());
    return;
  }

  if (command === "skills" || command === "skill") {
    // Lamp's skills, from Lamp's own folder beside this command: the one place that says which of Lamp's building
    // blocks to use and how.
    const skills = allSkills();
    if (!skills.size) throw new Problem("Lamp's skills aren't beside this copy of lamp");
    if (command === "skill") {
      if (!args[0]) throw new Problem("skill takes a name: lamp skills lists them");
      const skill = skills.get(args[0]);
      if (!skill) throw new Problem(`there's no skill "${args[0]}": lamp skills lists them`);
      console.log(`# ${skill.name}\n\n${skill.description}\n\n${skill.body}`);
      return;
    }
    // `lamp skills game` lists only those about a word.
    const about = args[0] ? args[0].toLowerCase() : null;
    const listed = [...skills.values()].filter((skill) => !about || `${skill.name} ${skill.description}`.toLowerCase().includes(about)).sort((a, b) => a.name.localeCompare(b.name));
    for (const skill of listed) console.log(`${skill.name}: ${skill.description.length > 170 ? skill.description.slice(0, 170).replace(/\s+\S*$/, "") + "…" : skill.description}`);
    if (about && !listed.length) console.log(`No skill is about "${about}": lamp skills lists them all.`);
    else if (!about) console.log("\n`lamp skills <word>` lists only those about a word; `lamp skill <name>` prints one.");
    return;
  }

  throw new Problem(`there's no "${command}"\n\n${USAGE}`);
}

main().catch((error) => {
  if (error instanceof Problem) fail(error.message);
  throw error;
});
