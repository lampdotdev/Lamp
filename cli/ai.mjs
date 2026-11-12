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
import { decidePrompt, planPrompt, planSchema, readDecision, readPlan, readStep } from "./app-ai.mjs";


/** Which of the person's programs answers: `LAMP_AI` (claude or codex) when it's set, else Claude Code, else Codex. */
export function engine() {
  const wanted = process.env.LAMP_AI;
  for (const name of wanted ? [wanted] : ["claude", "codex"]) {
    if (name !== "claude" && name !== "codex") continue;
    try { execFileSync("/usr/bin/which", [name], { stdio: ["ignore", "pipe", "ignore"] }); return name; } catch {}
  }
  return null;
}

const missing = "AI here needs Claude Code or Codex on this Mac, signed in: install one, or open the app in Lamp.";
const named = (which) => (which === "codex" ? "Codex" : "Claude Code");

/** One answer from the engine: text, or JSON fitting `schema`. Nothing to run, no files, no session kept. */
export function complete({ system, prompt, schema, seconds = 60, which = engine() }) {
  if (which !== "claude" && which !== "codex") return Promise.reject(new Error(missing));
  const folder = mkdtempSync(join(tmpdir(), "lamp-ai-"));
  const sayer = system || "You are a helpful assistant inside an app.";
  let args;
  if (which === "claude") {
    // Sealed as Lamp's app seals it (`AppAI.viaEngine`): none of the person's settings or hooks (--restricted), no MCP,
    // no tools.
    args = ["-p", prompt, "--output-format", "stream-json", "--verbose", "--no-session-persistence", "--restricted", "--strict-mcp-config",
      "--disable-slash-commands", "--tools", "", "--system-prompt", sayer];
    if (process.env.LAMP_AI_MODEL) args.push("--model", process.env.LAMP_AI_MODEL);
    if (schema) args.push("--json-schema", JSON.stringify(schema));
  } else {
    // Sealed as Lamp's app seals it: read-only, none of the person's config, rules or hooks, and none of its tools. Its
    // picture tool reads any file on the Mac: `features.view_image` turns it off now, `tools.view_image` did before
    // (each version ignores the other's, with a warning). What's left, checked with Codex 0.167.1, is asking the person
    // a question, which a run with no one to ask can't use.
    args = ["exec", "--json", "--ignore-user-config", "--ignore-rules", "--skip-git-repo-check", "--ephemeral", "-s", "read-only",
      "-c", "hooks={}", "-c", 'model_reasoning_effort="low"', "-c", 'approval_policy="never"',
      "-c", "features.shell_tool=false", "-c", "features.unified_exec=false", "-c", 'web_search="disabled"',
      "-c", "features.apps=false", "-c", "features.multi_agent=false", "-c", "features.view_image=false",
      "-c", "tools.view_image=false", "-c", "features.goals=false",
      "-c", `developer_instructions=${JSON.stringify(sayer + "\n\nAnswer directly. Don't run commands or change files.")}`];
    if (process.env.LAMP_AI_MODEL) args.push("-m", process.env.LAMP_AI_MODEL);
    if (schema) { writeFileSync(join(folder, "schema.json"), JSON.stringify(schema)); args.push("--output-schema", "schema.json"); }
    args.push("--", prompt);
  }
  return new Promise((resolve, reject) => {
    const child = spawn(which, args, { cwd: folder, stdio: ["ignore", "pipe", "pipe"] });
    let text = "", failure = null, rest = "", said = "";
    const timer = setTimeout(() => { failure = `${named(which)} took too long to answer.`; child.kill("SIGKILL"); }, seconds * 1000);
    const line = (raw) => {
      let event;
      try { event = JSON.parse(raw); } catch { return; }
      if (which === "codex") {
        if (event.type === "item.completed" && event.item?.type === "agent_message" && typeof event.item.text === "string") text = event.item.text;
        else if (event.type === "turn.failed" || event.type === "error") failure = String(event.error?.message || event.message || "Codex couldn't answer.");
        return;
      }
      if (event.type !== "result") return;
      if (event.is_error) failure = String(event.result || "Claude Code couldn't answer.");
      else if (schema && event.structured_output !== undefined) text = JSON.stringify(event.structured_output);
      else if (typeof event.result === "string") text = event.result;
    };
    child.stdout.on("data", (chunk) => {
      rest += chunk;
      const lines = rest.split("\n");
      rest = lines.pop();
      lines.forEach(line);
    });
    child.stderr.on("data", (chunk) => { said = (said + chunk).slice(-400); });
    child.on("error", () => { clearTimeout(timer); rmSync(folder, { recursive: true, force: true }); reject(new Error(missing)); });
    child.on("close", () => {
      clearTimeout(timer);
      if (rest) line(rest);
      rmSync(folder, { recursive: true, force: true });
      if (failure) return reject(new Error(failure));
      if (!text) return reject(new Error(`${named(which)} didn't answer. Check it's signed in.${said.trim() ? ` ${said.trim().split("\n").pop()}` : ""}`));
      resolve(text);
    });
  });
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
  if (Array.isArray(body.images) && body.images.length) return [501, { error: "Pictures go to the AI through Lamp's app: open the app in Lamp." }];
  let system = typeof body.system === "string" ? body.system : "";
  if (body.json) system += (system ? "\n\n" : "") + "Answer with JSON only, nothing around it.";
  try { return [200, { text: await complete({ system, prompt }) }]; }
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
  const seconds = 60;
  const deadline = Date.now() + Math.min(r.seconds, seconds) * 1000;
  const tag = "outside-text-" + randomBytes(4).toString("hex");
  let retry = null;
  for (let attempt = 0; attempt < 2; attempt++) {
    const left = (deadline - Date.now()) / 1000;
    if (left < 1) return [504, { error: "This step ran out of time." }];
    const { system, prompt } = planPrompt(r, tag, retry);
    let text;
    try { text = await complete({ system, prompt, schema: planSchema(r), seconds: left, which }); }
    catch (error) { return Date.now() >= deadline ? [504, { error: "This step ran out of time." }] : [502, { error: error.message }]; }
    const read = readPlan(text, r);
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
