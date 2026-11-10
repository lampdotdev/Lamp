// `lamp play <code>`: the helper on the player's Mac for a shared game's page on lamp.dev (lamp.dev/change?w=<id>,
// site/RELAY.md) that lets the player's own agent change the game. It trades the page's short code for a credential of
// its own, takes a copy of the game into a folder of lamp's, and asks lamp.dev every couple of seconds for what the page
// wants, running one change at a time with the agent confined to that copy. After a run that worked, the copy's files
// go straight to lamp.dev's file store and lamp.dev checks them and moves the game to them in one step; after one that
// didn't, the copy goes back to the version the page plays and nothing is sent.
//
// Only static games: nothing of the game's is ever run here, no build and no install, and the agent has no shell.

import { spawn } from "node:child_process";
import { createHash } from "node:crypto";

import { appendFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { Problem } from "./state.mjs";
import { TOKEN_SHAPES } from "./lampapp.mjs";
import { TOOLS } from "./play-guard.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const GUARD = join(HERE, "play-guard.mjs");

/** Where the page and the helper meet: lamp.dev, or with LAMP_RELAY another (a dev server: http://localhost:4321). */
export const RELAY = (process.env.LAMP_RELAY || "https://lamp.dev").replace(/\/+$/, "");

/** What a version sent back may hold: what lamp.dev takes (`RELAY_LIMITS`). */
export const BUILD_LIMITS = { files: 3000, file: 16_000_000, total: 64_000_000 };

/** How long one change may take. */
const RUN_MS = 10 * 60_000;

// Files an agent keeps for itself, or reads as instructions, that never go into the copy it works in nor back out.
const AGENT_FILES = new Set(["CLAUDE.md", "CLAUDE.local.md", "AGENTS.md", "AGENTS.override.md", "GEMINI.md", "node_modules"]);
const skipped = (name) => name.startsWith(".") || AGENT_FILES.has(name);

// MARK: The agents

/**
 * How each agent is run on the copy, behind one interface: the command, its arguments and its environment. Claude
 * Code is tried; Codex is wired the same way and hasn't been run.
 */
export const AGENTS = {
  claude: ({ folder, prompt, guardLog }) => ({
    command: process.env.LAMP_PLAY_CLAUDE || "claude",
    args: [
      "-p", prompt,
      // No tools that run anything, and no settings, hooks or MCP servers but ours: restricted mode ignores user,
      // project and local settings, and confines the file tools to the working folder.
      "--restricted", "--strict-mcp-config", "--disable-slash-commands", "--no-session-persistence",
      "--tools", Object.keys(TOOLS).join(","),
      "--permission-mode", "acceptEdits", "--permission-prompts", "none",
      "--settings", JSON.stringify({ hooks: { PreToolUse: [{ matcher: "*", hooks: [{ type: "command", command: `"${process.execPath}" "${GUARD}"` }] }] } }),
      "--append-system-prompt", SYSTEM,
      "--output-format", "stream-json", "--verbose",
    ],
    env: { LAMP_PLAY_FOLDER: folder, LAMP_PLAY_GUARD_LOG: guardLog },
  }),
  // UNTESTED. Codex's workspace-write sandbox keeps writes and commands in the folder with the network off, but it
  // still reads anywhere on the Mac, and its network setting doesn't cover every tool an MCP server could add.
  codex: ({ folder, prompt }) => ({
    command: process.env.LAMP_PLAY_CODEX || "codex",
    args: [
      "exec", "--sandbox", "workspace-write", "--skip-git-repo-check", "-C", folder,
      "-c", "sandbox_workspace_write.network_access=false", "-c", "mcp_servers={}",
      `${SYSTEM}\n\n${prompt}`,
    ],
    env: {},
  }),
};

const SYSTEM = "You are changing a static web game: the files in the current folder, which a browser plays as they are. " +
  "Change only files in this folder. There is no build step, nothing to install and nothing to run: write plain HTML, CSS " +
  "and JavaScript the browser takes as is. Make the change asked for and nothing else.";

// MARK: The copy

/** The game's files as the site takes a page: nothing hidden, none of an agent's, no link, within the limits. */
export function packed(folder, limits = BUILD_LIMITS) {
  const files = [];
  let total = 0;
  const walk = (dir, prefix) => {
    for (const name of readdirSync(dir).sort()) {
      if (skipped(name)) continue;
      const path = join(dir, name), stat = lstatSync(path);
      if (stat.isSymbolicLink()) throw new Problem(`${prefix}${name} is a link, and a game sent back holds only its own files`);
      if (stat.isDirectory()) { walk(path, `${prefix}${name}/`); continue; }
      if (!stat.isFile()) continue;
      total += stat.size;
      if (files.length >= limits.files || total > limits.total) throw new Problem(`the game is more than ${limits.files} files or ${limits.total / 1_000_000} MB`);
      if (stat.size > limits.file) throw new Problem(`${prefix}${name} is more than ${limits.file / 1_000_000} MB`);
      files.push([prefix + name, readFileSync(path)]);
    }
  };
  walk(folder, "");
  if (!files.some(([path]) => path === "index.html")) throw new Problem("the game has no index.html at its top");
  const leak = files.find(([, bytes]) => TOKEN_SHAPES.some((shape) => shape.test(bytes.toString("utf8"))));
  if (leak) throw new Problem(`${leak[0]} holds something shaped like a key, which never goes back to the page`);
  return { files };
}

/** Puts a version's files in the folder in place of what's there. Paths come checked from the relay; checked again. */
function restore(folder, files) {
  rmSync(folder, { recursive: true, force: true });
  mkdirSync(folder, { recursive: true });
  for (const [path, bytes] of files) {
    if (!path || path.startsWith("/") || path.includes("\\") || path.split("/").some((part) => part === ".." || part === "." || part === "" || skipped(part))) continue;
    mkdirSync(dirname(join(folder, path)), { recursive: true });
    writeFileSync(join(folder, path), bytes);
  }
}

const sameFiles = (a, b) => a.length === b.length && a.every(([path, bytes], n) => b[n][0] === path && b[n][1].equals(bytes));

// MARK: The helper

const sha256 = (bytes) => createHash("sha256").update(bytes).digest("hex");
const sleep = (ms) => new Promise((done) => setTimeout(done, ms));
const loopback = (origin) => ["localhost", "127.0.0.1", "[::1]"].includes(new URL(origin).hostname);

/**
 * Pairs with the page by its code (or with `rejoin`, takes up a room this Mac paired with before, with the credential it
 * kept), then does what the page asks until the room ends.
 */
export async function play({ code, rejoin = null, relay = RELAY, agent = "claude", yes = false, home = process.env.LAMP_PLAY_HOME || join(homedir(), ".lamp", "play"), say = console.log }) {
  if (!AGENTS[agent]) throw new Problem(`lamp play runs claude or codex, not ${agent}`);
  // Codex reads anywhere on the Mac, so it's only for trying a relay on this computer, never lamp.dev's.
  if (agent === "codex" && !loopback(relay)) throw new Problem("lamp play runs Claude Code for a game on lamp.dev: Codex can read files outside the game's copy");
  if (!code && !rejoin) throw new Problem("lamp play takes the code the game's page shows: lamp play ABC234");

  const call = async (method, op, { body, token, query = "" } = {}) => {
    const response = await fetch(`${relay}/api/relay?op=${op}${query}`, {
      method, signal: AbortSignal.timeout(30_000),
      headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { "Content-Type": "application/json" } : {}) },
      body: body ? JSON.stringify(body) : undefined,
    });
    if (op === "file") { if (!response.ok) throw new Problem(`a file of the game didn't come (${response.status})`); return Buffer.from(await response.arrayBuffer()); }
    const answer = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(new Problem(answer.error ?? `HTTP ${response.status}`), { status: response.status });
    return answer;
  };

  let room, token;
  if (rejoin) {
    try { ({ room, token } = JSON.parse(readFileSync(join(home, rejoin, "helper.json"), "utf8"))); } catch { throw new Problem(`this Mac hasn't paired with room ${rejoin}`); }
  } else {
    if (!yes) {
      if (!process.stdin.isTTY) throw new Problem("lamp play asks before it lets a page use your agent: run it in a terminal, or with --yes");
      const asking = createInterface({ input: process.stdin, output: process.stdout });
      const answer = await asking.question(`The game's page will be able to ask ${agent === "claude" ? "Claude Code" : "Codex"} on this Mac to change a copy of the game.\n` +
        `It works only on that copy, in ${home}, with no shell and no web. Go ahead? [y/N] `);
      asking.close();
      if (!/^y(es)?$/i.test(answer.trim())) throw new Problem("Not paired.");
    }
    try { ({ room, token } = await call("POST", "pair", { body: { code } })); }
    catch (error) { throw new Problem(error.status === 404 ? "That code doesn't work: it may have been used or run out. The page can show a new one." : error.status === 429 ? "Too many tries: wait a minute." : `lamp.dev didn't pair: ${error.message}`); }
  }
  const place = join(home, room), folder = join(place, "game"), logFile = join(place, "log.txt"), journalFile = join(place, "journal.json"), guardLog = join(place, "refused.txt");
  mkdirSync(place, { recursive: true, mode: 0o700 });
  // Kept so this Mac can take the room up again (`--rejoin`), readable only by its user, never in the game's copy.
  writeFileSync(join(place, "helper.json"), JSON.stringify({ relay, room, token }), { mode: 0o600 });
  const log = (line) => { const stamped = `${new Date().toISOString().slice(11, 23)} ${line}`; say(stamped); appendFileSync(logFile, stamped + "\n"); };
  log(`${rejoin ? "Back in" : "Paired with"} room ${room}. Changes the page asks for run here with ${agent}, in ${folder}.`);

  // What this helper took and how each ended. A change it was running when it stopped is never run again: lamp.dev
  // hears it didn't finish, and says so.
  const journal = existsSync(journalFile) ? JSON.parse(readFileSync(journalFile, "utf8")) : {};
  const remember = (id, entry) => { journal[id] = { ...journal[id], ...entry }; writeFileSync(journalFile, JSON.stringify(journal, null, 2)); };
  for (const [id, entry] of Object.entries(journal)) if (entry.state === "running") remember(id, { state: "interrupted" });
  const reconcile = async () => {
    const answer = await call("POST", "reconcile", { token, body: { journal: Object.fromEntries(Object.entries(journal).map(([id, entry]) => [id, entry.state])) } });
    for (const request of answer.requests) {
      const mine = journal[request.id];
      if (mine && mine.state !== request.state && ["done", "failed", "unchanged", "uncertain"].includes(request.state)) {
        if (mine.state === "interrupted") log(`request ${request.id}: it stopped while it ran, and lamp.dev has it as ${request.state}; not run again`);
        remember(request.id, { state: request.state, version: request.version });
      }
    }
    return answer.version;
  };

  // The version the page plays, which the copy is and goes back to.
  let version = await reconcile(), published = [];
  const fetchVersion = async (wanted) => {
    const list = await call("GET", "files", { token, query: `&v=${wanted}` });
    const files = [];
    for (const file of list.files) {
      const bytes = await call("GET", "file", { token, query: `&v=${wanted}&path=${encodeURIComponent(file.path)}` });
      if (file.sha256 && sha256(bytes) !== file.sha256) throw new Problem(`${file.path} didn't come as it was sent`);
      files.push([file.path, bytes]);
    }
    return files.sort(([a], [b]) => a.localeCompare(b));
  };
  published = await fetchVersion(version);
  restore(folder, published);
  log(`Version ${version} of the game: ${published.length} files.`);

  const run = async ({ id, prompt }) => {
    try { await call("POST", "claim", { token, body: { id } }); }
    catch (error) { if (error.status === 409) return; throw error; }
    remember(id, { state: "running", prompt, at: new Date().toISOString() });
    log(`request ${id}: running ${agent}: ${JSON.stringify(prompt)}`);
    restore(folder, published);
    const outcome = await runAgent({ agent, folder, prompt, guardLog, log: (line) => log(`request ${id}: ${line}`) });
    let failure = outcome.ok ? null : outcome.why, result = null;
    if (!failure) { try { result = packed(folder); } catch (error) { failure = error.message; } }
    const finish = async (state, message) => {
      restore(folder, published);
      remember(id, { state, message });
      log(`request ${id}: ${state}${message ? ` (${message})` : ""}; the game stays at version ${version}`);
      await call("POST", "finish", { token, body: { id, state, message } });
    };
    if (failure) return finish("failed", failure);
    if (sameFiles(result.files, published)) return finish("unchanged", "the agent changed nothing");
    // The files go straight to lamp.dev's file store, each with the permission it gave for that one file; lamp.dev then
    // reads each back, checks it against the list, and only then plays the new version.
    try {
      const listed = result.files.map(([path, bytes]) => ({ path, size: bytes.length, sha256: sha256(bytes) }));
      const { build, uploads } = await call("POST", "upload", { token, body: { id, files: listed } });
      const bytesOf = new Map(result.files.map(([, bytes]) => [sha256(bytes), bytes]));
      for (const upload of uploads) {
        const response = await fetch(upload.url, { method: "PUT", headers: upload.headers, body: bytesOf.get(upload.sha256), signal: AbortSignal.timeout(120_000) });
        if (!response.ok) throw new Problem(`a file wasn't taken (${response.status})`);
      }
      const done = await call("POST", "commit", { token, body: { id, build } });
      published = result.files;
      version = done.version;
      remember(id, { state: "done", version });
      log(`request ${id}: published version ${version} (${result.files.length} files, ${uploads.length} sent)`);
    } catch (error) {
      await finish("failed", `the new version wasn't taken: ${error.message}`).catch(() => {});
    }
  };

  // Every two seconds while there's something to do, and less often, up to every fifteen, while there isn't.
  for (let quiet = 0, lost = false; ;) {
    try {
      if (lost) { version = await reconcile(); lost = false; log("lamp.dev answers again."); }
      const next = await call("GET", "next", { token });
      if (next.version !== version && !next.running) {
        published = await fetchVersion(next.version);
        version = next.version;
        restore(folder, published);
      }
      if (next.next && !journal[next.next.id]) { quiet = 0; await run(next.next); continue; }
      quiet++;
    } catch (error) {
      if (error.status === 401 || error.status === 404) { log("The room has closed."); return; }
      if (!lost) log(`lamp.dev didn't answer (${error.message}); trying again.`);
      lost = true;
    }
    await sleep(Math.min(15_000, 2000 * 2 ** Math.min(3, Math.floor(quiet / 10))));
  }
}

