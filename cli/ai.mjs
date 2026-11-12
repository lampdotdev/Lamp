// The AI a page asks for with LampAI (lamp.js), answered by lamp itself for the pages it serves, with the person's own
// Claude Code or Codex on this Mac: their subscription, through the program they signed in to, never a key in the page.
// The same routes and answers Lamp's app gives (`/ai/status`, `/ai`, `/ai/act`, `/ai/decide`), told and checked by the
// same code (app-ai.mjs, which Lamp's app has do it too), so a page can't tell which answered it. Pictures and
// hearing need Lamp's app: asked here, they say so.

import { spawn, execFileSync } from "node:child_process";
import { mkdtempSync, rmSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import { randomBytes } from "node:crypto";
import { chatBody, decidePrompt, planPrompt, planSchema, readDecision, readMessage, readPlan, readStep } from "./app-ai.mjs";
import { DEFAULT_MODEL, OpenRouterTrouble, chat as openRouterChat, text as openRouterText } from "./openrouter.mjs";


/**
 * What answers: `LAMP_AI` (claude, codex or openrouter) when it's set, else Claude Code, else Codex, else OpenRouter with
 * the person's key in OPENROUTER_API_KEY.
 */
export function engine() {
  const wanted = process.env.LAMP_AI;
  for (const name of wanted ? [wanted] : ["claude", "codex", "openrouter"]) {
    if (name === "openrouter") { if (process.env.OPENROUTER_API_KEY) return name; continue; }
    if (name !== "claude" && name !== "codex") continue;
    try { execFileSync("/usr/bin/which", [name], { stdio: ["ignore", "pipe", "ignore"] }); return name; } catch {}
  }
  return null;
}

const missing = "AI here needs Claude Code or Codex on this computer, signed in, or an OpenRouter key in OPENROUTER_API_KEY. Or open the app in Lamp.";
const named = (which) => (which === "codex" ? "Codex" : which === "openrouter" ? "OpenRouter" : "Claude Code");

/** Why an engine gave no answer: `kind` is "missing", "timeout", "stopped", "failed" (its own words) or "silent". */
export class EngineTrouble extends Error {
  constructor(kind, message) { super(message); this.kind = kind; }
}

/**
 * One answer from Claude Code or Codex, the person's own sign-in: text, or JSON fitting `schema`. Every run is sealed:
 * none of the person's settings, rules, hooks or MCP servers, and none of the engine's tools, so nothing of the
 * computer is read or run whatever the prompt asks. Pictures (`images`, base64 with their `media_type`) go with the
 * request itself: to Claude Code in its input, to Codex as attachments, never through a tool that reads files.
 * Lamp's app runs it this way too (`engineAnswer` in calls.mjs, `AppAI.viaEngine`), naming the program (`tool`) and
 * what it needs set (`env`); on its own lamp finds the person's own on the PATH.
 */
export function complete({ system, prompt, schema, seconds = 60, which = engine(), tool, env = {}, model = process.env.LAMP_AI_MODEL || "", images = [], signal } = {}) {
  if (which === "openrouter") return viaOpenRouter({ system, prompt, schema, seconds, model, images, signal });
  if (which !== "claude" && which !== "codex") return Promise.reject(new EngineTrouble("missing", missing));
  const folder = mkdtempSync(join(tmpdir(), "lamp-ai-"));
  const sayer = system || "You are a helpful assistant inside an app.";
  const pictures = (Array.isArray(images) ? images : []).filter((image) => typeof image?.data === "string" && image.data);
  let args, input = null;
  if (which === "claude") {
    // None of the person's settings or hooks (--restricted), no MCP, no tools. With pictures, the prompt and the pictures
    // go in on its input as one message, which it takes in stream-json.
    args = ["-p", ...(pictures.length ? [] : [prompt]), "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--restricted",
      "--strict-mcp-config", "--disable-slash-commands", "--tools", "", "--system-prompt", sayer];
    if (model) args.push("--model", model);
    if (schema) args.push("--json-schema", JSON.stringify(schema));
    if (pictures.length) {
      args.push("--input-format", "stream-json");
      const content = [{ type: "text", text: prompt }, ...pictures.map((image) => ({ type: "image",
        source: { type: "base64", media_type: String(image.media_type || "image/jpeg"), data: image.data } }))];
      input = JSON.stringify({ type: "user", message: { role: "user", content } }) + "\n";
    }
  } else {
    // Read-only, none of the person's config, rules or hooks, and none of its tools. Its picture tool reads any file on
    // the computer: `features.view_image` turns it off now, `tools.view_image` did before (each version ignores the
    // other's, with a warning); pictures given with `-i` are part of the request, not that tool. What's left, checked
    // with Codex 0.167.1, is asking the person a question, which a run with no one to ask can't use.
    args = ["exec", "--json", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
      "-c", "hooks={}", "-c", 'model_reasoning_effort="low"', "-c", 'approval_policy="never"',
      "-c", "features.shell_tool=false", "-c", "features.unified_exec=false", "-c", 'web_search="disabled"',
      "-c", "features.apps=false", "-c", "features.multi_agent=false", "-c", "features.view_image=false",
      "-c", "tools.view_image=false", "-c", "features.goals=false",
      "-c", `developer_instructions=${JSON.stringify(sayer + "\n\nAnswer directly. Don't run commands or change files.")}`];
    if (model) args.push("-m", model);
    if (schema) { writeFileSync(join(folder, "schema.json"), JSON.stringify(schema)); args.push("--output-schema", "schema.json"); }
    pictures.forEach((image, i) => {
      const name = `image${i}.${String(image.media_type).endsWith("png") ? "png" : "jpg"}`;
      writeFileSync(join(folder, name), Buffer.from(image.data, "base64"));
      args.push("-i", name);
    });
    args.push("--", prompt);
  }
  // Run on Lamp's own runtime, lamp is Bun told to be itself; the engine is never told so, or Claude Code, which is
  // built on Bun, would be Bun too.
  const childEnv = { ...process.env, ...env };
  delete childEnv.BUN_BE_BUN;
  return new Promise((resolve, reject) => {
    const child = spawn(tool || which, args, { cwd: folder, env: childEnv, detached: true, stdio: [input ? "pipe" : "ignore", "pipe", "pipe"] });
    let text = "", trouble = null, rest = "", said = "";
    // The whole group, since an engine may leave a child holding its output.
    const stop = (kind, words) => { if (!trouble) trouble = new EngineTrouble(kind, words); try { process.kill(-child.pid, "SIGKILL"); } catch { child.kill("SIGKILL"); } };
    const timer = setTimeout(() => stop("timeout", `${named(which)} took too long to answer.`), Math.max(1, seconds) * 1000);
    const stopped = () => stop("stopped", "Stopped.");
    if (signal?.aborted) stopped(); else signal?.addEventListener("abort", stopped);
    const line = (raw) => {
      let event;
      try { event = JSON.parse(raw); } catch { return; }
      if (which === "codex") {
        if (event.type === "item.completed" && event.item?.type === "agent_message" && typeof event.item.text === "string") text = event.item.text;
        else if (event.type === "turn.failed" || event.type === "error") {
          // Codex nests the service's error as JSON text: its message is what's said.
          const words = String(event.message || event.error?.message || "Codex couldn't answer.");
          let nested;
          try { nested = JSON.parse(words)?.error?.message; } catch {}
          trouble ??= new EngineTrouble("failed", nested || words);
        }
        return;
      }
      if (event.type !== "result") return;
      if (event.is_error) trouble ??= new EngineTrouble("failed", String(event.result || "Claude Code couldn't answer."));
      else if (schema && event.structured_output !== undefined) text = JSON.stringify(event.structured_output);
      else if (typeof event.result === "string") text = event.result;
    };
    // Read as text across chunks, so a character split between two of them stays whole.
    child.stdout.setEncoding("utf8");
    child.stderr.setEncoding("utf8");
    child.stdout.on("data", (chunk) => {
      rest += chunk;
      const lines = rest.split("\n");
      rest = lines.pop();
      lines.forEach(line);
    });
    child.stderr.on("data", (chunk) => { said = (said + chunk).slice(-400); });
    if (input) { child.stdin.on("error", () => {}); child.stdin.end(input); }
    const done = () => { clearTimeout(timer); signal?.removeEventListener("abort", stopped); rmSync(folder, { recursive: true, force: true }); };
    child.on("error", () => { done(); reject(new EngineTrouble("missing", missing)); });
    child.on("close", () => {
      done();
      if (rest) line(rest);
      if (trouble) return reject(trouble);
      if (!text) return reject(new EngineTrouble("silent", `${named(which)} didn't answer. Check it's signed in.${said.trim() ? ` ${said.trim().split("\n").pop()}` : ""}`));
      resolve(text);
    });
  });
}

/** An answer from OpenRouter with the person's key (openrouter.mjs, as Lamp's app sends it), its troubles said as an engine's. */
async function viaOpenRouter({ system, prompt, schema, seconds, model, images, signal }) {
  try {
    return (await openRouterText({ key: process.env.OPENROUTER_API_KEY, prompt, images, system: system || "You are a helpful assistant inside an app.",
      model: model || DEFAULT_MODEL, json: !!schema, schema, seconds, signal })).text;
  } catch (error) {
    if (!(error instanceof OpenRouterTrouble)) throw error;
    const words = error.reply?.error?.message;
    throw new EngineTrouble(error.kind === "refused" ? "failed" : error.kind, words ? String(words) : error.message);
  }
}

// MARK: Status and asking

/** `/ai/status`: what can answer here. Text, decisions and actions with an engine; pictures only in Lamp's app. */
export function status() {
  const which = engine();
  const route = which ? named(which) : null;
  const available = (kind) => route ? { available: true, route, where: "remote" } : { available: false, reason: missing, setup: "lamp" };
  return {
    text: !!route, decisions: !!route, pictures: false, act: !!route,
    details: { text: available("text"), decisions: available("decisions"), act: available("act"),
      pictures: { available: false, reason: "Pictures need Lamp's app: open the app in Lamp.", setup: "lamp" } },
  };
}

/** `/ai`: a text answer, or JSON when asked for it. */
export async function ask(body) {
  const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt) return [400, { error: "Missing prompt." }];
  let system = typeof body.system === "string" ? body.system : "";
  if (body.json) system += (system ? "\n\n" : "") + "Answer with JSON only, nothing around it.";
  try { return [200, { text: await complete({ system, prompt, images: body.images }) }]; }
  catch (error) { return [502, { error: error.message }]; }
}

