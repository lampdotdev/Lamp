# Kinds of app

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

What an app is for (`Platform`, kept in meta.json as "mac", "iphone", "universal", "android", "tv", "game", "device") is one
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

Where an app opens is its kind's `places`, each a `Destination`: this Mac, iOS, Android, a TV or a device through its
integration. Building, opening, looking at, using, quitting, Try On, setup checks and the device note go by the
destination (`onIOS`, `onAndroid`, `onTV`, `onDevice`), so a kind that opens where another does (an Android TV app on
Android's emulator and devices) gets all of that from its file and a line in `Targets.all`. A new place to open is a new
`Destination` and its paths in `Store`.

