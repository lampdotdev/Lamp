import http from "node:http";
import { Readable } from "node:stream";
import { createReportHandler } from "../lib/bug-report.js";

export async function listen(handler, port = 0) {
  const server = http.createServer(async (req, res) => {
    try {
      const response = await handler(new Request(`http://127.0.0.1${req.url}`, {
        method: req.method, headers: { ...req.headers, "x-vercel-forwarded-for": "192.0.2.1" },
        ...(req.method !== "GET" && req.method !== "HEAD" ? { body: Readable.toWeb(req), duplex: "half" } : {}),
      }));
      res.writeHead(response.status, Object.fromEntries(response.headers));
      res.end(Buffer.from(await response.arrayBuffer()));
    } catch { res.writeHead(500); res.end("test receiver error"); }
  });
  await new Promise((resolve) => server.listen(port, "127.0.0.1", resolve));
  return { server, url: `http://127.0.0.1:${server.address().port}`, close: () => new Promise((resolve) => server.close(resolve)) };
}

// This local receiver is the only network destination used by the stand-in. Even the fake webhook
// URL must never be fetched directly, so unexpected destinations are rejected rather than delegated.
export async function standIn({ evaluate, onPayload = () => {}, port = 0 } = {}) {
  const payloads = [];
  let failure = false;
  const counts = new Map();
  const receiver = await listen(async (request) => {
    if (new URL(request.url).pathname === "/redis") {
      const command = await request.json();
      if (evaluate) return Response.json({ result: await evaluate(command) });
      const keys = command.slice(3);
      const limits = [3, 10, 30];
      if (keys.some((key, i) => (counts.get(key) ?? 0) >= limits[i])) return Response.json({ result: 3600 });
      keys.forEach((key) => counts.set(key, (counts.get(key) ?? 0) + 1));
      return Response.json({ result: 0 });
    }
    const payload = await request.json();
    payloads.push(payload);
    await onPayload(payload);
    return new Response(failure ? "stand-in rejected the request" : "ok", { status: failure ? 500 : 200 });
  });
  const env = {
    LAMP_BUG_REPORT_SLACK_WEBHOOK_URL: "https://hooks.slack.com/services/TEST/TEST/stand-in-only",
    UPSTASH_REDIS_REST_URL: "https://limiter.invalid", UPSTASH_REDIS_REST_TOKEN: "stand-in-token", VERCEL_ENV: "preview",
  };
  const fetcher = (url, options) => {
    const target = String(url);
    if (target === env.LAMP_BUG_REPORT_SLACK_WEBHOOK_URL) return fetch(`${receiver.url}/slack`, options);
    if (target === env.UPSTASH_REDIS_REST_URL) return fetch(`${receiver.url}/redis`, options);
    throw new Error("Stand-in forbids external network access");
  };
  const handle = createReportHandler({ env, fetcher });
  const app = await listen(async (request) => {
    if (new URL(request.url).pathname === "/test/status") return Response.json({ deliveries: payloads.length });
    if (new URL(request.url).pathname === "/test/failure") {
      failure = true;
      return Response.json({ mode: "failure" });
    }
    return handle(request);
  }, port);
  return { ...app, handle, env, fetcher, payloads, setFailure: (value) => { failure = value; },
    close: async () => { await app.close(); await receiver.close(); } };
}
