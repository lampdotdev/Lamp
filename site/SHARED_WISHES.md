# Wishes shared as links

Lamp's Share Wish menu has **Share Link…**: the person reviews what the link will show (the wish's name, its line,
its words and, if they keep it, a picture of the app, which they can leave out or take again), and Copy Link puts it
on lamp.dev and copies `https://lamp.dev/w/<id>`. Only the idea travels: no code, no data, no chat. Whoever opens the
link makes their own version from the words.

- The page (`/w/<id>`, `lib/shared-wish-page.js`, served by `api/wish-page.js` through a rewrite in `vercel.json`):
  the picture, icon, name, line and the words in a box to change, and the two ways into Lamp the first-idea section
  has (FIRST_IDEA.md): on a Mac it tries `lamp://wish?text=…` once as it opens and offers **Open in Lamp**, and
  **Download Lamp** copies the wish with Lamp's mark. The hand-off code is `lib/wish.js`, sent with the page.
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
   (and Preview, to try it on preview deployments). That adds `BLOB_READ_WRITE_TOKEN`. The pictures are public at
   addresses with a random part, under `production/` or `preview/`.
2. The Upstash variables the bug reports already use (`UPSTASH_REDIS_REST_URL`, `UPSTASH_REDIS_REST_TOKEN`, see
   BUG_REPORTS.md) keep each wish's record and the quotas. Add them for Preview too to try it there; preview's
   records and counters are kept apart from production's.

Without either, sharing answers 503 and Lamp says it couldn't share; links already made still open.

## Limits and privacy

- What's taken: a name (60 characters), a line (140), the words (2,000), a PNG or JPEG picture (1.5 MB, 4,096 px a
  side) and a square PNG icon (300 KB), checked by their bytes; nothing else. Lamp holds the sharer to the same
  limits and sends the picture as a fresh JPEG, which leaves behind whatever the file carried besides its pixels.
- `QUOTAS` in `lib/shared-wishes.js`: 10 shares or changes an hour per address, 200 an hour and 1,000 a day overall;
  60 takedowns an hour per address. As for bug reports, only expiring counters and a keyed hash of the address are
  kept. Nothing a request holds is logged.
- Only the hash of each secret is kept. The page is `noindex` and carries a content security policy that allows only
  its own script and pictures from here and the Blob store.
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
