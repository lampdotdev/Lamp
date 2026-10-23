# Wishes shared as links

Lamp's Share Wish menu has **Share Link…**: the person reviews what the link will show (the wish's name, its line,
its words and, if they keep it, a picture of the app, which they can leave out or take again), and Copy Link puts it
on lamp.dev and copies `https://lamp.dev/w/<id>`. Only the idea travels: no code, no data, no chat. Whoever opens the
link makes their own version from the words.

- The page (`/w/<id>`, `lib/shared-wish-page.js`, served by `api/wish-page.js` through a rewrite in `vercel.json`):
  the ideas page with the shared wish's card open on it, the same card (`WishDialog.astro`) the homepage's and the
  ideas page's wishes open in, so it has their Download Lamp (which copies the wish with Lamp's mark, FIRST_IDEA.md)
  and, on a Mac, their "Already have Lamp? Open it with this wish" (`lamp://wish?text=…`), which waits for the click
  as theirs does. Closed, it leaves the visitor among more ideas. The function serves the built ideas page
  (`dist/ideas/index.html`, bundled with it by `includeFiles`) with the wish in `#shared-wish` and its own title,
  description and preview tags in place of the ideas page's; `npm run dev` gives it its own server's ideas page.
- The preview card (`/w/<id>/card.png`, `lib/wish-card.js`, `api/wish-card.js`): 1200×630, drawn by `@vercel/og`
  with Geist (`lib/fonts`, SIL Open Font License) on the first-idea section's night sky. The page names it in
  `og:image` and `twitter:image` with Twitter's large card.
- The API Lamp talks to (`api/wishes.js`, `lib/shared-wishes.js`): `POST` shares and answers `{id, url, secret}`;
  `PUT ?id=` with `Authorization: Bearer <secret>` changes what the link shows and keeps the link; `DELETE ?id=`
  with the secret takes it down. Lamp keeps the secret in its own folder (`Wish Links.json`, readable only by the
  user), never in the app's. Lamp's side is `Sources/Lamp/WishLink.swift`; the tests check the two agree on the limits.

## Setup (one time)

In the **lamp** Vercel project:

1. **Storage → Create Database → Blob**, name it **lamp-shared-wishes**, and connect it to **lamp** for Production
   and Preview, with **Public** access. That adds `BLOB_STORE_ID`, which `@vercel/blob` uses with the deployment's
   OIDC token (a store connected the older way gives `BLOB_READ_WRITE_TOKEN`, which works too). The pictures are
   public at addresses with a random part, under `production/` or `preview/`.
2. The bug reports' Upstash database (**lamp-bug-reports**, see BUG_REPORTS.md) keeps each wish's record and the
   quotas. Under Storage → lamp-bug-reports → Projects, the lamp connection's **Update Project Connection** has
   Production and Preview ticked: the site reads the `KV_REST_API_URL` and `KV_REST_API_TOKEN` that connection gives
   when `UPSTASH_REDIS_REST_URL` and `UPSTASH_REDIS_REST_TOKEN` aren't set. Preview's records and counters are kept
   apart from production's.

Without either, sharing answers 503 and Lamp says it couldn't share; links already made still open.

## Limits and privacy

- What's taken: a name (60 characters), a line (140), the words (2,000), a PNG or JPEG picture (1.5 MB, 4,096 px a
  side) and a square PNG icon (300 KB), checked by their bytes; nothing else. Lamp holds the sharer to the same
  limits and sends the picture as a fresh JPEG, which leaves behind whatever the file carried besides its pixels.
- `QUOTAS` in `lib/shared-wishes.js`: 10 shares or changes an hour per address, 200 an hour and 1,000 a day overall;
  60 takedowns an hour per address. As for bug reports, only expiring counters and a keyed hash of the address are
  kept. Nothing a request holds is logged.
- Only the hash of each secret is kept. The page is `noindex`; what the sharer wrote reaches it only as JSON in a
  script that isn't run, which the card reads as text.
- The page is cached a minute and the card a day; a change or takedown purges both by their cache tag
  (`wish-<id>`). A record stays until the sharer takes it down.
- To take a link down for someone (it shows what it mustn't): `scripts/take-down-wish.js`.

## Trying it locally

`npm run dev` answers `/api/wishes`, `/w/<id>` and its card itself, keeping shared wishes in memory, with no quotas.
A Lamp Dev started with `LAMP_WISH_LINK_ENDPOINT=http://localhost:4321/api/wishes` shares to it (installed Lamp
ignores the variable). A Lamp Dev's link scheme is its own (`lamp-dev-…://`), so the page's Open in Lamp opens the
installed Lamp, if any: try the hand-off with `open "lamp-dev-<instance>://wish?text=…"` instead.

To check the previews once deployed: X's card validator is gone, so post the link in a draft (or use a preview tool
such as opengraph.xyz); Slack and iMessage show the card when the link is pasted.
