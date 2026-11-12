---
name: lamp
description: Make, run, see and try an app with lamp's command line - a web app, a web game, or a Mac app Lamp made in Swift. Use when the person asks for a new web game, or when working in a folder made with Lamp (a page beside lamp-game.js or in Web/, or Package.swift with build.sh and Sources/LampSupport.swift) or in a plain site's folder and they ask to change the app, to see it, or to check that a change works. Every saved change goes into the open app, and a game keeps the player's place.
---

# Working on an app with lamp

`{{lamp}}` runs the page in the app's folder and puts each change into it while it's open. Save a file and the change
goes in. Never build, restart or reload anything for a change.

Run the commands from the app's folder, or give the folder after the command (`{{lamp}} look path/to/app`).

Most of this is about an app that is a web page: a web game, a web app, a plain site. An app Lamp made that way has
the page in `Web/`, beside the Swift of the app around it, which stays as it is. An app whose own screens are Swift
is a Mac app: "A Mac app" below says what's different for one.

## A new game

`{{lamp}} new path/to/folder --name "Its Name"` makes a new web game's folder from Lamp's starting files: the game
runtime (`lamp-game.js`), three.js and Phaser, `APP.md`, and a page that shows a card until the game replaces it. The
page is at the top of the folder: what Lamp's skills call `Web/` is the folder itself.

Before writing, read Lamp's `web-game` and `game-feel` skills, which are for every game, and `game-playtest` when
you're asked to play it; "Lamp's skills" below says what in them is Lamp's app's doing. The card's `game.js`,
`world.js` and `making.js` are yours to replace, as `web-game` says.

The card is a small game of its own, and the runtime keeps what it registered (a state called `play`, a camera)
through a change, as it would the player's place. So write the whole game before the first look, and make that look
with `--reopen` (`{{lamp}} look --reopen`): the game then opens from its beginning, not from the card's. If you
looked earlier, `--reopen` puts it right.

## A new web app

`{{lamp}} new path/to/folder --web --name "Its Name"` makes a new web app's page from Lamp's starting files:
`index.html`, `style.css` and `app.js`, which are yours to write, `APP.md`, and `lamp.js`, Lamp's building blocks for
a page (saved data with `LampStore`, the app's files and more). Read Lamp's `web-app` skill before writing it, and
the comments in `lamp.js` for how each block is used; never edit `lamp.js`. Its AI (`LampAI`: ask, act, decide) is
answered by lamp itself on this Mac, with the person's own Claude Code or Codex, in every page lamp runs here (`dev`,
`open`, `look`, `use`); pictures and hearing need Lamp's app. Shared on lamp.dev, it's answered on the computer the page is played on while `{{lamp}} ai` runs there in a terminal, once the person allows that page. Never put a key or a model provider's address in the page. A page that wants none of Lamp's needs no starting files: write its
`index.html` in an empty folder.

## A Mac app

A folder with `Package.swift`, `build.sh` and `Sources/LampSupport.swift` and no page is a Mac app Lamp made in
Swift. `{{lamp}} new path/to/folder --mac --name "Its Name"` makes a new one: Lamp's building blocks, and a card it
shows until its code in `Sources/` is written. The same commands work on it, with these differences:

- **Lamp's building blocks** are what the app is made with: saved data, AI, windows, the menu bar and the rest.
  `{{lamp}} blocks` lists them with what each is for, and `{{lamp}} blocks LampStore` says how one is used: read the
  ones the app needs before writing it. Lamp's `building-blocks` and `app-kinds` skills say which to reach for and
  how such an app is laid out; where a skill points to rules of Lamp's own that aren't here (a base design), use
  your judgment.
- **A change is a build.** Each save to the app's code builds it again, a few seconds for a small change, and opens
  it again: what was typed or open in it is gone, so change first and try after. `look` waits for the build.
- **`look`** answers pictures of the app's windows (taken by the app itself, so nothing is asked of the person),
  what it printed, and when it didn't build, the compiler's errors with their file and line: the app is then as it
  was before the change. It answers the screen as text too once the app has been in front with the Mac unlocked;
  without it, aim by the picture, whose points are the points to click. `look --reopen` quits the app and opens it
  again first, as `{{lamp}} reload` does.
- **`use`** takes `click` (a point of the picture, or a name or id from the screen as text: `{{lamp}} use click "Add"`),
  `type`, `key` (`return`, `escape`, `cmd+a`…), `drag`, `scroll` and `wait`. It brings the app to the front. Only
  when asked to try it.
- **What you add while trying it is the app's real saved data**, kept under the app's own name in the person's
  Application Support: take it out again, or tell them it's there.
