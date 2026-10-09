# The first-idea section

Right under the homepage's hero, a short conversation helps a visitor find their first app before they
download Lamp. A button under its heading starts it: four everyday situations at a time ("Can you relate to any of these?"), one or two questions
about the one they pick, then the request in their own words, in a card they can edit, with one button that
copies it and downloads Lamp, to paste into New App.

- The page: `src/components/FirstIdea.astro`. The situations, the rounds and the questions used when the model
  can't be reached: `lib/situations.js`, shared with the server.
- The follow-up: `api/first-idea.js` (`lib/first-idea.js`). The page sends only a situation's id (or the
  visitor's own words) and the short answers so far; the instructions to the model live on the server.
- The counts: `api/idea-event.js` (`lib/idea-events.js`).

## Setup (one time)

In the **lamp** Vercel project, **Settings → Environment Variables**:

1. `OPENROUTER_API_KEY`: an OpenRouter key for the site, Sensitive on. Give it a monthly credit limit in
   OpenRouter's key settings, as a ceiling on top of the quotas below.
2. `FIRST_IDEA_MODEL` (optional): any OpenRouter model id. Without it the site uses `DEFAULT_MODEL` in
   `lib/first-idea.js`. Changing the variable and redeploying is all it takes to try another model.
3. The Upstash variables the bug reports already use (`UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`,
   see BUG_REPORTS.md) cover the quotas and the counts. To try it on preview deployments, add all of these
   for Preview too: preview counts are kept apart from production's.

Without a key, or when a quota is reached, the section still works: it asks the built-in question for the
situation and writes the request from the answer.

## Trying it locally

`npm run dev` answers `/api/first-idea` itself (see `astro.config.mjs`), with no quotas and no counts. Put
`OPENROUTER_API_KEY=…` (and `FIRST_IDEA_MODEL=…` to try a model) in `site/.env.local`, which git ignores, and
restart the dev server. Without a key it falls back to the built-in questions.

## Limits and privacy

- `QUOTAS` in `lib/first-idea.js`: 30 calls an hour per visitor (a conversation is two or three), 1,500 an hour
  and 9,000 a day overall.
- What a visitor types goes to OpenRouter and the model, and nowhere else: it isn't logged or stored. Only
  expiring counters and a keyed hash of the IP are kept for the quotas, as for bug reports.

## Reading the counts

Each day keeps a tally of what happened, never what anyone typed: starts, rounds shown, "None of these" per round,
which situation was picked, own words, questions asked, requests written (by the model or the built-in
questions), edited, copied, Download pressed, and the model failing. From `site/`:

```bash
vercel env pull .env.local
node --env-file=.env.local scripts/first-idea-stats.js 14
```
