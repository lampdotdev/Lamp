# Working on Lamp

Lamp is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

## Keep the agent harnesses in step

Lamp drives three coding agents, chosen in Settings → Building: **pi** (bundled), **Claude Code** and
**Codex**. They are set up in `Sources/Lamp/Engines.swift` (`Agent.run`), one `case` per engine, and
the output of each is read by its own parser there (`parseClaude`, `parseCodex`, and pi's in
`Agent.parseLine`).

A capability given to one engine must be given to all of them that can take it, in the same change:

- **Tools the agent calls** (`look_at_app`, `use_app`, `plan`, `delete_file`, the version tools): their
  names, descriptions and schemas live once, in `Resources/lamp-tools.json`. pi's extension
  (`Resources/lamp-tools.ts`) reads it for its definitions and holds only the `execute` bodies; Lamp's MCP
  endpoint (`Store.mcpTools`, `/mcp` on the gateway) serves it to Claude Code and Codex. A new tool is an
  entry there, an `execute` in the extension, and a `case` in `Store.mcp`.
  Codex has no file tools of its own, so the endpoint also gives it `read`, `ls`, `find` and `grep`
  (`FileTools`, listed when the URL carries `files=1`): they mirror pi's built-in ones, and each call is
  checked by `Privacy.verdict` like pi's. Don't let a Codex shell command skip approval because it looks
  like a read.
- **Rules in the system prompt** (`Agent.systemPrompt`, `Agent.tryRules`): every tool is available to every
  engine (`look_at_app`, `use_app`, `plan`, `delete_file` and the version tools), so their rules all live in
  `tryRules`. The file tools only Codex is given have theirs in `Agent.codexNote`.
- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
- **What Lamp shows the user** (`BuildCard.activity`, `ToolCall`): tool names must be recognised in every
  engine's spelling. Claude Code calls MCP tools `mcp__lamp__<name>`; `Engines.plainName` strips that.
  Codex reports them as `mcp_tool_call` items.
- **Models**: each engine has its own model list and picker (`Builder.engineModel`); never default to Haiku.

Before opening a PR that touches any of this, check each engine's `case` in `Agent.run` and its parser,
and say in the PR description which engines you tried.

## Two Lamps on one Mac

A build from source is **Lamp Dev**, a separate app from the Lamp people install: its own name and icon (an
orange DEV banner), bundle id (`dev.lamp.host.dev`), folders (`~/Library/Application Support/Lamp Dev`,
`~/Applications/Lamp Dev Apps`, `~/Library/Logs/Lamp Dev`), gateway and model-server ports, URL scheme
(`lamp-dev://`) and Keychain entries, and no self-updating. `Sources/Lamp/Edition.swift` is the one place
these come from, read off the bundle id that `build.sh` writes (`FLAVOR=dev` by default; `release.sh` passes
`FLAVOR=release`). Anything new that names Lamp on disk or on the network goes through `Edition`, and the
generated apps get it through the `{{SCHEME}}`, `{{NOTE}}`, `{{HOST}}` and `{{APPS}}` placeholders in
`Template.swift`. The app-signing keychain is shared on purpose, so apps keep their permissions whichever
Lamp rebuilds them. `scripts/dev-data.sh` copies your apps, keys, settings and the agent's sign-ins from the
installed Lamp into Lamp Dev, so the development build has something to work on.

## iPhone apps

