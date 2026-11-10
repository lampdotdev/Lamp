// PROTOTYPE. `lamp play <code>`: the helper on the player's Mac for a game's page that lets the player's own agent
// change the game (the relay, `site/relay/relay.mjs`, is the other end). It trades the page's short code for a secret
// of its own, takes a copy of the game into a folder of lamp's, and runs each change the page asks for, one at a time,
// with the agent confined to that copy. After a run that worked, the copy is packed as the site packs a page and sent
// back as one new version; after one that didn't, the copy goes back to the last version sent and the game in the
// page stays as it was.
//
// Only static games: nothing of the game's is ever run here, no build and no install, and the agent has no shell.

import { spawn } from "node:child_process";

import { appendFileSync, existsSync, lstatSync, mkdirSync, readdirSync, readFileSync, rmSync, writeFileSync } from "node:fs";
import { homedir } from "node:os";
import { dirname, join } from "node:path";
import { createInterface } from "node:readline/promises";
import { fileURLToPath } from "node:url";
import { Problem } from "./state.mjs";
import { zipOf } from "./share.mjs";
import { TOKEN_SHAPES } from "./lampapp.mjs";
import { TOOLS } from "./play-guard.mjs";

const HERE = dirname(fileURLToPath(import.meta.url));
const GUARD = join(HERE, "play-guard.mjs");

/** The prototype's relay, until there's one on the web. */
export const RELAY = process.env.LAMP_RELAY || "http://127.0.0.1:4700";

/** What a build sent back may hold: the site's page limits, lowered to what the relay keeps in memory. */
export const BUILD_LIMITS = { files: 3000, total: 64_000_000, packed: 32_000_000 };

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
      files.push([prefix + name, readFileSync(path)]);
    }
  };
  walk(folder, "");
  if (!files.some(([path]) => path === "index.html")) throw new Problem("the game has no index.html at its top");
  const leak = files.find(([, bytes]) => TOKEN_SHAPES.some((shape) => shape.test(bytes.toString("utf8"))));
  if (leak) throw new Problem(`${leak[0]} holds something shaped like a key, which never goes back to the page`);
  const zip = zipOf(files);
  if (zip.length > limits.packed) throw new Problem(`the game is ${(zip.length / 1_000_000).toFixed(1)} MB packed, more than ${limits.packed / 1_000_000} MB`);
  return { files, zip };
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

