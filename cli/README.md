# lamp, from a terminal

Runs an app from its folder and puts each saved change into it, for whoever is making it: a person, or a coding
agent in a terminal. A web app or web game is served and shown in a browser; a Mac app Lamp made in Swift is built
and run on the Mac. It needs no Lamp app open and has no dependencies (Node 20 or later).

```bash
node cli/lamp.mjs dev path/to/app --open
```

`npm link` in `cli/` makes it `lamp` everywhere. The folder is one Lamp made (its page is in `Web/`) or any folder
with an `index.html`; without one, the folder you're in.

| Command | What it does |
| --- | --- |
| `lamp new <folder> [--name "Its Name"]` | Makes a new web game's folder from Lamp's starting files. |
| `lamp init [--update]` | Puts Lamp's game runtime beside a page that's already there, changing none of the page's own files. |
| `lamp dev [--open] [--lan] [--port N]` | Runs the page and says how each change went. Each save goes into every open copy of it. `--open` opens a window for it; `--lan` lets other devices on the network open it. |
| `lamp open` | Shows the page in a window, running it in the background if it isn't running, and returns at once. |
| `lamp look [--reopen] [--wait s] [--json]` | How the changes since the last look went, a picture of the page, its screen as text, new errors and the log. `--reopen` opens the page again from its beginning first. |
| `lamp use key w 2` | Tries it as a person would, then looks: `click`, `type`, `key` (several at once with `w+d`), `drag`, `scroll`, `wait`, and in a game on Lamp's runtime `stick` and `button`, which hold Lamp's own controller as Lamp's app does (`window.__lampDrive`) and give it back when the person plays. Several moves with `then` between them go one after another, with one look at the end. |
| `lamp reload [--fresh]` | Opens the page again from its files, a game from where the player is, or with `--fresh` from its beginning (`window.lampFreshStart`). |
| `lamp stop` | Stops running it. |
| `lamp share --words "…"` | Puts the page on lamp.dev: anyone with the link plays it there and can send an idea. Again, it sends the page as it is now to the same link. |
| `lamp ideas [in <n> \| dismiss <n>]` | The ideas people playing the link have sent, and saying what became of one. |
| `lamp unshare` | Takes the link down. |
| `lamp setup [--remove]` | Teaches Claude Code and Codex on this computer to work this way: a skill for each. |
| `lamp guide` | What that skill says, for any other agent. |
| `lamp skills [word]`, `lamp skill <name>` | Lamp's skills (`Resources/skills`), the one place that says which building blocks to use and how: all of them or those about a word, and one in full, put together from its sections as Lamp's app does (`cli/skills.mjs` follows `Skills.assembled`). |

## For a coding agent

```bash
node cli/lamp.mjs setup
```

writes one skill, [`skill/SKILL.md`](skill/SKILL.md), where each agent found on the computer reads its skills
(`~/.claude/skills/lamp`, `~/.codex/skills/lamp`), with the command as it's run on this computer filled in. From its
next session the agent uses lamp by itself in an app's folder: it opens the window for the person, changes the
files, looks after each change, and tries the app only when asked to. `lamp setup` replaces only a skill it wrote,
and `--remove` takes it away. That file is the one place that says how an agent works with lamp; `lamp guide`
prints it for an agent that has no skills.

## How a change goes in

Files are watched; a save is handed to every open page a moment later.

- **A game made with Lamp's runtime** (`lamp-game.js` beside the page) takes it the way it does inside Lamp. The
  runtime is handed the change exactly as Lamp's app around the page hands it over (`window.__lampLive`), so nothing
  in the game differs. A module that accepts changes is swapped in while the game runs (`live`); other code runs
  again with the player where they were (`reran`); what can't go in either way opens the page again from the
  player's place (`reopened`); and a game at a moment it can't be interrupted waits for the person's Reload (`held`).
- **Any other page** opens again.

## Lamp's own files beside a game's page

Lamp's app writes some files beside a game's page at every build. A folder that came from Lamp has them, and
`lamp new` writes them into the folder it makes, so the folder is a whole site that runs wherever it's served from.
What a game's folder lacks all the same, the server gives it:

| File | Where it comes from here |
| --- | --- |
| `lamp-device.js`, `lamp-build.js` | Made by the server: the device is a browser on any device, as a page published to the web is given, and the build is named for the files as they are. |
| `lamp-controllers.js` | `cli/lamps/lamp-controllers.js`, the list of controllers as Lamp writes it (`Controllers.pageJS`). `CLIFilesTests` fails when the two differ, and writes the copy again when run with `LAMP_WRITE_CLI_FILES=1`. The game runtime can't load without it. |
| `three/`, `phaser/`, `rapier/` | Lamp's copies (`Resources/WebLibraries`), for a library the page asks for and the folder has none of. |
| `lamp.js` | A stand-in that holds nothing. Lamp's building blocks for a page (AI, saved data, the app's files) are code in Lamp's app and reach the page through it, so a page that uses one says so in its errors. |

A file the page asks for that neither the folder nor Lamp has is logged as an error, since a module that imports one
never runs and the page can't say so itself.

## A new game

`lamp new` copies what Lamp gives a new web game: the starting page (`Resources/GameKit/scaffold-web`), the game
runtime (`Resources/GameKit/web`), the libraries its import map names (three.js and Phaser), and Lamp's own files
beside the page (the table above). `lamp init` gives a page that's already there the same, the starting page aside. The page is at
the top of the folder with nothing that builds it, which is what Lamp's app opens as a site (`StaticSite.isPlain`).
It isn't yet an app as Lamp's app makes one: it has no manifest and none of the app around the page, which Lamp's app
adds when it takes the folder on. A plain web page needs no starting files.

