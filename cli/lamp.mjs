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
//   lamp share [folder]   a link on lamp.dev to play it, and lamp ideas for what people send back
//   lamp devices          the person's devices; lamp open --on xbox, or --on android, puts a page on one
//   lamp setup            teach the coding agents on this computer to work this way
//   lamp skills           Lamp's guidance for each kind of work; lamp skill <name> reads one

import { spawn, spawnSync } from "node:child_process";
import { chmodSync, cpSync, existsSync, mkdirSync, openSync, readdirSync, readFileSync, realpathSync, rmSync, rmdirSync, statSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { basename, dirname, join, resolve } from "node:path";
import { fileURLToPath } from "node:url";
import { Problem, layoutOf, projectOf, stateOf, running, ask } from "./state.mjs";
import { serveMac } from "./mac.mjs";
import { serve, ANY_BROWSER, CONTROLLERS, CONTROLLERS_FILE, DEVICE_FILE, lampJS } from "./dev.mjs";
import { allSkills } from "./skills.mjs";
import { share, unshare, ideas, finishIdea, readLink, nameOf, siteOrigin, LIMITS } from "./share.mjs";
import { Runner, allKept, fields, forget, integrationOf, isReady, look as lookForDevices, takesPages } from "./devices.mjs";
import { placeNamed } from "./place.mjs";
import { androidAdvice, androidDevices, androidDone, emulatorNamed, emulators, forgetAndroid, installTools, knowsAndroid, toolsThere } from "./android.mjs";

const here = dirname(fileURLToPath(import.meta.url));
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));

const USAGE = `lamp runs the app in a folder and puts each saved change into it: a web app or game, shown in a browser, or a
Mac app Lamp made in Swift, built and run on this Mac.

  lamp new <folder> [--name "Its Name"] [--web | --mac]
      Make a new web game's folder from Lamp's starting files: the game runtime, three.js and a page to build on.
      --web makes a new web app instead, and --mac a new Mac app in Swift, each with Lamp's building blocks.
  lamp init [folder] [--update]
      Give a page that's already there Lamp's game runtime: its own files beside the page, none of the page's
      changed. --update writes Lamp's files again, for a newer Lamp.
  lamp dev [folder] [--open] [--port N] [--lan]
      Run it, saying how each change went. --open opens a window for it; --lan lets other devices on the
      network open it too.
  lamp open [folder] [--on <device>] [--hidden]
      Show it in a window, running it in the background if it isn't running. Returns at once.
      --on puts a page on one of the person's devices instead and opens it there (--on xbox): packaged, installed
      and opened, the copy that was there replaced. --on android builds Lamp's Android app around the page and
      opens it in lamp's Android emulator (--on android-tv, its TV emulator), or on a phone, tablet or TV of the
      person's by its name. --hidden starts the emulator with no window and no sound, for a check nobody watches.
  lamp look [folder] [--reopen] [--size 800x600] [--wait seconds] [--json]
      How the changes since the last look went, a picture of the page (or of a Mac app's windows), its screen as
      text, and its log. --reopen opens it again from its beginning first (what it saved kept): what someone
      opening it sees.
      --size looks at it as a window of that size shows it, when no window of the person's is open.
      --on <device> looks at the device instead: its screen as a picture, whether the app is open there, and what
      the app last logged there, which for a game says how many frames a second it gets.
  lamp use [folder] [--on <android device>] <one of these>
      Try it as a person would, then look. --on tries it on an Android place instead: a point of its picture
      clicked or dragged from, typing, one key or one controller's button at a time (no stick), and wait.
        click <x> <y>                         a point of the picture
        click "A Name"                        a control by its name in the screen as text
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
      A Mac app is quit and opened again.
  lamp stop [folder] [--on <device>]
      Stop running it. A Mac app is quit. --on ends it on a device instead (and closes an emulator lamp started
      with no window).
  lamp remove [folder] --on <device>
      Take it off a device lamp put it on.
  lamp devices [add [name] | forget <name>]
      The person's devices that lamp puts a page on: an Xbox in Developer Mode, those set up and those found on the
      network; and Android, lamp's emulators and the phones, tablets and TVs plugged in with USB debugging on.
      "add" sets one up, a step at a time; it asks for what only the person should do (type an Xbox's Device Portal
      password; accept Google's terms for Android's tools, with "add android"), so they run it in a terminal
      themselves. "forget" lets one go ("forget android": lamp's emulators and its key to the person's devices).
  lamp share [folder] --words "What it is" [--name N] [--line "A line under its name"] [--by "Who made it"]
             [--asks "Found a bug?|What's missing?"] [--shape fill|16:9] [--no-picture] [--anyway]
      Put the page on lamp.dev, where anyone with the link plays it and can send an idea. Public, so only when the
      person asks. Again, it sends the page as it is now to the same link, with the same words unless new ones are given.
  lamp unshare [folder]   Take the link down.
  lamp ideas [folder] [in <n> | dismiss <n>]
      The ideas people playing the link have sent. "in" says one is in the game now (whoever asked to hear is
      written to); "dismiss" lets one go.
  lamp setup [--remove]   Teach Claude Code and Codex on this computer to work this way (a skill for each).
  lamp guide              What that skill says, for any other agent.
  lamp skills [word]      Lamp's guidance for each kind of work, those about a word; lamp skill <name> reads one.
  lamp blocks [folder] [Name]
      Lamp's building blocks for a Mac app (saved data, AI, windows, the menu bar…) with what each is for, or one
      in full: read from the app's own Sources/LampSupport.swift.

The folder is one Lamp made (a page in Web/, or a Mac app's Package.swift and build.sh) or any folder with an
index.html; without one, the folder you're in.`;

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

