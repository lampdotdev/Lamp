# 3D, widgets, Live Activities, Apple Watch, App Intents, share extensions and Spotlight

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

### 3D scenes and games

Every prompt offers the `game` skill, for games of every kind and either make (Lamp's game runtime in a page,
SpriteKit in Swift, an integration's own), the `2d-game` skill, for 2D: Phaser in a page of the game kind, played
wherever a page goes, or SpriteKit in a Mac or iPhone app, which stays on Apple's devices, and when to choose which;
and the `3d-game` skill, for three.js in a page on any device that runs
web. 3D in Swift is the `scene-3d` skill
(RealityKit, Mac apps, offered only on a Mac with macOS 15, where RealityView begins), with the `maps` skill beside it
for a real place built from OpenStreetMap data. A Mac app whose own code
imports RealityKit gets `Sources/LampScene.swift` (`Template.lampSceneSwift`, written by `writeSceneSupport`
beside LampSupport.swift and taken away with the last such import), and its Package.swift and build.sh ask for
macOS 15 (`Template.withScene`). It's Lamp's like LampSupport.swift: protected, left out of versions' diffs and of
shared `.lampapp` files, and part of `BuildStamp`. It holds `LampSceneView` (sky, camera rig, keys, the frame
loop), `LampMesh` (lathe, extrude, sweep, tube and boxes with textures laid on in meters), `LampMaterial`
(materials with their detail drawn in code, no image files), parts that press, turn, slide and are grabbed, and
`LampScene.copies` (instancing), `scene.place` (a prop by name, so a live change to it shows) and `scene.stream` (a big world built a tile at a time around the player, a few milliseconds a frame, so it opens at once). It carries what cost time to find: no sun shadows (with them RealityKit drops
the sunlight on some frames and the whole picture flickers), a camera near plane of 10 cm, and instance batches
split below a few million vertices (a bigger batch isn't drawn, silently).

Props are made in code and checked by eye: `LampSceneView(props:)` names them, and `look_at_app` with `prop`
asks the running app to show one from four sides (`LampPropStudio`, answered in `.lamp/runtime/prop.txt`) for the
agent to compare with a reference picture. `look_at_app` with `motion` works for every Mac app: `LampRuntime`
watches the front window for about two seconds and writes what changed frame to frame (`motion.json`, the two
most different frames beside it), and `Runtime.motion` puts that in words; it's how flicker is caught, which a
single picture hides.

### Widgets

A Mac app can have a desktop widget. The agent writes it in `Widget/` at the app's root (`Agent.Rules.widget` and the `mac-widgets` skill,
Mac only; an iPhone app's widgets are described under "Home screen widgets and Live Activities" below). Swift in that folder (`Template.hasWidget`,
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
to change it): macOS refuses an app group to a certificate with no team ID, which is how Lamp signs when no team
is chosen, and Lamp doesn't use exceptions to the sandbox. `LampWidget.share(value, as:)` in LampSupport.swift keeps what the app
shares, answers on this Mac's own address at a port worked out from the app's id (`Template.widgetPort`) to
whoever sends the app's widget secret (`Template.widgetToken`), and reloads the widget. `LampWidget.read` in
`Widget/LampWidgetSupport.swift`, a fourth file Lamp owns and rewrites (`Template.writeWidgetSupport`, only
for an app with a widget), asks, and keeps the last answer in the widget's own sandbox for when the app is
closed. So a widget is as fresh as the last time its app ran. The secret never crosses the connection: the
widget signs its question with it and the app signs its answer over the question's nonce, so only the app's
widget is answered and the widget passes over anything else that took the port.

The widget's buttons change the app's data through the app, with one call on each side whatever the signature:
an App Intent in `Widget/` calls `LampWidget.perform(name, payload)`, and the app's `LampWidget.onAction` does
it, shares what changed and the widget is redrawn. How it travels is decided when `Store.deploy` signs the app.
Signed for the person's team, the app and its widget get an app group named `<team>.<bundle id>`
(`Template.macAppGroup`; macOS honours that form from the signature alone, while `group.…` would need a
provisioning profile), in both signatures and both Info.plists (`LampAppGroup`, `Store.setAppGroup`): the widget
writes each action as its own file in the group's folder (whole, under its final name) and posts a Darwin
notification, and the app does them at launch and when nudged, deleting each once its handler has run. Signed with Lamp's certificate, the widget sends the action over the reading
connection, signed with the same secret over the action's id, and the app answers once its handler has run; an
action the app wasn't there to take waits in the widget's own storage and goes with its next read. The app does
each action once, by id, so one sent again after a lost answer isn't done twice, and counts it done only after
its handler has run, so one cut short by a quit is done next time. The widget changes its list of waiting
actions under one lock. The widget's own App Intents
metadata is kept without a team (only the app's is taken out): its buttons run inside the widget.

Lamp never replaces an app on disk while it's running (`HeldInstalls`): macOS then stops taking the running
app for its widget's owner and refuses its redraws until it's reopened. A build quits the app first; a new
icon or its artwork (`Store.installIcon`) waits for the app to close or for the next build. The widget's
own process is ended just before the swap too, and before an app is deleted (`WidgetProcess`, found by its
file inside that app or, for a copy running from elsewhere such as the Trash, by the widget's bundle id):
left alive it no longer matches the widget installed, and macOS fails every reload and leaves the widget
blank until that process happens to exit.

### Home screen widgets and Live Activities

An iPhone app, and the iPhone half of an app for both, gets its widgets the same way: Swift in `Widget/`
(`Template.hasWidget` says yes for every kind; `isWidgetOnly` stays the Mac's) makes a WidgetKit extension
holding home screen widgets and Live Activities (`ActivityConfiguration`) in one `WidgetBundle`. The rule is
`Agent.Rules.iPhoneWidget`, given to the iPhone prompt and, marked for its half, to an app for both's; how to write
them is the `iphone-widgets` skill.

- **Building.** In the simulator build the extension is a second SwiftPM product (`iPhonePackageSwift(widget:)`,
  `universalPackageSwift(widget:)`), linked with its own entitlements in its binary like the app's, and wrapped
  by `iPhoneBuildSh(widget:)` as `PlugIns/<Exe>Widget.appex` at the top of the bundle (`XPC!`,
  `com.apple.widgetkit-extension`, a version that changes every build so iOS rereads the widget's kinds),
  signed before the app; `finishSimulatorBundle` signs any `.appex` before the app again. The app's Info.plist
  says `NSSupportsLiveActivities` and names the folder it shares (`LampAppGroup`). On a phone and for an app for
  both, the Xcode project gains an app extension target (`withWidgetTarget`: its folder as a synchronized group,
  an Embed Foundation Extensions phase, automatic signing with the app, `Widget-Info.plist`, `Widget.entitlements`);
  for an app for both the target and its embedding carry `platformFilter = ios`, so the Mac half builds without
  it. A malformed extension doesn't fail the build, it just never shows in the gallery: check there.
- **Shared code.** Swift in `Widget/Shared/` compiles into both targets: Lamp links it into `Sources/` as
  `Sources/WidgetShared` (`linkSharedWidgetCode`, before every build, and only ever a link Lamp made), because
  SwiftPM refuses one file in two targets; Xcode's synchronized group doesn't follow that link, so the project
  gives the app target `Widget/Shared/` as a synchronized group of its own (`withWidgetTarget`). It's where an
  `ActivityAttributes` type goes. In an app for both the Mac half compiles that folder too, and
  `ActivityAttributes` is unavailable on macOS, so the rule says to put it under `#if os(iOS)` and to check the
  Mac half with `swift build --product <app>`.
- **Data.** Unlike the Mac (`Template.WidgetSharing`), iOS lets the app and its extension share an app group,
  `group.<the app's id as signed>` (`appGroup(for:onDevice:)`; the team is in it on a phone): both are signed for
  it, ad hoc in the simulator through the entitlements in their binaries. `LampWidget.share` (in LampSupport,
  under `#if os(iOS)`) writes a JSON file there and reloads the timelines; the widget's `LampWidget.read` comes
  from `lampWidgetSupportIOSSwift`, the iPhone version of Lamp's own file in `Widget/`. The calls are the Mac's,
  so the agent learns one way.
- **Live Activities** are started, updated and ended from the app with ActivityKit; there is no push from a
  server, so the rule says to give timers and progress an end date and let them move by themselves.
- **Looking.** A widget and a Live Activity aren't the app's screen. `use_app` with `key` "home" or "lock" presses
  the viewer's own Home and Lock commands (`Simulator.Driver.pressMenuItem`; lock then wakes the screen, onto the
  lock screen) before the picture. Only the person can add a widget to the home screen; the chat's `WidgetCard`
  says how in iOS words (`WidgetCard.phoneStatus`), and iOS doesn't say whether they did, so it always does.

### Apple Watch

An iPhone app, and the iPhone half of an app for both, can have an Apple Watch app: Swift in `Watch/`
(`Template.hasWatch`, asked before every build) is a SwiftUI watch app, and Swift in `Watch/Complications/`
(`hasComplications`) its complications, a WidgetKit extension inside it. The rule is `Agent.Rules.iPhoneWatch`, and how
to write it the `apple-watch` skill.

- **Building.** `Template.withWatch` adds the watch's targets to Package.swift (`.watchOS(.v10)`, the
  complications as an extension like the widget, the watch app's target excluding Complications/) and to
  build.sh: the iPhone app is built by product name, so the watch code isn't compiled for iOS, and
  `watchBuildSteps` builds for the watch simulator SDK into `<App>.app/Watch/<Exe>Watch.app` (`WKApplication`,
  `WKCompanionAppBundleIdentifier`, id `<app's id>.watchkitapp`) with `PlugIns/<Exe>WatchComplications.appex`,
  each signed before what holds it, the app group linked into their binaries as for the iPhone app. Without the
  watch SDK the iPhone app builds without it, with a warning. On a phone and for an app for both,
  `withWatchTarget` adds a watchOS app target embedded by an Embed Watch Content phase (`platformFilter = ios`)
  and the complications' extension target embedded in it; Xcode takes synchronized-group exceptions per file, not
  per folder, so the Complications/ files are listed each time the project is written.
- **Data.** `LampWatch` in LampSupport (WatchConnectivity on iOS, calls that do nothing on the Mac) sends
  everything shared as the session's application context and takes the watch's actions (`onAction`, once each
  by id). The watch's half is `lampWatchSupportSwift`, written into both folders (`writeWatchSupport`; the
  complications' copy compiles with `LAMP_COMPLICATION` and only reads): `@LampWatched` and `LampWatch.read` read
  what the watch app kept in the folder it shares with its complications, and `send` goes as a message, which
  wakes the iPhone app, or a transfer when the phone is away. While a complication is on the watch face, each
  change also goes as a complication transfer (`transferCurrentComplicationUserInfo`, about 50 a day), which
  wakes the watch app out of sight: `.lampWatch()` on its WindowGroup takes it (`backgroundTask(.watchConnectivity)`)
  and redraws the complications.
- **Simulator.** After the iPhone app opens, `Store.openWatchApp` installs and opens the watch app on the watch
  simulator paired with that iPhone (`Simulator.pairedWatch`, which pairs a new one when Xcode has a watchOS
  that pairs; `LAMP_PRETEND_MISSING=watch`); with none, one line in the chat says how to add watchOS. The agent
  can't look at or use the watch. A shared `.lampapp` carries `Watch/` (format 6), without Lamp's files there.

### App Intents

An app's actions reach Siri, Shortcuts, Spotlight, the Action button, a widget's buttons and Control Center as
App Intents (`Agent.Rules.intents`, given to every kind of app; the widget parts are in the `mac-widgets` and
`iphone-widgets` skills). The system finds them in `Metadata.appintents` inside the bundle, which Xcode writes from
the compiler's record of the code's constant values; a package build writes nothing of the sort, so build.sh does
what Xcode does (`Template.appIntentsSetup`, one for a Mac bundle and one for an iOS one). When some Swift in
`Sources/` or `Widget/` imports AppIntents and Xcode's `appintentsmetadataprocessor` is there, the compiler is
asked for the record (`-emit-const-values`, with the protocols Xcode lists, `Template.appIntentsProtocols`,
written into `.build` by the script), and `intents` runs that processor and then `appintentsnltrainingprocessor`
(Siri's phrases) on each bundle before it's signed: the app (`Contents/Resources` on the Mac, the bundle's top
on iOS) and its widget extension. The record is looked for where SwiftPM's build engine leaves it
(`.build/out/Intermediates.noindex/<package>.build/<configuration>/<target>-p.build`); a build that doesn't
leave it there warns and goes on. The phrase step needs `CFBundleDevelopmentRegion` in Info.plist and only
warns when it fails. With only the Command Line Tools the build warns that the system won't see the intents,
and the rule tells the agent to say so. Xcode's own builds (a phone, the Mac half of an app for both) extract
them by themselves.

macOS runs a Mac app's intents only when the app is signed for an Apple team: signed as Lamp signs by itself
(its own certificate, or ad hoc) the intents are listed in Spotlight and Shortcuts, but the app's connection to
the service that runs them is refused, and running one reports success and does nothing. So when a team is
chosen in Settings → Building and this Mac has its Apple Development certificate (`Devices.signingIdentity`),
`Store.deploy` signs a Mac app with that, from the login keychain where Xcode keeps it
(`AppSigning.command(ownKeychain: false)`), widget first as before; otherwise it takes `Metadata.appintents` out
of the app and its widget and signs with Lamp's certificate. Moving between the two changes the app's signature,
which macOS treats as a new app: its permissions are cleared once and the chat says so (the same path as any
change of certificate). The team's certificate keeps its name through Apple's yearly renewal, which is what the
signature's requirement names, so permissions last as long as with Lamp's own. The agent is told the rule
(`Agent.Rules.macIntents`), and `look_at_app` says why when a Mac app with intents was installed without them
(`Store.intentsHint`, read off the installed copy: no Xcode, no team, or a team whose key wasn't allowed). A team
chosen later brings them back: it's part of such an app's fingerprint, and opening one installed without them
builds it again once a team can sign it (`Store.intentsCanComeBack`). Settings → Building shows the team (`PhoneSigningSection`, "Signing") with an iPhone or
iPad app, which needs one, or when this Mac has a team's certificate; with only Mac apps, None is a choice and
nothing is chosen for the person.

On iPhone, a widget's or Live Activity's button runs its intent in the extension unless the intent is a
`LiveActivityIntent`, which iOS performs in the app, starting it out of sight when it's closed. So the rule puts
such an intent in `Widget/Shared/` and its work under `#if !LAMP_WIDGET`: the extension compiles with
`LAMP_WIDGET` (a `.define` on its package target and `SWIFT_ACTIVE_COMPILATION_CONDITIONS` in the Xcode project),
the app without it, and the work changes the data and calls `LampWidget.share`. `LiveActivityIntent` doesn't
exist on macOS, so in an app for both it goes under `#if os(iOS)`. A Mac widget shares no code with the app, so
its buttons can only change what the widget keeps itself.

### Share extensions and Spotlight

An app takes things in without being opened through a share extension: Swift in `Share/` at the app's root
(`Template.hasShare`), built like the widget on every route and beside it when there's both. The agent writes only
`ShareView` (`struct ShareView: View { let items: [LampShare.Item] … }`, usually just `LampShareSheet(items:)`);
Lamp owns `Share/LampShareSupport.swift` (`Template.writeShareSupport`, one source for both platforms), which holds
`LampShareController`, the principal class the extension's Info.plist names (`shareExtensionPlistLines`: the
`com.apple.share-services` point and what it's offered for), the item loading and the ready-made sheet.
`LampShare.send(items)` writes the share into the app group as a folder of its own (written under a dot name, then
renamed, so the app never reads half of one) and posts a Darwin notification; the app's `LampShare.onReceive` in
LampSupport takes each finished share at launch, when nudged and when it comes to the front, and deletes it once its
handler has run.

- **iPhone**: a third SwiftPM product (`extensionTargets`), its entitlements in its binary
  (`.lamp/share-entitlements.plist`, `simulatorExtensionEntitlementsPlist`), `PlugIns/<Exe>Share.appex` signed before
  the app (`iPhoneShareBuildSteps`); on a phone and for an app for both a target of its own in the Xcode project
  (`withShareTarget`, sharing the widget's Embed Foundation Extensions phase when both exist), iOS only. The app group
  is the widget's (`appGroup(for:onDevice:)`): the app carries it and `LampAppGroup` whenever it has either extension.
- **Mac**: build.sh puts it in `Contents/PlugIns/<Exe>Share.appex`, sandboxed (`macShareEntitlementsPlist`). macOS
  allows the shared folder only to a signature with a team, so `Store.deploy` keeps the extension only when it signs
  the app for the person's team (the folder is `macAppGroup`, set in every Info.plist with `setAppGroup`, and
  `AppSigning.command(share:)` signs it before the app); signed with Lamp's certificate it's taken out, since it
  would take what people share and lose it, and `look_at_app` says why (`Store.shareHint`). macOS keeps a new share
  extension off until the person turns it on (Edit Extensions… in a Share menu), which the rule tells the agent.
- A shared app (`.lampapp`) carries `Share/` without Lamp's file and says it is format 7.

`LampSpotlight.index(id:title:details:keywords:)`, `remove` and `removeAll` keep the app's own things in Core
Spotlight, and `.lampSpotlightOpen { id in … }` on a view hears which one was tapped (SwiftUI's
`onContinueUserActivity` for `CSSearchableItemActionType`, which also gets the tap that launched the app): a view
modifier, since an app has no other place that's told. The rules are `Agent.Rules.share` (as `macShare`,
`iPhoneShare` and `universalShare`) and the Spotlight part of `Rules.sharedBlocks`.