A change saved while a page is opening isn't lost: each page says which change its files had, and is handed what came
after. A server started again tells its pages to open again, since it can't know what changed while it was away.

## Looking and using

`lamp look` is how whoever made a change checks it. It checks every file first (a look straight after a save can
come before the system says the file changed), waits for the page to finish taking the change in, and answers:

- how each change since the last look went in, in the words above, and why;
- a picture of the page, one pixel a point, so a point of the picture is a point to click (each look's is a file of
  its own, and the last forty are kept);
- the screen as text: each control and canvas with the point at its middle, and the words shown;
- the errors and the log since the last look.

What it looks at:

1. **The window `lamp open` or `lamp dev --open` opened**, when there is one: what the person sees, where they are in it.
2. **A copy of the page with no window**, which lamp starts for itself otherwise and closes ten minutes after it was
   last looked at. It starts where the page starts.
3. With no browser lamp can drive on the computer, **a page open in any browser** says what's on it, without a picture.

The window and the copy are a Chromium-family browser already on the computer (Chrome, Edge, Brave, Chromium;
`LAMP_BROWSER` names another), started with files of its own, never the person's own browser profile, and spoken to
over a pipe only lamp holds. `lamp use` acts in the same page, so with a window open the person sees it happen.

`lamp open`, `lamp look` and `lamp use` start `lamp dev` in the background when it isn't running. That one ends by
itself half an hour after it was last used, unless its window is open, and a `lamp dev` run by hand takes its place
when it has no window.

## A Mac app

A folder with `Package.swift`, `build.sh` and `Sources/` and no page is an app Lamp made in Swift (`cli/mac.mjs`).
The folder holds all it takes, so nothing of Lamp's app is run:

- **Building** is the app's own `build.sh`, which Lamp writes: it makes `build/<Name>.app`. lamp asks first for the
  build Lamp's app makes while an app is being changed (`LAMP_LIVE`: a debug build of a copy of the sources in
  `.lamp/live`, a few seconds for a small change), and when that doesn't build, for the plain one, whose errors are
  in the app's own code at its own lines. An app whose copy doesn't build though its code does is built plainly from
  then on.
- **The app takes lamp for its Lamp.** Its support code reads where Lamp is from `LampInstall` in its Info.plist,
  which Lamp's app writes into every copy it installs (`Template.installValues`). lamp writes those values into the
  built app and signs it again: its folder, a token only the two have, and a name for what they say to each other.
- **Looking** is the app's own doing: asked with a notification as Lamp's app asks (`snapshot`), it pictures its own
  windows and writes what's on them as text beside its log, in the folder's `.lamp/runtime`. No permission is asked.
- **Using** is the app's own driver (`LampDriver`): the actions go as Lamp's app sends them (`useApp`), signed with
  the token, and the app answers what it did.
- **A change** builds the app again and opens it again. The app's own build writes `build/`, `.build/` and
  `.lamp/` in the folder, as it does under Lamp's app.

What stays Lamp's app's for a Mac app: putting a change in while it runs (`LiveReload`), what the app asks of Lamp
on its port (AI, secrets, sharing: here nothing answers, which the app takes as Lamp not running), signing for a
team, the chat beside the app, and making a new one (its files are written from `Template.swift`).

## Sharing

`lamp share` is Lamp's side of the site's API, as `Sources/Lamp/WishLink.swift` is in Lamp's app
(`cli/share.mjs`; the limits are read from `site/lib/shared-wishes.js`, so the two can't disagree): the link's words
and a picture of the page, then the page itself, zipped and sent in parts, which the site unpacks and plays on a host
of the link's own.

- **What goes up** is the page as it's served: every file in its folder (nothing hidden, no link followed, `APP.md`
  left out), and for a game Lamp's own files beside it, as Lamp's app stages a page it publishes (`GamePage.stage`).
- **The picture and the shape** come from the page as it runs: a picture of it for the link's card, and the stage a
  game is drawn on (its width over its height) or `fill` for a page that takes any window. A page that's logging
  errors isn't shared without `--anyway`.
- **The link's secret**, which is what lets it be changed or taken down, is kept with lamp's state for the folder
  (`link.json`, readable only by the person), never in the folder.
- **Not sent:** the wish's own file, which only Lamp's app makes. The link plays the page and carries its words.
- **`LAMP_SITE`** names another site to share to, for trying this against a copy of the site (`npm run dev` in
  `site/` keeps links in memory). The tests run against the site's handlers the same way, and never reach lamp.dev.

## Where things are kept

- **Nothing in a page's folder.** lamp reads the folder and never writes in it (`lamp new` and `lamp init` aside,
  which are asked to; a Mac app's folder takes its own build, as above), so nothing of
  lamp's is committed or published with it, and a folder Lamp's app is running too keeps its own log.
- **Everything lamp keeps** (the page's log, which `lamp look` names; the browser's files, so a game's saves last
  from one run to the next; the last few pictures; which server is running) is in
  `~/.lamp/dev/<folder's name>-<hash>/`. `LAMP_DEV_HOME` moves it.
- **The port** is the folder's own, from its path (4400 to 4899), or the next free one, so two apps run side by side.
  A folder keeps its port from run to run, since a game's saves belong to the address.

## Who it answers

The server listens on this computer only, unless `--lan` is given. It answers requests made to its own name
(`localhost`, and with `--lan` the computer's names on the network), nothing sent by a page of another site, and
never a hidden file, one outside the page, or one a link in the folder points to elsewhere. `look`, `use`, `reload` and `stop` need a token only lamp's own commands
can read.

## What it doesn't do yet

Phones, TVs and consoles as places to run, and anything that needs Lamp's Mac app around the page (`lamp.js`'s
building blocks, `LampNative`, a game's phone controllers).

## Tests

```bash
node --test cli/tests/*.test.mjs
```
