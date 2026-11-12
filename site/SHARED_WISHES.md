# Wishes shared as links

The chat's Share popover has **Make a Link…** (a gear beside the link, to change it, once it has one): the person reviews what the link will show (the wish's name, what it
does, who it's by (their name on the Mac until they change it, which Lamp remembers) and a picture of the app, which they can take again), and Copy Link puts it
on lamp.dev and copies `https://lamp.dev/w/<id>-<name>`. The name (`slugFor`) is only for reading: the id finds the wish (`wishIDFrom`), so a link with an old name or none (made before a rename, or before links carried it) still works. Whoever opens the link makes their own version from the words, which Lamp sends as what the wish does (its first request when that's empty). The
wish's shared file (`<name>.lampapp`, made as Share… makes it, with its
license and key checks) goes too, whenever its kind can go as a file, and the page offers that exact wish to anyone with Lamp (Remix, then Open, on a Mac), which reviews it
before it opens, as any shared file, and makes a copy that follows the link. Never the chat or the app's data.

- The wish to play (`/w/<id>` for a wish sent with its page): a web app, a web game or a screen (the wish's own, or its
  one app's when that's in a part of its own, `Publish.pageApp`) plays at the top of
  the link's page, filling the room between its header and the bar under it, as the app's window fills a Mac's: a game's
  controls reach its edges and its scene, drawn on a fixed stage, is fitted inside with black around it where the
  shapes differ. The `shape` Lamp sends with the link (`Publish.pageShape`) stays in the page's JSON but no longer sizes
  the frame. Full screen is the browser's own, with the page's chevron putting its header and box away, so whoever
  opens the link tries it first. Lamp sends the page with the wish's file (`WishLink.playablePage`: the page Lamp puts on
  GitHub Pages, what it saves kept under the link), zipped, in parts to `api/wish-file.js` with `what=page`; the site
  unpacks it (`readPage`: index.html at its root, never a link or a path that steps up, at most 3,000 files) into Blob,
  each version in a folder of its own, and drops the last one. Blob hands HTML out as a download and refuses frames, so
  the files are served by `api/wish-play.js` (`/w/<id>/play/<version>/<path>`, `createPlayHandler`) only on the link's
  own host under the play host (`playOrigin`: `<id in hex>.play.lamp.dev`), so one shared page can never read what
  another saved in the browser, and never on lamp.dev itself; framed only by the site (`frame-ancestors`). Each file is passed on as it comes from Blob; a file of data the page fetches (map tiles, models, sound, JSON: `DIRECT_DATA`), and any file of 9 MB or more (`DIRECT_FILE`, since the CDN keeps nothing over 10 MB from a function), is sent straight to Blob instead, so the play host reads only a page's HTML, scripts, style sheets and pictures. A page's HTML is given a small script at the top of its head (`pictureScript`): asked by the link's page alone, it answers with a picture of the app's biggest canvas, drawn after its next frame, which goes with an idea sent from the box. That needs Blob to call it what it is, so files are kept with their own type, and a page kept that way has `page.sizes`. A page's
  version counts up for the link (`pageVersion`), so an address never plays two different pages. The page goes with
  the wish's file: taking the file away takes the page too. Without a play host, the page shows the wish's picture (or its icon, when it has none) with its
  line and how to get it.
