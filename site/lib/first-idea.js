import { isIP } from "node:net";
import { SHAPES, SITUATIONS, TYPED } from "./situations.js";
import { redis, reserve } from "./quota.js";

// The model that asks the follow-up and writes the request, through OpenRouter. Set FIRST_IDEA_MODEL in
// Vercel to try another (any OpenRouter id) without a code change.
export const DEFAULT_MODEL = "anthropic/claude-sonnet-5.5";
export const modelFor = (env) => (env.FIRST_IDEA_MODEL || "").trim() || DEFAULT_MODEL;

// A conversation is two or three calls. Per visitor, enough for several goes in an hour; overall, a ceiling
// on what a flood could cost in a day.
export const QUOTAS = [
  { name: "ip", perIP: true, limit: 30, seconds: 3600 },
  { name: "hour", limit: 1500, seconds: 3600 },
  { name: "day", limit: 9000, seconds: 86400 },
];

export const MAX_BODY_BYTES = 8192;
const LIMITS = { words: TYPED.words, answer: TYPED.answer, question: 300, turns: 3, passed: 16 };

export const RULES = `You are Lamp, talking with someone on Lamp's website. Lamp is a Mac app that builds apps for people who have never programmed: they describe what they want in a sentence or two and Lamp makes it. They just told you about something that happens to them a lot. Ask very little, then write the request they'll paste into Lamp to make an app that does it for them.

What a Lamp app can do: read their Mail, Calendar, Reminders and Contacts; draft emails that open in Mail for them to send (never send by itself); add events and reminders; watch a folder and act on new files; read text from PDFs, screenshots and photos; keep what they copy; fetch public web pages; use AI to read, sort, summarize and write; show notifications; open with a keyboard shortcut from any app; open at login and keep working in the background. Sites they must sign in to are reachable only by operating the browser, which is slow: prefer email, files, calendar and public pages. Anything that changes or moves things asks first.

People think of apps by the shape they take, so every request names one. Choose by what they'll do with it, and don't default to the menu bar:
- A desktop widget: when the point is to see something at a glance without opening anything (a page that changes, what's due, who hasn't replied, a count or a status). A widget only shows: clicking it opens its app. When they also need to add, tick off or change things, it's "A Mac app with a desktop widget that…", the app for the doing and the widget for the glance.
- A menu bar app: when they need to act on it quickly from anywhere, all day (add something in two seconds, run something on demand, a timer, something working quietly in the background that taps them with a notification).
- A Mac app: when there's real work in a window (going through a list, dropping files in, reading, editing, a history to look back on).
- An iPhone app: when it happens away from the desk (snapping a photo, where they are, a quick tap on the go).
If two would suit them equally and it would change what they get, one of your questions can be where they'd want it, with plain options like "At a glance on my desktop", "One click away in the menu bar", "On my phone".

How to talk:
- Like a friend who's handy with computers. Short, casual, plain. No praise, no exclamation marks, no technical words (automate, API, script, workflow, integration).
- Ask at most two questions in total; usually one is enough. Each question asks one thing, never two joined with "and" or "or".
- Give 2 to 4 short likely answers in their voice. They can also type.
- As soon as you could write something specific, write it. When in doubt, write it: they can edit it.
- Stay on this topic. If they ask for something unrelated, steer back to what their Mac could do for them.

The request is what they'll type into Lamp, so it reads like a person asking for an app, not a spec:
- It starts with the shape: "A desktop widget that shows…", "A menu bar app that…", "A Mac app that…", "An iPhone app that…".
- First person, plain words, two to four sentences, about 40 to 80 words.
- It says what the app works on, what it shows or does, and when, using the specifics they gave you (which folder, which site, whose emails, how often).
- It does what they asked and nothing more: no extra features they didn't mention. At most one small touch that follows from what they said, and often none.
- If it changes, moves, sends or deletes anything, it asks first.
- One paragraph of plain text: no name or title, no lists, no line breaks, no parentheses, no markup, no technical words.
- "lead" is one short sentence from you introducing it, like "Here's your wish. Change anything you like."

Reply with "kind" set to "question" (fill "question" and "options", leave "lead" and "request" empty) or "request" (fill "lead" and "request", leave "question" empty and "options" empty).`;

const SCHEMA = {
  type: "object",
  additionalProperties: false,
  required: ["kind", "question", "options", "lead", "request"],
  properties: {
    kind: { type: "string", enum: ["question", "request"] },
    question: { type: "string" },
    options: { type: "array", items: { type: "string" } },
    lead: { type: "string" },
    request: { type: "string" },
  },
};

const reply = (status, body, headers = {}) => Response.json(body, {
  status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers },
});

const text = (value, max) => (typeof value === "string" && value.trim() && value.length <= max ? value.trim() : null);

/** What the visitor sent, checked: a known situation or their own words, the situations they passed over,
 *  and at most three short question-and-answer turns. Null when anything is off. */