/** A look at a device, as words: whether the app is open there, where the picture of its screen is, and what the app logged. */
function deviceReport(seen) {
  const lines = [...(seen.did ? [seen.did] : []), seen.installed ? (seen.running === false ? `On ${seen.device}: not open now (lamp open --on puts it there again).` : `On ${seen.device}: open.`)
    : `On ${seen.device}: lamp hasn't put this there yet (lamp open --on does).`];
  if (seen.picture) lines.push(`Picture: ${seen.picture}${seen.size ? ` (${seen.size.width}x${seen.size.height})` : ""}, the device's screen now, whatever is on it.`);
  if (seen.log) {
    const said = seen.log.split(/\r?\n/).filter((line) => line.trim());
    lines.push(said.length ? `Its log there, the last ${Math.min(said.length, 40)} lines of ${said.length}:\n${said.slice(-40).map((line) => "  " + line).join("\n")}` : "Its log there is empty.");
  } else if (seen.installed) lines.push("It has logged nothing there yet.");
  return lines.join("\n");
}

/** What the person types for a device's setup, read from the terminal without showing it. */
function typed(label) {
  if (!process.stdin.isTTY) throw new Problem(`this needs ${label.toLowerCase()}, which only the person types: they run "${lampCommand()} devices add" in a terminal themselves`);
  return new Promise((done, failed) => {
    const input = process.stdin;
    let text = "";
    const end = () => { input.setRawMode(false); input.pause(); input.off("data", heard); process.stdout.write("\n"); };
    const heard = (chunk) => {
      for (const letter of String(chunk)) {
        if (letter === "\r" || letter === "\n") { end(); return done(text); }
        if (letter === "\u0003") { end(); return failed(new Problem("stopped")); }
        if (letter === "\u007f" || letter === "\b") text = text.slice(0, -1);
        else if (letter >= " ") text += letter;
      }
    };
    process.stdout.write(`${label} (not shown as you type): `);
    input.setRawMode(true);
    input.resume();
    input.on("data", heard);
  });
}

/** What a device is, by its maker and model, the maker said once. */
const called = (device) => (String(device.model).startsWith(device.maker) ? device.model : `${device.maker} ${device.model}`);

/** One line read from the person at the terminal. */
async function answered(question) {
  const { createInterface } = await import("node:readline/promises");
  const terminal = createInterface({ input: process.stdin, output: process.stdout });
  try { return (await terminal.question(question)).trim(); } finally { terminal.close(); }
}

/** What `lamp devices` says of Android: lamp's emulators, and the person's devices adb sees. Nothing where lamp can't build for it. */
async function androidLines() {
  if (!knowsAndroid()) return [];
  if (!toolsThere().builds) return [`Android: its tools aren't on this computer yet. "${lampCommand()} devices add android" downloads them (about 2 GB); it accepts Google's terms for them, so run it in a terminal yourself.`];
  const lines = ["Android:"];
  for (const emulator of await emulators()) {
    const standing = !emulator.downloaded ? `not downloaded yet (${lampCommand()} devices add ${emulator.word}, about a gigabyte)`
      : emulator.running ? `running${emulator.hidden ? ", with no window" : ""}` : "started when a page is opened in it";
    lines.push(`  ${emulator.name[0].toUpperCase()}${emulator.name.slice(1)} (--on ${emulator.word}): ${standing}`);
  }
  const own = await androidDevices();
  for (const device of own) lines.push(`  ${device.name} (--on ${/\s/.test(device.name) ? `"${device.name}"` : device.name}): ${device.state === "device" ? `ready${device.tv ? ", a TV" : ""}` : androidAdvice(device.name, device.state)}`);
  if (!own.length) lines.push("  A phone, tablet or TV of the person's is listed once it's plugged in with USB debugging on.");
  return lines;
}

