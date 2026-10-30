# Generated apps

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp owns three files in every app and never trusts what's in them: `Sources/LampSupport.swift`, `build.sh`
and `Package.swift` are written afresh before every build (`Template.writeOwnedFiles`), and the build stops if
that fails. The last two are what the build runs (the shell runs build.sh; SwiftPM compiles and executes
Package.swift as a program), so they're replaced rather than checked: nothing the agent's file tools wrote
into them, with no card, can run. Shared apps never carry them: import writes its own.
What a shared file says still reaches build.sh: the app's name and its permission reasons. They are never pasted into
the script's code: `Template.write` sets them in single quotes at the script's top (`Template.shellWords`) and the
script reads them as variables, so no name runs, ends a heredoc or breaks a quote, and names stay as free as they are.
Replacing them isn't enough on its own: they sit in the agent's folder, and a command it left running can put
its own there between Lamp writing them and running them. So the build runs as the agent's commands do, in the
app's sandbox (`Store.runBuild`, through `Sandbox.run`), and so does everything else Lamp runs over what's in
that folder: the compiler's looks at the code for live changes and Undo (`LiveReload`), and the finishing of a
simulator bundle (`finishSimulatorBundle`). Xcode's builds are no different: the phone's and the Mac half of an app
for both build in the sandbox with signing off. Only a copy Lamp made in its own folder is signed with Lamp's or the
person's keys (`Store.deploy`, `Devices.signedCopy`, `TeamSigning`). A new command of Lamp's that reads or runs what's
in an app's folder belongs in `Sandbox.run`, never in `Shell.run` directly.
What Lamp itself writes there around a build (its own files, what the build was made from, the stamp in the built
app, the live copy's records, the simulator bundle's files) goes through `AppFolder`, which follows no link on the
way: a build can leave one where any of them goes. Writes that aren't part of a build (the notes, meta.json) don't go through it.

`Sources/Lamp/Template.swift` holds `LampSupport.swift`, the support code copied into every generated
app (`LampAI`, `LampStore`, `LampScript`, the connectors, `LampDriver` for `use_app`). It is a Swift
string: after editing it, extract and type-check it (`swiftc -typecheck`), and bump anything that detects
an outdated app (`Store.open` rebuilds apps built by an older Lamp). The stamp is read where the app runs from: a Mac
app's installed copy, an iPhone app's own build (what the simulator gets), and never a Mac copy for the iPhone half of
an app for both. A game's or a screen's Mac copy made from Lamp's player carries the player's version too
(`BuildStamp.player`), and is made again, in a second, when it's another player's or the app has come to be compiled
("Lamp's player" in the devices guide). LampSupport.swift is compiled into the player as well, so a change to it reaches
games and screens with the next Lamp build, and nothing else needs bumping for them.

A Mac app's reasons for its permissions are one list, `Template.macUsageDescriptions`, written by build.sh, the
Mac half of an app for both (`universalMacInfoPlist`) and `Store.deploy`: macOS kills an app that asks for
the photo library, Bluetooth, the camera and the like without one. A new one goes in that list and nowhere
else, only for something macOS refuses without it (location and music are asked about with none), and is
named in the prompt's `{{EXTRA_PERMISSIONS}}`. The list is part of `BuildStamp`, so apps built before a
reason was added are rebuilt when next opened.

`use_app` on a Mac app is carried out by the app itself (`LampDriver`, reached by a distributed notification
signed with the app's token, `Store.use`), so no Accessibility permission is needed. With every picture the
app writes its front window as text (`LampScreen` in LampSupport.swift, `.lamp/runtime/screen.txt`): one line
per thing its own accessibility tree names (NSAccessibility walked in-process, SwiftUI's elements included; a web
view's insides are never walked, so a page in LampPage.swift's host adds its own things through `LampPageItems`, read
by a script in the page, "Where the agent looks at it" in the devices guide), with a short id, what it is, its name, what it holds and its middle in the picture. `look_at_app` and `use_app`
return it beside the picture (`Runtime.screenText`), the same lines the iPhone driver writes. An action names
what it's for by `target` (an id or exact name, `LampScreen.find`): a button, switch, link or choice is asked
to press itself (`accessibilityPerformPress`), a field takes the text in place of what it held, a slider or
stepper takes a number or a step, and what has no action of its own, or isn't listed (a drawing, a canvas),
is clicked at a point, pixels in the picture. Lamp tells an app built before the list existed by a line of the
heading in its binary (`Store.screenTextMarker`): such an app is told to be rebuilt when a target is used.

**Showcase mode.** An app opened with `LAMP_SHOWCASE` set to a folder holding a showcase.json is being recorded for
a reel (`LampShowcase`; "A starter's reel" in the desk guide): it keeps its data in that folder, starting empty
(LampStore imports any `data/<name>.json` there), LampAI's calls are answered from the script (every route, through
`LampAI.post`), LampLocation is where the script says, notifications are logged and not sent, and no `LampSchedule`
runs. Once its window is up, and the recorder has its first frame (it leaves a `recording` file in the folder; with
none in two minutes it plays nothing and logs why), it plays the script's steps on it with `LampDriver`'s own actions
(`LampDriver.playShowcase`), so it needs no Accessibility permission, and logs everything to events.tsv with the
time and the frame of what it acted on, which the reel's edit lines up with the recording. The app's own code for its
microphone, camera or speech asks the script while it's on (`LampShowcase.hear`, `speak`, `file`, `line`); nothing of
the person's is read, so the reel shows none of it.

