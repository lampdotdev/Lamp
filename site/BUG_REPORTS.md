# Sending Lamp bug reports

## Setup (one time, about 10 minutes)

For **Dan's boss or another administrator with access to the team's Slack workspace and the Roo Code Vercel team**. No coding or terminal commands are needed. Choose an existing Slack channel for feedback before starting; `#lamp-bugs` is a suggested name, not a channel this PR creates. Join it first if it is private.

**Why these pieces:** the Slack app/webhook lets the website post into the selected channel; the Vercel variables keep the credentials on the server; Upstash Redis shares spam-limit counters across server instances; redeploy loads the new variables; one test report checks the whole path.

**Never paste the full Slack webhook URL or the Redis REST token into this PR, chat, code, or screenshots.** Copy them only into the Vercel Value fields below or an approved password manager. No bot token or Slack signing secret is needed.

**Before redeploy/test:** this PR is still draft. A maintainer must first approve and deploy its website changes and provide a Lamp build with **Help → Report a Bug… → Send**. You can configure the services now; redeploying an older website or testing an older Lamp will not enable this feature. These instructions do not authorize merging this PR.

1. **Open [Slack's app dashboard](https://api.slack.com/apps)** while signed into the team's Slack workspace. **Expected:** your apps and a **Create New App** button.
2. **Click Create New App.** **Expected:** a choice of how to create the app.
3. **Select From scratch.** **Expected:** the app-name/workspace form.
4. **Enter `Lamp Bug Reports` in App Name.** **Expected:** that name in the field.
5. **Select the team's workspace in the workspace dropdown.** **Expected:** the workspace containing your chosen feedback channel is selected.
6. **Click Create App.** **Expected:** the new app's **Basic Information** page. If this named app already exists, use its settings instead of creating a duplicate.
7. **Click Incoming Webhooks in the app's left sidebar.** **Expected:** the incoming-webhook settings page.
8. **Switch Activate Incoming Webhooks to On.** **Expected:** webhook creation becomes available.
9. **Click Add New Webhook to Workspace.** **Expected:** Slack's authorization screen with a channel dropdown.
10. **Select your existing feedback channel in that dropdown** (`#lamp-bugs` if that is the channel you chose). **Expected:** that channel is shown as the posting destination.
11. **Click the authorization button (Authorize/Allow).** **Expected:** a new row under **Webhook URLs for Your Workspace**, paired with the selected channel. [Slack's current webhook guide](https://docs.slack.dev/messaging/sending-messages-using-incoming-webhooks/) documents this authorization flow.
12. **Copy the complete URL from that new webhook row.** **Expected:** the clipboard contains an HTTPS Slack incoming-webhook URL, including its secret tail; keep it private.
13. **Open [Roo Code → lamp → Settings → Environment Variables](https://vercel.com/roo-code/lamp/settings/environment-variables).** **Expected:** the **lamp** project's **Add New** form. This is the `lamp.dev` website with Root Directory `site/`, not `forge-updates`.
14. **Enter `LAMP_BUG_REPORT_SLACK_WEBHOOK_URL` in the form's Name/Key field.** **Expected:** that exact name, with no `PUBLIC_` prefix.
15. **Paste the webhook URL into Value.** **Expected:** the full URL is entered privately in the value field, not the PR or chat.
16. **Set Environments to Production only.** **Expected:** Production selected; Preview and Development unselected.
17. **Turn Sensitive on for this new variable.** **Expected:** the Sensitive switch is enabled. If it is disabled, check that Development is unselected.
18. **Click Save.** **Expected:** a row named `LAMP_BUG_REPORT_SLACK_WEBHOOK_URL`, scoped to Production, with a Sensitive badge and masked value.
19. **Open [the lamp project](https://vercel.com/roo-code/lamp) → Storage.** **Expected:** its database/resource page.
20. **Click Create Database.** **Expected:** the Marketplace storage-provider choices.
21. **Choose Upstash for Redis.** **Expected:** the Upstash installation/Redis setup flow, not Vector, Search or QStash. [Vercel's product page](https://vercel.com/marketplace/upstash/upstash-kv) lists the Redis product and Free plan.
22. **Select Create New Upstash Account if the account choice appears.** **Expected:** Vercel will manage the new account. If Upstash is already installed for this team, use that installation instead.
23. **Click Continue if shown in the account-selection dialog.** **Expected:** the provider agreement or database configuration screen.
24. **Accept the provider agreement if Vercel displays its Accept Terms modal.** **Expected:** access to the database plan/configuration form; do this yourself as the administrator.
25. **Select the Free plan ($0).** **Expected:** Free selected, not Pay as You Go, Fixed or Prod Pack. Stop if Free is unavailable rather than accepting a paid plan. The current Free tier includes 256 MB and 500K commands/month; it is enough for ordinary beta feedback, not unlimited traffic. [Upstash pricing](https://upstash.com/pricing/redis).
26. **Enter `lamp-bug-reports` in the database Name field.** **Expected:** that resource name in the form.
27. **Select `us-east-1` / N. Virginia, USA as Primary Region.** **Expected:** that region selected, near Vercel's default `iad1` function region. [Upstash database settings](https://upstash.com/docs/redis/overall/getstarted), [Vercel's default region](https://vercel.com/docs/regions), [eviction behavior](https://upstash.com/docs/redis/features/eviction).
28. **Leave optional Read Regions empty.** **Expected:** no extra read-region replicas selected; they are unnecessary for these counters.
29. **Leave Eviction Off if that option is shown.** **Expected:** the switch remains Off, so storage pressure cannot discard quota counters and weaken the spam limits.
30. **Submit the database form with Create/Create Database.** **Expected:** the resource detail page shows `lamp-bug-reports`, status **Available**, and plan **Free**. The native Vercel flow asks for the plan before resource details; an Upstash-console form may instead show **Next** before its plan step.
31. **Click Connect Project on the resource page if lamp is not already connected.** **Expected:** the project-connection dialog.
32. **Select `lamp` in the project selector.** **Expected:** only the website project selected, not `forge-updates`.
33. **Choose Production only for the connection's environments.** **Expected:** Preview and Development unselected. If the integration has already connected automatically, verify the connection is limited to Production before continuing.
34. **Click Connect to save the project connection.** **Expected:** `lamp` appears among the resource's connected projects. [Upstash's Vercel integration guide](https://upstash.com/docs/redis/howto/vercelintegration) shows the resource and project connection.
35. **Open the resource's Quickstart → `.env.local` view.** **Expected:** credential names such as `KV_REST_API_URL` and `KV_REST_API_TOKEN`, with values masked. The full-access token is `KV_REST_API_TOKEN`, not the row with `READ_ONLY` in its name.
36. **Click Show secret in that Quickstart panel.** **Expected:** the credential values are visible only on your private screen; do not screenshot this panel.
37. **Copy only the value of `KV_REST_API_URL`** (or `UPSTASH_REDIS_REST_URL` in Upstash's REST panel). **Expected:** an `https://…upstash.io` REST endpoint on the clipboard, without the variable name or surrounding quotes. Do not use `KV_URL`, `REDIS_URL`, or a `redis://`/`rediss://` connection string.
38. **Return to [lamp → Settings → Environment Variables](https://vercel.com/roo-code/lamp/settings/environment-variables).** **Expected:** its Add New form. The integration may create `KV_*` variables, but Lamp specifically requires the `UPSTASH_*` names below; those are not interchangeable names in this implementation.
39. **Enter `UPSTASH_REDIS_REST_URL` in Name/Key.** **Expected:** that exact name.
40. **Paste the copied HTTPS REST endpoint into Value.** **Expected:** the URL value, without quotes or an assignment prefix.
41. **Set Environments to Production only.** **Expected:** Production selected; Preview and Development unselected.
42. **Leave Sensitive off for this URL-only variable.** **Expected:** this non-secret endpoint remains readable for checking; the token is protected separately in the next variable.
43. **Click Save.** **Expected:** `UPSTASH_REDIS_REST_URL` listed for Production. If this exact variable was populated already with the same URL and Production scope, keep that row instead of duplicating it.
44. **Reopen Vercel Storage → lamp-bug-reports → Quickstart → `.env.local`.** **Expected:** the resource's credential panel, separate from the website's variable form.
45. **Click Show secret if the values are masked.** **Expected:** you can privately copy the full-access REST token.
46. **Copy only the full-access value of `KV_REST_API_TOKEN` from the resource's private Quickstart view** (or `UPSTASH_REDIS_REST_TOKEN` from **Details → Connect → REST**). **Expected:** the read/write REST token on the clipboard. Do not use `KV_REST_API_READ_ONLY_TOKEN`; rate limiting needs writes. Keep the token out of the PR/chat.
47. **Return to lamp → Settings → Environment Variables.** **Expected:** the Add New form again.
48. **Enter `UPSTASH_REDIS_REST_TOKEN` in Name/Key.** **Expected:** that exact name.
49. **Paste the read/write REST token into Value.** **Expected:** the token entered privately, without quotes or its variable-name prefix.
50. **Set Environments to Production only.** **Expected:** Production selected; Preview and Development unselected.
51. **Turn Sensitive on for this new token variable.** **Expected:** Sensitive enabled before saving. Sensitive must be set before Save; editing an existing row cannot turn it on. [Vercel's Sensitive-variable instructions](https://vercel.com/academy/optimize-your-vercel-account/sensitive-env-vars).
52. **Click Save.** **Expected:** `UPSTASH_REDIS_REST_TOKEN` listed with Production, Sensitive and a masked value. The three required names are now present; extra integration-managed `KV_*` rows do not replace them.
53. **Open lamp → Deployments after the maintainer confirms the approved website code is deployed.** **Expected:** a Production deployment containing this PR's endpoint, associated with `lamp.dev`. Do not use this PR's protected Preview deployment or an older Production build.
54. **Open that Production deployment's ellipsis (`…`) menu.** **Expected:** a **Redeploy** action.
55. **Choose Redeploy.** **Expected:** the **Redeploy to Production** confirmation dialog.
56. **Click Redeploy in that dialog.** **Expected:** a new Production deployment that progresses to **Ready** and serves `lamp.dev`. New environment variables apply to new deployments, not previous ones. [Vercel's redeploy guide](https://vercel.com/docs/deployments/managing-deployments).
57. **Open Help → Report a Bug… in the Lamp build supplied by the maintainer that includes Send.** **Expected:** the editable report window with Send, Copy Report and Share….
58. **Enter `Setup test — please ignore (admin verification)` under What happened.** **Expected:** that harmless text plus the visible diagnostics; no secrets in the report.
59. **Click Send once after reviewing the whole report.** **Expected:** **Report sent. Thank you for helping improve Lamp.** Keep Copy/Share available if sending fails; avoid repeated test clicks because limits are 3/IP/hour, 10 total/hour and 30 total/day.
60. **Open the Slack channel selected in step 10.** **Expected:** one message from **Lamp Bug Reports** containing the setup-test text and Lamp/macOS diagnostics. This confirms the website, credentials, limiter and Slack forwarding together. The administrator performs this real-channel test; no test post was sent during development.

If a required variable already exists, use its **row → … → Edit** to check its name, Production scope and value source. For an existing webhook/token row without Sensitive, privately retain the original value from Slack/Upstash, use **row → … → Delete**, confirm the deletion, then recreate it with the exact name, Production only and Sensitive On using the form steps above. Do not delete an integration-managed variable; create the required `UPSTASH_*` alias instead.

If the test fails, check the three names and Production scopes, the full-access Redis token, the selected webhook channel, and whether the redeployed website includes the approved endpoint. Share only the displayed error/state and the variable **names/scopes**, never credential values or screenshots with secrets revealed. Sensitive values cannot be read back; replace them from their original source if necessary.

Provider docs and their published UI screenshots checked on **2026-10-07**. The administrator setup itself has not been executed. The same instructions are kept in `site/BUG_REPORTS.md`.

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