- The page (`/w/<id>`, `src/pages/w/index.astro` filled by `lib/shared-wish-page.js`, served by `api/wish-page.js`
  through a rewrite in `vercel.json`): a page of the wish's own, for playing it, plain, on the site's paper and ink (the wish between thin-ruled bars, on black once they're put away),
  with Lamp only its mark and name, quiet at the foot, and the header the wish's icon, name and who it's by, with Make it your
  own on the right for a game that plays there and came with its file. The wish fills the
  rest of the window: a page that plays fills it, and a picture is only as big as it is (it's of the Mac window). Making one's own is a slim band
  at the foot, slid out of the window with the header by a chevron in the window's corner, which brings both back from the same
  place (remembered in that browser): a prompt box with
  the changes Lamp suggests for it (`RemixSuggestions`, sent with the link) turning in its placeholder, and a send
  button that opens **Remix** with what's written, or else the change shown: a dialog with the change, a line on
  Lamp, and two ways on side by side: **Open in Lamp** on a Mac (`lamp://wish?shared=<id>` with the change, so the copy
  follows the link, or `lamp://wish?text=…` for a link without the wish's file) and **Get Lamp**, which downloads it and
  copies the change with Lamp's mark naming the link (`data-lamp-wish="shared=<id>"`), so a new Lamp opens the shared app
  itself as the link would, or the wish and the change for a link without its file (FIRST_IDEA.md). Get Lamp under a
  picture copies the same, without a change. A request the link brought (`?ask=`) waits in the box. The function
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
  user), never in the app's. Lamp's side is `cli/link.mjs`, which Lamp's app asks (`WishLink`) and `lamp share` uses; it reads the limits from here.


## Usernames

A maker's links go under their username once they have one: `lamp.dev/<username>/<app>` (`linkOf`). An account is a
username and the email that confirmed it, nothing else, and there are no passwords (`lib/accounts.js`, `/api/accounts`).
Lamp, or `lamp account`, asks for one with a username and an email: the site answers a key the asker keeps and emails a
link (through Resend, as ideas' emails go), and once that's opened the key is the account's. Asked again with an address
that has an account, it's a sign-in, and that Lamp gets a key of its own. A share sent with a key (`X-Lamp-Account`)
goes under its username: a new link by the app's name there (`-2` and on when the name's taken), and an old link sent
again moves there, keeping that name whatever the app is called later. The old address (`/w/<id>-<name>`) sends anyone
to the new one (301). A share with no key is made as before, at `/w/`. The page plays from the same per-link play host
either way. Usernames are 2 to 30 lowercase letters, digits and dashes, never one of the site's own words (`w`, `api`,
`ideas` and the rest, `RESERVED`), and `/:user/:app` is the last of the site's routes, so a page of its own always wins.

Lamp and `lamp account` keep one account between them: lamp's command line keeps the key (`account.json` in lamp's
state, by site), and Lamp's app asks through it (the `account`, `accountAsk` and `accountForget` calls), so a link
shared from either goes under the same username. Lamp's Share Link card asks for one while there's none, filled in from
the name on the card and taken only with an email; without one the link goes out as before. While the email waits the
card says so, with Change for a mistyped address, and once it's confirmed a link from before moves at its next release.

A browser is signed in only by pressing the button on an idea's confirm page (never by opening a link, which anyone
could be sent to): a key of its own in an HttpOnly, SameSite=Lax cookie (`ACCOUNT_COOKIE`), which `GET /api/accounts`
reads and `DELETE` clears. An idea sent from a signed-in browser is by
its username (`user`, and the name the maker sees), and its news goes to the account's address. Someone who sends an
idea with an address that has no account is emailed a link to confirm it (`askToConfirm`): the page it opens shows a
button, so nothing is used up by a mail scanner, and pressing it signs the browser in to the address's account or
makes one with the username they choose (suggested from the name they gave). Emails about an idea go only to an
address with an account (`writeToSender`), so nobody hears about an idea someone else typed their address into.

## Where a link came from

A link made from a copy of another link's app says where it came from. The file that goes with a link names that link
on its credits' chain (`link`), so a copy of it, opened in Lamp or by `lamp play` or `lamp unpack`, knows it, and its own
share sends that link's id as `from`. The site keeps it only when there's such a link and it isn't the share's own; a
change that doesn't send it keeps it. The page draws "from <maker>/<app>" (or the source's name, with no username)
beside the name, linking to the source as it's known now (`findWish`), and nothing once the source is taken down.

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