- **The app stays open** when you finish, as the person's to use. `{{lamp}} stop` quits it, when they only wanted it
  checked.
- **Lamp's own files** are `Sources/LampSupport.swift`, `build.sh` and `Package.swift`: never edit any of them.
- **A change into the open app, without reopening it**, is Lamp's app's: when the person has Lamp open and wants that,
  `{{lamp}} open --in-lamp` gives the app to it (Lamp shows them its review the first time). From then on `look`, `dev`
  and `reload` say how each change went in (live, held for their Reload, reopened, not built), and the person tries it
  there, and `use` tries the app Lamp has open, in plain sight. `{{lamp}} open --here` has lamp run its own copy again.
- **Not here:** the app's AI (`LampAI`), and a link to one on lamp.dev (its Lamp app file is here: see "A Lamp app
  file"). Those
  are Lamp's app's: say so rather than working around it. What the app keeps secret (`LampSecrets`) is kept for it.

## A game that's already there

A web game from somewhere else runs as it is: every command here works on it, each change opens its page again from
the start, and `look` can't know when it has finished loading. Putting it on Lamp's runtime is what lets it take
changes while it's played and say when it's really playing. `{{lamp}} init` puts Lamp's own files beside its page and
changes none of the page's; taking the runtime up in the game's code is the work. It goes in steps, each worth having
by itself:

1. **The runtime runs the game's loop** (`game()` in place of the game's own), with its renderer kept and the
   player's place given and taken back. A change then runs the game's code again in place, where before it opened
   the page again. A page laid out at the window's size that reads its own keys and touches says so to `game()`:
   the options are in `lamp-game.js`'s comments on the frame.
2. **The modules that get tuned accept their changes**, and those go in live.
3. **What's slow to build is kept**, so running the code again doesn't build it again.

Lamp's `game-live` skill says how each is done (its "A game from before this, or one brought in" is step 1), and
`lamp-game.js`'s comments are the whole interface: read those, not `web-game`, which is for a new game. A game
brought in reads its own input until its code reads the runtime's, so try it with keys, not Lamp's controller.

Where Lamp's `github-projects` skill has Lamp's app keep the project's credit and licenses (`lampify`), nothing does
here: keep its license file, its copyright headers and its author's credit on screen yourself.

## The loop

1. **Show the person the app** once, when you start, unless they don't want to watch: `{{lamp}} open`. It opens a
   window they can use and play in while you work, and returns at once.
2. **Change the files.** While the person watches a page you opened, first say what you're changing, in a few words
   of theirs: `{{lamp}} changing "Rain on the roads"`. The page shows it on the card it puts up as the change goes in.
3. **Look**: `{{lamp}} look`. It waits for the change to go in, then answers how it went, a picture of the page (a
   file: read it; the last forty are kept), the screen as text, and the errors and the log since your last look. Look
   after every change, and read the errors and the picture before saying it works. `{{lamp}} look --reopen` opens the
   page again from its beginning first, a game with its saves kept: what someone opening it sees. `--size 900x600`
   looks at it as a window of that size shows it, for a layout that has to hold at any shape (with no window open).
   When the answer says lamp found no Chrome, Edge, Brave or Chromium, there's no picture and `use` can't play the
   page: tell the person, since only they can install one.

Nothing has to be running first. With no window open, `look` runs the app itself in a copy of the page nobody sees,
opened from the files as they are, so the first look has no changes to report. The copy goes on running between
commands, as a window would: what you clicked and typed is still there, and a game's clock doesn't wait for you. It
closes by itself ten minutes after you last used it: there's nothing to stop when you finish.

## Trying it

Only when the person asks you to try, play or test the app: a request to change it is made and looked at, not played.

- `{{lamp}} use click "Add"` clicks a control by its name in the screen as text, and `{{lamp}} use click 640 400` a
  point of the picture, for what has no name there (a canvas, a drawing). The answer names what the click landed on.
- `{{lamp}} use type hello` types into whatever has the keyboard: click a field first.
- `{{lamp}} use key w 2` holds a key for two seconds (a letter, a digit, `space`, `enter`, `escape`, `up`, `left`…),
  and `w+d` holds two at once.
- `{{lamp}} use drag 400 300 700 300` presses at one point, moves to the other and lets go.
- `{{lamp}} use scroll 600` scrolls down, and up with a negative number. A look shows only what's in the window.
- `{{lamp}} use wait 3` waits, for something that takes time: thirty seconds at most, so wait again for longer.

Several moves go in one command with `then` between them, one after another with nothing in between and one look at
the end: `{{lamp}} use click 640 400 then key w 3 then key w+d 2`. Play anything with a clock that way, a whole
stretch of it to a command, and end the stretch on the game's pause when it has one (`… then button menu`): the game
runs on while you read a picture. Where a canvas is drawn at another size than it's shown, the screen as text says
how a point of the game is found in the picture.

