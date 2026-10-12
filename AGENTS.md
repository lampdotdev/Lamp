# Working on Lamp

Lamp is a Mac app that builds other Mac apps with an LLM agent. Read `README.md` for what it is and
`RELEASING.md` for how it ships. This file is for whoever (or whatever) edits the code.

## Keep the agent harnesses in step

Lamp drives three coding agents, chosen in Settings → Building: **pi** (bundled), **Claude Code** and
**Codex**. They are set up in `Sources/Lamp/Engines.swift` (`Agent.run`), one `case` per engine, and
the output of each is read by its own parser there (`parseClaude`, `parseCodex`, and pi's in
`Agent.parseLine`). When the Mac already has Claude Code or Codex (on the person's PATH, or inside the Claude or
ChatGPT app), Lamp runs that copy with the person's own sign-in and folder (~/.claude, ~/.codex), so nobody who
already uses one downloads or signs in again; Lamp's runs are kept apart from their setup by their flags
(`--restricted`, `--ignore-user-config`, …). Only when there is none does Lamp download its own (`EngineInstall`),
checked (the vendor's checksum and Developer ID team) and updated daily, with its own folder for sign-in and
state (`EngineInstall.environment`: `CLAUDE_CONFIG_DIR`, `CODEX_HOME`). Which copy is used is decided in one
place, `EngineInstall.path(for:)`: every place that runs one takes its path from there and merges
`EngineInstall.environment`, and reads the engine's state from `EngineInstall.configFolder`. Never look for a copy
anywhere else. `updates/api/engines.js` can hold Lamp's own copy back to a version.

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
  `.compacted`; Codex doesn't say, so its conversations are told again every few requests), and the person can switch it off (`Memory.isOn`, on by default, the checkbox at the top of Settings → Memory): off, there are no notes tools, rule or summaries, and Settings doesn't list the notes. The switch keeps the key it had as an experiment that was off by default (`experimentMemory`), so whoever chose then keeps their choice and only someone who never chose gets the default.
  What is worth saving is said in `save_notes`'s description: every word there is paid for on every call.
- **Approvals and privacy**: shell commands go through `/agent/approve` for every engine (pi's extension,
  Claude Code's hooks, Codex's hooks); file access outside the app's folder is checked the same way.
  Claude Code's and pi's approved commands come back confined (`Sandbox`: `sandbox-exec` with a profile
  that opens the app's folder, the system, developer tools, caches, temp folders and the network, and
  closes the rest of the home folder and both Lamps' folders), so nothing reads a command's text to see
  where it looks. Codex's hook can't change a command and a sandbox can't be nested, so Codex itself runs
  inside the profile (`Sandbox.wrapEngine`, with the copy in use and its folder opened and Codex's own sandbox off) and its
  commands with it. SwiftPM's own sandbox can't start inside Lamp's, so a `swift` shim first on the path
  (`Sandbox.bin`) gives `swift build`/`test`/`run`/`package` `--disable-sandbox`. Nothing reads a command's text
  for paths any more; don't bring that back.
  Lamp's own git (saving a version, Undo, restore, version names, the look for unsaved work) runs under the
  same sandbox, through `Versions.git` (`gitBlocking` where it can't await): the app's folder is the agent's
  to write, its `.git` included, and git runs the programs a repository names (hooks, filters, a signing
  program), so unconfined it would run whatever the agent left there. A new git call on an app's folder
  belongs in that helper, never in `Shell.run` directly. The one exception is the helper's own look at the
  person's Mac-wide git settings (`Versions.personalFiles`), which the sandbox closes: it reads files the agent
  can't write, runs no program, and opens to Lamp's git only the files those settings name, never a folder
  and never anything in Lamp's own folders. Nothing in an app's history is checked, cleaned or
  refused, and the agent may use git on it as it likes. On Lamp's own runs signing, hooks and the
  file-watcher command are off (`Versions.environment`): the sandbox closes the person's keys, and a hook
  could only stall a save.
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
  as before. A task goes along the route chosen for the app's text, when one was chosen; with none, along
  `AppAI.computerDefault`, which is not the text default: a Claude Code or Codex sign-in first, then one
  OpenRouter model (`AppAI.computerOpenRouterModel`), each picked by timing the same task, so change them by
  measuring again, not by taste. Through OpenRouter, Lamp runs the tool loop itself. Otherwise the task is one
  turn of a coding agent: pi gets the driver's tools through its
  extension (a tools file and `LAMP_COMPUTER_URL`, which posts each call to `/agent/computer`), Claude Code
  and Codex through `/mcp` with the task's own token (`Store.computerTasks`, never the build tools). The
  driver, approvals, element names and the task's limits (`ComputerUse.stepLimit`, `timeLimit`: every route
  ends there with a plain message, and what it spent is still recorded) live in `ComputerUse.Job` either
  way, so a change to what a task may do is made once.

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
installed Lamp into Lamp Dev, so the development build has something to work on. To see what someone with a bare Mac
sees, `LAMP_PRETEND_MISSING` (`Pretend`, Lamp Dev only) makes Lamp's own checks miss the Command Line Tools,
Xcode, the person's own Claude Code and Codex or tools from the PATH; a new check for something a fresh Mac lacks goes through it too.

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
size, so a pixel in them is a point on the screen. The same tree, read whole, is the screen as text that
`look_at_app` and `use_app` return beside the picture (`Driver.screenText`: one line per control or piece of
text, with the point to tap it). The app showing the simulator is Simulator, or from Xcode 27 Device Hub
(`Simulator.viewers`), which shows one device at a time: Lamp chooses the device in its list
(`Driver.choose`) and finds the screen a few layers down its window (`Driver.screenBoxes`: a group shaped like
the screen that Device Hub marks `iOSContentGroup`, an undocumented subrole; two candidates in different places
are refused). That needs Lamp to be allowed in System Settings → Privacy & Security → Accessibility; the first
`use_app` asks, by opening that page with a panel at the foot of the Settings window holding Lamp to drag into the
list (`SettingsGuide`; `LampPermissionGuide` in LampSupport is the same panel for a generated app's own permissions,
so a change to one is a change to the other). The driver runs on its own queue (`AccessibilityActor`), never the main thread, and no call to
the other app waits more than `Driver.patience`; when the screen can't be used, `Driver.Trouble` says which
reason it was, in words for the agent. Device Hub (checked on Xcode 27.0) doesn't pass on mouse or key events
posted to it, so there a scroll is the page scroll the iPhone's own elements offer, a row's swipe action is the
row's own named action, return is the on-screen keyboard's key, and a long press, a sideways swipe and escape
are refused with the reason rather than reported as done. Its list holds the devices added to it, not every
booted one, and it loses a device's display when the simulator restarts: both are told to the agent as they
are. `SimulatorLiveTests` runs the driver against a real window when `LAMP_LIVE_UDID` is set.

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

`capabilities.json` at an app's root is where the agent declares what the app needs beyond its code
(`Template.Capabilities`): for an iPhone app the entitlements and background work described above, for a Mac
app what Finder may hand it, `{"opens": ["folder", "png", "public.image"]}` ("folder", "file", extensions,
type identifiers). Each field has its own check and only what passes is used (`Capabilities.checked`),
whoever wrote the file. A new capability is a field there, its check, and where it lands: `apply(to:)` for a
Mac app's Info.plist (called in `Store.deploy`, as `finishSimulatorBundle` does for the simulator's bundle),
`lists` and `entitlementsPlist` for an iPhone app. A shared app carries the file as Lamp read it, checked,
and the copy's is written from what passed the same checks on the way in (`Sharing.Package.capabilities`);
such a file says it is format 4, so an older Lamp asks to be updated instead of dropping it.

`opens` becomes `CFBundleDocumentTypes`, one entry for each kind (macOS ignores a type's extensions once it
names content types), always as an alternative, so an app is offered for a kind of file and never takes it
from the app that opens it by default; a kind nothing else opens (a made-up extension) macOS gives to the
app. Without a declaration macOS hands the app nothing: Finder takes no drop on its
icon and doesn't list it in Open With, and the agent's confined `open -a App file` is refused with -10820.
With one, that command works, and `look_at_app` gives the agent the exact line (`Store.handingHint`): the
installed copy's path, since the copy in build/ or the bundle id starts a second copy beside the one Lamp
opened. `Agent.sandboxNote` says which failures are the sandbox's and not the app's; keep it true when the
profile changes.

### Widgets

A Mac app can have a desktop widget. The agent writes it in `Widget/` at the app's root (`Agent.Rules.widget`,
Mac only; an iPhone app is still told widgets aren't possible). Swift in that folder (`Template.hasWidget`,
asked before every build) gives the app's Package.swift a second program, built as an extension, and build.sh
puts it in the app as `Contents/PlugIns/<Exe>Widget.appex` with the bundle id `<app's id>.widget`. It is
signed by itself, sandboxed (`Template.widgetEntitlementsPlist`), before the app around it
(`AppSigning.command`): macOS shows no widget that isn't sandboxed, and the app stays unsandboxed. The widget
shares no code with `Sources/` and doesn't get `LampSupport.swift`, only its own small file (below). Nobody but the person can place a widget
(Edit Widgets), and `look_at_app` can't see one. A rebuild in place keeps a placed widget; moving the app,
which renaming it does, removes it.

A shared app (`.lampapp`) carries its widget's code in `Widget/`, never Lamp's own file there. Such a file
says it is format 3 (`Sharing.format(withWidget:)`; one without a widget stays 2), so a Lamp from before
widgets asks to be updated instead of building the app without it. `Sharing.Package.sources` is all the
code in a file, the app's and the widget's: the review reads that list and `Sharing.install` writes from it,
so add nothing to an app's code folders from a shared file by another way. The widget is read whatever
number the file gives itself.

Asking for a widget gives a widget and nothing that looks like an app. When a widget is all that was asked
for, the agent makes the app one scene, `LampWidgetOnly()`, and puts everything in the widget
(`Template.isWidgetOnly`: an app with a widget whose own code is that scene). Such an app has no window, is
kept out of the Dock (`LSUIElement`, written by build.sh), and Lamp never opens it in front of anyone. A
click on its widget opens the app, as macOS does for every widget, and shows nothing: the scene is a menu bar
item that is never put in the menu bar, so SwiftUI has no window to open for the click (a Settings scene
opened an empty Settings window). A link on the widget (`widgetURL`, `Link`) is sent to the app too, not
to the browser, so the app passes it on (`LampWidgetLinks`: it answers the request to open a link itself and
hands the link to whatever opens it, never back to itself); a widget with no link opens nothing. Whether a
widget has a link is the agent's choice, and the rule says nothing about clicks. A
widget that needs something an app must fetch or keep gets a real app, in the menu bar. Either way the chat
has one card (`WidgetCard`, a `.widget` line added at the first install with a widget): how to add the
widget, then "On your desktop". macOS gives Lamp no way to open Edit Widgets or to place a widget, so the
card only says how. It knows the widget is placed because the app it belongs to may ask macOS
(`LampWidgetPlacement` in LampSupport.swift) and leaves the answer in its runtime folder; a widget-only app
is run out of sight for that after a build and when Lamp comes back to the front, and quits by itself. The
agent is told to say two sentences at most and never how to add the widget: that is the card's.

The widget gets the app's data by asking the app (`Template.WidgetSharing` says why, and is the one place
to change it): macOS refuses an app group to a certificate with no team ID, which is how Lamp signs, and Lamp
doesn't use exceptions to the sandbox. `LampWidget.share(value, as:)` in LampSupport.swift keeps what the app
shares, answers on this Mac's own address at a port worked out from the app's id (`Template.widgetPort`) to
whoever sends the app's widget secret (`Template.widgetToken`), and reloads the widget. `LampWidget.read` in
`Widget/LampWidgetSupport.swift`, a fourth file Lamp owns and rewrites (`Template.writeWidgetSupport`, only
for an app with a widget), asks, and keeps the last answer in the widget's own sandbox for when the app is
closed. So a widget is as fresh as the last time its app ran. The secret never crosses the connection: the
widget signs its question with it and the app signs its answer over the question's nonce, so only the app's
widget is answered and the widget passes over anything else that took the port.

Lamp never replaces an app on disk while it's running (`HeldInstalls`): macOS then stops taking the running
app for its widget's owner and refuses its redraws until it's reopened. A build quits the app first; a new
icon or its artwork (`Store.installIcon`) waits for the app to close or for the next build. The widget's
own process is ended just before the swap too, and before an app is deleted (`WidgetProcess`, found by its
file inside that app or, for a copy running from elsewhere such as the Trash, by the widget's bundle id):
left alive it no longer matches the widget installed, and macOS fails every reload and leaves the widget
blank until that process happens to exit.

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
end in "Configure providers…", which leads here); **Memory**, what Lamp remembers and whether it does; **Experimental**, what the Lamp team is still working on, a tab that is there only while there is an experiment to show (none now: bring `ExperimentalSettings` back with the next one).
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
- Files committed to the repo (README, docs, code comments, tests) must never name a person, personal device or hostname, or narrate a particular session or test run; put those details in the PR description.
- Verify in an isolated harness app rather than in the user's apps.
- No attribution lines in commits or PR descriptions.
