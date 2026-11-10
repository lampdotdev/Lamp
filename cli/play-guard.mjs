// PROTOTYPE. The check Claude Code runs before each tool when `lamp play` has it change a game (a PreToolUse hook,
// given with --settings): only the file tools, and only on paths inside the game's folder, links resolved. Claude's
// own restricted mode confines its file tools to the folder too; this holds it to that whatever Claude's defaults
// become, and writes each refusal to the helper's log.
//
// Read as a hook: the tool call as JSON on stdin; the folder in LAMP_PLAY_FOLDER, the log in LAMP_PLAY_GUARD_LOG.

import { appendFileSync, existsSync, readFileSync, realpathSync } from "node:fs";
import { dirname, isAbsolute, relative, resolve, sep } from "node:path";
import { fileURLToPath } from "node:url";

/** The tools the agent has (`--tools`), each with the inputs that name a path. */
export const TOOLS = { Read: ["file_path"], Edit: ["file_path"], Write: ["file_path"], Glob: ["path", "pattern"], Grep: ["path", "glob"] };

/** Where a path really is: the nearest part of it that exists with its links resolved, and the rest after it. */
function realPath(path) {
  let existing = path;
  const rest = [];
  while (!existsSync(existing)) {
    const up = dirname(existing);
    if (up === existing) break;
    rest.unshift(existing.slice(up.length + (up.endsWith(sep) ? 0 : 1)));
    existing = up;
  }
  return resolve(realpathSync(existing), ...rest);
}

const inside = (folder, path) => { const from = relative(folder, path); return from === "" || (!from.startsWith("..") && !isAbsolute(from)); };

/** Null when the call may go ahead, else why not. */
export function verdict(folder, call) {
  const real = realpathSync(folder);
  const fields = TOOLS[call?.tool_name];
  if (!fields) return `${call?.tool_name ?? "this tool"} isn't one of the file tools a game's change may use`;
  for (const field of fields) {
    const value = call.tool_input?.[field];
    if (value === undefined || value === null || value === "") continue;
    if (typeof value !== "string") return `${field} isn't a path`;
    // A pattern is matched under the folder: one that starts elsewhere or steps up could match outside it.
    if (field === "pattern" || field === "glob") {
      if (isAbsolute(value) || value.startsWith("~") || value.split(/[\\/]/).includes("..")) return `${field} ${value} reaches outside the game's folder`;
      continue;
    }
    if (value.startsWith("~")) return `${value} is outside the game's folder`;
    if (!inside(real, realPath(resolve(real, value)))) return `${value} is outside the game's folder`;
  }
  return null;
}

if (process.argv[1] && resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const folder = process.env.LAMP_PLAY_FOLDER;
  let call = null;
  try { call = JSON.parse(readFileSync(0, "utf8")); } catch {}
  let why;
  try { why = folder ? verdict(folder, call) : "no game folder was given"; } catch (error) { why = `the check failed: ${error.message}`; }
  if (why) {
    try { if (process.env.LAMP_PLAY_GUARD_LOG) appendFileSync(process.env.LAMP_PLAY_GUARD_LOG, `${new Date().toISOString()} refused ${call?.tool_name} ${JSON.stringify(call?.tool_input ?? {})}: ${why}\n`); } catch {}
    process.stdout.write(JSON.stringify({ hookSpecificOutput: { hookEventName: "PreToolUse", permissionDecision: "deny", permissionDecisionReason: why } }));
  }
  process.exit(0);
}