A game on Lamp's runtime is played with Lamp's own controller, as Lamp's game skills say (`use_app`'s `stick` and
`button`):

- `{{lamp}} use stick left 1 0 2` holds the left stick to the right for two seconds: `left` or `right`, then x and y
  from -1 to 1, right and up being 1. A button named after the seconds is held with it (`… 2 a`).
- `{{lamp}} use button a` presses a button, `a 1.5` holds it, and `a+rt` holds two: `a`, `b`, `x`, `y`, `lb`, `rb`,
  the triggers `lt` and `rt`, `menu`, `view`, `up`, `down`, `left`, `right`.

It's the first player's controller, from wherever the game is. It isn't a controller plugged in, so the game's
prompts go on naming keys. If the person plays meanwhile they have it back at once and the answer says so: the game
is theirs until they ask again. A key works in a game here too.

Each answers with a look. With the window open it happens in the person's own window, where they see it.

## How a change went in

`look` says one of these for each change since the last look:

- **live**: swapped in while the page ran. Nothing was lost.
- **reran**: the game's code ran again, with the player where they were. In a small game that takes a moment, and
  is as good as live.
- **reopened**: the page opened again. A game opens from the player's place. A plain page always takes a change this
  way and starts over: what was typed or counted in it is gone, so change first and try after.
- **held**: the change waits, and the page shows the person a Reload to apply button. Either it waits for a pause in
  the game (the end of a round, a menu), and goes in by itself then: a later look says so. Or for that button, because
  the page must open again for it: `{{lamp}} reload` presses it, so with a window open ask the person first.

The reason given after one names the file that changed, where an `accept()` would have taken the change, and the
module it's loaded through. A game that takes changes live is written for it. When a change won't go in, needs Reload
or loses the player's place, read Lamp's `game-live` skill before working around it.

## A Lamp app file

A folder with `lamp-app.json` at its top (or in `.lamp-wish/`) is an app in Lamp's format, from GitHub or a shared file:
every command here works on a web app, a game, a screen or a Mac app in one, and says so for a kind it doesn't run.

- `{{lamp}} unpack Name.lampapp` unpacks a Lamp app file (what Lamp's Share… makes) into a new folder beside it, with
  Lamp's own files put in, and says how to see it.
- `{{lamp}} export` makes the app's Lamp app file beside its folder, for the person to send or open in Lamp: only when
  they ask. It's refused when something in the app is shaped like a key, or a license its credits name is gone; when
  it uses work that came with no license, ask the person before `--anyway`.

## Sharing it

Only when the person asks: a link is public, and anyone who has it can play the page.

- Start with `{{lamp}} share --preview`: it says what would go and sends nothing. Show the person, and share only once they
  say so.
- **An app of Lamp's own** (its folder is in Lamp's, or a link to one; the preview says it's going through Lamp) is
  shared by Lamp, which must be open, to the link it already has, filled as its Share Link card fills itself: its words,
  the questions and what's new Lamp writes, its file, its GitHub release. Run `{{lamp}} share` with no words of your own,
  and give `--line`, `--by`, `--asks "a|b"` or `--notes "What's new|And more"` only for what the person wants changed.
  Its ideas and taking it down are on Lamp's Share Link card, not `ideas` and `unshare` here.
- **Any other page:** `{{lamp}} share --words "What it is, in a sentence or a few"` puts it on lamp.dev and answers its
  link. `--line` is a line under its name, `--asks "Found a bug?|What's missing?"` what the box under the page asks
  people, and `--by "Their Name"` who it's by: only a name the person gave you to show. A page that's logging errors
  isn't shared until they're put right. Again, after changes, it sends the page as it is now to the same link, with the
  same words unless you give new ones.
- `{{lamp}} ideas` lists what people playing it have sent, each with the address of a picture of the app as they saw
  it when they kept one in: look at it before building the idea. Once one is in the game and the game shared again,
  `{{lamp}} ideas in <number>` says so, and whoever asked to hear is written to; `{{lamp}} ideas dismiss <number>` lets
  one go. Words after the number are a note to whoever sent it, shown on the link's page and put in that email: write
  one only when the person asks you to answer them, in their words. Senders can answer by email: `{{lamp}} ideas` shows
  what's been said under each idea, and those they've answered; `{{lamp}} ideas reply <number> <words>` answers again,
  and `{{lamp}} ideas done <number>` leaves one without a word. `{{lamp}} ideas --earlier` lists those seen to. `{{lamp}} ideas email <address>` sends new ideas and replies to the
  person's own address too, once they confirm it from the email it sends (`off` stops them): only with an address
  they gave you.
- `{{lamp}} unshare` takes the link down.

Tell the person the link, and that it's public.

## On the person's Xbox

A page goes on an Xbox in Developer Mode, in Lamp's own host for the console's browser: the same files, played with
the console's controller. Only when the person asks for it there, and only on a device they set up.

- `{{lamp}} devices` lists the devices set up with lamp and those found on the network. One only found may not be
  theirs: never put anything on it.
- Setting one up asks for the console's Device Portal password, which only the person types. Ask them to run
  `{{lamp}} devices add` in a terminal themselves; never ask for the password, and never type one.
- `{{lamp}} open --on xbox` packages the page as it is now, installs it and opens it on the console, in place of the
  copy that was there. A change isn't live there: put the page on again once it works on this computer.
- `{{lamp}} look --on xbox` is the console's screen as a picture, whether the app is open there, and what it logged
  there. A game on Lamp's runtime logs how many frames a second it gets: that, never this computer's, says how it
  runs on the console.
- You can't press the controller there. Try the game in its window here (`stick`, `button`), where it's the same
  code, and tell the person what's left for them to try with the controller in their hands.
- `{{lamp}} stop --on xbox` ends it, and `{{lamp}} remove --on xbox` takes it off the console.

## On Android

A page goes on Android in Lamp's own Android app around it: the same files, on a phone, a tablet or a TV. It needs a
Mac with Android's tools, which `{{lamp}} devices` says are there or not. If they aren't, ask the person to run
`{{lamp}} devices add android` in a terminal themselves: it downloads Google's tools and accepts Google's terms for
them, which is theirs to do.

- `{{lamp}} open --on android` builds the app and opens it in lamp's Android emulator, a phone in a window on the Mac;
  `--on android-tv` is its TV emulator. Use these when the person asks to see it on Android.
- For a check of your own, add `--hidden`: the emulator starts with no window and no sound, and
  `{{lamp}} stop --on android` closes it when you're done. Don't leave one running.
- A phone, tablet or TV of the person's goes by its name (`{{lamp}} devices` lists those plugged in with USB debugging
  on): only when they ask for it there. If it says to allow debugging, that's a tap on the device's own screen, theirs.
