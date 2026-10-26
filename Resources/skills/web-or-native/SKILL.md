---
name: web-or-native
description: Choosing how an app or game is made - as a web page Lamp's host shows on each device, or in the device's own code - and on which devices, when to ask the person and what to tell them. Read before the first make_app_for of a wish, and before changing how an app is made or adding a device.
---

# Web or native

Every app and game Lamp makes is made one of two ways:

- **Web**: one page (HTML and JavaScript) that Lamp's host shows on each device. The same page runs on a Mac, an
  iPhone or iPad, an Android phone, a Samsung or LG TV, an Android TV and an Xbox.
- **Native**: the device's own code. Swift for Apple's devices (one code covers a Mac, an iPhone or iPad, an Apple TV
  and a Vision Pro), Kotlin for Android, and what an integration declares for its device.

`make_app_for`'s description lists what each device can run and how a build gets onto it, and it refuses a make a
device can't run, with the reason. Those are facts. Everything below is yours to weigh with the request in front of
you: there's no default, and nothing here is a rule.

## What decides it: how the app gets to the people who use it

Native looks nicer and can do more (the device's own controls, widgets, the watch, Health, the camera, working in the
background), but it is hard to get onto devices that aren't this Mac:

- an iPhone or iPad is paired with this Mac and gets its build phone by phone;
- an Android phone needs USB debugging turned on, and is installed one device at a time;
- an Apple TV is paired with this Mac, one TV at a time.

Web is a link: the person opens it, or saves it to their home screen, and anyone on the same Wi‑Fi can do the same.
On a TV, Lamp installs the page for them.

So think about whose devices it's for, how many there are, and which one matters most:

- **Only this Mac**: native. Lamp builds it here and it's ready; web gains nothing, unless it's meant for several
  Macs.
- **The person's own iPhone**: native is worth the pairing. It's one phone, theirs, and it does more.
- **Several people's phones** (a family, a class, friends at a party): web. Pairing each phone with this Mac is more
  than anyone wants for a quiz or a game night.
- **A TV**: whichever the TV runs. An Apple TV runs only native; a Samsung or LG TV only web; an Android TV either.
- **One main device and others to glance at**: make the main one the way it suits best, then reach the others from
  the same code where it can (one Swift code for an iPhone app and its Apple TV app), or with a small web app beside
  it (an LG TV showing what the iPhone app keeps).

## Examples

| Asked | A good choice, and why |
|---|---|
| A habit tracker for my Mac | Native: it's built here and ready, and does more |
| A game for my Apple TV | Native: the Apple TV runs nothing else |
| A 3D racing game for my LG TV | Web: the only make it runs; keep the scene light (the 3d-game skill) |
| A game the family plays on the TV, phones as controllers | Web: the phones are several people's, and a link is how they join |
| A quiz for my class's tablets | Web: a link for thirty tablets, nothing to install |
| An iPhone app to track X, that I can also see on the TV | Native iPhone app; an Apple TV app from the same Swift, or a small web app for another TV |
| A game for iPhone, nobody named | Ask whose phones in one short line, or pick and say which and why: your judgment |

## When to ask

Only when the answer really changes what you'd make, and only in one line about people and devices, never in the
words "web" or "native": "Is this for your iPhone, or for everyone's phones at the party?" When the request already
says, or a wrong guess is cheap to change, choose, build, and say in a sentence what you chose and how it gets onto
their devices.

## Saying how it gets there

Tell the person how the build reaches each device, as `make_app_for` answers it ("each phone is paired with this Mac",
"open this link on each phone"), so a choice that doesn't suit them shows at once.

## Online

A web app is served from this Mac over the home Wi‑Fi: phones and TVs on the same network reach it while Lamp is
open. That suits nearly everything people play or use at home. Lamp can't put an app's page online yet, so a game
played with friends in other homes can't be hosted by Lamp: say so plainly, and offer what works (playing together on
the same Wi‑Fi).

## Changing it later

A change from web to native, or back, writes the app again in the other code, and moves what it saved (LampStore in
Swift, `Lamp.store` and `save`/`load` in a page): `make_app_for` says what it set up. Do it when the reason changed
(the person now wants widgets, or wants friends to join from their phones), not to try the other way. An app another
way beside the one there, or in its place, is the person's call: when both could make sense, ask whether to keep the
old one. Taking an app away is `remove_app`, which the person can undo.
