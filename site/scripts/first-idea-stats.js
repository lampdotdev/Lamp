// Prints what the homepage's first-idea section counted, a column per day (newest first).
// Needs the site's Upstash variables: `vercel env pull .env.local` in site/, then
//   node --env-file=.env.local scripts/first-idea-stats.js [days] [preview]
import { EVENTS } from "../lib/idea-events.js";
import { SITUATIONS } from "../lib/situations.js";

const days = Number(process.argv[2] ?? 7);
const scope = process.argv[3] === "preview" ? "preview" : "production";
const url = process.env.UPSTASH_REDIS_REST_URL;
const token = process.env.UPSTASH_REDIS_REST_TOKEN;
if (!url || !token) throw new Error("Set UPSTASH_REDIS_REST_URL and UPSTASH_REDIS_REST_TOKEN (see the comment at the top)");

const dates = Array.from({ length: days }, (_, i) => new Date(Date.now() - i * 86400000).toISOString().slice(0, 10));
const tallies = await Promise.all(dates.map(async (date) => {
  const response = await fetch(url, {
    method: "POST", headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(["HGETALL", `lamp:first-idea:{${scope}}:events:${date}`]),
  });
  const flat = (await response.json()).result ?? [];
  return Object.fromEntries(Array.from({ length: flat.length / 2 }, (_, i) => [flat[i * 2], Number(flat[i * 2 + 1])]));
}));

const fields = Object.entries(EVENTS).flatMap(([event, details]) => details.map((d) => (d ? `${event}:${d}` : event)));
const label = (field) => {
  const [event, detail] = field.split(":");
  return event === "pick" ? `pick  ${SITUATIONS[detail].text.slice(0, 48)}…` : field;
};
const width = Math.max(...fields.map((f) => label(f).length));
console.log(`${"".padEnd(width)}  ${dates.map((d) => d.slice(5)).join("  ")}`);
for (const field of fields) {
  const row = tallies.map((t) => String(t[field] ?? 0).padStart(5));
  if (row.every((cell) => cell.trim() === "0")) continue;
  console.log(`${label(field).padEnd(width)}  ${row.join("  ")}`);
}
