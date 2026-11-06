# Wishes shared as links

The chat's Share popover has **Make a Link…** (a gear beside the link, to change it, once it has one): the person reviews what the link will show (the wish's name, what it
does, who it's by (their name on the Mac until they change it, which Lamp remembers) and a picture of the app, which they can take again), and Copy Link puts it
on lamp.dev and copies `https://lamp.dev/w/<id>-<name>`. The name (`slugFor`) is only for reading: the id finds the wish (`wishIDFrom`), so a link with an old name or none (made before a rename, or before links carried it) still works. Whoever opens the link makes their own version from the words, which Lamp sends as what the wish does (its first request when that's empty). The
wish's shared file (`<name>.lampapp`, made as Share… makes it, with its
license and key checks) goes too, whenever its kind can go as a file, and the page offers that exact wish to anyone with Lamp (Remix, then Open, on a Mac), which reviews it
before it opens, as any shared file, and makes a copy that follows the link. Never the chat or the app's data.

- The wish to play (`/w/<id>` for a wish sent with its page): a web app, a web game or a screen (the wish's own, or its
  one app's when that's in a part of its own, `Publish.pageApp`) plays at the top of
  the link's page, as large as the window allows in the shape Lamp sends with it (`shape` in the page's JSON: its width
  over its height, or `"fill"` for a page that takes any shape; Lamp sends a web game's stage, and `"fill"` for a web app
  or a screen, `Publish.pageShape`; without one, the 16:9 a web game is drawn in), with a button for full screen, so whoever opens the link tries it
  first. Lamp sends the page with the wish's file (`WishLink.playablePage`: the page Lamp puts on
  GitHub Pages, what it saves kept under the link), zipped, in parts to `api/wish-file.js` with `what=page`; the site
  unpacks it (`readPage`: index.html at its root, never a link or a path that steps up, at most 3,000 files) into Blob,
  each version in a folder of its own, and drops the last one. Blob hands HTML out as a download and refuses frames, so
  the files are served by `api/wish-play.js` (`/w/<id>/play/<version>/<path>`, `createPlayHandler`) only on the link's
  own host under the play host (`playOrigin`: `<id in hex>.play.lamp.dev`), so one shared page can never read what
  another saved in the browser, and never on lamp.dev itself; framed only by the site (`frame-ancestors`). Each file is passed on as it comes from Blob; one of 16 MB or more (`DIRECT_FILE`, a game's map data, say) is sent straight to Blob instead, since the CDN keeps nothing over 20 MB from a function. That needs Blob to call it what it is, so files are kept with their own type, and a page kept that way has `page.sizes`. A page's
  version counts up for the link (`pageVersion`), so an address never plays two different pages. The page goes with
  the wish's file: taking the file away takes the page too. Without a play host, the page shows the wish's picture (or its icon, when it has none) with its
  line and how to get it.
- The page (`/w/<id>`, `src/pages/w/index.astro` filled by `lib/shared-wish-page.js`, served by `api/wish-page.js`
  through a rewrite in `vercel.json`): a page of the wish's own, for playing it, plain, on the site's paper and ink (the wish between thin-ruled bars, on black once they're put away),
  with Lamp only a quiet "Made with Lamp" in the header beside the wish's icon, name and who it's by. The wish fills the
  rest of the window, playing or as its picture, only as big as it is (a page that plays takes the shape sent with it:
  it can't say its shape from inside its frame, and the picture is of its Mac window). Making one's own is a slim band
  at the foot, slid out of the window with the header by a chevron in the window's corner, which brings both back from the same
  place (remembered in that browser): a prompt box with
  the changes Lamp suggests for it (`RemixSuggestions`, sent with the link) turning in its placeholder, and a send
  button that opens **Remix** with what's written, or else the change shown: a dialog with the change, a line on
  Lamp, and two ways on side by side: **Open in Lamp** on a Mac (`lamp://wish?shared=<id>` with the change, so the copy
  follows the link, or `lamp://wish?text=…` for a link without the wish's file) and **Get Lamp**, which downloads it and
  copies the wish and the change with Lamp's mark (FIRST_IDEA.md). A request the link brought (`?ask=`) waits in the box. The function
  serves the built page (`dist/w/index.html`, bundled with it by `includeFiles`) with the wish in `#shared-wish`
  (its play address in `play`) and its own title, description and preview tags in place of the built page's; `npm run
  dev` gives it its own server's. On its own, `/w/` goes to the ideas page.
- What's new (`releases` on the record): each version the sharer released (Release Update, `WishReleases` in Lamp),
  newest first, with when it went out and the plain lines Lamp wrote for it and the sharer kept. The page's header says
  "updated <date of the newest>" after the name and who it's by, when there are any, and opens the list under it (a
  popover). Until this browser has opened it since the newest release (`lamp.shared.seen.<id>` in localStorage), it's
  darker with a sparkle, which twinkles twice as the page comes in (still where less motion is asked for); after, gray
  like the byline. A change from a Lamp that doesn't send `releases` keeps the ones
  the link has.
- The preview card (`/w/<id>/card.png`, `lib/wish-card.js`, `api/wish-card.js`): 1200×630, drawn by `@vercel/og`
  with Geist (`lib/fonts`, SIL Open Font License) on a night sky with the lamp's warm light. It's only about the app (its
  icon, name, line and picture), and its page's title is only the app's name: the preview names lamp.dev already. The page names it in
  `og:image` and `twitter:image` with Twitter's large card.
- The wish's file (`api/wish-file.js`, `createFileHandler` in `lib/shared-wishes.js`), only with the link's secret:
  `PUT ?id=&part=<n>&of=<count>` sends one part as raw bytes (at most 3 MB, since a request to a function holds 4.5 MB),
  `POST ?id=` puts the parts together, checks the result is a zip whose listing names `lamp-app.json` and is at most 48 MB,
  and gives it to the link in place of any it had (in Blob, public at an address with a random part); `DELETE ?id=` takes
  it away. Parts go once they're together; everything goes with the link, and with `scripts/take-down-wish.js`.
- Following (`GET /api/wishes?id=`, `latest` in `lib/shared-wishes.js`): public, with no quota, for the Lamps that
  follow a link: `{format: 1, id, name, by, version, file}` (`by` as the page names who it's by, empty for nobody, which Lamp keeps with what it pulls in from the copy), the file's version counting up each time it's sent again
  (Release Update), 0 with no file. The count is the link's (`fileVersion`), so a file taken away and sent again later is
  still newer than any before. The page's Open is `lamp://wish?shared=<id>`
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

- What's taken: a name (60 characters), who it's by (60, or nothing), a line (140), up to three changes Lamp suggests (100 each), up to 30 releases of up to five lines (120 each) with an ISO date no more than a day ahead, the page's shape (a width over a height from 0.2 to 5, or "fill"), the words (2,000), a PNG or JPEG picture (1.5 MB, 4,096 px a
  side) and a square PNG icon (300 KB), checked by their bytes; nothing else. Lamp holds the sharer to the same
  limits and sends the picture as a fresh JPEG, which leaves behind whatever the file carried besides its pixels.
- `QUOTAS` in `lib/shared-wishes.js`: 10 new links an hour per address, 200 an hour and 1,000 a day overall. Changes
  to a link that's out, and putting a file's or a page's parts together, count apart (`UPDATE_QUOTAS`): 90 an hour per
  address (an update counts up to three) and 5,000 a day overall. 60 takedowns an hour per address. A file's and a
  page's parts: 200 an hour per address and 3,000 a day overall (`PART_QUOTAS`). A file, and a page as it's sent, is at most 48 MB (`FILE_LIMITS`); a page unpacks to at most 128 MB and 3,000 files (`PAGE_LIMITS`), which Lamp checks before sending it. As for bug reports, only expiring counters and a keyed hash of the address are
  kept. Nothing a request holds is logged.
- Only the hash of each secret is kept. The page is `noindex`; what the sharer wrote reaches it only as JSON in a
  script that isn't run, which the card reads as text.
- The page is cached a minute and the card a day; a change or takedown purges both by their cache tag
  (`wish-<id>`). A record stays until the sharer takes it down.
- To take a link down for someone (it shows what it mustn't): `scripts/take-down-wish.js`.

## Trying it locally

`npm run dev` answers `/api/wishes`, `/w/<id>` and its card itself, keeping shared wishes in memory, with no quotas.
A Lamp Dev started with `LAMP_WISH_LINK_ENDPOINT=http://localhost:4321/api/wishes` shares to it (installed Lamp
ignores the variable). A Lamp Dev's link scheme is its own (`lamp-dev-…://`), so the page's Open opens the
installed Lamp, if any: try the hand-off with `open "lamp-dev-<instance>://wish?text=…"` instead.

To check the previews once deployed: X's card validator is gone, so post the link in a draft (or use a preview tool
such as opengraph.xyz); Slack and iMessage show the card when the link is pasted.
