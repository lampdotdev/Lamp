# Working on Lamp

Lamp is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

## Keep the agent harnesses in step

Lamp drives three coding agents, chosen in Settings → Building: **pi** (bundled), **Claude Code** and
**Codex**. They are set up in `Sources/Lamp/Engines.swift` (`Agent.run`), one `case` per engine, and
the output of each is read by its own parser there (`parseClaude`, `parseCodex`, and pi's in
`Agent.parseLine`).

A capability given to one engine must be given to all of them that can take it, in the same change:

- **Tools the agent calls** (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, the version tools, the notes tools): their
  names, descriptions and schemas live once, in `Resources/lamp-tools.json`. pi's extension
  (`Resources/lamp-tools.ts`) reads it for its definitions and holds only the `execute` bodies; Lamp's MCP
  endpoint (`Store.mcpTools`, `/mcp` on the gateway) serves it to Claude Code and Codex. A new tool is an
  entry there, an `execute` in the extension, its name in pi's `--tools` list (`Agent.tools`) and Claude Code's
  allowed tools (`Agent.run`), and a `case` in `Store.mcp`.
  Codex has no file tools of its own, so the endpoint also gives it `read`, `ls`, `find` and `grep`
  (`FileTools`, listed when the URL carries `files=1`): they mirror pi's built-in ones, and each call is
  checked by `Privacy.verdict` like pi's. Don't let a Codex shell command skip approval because it looks
  like a read.
- **Rules in the system prompt** (`Agent.systemPrompt`, `Agent.tryRules`): every tool is available to every
  engine (`look_at_app`, `use_app`, `plan`, `delete_file`, `offer_setup`, the version tools and the notes tools), so their rules all live in
  `tryRules`. The file tools only Codex is given have theirs in `Agent.codexNote`.
