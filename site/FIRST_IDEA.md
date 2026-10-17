# The first-idea section

Right under the homepage's hero, a short conversation helps a visitor find their first app before they
download Lamp. A button under its heading starts it: four everyday situations at a time ("Can you relate to any of these?"), one or two questions
about the one they pick, then the request in their own words, in a card they can edit, with one button that
downloads Lamp and hands it the wish.

The hand-off (`lib/wish.js` here, `Sources/Lamp/Wish.swift` in the app) has two ways in, since a page can't
tell whether Lamp is installed:

- **Download Lamp** copies the wish with a mark only Lamp looks for (an attribute in the clipboard's web
  form; the plain text is just the wish). The first time Lamp opens it looks at the clipboard once and, if
  the mark is there, puts the wish in the first-app box. Anything else on the clipboard is left alone, and
  where macOS would ask before letting an app read it, Lamp doesn't read: the box offers "Paste my wish".
- **Already have Lamp? Open it with this wish** opens `lamp://wish?text=…`: the card sinks back into the
  lamp's light and Lamp comes to the front with the wish in a new app's message box (or the welcome's box,
  if it's still there), waiting for the person to send it. The page is never told whether Lamp opened, so
  it says "Off it goes." and offers to try again.

An example that is one of the apps Lamp comes with can hand Lamp that app rather than a wish to make it again:
`starterLink` and `copyStarter` in `lib/wish.js` work as the two ways in above, with the starter's name, and Lamp
opens it with its chat and the changes it suggests, putting it back on the desk first if it isn't there.

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

To see what a change to the model's instructions (`RULES` in `lib/first-idea.js`) does to its questions and
wishes, run ten made-up visitors through it, or only some of them by number:

```bash
node --env-file=.env.local scripts/try-first-idea.js
node --env-file=.env.local scripts/try-first-idea.js 1 5 9
```

## Limits and privacy

- `QUOTAS` in `lib/first-idea.js`: 30 calls an hour per visitor (a conversation is two or three), 1,500 an hour
  and 9,000 a day overall.
- What a visitor types goes to OpenRouter and the model, and nowhere else: it isn't logged or stored. Only
  expiring counters and a keyed hash of the IP are kept for the quotas, as for bug reports.

## Reading the counts

Each day keeps a tally of what happened, never what anyone typed: starts, rounds shown, "None of these" per round,
which situation was picked, own words, questions asked, requests written (by the model or the built-in
questions), edited, copied, Download pressed, sent to Lamp by the link, and the model failing. From `site/`:

```bash
vercel env pull .env.local
node --env-file=.env.local scripts/first-idea-stats.js 14
```