export function readConversation(body) {
  if (!body || typeof body !== "object" || Array.isArray(body)) return null;
  const situation = body.situation == null ? null : (Object.hasOwn(SITUATIONS, body.situation) ? body.situation : undefined);
  const words = body.words == null ? null : text(body.words, LIMITS.words);
  if (situation === undefined || words === undefined || (!situation) === (!words)) return null;
  if (body.words != null && !words) return null;
  const passed = body.passed ?? [];
  if (!Array.isArray(passed) || passed.length > LIMITS.passed || !passed.every((id) => Object.hasOwn(SITUATIONS, id))) return null;
  const turns = body.turns ?? [];
  if (!Array.isArray(turns) || turns.length > LIMITS.turns) return null;
  const checked = turns.map((t) => t && typeof t === "object" && { q: text(t.q, LIMITS.question), a: text(t.a, LIMITS.answer) });
  if (!checked.every((t) => t && t.q && t.a)) return null;
  return { situation, words, passed: [...new Set(passed)].filter((id) => id !== situation), turns: checked };
}

/** The visitor's side of the conversation. The rules stay in the system message, which nothing a visitor
 *  sends can change. */
export function buildPrompt({ situation, words, passed, turns }) {
  const lines = [];
  if (situation) lines.push(`You showed them a few everyday situations and they picked this one: "${SITUATIONS[situation].text}" (${SHAPES[SITUATIONS[situation].shape]})`);
  else lines.push(`They said, in their own words: "${words}"`);
  if (passed.length) {
    lines.push("", "Situations they passed over, so these are less likely to be what they need:");
    for (const id of passed) lines.push(`- ${SITUATIONS[id].text}`);
  }
  lines.push("", turns.length ? "So far:" : "Nothing asked yet.");
  for (const t of turns) lines.push(`You: ${t.q}`, `They: ${t.a}`);
  if (turns.length >= 2) lines.push("", "You know enough: write the request now.");
  return lines.join("\n");
}

export async function askModel(conversation, env, fetcher = fetch) {
  const key = env.OPENROUTER_API_KEY;
  if (!key) throw new Error("Model unavailable");
  const body = JSON.stringify({
    model: modelFor(env),
    messages: [{ role: "system", content: RULES }, { role: "user", content: buildPrompt(conversation) }],
    response_format: { type: "json_schema", json_schema: { name: "answer", strict: true, schema: SCHEMA } },
    reasoning: { effort: "low" },
    max_tokens: 4000,
  });
  // A provider's safety filter now and then refuses an ordinary request at random; asking again gets the answer.
  for (let attempt = 0; attempt < 2; attempt++) {
    const response = await fetcher("https://openrouter.ai/api/v1/chat/completions", {
      method: "POST", redirect: "error", signal: AbortSignal.timeout(25000),
      headers: { Authorization: `Bearer ${key}`, "Content-Type": "application/json", "HTTP-Referer": "https://lamp.dev", "X-Title": "Lamp website" },
      body,
    });
    if (!response.ok) throw new Error(`Model failed: ${response.status}`);
    const choice = (await response.json()).choices?.[0];
    if (choice?.finish_reason === "content_filter") continue;
    const answer = JSON.parse(choice?.message?.content ?? "");
    const turns = conversation.turns.length;
    if (answer.kind === "request" && plain(answer.request)) {
      return { lead: plain(answer.lead).slice(0, 200), request: plain(answer.request).slice(0, 1200) };
    }
    if (answer.kind === "question" && answer.question?.trim() && turns < 2) {
      const options = (Array.isArray(answer.options) ? answer.options : []).filter((o) => typeof o === "string" && o.trim()).slice(0, 4);
      return { question: answer.question.trim().slice(0, 300), options: options.map((o) => o.trim().slice(0, 80)) };
    }
    throw new Error("Model answer unusable");
  }
  throw new Error("Model filtered");
}

/** The model's words as one paragraph of plain text: now and then a reply carries a stray tag, a bracket left
 *  over from the JSON around it, or a last sentence on a line of its own in parentheses. */
export function plain(text) {
  return String(text ?? "")
    .replace(/<[^>]*>/g, " ")
    .replace(/\s*\n+\s*\(([^)]*)\)\s*$/, " $1")
    .replace(/\s+/g, " ")
    .replace(/[\s{}\[\]]+$/, "")
    .trim();
}

async function readBody(request) {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_BODY_BYTES)) throw new RangeError();
  const raw = await request.text();
  if (Buffer.byteLength(raw) > MAX_BODY_BYTES) throw new RangeError();
  return JSON.parse(raw);
}

// `limited: false` is only for the local dev server (astro.config.mjs), which has no Upstash to count in.
export function createIdeaHandler({ env = process.env, fetcher = fetch, limited = true } = {}) {
  return async (request) => {
    if (request.method !== "POST") return reply(405, { error: "method_not_allowed" }, { Allow: "POST" });
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) return reply(403, { error: "origin_not_allowed" });
    if (!/^application\/json(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") || "")) return reply(415, { error: "json_required" });
    let conversation;
    try { conversation = readConversation(await readBody(request)); }
    catch (error) { return reply(error instanceof RangeError ? 413 : 400, { error: "invalid_request" }); }
    if (!conversation) return reply(400, { error: "invalid_request" });

    if (limited) {
      // Vercel overwrites these headers with the client IP. Do not place another untrusted proxy in front.
      const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
      if (!isIP(ip)) return reply(503, { error: "service_unavailable" });
      let retry;
      try { retry = await reserve(redis(env), ip, QUOTAS, fetcher); }
      catch { return reply(503, { error: "service_unavailable" }); }
      if (retry > 0) return reply(429, { error: "rate_limited" }, { "Retry-After": String(retry) });
    }
    try { return reply(200, await askModel(conversation, env, fetcher)); }
    catch { return reply(502, { error: "model_failed" }); }
  };
}
