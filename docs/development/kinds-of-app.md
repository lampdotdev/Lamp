# Kinds of app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

What an app is for (`Platform`, kept in meta.json as "mac", "iphone", "universal", "android", "tv", "game", "screen", "device") is one
`Target` in `Sources/Lamp/Targets/`, listed in `Targets.all`, made of the pieces that differ from kind to kind: its
`identity` (its names, the device words it's chosen by, which `Targets` puts together for the naming call,
`make_app_for` and an undecided wish, Try On's help and the desk's place), its `guidance` (prompt, the rules
`make_app_for` answers with, skills, AI away from the Mac), its `recipe` (its language, scaffold, Lamp's own files, how
its folder is told apart, what a build is made from, whether it can be shared), its `part` when it can be one of a
wish's other apps (folder, family, rules), and its `setup` (what this Mac must have to build it, and the chat's setup
line). Kinds of one language change into each other in place; a wish has one part of a family. Code outside
`Targets/` asks a kind what it can do (`hasMac`, `hasIOS`, `hasTV`, `hasDevice`, `choosesPlace`), never which kind it is,
except where an Apple kind's own build and signing differ. Lists of kinds go in `Targets.all`'s order, the kinds that
stand alone after the rest and the Mac's hint last; a folder or a list of devices is matched with a kind made from
another's files (`recipe.refines`) before that one and the Swift kinds last, since a Package.swift says less than another
kind's own mark.

Where an app opens is its kind's `places`, each a `Destination`: this Mac, iOS, Android, Android TV, a Samsung or LG TV
or a device through its integration. A kind whose app is a page (a web game, a screen) doesn't list its own: its
places are wherever Lamp has a host for a web engine (`Places.pagePlaces`, "Pages and their hosts" in the devices
guide). Building, opening, looking at, using, quitting, Try On, setup checks and the device note go by the
destination (`onIOS`, `onAndroid`, `onTV`, `onDevice`), so a kind that opens where another does (an Android TV app on
Android's devices, in the TV emulator: `onAndroid` holds for Android TV too, and `Destination.emulator` says which
emulator) gets all of that from its file and a line in `Targets.all`. A new place to open is a new
`Destination` and its paths in `Store`.

An app of several places (an app for both, a game, a screen) has a build for each, and what each was built from is kept
apart (`Runtime.markBuilt` writes this Mac's and the simulator's in their copies' folders, every other place's as
`built-<place>`), so building for one never makes another look current. `Runtime.behind(_:at:)` asks it of one place, and
`LampProject.at(_:)` is the app as it would be there, for building or opening it without moving Try On. Opening a place
whose build is older than the code builds it first (`Store.open`). After anything that changed a wish (a request, Undo,
a restore, an update for this Lamp: every hold's end, `Store.finish`), `Store.updatePlaces`, once the wish has been left
alone for a moment (so a run of requests builds each place once; a second when only pages changed, which every open
copy takes as it is, else 20), first puts a page's change into each copy open on the person's other devices through the
wish's room (`PageCopies`, below), then builds each other place that had a build and is behind, and puts it where Lamp
reaches it without opening anything: this Mac, a booted simulator, Lamp's running emulator, or the copy open there,
which takes it as a request's change would (a page's copy on this Mac or in the simulator takes its page in place,
`PageLive`; anything else waits for Reload). The chat says in one line where a page's change went; the status lines of
that work are taken away again; what it couldn't reach is said in one line, and is tried again every couple of minutes, a
few times, and otherwise at the next change or when opened there. A copy open on Android counts only on its own place:
the phone's and the TV's share a package and Lamp's emulators a serial. A TV or an Xbox is never built for this way:
putting an app on one opens it over whatever it shows. A request sent meanwhile ends the work, which starts again after
it. Try On says beside a place that's behind that it's updated when opened (`placesBehind`).

