# Sending Lamp bug reports

## Setup (one time, about 10 minutes)

Never paste the webhook URL or Redis token anywhere but Vercel.
Use **Production only** for all three variables, with **Sensitive on** for the webhook URL and Redis token.

### Slack webhook

1. In [Slack apps](https://api.slack.com/apps), create an app **From scratch** named **Lamp Bug Reports** in your workspace.
2. Open the app’s **Incoming Webhooks** settings and switch them on.
3. Choose **Add New Webhook to Workspace**, select the feedback channel, and authorize it.

### Vercel + Upstash

4. Open the **Roo Code → lamp** Vercel project, not **forge-updates**, and go to **Settings → Environment Variables**.
5. Add `LAMP_BUG_REPORT_SLACK_WEBHOOK_URL` with the full URL from Slack’s new webhook row.
6. In **Storage → Create Database**, choose **Upstash for Redis**, name it **lamp-bug-reports**, select **Free**, and connect it to **lamp** for Production only.
7. Add `UPSTASH_REDIS_REST_URL` using the database’s `KV_REST_API_URL` value, the HTTPS REST endpoint.
8. Add `UPSTASH_REDIS_REST_TOKEN` using its `KV_REST_API_TOKEN` value, the read/write token rather than the read-only token.

### Test

Redeploy and test only after this PR is merged.

9. In **lamp → Deployments**, open the latest Production deployment’s **… → Redeploy** action.
10. In a Lamp build with Send, open **Help → Report a Bug…** and send one report saying **Setup test — please ignore**.
11. Confirm Lamp says **Report sent** and one test message appears in the Slack channel you selected.

## How it works

Lamp posts the exact UTF-8 report text to `https://lamp.dev/api/bug-report` only when the person clicks
Send. This Vercel Function lives under `site/api/`, alongside the static Astro site. Validation and
quotas are in `lib/bug-report.js` and `lib/report-limit.js`; changing the destination only needs a new
adapter in `lib/report-destination.js`. The app contains no Slack credential.

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
