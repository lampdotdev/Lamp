// The AI a page asks for with LampAI (lamp.js), answered by lamp itself for the pages it serves, with the person's own
// Claude Code or Codex on this Mac: their subscription, through the program they signed in to, never a key in the page.
// The same routes and answers Lamp's app gives (`/ai/status`, `/ai/models`, `/ai`, `/ai/act`, `/ai/decide`), told and checked by the
// same code (app-ai.mjs, which Lamp's app has do it too), so a page can't tell which answered it. Pictures and
// hearing need Lamp's app: asked here, they say so.

import { spawn } from "node:child_process";
import { accessSync, constants, mkdtempSync, rmSync, statSync, writeFileSync } from "node:fs";
import { tmpdir } from "node:os";
import { delimiter, join } from "node:path";
import { randomBytes } from "node:crypto";
import { chatBody, decidePrompt, planPrompt, planSchema, readDecision, readMessage, readPlan, readStep } from "./app-ai.mjs";
import { DEFAULT_MODEL, OpenRouterTrouble, chat as openRouterChat, text as openRouterText } from "./openrouter.mjs";


/**
 * What answers: `LAMP_AI` (claude, codex or openrouter) when it's set, else Claude Code, else Codex, else OpenRouter with
 * the person's key in OPENROUTER_API_KEY.
 */
export function engine() {
  return engines()[0] ?? null;
}

/** Every engine that can answer here, what answers first: only `LAMP_AI`'s when it's set. */
export function engines() {
  const wanted = process.env.LAMP_AI;
  return (wanted ? [wanted] : ["claude", "codex", "openrouter"]).filter((name) => {
    if (name === "openrouter") return !!process.env.OPENROUTER_API_KEY;
    if (name !== "claude" && name !== "codex") return false;
    return !!onPath(name);
  });
}

/** Where a program is on the PATH this process has now, looked up here rather than by asking `which`, whose answer
 *  can differ from this process's own PATH under Bun. */
