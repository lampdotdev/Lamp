---
name: web-or-native
description: Choosing how an app or game is made - as a web page Lamp's host shows on each device, or in the device's own code - from the default the table of devices gives (web wherever Lamp has a host for a page), the few things only native code does (a menu bar icon, widgets, Siri and Shortcuts, Health, share sheets), and on which devices, when to ask the person and what to tell them. Read before the first make_app_for of a project, and before changing how an app is made or adding a device.
---

# Web or native

Every app and game Lamp makes is made one of two ways:

- **Web**: one page (HTML and JavaScript) that Lamp's host shows on each device, the same page everywhere it goes.
- **Native**: the device's own code. Swift for Apple's devices (one code for all of them), Kotlin for Android, and
  what an integration declares for its device.

`make_app_for`'s description has the table of devices: what each one runs, and how a build gets onto it. It refuses
a make Lamp can't build on a device, with the reason, and the request's device line says what Lamp knows of the
person's own devices. Those are the facts, and the only place they're kept; this skill doesn't repeat them.

## The default

A page is where every app and game starts. When the person names no make, an app or a game is **web** wherever Lamp
has a host for a page: a Mac, an iPhone or iPad, an Android phone or tablet, a Samsung or LG TV, an Android TV and an
Xbox. Where there's none (an Apple TV, an Apple Watch, a Roku), it's native. A game is on Lamp's game runtime (the game
skill says what it's drawn with). One app across several devices is web where every one of them takes a page.

A web app is one page that goes anywhere: the person can open it on another device later without it being written
again, and putting it on GitHub gives it a link anyone can open in a browser without Lamp. On a Mac, an iPhone or an iPad the app around the page still reaches
the person's mail, calendar, reminders, contacts, photos and location (`LampNative`, the web-app skill).

Make it **native** only when it needs something a page can't be:

- a Mac app that lives in the menu bar (the menu-bar skill), takes files from Finder (the finder-files skill), or is a
  utility that works where the person already is or in the background (a global shortcut, the selection in another
  app, opening at login: the app-kinds skill);
- widgets, Live Activities or Control Center controls (the mac-widgets and iphone-widgets skills), or an Apple Watch
  app (the apple-watch skill);
- its actions in Siri, Shortcuts, Spotlight or the Action button (the app-intents skill), or a place in the share
  sheet (the share-extension skill);
- Apple Health, iCloud sync, work while an iPhone app is closed, or the phone's hardware beyond what a page has (the
  iphone-hardware and icloud-sync skills);
- 3D in Swift with RealityKit (the scene-3d skill), or a game inside an Apple thing (Game Center, a widget).

When one of these is part of what was asked, choose native and say why in a sentence. When the person asks for one
later in an app made web, say what it needs, and offer to make it native. A web app brought in from elsewhere is the
exception: it stays as it is, made native only when the person asks for that (the web-app skill, "A web app brought
in").

The default is where you start, not a limit:

- **A make the person names is theirs.** When they ask for a web app, or a native one, make it that way wherever Lamp
  can build it; say in a sentence what that costs only when it matters.
- **Nothing switches silently.** Devices found on the network aren't a request for one app across them: add a device
  only once the person has said that's what they want, or answered so when you asked.
- **An app the project has is never converted to follow the default.** It's for a new app, and for a change the person
  asks for. An app made native before keeps its make.
- **A web app brought in keeps its make and its kind.** A site or page someone made elsewhere stays a web app, with no
  Swift of its own, unless the person asks in so many words for it to be native or a game on Lamp's runtime; being on a
  Mac isn't such a request (the web-app skill, "A web app brought in").
- **Separate apps that talk don't need the same make.** The project's apps reach each other through `LampWish` on
  whichever devices they're on, however each is made (the wish-links skill).
- **Never choose a make to get around a limit of Lamp's**: two apps of one code in one project, say (the more-apps
  skill). Say what the limit is instead, and offer what can be done.
- **Never refuse a make that works only because it isn't the default.** Only the table, and the refusal it gives,
  says what can't be built.

## What to weigh

- **What the app needs from the device**: the list above. A page reaches the person's things only through Lamp's app
  around it, where there is one (`LampNative`, the web-app skill): on a TV, Android or the Xbox it shows example content
  instead. A game made native for an Apple thing is SpriteKit for 2D: say that it then stays on Apple's devices, where
  a game on the runtime can go to Android, a TV, the Xbox or the web later without being written again.
- **How it gets to the people who use it.** Read the table's way onto each device, for each make. On some devices a
  page still comes inside an app of Lamp's that is installed the same way a native app is.
- **Whose devices, and how many.** One person's own Mac or phone, a family's TV, every phone at a party: who has to
  install or open what.
- **What it's played or used with.** A remote, a controller, touch, phones in the room: the game skill and the
  phone-controllers skill say what each takes.

When the app needs several devices, it can be one app on all of them, or several of the project's apps, each made for its
device, that talk through `LampWish`. Adding one more app to a project that has one is the person's to choose: the
more-apps skill says how to ask.

## When to ask

Only when the answer really changes what you'd make, and only in one line about people and devices, never in the
words "web" or "native": "Is this for your iPhone, or for everyone's phones at the party?" When the request already
says, or a wrong guess is cheap to change, choose, build, and say in a sentence what you chose and how it gets onto
their devices.

## Saying how it gets there

Tell the person how the build reaches each device, as `make_app_for` answers it ("each phone is paired with this Mac",
"each phone joins the TV's game by a link"), so a choice that doesn't suit them shows at once.

## Away from home

Each way of connecting has its own reach, said where it's described: phones joining a TV app's page do it on the same
Wi‑Fi with Lamp open on this Mac, and a game's on the Mac with Lamp open or closed (the phone-controllers skill); the project's own apps find each other on the home
network, and once Lamp has introduced them go on talking with Lamp closed (the wish-links skill, which also says what
reaching each other away from home takes). Lamp runs no relay of its own for players in other homes: when that's what
the person wants, say so plainly, and offer what works (playing on one Wi‑Fi, or another way of connecting, as the
wish-links skill says).

## Changing it later

`make_app_for` with an app's folder in `app` changes how that app is made: it keeps its folder and what it saved, but
the new code doesn't read what the old one saved unless you write it to, and Lamp moves nothing across, so say so when
it matters. One more app beside the others is `another`, only once the person chose that when you asked (the
`more-apps` skill). `remove_app` takes one away, which the person can undo.
