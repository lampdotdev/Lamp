# iPhone apps, and apps for both the Mac and the iPhone

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

## iPhone apps

Nobody picks what a new app runs on. The first request's naming call (`AppName.suggest`) also lists the devices it
runs on (`mac`, `iphone` for iPhone and iPad; `Platform(devices:)`) and whether the person said so; `Store.chooseKind` takes that before anything is
written: a kind the person didn't say only when this Mac can build it now (`PhoneTools.checked`: Xcode, and a team for
both), else a Mac app with a line in the chat offering the setup (`IPhoneSetupLine`: once it's done, the app is asked to be made for the iPhone, through the agent), and one they said either way (the build says what's missing). A line in the chat says so for
anything but a Mac app. The starter ideas mix Mac and iPhone ones (`Ideas.mixed`). Later, "make it work on my
iPhone too" is the agent's `make_app_for` (`Store.convert`), given every device the app runs on from then on (a
device's word is its kind's, "Kinds of app" below; "watch" brings the iPhone with it,
and the answer tells the agent to add `Watch/` with the apple-watch skill, or remove it): it checks this Mac can build the new kind (opening the
setup steps if not), quits every copy, changes the kind in meta.json, rewrites Lamp's own files, copies the Mac
settings (UserDefaults) to a new signed id, and answers with the rules for the new kind, which stay in the
conversation; the agent then adapts the code. A Mac app's data doesn't move: LampSupport keeps it under the app's
plain id (`{{DATAID}}`, `Edition.appBundlePrefix` and the folder name) whatever it's signed as, and moves it there
once from a folder named after its signed id. New App makes a draft, a folder with only `.lamp/meta.json`
(`Template.draft`), so its kind and name are just that file; the scaffold is written and committed when it first
builds (`Store.materialize`, in the first turn after naming and in `run`), and `LampProject.scaffolded` tells the two apart. An iOS app is one app for both devices, as Apple has it; **Try On** (in the toolbar and the app's right-click menu) picks which simulator it opens in (`LampProject.family`, iPhone to begin with), or one simulator by name under Choose Simulator (`LampProject.simulator`, kept in `meta.json`; the list is `Simulator.choices`), for what only some models have, such as the Dynamic Island. Lamp's own pick of the family is used when the chosen one is no longer installed, and `look_at_app` tells the agent which simulator the app is open on. It runs in the iPhone or iPad simulator on this Mac (`LampProject.platform == .iphone`,
kept in `meta.json` and through renames). It needs Xcode, not just the Command Line Tools. Lamp's choice of Xcode stays in its own
process (`DEVELOPER_DIR`, which its shells, the engines, simctl and devicectl inherit; xcode-select is never changed): the one
chosen in setup (Use Xcode), else, when xcode-select names the Command Line Tools, one Lamp finds by itself at launch
(`PhoneTools.installedXcode`): only in /Applications, through every link (the bundle, its developer folder and each
tool Lamp runs from it), since Lamp runs its tools as itself and the agent
can't write there, and only once its agreements are accepted, or every build would fail. Builds then use Xcode's toolchain
too, and `Shell.compatibleSDK` goes by `DEVELOPER_DIR` before xcode-select. `Simulator`
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
The simulator's build takes its entitlements (Health, iCloud, push) from a section of the binary, as Xcode puts
them: `writeOwnedFiles` writes `.lamp/entitlements.plist` and the iPhone build.sh links it in with `-sectcreate`;
the bundle's ad hoc signature claims none, since the simulator refuses to launch an app whose signature claims a
restricted entitlement without a provisioning profile.
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
text, with a short id, its name, what it holds and the point to tap it). An action names what it's for by
`target`, an id or exact name from that list (`Driver.find`), and is carried out at the thing's middle; x and y
are for what the list doesn't have. A Mac app does the same for itself (see "Generated apps" below), and the two
lists share one format: `Driver.text` here and `LampScreen.text` in LampSupport.swift are copies, held together
by `MacScreenTextTests`, so a change to one is a change to the other. The app showing the simulator is Simulator, or from Xcode 27 Device Hub
(`Simulator.viewers`), which shows one device at a time: Lamp chooses the device in its list
(`Driver.choose`) and finds the screen a few layers down its window (`Driver.screenBoxes`: a group shaped like
the screen that Device Hub marks `iOSContentGroup`, an undocumented subrole; two candidates in different places
are refused). That needs Lamp to be allowed in System Settings → Privacy & Security → Accessibility; the first
`use_app` asks, by opening that page with a panel at the foot of the Settings window holding Lamp to drag into the
list (`SettingsGuide`; `LampPermissionGuide` in LampSupport is the same panel for a generated app's own permissions,
so a change to one is a change to the other). The panel is the one place to drag from, and asking again (the
next `use_app`, or the app's Open System Settings button) brings the page and the panel back in front. Where the
Settings window can't be found there is no panel: Lamp then makes macOS's own request, and a generated app's
permission screen shows the app to drag on itself (`LAMP_PERMISSIONS=nopanel` shows that screen). The driver runs on its own queue (`AccessibilityActor`), never the main thread, and no call to
the other app waits more than `Driver.patience`; when the screen can't be used, `Driver.Trouble` says which
reason it was, in words for the agent. Device Hub (checked on Xcode 27.0) doesn't pass on mouse or key events
posted to it, so there a scroll is the page scroll the iPhone's own elements offer, a row's swipe action is the
row's own named action, return is the on-screen keyboard's key, and a long press, a sideways swipe and escape
are refused with the reason rather than reported as done. Its list holds the devices added to it, not every
booted one, and it loses a device's display when the simulator restarts: both are told to the agent as they
are. `SimulatorLiveTests` runs the driver against a real window when `LAMP_LIVE_UDID` is set.

**The devices Lamp knows** (`Device`, Device.swift): one record for every
device the person owns, read from the device itself and never guessed by a model: maker and exact model, model id,
the person's name for it, OS and version, screens, input, the features that change what's built (a Dynamic Island,
HealthKit), how Lamp reaches it, and where its setup stands (`Device.setup`: ready, or the one next step). This Mac
fills it from its own hardware and displays (`Device.thisMac`), iPhones, iPads and Apple Watches from Xcode's device
list (`Devices.list`, `Device.from(devicectl:)`; watches are kept, since their app goes with an iPhone's, and ready
once an iPhone is). The one list is Settings → Building's Your Devices (`DevicesSection`), each with its model and
state and the button for its next step; Try On lists the same phones, by model and state, and links there. Nothing
is set up in advance, but a wish is named knowing what's here: Lamp looks for devices as one begins (something typed in
the desk's bar, a new wish, its first request; a look from the last two minutes does, and the naming waits five seconds
at most, `Store.devicesForWish`), and the naming call is told each device found that changes the answer, with what to
answer for it (`AppName.seen`: a TV, an Android device, an integration's device, so "my TV" is the TV the person has).
Apple's phones, iPads and watches are left off it, since the rules name them already and listing them drew wishes that
named no device to the iPhone. A wish to run something on a device Lamp can't put apps on yet is "other": it stays a
draft with nothing scaffolded (`Store.waitsForDevice`, by its instance, which a rename keeps) while the agent sets the
device up and gives it its kind with `make_app_for`, which then makes it, scaffold and first version (`convert`). The exact device a request is for goes to the agent at the end of the request (`DeviceNote`,
sent like `AIStatus.brief`: once per conversation and again when it changes) in the shape "iPhone 16 Pro Max, iOS
27, Dynamic Island" (`Device.forAgent`). A new kind of device is a `Device.Kind`, a reader that fills the record,
and its own setup steps; the lists and the note read nothing else. Xcode 27 keeps simctl and devicectl in the
frameworks beside it rather than in its developer folder, which `DeveloperTools.path` allows for.

**On the person's own phone**: Try On also lists the iPhones and iPads the Mac can see (`Devices.list`, through
`devicectl`): paired ones to choose, and plugged-in ones that haven't trusted the Mac yet, which it offers
to pair (`Devices.pair`, `devicectl manage pair`, which puts the Trust prompt on the phone) before telling
the person about Developer Mode. `LampProject.device` remembers the chosen one. Play and the end of a turn then go through
`Store.installOnDevice`, which first writes Lamp's own files afresh as every build does (an app opened straight onto the
phone after Lamp was updated still holds the older support code), and then `Devices.stage` puts together what Xcode builds from in Lamp's own folder
(`Devices.buildFolder`, under `Phone Builds`): `Template.writeDeviceProject` writes a small Xcode project there (one
app target over the package's Sources as a synchronized group, the icon in an asset catalog, the attachments as a
folder reference, a real Info.plist), and the app's Sources, Assets, Widget, Share and Watch are copied beside it, in
`app/`, by a command under the app's sandbox, links kept as links; the project reads that copy by full path
(`Template.reaching`). Xcode copies whatever a link leads to into the app, and on the phone the app can send what it
carries anywhere, so a build folder holding any link but Lamp's own to the widget's shared code is refused
(`Devices.LinkedFiles`). `Devices.build` builds it with `xcodebuild` in the app's sandbox, with only that folder opened
and signing off, so what Xcode does with the agent's code runs as the agent's commands would. Signing for the team in
Settings → Building (`Devices.team`, found from the Mac's Apple Development certificates) happens only as Lamp, on a
copy in a folder the build can't write (`Devices.signingFolder`, `Phone Builds/.signing`), in `Devices.signedCopy`.
What each piece is signed with comes from `TeamSigning`: the same project written there over a few lines of Lamp's
own code and under names of its own (the app's name and program name are in meta.json, the agent's to write; its ids
come from its folder name and the team), which Xcode builds with automatic signing, registering the phone and making
the certificate and profiles with the account signed in to Xcode (Lamp never holds the account); each piece of the
real build, matched by its id, then gets that piece's profile and the entitlements Xcode signed it with, and a build
holding a piece Lamp's project doesn't, or a program or library that isn't a piece's own (`TeamSigning.checkCode`),
isn't signed. Nothing the agent wrote is read for it. The bundle id carries the team (`deviceBundleID(team:)`). What a free account's team can't sign (iCloud, NFC, Siri, WeatherKit, Time Sensitive notifications) is listed once, in `TeamLimits`: the setup check names it before a build signed for the team (`PhoneSetup.Context.paidFor`), the build says it (`Devices.membershipProblem`), and the request's device line tells the agent while the team is free (`TeamLimits.agentLine`, the same for every engine). Xcode lists a newly added account's team only once it has a development certificate, so an account with none (`PhoneTools.xcodeAccountsWithoutTeams`) is told how to make one, in the setup check and under the team in Settings → Building. `devicectl` installs and
launches the app with `--console`, so what it prints reaches the app's log. The signed copy installed is kept, with when its profile runs out (`PhoneRenewals`, in the signing folder), and Lamp puts it back before then (`Store.renewPhoneApps`: at launch, every quarter of an hour and when the Mac wakes, once a day for a free account's seven-day profile (six days before the end) and near the end of a paid one's, holding the app as a turn does so nothing signs or installs over it): the project Lamp signed the kept copy from, kept with it (`TeamSigning.snapshot`), is planned again with new profiles (`TeamSigning.plan(renewing:)`, which removes Xcode's own copies of the app's profiles so it makes new ones), never the app's folder as it is now, the same copy signed with them and installed over itself, never opened, which keeps the app's data (`Devices.renew`). A free account's profiles last seven days, a paid one's a year. A failure is tried again within the hour when the phone was away or locked, a day later otherwise; only once the app has stopped opening is the person told, once, in its chat with Retry (which puts the kept copy back on its own phone, wherever Try On points now) and in a notification. Renewals run while Lamp is open; the person can choose to keep their phone apps opening (`PhoneRenewals.staysOpen`), from a card in the chat after an app first goes on a phone with a seven-day profile (`KeepOpeningLine`, once per app) or under Your Devices in Settings → Building, shown once an app is on a phone: Lamp then opens at login (`SMAppService.mainApp`) and doesn't quit when its window closes while an app is on a phone. An app that stopped opening says so under its phone in Settings and beside it in Try On. `PhoneRenewalLiveTests` renews on a real phone (opt-in). The agent's looks stay on the
simulator: the phone's screen can't be photographed. The app reaches Lamp's gateway at the Mac's Bonjour
name (`Devices.macHost`, the `{{MACHOST}}` placeholder, chosen in LampSupport by `targetEnvironment`): the
gateway also listens on the network while some app is set to open on a phone (`Store.syncLocalNetwork`), marks those
requests, and admits them only to the app routes with the Mac's own name as Host (`Store.isMacHost`).
Away from the Mac, a phone app answers for itself (`LampDirect` in LampSupport, device builds only): `post`
first asks `/ai/keys` with a four-second timeout, at most every half minute; while the Mac answers, the
call goes through Lamp as ever and the reply (the OpenRouter key and the app's model choices, served by `Store.keysForPhone` only for iPhone apps) is kept in the
phone's Keychain. The reply is sealed with a secret (`Template.phoneSecret(in:)`) kept in the phone's build folder
and written only into the Info.plist there, which the app reads (`LampPhoneSecret`): the app's token is in its
folder, where the agent's commands read it, so the secret must never be there too, nor in LampSupport.swift or the
`.lamp/device` project of an app for both, or a command could ask for the keys and open them. When the Mac doesn't answer, `LampDirect.handle` does
what the gateway would with the provider directly (chat completions with the JSON retry, systemone
decisions, images). The prompt's fencing and dates are made in the library either way. What's spent this
way isn't recorded in Lamp, and `/ai/computer` says it needs the Mac.

**A free Apple account** (a Personal Team, `PhoneTools.xcodeFreeTeams`) signs for the person's own phones too, within
Apple's limits, which `FreeTeamProbeLiveTests` finds by planning Lamp's own project for such a team (opt-in:
`LAMP_FREE_TEAM=<team> LAMP_FREE_TEAM_DEVICE=<udid>`; every probe reuses one app id, so a run costs two of the team's ten
ids a week). What it found with Xcode 27: a profile lasts seven days; HealthKit, HomeKit and app groups (a widget's)
sign; NFC, Siri, iCloud with push, WeatherKit and Time Sensitive notifications are refused, each with Apple's "Personal
development teams … do not support the … capability". Planning again returns the same profile while Xcode's copy of it
is kept (in `~/Library/Developer/Xcode/UserData/Provisioning Profiles`); with that copy removed, Xcode makes a new one
good for seven days from then, so a renewal can come before the old one runs out. An app signed again and installed over
itself keeps its data. `devicectl device info apps` marks what a developer built (`builtByDeveloper`), and Lamp's bundle
ids end in the team, so the apps a team has on a phone can be counted. Xcode lists a newly added account's team in its
settings, where Lamp reads teams, only once the team has a development certificate.

**On Apple TV and Vision Pro**: an iPhone app, and the iPhone half of an app for both, can open on the Apple TV or Vision
Pro simulator, chosen under Try On as the iPad is (`DeviceFamily.appletv`, `.vision`; not for a game, whose kit is
iOS's). It's the same code built for tvOS or visionOS: the build passes `LAMP_FAMILY`, and the iPhone build.sh picks
that system's SDK, target and Info.plist from it (`iPhoneBuildSh`), leaving out widgets, the share extension and the
watch app (`Template.onlyForIOS`); the family is part of `Runtime.fingerprint`, so moving there rebuilds it. Package.swift
names both systems. LampSupport.swift type-checks for both too: on tvOS it leaves out what tvOS lacks (Health, calendar,
reminders, contacts, Spotlight, notifications), so type-check it for `appletvsimulator` and `xrsimulator` as well after
editing. The agent is told in the request's device line (`DeviceNote`, `Rules.otherOS`) that the app is built for that
system and to put what only the iPhone has under `#if !os(tvOS)` or `#if !os(visionOS)`. The simulator's system is a
download of Xcode's; the setup check asks for it by family (`PhoneTools`). Neither is offered on the person's own device yet.

## Apps for both the Mac and the iPhone

An app can be made for both (`Platform.universal`: the devices `mac` and `iphone` together, from the naming call or `make_app_for`), as
Xcode's multiplatform apps are: one code, with what differs under `#if os(macOS)` and `#if os(iOS)`, built for
one place at a time. Where it opens is `LampProject.destination`: a Mac app's is always the Mac and an iPhone
app's always iOS, and an app for both goes where Try On last put it (`chosen`, `target` in `meta.json`; "My Mac"
in `TryOnMenu`, `Store.setMac`, and the simulator and phone choices move it to iOS). It can be open in both places at once: Play
and Stop (and the app menu's Quit) are for where Try On points (`Store.isOpen`, from `openOnMac` and `openOnIOS`),
moving Try On closes nothing, and Stop quits only that copy (`quit(only:)`; a Mac build replaces only the Mac
copy). The chat is beside whichever copy is open: the Mac copy's own beside its window, the simulator's in Lamp's
panel attached to the device's window (found by its title through Accessibility, else the simulator's largest
window), and a phone's in Lamp's panel on its own (`ChatPanel`); Play, Stop and Try On are in its bar while it isn't
beside the Mac copy. Each copy keeps its log and pictures in its own folder: the Mac copy's in `.lamp/runtime` (`Runtime.macFolder`,
which the app writes itself, and where what only a Mac copy has, such as a held build or its quit reply, is read),
the iPhone copy's in `.lamp/runtime/ios` (`Runtime.folder` while Try On points at iOS). Everything about running,
looking and using branches on `destination` (`onIOS`); what an app could have, such as the Try On menu or the
phone's away-from-the-Mac keys, branches on `Platform.hasIOS` / `hasMac`. Its scaffold and owned files are
their own (`Template.universalAppSwift`, `universalPackageSwift` listing both platforms, `universalBuildSh`,
which takes `mac` or `ios`), and `Store.build` passes the destination; the destination is part of
`Runtime.fingerprint`, so moving the app rebuilds it. The iOS build is the iPhone app's. The Mac build is Xcode's,
from the same project the phone uses (`Template.writeDeviceProject`, with `universalPbxproj`: one target for
`iphoneos iphonesimulator macosx`, the Mac's own `Info-macOS.plist`), built by build.sh in the app's sandbox with
signing off, and signed for the team in Settings → Building when it's installed, so the app can use what Apple ties to
a team, which Lamp's own certificate can't give it (see `Template.WidgetSharing` for why). Without a team the build
stops with the fix, and the setup check (`PhoneSetup`, `requiresTeam`) asks for one before the first request. Its
bundle id carries the team on both platforms (`LampProject.bundleID`), and `Store.deploy` signs its copy, with what
it added (icon, assets, Info.plist), with the team's certificate (`Devices.signingIdentity`), the profile and the
entitlements Xcode signed Lamp's own project with for the Mac (`Store.signForTeam`, `TeamSigning`), never Lamp's
certificate. Those entitlements never include `get-task-allow`, which would let a debugger into the app while it
holds its secrets. The agent gets
both kinds' rules, each marked for its half, after one rule on sharing the code (`Agent.universalPrompt`). An app
for both is shared as a `.lampapp` like any other (the file says what it's made for, format 6, and carries `Watch/` when it has one); its widgets and Live Activities are the iPhone half's (below).