`use_app` happens in plain sight, and the person can take the app back at any moment (`Handover`). While the
actions run, the window in use glows, Lamp's cursor (a fingertip over the simulator) goes to each spot before
anything happens there with a word on what it's doing ("Lamp · clicking Add"), and a pill above the window says
"Lamp is trying <app>" with Stop and esc (`ComputerOverlay`, the same signs an app's use of other apps shows). The glow, the pill and the cursor sit just above that window in the stack, not over every app, so a window
the person brings in front of it covers them too (`ComputerOverlay.stack`). Nothing tells Lamp when another app's
window is raised (the notice that an app came forward arrives before it raises its windows), so the order is checked
with the glow's frame as it follows the window. A
Mac app says where each action is about to happen (`LampDriver.aimed`, a distributed notification whose object
carries it, since a sandboxed app may send nothing else) during the pause after the action before it, with the
time until it happens, so the cursor is there when the action is due and nothing waits for it (`LampDriver.step`;
Lamp paces the glide to that, `Handover.aim`). Only an action whose spot couldn't be sent ahead (the first of a
batch, a target that wasn't on screen yet, a window that opened since) waits `Template.useAppLead` for it. The
simulator's driver does the same: the fingertip goes to the next action's spot while the picture is taken
(`Simulator.Driver.spot`). The person takes the app back with Stop, with Esc while Lamp or the app is in front, or by clicking or
typing in it themselves. A Mac app sees their own presses as they reach its event queue (`LampDriver.Handover`):
the driver's events go straight to the window and never pass through it, and the one kind that does (a key held
down) is marked. Lamp's Stop reaches it as a stop signed with the app's token like the request
("lampUseAppStop" marks the builds that take it; older ones are rebuilt first). For the simulator Lamp watches
for a click that lands on its window (the window server's own hit test, `Handover.owner`: a click on another app's
window over it is that app's) or a key while it's in front (`Handover.isPersons`), and marks the taps and keys it
posts itself. Either way the rest of the batch is dropped, keys held down are let go, the Simulator isn't
brought forward again, the pill says "You have the app. Lamp stopped trying it.", the chat gets a "Trying it:
stopped by you" line, and `use_app` answers how far it got and refuses further calls until the person's next
message reaches the agent (`Turn.tookOver`). `UseAppStopTests` compiles the app's half out of the template and
drives it with real events. The pill's outline, and the approval card's, take no clicks (`allowsHitTesting(false)`):
a capsule's stroke counts a click on the line through its middle as its own, which is where Stop's middle is, and a
click the outline took in that panel never reached the button.

A Mac app can be changed while it's in use (apps show the wand while the file `MagicPanel.flag`, which Lamp writes
at launch, is beside their folders, checked each time a window comes forward): `LampMagic` in LampSupport.swift puts a
wand at the top right of each of its windows, which opens the app's chat beside that window
(`LampSidebar`; where it goes is below) and stays where it is while the chat is open, lit, closing the chat when
clicked again, so people always find it in the same place (`LampMagic.showWand`); the app menu's Customize with Lamp… (⇧⌘E) opens it too (`LampSidebar.openFromMenu`), and in Lamp's panel
(`ChatPanel`) when the app has no window to put it beside. In a window with a title bar the wand is a title bar accessory. A
window whose content runs under a title bar with nothing in it (a game, `.hiddenTitleBar`) has no bar for it, and an
accessory would give it one: there the wand floats at the top right over the content, level with the traffic
lights, on a dark disc of its own so it shows over any content (`LampMagic.isFullBleed`, `float`, `FloatingWand`). The wand
is wherever the app shows itself, so people can count on finding it: a menu bar app's panel has it in its header beside the
app's own buttons (`LampPanelWand`, which the menu bar rule asks for), or, in a panel whose code doesn't place it, in
a strip of its own above the app's content (`LampMenuBar.PanelWand`), and a menu has Customize with Lamp… with the
wand's symbol beside Settings… and Quit. Either opens the panel as a window of the app's (the one shown when the icon
is hidden) with the chat beside it (`LampMenuBar.customize`, which Customize with Lamp… does too when there's no
window), since a panel closes at any click elsewhere; a change that reopens the app opens that window and its chat
again, only just after such a quit (`chatQuitKey`). A Mac widget has it in its top right corner (`.lampWand()` in
Lamp's own widget file, which the mac-widgets skill asks for): a link the app takes as Customize with Lamp…
(`LampWidgetLinks`, which passes every other link to SwiftUI, or for a widget-only app to whatever opens it).
This is how a new app is changed from its first build on:
as soon as a new Mac app's scaffold is built and opened at the start of its first turn (`Store.showEarly`, then
`Store.present`; else at the agent's first look, or at the end of that turn), Lamp's panel, where its chat was until then, closes and the app opens the chat beside its content, so the rest of the turn's passes go
in while the person watches (`MagicPanel.handOff`, once per app, marked by `.lamp/sidebar-handed-off`; the panel
closes only once the sidebar has connected, so Lamp neither quits nor leaves the chat nowhere). A wish whose apps are all
in folders of their own has its chat beside its one Mac app with windows (a game in Game/), the same way
(`Store.chatApp`): that app's sidebar connects as the wish (`SidebarServer.accepted`), so it shows the wish's chat,
the only one there is, and everything keyed by the chat (the panel closing, `isConnected`, pointing) goes by the
wish while the window and the app's copies go by that app. Lamp asks the app
with a file in its runtime folder for a copy still starting and a notification for one already running
(`MagicPanel.openChat`, `LampSidebar.openForLamp`). The first time the person closes the chat, a popover points at
the wand to say how to get back (`LampSidebar.coach`, once per app). The
chat is an ExtensionKit extension Lamp puts in every Mac app it installs (`Sidebar.install`: Sources/LampSidebar,
built with Lamp and copied into `Contents/Extensions/LampSidebar.appex`, with an extension point of the app's own,
`<bundle id>.lamp-sidebar`): macOS shows an extension bundled in the app without asking the person, in a sandboxed
process of its own whose view the app hosts (`EXHostViewController`) but can't draw, read or type into. Lamp draws
the chat's content, never the app: the extension shows what Lamp sends and passes on what the person does
(`SidebarWire`, one JSON value a line, in Sources/LampSidebarKit), so all the chat does stays in Lamp
(`SidebarServer`: the chat's state, the same that Lamp's own panel draws, "The chat's one screen" in the chat guide). Without Agent Details a finished turn's steps fold where they came, those just
before its answer into one line above it, "Worked for 2 min 3 s" from the turn's summary, which opens to show them
(`ChatItem.items(gather:)`, `ChatLook.Worked`); a turn still going shows its steps as they come. The screen is LampSidebarKit's (`ChatScreen`, with
`Composer`, the message box, and `ChatLook`, the bubbles, statuses, cards, Stop and Send), the one Lamp's panel draws,
so a change to how the chat looks is made there and reaches both; the sidebar program is part of `BuildStamp`, so
apps installed with an earlier one are built again when next opened. It reaches Lamp on this Mac's own address at `Edition.sidebarPort` (macOS keeps other apps, Lamp
included, out of an extension's folder, so a socket there can't be made), and Lamp listens to a connection only
after finding which process is on its other end (`Sidebar.app(on:)`, by the connection's port among the processes
running a sidebar) and checking that it runs the very extension Lamp signed for that app: the hash of what was
signed is kept in Lamp's own folder (`Sidebar.remember`), and the extension is signed with the hardened runtime so
nothing can be loaded into it. Lamp writes each hash it keeps (or why it couldn't), each copy swapped in, and each
connection it turns away with the check that failed, to the unified log (`Sidebar.log`, category `sidebar`, with the
same category on the extension's side), so a chat that never came up can be traced. A refused sidebar tries again
twice a second; once it has gone `ChatWait.patience` without a chat it could show, however often it reconnected, it
says Lamp couldn't open the chat there and offers Open in Lamp, which shows the wish's chat in Lamp's panel
(`lamp://chat`, `Store.showChatInLamp`). The extension must start as Apple's own do, through `_NSExtensionMain` (the linker's
entry point), or it crashes before its code runs. Whatever the app's process can do, its generated code can, so the
app has no way to speak to the agent that builds it: it only shows the chat, says where its window is, and closes or
moves the panel when the chat asks (`LampSidebarHost`, the one thing the chat asks of it). The draft
is the store's (`Store.updateDraft`), so it goes with the chat wherever it's drawn. A sidebar left open opens again with the app's first window when
the app reopens (`LampSidebar.restore`). An app
installed without the extension (by an earlier Lamp) shows its chat in Lamp's panel instead. Most changes go into
the open app (below); for one that reopens it, the rule (`Agent.Rules.macGenerated`) tells the agent so and asks it to
keep what the person was looking at in `@SceneStorage`, so it comes back as they left it. As the app quits it leaves where its front window was in its
runtime folder (`LampMagic.leavePlace`), and the new copy opens its first window in the same place (`putBack`). Lamp
puts no picture of the window in its place meanwhile: a copy that opens no window (a menu bar app) left one standing
until it timed out.
While Lamp builds a change for a Mac app that's open, smoke in Lamp's stripe colors curls up from the bottom of the app's
windows, with a faint glow round their edges, and as the change goes in the stripes roll up across them on the slant, covering the window at the middle of the roll (`AppTransition`, drawn by
`LampTransition` in LampSupport.swift). It starts in `Store.build`,
lands in `reloadInPlace` (or, after a reopen, once the new copy's window is on screen, `landWhenShown`), and fades after `install` otherwise (held for Reload,
kept open, failed); Lamp renews it while the turn goes on and the app lets it go after 90 seconds unrenewed. The app
draws it in clear child windows that let clicks through and are left out of its pictures (`windowsOnScreen`), so the
builder never sees it; requests are signed with the app's token, with their time and an id, and taken once. An app
built before it has no `lampTransitionSignature` in its binary and is sent nothing: its next change reopens it with
the new building blocks. How it looks is `LampTransition.Look` (TransitionLook.swift), compiled into Lamp too and copied into the template by `scripts/sync-transition-look.sh` (`TransitionLookTests` fails while they differ): change it there and try it in the gallery's Transition entries, over made-up app windows or on an open app.

Where the chat goes (`LampSidebar.show`): always a panel of its own beside the window, never inside it (a column there
took more room from the app than it gave the chat). It's a borderless `NSPanel` attached as the window's child
(`LampSidebar.Beside`), so macOS moves, stacks, hides and takes it to Stage Manager's strip and other Spaces with the
window, holding the chat on a card of the chat's own paper (`LampSidebar.card`, `LampSidebar.Paper`, and `chatGround` in
the chat), opaque: glass let what's behind the window show through, which drew the eye from the chat, and drew a bright
line round its edge. It goes on the side with room, the right first, at its kept width or
the room there is down to its narrowest. Opened where neither side has room, the window makes some (`makeRoom`): it moves
over on its screen when that's enough, else it's made narrower, never below its own smallest width, to leave the chat its
narrowest on the right, and gets the width back when the chat closes (`narrowedBy`, each window its own; a change that reopens the app hands it
to the window put back in its place, `handOn`; given back after full screen when the chat was closed there). Only where neither can be done (full
screen, a window that can't be that narrow) does the chat go over the window's right edge, below its title bar, still its
own panel (`Chat.over`). A move or resize the person makes never moves or narrows their window: the chat changes side, or
goes over the edge when neither side has room, and back beside when there's room again (`replace`); going in and out of
full screen takes the panel down and puts it back where it now goes. Dragged by the chat's bar, the panel comes away from
the window (`Beside.detached`): no longer its child, it goes where it's put, floats over the app's windows while the app is
in front, and stays there through the window's moves and the chat closing and opening again, until the app quits (or the
window goes full screen), when it goes back beside the window. The press lands in the chat's process, so the chat asks the
app to move it (`startMove`) and the app follows the pointer until the button is let go. The chats' process can't
tell which of an app's chat connections is its own, so it asks over each with one request id, and the app picks the
chat once per request (`LampSidebar.isAsked`: the one under the pointer, else the one with the keyboard). Beside the window the chat is
dragged wider or narrower by an edge of its own (`Edges`, the panel's outer side, or the side facing into the window when
it's over it); moved away, by any edge or corner. The edges are a rim inside the card around the chat (`Beside.rim`), not
room around it: the glass glows a little past its edge, and a margin showed that glow cut off square by the panel. The width stays between
`LampSidebar.narrowest` and `widest` and is kept for the app (`LampSidebar.width`). The edges sit beside the
chat, never over it: the chat is drawn by another process, which takes every click on its part of the window. The panel
is told outright to take mouse events (`ignoresMouseEvents` off): its glass is drawn by the window server, so its own
pixels are clear, and a clear window lets clicks on clear pixels through. The panel takes the keyboard for the message box
without becoming the main window. The chat's bar is one row drawn by the extension (`ChatBar`): a red close button like a
window's, which asks the app to close the chat (`closeChat`), "Customize" and the app's name, then the buttons: Wish Info,
Share (the file is made by Lamp and handed over whole, `SidebarState.sharing`, since the extension can't read it; sent
once, so the extension keeps it as it's read, `Link.sharing`, as one lasting file per wish in a folder of its own under
its caches folder, since Lamp's process draws every wish's chat and one wish's share mustn't remove another's; each share
replaces it in one step, `SharedCopy`, as Lamp's own Share… does), Agent Details and Delete, then Undo Last Change and Versions.
A wish that opens anywhere but this Mac alone (a game, a screen, an app for both) has Try On's device button before
Undo, which stays with it: where it opens, a tick on where Play puts it, and for a game or a screen "… Too" for each
place it hasn't got. Its choices are one list, `TryOnMenu`, which the desk's menu draws as well (`SidebarState.tryOn`, a
click sent back as `SidebarCommand.tryOn` and done by `Store.tryOn`; beside the app, where there's no Play, a place
chosen is where it opens at once).
The bar is laid out one way at every width, beside an app and in Lamp's panel alike: Undo (with Play and Try On before
it where they show), and a button for the rest, which pressed stays lit and puts the rest, Versions beside Undo, in the
title's place. Play shows only once there's something to play: during a first build Lamp opens the app itself. The room between the buttons moves the chat. ⌘` goes
through the app's windows with each open chat right after its window (`LampSidebar.watchCycling`), since macOS leaves
panels out of its own cycle. Versions and Wish Info show as panels in place of the chat (`VersionsPanel`, a page of versions at a time with the rest a click away; `InfoPanel`; the info rows are
`AppInfoView.sections`). An app's chat is in one place at a time: when it opens beside the app, Lamp's panel for it
closes (`MagicPanel.chatOpenedInApp`). Where there's no Mac window to put it beside (a wish not yet made or being found,
a menu bar app, a widget, a background app, an iPhone app, an app built by a Lamp from before the sidebar) the chat is in
Lamp's panel, and setup cards' keys, sign-ins and Image Playground are in Lamp's sheet (`SetupSheet`), "The chat's one
screen" in the chat guide. An app opened for its chat that never connects one (it couldn't start) has its chat shown in
Lamp's panel (`MagicPanel.showChatIfAppNeverComes`), and so does one that crashes, quits while a turn is going on, or
quits because it moved off the Mac (to a TV, a phone or another device, whether the place was chosen just before the quit
or just after), with its chat beside it (`MagicPanel.showChatAfterQuit`, once three seconds have passed with no copy
running: a change that reopens the app leaves a moment with none). A plain quit of an app that still opens on the Mac
leaves its chat closed, and so does a later change of device for an app whose chat the person closed (`ChatReturn`).
Closing the chat beside the app only hides it, and its connection stays, so the app tells Lamp it was closed
(`LampSidebar.close`, `MagicPanel.closedInApp`): a chat the person closed there stays closed when the app moves off the Mac. The chat is drawn by another process, which AppKit's focus doesn't follow
(what had the keyboard, a list say, keeps it through a click in the chat), so once a click in the chat has landed the
keyboard goes to it (`LampSidebar.watchClicks`). Point at the Screen is an item of the + by the message box, beside
Attach a File…, in both chats (`ChatLook.MessageBar`'s `point`, `PlusMenu`) while the app is open on this Mac (`MagicPanel.point`; from Lamp's panel, Lamp comes back in front when it's done). It lets the person point at part of the app: the app lays a clear window over its own (`LampMagic.Picker`), kept above the app's own panels, sheets and alerts however high they float, but no higher, so other apps' windows still cover it (`Picker.keepOnTop`), and what's in them is pointed at and pictured as shown, outlines the smallest named
thing under the pointer from its own accessibility tree (`LampDriver.elements`), a click where nothing is named (a game's
ball, a drawing) takes the area around it, and a drag draws a box of the person's own; it then leaves a cropped
picture in its runtime folder and says what it is (an area is named by where it is, "Top left area"); Lamp attaches that picture to the message, named after the
thing ("Save button.png", `MagicPanel.name`), and takes a picture only from that folder. In both chats' message boxes it is
one pill (`ChatLook.PointedPill`: what it is and what it's part of, from the app's own row or the heading above it),
which a click points again and its × lets go; pointing again replaces it, and nothing is left drawn over the app.

A build asks the app to quit before it replaces it, and the app's answer decides (`AppQuit`). An app may ask
about unsaved work first: Lamp sends the quit request itself and reads the reply macOS carries back, which is
"cancelled" when the person keeps the app open and doesn't come while the question is still up. Until then Lamp
waits, with the app in front and "Waiting for … to close…" in the chat. Kept open, the app isn't replaced: the
chat says so, the build waits like a held icon (`HeldInstalls`) and goes in when the app closes, and a look tells
the agent that what's on screen isn't its change and `use_app` is refused (`Turn.keptOpen`,
`Runtime.holdsBuild`); a turn asks the app once. Lamp ends an app itself in one case only: it agreed to quit and
is still there. One that doesn't answer may be stuck or in the middle of a long save, and from outside the two
look the same, so Lamp never ends it: a copy that answers Lamp's "still there?" (`LampRuntime` answers on the
main thread, and says it listens by leaving its process id in its runtime folder) is asked that before it is
asked to quit, and when it doesn't answer the chat says so beside a Force Quit button (`UnresponsiveNotice`,
`Store.notResponding`), with what the click costs: anything unsaved in that app. The click is the only thing
that ends it. A build that waits for an app for both
goes in only while Try On points at this Mac. Don't add a time limit after which an app is ended anyway: that
is what lost people's work.

A wish goes on GitHub as a repository on the person's own account (`GitHubRepo`, its card `GitHubRepoCards` and
`RepoCard`, from the chat's Share menu): the shared file's contents (`Sharing.export`, so the same checks and the same
credits chain) unpacked, Lamp's own files for each of the wish's apps beside them (`GitHubRepo.ownedPaths`: the files
the builder can't delete, laid out as the shared file lays the apps out, `Sharing.layout`; for a page, the app around it,
`ScreenKit.paths`), the shared file itself, a
README, and an MIT license by choice, never offered when
something the wish is based on is share-alike. The README promises `zsh build.sh` only for a kind whose script builds
with Apple's tools and nothing of Lamp's (`Recipe.buildsAlone`: the Mac app's; an app for the Mac and the iPhone is
built by Xcode from a project Lamp keeps, so its README says Lamp builds it). The README leads with trying the wish
before changing it: in a public repository, an Open in Lamp button (`GitHubRepo.openButton`, drawn into `.github/` by
`writeButtons` as lamp.dev's buttons are, words alone), after Play in your browser for a game with a page, both to lamp.dev's remix link
(`GitHubRepo.remixLink`, `RemixLink.site`: the repository without a commit, so it's always the latest, and `from=readme`
for the site's counts); then the wish's ideas (`RemixSuggestions`, a starter's tweaks), each that link with its request.
A private repository, which Lamp can't fetch without a sign-in, offers the Share Link and the shared file instead; the
card stages again when a new repository is made private (`setPrivate`). A public repository with no website of its own
gets the remix link as its website (`offerRemixAsWebsite`, `from=github`); one the person set is left alone. One commit per Put on GitHub, on top of
what's there (a shallow clone, the tree replaced; unchanged when only the export's own marks differ), never the wish's
own history, which holds every version and the chat's attachments. The repository is remembered by the wish's instance
in Lamp's own folder (`GitHub Repositories.json`, with whether it carries the license, which an update keeps to), as a
published page is. `gh`, the sign-in and the repository name come from `Publish`, which shares them. The file's credits
name the repository on the chain's last link (`Credits.Remix.url`, `Sharing.export(repository:)`), so a remix opened
from there links where it came from.

A repository opens in Lamp as a shared file does (`RepoImport`): File → Open from GitHub… takes its address (owner and
name, with a branch, tag or commit after `/tree/` or `/commit/`; `RepoImport.source`), Import Shared Wish… takes a
folder it was cloned into, and a wish's link may name it (`lamp://wish?file=https://github.com/…`, `Store.take(exact:)`).
The tree is fetched one commit deep with Lamp's own git, confined as every git command of Lamp's is (`Versions.git`, in
a folder of Lamp's with the network open, never asking for a sign-in), then copied into an import folder without the
repository's records (`.git`, builds) and the shared file beside the code, held to a shared file's limits, and read as
a shared file's contents are (`Sharing.open(unpacked:)`): the same review, the same checks, Lamp's own files written
afresh and never read from the tree (`Sharing.read` leaves LampSupport.swift and LampScene.swift out of the code, as
the install does). A folder holding only a shared file opens that file. The chain's last link takes the repository's
address when it has none (a repository put up before Lamp wrote it, or a folder's git remote, `RepoImport.repository`).
The person's folder is only read, never changed or removed. The chain's last link also takes the commit the tree is
at (`Credits.Remix.commit`, from the clone's HEAD, `RepoImport.repository`): the commit of its repository the wish
has, which an update is merged from and a contribution goes back on top of. Put on GitHub keeps the commit it pushed
in the wish's record (`GitHubRepo.Repo.commit`), and an export names the kept repository and commit on the chain when
its caller names no place (`Sharing.export`), so a file shared from a wish that's on GitHub says where it lives too.
A wish opened from one repository and put on another gets a second link for the new place (`Credits.remixed`,
`Remix.sameLink`): the chain keeps where it came from, and `Credits.origin(own:)`, the last link naming a repository
that isn't the wish's own, is what the info panel's Visit and Check for Updates… and Send Changes Back go by
(`AppInfoView.origin`).

Every wish with somewhere to be updated from has the same Check for Updates… in its Credits, Review Update… once
there is one, with a row that says "An update is available" or "Your app is up to date" (`AppUpdates`). The check asks
GitHub for the default branch's latest commit (`git ls-remote`, confined, no sign-in, no clone, no model), at most daily
by itself and coalesced across wishes following the same repository, and compares it with the commit the wish has.
Which repository a wish follows (`AppUpdates.route`): a wish from another wish follows that wish (below); a wish the agent
made from someone's own project follows the work it's based on (`Credits.basis`: the source marked `adapted`, else the
first with no mark either way, as credits from before the mark have it; a source marked `adapted: false` is never it, so
a wish that only uses a library has no route), when that's on GitHub with the commit it was taken at. A source with
no commit is offered nothing. A wish made from a tag or a branch other than the default is credited at that exact
commit, and its updates follow the default branch from there.

### Someone's project on GitHub, made into a Lamp app by the agent

A wish never guesses from a link what the person wants: a request naming a project on GitHub goes to the agent as
typed, with a line naming the github-projects skill (`GitHubProjects.note`), and the agent does what it asks. It reads
the project in a git clone of its own (`.lamp/reference/<name>`, an approved command like any other). To make an app
from it, it calls `lampify` (`Store.lampify`, `GitHubProjects`) before using any of its code and again when the app is
done. lampify's work is all Lamp's, so it asks no approval, and it never runs what the project holds.

- **The commit is pinned once.** The commit given is the one used; with none, the one the wish is already credited at;
  with none of those, the commit the address names, or its branch, tag or default branch read once
  (`GitHubProjects.pin`). A later call never moves a branch on by itself, and a commit other than the credited one is
  refused: moving on is an update's.
- **What's credited is what Lamp read.** The agent's clone proves nothing about what was copied, so lampify keeps its
  own untouched copy at the pinned commit in `.lamp/lampify/<owner>/<name>@<commit>`, checked to be that commit of that
  repository, and before each reuse checked file by file against that commit's tree, computed by Lamp rather than by
  `git status`, which could run what the copy's own git configuration names (`GitHubProjects.untouched`); a changed
  copy is fetched again (`GitHubProjects.snapshot`). It's fetched with Lamp's confined git (`RepoImport.clone`), and
  with the person's sign-in through `gh` for a project only they can read (`GitHubProjects.fetchAnyway`, as Put on
  GitHub… signs in): the agent's sandbox can't see that sign-in, so a private project reaches the wish this way. With
  `read_only` it only fetches and gives the copy's path, for explaining a private project: nothing is credited.
- **The credit** goes in through `Credits.add`, Lamp's own record included: the canonical address, the owner as author,
  the commit. Every license and notice file anywhere in the project (not its tools': `.git`, `node_modules`, …) is copied
  as it came into `Licenses/<owner>/<name>/` (two folders, so `foo-bar/baz` and `foo/bar-baz` never share one) at its
  path in the project (`RepoLicenses`): the license at its top in `licenseFile`, the rest in `noticeFiles`. The SPDX id is recorded only when Lamp can tell it for certain from a single
  license at the top; otherwise the credit says `LicenseRef-<owner>.<name>`, terms of its own with the texts as the
  authority, never a guessed id (GPL texts don't say "only" or "or later"). `adapted` marks the project the wish is
  made from, which its updates follow; a wish has one, and a library or assets it uses are credited `adapted: false`.
  At most 200 license and notice files are kept, the project's own first; more than that is said in the answer as
  something missing, never dropped silently. Every file a credit names goes with the shared file and comes back on import (`Credits.Source.termsFiles`,
  `Sharing.export`, `Sharing.open`), and sharing is refused while one is missing (`ShareCheck`).
- **The shape** (`GitHubProjects.shape`): the app's structure (`make_app_for`), its line (`Sharing.description`, the
  wish's or its root app's) and an APP.md naming what it's based on are looked for in the wish; then the wish is made as
  Put on GitHub… would put it up (`GitHubRepo.stage` with no repository: lamp-app.json from the shared file's manifest,
  credits.json, the icon, the license files, Lamp's own files, README) and opened again as Open from GitHub… does
  (`RepoImport.open`). Whatever sharing refuses (a license missing, a key in the code) is reported as something still
  missing, with the rest. The tree is kept in `.lamp/repository` for a look; nothing goes anywhere until the person
  chooses Put on GitHub….
- **A Lamp wish on GitHub** isn't rebuilt: the skill, and lampify when it's called on one, send the person to File →
  Open from GitHub….

That the agent lampifies a project before copying from it is the skill's instruction and the tool's answer; nothing
checks what was copied, so a project read in a clone and copied without lampify goes uncredited.

An adapted wish's Review Update… says what preparing it costs, then (`Store.prepareUpdate`) saves the wish as a version
and makes a separate copy of it, unsaved changes included (`Sharing.export`, then a wish of its own with Lamp's files
written afresh, "<Name> Update"): its own app, bundle id, data and agent session, so nothing the agent does or runs
reaches the wish. The update is fetched into the copy's `.lamp/update/` (blobless, pinned to the commit the check saw:
`latest/`, `files.txt`, `log.txt`, `changes.diff`, and the fetched `repo` for files as they were) and the request goes to
the copy, with a note saying where it all is and how to port it (`AppUpdates.note`). The job, in the copy's
`.lamp/update/job.json`, names the wish and the wish's version when the copy was made. After a turn in the copy that
finished with no error (`Store.settleUpdate`) the copy takes the update's commit in its credits and the review opens
(`Store.openPreparedReview`: `Sharing.review` of the copy as exported, `PendingImport.prepared`). Update puts the copy's
files in place of the wish's through the ordinary update path, never `mergeUpdate`, since the copy already has the
wish's changes; the wish keeps its own credits with the commit moved on, and the copy is deleted. If the wish changed
since the copy was made (`AppUpdates.isStale`), Update offers to prepare it again instead. Keep Both keeps the copy as an
app of its own, renamed after the wish; Cancel deletes it. Review Update… while a copy exists shows its chat, or its
review once it's ready. A base that's no longer on GitHub fails the fetch rather than making up a change. File → Open
from GitHub… on a project that isn't a wish offers Make App, a new wish whose first request is to make it into one.

A wish whose chain names where it came from is updated as it was opened
(`AppInfoView.updateFromRepository`; a starter's copy too, "Desk"): the repository fetched again and opened as any is,
which lands on Update or Keep Both for that wish (`Store.importRepository(updating:)`, carried through a review that
waits for the welcome, `Store.copy(of:among:updating:)`: whatever identity the repository's file carries, so a starter's
copy or a second copy made with Keep Both is the one updated). A wish unchanged since it arrived
(`Store.changedSinceArrival`: its files are the last version Lamp saved as an arrival, and nothing is unsaved; looked
at again once the update owns the wish, since a turn may have run while the review waited) takes the new code in
place. One changed here is merged by git (`Upstream.merge`, from `Store.mergeUpdate`), never replaced: the wish's own
git gets the repository as its `upstream` remote and fetches the recorded commit one deep (through `Versions.git`, so
confined to the wish's folder with the network open, and only ever fetched from); that commit's tree is read as a
repository is (`RepoImport.open`) and staged as the import would install it, and so is the reviewed package
(`Upstream.stage`: the code the review read, an Android app's moved into this Mac's package as `AndroidFiles.install`
moves it, the app's files, its notes and declarations, never Lamp's own files or the icon's pictures), each a tree in
the wish's git made in an index of the merge's own (`.lamp/merge`), the second committed on top of the first at
`refs/lamp/upstream`. `git merge-tree` merges the wish's files, the base and that commit three ways and the result
goes into the index and the files (`git read-tree --reset -u`), with the version saved first so Versions can bring the
wish back. What changed only upstream or only here is in place with no agent; the icon's pictures follow when the
icon changed upstream, for the design as git merged it (`Sharing.installArtwork`, never the file's design in place of
one changed here), the description when it changed upstream and not here, and an app the package brings that the
wish doesn't have is made as an update makes one (`Store.installParts`, `Merged.newParts`). A clean merge is saved
("Merged the latest from GitHub"), noted for the agent (`Versions.rememberMerged`) and built. Files both sides changed
in the same place keep git's conflict markers, and a request goes to the agent with a note naming them
(`Versions.rememberConflicts`: what the markers mean, `git show HEAD:<path>` and `git show refs/lamp/upstream:<path>`
for each side), to settle the obvious itself and ask (`ask`) only where it can't tell. The credits are merged by Lamp
either way, which moves the chain's commit on to the one fetched, so the next update is measured from there; the
wish's history stays a line (the merge is one version, never a merge commit), and nothing of it leaves.

The base, in order (`Upstream.Base`): the repository's commit, fetched; else the version of this wish's own history
the file says it was made from (`Upstream.ownVersion`: a file shared from a wish that lives nowhere names the version
its export was made from, `Sharing.export`, and a copy sharing on keeps that rather than naming its own, so a file
that comes back from whoever it was sent to merges against the version they were given, with no repository anywhere),
unless the last update brought in was measured against that same version (a file coming back again names the version
it was first given; the kept commit records its base as a trailer), in which case what that update brought in
(`refs/lamp/upstream`: a change the sender took back since is then taken back here, rather than read as unchanged);
else that, for a wish from a file updated more than once; else the version that arrived (its tree as a shared file
carries it, `Upstream.filteredTree`); else nothing. A part the package brings that the wish doesn't have is in the
kept tree (staged as the app it will be) but not in what's merged. The review sheet says so (`ImportReviewCard.changedHere`, "Already here,
changed here" in the gallery).

A wish that came from a repository can send its changes back: Send Changes Back… in the chat's Share menu
(`SidebarToolbar.canContribute`, `Contribute`, its card `ContributeCards` and `ContributeCard`, shaped as Put on
GitHub's). It stages the wish as Put on GitHub does (`GitHubRepo.stage`: the same checks for licenses and keys), forks
the repository to the person's account with `gh` when they have no fork (`Contribute.fork`), fetches the recorded
commit into a folder of Lamp's, puts the staged tree over it with the repository's README and license left as its
owner wrote them (read first) and its credits.json keeping its chain and taking only what the wish newly uses, commits that once in the person's name,
pushes it to a branch of the fork and opens a pull request on the repository (`Contribute.send`). The request's text
(`Contribute.summary`) is the wish's line, the names its versions since it arrived were given (never the requests
themselves, never the chat) and the files changed. The person's own repository is refused (Put on GitHub updates it).

On a Mac without Lamp (an app copied over, or kept after Lamp was removed), the wand is on all the same
(`LampMagic.isOn` when `LampMagic.lampInstalled` is false) and the chat beside the app is the sidebar extension with
nothing to connect to: once Lamp has been away a few seconds and macOS says no Lamp is installed (`Link.lampInstalled`,
from the `LampHost` Lamp wrote into the extension's Info.plist), it shows `RemixPanel` (LampSidebarKit): the app's name
and line, three things to change and a box; Continue with Lamp goes where `RemixLink.url` says: lamp.dev with what the
app is a copy of (`RemixLink.Origin`: a starter's id, or a repository and commit) beside the request as `ask`, when the
offer names one (a published page does, "Remixing a published page" in the wishes guide, and so does an app whose wish
is on GitHub, below); else the wish's Share Link
page with the request as `ask` (the site adds it to the wish's words, `withAsk` in lib/wish.js); else lamp.dev with a
request that names the app, since without either Lamp makes its own version. The line under the button says which
(`RemixLink.note`). The three things come from `RemixSuggestions`: written by
the helper model after a change lands (`Store`, beside the version's title), kept in `.lamp/suggestions.json` with a
stamp of the name, line and APP.md, and put into the extension's Info.plist as the app is installed (`Sidebar.install`:
`LampSuggestions`, with `LampAbout` and `LampShareLink`); the panel has three of its own until then
(`RemixOffer.fallback`). A wish that's been Put on GitHub also has its repository and the commit last pushed there
(`LampRepository`, `LampCommit`), while the repository is public and holds this version (`GitHubRepo.remixOrigin`, by the app's wish for an app in
a folder of its own; a push refreshes every app of the wish), so
the panel's request goes with them and Lamp starts from a copy of this exact wish; a
starter's copy doesn't name the starter, since it may have been changed. When suggestions arrive after an install, a
Share Link is made or taken down, or Put on GitHub pushes a new commit, the installed
copy is made again from the build on disk and signed as before (`Store.refreshInstalled`: now if the app isn't open,
else at its next quit), so a copy taken off this Mac carries them. On a Mac with Lamp, a request that came with a wish's
link goes with the exact wish through a link of Lamp's own (`lamp://wish?file=…&text=…`, `exactWishLink` in
lib/wish.js, `Wish.Exact`): Lamp fetches the shared file itself (https only, no bigger than any shared file, refused by its
declared length and cut off as it comes, `Store.fetch`), keeps the request beside the file in a folder of its own
(`fetchedRequest`), so it stays with that file through the review, a wait for setup or a restart, reviews it as one
opened by hand, and the request is in the wish's box once it's here (`PendingImport.request`, `finishImport`, and `confirmUpdate` for a
file that's another version of an app already here). The clipboard isn't used: macOS 15.4 asks before a browser's copy is read. A published page gets the same panel under Remix… in its credit bar (`Publish.withCreditBar`).
Where the wand would otherwise fall back to Lamp's window (`LampSidebar.fallback`, `openFromMenu`), a Mac without Lamp
goes to lamp.dev: that's all an app built from its repository with `zsh build.sh` can do, since the extension is Lamp's
and goes into an app only as Lamp installs it (`Sidebar.install`). An app with no extension in its bundle goes there at
once, without the few seconds' wait for a chat that was never put in.

A Mac app's About window credits what the wish is based on: Lamp writes `Contents/Resources/Credits.html` from the
wish's credits (`Credits.aboutPage`, "Credit" in the wishes guide) as it installs the app, and macOS's standard About
window shows it under the app's name ("Based on Slop New York by Mr.doob (MIT)", linked); an app with no credits has
none. A change that goes into the open app (`LiveReload`, `PageLive`) installs nothing, so a credit the same change added
(work the agent brought in) would wait for the next install: the app's About command
(`LampAbout` in LampSupport, through `LampCommands`) asks Lamp for the page as it is now (`/app/credits`) and shows that,
and the bundle's page only when Lamp doesn't answer within a moment. Only `Credits.basis` is "Based on", there, in the info panel, the README and the credit
bar; everything else, and a library in a wish with no basis, is "Uses".

`capabilities.json` at an app's root is where the agent declares what the app needs beyond its code
(`Template.Capabilities`): for an iPhone app the entitlements and background work described above, for a Mac
app what Finder may hand it, `{"opens": ["folder", "png", "public.image"]}` ("folder", "file", extensions,
type identifiers), and for either the app's own reason for the local network (`localNetwork`, `LampNetwork`'s question,
in place of Lamp's general one). Each field has its own check and only what passes is used (`Capabilities.checked`),
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

