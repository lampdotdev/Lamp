import { createHmac } from "node:crypto";

// All counters are checked and incremented together. A process-local counter would reset whenever
// Vercel starts another instance, allowing a public endpoint to flood the feedback channel.
export const limitScript = `
local limits = {3, 10, 30}
local lifetimes = {3600, 3600, 86400}
local retry = 0
for i, key in ipairs(KEYS) do
  if tonumber(redis.call('GET', key) or '0') >= limits[i] then
    retry = math.max(retry, math.max(1, redis.call('TTL', key)))
  end
end
if retry > 0 then return retry end
for i, key in ipairs(KEYS) do
  if redis.call('INCR', key) == 1 then redis.call('EXPIRE', key, lifetimes[i]) end
end
return 0
`;

export async function reserveReport(ip, env, fetcher = fetch) {
  const url = env.UPSTASH_REDIS_REST_URL;
  const token = env.UPSTASH_REDIS_REST_TOKEN;
  if (!url || !token || new URL(url).protocol !== "https:") throw new Error("Limiter unavailable");
  const scope = env.VERCEL_ENV === "production" ? "production" : "preview";
  // Only expiring counters and a keyed IP hash are stored, never reports or raw IP addresses.
  const hash = createHmac("sha256", token).update(ip).digest("hex");
  const prefix = `lamp:bug-report:{${scope}}`;
  const response = await fetcher(url, {
    method: "POST", redirect: "error", signal: AbortSignal.timeout(3000),
    headers: { Authorization: `Bearer ${token}`, "Content-Type": "application/json" },
    body: JSON.stringify(["EVAL", limitScript, "3", `${prefix}:ip:${hash}`, `${prefix}:hour`, `${prefix}:day`]),
  });
  if (!response.ok) throw new Error("Limiter unavailable");
  const body = await response.json();
  if (body.error || !Number.isInteger(body.result) || body.result < 0) throw new Error("Limiter unavailable");
  return body.result;
}