- `{{lamp}} look --on android` is the device's screen as a picture, whether the app is open, and what the page logged
  there: a game on Lamp's runtime logs how many frames a second it gets.
- `{{lamp}} use --on android click <x> <y>` taps a point of that picture; `drag`, `type`, `key` and `button` work too,
  one key or button at a time, with no stick. A game shows touch controls until a controller's button is pressed.
- A change isn't live there: `{{lamp}} open --on android` again builds and installs it, in a few seconds.
- `{{lamp}} remove --on android` takes it off.

## Lamp's skills

An app Lamp made (its page loads `lamp.js`) is built from Lamp's own building blocks, and Lamp has guidance for each
kind of work on one: a new web game, 3D, how a game feels, a web app's page. `{{lamp}} skills game` lists those about a
word, `{{lamp}} skills` all of them, and `{{lamp}} skill <name>` prints one. Read the ones that fit before changing what
they cover: they are the one place that says which building blocks to use and how.

Those skills are written for Lamp's app, which builds the game, opens it and looks at it for you when your turn
ends, and so tells you to write and finish without looking or playing. Nothing does that here: you look after every
change, as above, and that comes first. Where one names a tool of Lamp's:

- `look_at_app` is `{{lamp}} look`, and its `reopen` is `--reopen`. There's no `motion`: look twice.
- `use_app` is `{{lamp}} use`, one move to each of its actions. A control on the page is clicked at its point from the
  screen as text, not by an id.
- `read_skill` is `{{lamp}} skill <name>`, and `make_app_for` is `{{lamp}} new`, for a web game only.
- `delete_file` is deleting the file, and putting a change in needs no tool.
- `assets`, `make_art` and `lampify` aren't here: make what's needed in code, or say what's missing.

A plain site, on neither `lamp.js` nor Lamp's runtime, uses none of them: skip the skills there.

## Rules

- Lamp's own files in the folder are rewritten by Lamp, so read them and never edit them: `lamp.js`, `lamp-game.js`,
  `lamp-phaser.js`, `lamp-controllers.js`, and the `three/` and `phaser/` folders.
- The page's whole log is the file `look` names.
- lamp runs the page in a browser on this computer, and puts it on an Xbox ("On the person's Xbox") and on Android
  ("On Android"). iPhones, Samsung and LG TVs,
  and whatever needs Lamp's Mac app around the page, aren't here: say so rather than working around it.
