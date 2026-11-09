# lamp dev (prototype)

Runs a web app or web game from its folder in any browser, and puts each saved change into the open page. It needs
no Mac app and no build: whatever edits the files, a person or a coding agent, just saves them.

```bash
node cli/lamp.mjs dev path/to/app --open
```

The folder is one Lamp made (the page is in `Web/`) or any folder with an `index.html`. Options: `--port 4400`,
`--open` to open the browser.

## What it does

- **A game made with Lamp's runtime** (`lamp-game.js` beside the page) takes a change the way it does inside Lamp:
  a module that accepts changes is swapped in while the game runs, other code runs again with the player where they
  were, and what can't go in either way opens the page again from the player's place. The runtime is handed the
  change exactly as Lamp's app around the page hands it over (`window.__lampLive`), so nothing in the game differs.
- **Any other page** is opened again on each change.
- **The terminal says how each change went** ("swapped in while it ran", "the page opened again"), and **what the
  page logs is written to `.lamp/runtime/log.txt`** in the folder, where Lamp keeps it too, for whoever made the
  change to read.

The two files Lamp writes beside the runtime in each copy of a game (`lamp-device.js`, `lamp-build.js`) are served
from memory when the folder has none: the device is a browser on any device, as a page published to the web is given.

## What it doesn't do yet

Only the browser on this computer: no phone, TV or console, no Mac app around the page (so nothing that needs
`LampNative`), no sharing, and no way for an agent to look at the page other than its log.
