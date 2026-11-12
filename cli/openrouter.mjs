// An app's AI asked of OpenRouter with the person's own key: the one place it's sent, for Lamp's app (`openRouterText`,
// `openRouterChat`, `openRouterDecide` and `openRouterImage` in calls.mjs; `AppAI.viaOpenRouter`, `AppAct.openRouterStep`,
// `AppAI.decide` and `AppAI.image`) and for lamp's own answers
// (ai.mjs, with OPENROUTER_API_KEY). The key comes with each request and is kept nowhere here.

const ENDPOINT = "https://openrouter.ai/api/v1/chat/completions";
/** The model lamp answers with when none is named: the one Lamp's app offers first for apps' text. */
export const DEFAULT_MODEL = "anthropic/claude-sonnet-5.5";
const FILTERED = "The AI provider's content filter cut the reply off. Try rewording the request.";

/** Why OpenRouter gave no answer: `kind` "refused" (with its `status` and `reply`), "filtered", "timeout" or "stopped". */
export class OpenRouterTrouble extends Error {
  constructor(kind, message, { status = 0, reply = {}, cost = 0 } = {}) {
    super(message);
    Object.assign(this, { kind, status, reply, cost });
  }
}

/**
 * A request for text: the prompt with its pictures (base64, with their `media_type`) and the system prompt. With
 * `json` the answer must be a JSON object, with room for a long one (a cut-off reply is what breaks apps), and with a
 * `schema` it must fit it too.
 */
export function textBody({ prompt, images = [], system = "", model = DEFAULT_MODEL, json = false, schema } = {}) {
  const messages = [];
  if (String(system).trim()) messages.push({ role: "system", content: system });
  messages.push({ role: "user", content: [{ type: "text", text: prompt },
    ...(Array.isArray(images) ? images : []).filter((image) => image?.data).map((image) => ({ type: "image_url", image_url: { url: `data:${image.media_type || "image/jpeg"};base64,${image.data}` } }))] });
  const body = { model, messages, usage: { include: true } };
  if (json) {
    body.response_format = schema ? { type: "json_schema", json_schema: { name: "answer", strict: true, schema } } : { type: "json_object" };
    body.max_tokens = 16000;
  }
  return body;
}

/**
 * One chat completion: `{message, cost}`, the model's message as OpenRouter gives it (its text, or its tool calls) and
 * what it cost. A provider's safety filter sometimes refuses an ordinary request at random (finish_reason
 * "content_filter", an empty reply, HTTP 200), so it's asked again, twice at most, within the same `seconds`.
 */
export async function chat({ key, body, seconds = 120, signal, fetcher = fetch }) {
  const deadline = Date.now() + seconds * 1000;
  let cost = 0;
  for (let attempt = 0; attempt < 3; attempt++) {
    // Whole milliseconds: a timer takes nothing finer, and the seconds given may have more.
    const left = Math.floor(deadline - Date.now());
    if (left < 1000) throw new OpenRouterTrouble("timeout", "This ran out of time.", { cost });
    let answer;
    try {
      answer = await fetcher(ENDPOINT, { method: "POST", body: JSON.stringify(body),
        headers: { Authorization: `Bearer ${key || ""}`, "Content-Type": "application/json", "X-Title": "Lamp" },
        signal: signal ? AbortSignal.any([signal, AbortSignal.timeout(left)]) : AbortSignal.timeout(left) });
    } catch (error) {
      if (signal?.aborted) throw new OpenRouterTrouble("stopped", "Stopped.", { cost });
      if (error?.name === "TimeoutError" || Date.now() >= deadline) throw new OpenRouterTrouble("timeout", "This ran out of time.", { cost });
      throw new OpenRouterTrouble("refused", "Couldn't reach OpenRouter.", { cost });
    }
    let reply = {};
    try { reply = await answer.json(); } catch {}
    cost += Number(reply?.usage?.cost) || 0;
    const choice = Array.isArray(reply?.choices) ? reply.choices[0] : null;
    if (answer.status !== 200 || !choice) throw new OpenRouterTrouble("refused", "OpenRouter didn't answer.", { status: answer.status, reply, cost });
    if (choice.finish_reason === "content_filter") {
      if (attempt < 2) { await new Promise((done) => setTimeout(done, Math.min(400 << attempt, Math.max(0, deadline - Date.now())))); continue; }
      throw new OpenRouterTrouble("filtered", FILTERED, { cost });
    }
    return { message: choice.message ?? {}, cost };
  }
  throw new OpenRouterTrouble("refused", "The AI didn't answer.", { cost });
}

