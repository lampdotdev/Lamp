# Wishes shared as links

The chat's Share Wish popover has **Make a Link…** (a gear beside the link, to change it, once it has one): the person reviews what the link will show (the wish's name, what it
does, who it's by (their name on the Mac until they change it, which Lamp remembers) and a picture of the app, which they can take again), and Copy Link puts it
on lamp.dev and copies `https://lamp.dev/w/<id>`. Whoever opens the link makes their own version from the words, which Lamp sends as what the wish does (its first request when that's empty). The
wish's shared file (`<name>.lampapp`, made as Share… makes it, with its
license and key checks) goes too, whenever its kind can go as a file, and the page offers that exact wish to anyone with Lamp (Open in Lamp, on a Mac), which reviews it
before it opens, as any shared file, and makes a copy that follows the link. Never the chat or the app's data.

- The wish to play (`/w/<id>` for a wish sent with its page): a web app, a web game or a screen (the wish's own, or its
  one app's when that's in a part of its own, `Publish.pageApp`) plays at the top of
  the link's page, as large as the window allows in its picture's shape, with a button for full screen, so whoever opens the link tries it
  first. Lamp sends the page with the wish's file (`WishLink.playablePage`: the page Put on GitHub puts on
  GitHub Pages, what it saves kept under the link), zipped, in parts to `api/wish-file.js` with `what=page`; the site
  unpacks it (`readPage`: index.html at its root, never a link or a path that steps up, at most 3,000 files) into Blob,
  each version in a folder of its own, and drops the last one. Blob hands HTML out as a download and refuses frames, so
  the files are served by `api/wish-play.js` (`/w/<id>/play/<version>/<path>`, `createPlayHandler`) only on the link's
  own host under the play host (`playOrigin`: `<id in hex>.play.lamp.dev`), so one shared page can never read what
  another saved in the browser, and never on lamp.dev itself; framed only by the site (`frame-ancestors`). A page's
  version counts up for the link (`pageVersion`), so an address never plays two different pages. The page goes with
  the wish's file: taking the file away takes the page too. Without a play host, the page shows the wish's picture.
- The page (`/w/<id>`, `src/pages/w/index.astro` filled by `lib/shared-wish-page.js`, served by `api/wish-page.js`
  through a rewrite in `vercel.json`): a page of the wish's own, about the thing someone made, on the homepage's paper,
  with Lamp only "Made with Lamp" at the top ("Learn more" beside it) and the bottom. The wish fills the top, playing
  or as its picture, only as big as it is (a page that plays takes its picture's shape, since it can't say its size
  from inside its frame); under it its icon, name, who it's by and what it does, and the ways to make one's own: a box
  for what to change with the changes Lamp suggests for it above it (`RemixSuggestions`, sent with the link; one puts its
  words in the box), **Open in Lamp** on a Mac (`lamp://wish?shared=<id>` with the change, so the copy follows the
  link, or `lamp://wish?text=…` for a link without the wish's file), and **Download Lamp**, which copies the wish and
  the change with Lamp's mark (FIRST_IDEA.md). A request the link brought (`?ask=`) waits in the box. The function
  serves the built page (`dist/w/index.html`, bundled with it by `includeFiles`) with the wish in `#shared-wish`
  (its play address in `play`) and its own title, description and preview tags in place of the built page's; `npm run
  dev` gives it its own server's. On its own, `/w/` goes to the ideas page.
- The preview card (`/w/<id>/card.png`, `lib/wish-card.js`, `api/wish-card.js`): 1200×630, drawn by `@vercel/og`
  with Geist (`lib/fonts`, SIL Open Font License) on the first-idea section's night sky. The page names it in
  `og:image` and `twitter:image` with Twitter's large card.
- The wish's file (`api/wish-file.js`, `createFileHandler` in `lib/shared-wishes.js`), only with the link's secret:
  `PUT ?id=&part=<n>&of=<count>` sends one part as raw bytes (at most 3 MB, since a request to a function holds 4.5 MB),
  `POST ?id=` puts the parts together, checks the result is a zip whose listing names `lamp-app.json` and is at most 48 MB,
  and gives it to the link in place of any it had (in Blob, public at an address with a random part); `DELETE ?id=` takes
  it away. Parts go once they're together; everything goes with the link, and with `scripts/take-down-wish.js`.
- Following (`GET /api/wishes?id=`, `latest` in `lib/shared-wishes.js`): public, with no quota, for the Lamps that
  follow a link: `{format: 1, id, name, version, file}`, the file's version counting up each time it's sent again
  (Update Link), 0 with no file. The count is the link's (`fileVersion`), so a file taken away and sent again later is
  still newer than any before. The page's Open in Lamp is `lamp://wish?shared=<id>`
  (`sharedWishLink` in `lib/wish.js`): Lamp asks this for the file, and the copy it makes follows the link
  (`Following` in Lamp).
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

3. Hosts of their own for the pages people play: add the wildcard domain **\*.play.lamp.dev** to the **lamp** project
   (Vercel serves a wildcard only for a domain on its nameservers) and set `LAMP_PLAY_ORIGIN` to
   `https://play.lamp.dev` for Production, and `LAMP_SITE_ORIGIN` to the site's (`https://lamp.dev`) if it isn't that.
   Each link's page runs on a host of its own there, apart from every other link's and from lamp.dev's cookies and
   API. Until it's set, links show their card and nothing plays.

Without the first two, sharing answers 503 and Lamp says it couldn't share; links already made still open.

## Limits and privacy

- What's taken: a name (60 characters), who it's by (60, or nothing), a line (140), up to three changes Lamp suggests (100 each), the words (2,000), a PNG or JPEG picture (1.5 MB, 4,096 px a
  side) and a square PNG icon (300 KB), checked by their bytes; nothing else. Lamp holds the sharer to the same
  limits and sends the picture as a fresh JPEG, which leaves behind whatever the file carried besides its pixels.
- `QUOTAS` in `lib/shared-wishes.js`: 10 shares or changes an hour per address, 200 an hour and 1,000 a day overall;
  60 takedowns an hour per address. A file's and a page's parts: 200 an hour per address and 3,000 a day overall (`PART_QUOTAS`);
  putting them together counts as a share. A file, and a page, is at most 48 MB (`FILE_LIMITS`). As for bug reports, only expiring counters and a keyed hash of the address are
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
