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

A phone's browser, joined by a QR code, needs the TV app's phone page (`Phone/index.html` in the TV app's own folder,
beside its `Web/`: the phone-pages skill says where) and a TV app's page, on a Samsung or LG TV, that uses lamp.js's
`Lamp.controllers`: Lamp serves the phone page and runs the relay only while that app is open on such a TV or in its
TV preview on this Mac.

An iPhone app of the wish's own needs no browser page: it joins the TV app's game as a player with `LampController`
over `LampWish`. An Android app has no `LampController` and doesn't join as a player. Every app of the wish's talks to
the others through `LampWish` (messages, shared values, files) on whichever devices they're on (the wish-links skill).

Nothing else hosts the phone page yet, whatever device it's on:

- a page on Lamp's game runtime (lamp-game.js), which is what `make_app_for` with `kind` "game" makes, has no
  `Lamp.controllers`, even when the game is on a Samsung or LG TV: its players use a controller, the keyboard or touch;
- a page shown by Lamp's other hosts, and a native app, have no host's side of phones.

So a game played with phones as its controllers is, for now, `make_app_for` with `kind` "app", `made` "web" and
`devices` "tv": that's the TV app's page, which has `Lamp.controllers`, and the game is drawn in it without the
runtime, in 2D or 3D (the game and 3d-game skills say how). It's still a game to the person; only Lamp's routing calls it an app until the game
runtime takes phones.

These are limits of how Lamp hosts phones now, not of the devices. Say so plainly when the person asks for phones
there, and offer what works: the TV app's page (its preview on this Mac hosts phones too, with no TV), or the game
played with a controller, the remote or touch.

## A page or an app on the phones?

For the person's own iPhone, an app of the wish's on it, made natively. For game controls on an Android phone, a page,
since a native Android app can't join as a player.
For several people's phones joining one TV app, a page: nothing to install, and any phone on the Wi‑Fi joins (that's
one app shared across devices, the case where web-or-native chooses web). The web-or-native skill has the rest of that
choice.

## Away from home

Phones reach the TV app's page on the same Wi‑Fi, with Lamp open on this Mac, which runs the relay. Friends in other
homes can't join through it: say so if that's what they want. Apps of the wish's that talk through `LampWish` work
by its own rules (the wish-links skill).

## Building it

Once you've chosen, open the phone-pages skill: the TV app's page in its own Phone/, `LampController` on the phone and
`Lamp.controllers` on the screen, files, tilt and second screens.