/** A text answer: `{text, cost}`. */
export async function text(given) {
  const { message, cost } = await chat({ ...given, body: textBody(given) });
  return { text: typeof message.content === "string" ? message.content : "", cost };
}

/** One request to OpenRouter, within `seconds`: its status and its JSON, or why there was none. */
async function post(path, { key, body, seconds, signal, fetcher = fetch }) {
  const timeout = AbortSignal.timeout(Math.floor(seconds * 1000));
  let answer;
  try {
    answer = await fetcher(`https://openrouter.ai/api/v1/${path}`, { method: "POST", body: JSON.stringify(body),
      headers: { Authorization: `Bearer ${key || ""}`, "Content-Type": "application/json", "X-Title": "Lamp" },
      signal: signal ? AbortSignal.any([signal, timeout]) : timeout });
  } catch (error) {
    if (signal?.aborted) throw new OpenRouterTrouble("stopped", "Stopped.");
    if (error?.name === "TimeoutError") throw new OpenRouterTrouble("timeout", "This ran out of time.");
    throw new OpenRouterTrouble("refused", "Couldn't reach OpenRouter.");
  }
  let reply = {};
  try { reply = await answer.json(); } catch {}
  return { status: answer.status, reply: reply && typeof reply === "object" ? reply : {} };
}

/**
 * Decisions from a decision model (`LampAI.decide`, `AppAI.decide`): `{answers, cost}`. Rate limits (429) and overload
 * (529) are expected under load, so it backs off and asks again three times at most. A request the model can't take
 * (422) is "invalid", with what it said.
 */
export async function decide({ key, model, state, questions, seconds = 60, signal, fetcher }) {
  for (let attempt = 0; attempt < 4; attempt++) {
    const { status, reply } = await post("systemone", { key, body: { state, model, questions }, seconds, signal, fetcher });
    if ((status === 429 || status === 529) && attempt < 3) { await new Promise((done) => setTimeout(done, 500 << attempt)); continue; }
    if (status !== 200 || !reply.answers || typeof reply.answers !== "object") {
      const detail = reply.error?.message ?? (reply.detail !== undefined ? String(typeof reply.detail === "string" ? reply.detail : JSON.stringify(reply.detail)) : `HTTP ${status}`);
      throw new OpenRouterTrouble(status === 422 ? "invalid" : "refused", status === 422 ? `The decision request was invalid: ${detail}` : "The decision model didn't answer.", { status, reply });
    }
    // Jev charges per input token ($0.042 per million); OpenRouter may report the exact cost.
    // A cost OpenRouter reports stands, nothing included; the estimate is only for when it reports none.
    const reported = reply.usage?.cost;
    const cost = typeof reported === "number" && Number.isFinite(reported) ? reported : (Number(reply.usage?.input_tokens) || 0) * 0.042 / 1_000_000;
    return { answers: reply.answers, cost };
  }
  throw new OpenRouterTrouble("busy", "The decision model is busy. Try again in a moment.");
}

/**
 * A picture from an image model (`LampAI.makeImage` and its edits, `AppAI.image`): `{image, cost}`, the PNG in base64.
 * `references` are the pictures to edit or build on (base64, with their `media_type`).
 */
export async function image({ key, model, prompt, references = [], aspectRatio, seconds = 240, signal, fetcher }) {
  const body = { model, prompt, n: 1, output_format: "png" };
  if (aspectRatio) body.aspect_ratio = aspectRatio;
  const given = (Array.isArray(references) ? references : []).filter((reference) => reference?.data);
  if (given.length) body.input_references = given.map((reference) => ({ type: "image_url", image_url: { url: `data:${reference.media_type || "image/png"};base64,${reference.data}` } }));
  const { status, reply } = await post("images", { key, body, seconds, signal, fetcher });
  if (status !== 200) throw new OpenRouterTrouble("refused", "The image model didn't answer.", { status, reply });
  const picture = Array.isArray(reply.data) ? reply.data[0]?.b64_json : null;
  if (typeof picture !== "string" || !picture) throw new OpenRouterTrouble("empty", "The image model didn't return a picture.", { reply });
  return { image: picture, cost: Number(reply.usage?.cost) || 0 };
}
