---
name: phone-controllers
description: What to weigh when phones are to be controllers or a second screen for a game or app - whose phones, who can host them, a page or an app on the phones, and what Lamp can't do yet. Read whenever someone wants to play or steer something with their phone.
---

# Phones as controllers: what to consider

"A game I can control with my phone" can be made several ways. Before building, think through these, and ask the
person only what you can't tell from the request (one short line, about people and devices).

`make_app_for`'s table says what each device runs; it doesn't yet say which apps can take phones, because that
depends on how an app is made and run, not on the device alone. What follows is that account.

## Whose phones?

- **Several people's** (family, friends, a class): each phone has to join with nothing to install. That's a page for
  phones: they scan a QR code on the screen and play in their browser. The phone-pages skill says how to build it,
  held sideways by default.
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

- a game on Lamp's game runtime (`make_app_for` with `kind` "game");
- a TV app's page: while it's open on a Samsung or LG TV or in its TV preview on this Mac.

Who serves the phone page and runs the link phones join is the game's choice, `Lamp.controllers.start({ host })`
(the phone-pages skill):

- Game-owned hosting (`'game'`) runs with the game and needs no Lamp. The game has it on the Mac, on an iPhone or iPad
  while it's in front, on an LG TV from webOS 5 on, where Lamp packages a service with the game, and on the Xbox,
  where the game's own host runs it.
- Lamp hosting (`'lamp'`) needs Lamp open and the Mac reachable. Lamp has it for the TV preview, a Samsung or LG TV and
  the Xbox.
- Device networking and store rules can affect either one.

They're options, not an order, and another approach is fine. A host that isn't there, or fails, is said in
`onError`; the game never moves to the other one by itself. `start()` with no host keeps where each device ran before.

An iPhone app of the wish's own needs no browser page: it joins the TV app's game as a player with `LampController`
over `LampWish`. An Android app has no `LampController` and doesn't join as a player. Every app of the wish's talks to
the others through `LampWish` (messages, shared values, files) on whichever devices they're on (the wish-links skill).

On an iPhone or iPad the game's own phones play only while the game is in front: when the person leaves it, every
phone is let go, and once they come back the game shows a new code to scan (`Lamp.controllers.onLink` hears it).

Neither host covers a game played on Android, a page shown by Lamp's other hosts, or a native app yet. Say so plainly
when the person asks for phones there.

## A page or an app on the phones?

For the person's own iPhone, an app of the wish's on it, made natively. For game controls on an Android phone, a page,
since a native Android app can't join as a player.
For several people's phones joining one game or TV app, a page: nothing to install, and any phone on the Wi‑Fi joins (that's
one app shared across devices, the case where web-or-native chooses web). The web-or-native skill has the rest of that
choice.

## Away from home

Phones reach the phone page on the same Wi‑Fi, whichever host serves it. Friends in other
homes can't join through it: say so if that's what they want. Apps of the wish's that talk through `LampWish` work
by its own rules (the wish-links skill).

## Building it

Once you've chosen, open the phone-pages skill: the page in the app's own Phone/, `LampController` on the phone and
`Lamp.controllers` on the screen, files, tilt and second screens.
