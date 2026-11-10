# lamp, from a terminal

Runs an app from its folder and puts each saved change into it, for whoever is making it: a person, or a coding
agent in a terminal. A web app or web game is served and shown in a browser; a Mac app Lamp made in Swift is built
and run on the Mac. It needs no Lamp app open and has no dependencies (Node 20 or later).

```bash
node cli/lamp.mjs dev path/to/app --open
```

`npm link` in `cli/` makes it `lamp` everywhere. The folder is one Lamp made (its page is in `Web/`), one in Lamp's
format (its `lamp-app.json`, at its top or in a site's `.lamp-wish/`, says what it is: a web app, a game, a screen or a
Mac app, `projectOf`), or any folder with an `index.html`; without one, the folder you're in. A kind lamp doesn't run
(an iPhone app, an app for both, Android, a TV app) or a wish of several apps is said so, to open in Lamp's app.

| Command | What it does |
| --- | --- |
| `lamp new <folder> [--name "Its Name"] [--web \| --mac]` | Makes a new web game's folder from Lamp's starting files, or with `--web` a new web app's, or with `--mac` a new Mac app in Swift. |
| `lamp init [--update]` | Puts Lamp's game runtime beside a page that's already there, changing none of the page's own files. |
| `lamp unpack <file.lampapp> [folder]` | Unpacks a Lamp app file into a new folder beside it, named for it. A file carries none of Lamp's own files: a page gets them beside it as it's unpacked (the runtime for a game, lamp.js, the libraries its import map names), and a Mac app gets Package.swift, build.sh and LampSupport.swift from Lamp's starting files as it's first built (`writeMacStarter`), where it has none. One with a widget, a share extension or a 3D scene is left to Lamp's app, which writes the files they're built with. |
| `lamp export [--to file] [--anyway]` | Makes the app's Lamp app file as Lamp's Share… does (`Sharing.export`, followed by `cli/lampapp.mjs`): its own files as its kind travels, Assets/, APP.md, what it declares, its credits with the app added to the chain, the licenses they name, its icon's design and lamp-app.json, never Lamp's own files. Refused when a license its credits name is gone or something in it is shaped like a key; `--anyway` sends work its credits give no license for. |
| `lamp dev [--open] [--lan] [--port N]` | Runs the page and says how each change went. Each save goes into every open copy of it. `--open` opens a window for it; `--lan` lets other devices on the network open it. |
| `lamp open` | Shows the page in a window, running it in the background if it isn't running, and returns at once. |
| `lamp open --in-lamp` | Gives a Mac app to Lamp's app (`cli/outside.mjs`), over the socket the person's own coding agent uses (`OutsideServer`, `OutsideWork`): `open_project` takes the folder on, with Lamp's review the first time, and from then on `look`, `reload` and `dev` call `apply_change`, so a change goes into the open app as Lamp's app puts it there (`LiveReload`) and its outcome is said: live, held, reopened, not_built, crashed. `use` calls `use_app`, in plain sight in the app Lamp's app has open, and `stop` calls `close_app`. A folder Lamp's app no longer has (its refusal says `taken_on: false`) is lamp's own again, said once. `lamp open --here` has lamp run its own copy again. `LAMP_APP` names another Lamp by its bundle id (a Lamp Dev instance). A Mac app `lamp new --mac` makes has the `lamp-app.json` Lamp's app takes a folder on by. |
| `lamp look [--reopen] [--wait s] [--json]` | How the changes since the last look went, a picture of the page, its screen as text, new errors and the log. `--reopen` opens the page again from its beginning first. |
| `lamp use key w 2` | Tries it as a person would, then looks: `click`, `type`, `key` (several at once with `w+d`), `drag`, `scroll`, `wait`, and in a game on Lamp's runtime `stick` and `button`, which hold Lamp's own controller as Lamp's app does (`window.__lampDrive`) and give it back when the person plays. Several moves with `then` between them go one after another, with one look at the end. |
| `lamp reload [--fresh]` | Opens the page again from its files, a game from where the player is, or with `--fresh` from its beginning (`window.lampFreshStart`). |
| `lamp stop` | Stops running it. |
| `lamp share --words "…"` | Puts the page on lamp.dev: anyone with the link plays it there and can send an idea. Again, it sends the page as it is now to the same link. |
| `lamp share` (an app of Lamp's) | For a folder in Lamp's own (or a link to one), shared by Lamp's app over its socket (`share_link`, `OutsideWork`): its Share Link card filled as it fills itself (`WishLinkCards.prepare`: the link's last words, the questions and what's new Lamp writes, the app's file, the GitHub release) and shared without its window, with `--line`, `--by`, `--asks`, `--notes`, `--no-file`, `--no-github`, `--put-on-github` in place of the card's own, and `--preview` to see it first. The link's secret stays in Lamp. Which Lamp is the one whose folder it is (`lampOwning`). |
| `lamp ideas [in <n> \| dismiss <n>]` | The ideas people playing the link have sent, and saying what became of one. |
| `lamp unshare` | Takes the link down. |
| `lamp devices [add \| forget <name>]` | The person's devices lamp puts a page on: an Xbox in Developer Mode (those set up and those found on the network), and Android (lamp's emulators, and the phones, tablets and TVs plugged in with USB debugging on). `add` sets one up, a step at a time; `add android` downloads Android's tools. |
| `lamp open --on xbox` | Packages the page, installs it on the device and opens it there. `lamp look --on xbox` is the device's screen and the app's log there, `lamp stop --on xbox` ends it, and `lamp remove --on xbox` takes it off. |
| `lamp open --on android [--hidden]` | Builds Lamp's Android app around the page and opens it in lamp's Android emulator (`--on android-tv`: its TV emulator; a device of the person's by its name), with `look`, `stop` and `remove` as on any device, and `lamp use --on android` to tap, type and press there. `--hidden` starts the emulator with no window. |
| `lamp setup [--remove]` | Teaches Claude Code and Codex on this computer to work this way: a skill for each. Says so when the computer has no browser lamp can drive, which web apps and games are looked at and played in; it's advice, never a failure. |
| `lamp guide` | What that skill says, for any other agent. |
| `lamp blocks [Name]` | Lamp's building blocks for a Mac app, each with what it's for, or one in full: read from the app's own `Sources/LampSupport.swift`, whose comments say how each is used. |
| `lamp skills [word]`, `lamp skill <name>` | Lamp's skills (`Resources/skills`), the one place that says which building blocks to use and how: all of them or those about a word, and one in full, put together from its sections as Lamp's app does (`cli/skills.mjs` follows `Skills.assembled`). |

## For a coding agent

On a Mac with Lamp, the lamp to set up is the one in Lamp's app, which updates with Lamp and runs on the app's own
runtime, so no Node is needed:

```bash
/Applications/Lamp.app/Contents/Resources/cli/lamp setup
```

On a computer without Lamp, lamp comes from npm, `npm install -g @lampdotdev/lamp` (it needs Node 20), and
`lamp setup` sets it up the same way. From a checkout of this repository, `node cli/lamp.mjs setup`.

The npm package is laid out as the repository is (`scripts/npm-package.sh <version>` packs it into `build/npm`, and with
`--publish` publishes it): `cli/` with the files only Lamp's code makes written first (`scripts/cli-files.sh`), the
site's limits for a link, and the Lamp resources lamp reads, with their licenses. A copy npm installed asks npm's
registry for a newer one at most once a day, in a process of its own that never holds up the command, and the next
command says so in one line, once a day, with the command that updates it (`cli/update.mjs`). It never updates itself.
The copy in Lamp's app updates with Lamp and a checkout with its repository, so neither asks; nor does one in CI, or
with `LAMP_NO_UPDATE_CHECK` set.

writes one skill, [`skill/SKILL.md`](skill/SKILL.md), where each agent found on the computer reads its skills
(`~/.claude/skills/lamp`, `~/.codex/skills/lamp`), with the command as it's run on this computer filled in. From its
next session the agent uses lamp by itself in an app's folder: it opens the window for the person, changes the
files, looks after each change, and tries the app only when asked to. `lamp setup` replaces only a skill it wrote,
and `--remove` takes it away. That file is the one place that says how an agent works with lamp; `lamp guide`
prints it for an agent that has no skills.

Lamp's app carries the whole of lamp (`build.sh`): its modules, `page.js`, the skill, and in `lamps/` the controllers'
list and the files only Lamp's code makes, written by the app itself as it's built (`Lamp --cli-files`, `CLIFiles`), with
`lamp` beside them, a launcher on pi's runtime (`cli/lamp.sh`: pi is Bun with `BUN_BE_BUN`). Lamp's resources are found
beside the copy either way (`RESOURCES`: the repository's `Resources/`, or the bundle's). The skill that copy writes
names its launcher, so the agent always runs the lamp of the Lamp that's installed.

## How a change goes in

Files are watched; a save is handed to every open page a moment later. `APP.md` at the page's top is the app's
notes, never part of the page, so saving it hands nothing over; any other Markdown may be content the page loads, and is a change.

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
| `lamp.js` | Lamp's building blocks for a page (saved data, the app's files, AI through Lamp's app), as Lamp's own code writes them: `scripts/cli-files.sh` writes the file out (`cli/lamps/lamp.js`, and `lamp-for-games.js` as a game is given it, without a TV's remote; not committed, since they change often), and without it a stand-in that holds nothing. What a block asks of Lamp's app as the page runs (its AI) isn't answered here. |

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
3. With no browser lamp can drive on the computer, **a page open in any browser** says what's on it, without a picture,
   and `lamp use` can't act in it. A look with no page open yet waits for one, as long as it's given to wait. `open`,
   `look`, `use` and `setup` each say that Chrome, Edge, Brave or Chromium is what's missing (`noBrowser` in
   `cli/browser.mjs`).

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
- **A change** to what the build reads (the code, the package, the app's own files) builds the app again and opens
  it again. The app's own build writes `build/`, `.build/` and `.lamp/` in the folder, as it does under Lamp's app.

- **A new one** (`lamp new --mac`) is a copy of the folder Lamp's app makes for a new Mac app (`Template.scaffold`),
  under the app's own name; `lamp new --web` is the same for a web app's page (`ScreenKit.fill`, `cli/lamps/web-starter`). Those files are Lamp's own code's doing, and its building blocks change often, so the copy
  isn't kept in the repository: `scripts/cli-files.sh` writes it (`cli/lamps/mac-starter`, through `CLIFilesTests`)
  from the code as it is, and `lamp new --mac` says to run it when there's none.

- **The build is fenced in**, as it is under Lamp's app: it runs under `sandbox-exec` with Lamp's profile for a
  build (`Sandbox.profile`, here `buildProfile`), which closes every person's files and opens the app's own folder
  and what a build needs, with Lamp's `swift` in front of the real one, since SwiftPM's own sandbox can't start inside
  another. What the build made is then copied out of the folder, to lamp's state for it, and that copy is given the
  values and run: what only lamp and the app have is never in the folder for a later build to read, and the app that
  runs is never one a build changed after it was made.

One difference from Lamp's app remains for an app that came from someone else. Lamp's app writes `build.sh`,
`Package.swift` and `LampSupport.swift` afresh before every build (`Template.writeOwnedFiles`), so nothing a folder
brought with it in those files ever runs. lamp runs the folder's own, inside the fence: they can do what a build
can, in the app's folder and the temporary folders, and no more.

- **What the app asks of Lamp** as it runs goes to lamp's server for the folder (`LampInstall.port`), shown the
  token. Its secrets (`LampSecrets`, `/app/secrets`) are kept for it with lamp's state for the folder, readable only
  by the person, as Lamp's app keeps them for an app whose own Keychain items macOS ties to one build; and its Reload
  (`/app/reload`) is told no change is waiting, so the app opens itself again. Its AI (`/ai/…`), sharing and the rest
  aren't answered yet: the app is told so, and the log says what it asked for.

What stays Lamp's app's for a Mac app: putting a change in while it runs (`LiveReload`), its AI and sharing, signing
for a team, and the chat beside the app.

## Sharing

`lamp share` speaks the site's API through `cli/link.mjs`, the one place Lamp does, for lamp and for Lamp's app's
Share Link card alike (`WishLink` asks it: the `link…` calls); the limits are read from `site/lib/shared-wishes.js`, so
the two can't disagree, and `build.sh` puts that file and the one it reads beside lamp in the app. `cli/share.mjs` sends the link's words
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

## Devices

A page goes on one of the person's devices through the device's integration, the same file Lamp's app reads
(`Resources/Devices/*.json`): how the device is found, its setup steps, and the requests that install, open, picture
and remove an app. Nothing in one is code: `cli/devices.mjs` runs it (`Runner`), for lamp and for Lamp's app alike
(`IntegrationRunner` asks it), so a change to an integration reaches both. An Xbox is the only device lamp puts a page on
itself so far (`takesPages`): the one whose host for a page lamp packages for.

- **Finding** is one SSDP search of the home network, with each answer read as its integration says
  (`searchNetwork`: its search target, a Bonjour service, or a page on the device holding words; then its identity
  read from the device's description or its own pages), and for Lamp's app the devices no integration knows, read
  from their UPnP descriptions. Bonjour is asked as a one-shot mDNS question from a port of lamp's own, which each
  device answers there, so nothing listens on mDNS's own port. A device found is only shown; it's kept once a setup
  step has passed on it, and only a kept one is ever sent anything.
- **Setting up** (`lamp devices add`) takes the device through its integration's steps in order. What a step asks the
  person to type (an Xbox's Device Portal password) is read from the terminal without being shown, so an agent can't
  give it: run without a terminal, the command says the person runs it themselves.
- **The guards** are the ones every request to a device has, Lamp's app's too, since this is where a request is
  made for both ("Lamp's app", below): a request goes only to the address the device was found at,
  which must be on the home network and never this computer; no redirect is followed; over HTTPS the device's own
  certificate is kept the first time, per port, and another refused from then on unless the device's own root, read
  over that first connection, signed it (an Xbox makes itself a new certificate at each restart); and the password
  goes only to a device whose certificate is kept, in answer to the device's own request for it (as it is to a
  device that asks plainly, and to one that asks for a digest only what its challenge makes of it).
- **A request** is HTTP/1.1 written out by hand on a connection lamp opened itself (`exchange`), so it goes down the
  very connection whose certificate was just checked, and runs the same on Node and on Bun. Nothing in it may end a
  line: the path whole and each header are checked before anything is sent.
- **The package** (`cli/msix.mjs`) is the one package maker, Lamp's app's too ("Lamp's app", below): the manifest,
  the block map, the content types, the Zip64 layout and the Authenticode signature, under a key and certificate of
  lamp's own, which the console installs beside the package. `cli/tests/fixtures/msix` keeps one small package's
  manifest and signature as Lamp's Swift code made them before this took its place, under a key made for that alone,
  and `cli/tests/msix.test.mjs` makes the same package and compares: the signature signs the hashes of every record,
  the directory, the block map and the content types, so one that matches says the whole package does.
- **What's in it** (`cli/place.mjs`) is Lamp's web host for the console (`Resources/WebHost`, as it ships), and under
  `Web/` the page as `lamp share` gathers it, with `lamp-device.js` saying it's on an Xbox (the integration's
  `input`, as `GamePage.descriptor` writes it). A page with `lamp-game.js`, or whose folder's `capabilities.json` says
  `"game": true`, is installed as a game, which the console gives more memory and its whole GPU.
- **Installing** follows `DeviceApps.install`: the copy there is ended, the new one sent and waited for, then
  launched until the console lists it running, since a console only just done installing refuses for a while. Each
  package is a newer version than the last, so it replaces it.
- **Looking** (`lamp look --on xbox`) is the bridge's `look` and `log`: the console's screen, whatever is on it, and
  the log Lamp's host keeps of the page's console there.
- **Not here yet:** where Lamp is isn't written into the page's `lamp.js` (`DeviceSupport.fill`), so its AI isn't
  answered on the console; a game's phone controllers; a wish's other apps; and the test run a device's setup
  offers in Lamp's app.

## Android

A page goes on Android in Lamp's Android app around it (`GameAndroid` in Lamp's app): one app for phones, tablets and
TVs, which serves the page from its own assets in a WebView, reads the controllers itself and hands them to a game's
runtime, and sends the page's console to the device's log. `cli/android.mjs` does what Lamp's app does to build it
and put it somewhere.

- **The app's files are Lamp's own**, written out by `scripts/cli-files.sh` (`cli/lamps/android-host`, not committed):
  its Gradle files, its manifest and activity for a game and for any other page, and the list of tools Lamp builds
  with (`tools.json`: the versions, where each is downloaded from and its checksum). lamp fills in the app's names as
  `Template.write` does. Without that folder, or off a Mac, `--on android` says so.
- **The project** is written in lamp's folder for the app (`~/.lamp/dev/<app>/android/`), never in the app's: Lamp's
  host, and the page's files as `lamp share` gathers them, with `lamp-device.js` saying it's on Android. Nothing in
  the app's folder runs in the build. A file is written only when it changed, so a build after a small change is a
  few seconds. The package is `dev.lamp.cli.<the app's id>`, lamp's own, so a copy lamp installs never takes the
  place of one Lamp's app installed.
- **The tools** are the ones every Lamp on the Mac shares (`~/Library/Developer/Lamp/Android`: Java, Google's
  command-line tools, Gradle, the platform, the emulator and its images), and so is Gradle's cache
  (`~/Library/Caches/Lamp/gradle`). `lamp devices add android` downloads whichever are missing, as
  `AndroidTools.install` does: each archive checked against the checksum its maker publishes, then Google's packages
  through its own package manager. That accepts Google's terms for them, so it asks first, and only at a terminal:
  an agent can't answer for the person.
- **lamp's own** (`~/.lamp/android/`, `LAMP_ANDROID_HOME` moves it): its adb server's key to the person's devices,
  and its emulators, a phone ("android") and a 1080p TV ("android-tv"), each made the first time a page opens in it
  and a few gigabytes once it has run. Its adb server and its emulators are on ports no Lamp's app uses, and it
  doesn't look for emulators on adb's usual ports: those are the person's, or another Lamp's.
  `lamp devices forget android` closes the emulators and removes that folder.
- **The emulator** opens as a window of its own, where the person plays. `--hidden` starts it with no window and no
  sound, for a check nobody watches; `lamp stop --on android` then closes it too, since nobody could. In lamp's own
  emulator Android's first-time tip on leaving full screen is taken as read, so it doesn't cover the first look.
- **A device of the person's** is one adb lists: plugged in, with USB debugging on, and this computer allowed on it
  (it asks on its own screen, once for lamp). It goes by its name, or adb's serial for it. Connecting one over Wi‑Fi
  isn't here yet.
- **Looking** is the device's screen as a picture, whether the app's process is running, and what the page said
  since it was opened (its console, which Lamp's host logs, and how Android ended the app if it did).
  **Using** is adb's own input: a tap or a drag at a point of the picture, typing, one key, or one of a controller's
  buttons, which the host hands the game as a controller's. There's no stick, and nothing is held with another.
- **Not here yet:** the page's AI (the app is told where Lamp is as it's installed, `Adb.tellApp`, and lamp has no
  gateway), a wish's other apps, connecting a device over Wi‑Fi, and an Android app written in Kotlin.

`cli/tests/android.test.mjs` holds what lamp writes and what it asks of Gradle and adb, with stand-ins for both; it
runs where `cli/lamps/android-host` has been written.

## Lamp's app

What lamp does, Lamp's app has it do, rather than doing the same again in Swift. The way in is `cli/calls.mjs`, run
once for each call (`LampCLI.call` in Lamp's app): the call's name is its argument, what it's given is one JSON object
on standard input, and its answer is the last line it prints, `{"done": …}`, or `{"problem": "…"}` in a sentence for
what the person can put right. Anything else ends the run with its words on standard error, which Lamp's app shows as
its own fault.

The many small things are asked of one run that stays (`calls.mjs --serve`, `LampCLI.ask`): a line in for each,
`{"id", "call", "given"}`, and a line out as each finishes, in any order; `{"stop": id}` lets go of one whoever asked
no longer wants (a task cancelled in Lamp's app), and the run ends when its input does, which is when Lamp's app
does. A problem says its kind where Lamp's app acts on which it was: a device that's away, a certificate that changed.

- **What a call is given** is paths in Lamp's own folders, laid out by Lamp's app, never an app's folder: what an
  agent wrote is read by Lamp's app on that folder's terms first. A call refuses a link in what it's handed.
- **The runtime** in Lamp's app is the one it already carries: its bundled agent is built on Bun, and run with
  `BUN_BE_BUN=1` that program is Bun itself (`LampCLI.launch`, the one place that decides). So `calls.mjs` and what it
  imports must run on Bun as well as Node; `build.sh` copies `cli/*.mjs` into the app. The tests run on both. Run
  from a copy of Lamp's app, the command line is that app to macOS: it's on the local network only once the app is
  allowed there (a search before that hears nothing, and a request to a device gets no answer).
- **The calls so far:** `msix`, an Xbox's package from a folder of files; `send`, one request to a device, with the
  file its certificates are kept in named by Lamp's app (`pinsAt`), so each device has one store whichever asks
  (what the person typed for a device comes with the request, on the run's input, and is kept nowhere here); `look`,
  one look at the home network for the integrations Lamp's app gives it, with the TVs that answered read as a
  Samsung's API and an LG's descriptions say (`tvsIn`, cli/network.mjs); `tv`, a Samsung TV read again; `search`, a
  search for one target; `probe`, whether a device is there now, as a setup step's check asks; `run`, `open`, `putBack` and `check`, an
  integration's sequences and a setup's checks on one device, with the values Lamp's app fills in (what the person
  typed, from its own store, on the call's input) and, while a call waits on the device, an event that says so; `network`, the sweep
  of this computer's subnet and every Bonjour service (cli/mdns.mjs); and `neighbours`, the gateway and subnet now.
  Two things stay in Lamp's app, since only it can see them: whether macOS lets Lamp look at all, which is
  Network.framework's to say (`DeviceProbe.localNetworkDenied`), and the neighbor table, which macOS shows only to a
  process it lets on the local network, and the runtime Lamp carries isn't one (`Neighbours`). Moving a
  piece of work here means a call for it, the Swift that did it deleted, and a test on each side
  (`cli/tests/calls.test.mjs`, `LampCLITests`).

## Where things are kept

- **Nothing in a page's folder.** lamp reads the folder and never writes in it (`lamp new` and `lamp init` aside,
  which are asked to; a Mac app's folder takes its own build, as above), so nothing of
  lamp's is committed or published with it, and a folder Lamp's app is running too keeps its own log.
- **Everything lamp keeps** (the page's log, which `lamp look` names; the browser's files, so a game's saves last
  from one run to the next; the last few pictures; which server is running) is in
  `~/.lamp/dev/<folder's name>-<hash>/`. `LAMP_DEV_HOME` moves it. What lamp made of the app for a device (its
  package, and which version the device has) is in `device/` there, and its Android project and build in `android/`.
- **The person's devices** are in `~/.lamp/devices/` (`LAMP_DEVICES_HOME` moves it), readable only by them: each
  device's record, its kept certificates and what was typed for it, and lamp's key for signing packages. They aren't
  Lamp's app's: a device set up in one is set up again in the other.
- **The port** is the folder's own, from its path (4400 to 4899), or the next free one, so two apps run side by side.
  A folder keeps its port from run to run, since a game's saves belong to the address.

## Who it answers

The server listens on this computer only, unless `--lan` is given. It answers requests made to its own name
(`localhost`, and with `--lan` the computer's names on the network), nothing sent by a page of another site, and
never a hidden file, one outside the page, or one a link in the folder points to elsewhere. `look`, `use`, `reload` and `stop` need a token only lamp's own commands
can read.

## What it doesn't do yet

iPhones, and Samsung and LG TVs, as places to run; an app's AI and a game's phone controllers; and putting a change
into a Mac app without opening it again.

## Tests

```bash
node --test cli/tests/*.test.mjs
```