export async function play({ code, relay = RELAY, agent = "claude", yes = false, home = process.env.LAMP_PLAY_HOME || join(homedir(), ".lamp", "play"), say = console.log }) {
  if (!AGENTS[agent]) throw new Problem(`lamp play runs claude or codex, not ${agent}`);
  if (!code) throw new Problem("lamp play takes the code the game's page shows: lamp play ABC234");
  if (!yes) {
    if (!process.stdin.isTTY) throw new Problem("lamp play asks before it lets a page use your agent: run it in a terminal, or with --yes");
    const asking = createInterface({ input: process.stdin, output: process.stdout });
    const answer = await asking.question(`The game's page will be able to ask ${agent === "claude" ? "Claude Code" : "Codex"} on this Mac to change a copy of the game.\n` +
      `It works only on that copy, in ${home}, with no shell and no web. Go ahead? [y/N] `);
    asking.close();
    if (!/^y(es)?$/i.test(answer.trim())) throw new Problem("Not paired.");
  }

  const call = async (method, path, { body, secret, raw } = {}) => {
    const response = await fetch(new URL(path, relay), {
      method, headers: { ...(secret ? { Authorization: `Bearer ${secret}` } : {}), ...(body && !raw ? { "Content-Type": "application/json" } : {}) },
      body: raw ? body : body ? JSON.stringify(body) : undefined,
    });
    const answer = await response.json().catch(() => ({}));
    if (!response.ok) throw Object.assign(new Problem(answer.error ?? `HTTP ${response.status}`), { status: response.status });
    return answer;
  };

  let paired;
  try { paired = await call("POST", "/api/pair", { body: { code } }); }
  catch (error) { throw new Problem(error.status === 404 ? "That code doesn't work: it may have been used or run out. The page can show a new one." : error.status === 429 ? "Too many tries: wait a minute." : `The relay didn't pair: ${error.message}`); }
  const { room, secret } = paired;
  const place = join(home, room), folder = join(place, "game"), logFile = join(place, "log.txt"), journalFile = join(place, "journal.json"), guardLog = join(place, "refused.txt");
  mkdirSync(place, { recursive: true, mode: 0o700 });
  const log = (line) => { const stamped = `${new Date().toISOString().slice(11, 23)} ${line}`; say(stamped); appendFileSync(logFile, stamped + "\n"); };
  log(`Paired with room ${room}. Changes the page asks for run here with ${agent}, in ${folder}.`);

  // The version last sent, which the copy goes back to when a run fails.
  const built = await call("GET", "/api/helper/build", { secret });
  let published = Object.entries(built.files).map(([path, data]) => [path, Buffer.from(data, "base64")]).sort(([a], [b]) => a.localeCompare(b));
  let version = built.version;
  restore(folder, published);
  log(`Version ${version} of the game: ${published.length} files.`);

  // Which requests this helper has taken and how each ended, so one sent again (a reconnect) is answered, not run again.
  const journal = existsSync(journalFile) ? JSON.parse(readFileSync(journalFile, "utf8")) : {};
  const remember = (id, entry) => { journal[id] = { ...journal[id], ...entry }; writeFileSync(journalFile, JSON.stringify(journal, null, 2)); };

  const queue = [];
  let working = false;
  const take = (request) => {
    if (queue.some((queued) => queued.id === request.id)) return;
    queue.push(request);
    if (!working) next();
  };
  const next = async () => {
    working = true;
    while (queue.length) {
      const request = queue.shift();
      try { await handle(request); } catch (error) { log(`request ${request.id}: ${error.message}`); }
    }
    working = false;
  };

  const handle = async ({ id, prompt }) => {
    const known = journal[id];
    if (known?.state === "done") { log(`request ${id}: already published as version ${known.version}; not run again`); return; }
    if (known?.state === "failed" || known?.state === "unchanged") { await call("POST", "/api/helper/status", { secret, body: { id, state: known.state, message: known.message } }); return; }
    if (known?.state === "started") {
      // Started before the helper stopped: never run twice, so it's told as not done.
      remember(id, { state: "failed", message: "the helper stopped while it ran" });
      await call("POST", "/api/helper/status", { secret, body: { id, state: "failed", message: "the helper stopped while it ran" } });
      return;
    }
    remember(id, { state: "started", prompt, at: new Date().toISOString() });
    await call("POST", "/api/helper/status", { secret, body: { id, state: "running" } });
    log(`request ${id}: running ${agent}: ${JSON.stringify(prompt)}`);
    restore(folder, published);
    const outcome = await runAgent({ agent, folder, prompt, guardLog, log: (line) => log(`request ${id}: ${line}`) });
    let failure = outcome.ok ? null : outcome.why;
    let result = null;
    if (!failure) { try { result = packed(folder); } catch (error) { failure = error.message; } }
    if (failure) {
      restore(folder, published);
      remember(id, { state: "failed", message: failure });
      log(`request ${id}: failed (${failure}); the game stays at version ${version}`);
      await call("POST", "/api/helper/status", { secret, body: { id, state: "failed", message: failure } });
      return;
    }
    if (sameFiles(result.files, published)) {
      remember(id, { state: "unchanged", message: "the agent changed nothing" });
      log(`request ${id}: the agent changed nothing`);
      await call("POST", "/api/helper/status", { secret, body: { id, state: "unchanged", message: "the agent changed nothing" } });
      return;
    }
    const answer = await call("PUT", `/api/helper/build?request=${encodeURIComponent(id)}&base=${version}`, { secret, body: result.zip, raw: true });
    published = result.files;
    version = answer.version;
    remember(id, { state: "done", version });
    log(`request ${id}: published version ${version} (${result.files.length} files, ${result.zip.length} bytes packed)`);
  };

  // The relay's stream of requests, opened again when it drops; the relay sends again what isn't finished.
  for (let wait = 1000; ;) {
    try {
      const response = await fetch(new URL("/api/helper/events", relay), { headers: { Authorization: `Bearer ${secret}` } });
      if (response.status === 401) throw new Problem("The relay no longer knows this helper.");
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      log("Listening for the page's requests.");
      wait = 1000;
      const decoder = new TextDecoder();
      let buffer = "";
      for await (const part of response.body) {
        buffer += decoder.decode(part, { stream: true });
        let end;
        while ((end = buffer.indexOf("\n\n")) >= 0) {
          const block = buffer.slice(0, end); buffer = buffer.slice(end + 2);
          const lines = block.split("\n").filter((line) => !line.startsWith(":"));
          const event = lines.find((line) => line.startsWith("event:"))?.slice(6).trim();
          const data = lines.find((line) => line.startsWith("data:"))?.slice(5).trim();
          if (event === "request" && data) take(JSON.parse(data));
        }
      }
    } catch (error) {
      if (error instanceof Problem) throw error;
    }
    log("The relay went away; connecting again.");
    await new Promise((done) => setTimeout(done, wait));
    wait = Math.min(wait * 2, 30_000);
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


