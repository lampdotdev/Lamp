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
looked earlier, `--reopen` puts it right. A plain web page needs no starting files: write its `index.html` in an
empty folder.

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
- **Not here:** putting a change in without opening the app again, the app's AI (`LampAI`), and sharing one. Those
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
2. **Change the files.**
3. **Look**: `{{lamp}} look`. It waits for the change to go in, then answers how it went, a picture of the page (a
   file: read it; the last forty are kept), the screen as text, and the errors and the log since your last look. Look
   after every change, and read the errors and the picture before saying it works. `{{lamp}} look --reopen` opens the
   page again from its beginning first, a game with its saves kept: what someone opening it sees. `--size 900x600`
   looks at it as a window of that size shows it, for a layout that has to hold at any shape (with no window open).

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

## Sharing it

Only when the person asks: a link is public, and anyone who has it can play the page.

- `{{lamp}} share --words "What it is, in a sentence or a few"` puts the page on lamp.dev and answers its link. `--line`
  is a line under its name, `--asks "Found a bug?|What's missing?"` what the box under the page asks people, and
  `--by "Their Name"` who it's by: only a name the person gave you to show. A page that's logging errors isn't shared
  until they're put right.
- Again, after changes, it sends the page as it is now to the same link, with the same words unless you give new ones.
- `{{lamp}} ideas` lists what people playing it have sent. Once one is in the game and the game shared again,
  `{{lamp}} ideas in <number>` says so, and whoever asked to hear is written to; `{{lamp}} ideas dismiss <number>` lets
  one go.
- `{{lamp}} unshare` takes the link down.

Tell the person the link, and that it's public.

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
- lamp runs the page in a browser on this computer. Phones, TVs and consoles, and whatever needs Lamp's Mac app
  around the page, aren't here: say so rather than working around it.
