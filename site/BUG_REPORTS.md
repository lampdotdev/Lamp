# Sending Lamp bug reports

Lamp posts the exact UTF-8 report text to `https://lamp.dev/api/bug-report` only when the person clicks
Send. This Vercel Function lives under `site/api/`, alongside the static Astro site. Validation and
quotas are in `lib/bug-report.js` and `lib/report-limit.js`; changing the destination only needs a new
adapter in `lib/report-destination.js`. The app contains no Slack credential.

## What Dan must configure

1. In Slack's [app dashboard](https://api.slack.com/apps), use an existing app or create one yourself.
   Enable **Incoming Webhooks**, then **Add New Webhook to Workspace**, choose the feedback channel,
   and authorize it. The secret needed is the resulting **incoming webhook URL**, not a bot token,
   signing secret, workspace ID or channel ID. It is tied to the channel selected there.
2. In the Roo Code Vercel team, open the [lamp project](https://vercel.com/roo-code/lamp) — check that it
   serves `lamp.dev` and its Root Directory is `site/`, rather than the update-feed project.
   Open **Settings → Environment Variables → Add Environment Variable**. Paste the full webhook URL
   into **`LAMP_BUG_REPORT_SLACK_WEBHOOK_URL`**, select **Production**, enable **Sensitive**, and save.
   Keep the real webhook out of Preview and Development. Do not use a `PUBLIC_` prefix.
3. Provision/connect **Upstash Redis** through Vercel's **Storage / Marketplace** for that project (or
   use an existing Upstash database). Add **`UPSTASH_REDIS_REST_URL`** and
   **`UPSTASH_REDIS_REST_TOKEN`** to the same project's Production environment; mark the token Sensitive.
   They are the database's HTTPS REST endpoint and read/write REST token. The Vercel integration may
   populate these automatically; verify the names. A read-only token cannot enforce quotas.
4. After the code is approved and deployed, redeploy the Production website so the new environment
   variables take effect. Configuration changes do not update existing deployments. Until the webhook
   and Redis are available, the endpoint returns 503 and Lamp keeps the report for Copy/Share.

No Slack app, webhook or real-channel message was created as part of development. Dan performs the
Slack authorization and production configuration himself. For preview testing, use a separate fake
receiver and separate test Redis configuration, never the real webhook.

## Abuse limits and privacy

- POST with UTF-8 plain text only; the body is capped at **16,384 bytes while streaming**, including
  requests without Content-Length. Empty/malformed text and cross-origin browser submissions fail.
- A single atomic Redis script reserves forwarding attempts: **3 per IP per hour**, **10 total per
  hour**, and **30 total per day**. Counters expire; quotas persist across deployments and concurrent
  instances. Failed forwarding attempts also consume quota. Limiter errors fail closed.
- Vercel's trusted client-IP headers are used, rather than a client-supplied identifier. No extra proxy
  should override those headers. Redis stores expiring counters with a keyed IP hash, not raw IPs or
  report contents. Preview and Production have separate counter namespaces.
- The endpoint is anonymous; quotas bound channel volume, rather than pretending an app-embedded key
  proves identity. Someone can exhaust the shared quota; Copy/Share remains available to real testers.
- Slack receives the reviewed text in `plain_text` blocks, split without breaking Unicode or encoded
  entities. Slack control characters are escaped so decoding preserves literal text such as `&lt;`.
  Formatting, mentions and link/media unfurls are disabled. The webhook is fixed by server configuration;
  a request cannot choose a channel or destination. Reports/credentials are not logged by this code.
- Network calls have timeouts and refuse redirects. A success response is returned only after Slack
  acknowledges `ok`. If the acknowledgement is lost, delivery is uncertain; no automatic retry occurs.
  A deliberate retry or a manually shared report can duplicate a report already accepted by Slack.

## Checks and local stand-in

`npm test` checks the HTTP contract and Slack payload with fake network receivers. To also exercise the
actual Lua quota script, put `redis-server` and `redis-cli` on PATH (or set `REDIS_SERVER`/`REDIS_CLI` to
their paths); the tests start an isolated Redis with persistence disabled and stop only that process.
`npm run build` builds the static site; Vercel deploys `api/bug-report.js` as its own Function.

`node tests/stand-in.js` runs the real report handler against fake Slack and Redis receivers on localhost.
Its endpoint is `http://127.0.0.1:49181/api/bug-report`; payloads are written only to a supplied proof
directory. The stand-in never contacts Slack. A Lamp Dev process can point at it using
`LAMP_BUG_REPORT_TEST_ENDPOINT` set to that loopback URL; installed Lamp ignores this override.

Reference: [Slack incoming webhooks](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/),
[Vercel environment variables](https://vercel.com/docs/environment-variables),
[Upstash Vercel integration](https://upstash.com/docs/redis/howto/vercelintegration).
