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
or a device through its integration. A kind whose app is a page (a three.js game, a screen) doesn't list its own: its
places are wherever Lamp has a host for a web engine (`Places.pagePlaces`, "Pages and their hosts" in the devices
guide). Building, opening, looking at, using, quitting, Try On, setup checks and the device note go by the
destination (`onIOS`, `onAndroid`, `onTV`, `onDevice`), so a kind that opens where another does (an Android TV app on
Android's devices, in the TV emulator: `onAndroid` holds for Android TV too, and `Destination.emulator` says which
emulator) gets all of that from its file and a line in `Targets.all`. A new place to open is a new
`Destination` and its paths in `Store`.


## The table of devices

What each device can run is one table of facts, `Places` (`Sources/Lamp/Places/Places.swift`): a row per device
(this Mac, iPhone and iPad, Apple Watch, Apple TV, Vision Pro, Android phones and tablets, Android TV, Samsung and LG
TVs), then a row per device integration that declares apps, read from its JSON's `supports` ("web", "native") or, when
it says nothing, from what its `app` declares. Each row says whether a **web** build (a page in a host of Lamp's, and which: `PageHost`) and a
**native** build (the device's own code: `apple`, `android`, `android-tv` or the integration's) can exist there, and how
each gets onto the device, or why it can't. It holds facts only, never a preference: which make and which devices an
app gets is the agent's choice. `IntegrationCheck.problems` refuses a `supports` that names a make the integration has
no files for.

A row claims a make only once a kind builds it there (`Places.kinds`, checked by `PlacesTests`): turning on a make
before its host or recipe exists is refused by the test, not discovered by the person. The table reaches the agent as
text generated from the rows, `{{PLACES}}` in `make_app_for`'s description (`Places.forAgent`), and the person's own
devices Lamp knows of are named with their rows in the device line (`Places.known`, in `DeviceNote.brief`), so a new
row needs no prompt edit. `make_app_for` reads each app it's given as a make and devices (`Places.model`) and refuses
one on a device that can't run that make, quoting the row (`Places.refusal`, in `Parts.asked`). Every stored kind
reads as a make and devices that lead back to it (`Places.kinds`); a game and a screen, both web at home on the Mac,
are still told apart by their folder's mark.

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
