# Working on Lamp

Lamp is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

This file holds only what every change needs. How each part of Lamp works, and the rules that apply to just that
part, are in the guides in `docs/development/`. **Before changing a part of Lamp, read its guide** (the table at
the end); a change that crosses parts reads each of theirs. The guides are plain links, never imports, so
nobody has to load all of them to work on one: keep it that way, and when you add a rule, put it in the guide for
the part it governs. Only a rule that every change must follow belongs here.

## Rules for every change

- **Keep the three engines in step.** Lamp drives three coding agents, chosen in Settings → Building: **pi**
  (bundled), **Claude Code** and **Codex**. Each is set up in `Sources/Lamp/Engines.swift` (`Agent.run`, one `case`
  per engine) and read by its own parser (`parseClaude`, `parseCodex`, pi's in `Agent.parseLine`). A capability
  given to one engine is given to every engine that can take it, in the same change: tools (defined once, in
  `Resources/lamp-tools.json`), their rules in the system prompt, approvals, what the chat shows, models. Which
  copy of an engine runs is decided only in `EngineInstall.path(for:)`. Before opening a PR that touches any of
  this, check each engine's `case` in `Agent.run` and its parser, and say in the PR description which engines you
  tried. Details: [engines](docs/development/engines.md).
- **Approvals and privacy hold for every engine.** Shell commands go through `/agent/approve` whichever engine runs
  them, and file access outside the app's folder is checked the same way (`Privacy.verdict`); a command never skips
  approval because it looks like a read. Lamp's own commands over what's in an app's folder run in the app's
  sandbox (`Sandbox.run`, never `Shell.run` directly). Details: [approvals and privacy](docs/development/approvals-and-privacy.md).
- **Lamp's own files in generated apps are written afresh, so fix them at their source.** `Sources/LampSupport.swift`,
  `build.sh` and `Package.swift` in every app are rewritten before each build (`Template.writeOwnedFiles`); a change
  to them belongs in `Sources/Lamp/Template.swift`. That file holds `LampSupport.swift` as a Swift string: after
  editing it, extract and type-check it (`swiftc -typecheck`), and bump anything that detects an outdated app
  (`Store.open` rebuilds apps built by an older Lamp). Details: [generated apps](docs/development/generated-apps.md),
  and [live changes](docs/development/live-reload.md) for anything that affects how an open app takes a change.
- **Names on disk and on the network come from `Edition`.** A build from source is Lamp Dev, a separate app with
  its own bundle id, folders, ports, URL scheme and Keychain entries, and a build from a worktree is an instance of
  its own; `Sources/Lamp/Edition.swift` is the one place these come from. Details:
  [Lamp Dev and instances](docs/development/lamp-dev-and-instances.md).
- **Ask a kind of app what it can do, not which kind it is.** Each kind is one `Target` in `Sources/Lamp/Targets/`;
  code outside it asks (`hasMac`, `hasIOS`, …) rather than checking the kind. Details:
  [kinds of app](docs/development/kinds-of-app.md).
- **A wish's chat is one screen.** It's drawn by `ChatScreen` (LampSidebarKit) from the state Lamp sends, beside a Mac
  app and in Lamp's own panel alike, and never in Lamp's window, which is the desk. What the chat shows or does is
  added to that state and that screen, never to one place it's drawn. Details: [chat](docs/development/chat.md).
- **Screens are for doing, not explaining.** On-screen words are short and plain, a control appears once it
  works, and a thing is shown where it's chosen. A new card or card state gets its entry in the gallery in the same
  change. Details: [interface](docs/development/interface.md).

## Naming: Lamp and Lamp

The app is called **Lamp**: that's the name in everything the user reads (the interface, Help, the agent's
words to the user, the "Customize with Lamp" command in generated apps, the bundle and the DMG). **Lamp** is its
code name and stays in code, comments, type names (`LampSupport`, `LampAI`, …) and in everything existing
installs depend on: the bundle ID `dev.lamp.host`, `~/Library/Application Support/Lamp`,
`~/Applications/Lamp Apps`, the `lamp://` scheme, the `.lampapp` extension and the signing certificates.
Renaming any of those needs a migration, not a find-and-replace.