- **What Lamp remembers** (`Memory`): two short sets of notes, about the person (`about-you.md` in the
  support folder) and about each app (`.lamp/notes.md`), each with a one-line summary. They must cost the
  person tokens only when used: the agent is told just the summaries and opens the notes with `read_notes`
  when it judges a request needs them; `save_notes` replaces a set. The summaries go at the end of the
  request, in `Agent.run`, before the engine's `case`, not in the system prompt: Claude Code and Codex keep
  the one a conversation began with when it is resumed, so anything that changes between turns has to ride
  with the request. `Memory.brief` adds them once per conversation and again only when the notes were
  changed by someone else, going by what `.lamp/notes-shown.json` says that engine's conversation last knew;
  most requests carry nothing. A conversation its engine has compacted is told again (pi's and Claude Code's parsers report
  `.compacted`; Codex doesn't say, so its conversations are told again every few requests), and it is an experiment (`Experiments.memory`, off by default, in Settings → Experimental): off, there are no notes tools, rule or summaries, and no Memory tab in Settings.
  What is worth saving is said in `save_notes`'s description: every word there is paid for on every call.
- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
  Claude Code's and pi's approved commands come back confined (`Sandbox`: `sandbox-exec` with a profile
  that opens the app's folder, the system, developer tools, caches, temp folders and the network, and
  closes the rest of the home folder and both Lamps' folders), so nothing reads a command's text to see
  where it looks. Codex's hook can't change a command and a sandbox can't be nested, so Codex itself runs
  inside the profile (`Sandbox.wrapEngine`, with `~/.codex` opened and Codex's own sandbox off) and its
  commands with it. SwiftPM's own sandbox can't start inside Lamp's, so a `swift` shim first on the path
  (`Sandbox.bin`) gives `swift build`/`test`/`run`/`package` `--disable-sandbox`. Nothing reads a command's text
  for paths any more; don't bring that back.
- **What Lamp shows the user** (`BuildCard.activity`, `ToolCall`): tool names must be recognised in every
  engine's spelling. Claude Code calls MCP tools `mcp__lamp__<name>`; `Engines.plainName` strips that.
  Codex reports them as `mcp_tool_call` items.
- **Models**: each engine has its own model list and picker (`Builder.engineModel`); never default to Haiku.
  Where an app's text AI goes is an `AppAI.TextRoute` (an OpenRouter model, the Claude Code or Codex sign-in,
  pi with its key provider, or a model on this Mac), listed by `AppAI.textRoutes` for the pickers in
  Settings → Apps (an app's info panel only shows what answers it), and dispatched by kind in `AppAI.dispatch`. The default
  (`AppAI.defaultRoute`) is the local model that builds apps when there is one, else Sonnet through
  OpenRouter with a key, else the builder's own sign-in. Settings → AI Providers lists each provider and
  sign-in with its state, not what it's used for: that's in the menus that choose it. Decisions
  (`AppAI.decisionModels`, `AppAI.decide`) go to Jev
  through OpenRouter or TypeSafe, to OpenAI's Decisions API (`decideViaOpenAI`, the same questions in its
  predicate/choice/score shape), to a Jev-class model on this Mac (`LocalModels.decisionCatalog`, run on the
  bundled llama-server; `decideLocally` does what the model's serving shim does: one forward pass per
  question, probabilities read off the label tokens at the "Answer:" slot), or by text through what answers
  apps (`decideByText`). A decision model is never offered for text or building (`LocalModels.isDecisionModel`).
- **What answers apps, and offering better** (`Sources/Lamp/Capabilities.swift`): `AppAI.resolve(capability,
  for: app, in: .mac | .phoneAway)` is the one answer to "what answers text / decisions / pictures for this
  app, how well (`Resolution.Tier`: none, works, best), and what would make it better (`Upgrade`: a key, a
  download, a sign-in)". Settings → Apps' menus and Not Ready rows, the notes under an app's
  pickers, the sharing review, the keys a phone takes away (`keysForPhone`) and the agent's status line
  all read it; don't work any of that out again elsewhere. A failure for want of setup carries
  `AppAI.Failure.needs`; the gateway passes it to the app (`LampAI.Failure.needsSetup`, and
  `LampAI.isAvailable` asks `/ai/status`) and offers a setup card in the app's chat (`Store.offerSetup`,
  `SetupCard`, once per app and capability; "Not Now" keeps Lamp's own offers away from every app). The
  agent is told what the app has at the end of a request (`AIStatus.brief`, beside `Memory.brief` and sent
  the same way: once per conversation and when it changes) and raises the same card with `offer_setup`.
  Before adding a capability, a way to make one better, or a new offer, read `design/setup-card/README.md`:
  when an offer is worth making, how the card and Settings rows are built, and how to write their copy (for
  someone who has never heard of a key or a model, never naming providers, routes or APIs).
- **Using other apps** (`ComputerUse`): two drivers behind one `ComputerUse.Job`. When the ChatGPT app has
  its Computer Use plugin installed, Lamp drives that (`CodexComputerUse`: the `cua_repl` MCP server from
  `~/.codex/plugins/cache/openai-bundled/unified-computer-use/<newest>/.mcp.json`, one `js` tool in which the
  model writes JavaScript against `cua`; the server asks before each step through MCP elicitation, which
  `MCPClient` answers from `Job.decide`: reads go ahead, actions through the person's approval). It isn't a
  documented interface, so when it's missing, off (Settings → Apps), or won't start, CuaDriver's tools are used
  as before. With an OpenRouter key, Lamp runs the tool loop itself against
  OpenRouter. Without one, the task is one turn of the builder: pi gets the driver's tools through its
  extension (a tools file and `LAMP_COMPUTER_URL`, which posts each call to `/agent/computer`), Claude Code
  and Codex through `/mcp` with the task's own token (`Store.computerTasks`, never the build tools). The
  driver, approvals and element names live in `ComputerUse.Job` either way, so a change to what a task may
  do is made once.

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

A new app's intro (`NewAppIntro`) and the welcome's first-app step (`IdeaStep`) have Mac / iPhone / iPad radio buttons (`AppKind`, `Store.setKind`), and the starter ideas follow the choice (`Ideas.phonePool`). New App makes a draft, a folder with only `.lamp/meta.json`
(`Template.draft`), so its kind and name are just that file; the scaffold is written and committed when it first
builds (`Store.materialize`, in the first turn after naming and in `run`), and `LampProject.scaffolded` tells the two apart. An iOS app is one app for both devices, as Apple has it; the radio buttons and the app's right-click menu's **Try On** pick which simulator it opens in (`LampProject.family`). It runs in the iPhone or iPad simulator on this Mac (`LampProject.platform == .iphone`,
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

**On the person's own phone**: Try On also lists the iPhones and iPads the Mac can see (`Devices.list`, through
`devicectl`): paired ones to choose, and plugged-in ones that haven't trusted the Mac yet, which it offers
to pair (`Devices.pair`, `devicectl manage pair`, which puts the Trust prompt on the phone) before telling
the person about Developer Mode. `LampProject.device` remembers the chosen one. Play and the end of a turn then go through
`Store.installOnDevice`: `Template.writeDeviceProject` writes a small Xcode project under `.lamp/device`
(one app target over the package's Sources as a synchronized group, the icon in an asset catalog, the
attachments as a folder reference, a real Info.plist) and `Devices.build` runs `xcodebuild` with automatic
signing for the team in Settings → Building (`Devices.team`, found from the Mac's Apple Development certificates), so
Xcode registers the phone and makes the certificate and profile with the account signed in to Xcode; Lamp
never holds the account. The bundle id carries the team (`deviceBundleID(team:)`). `devicectl` installs and
launches the app with `--console`, so what it prints reaches the app's log. The agent's looks stay on the
simulator: the phone's screen can't be photographed. The app reaches Lamp's gateway at the Mac's Bonjour
name (`Devices.macHost`, the `{{MACHOST}}` placeholder, chosen in LampSupport by `targetEnvironment`): the
gateway also listens on the network while some app is set to open on a phone (`Store.syncLocalNetwork`), marks those
requests, and admits them only to the app routes with the Mac's own name as Host (`Store.isMacHost`).
Away from the Mac, a phone app answers for itself (`LampDirect` in LampSupport, device builds only): `post`
first asks `/ai/keys` with a four-second timeout, at most every half minute; while the Mac answers, the
call goes through Lamp as ever and the reply (the OpenRouter key, the TypeSafe key when decisions go there,
and the app's model choices, served by `Store.keysForPhone` only for iPhone apps) is kept in the
phone's Keychain; when it doesn't, `LampDirect.handle` does
what the gateway would with the provider directly (chat completions with the JSON retry, systemone
decisions, images). The prompt's fencing and dates are made in the library either way. What's spent this
way isn't recorded in Lamp, and `/ai/computer` says it needs the Mac.

## Generated apps

Lamp owns three files in every app and never trusts what's in them: `Sources/LampSupport.swift`, `build.sh`
and `Package.swift` are written afresh before every build (`Template.writeOwnedFiles`), and the build stops if
that fails. The last two are what the build runs (the shell runs build.sh; SwiftPM compiles and executes
Package.swift as a program), so they're replaced rather than checked: nothing the agent's file tools wrote
into them, with no card, can run. Shared apps never carry them: import writes its own.

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

## Interface

Lamp's screens drift as features land: each adds its own explanation, warning or status, and an earlier
tidy-up is undone. Before adding to any of them (Settings, the welcome, the chat and its cards, the build
card), check:

- **Is it a choice, an action, or the fix for one?** Screens are for doing, not explaining. Labels say what
  something does; a note is only for what the person must accept to decide (an install, a permission, a
  cost), in a sentence or two. No footers, captions, or badges summing up what something is used for.
- **Can it be used now?** A control appears once it does something. Until then, its place shows why not
  and the one thing that fixes it (Not Ready, a gray line, a Download or Sign In… button): no menu of
  models that can't run, no field or switch that won't take effect yet. A menu lists only what works now,
  and one with a single option is plain text. Disabled is for a moment's state in a standard control
  (Remove with nothing selected), not for something that needs setting up first.
- **Does it ever contradict itself?** What's shown is what Lamp does: a menu shows the choice actually
  used, even when the saved one can't be. When all is well, say nothing; a problem is one orange mark and
  one gray line with its fix. Never a choice on screen with words under it saying it won't work.
- **Is this its only home?** Show a thing where it's chosen or changed, and from anywhere else link there
  rather than repeat it: repeats drift from what Lamp actually does. An experiment and its settings live in
  Settings → Experimental, under its checkbox; a feature leaving Experimental takes its settings to the tab
  whose job they are.
- **Does structure carry the meaning?** Related things share a group. What depends on something sits
  indented under it and shows only while that's on. Details for the curious (paths, versions) go in `.help`.
- **Same words for the same thing**, in every screen, Help and errors. Product names come from one place
  (`Engine.title`: "ChatGPT Codex"), never a literal.

### Settings

Each tab has one job: **Building**, how Lamp builds apps; **Apps**, what apps use while they run; **AI
Providers**, what's on this Mac, then cloud providers, with keys, sign-ins and downloads (other tabs' menus
end in "Configure providers…", which leads here); **Experimental**, what the Lamp team is still working on.
Lay out with the shared pieces in `Setup.swift`, and extend one rather than lay out by hand:
`SettingsCheckboxes` (on/off is a checkbox, box first, never a switch), `.underCheckbox()`,
`.checkboxNote(…)`, `NotReadyBadge`, `NotReadyRow`, `CapabilityNote` (the gray why-and-fix under Not Ready),
`ImageModelRow`, and `.settingsPane()` at the end of each tab. A PR that adds to Settings says which tab, and why the option needs to exist at all.

### The app's info panel

The info panel (`AppInfoView`, ⓘ in an app's toolbar) shows facts about one app; it chooses nothing. What
belongs: what the app has cost, what answers its AI (from `AppAI.resolve`, so it's what really answers),
how Lamp builds it, and where it lives. What doesn't: menus, switches, explanations, upgrade offers, or
anything that's the same for every app and already in Settings.

- **Read-only.** A thing that can be changed is changed in Settings: each section ends in one small button
  that opens the tab where it's chosen ("Configure Providers…", "Building Settings…"). The only exception is
  undoing what an app was left with by an earlier Lamp ("Use Settings' Choices", shown only when there is
  something to undo).
- **Facts, not notes.** A row is a label and its value. Nothing answers: `NotReadyBadge` as the value, with
  no sentence under it; the fix is in Settings, one button away. No footers or captions.
- **Fit the width.** Rows are `InfoRow`: the value beside its label when it fits, else under it, both
  left-aligned. Keep values short (`AppInfoView.short`), and keep the panel's width (`inspectorColumnWidth`)
  wide enough that most rows fit on one line.
- **Current.** The panel observes whatever its rows read (Settings, keys, the app's own choices, the models
  on this Mac), so a value never outlives what it describes.

## Conventions

- Comments explain why, in plain prose; user-facing text never names files, types or frameworks.
- Verify in an isolated harness app rather than in the user's apps.
- No attribution lines in commits or PR descriptions.