function onPath(name) {
  for (const folder of String(process.env.PATH || "").split(delimiter)) {
    if (!folder) continue;
    const path = join(folder, name);
    try { accessSync(path, constants.X_OK); if (statSync(path).isFile()) return path; } catch {}
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
    const child = spawn(tool || onPath(which) || which, args, { cwd: folder, env: childEnv, detached: true, stdio: [input ? "pipe" : "ignore", "pipe", "pipe"] });
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

// MARK: Models (`LampAI.models`, and `model` on `ask` and `act`)

/** The models a page may name here, by Lamp's ids for them (`AppAI.anthropicModels` in Lamp's app, the same strings), with
 *  what OpenRouter calls each. Claude Code takes the ids as they are. */
const APP_MODELS = [
  { id: "claude-fable-5-2", name: "Claude Fable", openRouter: "anthropic/claude-fable-5.2" },
  { id: "opus", name: "Claude Opus", openRouter: "anthropic/claude-opus-5.5" },
  { id: "sonnet", name: "Claude Sonnet", openRouter: DEFAULT_MODEL },
  { id: "haiku", name: "Claude Haiku", openRouter: "anthropic/claude-haiku-5.5" },
];
/** Codex's models aren't known here without running it, so it's offered as one choice, by the id Lamp's app gives it then. */
const CODEX = "engine:codex";

/** How a page names a model through each engine, as Lamp's app does (`TextRoute.appID`), and what answers it
 *  (`via`). A bare id ("opus") is that model through the engine that answers first. */
const PREFIX = { claude: "engine:claude:", codex: CODEX, openrouter: "openrouter:" };
const via = (which) => ({ id: which === "claude" ? "claude-code" : which, name: named(which) });

/** One of the listed models by its bare id. */
const listed = (asked) => APP_MODELS.find((m) => m.id === String(asked || ""));

/** A model `LAMP_AI_MODEL` names that isn't one of Lamp's: what a page naming none gets from the engine that answers
 *  first, so it's listed too. */
function unlisted() {
  const wanted = process.env.LAMP_AI_MODEL || "";
  return wanted && !APP_MODELS.some((m) => m.id === wanted || m.openRouter === wanted) ? wanted : "";
}

/** The model's id a page gets when it names none: `LAMP_AI_MODEL` when it names one, else Sonnet, as Lamp's app
 *  answers apps (never Haiku unasked), through the engine that answers first. */
function defaultId(which) {
  if (which === "codex") return CODEX;
  const wanted = process.env.LAMP_AI_MODEL || "";
  const model = unlisted() || (APP_MODELS.find((m) => m.id === wanted || m.openRouter === wanted) ?? listed("sonnet")).id;
  return PREFIX[which] + model;
}

/** What `complete` is told to run on `which` for a bare model id: an unknown one is answered as one that named none,
 *  never refused. A `LAMP_AI_MODEL` that isn't listed still answers what names none, as before. */
export function modelFor(which, asked) {
  const model = listed(asked);
  if (which === "codex") return process.env.LAMP_AI_MODEL || "";
  if (model) return which === "openrouter" ? model.openRouter : model.id;
  if (process.env.LAMP_AI_MODEL) return process.env.LAMP_AI_MODEL;
  return which === "openrouter" ? DEFAULT_MODEL : "sonnet";
}

/** The engine and model a page's `model` goes to (`ask` and `act`): an id with its engine ("engine:claude:opus",
 *  "openrouter:opus", "engine:codex") is that engine when it can answer here; a bare id ("opus") is that model through
 *  the engine that answers first. One that can't answer is answered as one that named none, never refused: a model
 *  this doesn't list included, and any Codex model but its default, since Codex's own list isn't known here.
 *  `here` is the engines the page may use (`enginesFor`). */
export function routeFor(asked, here = engines()) {
  const first = here[0] ?? null;
  const id = String(asked || "");
  for (const which of here) {
    if (which === "codex") {
      if (id === CODEX) return { which, model: which === first ? process.env.LAMP_AI_MODEL || "" : "" };
      continue;
    }
    if (!id.startsWith(PREFIX[which])) continue;
    const model = id.slice(PREFIX[which].length);
    if (listed(model)) return { which, model: modelFor(which, model) };
    if (which === first && model === unlisted()) return { which, model };
    break;
  }
  const bare = id.includes(":") ? "" : id;
  return { which: first, model: first ? modelFor(first, bare) : "" };
}

/** The engines a request may use: every one here for the person's own page (`lamp dev`), only the one that answers
 *  first for a page shared on lamp.dev (`page`, from `serveLocalAI`), the one the person was asked to let it use. */
export const enginesFor = (page) => (page ? engines().slice(0, 1) : engines());

/** `/ai/models`: what a page can offer to choose from here, asked of nothing. The engine that answers first comes
 *  first, then the others, each with its most capable model first. */
export function models(here = engines()) {
  if (!here.length) return { models: [], default: null, reason: missing };
  const list = here.flatMap((which) => {
    if (which === "codex") return [{ id: CODEX, name: "ChatGPT's default model via Codex", model: "ChatGPT's default model", via: via(which), available: true }];
    const one = (id, model) => ({ id: PREFIX[which] + id, name: `${model} via ${named(which)}`, model, via: via(which), available: true });
    // A model LAMP_AI_MODEL names that isn't one of Lamp's is what a page naming none gets: it's offered too, first,
    // so choosing the default answers the same as choosing nothing.
    const extra = which === here[0] && unlisted() ? [one(unlisted(), unlisted())] : [];
    return [...extra, ...APP_MODELS.map((m) => one(m.id, m.name))];
  });
  return { models: list, default: defaultId(here[0]) };
}

/**
 * How long a page's request may take: a real answer is never cut off however long the model takes, and the guard only
 * ends a call that has stopped answering (`MAX_TURN_SECONDS` for a step of `act`, the same here). A page that wants a
 * quicker answer asks for one (`seconds`), never a longer one.
 */
const GUARD_SECONDS = 600;
const secondsFor = (body) => (typeof body?.seconds === "number" && body.seconds > 0 ? Math.min(body.seconds, GUARD_SECONDS) : GUARD_SECONDS);

/** `/ai`: a text answer, or JSON when asked for it. */
export async function ask(body, here = engines()) {
  const prompt = typeof body?.prompt === "string" ? body.prompt.trim() : "";
  if (!prompt) return [400, { error: "Missing prompt." }];
  let system = typeof body.system === "string" ? body.system : "";
  if (body.json) system += (system ? "\n\n" : "") + "Answer with JSON only, nothing around it.";
  const { which, model } = routeFor(body.model, here);
  try { return [200, { text: await complete({ system, prompt, images: body.images, which, model, seconds: secondsFor(body) }) }]; }
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
  try { text = await complete({ system, prompt, schema, seconds: secondsFor(body) }); } catch (error) { return [502, { error: error.message }]; }
  const read = readDecision(text, questions);
  return read.answers ? [200, { answers: read.answers }] : [502, { error: read.problem }];
}

// MARK: Actions (`LampAI.act`)

/** `/ai/act`: one step of the page's agent loop, told and checked as Lamp's app does it (app-ai.mjs). */
export async function act(body, here = engines()) {
  const first = here[0] ?? null;
  if (body?.probe === true) return [200, { act: !!first, route: first || "", why: first ? "" : missing }];
  if (!first) return [501, { error: missing }];
  let r;
  try { r = readStep(JSON.stringify(body ?? null)); } catch (refused) { return [refused.status ?? 400, { error: refused.message }]; }
  // The model the page named, through its own engine when that can answer here; else what answers first.
  const { which, model } = routeFor(r.model, here);
  // A step's guard against a call that has stopped answering, as Lamp's app gives it (`AppAct.turnSeconds`).
  const seconds = 600;
  const deadline = Date.now() + Math.min(r.seconds, seconds) * 1000;
  const tag = "outside-text-" + randomBytes(4).toString("hex");
  let retry = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    const left = (deadline - Date.now()) / 1000;
    if (left < 1) return [504, { error: "This step ran out of time." }];
    let read;
    try {
      if (which === "openrouter") {
        const body = chatBody(r, tag, retry, model);
        read = readMessage((await openRouterChat({ key: process.env.OPENROUTER_API_KEY, body, seconds: left })).message, r);
      } else {
        const { system, prompt } = planPrompt(r, tag, retry);
        read = readPlan(await complete({ system, prompt, schema: planSchema(r), seconds: left, which, model }), r);
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
export async function answer(path, body, page) {
  if (path === "/ai/status") return [200, status()];
  if (path === "/ai/models") return [200, models(enginesFor(page))];
  if (path === "/ai") return ask(body, enginesFor(page));
  if (path === "/ai/act") return act(body, enginesFor(page));
  if (path === "/ai/decide") return decide(body);
  if (path === "/ai/hear") return body?.probe === true ? [200, { hear: false, why: "Hearing needs Lamp's app." }] : [501, { error: "Hearing needs Lamp's app: open the app in Lamp." }];
  if (path === "/ai/image") return [501, { error: "Pictures need Lamp's app: open the app in Lamp.", needs: "pictures" }];
  return [404, { error: "Not found." }];
}
