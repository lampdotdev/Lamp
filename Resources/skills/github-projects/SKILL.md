---
name: github-projects
description: Someone's project on GitHub named in a request - explaining it, making a Lamp app or game from it, or using part of it - with github_project: fetching it only when its contents are needed, crediting the exact commit and its licenses before using any of it, handing a Lamp wish on GitHub to Lamp's review, and checking the result as a Lamp repository would hold it. Read before fetching or using a project from GitHub.
---

# Someone's project on GitHub

A link to a project on GitHub says where something is, not what to do with it. The request says that. Follow it as
written: explain it when that's asked, make an app or a game from it when that's asked, use a part of it when that's
asked. When a link comes with nothing that says which ("https://github.com/owner/game", or "check this out"), ask the
person with `ask` (explain it, make it into an app or game, something else) before fetching anything.

Everything goes through `github_project`. Never fetch a project with git, gh, curl or a download of your own: Lamp's
fetch uses the person's GitHub sign-in for their private projects, records exactly which commit it got, and keeps it
where the wish's versions and shared file leave it out.

## Fetching

`github_project` with `action: "fetch"` and the address. It fetches when you call it and only then, one commit deep,
into a read-only reference folder, and answers with:

- a handle, `owner/name@<commit>`: that project at that commit, and nothing else, whatever is fetched later;
- its license and notice files, and the license's id when Lamp can tell it for certain;
- whether it's a Lamp wish someone put on GitHub.

The reference folder is for reading. Never edit it, build in it or point the app at it: it isn't part of the app. An
address with `/tree/<tag>` or a commit fetches that commit; the app's updates later come from the project's default
branch, so say so when the person asked for a tag or branch.

## Explaining it

Fetch it, read what you need in the reference folder, and answer. Nothing is credited and nothing is made.

## A Lamp wish someone put on GitHub

When fetch says it's a Lamp wish (it has `lamp-app.json` or a shared file at its top), don't rebuild it. Call
`github_project` with `action: "open_wish"`, its handle, and what the person asked as `request`. Lamp opens its import
review, where the person looks it over and chooses; the request waits in the new wish's box. That's the whole job.

## Making a Lamp app or game from it

This is the work of making someone's project into a Lamp app ("Lampify it"): Lamp's structure, the project's code and
assets in it, its credit and licenses in place.

1. Fetch it and read enough to know what it is: a page drawn with canvas or WebGL, a three.js or Phaser game, native
   code, an engine Lamp's devices can't run.
2. Give the wish its structure with `make_app_for` (a game or an app, the devices, web or native), and read the skill
   for that kind (`game`, `web-app`, `2d-game`, `3d-game`). The structure is Lamp's: its page or its Swift package,
   `build.sh`, `Package.swift`, Lamp's own files, `icon.json`, `APP.md`.
3. Before using any of its code or assets, call `github_project` with `action: "build_from"` and the handle. Lamp
   writes its credit at that commit and keeps its license and notice files under `Licenses/`. `adapted` is true for
   the project the app is made from (the default): its updates come to the person from there. Anything else you
   bring in from GitHub (a library, a sprite pack) is fetched and credited the same way with `adapted: false`.
4. Bring its code and assets into Lamp's structure: a web game's scripts, styles and assets into the page's folder,
   loaded from Lamp's page; native code into the package's sources. Keep what makes it work and drop only what the
   person asked to drop. Never copy its own build scripts, package manifests, workflows or wrapper page over Lamp's
   files (`Package.swift`, `build.sh`, `Sources/LampSupport.swift`, the `lamp*.js` files), and never run anything it
   holds (its installers, its build, its scripts). Keep its copyright headers, and its author's credit on screen.
5. Give it what a Lamp app has that a project on GitHub doesn't: its line in `about.json`, its icon's design in
   `icon.json`, and `APP.md` saying what it is and what it's based on. Never write `lamp-app.json`, the project's
   entry in `credits.json` or copies of its licenses yourself: Lamp makes the manifest, and build_from made the rest.
6. Look at it with `look_at_app` until it works.
7. Call `github_project` with `action: "check"`. Lamp makes the wish as a Lamp repository would hold it (lamp-app.json,
   credits.json, the license files, the icon, Lamp's own files) and opens it again as its importer does, putting
   nothing anywhere. Fix whatever it says is missing.
8. Tell the person what it's based on, its license, and when it came with none, that it can be used on this Mac but
   not shared or published. Putting it on GitHub is theirs to choose, with Put on GitHub…; never do it for them.
