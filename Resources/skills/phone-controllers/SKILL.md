---
name: phone-controllers
description: What to weigh when phones are to be controllers or a second screen for a game or app - whose phones, which of Lamp's pages host them today, a page or an app on the phones, and what Lamp can't do yet. Read whenever someone wants to play or steer something with their phone.
---

# Phones as controllers: what to consider

"A game I can control with my phone" can be made several ways. Before building, think through these, and ask the
person only what you can't tell from the request (one short line, about people and devices).

`make_app_for`'s table says what each device runs; it doesn't yet say which apps can take phones, because that
depends on how an app is made and run, not on the device alone. What follows is that account.

## Whose phones?

- **Several people's** (family, friends, a class): each phone has to join with nothing to install. That's a page for
  phones: they scan a QR code on the screen and play in their browser. The phone-pages skill says how to build it.
- **Only the person's own phone**: an app of the wish's own on their iPhone or Android phone can be the controller
  too, and does what a page does poorly (the phone's hardware, haptics, data the phone keeps). It joins as a player the
  way a phone's page does (`LampController` over `LampWish`). The cost is installing it, the way the table says for
  that phone. A page still works for their phone too.

## What hosts phones today

Phones join in two separate ways.

A phone's browser, joined by a QR code, needs the app's phone page (`Phone/index.html`) and a TV app's page, on a
Samsung or LG TV, that uses lamp.js's `Lamp.controllers`: Lamp serves the phone page and runs the relay only while that
app is open on such a TV or in its TV preview on this Mac.

An app of the wish's own on a phone needs no browser page: it joins the TV app's game as a player with
`LampController` over `LampWish`, and the wish's apps talk to each other through `LampWish` on whichever devices
they're on (the wish-links skill).

Nothing else hosts the phone page yet, whatever device it's on:

- a page on Lamp's game runtime (lamp-game.js) has no `Lamp.controllers`, even when the game is on a Samsung or LG TV:
  its players use a controller, the keyboard or touch. A game played with phones today is a TV app's page with
  lamp.js's controllers, drawn without the runtime;
- a page shown by Lamp's other hosts, and a native app, have no host's side of phones.

These are limits of how Lamp hosts phones now, not of the devices. Say so plainly when the person asks for phones
there, and offer what works: the TV app's page (its preview on this Mac hosts phones too, with no TV), or the game
played with a controller, the remote or touch.

## A page or an app on the phones?

Unless the phones are only the person's own and the app needs what only an app on the phone does, a page: nothing to
install, and any phone on the Wi‑Fi joins. The web-or-native skill has the rest of that choice.

## Away from home

Phones reach the TV app's page on the same Wi‑Fi, with Lamp open on this Mac, which runs the relay. Friends in other
homes can't join through it: say so if that's what they want. Apps of the wish's that talk through `LampWish` work
by its own rules (the wish-links skill).

## Building it

Once you've chosen, open the phone-pages skill: the page in Phone/, `LampController` on the phone and
`Lamp.controllers` on the screen, files, tilt and second screens.
