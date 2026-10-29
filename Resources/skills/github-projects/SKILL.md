---
name: github-projects
description: Someone's project on GitHub named in a request - explaining it, making a Lamp app or game from it ("Lampify it"), or using part of it - reading it in a git clone, and lampify, which credits the exact commit, keeps its licenses, makes the manifest and says what a Lamp app made from it still lacks. Read before using a project from GitHub.
---

# Someone's project on GitHub

A link to a project on GitHub says where something is, not what to do with it. The request says that. Follow it as
written: explain it when that's asked, make an app or a game from it when that's asked, use a part of it when that's
asked. When a link comes with nothing that says which ("https://github.com/owner/game", or "check this out"), ask the
person with `ask` (explain it, make it into an app or game, something else) before cloning anything.

## Reading it

Clone it shallowly into the wish's reference folder and read it there:

    git clone --depth 1 https://github.com/owner/name .lamp/reference/name

A branch or tag the address names: add `--branch <name>`. The folder is for reading: never build in it or point the app
at it, it isn't part of the app. A clone that fails because the project is private: call `lampify`, which fetches it
with the person's GitHub sign-in, and read its copy, whose path its answer gives.

Asked to explain it: read it and answer. Nothing is credited and nothing is made.

## A Lamp wish someone put on GitHub

When the project has `lamp-app.json` or a `.lampapp` file at its top, it's a Lamp wish already: don't rebuild it. Tell
the person to open it with File → Open from GitHub… and paste its address. Lamp reviews it there.

## Making a Lamp app or game from it

This is making someone's project into a Lamp app ("Lampify it"): Lamp's structure, the project's code and assets in it,
its credit and licenses in place, and the rest of what a Lamp app has.

1. Clone it and read enough to know what it is: a page drawn with canvas or WebGL, a three.js or Phaser game, native
   code, an engine Lamp's devices can't run.
2. Give the wish its structure with `make_app_for` (a game or an app, the devices, web or native), and read the skill
   for that kind (`game`, `web-app`, `2d-game`, `3d-game`). The structure is Lamp's: its page or its Swift package,
   `build.sh`, `Package.swift`, Lamp's own files, `icon.json`, `APP.md`.
3. Before using any of its code or assets, call `lampify` with its address and the commit your clone is at
   (`git -C .lamp/reference/name rev-parse HEAD`). Lamp gets its own untouched copy at that commit, credits it in
   credits.json, keeps every license and notice file under `Licenses/`, and answers with the manifest and what's still
   missing. `adapted` is true for the project the app is made from (the default): its updates come to the person from
   there. Anything else you bring in from GitHub (a library, a sprite pack) is cloned and lampified the same way with
   `adapted: false`. Every later call passes the same commit: lampify never moves on to a newer one by itself.
4. Bring its code and assets into Lamp's structure: a web game's scripts, styles and assets into the page's folder,
   loaded from Lamp's page; native code into the package's sources. Keep what makes it work and drop only what the
   person asked to drop. Never copy its own build scripts, package manifests, workflows or wrapper page over Lamp's
   files (`Package.swift`, `build.sh`, `Sources/LampSupport.swift`, the `lamp*.js` files), and never run anything it
   holds (its installers, its build, its scripts). Keep its copyright headers, and its author's credit on screen.
5. Give it what a Lamp app has that a project on GitHub doesn't: its line in `about.json`, its icon's design in
   `icon.json`, and `APP.md` saying what it is and what it's based on. Never write `lamp-app.json`, the project's entry
   in `credits.json` or copies of its licenses yourself: lampify does.
6. Look at it with `look_at_app` until it works.
7. Call `lampify` again with the same address and commit, and fix whatever it says is still missing, until it says
   nothing is.
8. Tell the person what it's based on, its license, and when it came with none, that it can be used on this Mac but
   not shared or published. When the address named a tag or a branch, say its updates will come from the project's
   default branch. Putting it on GitHub is theirs to choose, with Put on GitHub…; never do it for them.
