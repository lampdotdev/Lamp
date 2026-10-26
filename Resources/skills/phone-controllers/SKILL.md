---
name: phone-controllers
description: What to weigh when phones are to be controllers or a second screen for a game or app - whose phones, what the game's device can take, web or native on the phones, and what Lamp can't do yet. Read whenever someone wants to play or steer something with their phone.
---

# Phones as controllers: what to consider

"A game I can control with my phone" can be made several ways. Before building, think through these, and ask the
person only what you can't tell from the request (one short line, about people and devices).

## Whose phones?

- **Several people's** (family, friends, a class): each phone has to join with nothing to install. That's a page for
  phones: they scan a QR code on the screen and play in their browser. The phone-pages skill says how to build it.
- **Only the person's own phone**: an app of the wish's own on their iPhone or Android phone can be the controller
  too, and does what a page does poorly (the phone's hardware, haptics, data the phone keeps). It joins as a player the
  way a phone's page does (`LampController` over `LampWish`). The cost is installing it: an iPhone paired with this
  Mac, an Android phone with USB debugging. A page still works for their phone too.

## What does the game's device take?

The phones connect to the game's own page, over the home Wi‑Fi, through a relay Lamp runs on this Mac:

- **A page with lamp.js's `Lamp.controllers`** hosts phones: a TV app's page, and a page shown full screen on a
  Mac, an iPad, a TV or an Xbox. This is what works today.
- **A page on Lamp's game runtime** (lamp-game.js) has no `Lamp.controllers` yet: its players use a controller, the
  keyboard or touch. A game played with phones today is a page with lamp.js's controllers, drawn without the runtime.
- **A native Apple TV game can't host phones yet**: the host's side of phones exists only in lamp.js. Say so, and
  offer what works: the game made as a page on a TV that runs web, or the Apple TV played with game controllers or
  the Siri Remote.
- **A native Mac or iPhone game** doesn't host phones either; the same choices apply.

## Web or native on the phones?

Unless the phones are only the person's own and the app needs what only native does, a page: nothing to install, and
any phone on the Wi‑Fi joins. The web-or-native skill has the rest of that choice.

## Away from home

The phones and the game must be on the same Wi‑Fi, with Lamp open on this Mac. Lamp can't put a game online, so
friends in other homes can't join: say so if that's what they want.

## Building it

Once you've chosen, open the phone-pages skill: the page in Phone/, `LampController` on the phone and
`Lamp.controllers` on the screen, files, tilt and second screens.
