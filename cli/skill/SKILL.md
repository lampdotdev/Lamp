---
name: lamp
description: Make, run, see and try a web app or web game with lamp's command line. Use when the person asks for a new web game, or when working in a folder made with Lamp (a page beside lamp-game.js, or in Web/ with APP.md) or in a plain site's folder and they ask to change the app, to see it, or to check that a change works. Every saved change goes into the open page, and a game keeps the player's place.
---

# Working on an app with lamp

`{{lamp}}` runs the page in the app's folder and puts each change into it while it's open. Save a file and the change
goes in. Never build, restart or reload anything for a change.

Run the commands from the app's folder, or give the folder after the command (`{{lamp}} look path/to/app`).

## A new game

`{{lamp}} new path/to/folder --name "Its Name"` makes a new web game's folder from Lamp's starting files: the game
runtime (`lamp-game.js`), three.js, and a page that shows a card until the game replaces it. Read Lamp's `web-game`
skill before writing the game, then work on it as below. A plain web page needs no starting files: write its
`index.html` in an empty folder.

## The loop

1. **Show the person the app** once, when you start, unless they don't want to watch: `{{lamp}} open`. It opens a
   window they can use and play in while you work, and returns at once.
2. **Change the files.**
3. **Look**: `{{lamp}} look`. It waits for the change to go in, then answers how it went, a picture of the page (a
   file: read it), the screen as text, and the errors and the log since your last look. Look after every change, and
   read the errors and the picture before saying it works.

Nothing has to be running first. With no window open, `look` runs the app itself in a copy of the page nobody sees,
opened from the files as they are, so the first look has no changes to report. The copy stays as it is from one
command to the next (what you clicked and typed is still there) until a change opens the page again. It closes by
itself when you've stopped using it: there's nothing to stop when you finish.

## Trying it

Only when the person asks you to try, play or test the app: a request to change it is made and looked at, not played.

- `{{lamp}} use click 640 400` clicks a point of the picture. The screen as text gives each control's point, its
  middle: click exactly there. The answer names what the click landed on.
- `{{lamp}} use type hello` types into whatever has the keyboard: click a field first.
- `{{lamp}} use key w 2` holds a key for two seconds (a letter, a digit, `space`, `enter`, `escape`, `up`, `left`…),
  and `w+d` holds two at once.
- `{{lamp}} use drag 400 300 700 300` presses at one point, moves to the other and lets go.
- `{{lamp}} use scroll 600` scrolls down, and up with a negative number. A look shows only what's in the window.
- `{{lamp}} use wait 3` waits, for something that takes time.

A game on Lamp's runtime is played with Lamp's own controller, as Lamp's game skills say (`use_app`'s `stick` and
`button`):

- `{{lamp}} use stick left 1 0 2` holds the left stick to the right for two seconds: `left` or `right`, then x and y
  from -1 to 1, right and up being 1. A button named after the seconds is held with it (`… 2 a`).
- `{{lamp}} use button a` presses a button, `a 1.5` holds it, and `a+rt` holds two: `a`, `b`, `x`, `y`, `lb`, `rb`,
  the triggers `lt` and `rt`, `menu`, `view`, `up`, `down`, `left`, `right`.

It's the first player's controller, from wherever the game is. If the person plays meanwhile they have it back at
once and the answer says so: the game is theirs until they ask again. A key works in a game here too.

Each answers with a look. With the window open it happens in the person's own window, where they see it.

## How a change went in

`look` says one of these for each change since the last look:

- **live**: swapped in while the page ran. Nothing was lost.
- **reran**: the game's code ran again, with the player where they were.
- **reopened**: the page opened again. A game opens from the player's place. A plain page always takes a change this
  way and starts over: what was typed or counted in it is gone, so change first and try after.
- **held**: the game is at a moment it can't be interrupted, and waits for the person to press Reload in the page.
  `{{lamp}} reload` does it for them: ask first.

A game that takes changes live is written for it. When a change won't go in, needs Reload or loses the player's
place, read Lamp's `game-live` skill before working around it.

## Lamp's skills

An app Lamp made (its page loads `lamp.js`) is built from Lamp's own building blocks, and Lamp has guidance for each
kind of work on one: a new web game, 3D, how a game feels, a web app's page. `{{lamp}} skills game` lists those about a
word, `{{lamp}} skills` all of them, and `{{lamp}} skill <name>` prints one. Read the ones that fit before changing what
they cover: they are the one place that says which building blocks to use and how. Where one names a tool of Lamp's,
`look_at_app` is `{{lamp}} look` and `use_app` is `{{lamp}} use` (each of its actions is one command); putting a change
in needs no tool here.

A plain site, with no `lamp.js`, uses none of them: skip the skills there.

## Rules

- Lamp's own files in the folder are rewritten by Lamp, so read them and never edit them: `lamp.js`, `lamp-game.js`,
  `lamp-phaser.js`, `lamp-controllers.js`, and the `three/` and `phaser/` folders.
- The page's whole log is the file `look` names.
- lamp runs the page in a browser on this computer. Phones, TVs and consoles, sharing, and whatever needs Lamp's Mac
  app around the page aren't here: say so rather than working around it.