/** Runs the agent once on the copy: whether it finished, and why not when it didn't. */
function runAgent({ agent, folder, prompt, guardLog, log }) {
  const { command, args, env } = AGENTS[agent]({ folder, prompt, guardLog });
  return new Promise((done) => {
    let child;
    try { child = spawn(command, args, { cwd: folder, env: { ...process.env, ...env }, stdio: ["ignore", "pipe", "pipe"] }); }
    catch (error) { done({ ok: false, why: `${command} didn't start: ${error.message}` }); return; }
    const timer = setTimeout(() => { child.kill(); }, RUN_MS);
    let buffer = "", result = null, stderr = "";
    child.stdout.on("data", (part) => {
      buffer += part;
      let end;
      while ((end = buffer.indexOf("\n")) >= 0) {
        const line = buffer.slice(0, end); buffer = buffer.slice(end + 1);
        let message;
        try { message = JSON.parse(line); } catch { if (line.trim()) log(line.slice(0, 300)); continue; }
        // What the agent does, a line each: its tools and their targets, and its last word.
        if (message.type === "assistant") {
          for (const block of message.message?.content ?? []) {
            if (block.type === "tool_use") log(`${block.name} ${JSON.stringify(block.input).slice(0, 200)}`);
          }
        } else if (message.type === "user") {
          for (const block of message.message?.content ?? []) {
            if (block.type === "tool_result" && block.is_error) log(`  refused or failed: ${String(Array.isArray(block.content) ? block.content.map((c) => c.text ?? "").join(" ") : block.content).slice(0, 200)}`);
          }
        } else if (message.type === "result") {
          result = message;
          log(`agent: ${String(message.result ?? "").replace(/\s+/g, " ").slice(0, 300)}`);
        }
      }
    });
    child.stderr.on("data", (part) => { stderr += part; });
    child.on("error", (error) => { clearTimeout(timer); done({ ok: false, why: `${command} didn't start: ${error.message}` }); });
    child.on("close", (status, signal) => {
      clearTimeout(timer);
      if (signal) done({ ok: false, why: `the agent was stopped (${signal})` });
      else if (status !== 0 || result?.is_error) done({ ok: false, why: `the agent ended with ${status}${stderr.trim() ? `: ${stderr.trim().slice(0, 200)}` : ""}` });
      else done({ ok: true });
    });
  });
}