/** `lamp devices add android`: Android's tools, downloaded once the person says so, since it accepts Google's terms for them. */
async function addAndroid(tv) {
  if (!knowsAndroid()) throw new Problem(process.platform === "darwin" ? "Lamp's Android app for a page isn't beside this copy of lamp: scripts/cli-files.sh writes it" : "lamp builds for Android on a Mac, so far");
  const there = toolsThere(), word = tv ? "android-tv" : "android";
  if (there.builds && there.emulatorPackages && (!tv || there.tvImage)) {
    console.log(`Android's tools are on this computer. Open a page in ${tv ? "the Android TV emulator" : "the Android emulator"} with: ${lampCommand()} open --on ${word}`);
    return;
  }
  if (!process.stdin.isTTY) throw new Problem(`this downloads Google's Android tools and accepts Google's terms for them, which only the person does: they run "${lampCommand()} devices add ${word}" in a terminal themselves`);
  console.log(`lamp makes Android apps with Google's free tools, and ${there.builds && there.emulatorPackages ? "the Android TV emulator isn't" : "they aren't all"} on this computer yet: ${there.builds && there.emulatorPackages ? "about a gigabyte" : "about 2 GB"}, kept in ~/Library/Developer/Lamp for every Lamp here.`);
  console.log("Downloading them accepts Google's terms for them: https://developer.android.com/studio/terms");
  if (!/^y(es)?$/i.test(await answered("Download them? (y/n) "))) { console.log("Nothing was downloaded."); return; }
  await installTools({ tv, said: (line) => console.log(line) });
  console.log(`\nAndroid's tools are ready. Open a page in ${tv ? "the Android TV emulator" : "the Android emulator"} with: ${lampCommand()} open --on ${word}`);
}

/** `lamp devices`: the person's devices that take a page, and setting one up. */
async function devices(args) {
  const { rest } = parse(args, []);
  const [verb, ...words] = rest, name = words.join(" ").toLowerCase();
  if (verb === "add" && emulatorNamed(name)) return addAndroid(emulatorNamed(name).emulator === "tv");
  if (verb === "forget" && name === "android") {
    console.log((await forgetAndroid()) ? "Forgot Android: lamp's emulators and its key to the person's devices are gone. Android's tools stay, for every Lamp here, and what lamp put on a device is still there."
      : "lamp has made nothing for Android to forget.");
    return;
  }
  const fits = (device) => !name || device.name.toLowerCase().includes(name) || device.integration.startsWith(name) || device.id.toLowerCase() === name;

  if (verb === "forget") {
    if (!name) throw new Problem("forget takes the device's name: lamp devices lists them");
    const mine = allKept().filter(fits);
    if (mine.length !== 1) throw new Problem(mine.length ? `"${words.join(" ")}" could be ${mine.map((device) => `"${device.name}"`).join(" or ")}` : `lamp has no device called "${words.join(" ")}" set up`);
    forget(mine[0].id);
    console.log(`Forgot ${mine[0].name}: its record, its certificate and what was typed for it. What lamp put on it is still there.`);
    return;
  }

  if (verb !== undefined && verb !== "add") throw new Problem("devices takes add or forget: lamp devices lists them");
  const all = await lookForDevices();
  const pages = all.filter((device) => takesPages(integrationOf(device.integration)));

  if (verb === undefined) {
    const mine = pages.filter((device) => device.kept), others = pages.filter((device) => !device.kept);
    if (mine.length) {
      console.log("Set up with lamp:");
      for (const device of mine) {
        const ready = isReady(device, integrationOf(device.integration));
        console.log(`  ${device.name}: ${device.model}, ${device.found === false ? `not answering now (last at ${device.address})` : `at ${device.address}`}${ready ? "" : ", setup not finished (lamp devices add)"}`);
      }
    }
    if (others.length) {
      console.log(`${mine.length ? "\n" : ""}Found on the network, not set up (they may not be yours):`);
      for (const device of others) console.log(`  ${device.name}: ${called(device)} at ${device.address}`);
      console.log(`\n"${lampCommand()} devices add" sets one up. It asks for what only you should type, so run it in a terminal yourself.`);
    }
    const elsewhere = all.filter((device) => !pages.includes(device) && device.found !== false);
    if (elsewhere.length) console.log(`${mine.length || others.length ? "\n" : ""}Also there, which lamp's command line doesn't put a page on: ${elsewhere.map((device) => `${device.name} (${called(device)})`).join(", ")}.`);
    if (!mine.length && !others.length) {
      console.log("lamp found no Xbox to put a page on. One is found in Developer Mode, on this network and switched on:");
      for (const line of integrationOf("xbox-one")?.steps?.[0]?.lines ?? []) console.log(`  - ${line}`);
    }
    const android = await androidLines();
    if (android.length) console.log("\n" + android.join("\n"));
    return;
  }

  // add: the one named, or the only one there, taken through its integration's steps in order.
  const candidates = pages.filter((device) => device.found !== false && fits(device));
  if (!candidates.length) {
    throw new Problem(`lamp found no ${name ? `device called "${words.join(" ")}" on the network` : "device on the network that it puts a page on"}. An Xbox answers once it's on and in Developer Mode:\n`
      + (integrationOf("xbox-one")?.steps?.[0]?.lines ?? []).map((line) => `  - ${line}`).join("\n"));
  }
  if (candidates.length > 1) throw new Problem(`lamp found ${candidates.map((device) => `"${device.name}"`).join(" and ")}: say which, lamp devices add <name>`);
  const device = candidates[0], integration = integrationOf(device.integration), runner = new Runner({ integration, device });
  console.log(`${device.name}: ${called(device)} at ${device.address}`);
  for (const step of integration.steps ?? []) {
    let result = await runner.check(step);
    for (let tries = 0; !result.passed && step.field && (result.needs || result.rejected) && tries < 3; tries++) {
      if (result.rejected) { fields.remove(device.id, step.field.key); console.log(`${device.name} didn't take that.`); }
      else { console.log(`\n${step.title}`); for (const line of step.lines ?? []) console.log(`  - ${line}`); }
      fields.save(device.id, step.field.key, await typed(step.field.label));
      result = await runner.check(step);
    }
    if (result.passed) { runner.passed(step, result.read); console.log(`Done: ${step.title}.`); continue; }
    if (result.rejected) fields.remove(device.id, step.field?.key);
    if (result.failed) throw new Problem(result.why);
    console.log(`\nNext: ${step.title}`);
    for (const line of step.lines ?? []) console.log(`  - ${line}`);
    if (step.link) console.log(`  ${step.link}`);
    console.log(`\nThen run "${lampCommand()} devices add" again.`);
    process.exitCode = 1;
    return;
  }
  console.log(`\n${device.name} is set up${device.model ? ` (${device.model})` : ""}. Put a page on it with: ${lampCommand()} open --on ${integration.id.split("-")[0]}`);
}

