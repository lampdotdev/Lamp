# Changing a shared game with your own agent

Someone playing a shared game on lamp.dev asks for a change, and their own coding agent, on their own Mac, makes it.
The rebuilt game then comes back into the page. The page is `/change?w=<id>` (`src/pages/change.astro`), for a link
whose page plays. Nothing links to its helper form yet; the AI app form below is opened from a link's idea dialog. The helper is `lamp play <code>` (`cli/play.mjs`). Between them are
stateless functions: `api/relay.js`, `api/relay-play.js` and `api/relay-cleanup.js`, all in `lib/relay.js`. Nothing
runs between their calls.

## How it goes

1. The page opens a room (`op=open`). The room makes its own copy of the link's page as version 1, in the relay's
   store: the link's files go once the sharer sends it twice more, and the room's game must not go with them. Each file
   is read whole, held to the room's limits (a page past them is refused), and kept under its SHA-256, so the first
   change sends only the files it changed. A big page takes more than one call, so the copy is made a few files at a
   time, by `op=open` and then by the page's `op=seed` calls; one call copies at a time, under a lease in Redis. Only
   once the copy is whole does the room play and give a code. The page gets its own credential (`<room>.<secret>`),
   kept in that tab's sessionStorage.
2. The player runs `lamp play <code>` on their Mac. The code is six characters. It works once (it's taken out of
   Redis as it's read), for five minutes, with five tries a minute and thirty an hour from one address. It's traded for
   the helper's own credential, which the helper keeps beside its copy of the game (readable only by its user) so
   `lamp play --rejoin <room>` can take the room up again. Only hashes of credentials are kept.
3. The page sends each request with an id it made, so a request sent again is the one already taken. It asks for the
   room every two seconds while something's happening, and less often, up to every twenty seconds, while nothing is.
   The helper does the same, up to every fifteen.
4. The helper claims the request waiting first. Only one runs in a room at a time (`room.running`). It runs Claude
   Code on its own copy, confined as below. After a run that worked, it lists the copy's files with their sizes and
   SHA-256 (`op=upload`). The function checks the list whole: paths as the site takes a page's, at most 3,000 files,
   16 MB each, 64 MB together, 256 MB kept by the room. It then gives permission to send each file the room doesn't
   already keep, straight to Blob: a client token for that one path, size and type, for ten minutes, never over a file
   that's there. A function takes at most 4.5 MB, so the files never pass through one.
5. `op=commit` reads each new file back from Blob and checks its size and SHA-256. It writes the version's list of
   files, then moves the room to it in one step (a compare-and-set of the room). If anything is off, the room stays on
   the version it had, which goes on playing. A run that failed or changed nothing is said so (`op=finish`), and the
   helper puts its copy back.
6. Each room's game plays from a host of its own, `r-<room>.play.lamp.dev` (`/relay-play/<room>/<version>/<path>`),
   apart from every link's host and from lamp.dev. It's framed only by the site's pages, in a sandboxed frame. It
   serves the version the room plays and the one before (for a frame still on it), each file with the type its path
   says. It never sees a credential. The page's calls must come from the site's origin, and the helper's must not come
   from a browser at all.

## An AI app sending the whole game

`/change?with=app` (with `&w=<id>` to start from a link's page, or without it to start empty) opens a room for an AI
app on the player's computer instead of the helper. ChatGPT or Codex, say, running curl. There's no code and no
pairing. The page shows words to paste into the app, with the room's address and a key of its own. The key is a third
credential, apart from the page's and the helper's, and only its hash is kept. "New key" replaces it, and the old one
stops working at once. The page says when a version came in from the app.

"Change with ChatGPT" is the page's main control; the words to paste, with Copy and "New key", are folded under
"Use another AI app". The button is a `codex://new?prompt=` link carrying those words (`src/lib/change-words.ts`
holds them for both), which opens a new chat in ChatGPT's desktop app on the Mac with them in the message box, unsent.
The link carries the key on purpose, as the words do when pasted; it's kept out of PostHog's autocapture, and "New
key" rebuilds it. The link can't choose Codex, so the words say to switch to it when commands can't run.

The words are short. How to read, change and send the game, and what to do with each answer the relay can give, are in
a guide the site serves, `/change-guide.md` (`public/change-guide.md`): text the app fetches with `curl -fsS`, so a
missing guide stops the run, not a skill it installs. The words themselves carry what can't wait for it: that the
game's page is where the game goes and shows each version by itself, so the game is sent only to the room's address,
with no site-publishing skill, local server or separate preview (an app's own habits otherwise take over); then "read
the guide first"; the room's address and key; the game's name and the page; and the request. With a request, the app
goes ahead without asking; without one, it asks. The room keeps the link's name as it opens, and every answer about
the room (`op=open`, `state`, `postkey`) gives it as `name` (null for an empty room, or one opened before rooms kept
it, which the words call "the game"). The guide has the app work in a new folder of its own (`mktemp -d`), say it's
ready only after a send is taken, in one plain line, and remove only that folder and what it started.

`&app=claude` makes "Change with Claude Code" the main control instead: a `claude-cli://open?q=` link with the same
words (without the line about Codex), which opens Claude Code in a terminal with them typed in, unsent. Claude Code
takes at most 5,000 characters from it; the words with the longest idea stay under that (a test holds it). It answers
the link only once it has registered its handler, after a message is sent in it, and not when that's turned off in its
settings; the line under the button says so.

The link's page offers this beside sending an idea (SHARED_WISHES.md): "I want to make this change myself", then
ChatGPT or Claude Code, opens `/change?with=app&w=<id>&app=<app>#idea=<the idea>` in a new tab. The idea goes in the
fragment, which never reaches a server; an inline script on the change page moves it into the tab's sessionStorage and
takes it out of the address before analytics starts, and those links are kept out of autocapture.

- `GET /r/<room>/game` with `Authorization: Bearer <key>` gives the game's one file as plain text that never runs:
  `text/plain`, `nosniff`, `no-store`, a sandbox with nothing allowed, and the version it is as its `ETag`.
- `POST /r/<room>/game` with the key, `If-Match: "<that version>"` and the whole HTML file as the body. The body is
  at most 4,000,000 bytes, counted in bytes, of strict UTF-8 that reads as an HTML page. The answer is
  `201 {version, play}`, or one plain line saying what to do.
  - No If-Match gets 428, and a version that's moved on gets 412 with the version now.
  - `Idempotency-Key` is optional: without it, the same file sent on the same version is the one already taken (200,
    `again: true`).
  - Quotas: 30 games a room an hour, 120 an hour per address, and the room's 256 MB.
  - Vercel turns away a body over about 4.5 MB before the function runs, with its own 413.
- Only a game that's one file (`index.html`) goes back and forth whole. A room for an AI app isn't opened on a link
  whose page is several files (`op=open` answers 422 `not_one_file`), so an old page or a typed address fails at
  once; the link's page only offers it when its page is one file (`page.oneFile`). A room that somehow plays several
  files still answers both with 409, and points to `lamp play`.
- Publishing is one step. The file goes to Blob under a name of its own, and its list goes under an id of its own,
  written so it never overwrites anything. Neither is played until the room's compare-and-set points at it. That
  compare-and-set checks again, against the room it replaces, the key, the base version, the idempotency key, that no
  helper change is running, and the room's quotas. If two games are sent on the same version at once, one is played
  and the other gets 412. What a refused send wrote is left for the cleanup. The helper's commit publishes the same
  way.
- Anything a browser sends (an `Origin` or `Sec-Fetch-Site` header) is refused on top of that, but the key is what
  lets a call in.
- Played on its own host, a page's answer carries a sandbox too (`allow-scripts allow-same-origin allow-pointer-lock
  allow-forms allow-modals`), for when its address is opened by itself rather than in the page's frame. Same-origin
  is kept so a game's saves work on the room's own host.

### When the helper stops or loses lamp.dev

The helper keeps a journal of each request it took and how it ended. When it starts or comes back, it sends the
journal (`op=reconcile`). A request the room has as running, which the helper isn't running, is marked **uncertain**:
the page says so, and it's never run again. One running past twenty minutes with no word is marked the same way. The
helper then takes the room's word on every request into its journal.

## The agent

The helper stays static-only. Nothing of a game's is run on the Mac, and the agent has no shell. Claude Code runs with:

- `--restricted`, `--strict-mcp-config` with no servers, and `--tools Read,Edit,Write,Glob,Grep`;
- a PreToolUse hook (`cli/play-guard.mjs`) that refuses any other tool, and any path outside the copy once links are
  resolved;
- none of an agent's own files in the copy: no hidden files, and no `CLAUDE.md` or `AGENTS.md`.

What goes back holds no links and nothing shaped like a key. The Codex adapter is refused for any site that isn't on
this computer, since Codex reads outside the copy.

## Where it's kept

- **Redis**: an Upstash database of the relay's own (`RELAY_REDIS_REST_URL`, `RELAY_REDIS_REST_TOKEN`), never the
  shared wishes' one. It holds rooms, codes, the request journal, each version's list of files, and the quota counters,
  under `lamp:relay:{production|preview}`. A room runs out two hours after it was last used, and after a day whatever
  happens.
- **Blob**: a private store of the relay's own (`RELAY_BLOB_READ_WRITE_TOKEN`). Files go under
  `relay/<scope>/<room>/<upload>/<sha256>`, and a room's copy of the link's page under `relay/<scope>/<room>/seed/<sha256>`. They're never changed, and Redis holds only their paths.
- **Cleanup**: Redis lets a room run out, but Blob keeps its files. So `api/relay-cleanup.js`, run hourly by Vercel's
  cron with the project's `CRON_SECRET`, removes every file of a room that's gone. It leaves a room still copying the link's page alone, and otherwise removes files no version of
  a live room points at once they're older than twenty minutes.
- **Quotas** (`RELAY_QUOTAS`):
  - rooms: 10 an hour per address, 500 a day overall;
  - requests: 60 an hour per address, 5,000 a day overall, 30 in a room's life, 5 waiting at once;
  - uploads: 60 an hour per address.

## Setup (not done yet)

1. An Upstash Redis database for the relay, connected to the **lamp** project. Give its REST URL and token as
   `RELAY_REDIS_REST_URL` and `RELAY_REDIS_REST_TOKEN`.
2. A **private** Vercel Blob store for the relay, with its read-write token as `RELAY_BLOB_READ_WRITE_TOKEN`.
3. `CRON_SECRET` for the cleanup.
4. Hourly cron jobs need a plan that allows them (Hobby runs cron once a day).
5. The `*.play.lamp.dev` wildcard and `LAMP_PLAY_ORIGIN` that shared wishes already use (SHARED_WISHES.md).

Until 1 and 2 are set, `/api/relay` answers 503 and the page says lamp.dev isn't answering.

## Trying it locally

`npm run dev` answers the relay too, with its Redis and Blob kept in memory (`memoryRedis`, `memoryBlobs`).
`/__relay-blob/` stands in for Blob's upload address, and a room's game plays on `r-<room>.localhost`. Share a game to
the dev server (`LAMP_SITE=http://localhost:4321 lamp share <folder> --words "…" --no-picture --no-file`), open
`http://localhost:4321/change?w=<id>`, and pair with `LAMP_RELAY=http://localhost:4321 lamp play <code>`.