**New iPhone & iPad App** (behind Settings → Building → Experimental, `Experiments.iosApps`) makes one app for both devices, as Apple has it; the app's right-click menu's **Try On** picks which simulator it opens in (`LampProject.family`). It runs in the iPhone or iPad simulator on this Mac (`LampProject.platform == .iphone`,
kept in `meta.json` and through renames). It needs Xcode, not just the Command Line Tools: `Simulator`
(`Sources/Lamp/Simulator.swift`) picks a booted or available iPhone with `simctl`, installs the built bundle,
launches it with its output going to the app's log, and photographs the screen for `look_at_app`. The
scaffold is a Swift package built for the simulator SDK by its own `build.sh` (no Xcode project, no signing
beyond ad hoc). It gets the same `LampSupport.swift` as a Mac app: the library is one source with the Mac-only
blocks (windows, `LampDriver`, `LampComputer`, folders and shortcuts, the clipboard, Mail, permissions, the menu
bar) under `#if os(macOS)`, `LampImage` standing for NSImage or UIImage, and the rest (`LampStore`, `LampAI`
and decisions, `LampScript`, `LampText`, drops, calendar, reminders, contacts, notifications, `LampAssets`)
shared. Type-check it for both SDKs after editing (`swiftc -typecheck`, once with `-target
arm64-apple-ios17.0-simulator -sdk $(xcrun --sdk iphonesimulator --show-sdk-path)`). The system prompt is
assembled from `Agent.Rules`: one rule per block, a `mac…`/`iPhone…` pair where the two kinds differ, so a new
block is described to both in one place. Before a launch, `Store.finishSimulatorBundle` does for the flat iOS
bundle what `deploy` does for a Mac one: usage descriptions, the icon (cut from `.lamp/AppIcon-square.png`,
which `Icons.write` makes from the same tile as the Mac icon) and the chat's attachments, then an ad hoc signature.
Every iOS app carries every usage description (`Template.iosUsageDescriptions`, one list for the scaffold's
build.sh, `finishSimulatorBundle` and the phone's Info.plist), so the agent only requests authorization.
What needs more, the agent declares in `capabilities.json` at the app's root (`Template.Capabilities`:
healthkit, nfc, siri, backgroundModes): Lamp turns it into an entitlements plist for the simulator's ad hoc
signature and the phone project's `App.entitlements`, which Xcode's automatic signing registers, and
`UIBackgroundModes` in Info.plist. `LampMotion` (iOS only, under `#if os(iOS)`) wraps Core Motion. The
prompt's `iPhoneHardware` rule lists what a phone has and what the simulator can't do.
`use_app` drives the simulator from outside the app (`Simulator.Driver`): the Simulator app shows the
iPhone's whole accessibility tree to the Mac, so Lamp finds what's under a point and presses it, sets a
field's text, and sends real mouse events for swipes, scrolls and long presses. Pictures are made at point
size, so a pixel in them is a point on the screen. That needs Lamp to be allowed in System Settings →
Privacy & Security → Accessibility; the first `use_app` asks.

**On the person's own phone** (Settings → Experimental → Put apps on your own iPhone or iPad,
`Experiments.devices`): Try On also lists the iPhones and iPads the Mac can see (`Devices.list`, through
`devicectl`): paired ones to choose, and plugged-in ones that haven't trusted the Mac yet, which it offers
to pair (`Devices.pair`, `devicectl manage pair`, which puts the Trust prompt on the phone) before telling
the person about Developer Mode. `LampProject.device` remembers the chosen one. Play and the end of a turn then go through
`Store.installOnDevice`: `Template.writeDeviceProject` writes a small Xcode project under `.lamp/device`
(one app target over the package's Sources as a synchronized group, the icon in an asset catalog, the
attachments as a folder reference, a real Info.plist) and `Devices.build` runs `xcodebuild` with automatic
signing for the team in Settings (`Devices.team`, found from the Mac's Apple Development certificates), so
Xcode registers the phone and makes the certificate and profile with the account signed in to Xcode; Lamp
never holds the account. The bundle id carries the team (`deviceBundleID(team:)`). `devicectl` installs and
launches the app with `--console`, so what it prints reaches the app's log. The agent's looks stay on the
simulator: the phone's screen can't be photographed. The app reaches Lamp's gateway at the Mac's Bonjour
name (`Devices.macHost`, the `{{MACHOST}}` placeholder, chosen in LampSupport by `targetEnvironment`): the
gateway also listens on the network while the switch is on (`Gateway.setLocalNetwork`), marks those
requests, and admits them only to the app routes with the Mac's own name as Host (`Store.isMacHost`).

## Generated apps

`Sources/Lamp/Template.swift` holds `LampSupport.swift`, the support code copied into every generated
app (`LampAI`, `LampStore`, `LampScript`, the connectors, `LampDriver` for `use_app`). It is a Swift
string: after editing it, extract and type-check it (`swiftc -typecheck`), and bump anything that detects
an outdated app (`Store.open` rebuilds apps built by an older Lamp).

## Naming: Lamp and Lamp

The app is called **Lamp**: that's the name in everything the user reads (the interface, Help, the agent's
words to the user, the "Edit with Lamp" command in generated apps, the bundle and the DMG). **Lamp** is its
code name and stays in code, comments, type names (`LampSupport`, `LampAI`, …) and in everything existing
installs depend on: the bundle ID `dev.lamp.host`, `~/Library/Application Support/Lamp`,
`~/Applications/Lamp Apps`, the `lamp://` scheme, the `.lampapp` extension and the signing certificates.
Renaming any of those needs a migration, not a find-and-replace.

## Conventions

- Comments explain why, in plain prose; user-facing text never names files, types or frameworks.
- Verify in an isolated harness app rather than in the user's apps.
- No attribution lines in commits or PR descriptions.
