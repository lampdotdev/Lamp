import { createHmac } from "node:crypto";

// Expiring counters in Upstash, checked and incremented together, for the first-idea endpoints. A process-local
// counter would reset whenever Vercel starts another instance. ARGV holds each key's limit, then each key's
// lifetime in seconds, so one script serves every quota.
export const quotaScript = `
local n = #KEYS
local retry = 0
for i, key in ipairs(KEYS) do
  if tonumber(redis.call('GET', key) or '0') >= tonumber(ARGV[i]) then
    retry = math.max(retry, math.max(1, redis.call('TTL', key)))
  end
end
if retry > 0 then return retry end
for i, key in ipairs(KEYS) do
  if redis.call('INCR', key) == 1 then redis.call('EXPIRE', key, tonumber(ARGV[n + i])) end
end
return 0
`;

// Increments one field of a day's tally after a per-IP check, so a script can't flood the numbers. The tally
// keeps no text and no IP address, only counts, for about a year.
export const tallyScript = `
if tonumber(redis.call('GET', KEYS[1]) or '0') >= tonumber(ARGV[1]) then return 0 end
if redis.call('INCR', KEYS[1]) == 1 then redis.call('EXPIRE', KEYS[1], 3600) end
redis.call('HINCRBY', KEYS[2], ARGV[2], 1)
redis.call('EXPIRE', KEYS[2], 34560000)
return 1
`;

export function redis(env) {
  // The names BUG_REPORTS.md has set by hand, else the ones the Upstash integration gives a project it's connected to.
  const url = env.UPSTASH_REDIS_REST_URL || env.KV_REST_API_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN || env.KV_REST_API_TOKEN;
  if (!url || !token || new URL(url).protocol !== "https:") throw new Error("Limiter unavailable");
  const scope = env.VERCEL_ENV === "production" ? "production" : "preview";
  return { url, token, prefix: `lamp:first-idea:{${scope}}`, ipHash: (ip) => createHmac("sha256", token).update(ip).digest("hex") };
}

export async function evaluate(db, command, fetcher = fetch) {
  const response = await fetcher(db.url, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(3000),
    headers: { Authorization: `Bearer ${db.token}`, "Content-Type": "application/json" },
    body: JSON.stringify(command),
  });
  if (!response.ok) throw new Error("Limiter unavailable");
  const body = await response.json();
  if (body.error || !Number.isInteger(body.result) || body.result < 0) throw new Error("Limiter unavailable");
  return body.result;
}

/** Seconds to wait before trying again, or 0 when the call may go ahead (and has been counted). */
export async function reserve(db, ip, quotas, fetcher = fetch) {
  const keys = quotas.map((q) => `${db.prefix}:${q.name}${q.perIP ? ":" + db.ipHash(ip) : ""}`);
  return evaluate(db, ["EVAL", quotaScript, String(keys.length), ...keys,
    ...quotas.map((q) => String(q.limit)), ...quotas.map((q) => String(q.seconds))], fetcher);
}

export const today = (now = new Date()) => now.toISOString().slice(0, 10);