**A page's change in every open copy.** A kind whose change is new web files (`Target.changesAreWeb`: a screen, a web
app, a web game, a TV app) has each build of its page record its files by hash, and the hash of everything else
(`PageCopies.record`, from `Runtime.markBuilt`), and `updatePlaces` runs for it whenever a copy is in the wish's room,
whether or not any of Lamp's own places is behind (a TV app on its own has no other). A copy of it open on another device (an iPad, a TV, the Xbox, an Android
device) is in the wish's room as it uses the wish, and Lamp sends it the whole page as it is (so it doesn't matter
which build that copy has), as Lamp's own word through the relay (`Relay.say`, from the relay's name, which no app may
take), in pieces under a message's size; lamp.js puts them together and takes them in place ("A change while it's open" in lamp.js,
`TVTemplate.pageChangeJS`): stylesheets alone are swapped as the page runs; anything else opens the page again from the
new files, kept for the session, which lamp.js, the page's first script, puts in place of the copy's own before any of
its scripts run, so what the page saved stays; what the page then asks for as it runs (`fetch`, XMLHttpRequest, a `src`
a script sets) is the change's file where it has one, and a script that isn't code (JSON, a template) is kept as data. Where each copy is comes from the device it says (`PageCopies.place`);
this Mac's and the simulator's copies take changes from Lamp itself (`PageLive`), and the preview is Lamp's own. What changed
is measured against what the copy was last given, or every build it may have (its place's latest, and each one Lamp put
on a device of the person's there, `Runtime.placed`). Which of a place's devices a copy is on isn't known. On a TV or the
Xbox only lamp.js matters, so the newest build Lamp put there says whether it takes Lamp's words, and a TV left on an
older one doesn't hold back the rest. A copy in an app of Lamp's on the person's iPhone, iPad or Android device also needs
the app around the page as it is now, which is taken as so only when every build Lamp put on such devices there has it
(never the simulator's or the emulator's build, which the copy isn't); otherwise it's offered Reload. A copy with no
such build recorded (put there by an earlier Lamp), a change of anything but the page, a script before lamp.js, a module script or more than 3 MB of page waits for
Reload (`PageCopies.cannot`), and the chat shows its Reload line
(`Store.placesAwaitReload`).

**Reload is every place.** Reload, in the app's title bar or the chat's line, puts the change on every place of the wish
the person has it on and Lamp can reach (`Store.reloadEverywhere`): this Mac, the booted simulator and Lamp's running
emulator (a copy open there opens again with it; one that isn't is only given it), and each device of the person's Lamp
put the app on (`Runtime.placed`: a TV, the Xbox, an iPhone or iPad, an Android device, recorded as each install there
works), where it's installed and opened as Play does, since Reload is the person's go-ahead. The chat says in one line
where it went and which places couldn't be reached.


## The table of devices

What each device can run is one table of facts, `Places` (`Sources/Lamp/Places/Places.swift`): a row per device
(this Mac, iPhone and iPad, Apple Watch, Apple TV, Vision Pro, Android phones and tablets, Android TV, Samsung and LG
TVs), then a row per device integration that declares apps, read from its JSON's `supports` ("web", "native") or, when
it says nothing, from what its `app` declares. Each row says whether a **web** build (a page in a host of Lamp's, and which: `PageHost`) and a
**native** build (the device's own code: `apple`, `android`, `android-tv` or the integration's) can exist there, and how
each gets onto the device, or why it can't. It holds facts only, never a preference: which make and which devices an
app gets is the agent's choice. `IntegrationCheck.problems` refuses a `supports` that names a make the integration has
no files for. Its reason for a make it can't run is its own `runs` (what the device runs, in a sentence the person
would follow: a Roku's says BrightScript channels and the remote, no pages, no 3D), so a game or a screen given a Roku as
a place is refused with that (`Places.refusal`, in `AppKinds.target`), and the agent's rules (`deviceRules`) have it say so in its own
words and offer what works: a simple version for the device as one of the wish's apps, or another place.

A row claims a make only once a kind builds it there (`AppKinds.target`, checked by `PlacesTests`): turning on a make
before its host or recipe exists is refused by the test, not discovered by the person. The table reaches the agent as
text generated from the rows, `{{PLACES}}` in `make_app_for`'s description (`Places.forAgent`), and the person's own
devices Lamp knows of are named with their rows in the device line (`Places.known`, in `DeviceNote.brief`), so a new
row needs no prompt edit. `make_app_for` refuses an app on a device that can't run its make, quoting the row (`Places.refusal`, in
`AppKinds.target`). Every stored kind reads back as devices that, asked for again, plan the same kind (`AppKinds.member`);
a game and a screen, both web at home on the Mac, are still told apart by their folder's mark. `AppKinds` is the one place
today's kinds meet these terms (the "Wishes" guide); the table itself holds facts only. A row whose words name different
families of Apple's devices says which word is which (`Place.wordFamilies`: "iphone" an iPhone, "ipad" an iPad), and a
row whose native app only comes with another's names that row (`Place.comesWith`: the watch, with the iPhone).

A row also says what a game's page is told about the device (`Place.input`, an integration's `input` in its JSON): what
its keyboard prints on the keys keyboards name differently (`.apple`: Return, Delete, Option and ⌘), the controller that
comes with it, which a game there starts on (`controller`), and the one controller layout the device's host supports,
where it supports only one, so the page names every controller by it rather than by what the controller reports
(`layout`; the Xbox's host supports Xbox controllers). Both name a layout in `Controllers`
(`Sources/Lamp/Places/Controllers.swift`), Lamp's one list of the controllers a game names buttons for, which the page
is given as `Web/lamp-controllers.js`. `.generic` (in JSON, `{}`) is a web view with a PC keyboard and no controller of
its own; a row without `input` can't have a game's page, and saying so is an error, never a default.

The page never asks where it is. `GamePage` resolves the row once for each copy of the page Lamp makes (the project's
destination and its family, which picks out its row where rows share a destination and must be one that shows a page,
or its integration on a device) and writes that row's input beside lamp-game.js as `lamp-device.js`:

- the preview's copy (this Mac's row) and a real iPhone's or iPad's (`Devices.stage`);
- build.sh's copies for the Mac, the simulator and Android, which take it from `LAMP_PAGE_DEVICE`
  (`GamePage.buildEnvironment`) in their one `stage_page` step;
- the copy of the app an integration's package step runs on (`DeviceApps.packageSource`, in Lamp's own folder; a copy
  holding a link is refused, and an old package in it is taken away before the step), checked after the step, and the
  package itself checked too where Lamp can read it (a ZIP, and so an MSIX made from one); a package in another form
  is the integration's own, and only the copy is checked;
- a page published to the web (`GamePage.anyBrowser`), which names each key keyboards differ on both ways ("Enter /
  Return", `Place.Input.anyKeyboard`), since it may be played on any device.

The app's own Web/ never holds one, and a copy of a game's page made without it stops the build. What a copy is told is
part of what the game is built from (`GamePage.buildInput`, in `GameTarget`'s inputs), so a change to a row builds the
game again. A device that fits a host Lamp has is one row; one that needs the page to behave differently gets a fact in
`Place.Input`, never a test in the page.
