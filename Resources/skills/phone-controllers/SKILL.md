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
- **Only the person's own phone**: on an iPhone, an app of the wish's own, made natively, is the controller: it has
  the phone's own feel, hardware and haptics, and keeps its data, and joins as a player with `LampController` over
  `LampWish`. Installing it goes the way the table says for that phone. An Android app has no `LampController`, so it
  can't join a game as a player: for game controls on an Android phone, native is out of reach and a page is the
  answer. A native Android app still suits plain messages to the TV app through `LampWish` (a few commands, a
  photo sent). A page works for an iPhone too, when they ask for one.

## What hosts phones today

Phones join in two separate ways.

A phone's browser, joined by a QR code, needs a phone page (`Phone/index.html` in the app's own folder, beside its
`Web/`: the phone-pages skill says where) and a page on the screen that uses lamp.js's `Lamp.controllers`. Two kinds
of app have both:

- a game on Lamp's game runtime (`make_app_for` with `kind` "game"): on the Mac, on an iPhone or iPad while it's in
  front, and on an LG TV from webOS 5 on (a service Lamp packages with it, so the Mac can be asleep or gone), the game
  serves its phone page and runs the relay itself, with Lamp open or closed; Lamp does it for the game in the TV
  preview, or set to open on a Samsung TV, an older LG TV or the person's Xbox;
- a TV app's page: while it's open on such a TV or in its TV preview on this Mac.

An iPhone app of the wish's own needs no browser page: it joins the TV app's game as a player with `LampController`
over `LampWish`. An Android app has no `LampController` and doesn't join as a player. Every app of the wish's talks to
the others through `LampWish` (messages, shared values, files) on whichever devices they're on (the wish-links skill).

So a game played with phones as its controllers is a game like any other (`kind` "game"), with its Phone/ page,
played on the Mac or put on a Samsung or LG TV (`places` "tv") or the Xbox (`places` "xbox-one"). A wish's own iPhone app (`LampController`) joins only
a TV app's game, not a game's.

On an iPhone or iPad the game's phones play only while the game is in front: when the person leaves it, every
phone is let go, and once they come back the game shows a new code to scan (`Lamp.controllers.onLink` hears it).

Nothing else hosts the phone page yet, whatever device it's on:

- a game played on Android: its players there use a controller or touch, and `Lamp.controllers` says it can't
  start (`onError`), so the game must be whole without phones;
- a page shown by Lamp's other hosts, and a native app, have no host's side of phones.

These are limits of how Lamp hosts phones now, not of the devices. Say so plainly when the person asks for phones
there, and offer what works: the game on the Mac, an iPhone or iPad, a Samsung or LG TV or the Xbox (the TV preview
on this Mac hosts phones too, with no TV), or played with a controller, the remote or touch.

## A page or an app on the phones?

For the person's own iPhone, an app of the wish's on it, made natively. For game controls on an Android phone, a page,
since a native Android app can't join as a player.
For several people's phones joining one game or TV app, a page: nothing to install, and any phone on the Wi‑Fi joins (that's
one app shared across devices, the case where web-or-native chooses web). The web-or-native skill has the rest of that
choice.

## Away from home

Phones reach the phone page on the same Wi‑Fi: a game on the Mac runs the relay itself, and everywhere else Lamp runs
it, open on this Mac. Friends in other
homes can't join through it: say so if that's what they want. Apps of the wish's that talk through `LampWish` work
by its own rules (the wish-links skill).

## Building it

Once you've chosen, open the phone-pages skill: the page in the app's own Phone/, `LampController` on the phone and
`Lamp.controllers` on the screen, files, tilt and second screens.
