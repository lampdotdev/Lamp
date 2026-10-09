import { isIP } from "node:net";
import { SITUATIONS, ROUNDS } from "./situations.js";
import { redis, evaluate, tallyScript, today } from "./quota.js";

// What the first-idea section counts, one tally per day: which situations people see and pick, how often none
// fit, and how far they get. Nothing anyone typed, and no IP address, is ever stored.
// Each event takes a detail from a fixed list, so the tally's fields are known in advance.
const rounds = ROUNDS.map((_, i) => String(i + 1));
const situations = Object.keys(SITUATIONS);
export const EVENTS = {
  start: [""],            // they pressed the button to start
  round: rounds,          // a round of four was shown
  none: rounds,           // "None of these" in that round
  pick: situations,       // a situation was picked
  own: [""],              // they wrote their own words instead
  question: ["1", "2"],   // the model asked its first or second question
  request: ["model", "script"], // a request was written, by the model or the built-in questions
  edit: [""],             // they changed the request
  copy: [""],             // they copied it
  download: [""],         // they pressed Download in this section
  failed: ["quota", "model", "network"], // the model couldn't be reached
};
export const PER_IP_PER_HOUR = 300;

const reply = (status) => new Response(null, { status, headers: { "Cache-Control": "no-store" } });

export function fieldFor(body) {
  if (!body || typeof body !== "object") return null;
  const { event, detail = "" } = body;
  if (typeof event !== "string" || !Object.hasOwn(EVENTS, event)) return null;
  if (typeof detail !== "string" || !EVENTS[event].includes(detail)) return null;
  return detail ? `${event}:${detail}` : event;
}

export function createEventHandler({ env = process.env, fetcher = fetch, now = () => new Date() } = {}) {
  return async (request) => {
    if (request.method !== "POST") return reply(405);
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) return reply(403);
    // sendBeacon sends a string as text/plain; the body is a tiny JSON object either way.
    const raw = await request.text();
    if (raw.length > 200) return reply(413);
    let field;
    try { field = fieldFor(JSON.parse(raw)); } catch { return reply(400); }
    if (!field) return reply(400);
    const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
    if (!isIP(ip)) return reply(503);
    try {
      const db = redis(env);
      await evaluate(db, ["EVAL", tallyScript, "2", `${db.prefix}:events-ip:${db.ipHash(ip)}`, `${db.prefix}:events:${today(now())}`,
        String(PER_IP_PER_HOUR), field], fetcher);
    } catch { return reply(503); }
    return reply(204);
  };
}