## Conventions

- Comments explain why, in plain prose; user-facing text never names files, types or frameworks.
- Files committed to the repo (README, docs, code comments, tests) must never name a person, personal device or hostname, or narrate a particular session or test run; put those details in the PR description.
- Verify in an isolated harness app rather than in the user's apps, without taking over the screen others are using:
  see "Checking a change beside other work" in [Lamp Dev and instances](docs/development/lamp-dev-and-instances.md).
- No attribution lines in commits or PR descriptions.

## Guides

Read the guide for the part you're changing before you change it. A section named in quotes in one guide
("Generated apps", "Kinds of app", "Apps for both") is found by its heading in the guide listed for it here.

| Guide | Read it when the change touches |
| --- | --- |
| [engines](docs/development/engines.md) | Keep the agent harnesses in step: `Engines.swift`, `EngineInstall`, the tools in `lamp-tools.json` and the MCP endpoint, prompt rules, memory, switching engines, skills, pictures shown to the agent, queued messages, tool names in the chat, models, what answers apps, using other apps |
| [chat](docs/development/chat.md) | How the agent talks: `Talk`, cards, `ask`, `progress`, the chat's timeline, its activity line and folded steps; the chat's one screen (`ChatScreen`, `SidebarState`) and Lamp's chat panel (`ChatPanel`, `SetupSheet`) |
| [approvals and privacy](docs/development/approvals-and-privacy.md) | `/agent/approve`, `Privacy`, the sandbox, file access outside an app's folder, data snapshots |
| [desk](docs/development/desk.md) | The desk, Lamp's only window: wishes as icons, opening a wish, starters and their checks |
| [Lamp Dev and instances](docs/development/lamp-dev-and-instances.md) | Two Lamps on one Mac: `Edition`, worktree instances, checking a change beside other work, `dev-data.sh`, `fresh-start.sh`, `LAMP_PRETEND_MISSING` |
| [kinds of app](docs/development/kinds-of-app.md) | `Platform`, `Targets/`, a kind's identity, guidance, recipe, part and setup; `Destination`; the table of what each device can run (`Places`) |
| [iPhone](docs/development/iphone.md) | iPhone apps, the simulator and phones, Apple TV and Vision Pro; Apps for both the Mac and the iPhone |
| [Android](docs/development/android.md) | Android apps, the emulator and Android devices |
| [devices](docs/development/devices.md) | Devices as data (device integrations), games and their places, and screens |
| [TV](docs/development/tv.md) | TV apps |
| [wishes](docs/development/wishes.md) | Wishes of more than one app: parts, plans, how a wish's apps reach each other |
| [Apple services](docs/development/apple-services.md) | iCloud, Apple Health, work while an iPhone app is closed, photos, location, weather, music and the home |
| [generated apps](docs/development/generated-apps.md) | Generated apps: Lamp's owned files, `Template.swift`, permission reasons, `use_app` and handover, the wand and the chat beside an app, Chrome's sidebar, quitting, `capabilities.json` |
| [live changes](docs/development/live-reload.md) | A change going into an open app: `LiveReload`, `LiveSlots`, the live copy, statics, removed properties and files, the live cases |
| [app extensions](docs/development/app-extensions.md) | 3D scenes and games, widgets, Home Screen widgets and Live Activities, Apple Watch, App Intents, share extensions and Spotlight |
| [services](docs/development/services.md) | Services the person already uses: sign-in on the service's page, personal tokens, open data, the app's secrets |
| [interface](docs/development/interface.md) | Any screen: Settings, the welcome, the chat's cards, the gallery, the app's info panel |
| [website](docs/development/website.md) | `site/` (lamp.dev) |