const WHERE = {
  mac: "the app as it runs on this Mac",
  window: "the window the person has open",
  copy: "lamp's own copy of the page, which nobody sees (no window is open)",
  page: "a page open in a browser lamp can't look into",
};

function report(seen) {
  const lines = [];
  if (seen.did) lines.push(seen.did);
  if (seen.where) lines.push(`Looked at ${WHERE[seen.where]}${seen.title ? `: "${seen.title}"` : ""}${seen.width ? `, ${seen.width}×${seen.height}` : ""}.${seen.opened ? " It was opened just now, from the files as they are." : ""}${seen.playing ? " The game says it's playing." : seen.playing === false ? " The game hasn't said it's playing yet." : ""}`);
  if (seen.problem) lines.push(seen.problem);
  if (seen.note) lines.push(seen.note);
  if (seen.unfinished) lines.push(`Taken while ${seen.unfinished}: look again.`);
  if (seen.picture) lines.push(`Picture   ${seen.picture}`);
  for (const other of seen.pictures ?? []) lines.push(`          ${other}  (another of its windows)`);
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
    if (options.web) {
      // A new web app's page as Lamp's app makes one (`ScreenKit.fill`): the page, its style and script, lamp.js and
      // its notes, from a copy Lamp's own code wrote under a stand-in name (scripts/cli-files.sh).
      const starter = join(here, "lamps", "web-starter");
      if (!existsSync(join(starter, "lamp-starter.json"))) {
        throw new Problem(`Lamp's starting files for a web app aren't made yet. In Lamp's folder, run scripts/cli-files.sh: it writes them from Lamp's own code.`);
      }
      const stood = JSON.parse(readFileSync(join(starter, "lamp-starter.json"), "utf8"));
      const title = String(options.name ?? basename(folder).split(/[-_\s]+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" ")).replace(/[\r\n]+/g, " ").trim();
      if (!title || title.length > 60) throw new Problem("a web app's name is 60 characters at most: --name \"Its Name\"");
      const inHTML = title.replace(/[&<>"]/g, (c) => ({ "&": "&amp;", "<": "&lt;", ">": "&gt;", '"': "&quot;" })[c]);
      mkdirSync(folder, { recursive: true });
      for (const file of readdirSync(starter)) {
        if (file === "lamp-starter.json") continue;
        // Lamp's building blocks are the same for every page; the rest names this one.
        if (file === "lamp.js") cpSync(join(starter, file), join(folder, file));
        else writeFileSync(join(folder, file), readFileSync(join(starter, file), "utf8").replaceAll(stood.name, file.endsWith(".html") ? inHTML : title));
      }
      console.log(`Made ${folder}: a new web app, "${title}", with Lamp's building blocks for a page (lamp.js).`);
      console.log("Yours to write: index.html, style.css, app.js and APP.md. It shows a card until then.");
      console.log("Lamp's, never edited: lamp.js.");
      console.log(`Write the app, then see it with: ${lampCommand()} look ${quoted(folder)}`);
      return;
    }
    if (options.mac) {
      // A new Mac app as Lamp's app makes one (`Template.scaffold`): Lamp's own files and the card the app shows until
      // it's written, from a copy Lamp's own code wrote under a stand-in name (scripts/cli-files.sh).
      const starter = join(here, "lamps", "mac-starter");
      if (!existsSync(join(starter, "lamp-starter.json"))) {
        throw new Problem(`Lamp's starting files for a Mac app aren't made yet. In Lamp's folder, run scripts/cli-files.sh: it writes them from Lamp's own code.`);
      }
      const stood = JSON.parse(readFileSync(join(starter, "lamp-starter.json"), "utf8"));
      const title = String(options.name ?? basename(folder).split(/[-_\s]+/).filter(Boolean).map((word) => word[0].toUpperCase() + word.slice(1)).join(" ")).trim();
      // The name goes into the app's build script and its code as it is, so it's one that's safe in both.
      if (!/^[A-Za-z][A-Za-z0-9 ]{0,39}$/.test(title)) throw new Problem("a Mac app's name here is letters, digits and spaces, starting with a letter, 40 at most: --name \"Its Name\"");
      const exe = title.split(/\s+/).map((word) => word[0].toUpperCase() + word.slice(1)).join(""), slug = exe.toLowerCase();
      const named = (text) => text.replaceAll(stood.bundle, `dev.lamp.cli.app.${slug}`).replaceAll(stood.name, title).replaceAll(stood.exe, exe).replaceAll(stood.slug, slug);
      const copy = (from, to) => {
        mkdirSync(to, { recursive: true });
        for (const entry of readdirSync(from, { withFileTypes: true })) {
          // What Lamp's app knows of the stand-in (.lamp) and the names it stood for aren't the new app's.
          if (entry.name === ".lamp" || entry.name === "lamp-starter.json") continue;
          const source = join(from, entry.name), target = join(to, named(entry.name));
          if (entry.isDirectory()) { copy(source, target); continue; }
          if (!entry.isFile()) continue;
          // Lamp's building blocks are the same for every app; the rest names this one.
          if (entry.name === "LampSupport.swift" || !/\.(swift|sh|md|json|plist|txt)$|^\.gitignore$/.test(entry.name)) cpSync(source, target);
          else writeFileSync(target, named(readFileSync(source, "utf8")));
          chmodSync(target, statSync(source).mode);
        }
      };
      copy(starter, folder);
      console.log(`Made ${folder}: a new Mac app, "${title}", with Lamp's building blocks (Sources/LampSupport.swift).`);
      console.log("Yours to write: the app's code in Sources/, and APP.md. It shows a card until then.");
      console.log("Lamp's, never edited: Sources/LampSupport.swift, build.sh and Package.swift.");
      console.log(`Build and open it with: ${lampCommand()} open ${quoted(folder)}`);
      return;
    }
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
    writeFileSync(join(folder, "lamp.js"), lampJS(true));
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
    if (!existsSync(join(layout.root, "lamp.js"))) { writeFileSync(join(layout.root, "lamp.js"), lampJS(true)); wrote.push("lamp.js"); }
    // And Lamp's libraries the page's import map names from beside it, where the folder has none.
    wrote.push(...addLibraries(layout.root));
    console.log(wrote.length ? `Lamp's own files are beside the page in ${layout.root}: ${wrote.join(", ")}.` : `Lamp's own files were beside the page already in ${layout.root}.`);
    if (kept.length) console.log(`Left as they were: ${kept.join(", ")} (lamp init --update writes them again).`);
    console.log(`The game takes the runtime up in its own code. Lamp's game-live skill says how (${lampCommand()} skill game-live), and lamp-game.js's own comments are the whole interface.`);
    return;
  }

  if (command === "dev") {
    const { options, rest } = parse(args, ["port", "idle"]);
    const layout = projectOf(rest[0] ?? ".");
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
    // A page is served and shown in a browser; a Mac app is built and run. Each is the folder's server from here on.
    const server = layout.kind === "mac"
      ? await serveMac({ folder: layout.folder, port, quiet: !!options.quiet, idle: Number(options.idle) || 0 })
      : await serve({ folder: layout.folder, port, lan: !!options.lan, quiet: !!options.quiet, idle: Number(options.idle) || 0 });
    for (const signal of ["SIGINT", "SIGTERM", "SIGHUP"]) process.on(signal, () => server.close().then(() => process.exit(0)));
    if (options.open && layout.kind !== "mac") await server.openWindow();
    return;
  }

  if (command === "look") {
    const { options, rest } = parse(args, ["wait", "size", "on"]);
    if (options.on !== undefined) {
      const seen = await (await placeNamed(options.on, { command: lampCommand() })).look(layoutOf(rest[0] ?? "."));
      console.log(options.json ? JSON.stringify(seen, null, 2) : deviceReport(seen));
      return;
    }
    const layout = projectOf(rest[0] ?? ".");
    // A Mac app's change is a build, which takes longer than a page's.
    const wait = options.wait === undefined ? (layout.kind === "mac" ? 180 : 20) : Math.min(Math.max(Number(options.wait) || 0, 0), 600);
    const size = options.size === undefined ? null : /^(\d{3,4})x(\d{3,4})$/i.exec(options.size)?.slice(1).map(Number);
    if (options.size !== undefined && !size) throw new Problem("--size takes a width and a height: --size 800x600");
    const seen = await ask(await serverFor(layout.folder), "look", { wait, reopen: !!options.reopen, size }, { timeout: (wait + 60) * 1000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "use") {
    const { options, rest } = parse(args, ["on"]);
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
        : kind === "click" ? (Number.isFinite(Number(values[0])) ? { kind, x: values[0], y: values[1] } : { kind, target: values.join(" ") })
        : kind === "type" ? { kind, text: values.join(" ") }
        : kind === "drag" ? { kind, x: values[0], y: values[1], toX: values[2], toY: values[3] }
        : kind === "scroll" ? { kind, points: values[0], x: values[1], y: values[2] }
        : kind === "stick" ? { kind, side: values[0], x: values[1], y: values[2], seconds: values[3], buttons: values[4] }
        : kind === "button" ? { kind, buttons: values[0], seconds: values[1] }
        : { kind, seconds: values[0] });
    }
    if (!moves.length) throw new Problem("use takes key, click, type, drag, scroll, stick, button or wait: lamp --help shows each");
    if (options.on !== undefined) {
      const place = await placeNamed(options.on, { command: lampCommand() });
      if (!place.use) throw new Problem(`lamp can't press a controller on ${place.name}: try it in its window on this computer (lamp use), and see how it runs there with lamp look --on`);
      const seen = await place.use(layoutOf(folder), moves);
      console.log(options.json ? JSON.stringify(seen, null, 2) : deviceReport(seen));
      return;
    }
    const layout = projectOf(folder);
    const seen = await ask(await serverFor(layout.folder), "use", moves.length === 1 ? moves[0] : { moves }, { timeout: 60_000 + moves.length * 35_000 });
    console.log(options.json ? JSON.stringify(seen, null, 2) : report(seen));
    return;
  }

  if (command === "open") {
    const { options, rest } = parse(args, ["on"]);
    if (options.on !== undefined) {
      const layout = layoutOf(rest[0] ?? "."), place = await placeNamed(options.on, { command: lampCommand() });
      const put = await place.put(layout, { said: (line) => console.log(line), hidden: !!options.hidden });
      console.log(put.line);
      console.log(`${lampCommand()} look --on ${options.on} shows its screen and what it logged there; ${lampCommand()} stop --on ${options.on} ends it.`);
      return;
    }
    const layout = projectOf(rest[0] ?? ".");
    const opened = await ask(await serverFor(layout.folder), "open", {}, { timeout: 30_000 });
    if (opened.opened === "app") {
      console.log(opened.running ? `${opened.url} is open.` : opened.building ? `${opened.url} is being built, and opens when it is: lamp look waits for it.` : `${opened.url} didn't build: lamp look says why.`);
      return;
    }
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

  if (command === "share") {
    const { options, rest } = parse(args, ["name", "words", "line", "by", "asks", "shape"]);
    const layout = layoutOf(rest[0] ?? ".");
    const before = readLink(layout.folder)?.site === siteOrigin() ? readLink(layout.folder) : null;
    // The link's words: what's given now, else what it went out with before. Its name, where nothing says, is the page's.
    const words = {
      name: String(options.name ?? before?.name ?? nameOf(layout)).trim(), words: String(options.words ?? before?.words ?? "").trim(),
      line: String(options.line ?? before?.line ?? "").trim(), by: String(options.by ?? before?.by ?? "").trim(),
      asks: options.asks !== undefined ? String(options.asks).split("|").map((ask) => ask.trim()).filter(Boolean) : before?.asks ?? [],
    };
    const count = (text) => [...new Intl.Segmenter("en", { granularity: "grapheme" }).segment(text)].length;
    if (!words.words) throw new Problem('a link says what the page is: share it with --words "What it is, in a sentence or a few"');
    if (!words.name || count(words.name) > LIMITS.name) throw new Problem(`a link's name is at most ${LIMITS.name} characters: --name "Its Name"`);
    if (count(words.words) > LIMITS.words) throw new Problem(`a link's words are at most ${LIMITS.words} characters`);
    if (count(words.line) > LIMITS.line) throw new Problem(`a link's line is at most ${LIMITS.line} characters`);
    if (count(words.by) > LIMITS.by) throw new Problem(`who it's by is at most ${LIMITS.by} characters`);
    if (words.asks.length > LIMITS.asks || words.asks.some((ask) => count(ask) > LIMITS.ask)) throw new Problem(`a link asks at most ${LIMITS.asks} things, each of at most ${LIMITS.ask} characters`);
    // The page as it runs now: its picture for the link's card, the shape it plays in, and whether it's working.
    let card = { picture: null, stage: null, errors: [] };
    if (!options["no-picture"]) card = await ask(await serverFor(layout.folder), "card", { wait: 30 }, { timeout: 120_000 });
    if (card.errors.length && !options.anyway) {
      throw new Problem(`the page logged errors, and a link shows it to anyone:\n  ${card.errors.slice(0, 5).join("\n  ")}\nPut them right, or share it as it is with --anyway.`);
    }
    let shape = card.stage ? Math.round((card.stage[0] / card.stage[1]) * 10000) / 10000 : "fill";
    if (options.shape !== undefined) {
      const ratio = /^(\d+(?:\.\d+)?)[:/x](\d+(?:\.\d+)?)$/.exec(String(options.shape));
      if (options.shape !== "fill" && !ratio) throw new Problem("--shape is fill, for a page that takes any window, or a shape like 16:9");
      shape = ratio ? Math.round((Number(ratio[1]) / Number(ratio[2])) * 10000) / 10000 : "fill";
    }
    const sent = await share({ layout, words, shape, picture: card.picture ? Buffer.from(card.picture, "base64") : null, said: (line) => console.log(line) });
    console.log(`${before ? "Sent again to its link" : "Shared"}: ${sent.url}`);
    console.log(`"${words.name}"${words.by ? ` by ${words.by}` : ""}: ${sent.files} files, ${(sent.bytes / 1_000_000).toFixed(1)} MB packed, ${shape === "fill" ? "filling the window" : "on its own stage"}${sent.picture ? ", with a picture of it" : ", with no picture"}.`);
    console.log("Anyone with the link can play it and send an idea: lamp ideas shows them. lamp unshare takes it down.");
    return;
  }

  if (command === "unshare") {
    const { rest } = parse(args, []);
    console.log(`Taken down: ${await unshare(layoutOf(rest[0] ?? ".").folder)}`);
    return;
  }

  if (command === "ideas") {
    const { rest } = parse(args, []);
    const outcomes = ["in", "dismiss"];
    const folder = rest.length && !outcomes.includes(rest[0]) ? rest.shift() : ".";
    const layout = layoutOf(folder);
    if (rest.length) {
      const n = Number(rest[1]);
      if (!outcomes.includes(rest[0]) || !Number.isInteger(n) || n < 1) throw new Problem("ideas takes in <number> or dismiss <number>: lamp ideas lists them with their numbers");
      const answer = await finishIdea(layout.folder, n, rest[0] === "in");
      console.log(rest[0] === "in" ? `Idea ${n} is in.${answer.notified ? " Whoever sent it asked to hear, and has been written to." : ""}` : `Idea ${n} is let go.`);
      return;
    }
    const sent = await ideas(layout.folder);
    if (!sent.ideas.length) { console.log(`No ideas waiting for ${sent.url}`); return; }
    console.log(`Ideas sent to ${sent.url}`);
    for (const idea of sent.ideas) {
      console.log(`  ${idea.n}. ${String(idea.text).split("\n").join("\n     ")}${idea.wantsNews ? "  (wants to hear when it's in)" : ""}`);
    }
    console.log("Say what became of one with: lamp ideas in <number>, or lamp ideas dismiss <number>.");
    return;
  }

  if (command === "remove") {
    const { options, rest } = parse(args, ["on"]);
    if (options.on === undefined) throw new Problem("remove takes the device to take it off: lamp remove --on xbox");
    const place = await placeNamed(options.on, { command: lampCommand() });
    console.log((await place.remove(layoutOf(rest[0] ?? "."))) ? `Taken off ${place.name}.` : `lamp hasn't put this on ${place.name}.`);
    return;
  }

  if (command === "devices") return await devices(args);

  if (command === "reload" || command === "stop") {
    const { options, rest } = parse(args, ["on"]);
    if (options.on !== undefined) {
      if (command !== "stop") throw new Problem("a change goes on a device by putting the page there again: lamp open --on " + options.on);
      const place = await placeNamed(options.on, { command: lampCommand() });
      console.log((await place.stop(layoutOf(rest[0] ?? "."))) ? `Stopped on ${place.name}.` : `lamp hasn't put this on ${place.name}.`);
      return;
    }
    const layout = projectOf(rest[0] ?? ".");
    const live = await running(layout.folder);
    if (!live) { console.log("lamp dev isn't running for this folder."); return; }
    const answer = await ask(live, command, { fresh: !!options.fresh });
    // Stopped means gone: the next command finds no server, never one on its way out.
    if (command === "stop") for (let tries = 0; tries < 50 && (await running(layout.folder)); tries++) await sleep(100);
    console.log(command === "stop" ? "Stopped." : answer.pages ? (layout.kind === "mac" ? "The app is opening again." : "The page is opening again.") : "Nothing is open.");
    return;
  }

  if (command === "guide") {
    // The skill without what only a skill's file needs in front.
    console.log(skillText().replace(/^---\n[\s\S]*?\n---\n+/, "").trimEnd());
    return;
  }

  if (command === "blocks") {
    // Lamp's building blocks for a Mac app, read from the app's own copy of them (Sources/LampSupport.swift), whose
    // comments are the whole of how each is used: every one with what it's for, or one in full.
    const { rest } = parse(args, []);
    const name = rest.find((word) => /^Lamp\w*$/.test(word)) ?? null;
    const project = projectOf(rest.find((word) => word !== name) ?? ".");
    const file = join(project.folder, "Sources", "LampSupport.swift");
    if (!existsSync(file)) throw new Problem("Lamp's building blocks are a Mac app's (Sources/LampSupport.swift): this folder has none");
    const lines = readFileSync(file, "utf8").split("\n");
    const declared = /^ {4}(?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:public|final|nonisolated|indirect)\s+)*(enum|struct|class|actor|protocol)\s+(Lamp\w+)/;
    const blocks = new Map();
    lines.forEach((line, at) => {
      const found = declared.exec(line);
      if (!found || blocks.has(found[2])) return;
      let above = at - 1;
      while (above >= 0 && /^ {4}@/.test(lines[above])) above--;
      const says = [];
      for (; above >= 0 && /^ {4}\/\/\//.test(lines[above]); above--) says.unshift(lines[above].replace(/^ {4}\/\/\/ ?/, ""));
      blocks.set(found[2], { at, says });
    });
    // What a block offers, by name: its members that aren't its own alone.
    const offers = (block) => {
      const names = [];
      for (let at = block.at + 1; at < lines.length && !/^ {4}\}/.test(lines[at]); at++) {
        const member = /^ {8}(?:@[\w.]+(?:\([^)]*\))?\s+)*((?:(?:static|public|private|fileprivate|nonisolated|mutating|final)(?:\(set\))?\s+)*)(?:func|var|let)\s+(\w+)/.exec(lines[at]);
        if (member && !/private/.test(member[1]) && !names.includes(member[2])) names.push(member[2]);
      }
      return names;
    };
    if (!name) {
      for (const [block, entry] of blocks) {
        // What it's for, where its comment says; else what it offers, which says as much.
        const first = entry.says.join(" ").split(/(?<=[.:])\s/)[0];
        const said = entry.says.length ? first : (() => { const names = offers(entry); return names.length ? `${names.slice(0, 8).join(", ")}${names.length > 8 ? "…" : ""}` : ""; })();
        if (said) console.log(`${block}: ${said.length > 150 ? said.slice(0, 150).replace(/\s+\S*$/, "") + "…" : said}`);
      }
      console.log(`\n${lampCommand()} blocks <Name> says how one is used.`);
      return;
    }
    const block = blocks.get(name);
    if (!block) throw new Problem(`there's no building block called ${name}: lamp blocks lists them`);
    console.log(`${name}  (Sources/LampSupport.swift:${block.at + 1})\n${block.says.length ? `\n${block.says.join("\n")}\n` : ""}`);
    // What it offers: each member's own comment and how it's written, without what's inside it or what's its own alone.
    for (let at = block.at + 1; at < lines.length && !/^ {4}\}/.test(lines[at]); at++) {
      const line = lines[at];
      if (/^ {8}\/\/\//.test(line)) { console.log(line.slice(4)); continue; }
      const member = /^ {8}((?:@[\w.]+(?:\([^)]*\))?\s+)*(?:(?:static|public|nonisolated|mutating|final|indirect|convenience)\s+)*(?:func|var|let|init|case|enum|struct|class|subscript|typealias)\b.*)$/.exec(line);
      if (member && !/\b(private|fileprivate)\b/.test(member[1])) console.log("    " + member[1].replace(/\s*\{.*$/, ""));
    }
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

// Whatever a command did on Android, its adb server isn't left holding the person's devices (android.mjs).
main().finally(() => androidDone().catch(() => {})).catch((error) => {
  if (error instanceof Problem) fail(error.message);
  throw error;
});
