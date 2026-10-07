import { isIP } from "node:net";
import { reserveReport } from "./report-limit.js";
import { destinationURL, forwardReport } from "./report-destination.js";

export const MAX_REPORT_BYTES = 16_384;
const reply = (status, error, headers = {}) => Response.json(error ? { error } : { sent: true }, {
  status, headers: { "Cache-Control": "no-store", "X-Content-Type-Options": "nosniff", ...headers },
});

async function readReport(request) {
  const length = request.headers.get("content-length");
  if (length && (!/^\d+$/.test(length) || Number(length) > MAX_REPORT_BYTES)) throw new RangeError();
  if (!request.body) return "";
  const reader = request.body.getReader();
  const chunks = [];
  let size = 0;
  try {
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      size += value.byteLength;
      if (size > MAX_REPORT_BYTES) { await reader.cancel(); throw new RangeError(); }
      chunks.push(value);
    }
  } finally { reader.releaseLock(); }
  return new TextDecoder("utf-8", { fatal: true, ignoreBOM: true }).decode(Buffer.concat(chunks));
}

export function createReportHandler({ env = process.env, fetcher = fetch } = {}) {
  return async (request) => {
    if (request.method !== "POST") return reply(405, "method_not_allowed", { Allow: "POST" });
    const origin = request.headers.get("origin");
    if (origin && origin !== new URL(request.url).origin) return reply(403, "origin_not_allowed");
    if (!/^text\/plain(?:\s*;\s*charset=utf-8)?$/i.test(request.headers.get("content-type") || "")) {
      return reply(415, "text_required");
    }
    let report;
    try { report = await readReport(request); }
    catch (error) { return reply(error instanceof RangeError ? 413 : 400, "invalid_report"); }
    if (!report.trim()) return reply(400, "empty_report");

    // Vercel overwrites these headers with the client IP. Do not place another untrusted proxy in front.
    const ip = (request.headers.get("x-vercel-forwarded-for") || request.headers.get("x-forwarded-for") || "").trim();
    if (!isIP(ip)) return reply(503, "service_unavailable");
    let destination;
    let retry;
    try {
      destination = destinationURL(env);
      retry = await reserveReport(ip, env, fetcher);
    } catch { return reply(503, "service_unavailable"); }
    if (retry > 0) return reply(429, "rate_limited", { "Retry-After": String(retry) });
    try { await forwardReport(report, destination, fetcher); }
    catch { return reply(502, "delivery_failed"); }
    return reply(200);
  };
}
