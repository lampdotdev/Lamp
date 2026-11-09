# lamp, from a terminal

Runs a web app or web game from its folder and puts each saved change into the open page, for whoever is making it: a
person, or a coding agent in a terminal. It needs no Mac app and no build step, and has no dependencies (Node 20 or
later).

```bash
node cli/lamp.mjs dev path/to/app --open
```

`npm link` in `cli/` makes it `lamp` everywhere. The folder is one Lamp made (its page is in `Web/`) or any folder
with an `index.html`; without one, the folder you're in.

| Command | What it does |
| --- | --- |
| `lamp dev [--open] [--lan] [--port N]` | Runs the page and says how each change went. Each save goes into every open copy of it. `--open` opens a window for it; `--lan` lets other devices on the network open it. |
| `lamp open` | Shows the page in a window, running it in the background if it isn't running, and returns at once. |
| `lamp look [--wait s] [--json]` | How the changes since the last look went, a picture of the page, its screen as text, new errors and the log. |
| `lamp use key w 2` | Tries it as a person would, then looks: `key <name> [seconds]`, `click <x> <y>`, `type <text>`, `wait <seconds>`. |
| `lamp reload` | Opens the page again from its files, a game from where the player is. |
| `lamp stop` | Stops running it. |
| `lamp setup [--remove]` | Teaches Claude Code and Codex on this computer to work this way: a skill for each. |
| `lamp guide` | What that skill says, for any other agent. |
| `lamp skills [word]`, `lamp skill <name>` | Lamp's skills (`Resources/skills`), the one place that says which building blocks to use and how: all of them or those about a word, and one in full. |

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

The two files Lamp writes beside the runtime in each copy of a game (`lamp-device.js`, `lamp-build.js`) are served
from memory when the folder has none: the device is a browser on any device, as a page published to the web is given.

A change saved while a page is opening isn't lost: each page says which change its files had, and is handed what came
after. A server started again tells its pages to open again, since it can't know what changed while it was away.

## Looking and using

`lamp look` is how whoever made a change checks it. It checks every file first (a look straight after a save can
come before the system says the file changed), waits for the page to finish taking the change in, and answers:

- how each change since the last look went in, in the words above, and why;
- a picture of the page, one pixel a point, so a point of the picture is a point to click (each look's is a file of
  its own, and the last few are kept);
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

## Where things are kept

- **The log.** In an app Lamp made, `.lamp/runtime/log.txt` in the folder, where Lamp keeps it too. A plain site's is
  kept with lamp's other state, and `lamp look` names it.
- **Everything else** (the browser's files, so a game's saves last from one run to the next; the last few pictures;
  which server is running) is in `~/.lamp/dev/<folder's name>-<hash>/`, outside the folder, so nothing of lamp's is
  committed or published with a site. `LAMP_DEV_HOME` moves it.
- **The port** is 4400, or the next free one; a folder keeps its port from run to run, since a game's saves belong
  to the address.

## Who it answers

The server listens on this computer only, unless `--lan` is given. It answers requests made to its own name
(`localhost`, and with `--lan` the computer's names on the network), nothing sent by a page of another site, and
never a hidden file or one outside the page. `look`, `use`, `reload` and `stop` need a token only lamp's own commands
can read.

## What it doesn't do yet

Phones, TVs and consoles as places to run; sharing; and anything that needs Lamp's Mac app around the page
(`LampNative`, a game's phone controllers). A new app isn't made here either: the folder comes from Lamp.

## Tests

```bash
node --test cli/tests/*.test.mjs
```
