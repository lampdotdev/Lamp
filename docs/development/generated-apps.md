# Generated apps

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

Lamp owns three files in every app and never trusts what's in them: `Sources/LampSupport.swift`, `build.sh`
and `Package.swift` are written afresh before every build (`Template.writeOwnedFiles`), and the build stops if
that fails. The last two are what the build runs (the shell runs build.sh; SwiftPM compiles and executes
Package.swift as a program), so they're replaced rather than checked: nothing the agent's file tools wrote
into them, with no card, can run. Shared apps never carry them: import writes its own.
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
an app for both.

A Mac app's reasons for its permissions are one list, `Template.macUsageDescriptions`, written by build.sh, the
Mac half of an app for both (`universalMacInfoPlist`) and `Store.deploy`: macOS kills an app that asks for
the photo library, Bluetooth, the camera and the like without one. A new one goes in that list and nowhere
else, only for something macOS refuses without it (location and music are asked about with none), and is
named in the prompt's `{{EXTRA_PERMISSIONS}}`. The list is part of `BuildStamp`, so apps built before a
reason was added are rebuilt when next opened.

`use_app` on a Mac app is carried out by the app itself (`LampDriver`, reached by a distributed notification
signed with the app's token, `Store.use`), so no Accessibility permission is needed. With every picture the
app writes its front window as text (`LampScreen` in LampSupport.swift, `.lamp/runtime/screen.txt`): one line
per thing its own accessibility tree names (NSAccessibility walked in-process, SwiftUI's elements included),
with a short id, what it is, its name, what it holds and its middle in the picture. `look_at_app` and `use_app`
return it beside the picture (`Runtime.screenText`), the same lines the iPhone driver writes. An action names
what it's for by `target` (an id or exact name, `LampScreen.find`): a button, switch, link or choice is asked
to press itself (`accessibilityPerformPress`), a field takes the text in place of what it held, a slider or
stepper takes a number or a step, and what has no action of its own, or isn't listed (a drawing, a canvas),
is clicked at a point, pixels in the picture. Lamp tells an app built before the list existed by a line of the
heading in its binary (`Store.screenTextMarker`): such an app is told to be rebuilt when a target is used.

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
closes only once the sidebar has connected, so Lamp neither quits nor leaves the chat nowhere). Lamp asks the app
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
nothing can be loaded into it. The extension must start as Apple's own do, through `_NSExtensionMain` (the linker's
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
While Lamp builds a change for a Mac app that's open, smoke in many colours curls up from the bottom of the app's
windows, with a faint glow round their edges, and as the change goes in a level band of white whooshes up across them (`AppTransition`, drawn by
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
Lamp's panel (`MagicPanel.showChatIfAppNeverComes`), and so does one that crashes, or quits while a turn is going on,
with its chat beside it (`MagicPanel.showChatAfterQuit`, once three seconds have passed with no copy running: a change
that reopens the app leaves a moment with none). The chat is drawn by another process, which AppKit's focus doesn't follow
(what had the keyboard, a list say, keeps it through a click in the chat), so once a click in the chat has landed the
keyboard goes to it (`LampSidebar.watchClicks`). Point at the Screen is an item of the + by the message box, beside
Attach a File…, in both chats (`ChatLook.MessageBar`'s `point`, `PlusMenu`) while the app is open on this Mac (`MagicPanel.point`; from Lamp's panel, Lamp comes back in front when it's done). It lets the person point at part of the app: the app lays a clear window over its own (`LampMagic.Picker`), kept above the app's own panels, sheets and alerts however high they float, but no higher, so other apps' windows still cover it (`Picker.keepOnTop`), and what's in them is pointed at and pictured as shown, outlines the smallest named
thing under the pointer from its own accessibility tree (`LampDriver.elements`), a click where nothing is named (a game's
ball, a drawing) takes the area around it, and a drag draws a box of the person's own; it then leaves a cropped
picture in its runtime folder and says what it is (an area is named by where it is, "Top left area"); Lamp attaches that picture to the message, named after the
thing ("Save button.png", `MagicPanel.name`), and takes a picture only from that folder. In both chats' message boxes it is
one pill (`ChatLook.PointedPill`: what it is and what it's part of, from the app's own row or the heading above it),
which a click points again and its × lets go; pointing again replaces it, and nothing is left drawn over the app.

A Mac app can also open beside a web page, in Chrome's sidebar (Lamp Dev only, an experiment: Settings →
Experimental, `BrowserBridge.switchKey`; how it fits together is in `experiments/browser-connector/README.md`).
The sidebar is a web page of the app's own (`Assets/Sidebar/`), which the app serves itself on this Mac's own
address (`LampBrowser.startPage` in LampSupport.swift), at a name under `.localhost` and a port of its own
(`Template.sidebarHost`, `sidebarPort`, trying the next few when another program has it), so it works while the app
is open whether Lamp is or not. One extension frames every app's page: it keeps the app's name and consent
line above the frame (the page makes its own offer), gives the page no browser powers, and is the page's only way to the person's tab (a read only
when the page's file declares it, once per click in it). The page asks its app for everything else (`lamp.call`,
with a key Lamp hands the extension, which passes it on only once the page proves it's the app's: the key's
signature over a nonce and the port); the app answers only its own name, only that key, never a request another
site made, and lets only the extension frame the page, whose own policy keeps it talking to the app alone. The page
looks as if Apple made it, not like a web page and not like a copy of the window's own theme: `/lamp.css` is
Apple's system look for a narrow Mac list pane, light and dark (grouped grey ground, rounded groups, inset
separators, SF, parts that rearrange at large text), and an app stands out only through one tint, chosen among
Apple's system colours with `data-tint` (each shade measured to read, `SidebarTintTests`), and its own content.
How a page is built (layout, pictures, every state from reading to a failed save, what to check) is the
`chrome-sidebar` skill, which the builder opens before writing the page. The app serves its own pictures
(`/assets/`, or hands one it keeps with an item to the page as a `data:` URL) and SF Symbols (`/symbols/`, drawn by
the app, used as masks), and the extension draws its strip above the page in the page's colours (`look`, plain
colours only). Apps built before pages still publish a
surface as data (`LampBrowser.start`), which the extension still draws. The app declares where it fits in
`browser.json` (`BrowserCompanions.Declaration`), which Chrome matches without the extension reading the page. The
builder decides from the wish (`Agent.Rules.browserCompanion`, which leaves the rest to the `chrome-sidebar` skill) and tries the sidebar with `look_at_app` and
`use_app` given `sidebar` and `page`: Lamp opens the app's page itself, out of sight at the sidebar's width
(`PagePreview`), shows it light, dark and at 200% zoom with the app's window beside it, says what it measured there
(contrast, the system font, small words, pictures and symbols that didn't load, sideways scrolling, words cut off,
parts out of line),
and hands it the page beside it, so every engine tries it the same way; it's the one thing the builder uses in a new app, since it isn't the person's Chrome.
Each Chrome tab has its own sidebar and the app keeps what one tab prepared by its tab (`call.tab`), so what one
page prepared never shows on another; keep that when changing either side. The builder may also give an app a
right-click item (`menu` in browser.json) for what its sidebar does with a page, whatever that is (save it, explain,
summarise or translate it, answer something about it): it opens that app's sidebar, and shows only on pages a fit
names by address, the one thing Chrome can check before its menu opens.
**The one exception to "once per click in it"**: choosing an app's right-click item counts as the person's click in
that app's page. The sidebar tells that page once (`lamp.onMenu`) and lets it read once without a click in it, only
within 15 seconds of the choice, only with the proof the page gave in that sidebar, and only of the page the item was
chosen on (the extension checks the tab's address before reading). A choice the page gets too late (a slow-starting
app) doesn't run, and the sidebar says so and that choosing the item again runs it. Nothing else stands in for a click: not the
toolbar icon, not opening the sidebar, not the page asking on its own. From the item a page may also go straight
through a step it would otherwise stop at for a look first (a save's check, say), since choosing the item already
said what to do; it then shows what it did where it can be changed or undone. Widening this needs the same say-so as
making it.

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

