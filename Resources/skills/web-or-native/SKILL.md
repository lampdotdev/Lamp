---
name: web-or-native
description: Choosing how an app or game is made - as a web page Lamp's host shows on each device, or in the device's own code - and on which devices, when to ask the person and what to tell them. Read before the first make_app_for of a wish, and before changing how an app is made or adding a device.
---

# Web or native

Every app and game Lamp makes is made one of two ways:

- **Web**: one page (HTML and JavaScript) that Lamp's host shows on each device. The same page runs on a Mac, an
  iPhone or iPad, an Android phone or tablet, a Samsung or LG TV and an Xbox. Lamp has no host for a page on an
  Apple TV, an Android TV, an Apple Watch or a Vision Pro.
- **Native**: the device's own code. Swift for Apple's devices (one code covers a Mac, an iPhone or iPad, an Apple TV
  and a Vision Pro), Kotlin for Android, and what an integration declares for its device.

`make_app_for`'s description lists what each device can run and how a build gets onto it, and it refuses a make a
device can't run, with the reason. Those are facts. Everything below is yours to weigh with the request in front of
you: there's no default, and nothing here is a rule.

## What decides it: how the app gets to the people who use it

Native looks nicer and can do more (the device's own controls, widgets, the watch, Health, the camera, working in the
background). Web is one page for many kinds of device, and the only make on a Samsung or LG TV and an Xbox.

On a phone or tablet, web doesn't save installing: a page on an iPhone, an iPad or an Android device is an app of
Lamp's around the page, and it gets there the same way as a native app:

- an iPhone or iPad runs it in the simulator on this Mac, or is paired with this Mac and gets its build one device at
  a time;
- an Android phone or tablet runs it in the emulator on this Mac, or needs USB debugging turned on, one device at a
  time;
- an Apple TV or a Vision Pro runs a native app in its simulator on this Mac only: Lamp can't put an app on a real one
  yet;
- a Samsung or LG TV, an Android TV and an Xbox get it from Lamp, which installs it on each one once it's set up.

The one way phones join with nothing to install is as controllers or companions of a Samsung or LG TV app's page:
that page hosts them, on the TV and in its preview on this Mac, and each phone opens a link (the phone-controllers
skill). Nothing else hosts phones yet: an Apple TV and an Android TV can't run a page, and a page on an Xbox, a Mac or
an iPad can't host phone controllers.

So think about whose devices it's for, how many there are, and which one matters most:

- **Only this Mac**: native. Lamp builds it here and it's ready, and it does more.
- **The person's own iPhone**: native. It's installed the same way as a page would be, and it does more.
- **Several people's phones** (a family, a class, friends at a party): an app on each phone is installed one device
  at a time, whichever the make. For a quiz or a game night, make it a Samsung or LG TV app's page the phones join as
  controllers by a link: on that TV, or in the app's preview on this Mac when there's no such TV. With an Apple TV,
  an Android TV or an Xbox, say plainly that phones can't join a game there yet, and offer the preview on this Mac or
  the device's own controllers.
- **A TV**: whichever the TV runs. An Apple TV runs only native, and for now only in its simulator on this Mac: say so.
  A Samsung or LG TV runs only web, an Android TV only native.
- **One main device and others to glance at**: make the main one the way it suits best, then reach the others from
  the same code where it can (one Swift code for an iPhone app and its Apple TV app), or with a small web app beside
  it (an LG TV showing what the iPhone app keeps).

## Examples

| Asked | A good choice, and why |
|---|---|
| A habit tracker for my Mac | Native: it's built here and ready, and does more |
| A game for my Apple TV | Native: the Apple TV runs nothing else. Say it runs in the Apple TV simulator on this Mac, since Lamp can't put it on a real Apple TV yet |
| A 3D racing game for my LG TV | Web: the only make it runs; keep the scene light (the 3d-game skill) |
| A game the family plays on a Samsung or LG TV, phones as controllers | Web: the TV app's page hosts the phones, and each joins by a link, with nothing to install |
| A quiz for my class's tablets | Web: a Samsung or LG TV app's page the tablets join by a link, on that TV or in the app's preview on this Mac when the room has no such TV. An app on each tablet is installed tablet by tablet, whichever the make |
| An iPhone app to track X, that I can also see on the TV | Native iPhone app; an Apple TV app from the same Swift (in its simulator for now), or a small web app for a Samsung or LG TV |
| A game for iPhone, nobody named | Ask whose phones in one short line, or pick and say which and why: your judgment |

## When to ask

Only when the answer really changes what you'd make, and only in one line about people and devices, never in the
words "web" or "native": "Is this for your iPhone, or for everyone's phones at the party?" When the request already
says, or a wrong guess is cheap to change, choose, build, and say in a sentence what you chose and how it gets onto
their devices.

## Saying how it gets there

Tell the person how the build reaches each device, as `make_app_for` answers it ("each phone is paired with this Mac",
"each phone joins the TV's game by a link"), so a choice that doesn't suit them shows at once.

## Online

Phones join a TV app's page over the home Wi‑Fi, with Lamp open on this Mac. That suits nearly everything people play
together at home. Lamp can't put an app's page online yet, so a game played with friends in other homes can't be
hosted by Lamp: say so plainly, and offer what works (playing together on the same Wi‑Fi).

## Changing it later

`make_app_for` with an app's folder in `app` changes how that app is made: it keeps its folder and what it saved, but
the new code doesn't read what the old one saved unless you write it to, and Lamp moves nothing across, so say so when
it matters. One more app beside the others is `another`, only once the person chose that when you asked (the
`more-apps` skill). `remove_app` takes one away, which the person can undo.