// MARK: Decisions

/** `/ai/decide`: each question answered by a text model, told and read as Lamp's app does it (app-ai.mjs). */
export async function decide(body) {
  const questions = body?.questions;
  if (body?.state === undefined || !questions || typeof questions !== "object" || Array.isArray(questions) || !Object.keys(questions).length) {
    return [400, { error: "A decision needs `state` and at least one question." }];
  }
  const { system, prompt, schema } = decidePrompt(body.state, questions);
  let text;
  try { text = await complete({ system, prompt, schema }); } catch (error) { return [502, { error: error.message }]; }
  const read = readDecision(text, questions);
  return read.answers ? [200, { answers: read.answers }] : [502, { error: read.problem }];
}

// MARK: Actions (`LampAI.act`)

/** `/ai/act`: one step of the page's agent loop, told and checked as Lamp's app does it (app-ai.mjs). */
export async function act(body) {
  const which = engine();
  if (body?.probe === true) return [200, { act: !!which, route: which || "", why: which ? "" : missing }];
  if (!which) return [501, { error: missing }];
  let r;
  try { r = readStep(JSON.stringify(body ?? null)); } catch (refused) { return [refused.status ?? 400, { error: refused.message }]; }
  const seconds = which === "openrouter" ? 25 : 60;
  const deadline = Date.now() + Math.min(r.seconds, seconds) * 1000;
  const tag = "outside-text-" + randomBytes(4).toString("hex");
  let retry = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    const left = (deadline - Date.now()) / 1000;
    if (left < 1) return [504, { error: "This step ran out of time." }];
    let read;
    try {
      if (which === "openrouter") {
        const body = chatBody(r, tag, retry, process.env.LAMP_AI_MODEL || DEFAULT_MODEL);
        read = readMessage((await openRouterChat({ key: process.env.OPENROUTER_API_KEY, body, seconds: left })).message, r);
      } else {
        const { system, prompt } = planPrompt(r, tag, retry);
        read = readPlan(await complete({ system, prompt, schema: planSchema(r), seconds: left, which }), r);
      }
    } catch (error) {
      const words = error?.reply?.error?.message || error.message;
      return Date.now() >= deadline || error?.kind === "timeout" ? [504, { error: "This step ran out of time." }] : [502, { error: String(words) }];
    }
    if (read.answer) return [200, { ...read.answer, route: which, seconds }];
    if (attempt === 0) { retry = read.problem; continue; }
    return [200, { reply: "I couldn't work out how to do that.", ask: false, route: which, seconds, trouble: read.problem }];
  }
  return [502, { error: "The AI didn't answer." }];
}

/** A page's AI request, by its route, as Lamp's app answers it: [status, JSON]. */
export async function answer(path, body) {
  if (path === "/ai/status") return [200, status()];
  if (path === "/ai") return ask(body);
  if (path === "/ai/act") return act(body);
  if (path === "/ai/decide") return decide(body);
  if (path === "/ai/hear") return body?.probe === true ? [200, { hear: false, why: "Hearing needs Lamp's app." }] : [501, { error: "Hearing needs Lamp's app: open the app in Lamp." }];
  if (path === "/ai/image") return [501, { error: "Pictures need Lamp's app: open the app in Lamp.", needs: "pictures" }];
  return [404, { error: "Not found." }];
}
