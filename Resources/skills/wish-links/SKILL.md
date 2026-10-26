---
name: wish-links
description: How the apps of a wish share data and send each other messages - Lamp's LampWish block, built into every app of a wish of several, what to do while another app of the wish isn't made yet, and when another way fits better. Read before writing how a wish's apps reach each other.
---

# The apps of a wish, talking to each other

A wish of several apps (a Mac app and an Android app, a TV app and an iPhone app, a game and the phone app that
sends it things to play with, a screen on the wall and the app that fills it) usually needs them to share something:
a score, a list, a "next" button. There's more than one way to do it. Lamp gives every app of such a wish
one way built in, `LampWish`, and it's the one to use unless the wish or the person calls for another.

## LampWish, built in

Every app of the wish has it, the same in each language: `LampWish.shared` in LampSupport.swift, `LampWish` in
LampSupport.kt, `Lamp.wish` in lamp.js (a TV app's page, a game's and a screen's, in Web/lamp.js). Read the block's
own comment there before using it.

- Each app of the wish is a peer named by its folder in the wish, lowercased: "tv", "iphone", "apple" (an app for
  iPhone and Mac), "mac", "android", "game", "screen".
- `peers` lists the wish's other apps that are open now (observable: @Published, a StateFlow, onPeers).
- `peer("tv")` is that app, open or not, with its `status`: `state`, a `reason` in words to show as they are ("Open
  the TV app on your TV.", "The TV app was last open 5 min ago. Open it on your TV.", "The TV app isn't ready yet."
  for one Lamp hasn't made) and `lastSeen`. Every app the wish asks for is there, even one not made yet. A reason
  changes as time goes by: watch every app's (`apps`, observable as `peers` is; `onApps` in lamp.js), not only the open
  ones.
- `send(data, to: "tv")` sends JSON of 16 KB at most to one of them, `send(data)` to all; false, with why in the app's
  log, when it wasn't sent. `onMessage { from, data in … }` hears what they send. A message is for apps open now.
- `sendFile(data, name: "photo.jpg", type: "image/jpeg", to: "tv")` (`Lamp.wish.sendFile(data, 'iphone', { name,
  type })` in lamp.js) sends a file of up to 64 MB to one app open now, two at a time to each; the transfer it gives
  says how far it's got and why it failed, and can be cancelled. `onFile { from, file in … }` hears the files they send,
  whole. Like a message, a file is for an app open now.
- `values` is a small map of JSON every app of the wish keeps on its device (each value 8 KB at most, all of them
  64 KB). `set("list", value)` sets one here and in the others, at once if they're open or when they next meet; nil
  (null) removes it. `onChange { key, value, from in … }` hears every change, this app's own included. Where two apps
  set one while apart, the later setting wins in both.
- The app's own `status` says how its link stands, with a `reason` when something keeps it from the others (on a Mac
  or iPhone, `localNetworkDenied`: the person turned off Local Network for it). An open app built by an earlier Lamp is
  `outOfDate`: still open, with a reason saying to open it from Lamp. More states may come: treat any you don't name as
  not connected.
- A game in Lamp's own preview can't reach the others: there `Lamp.wish` is `away`, with a reason saying so. Write the
  sharing the same way for every place, and keep the game or screen whole without it.
- `LampWishStatus()` (SwiftUI, Compose) and `Lamp.wish.statusView()` (lamp.js) show all of that ready-made, a line
  for each other app, or one app's line with its peer name. Use them, restyle them, or show the statuses your own way.

What it gives: the apps find each other on the home Wi‑Fi with nothing to sign up for, pair, host or pay for. While
Lamp is open on the Mac it introduces them; with Lamp closed, the Mac asleep or Lamp updating they go on talking
straight to each other on the same network. What they say is sealed with a key only the wish's apps have, and none of
it leaves the home network. What it doesn't do: reach an app on another network (a phone away from home), keep a
message or a file for an app that isn't open, or hold more than a small amount in `values`.

How to use it well:
- Start it as each app opens.
- Pick by what the data is. Something that happens now (a button pressed, "next round") is a message. Something the
  other app should still see after being closed (a list, a score, a setting, what's on the dashboard) fits `values`:
  they catch up by themselves when they meet, so there's nothing to resend. Something big the other app should have
  (a photo, a recording, a document, a game to play) is a file: send it when that app is open, show its progress, and
  say so plainly when it fails. The app's own records belong in its own store (LampStore), with only what the other app
  needs to show put in `values`.
- Draw from `values` and redraw on `onChange`, rather than keeping a copy of your own that can drift. What an app kept
  on its device can reach `values` a moment after it opens (on a TV, once it knows its wish), so never set a default
  because `values` looks empty at launch: show an empty state, and set a value when the person does something.
- Keep values to a few names you reuse. Each name counts at least 32 bytes against the 64 KB, and a removed one keeps
  counting for a month, so values aren't a queue of ever-new names: keep such records in the app's own store.
- Several apps may change the same value while apart, and the later setting wins whole. Where both sides add to one
  list, give each item of a short list its own value ("todo.<id>") or keep each app's part under its own name, so neither undoes the
  other's.
- Watch `peers` as it changes (onChange of it, collecting the StateFlow, onPeers), not by looking now and then: an app
  closed and opened again quickly leaves and comes back between two looks.
- Where something needs another app, show why it isn't there with its `reason` (or the status view), and keep every
  control usable while it isn't open.
- Never build a server, sockets, polling or pairing of your own beside it, and never put the app's token or Lamp's
  addresses in the code.

## While another app of the wish isn't made yet

A wish can ask for an app this Mac can't build yet (Google's tools aren't set up, Xcode is missing). Lamp says which
at the end of the request and makes it as soon as it can. The app you're building already has `LampWish`, and the
missing one is in its list, not open. So:
- Write the sharing with `LampWish` now, as if the other app were there. When it's made it has the same block, and the
  two find each other with nothing more to do.
- Until then show its `reason` where it matters, and make this app whole and useful on its own.
- Don't stand in for the missing app with an online service, or leave the sharing out "for later".

## When another way fits

`LampWish` is the default, not the only way. Use another when:
- **The person asks for one**: Tailscale, ntfy, their own server or database, a service they already pay for. Do it
  their way.
- **The apps must reach each other away from home**, not just on the same Wi‑Fi. For the Mac and the iPhone of one
  person, iCloud (the icloud-sync skill) keeps their data the same anywhere. Anything else is a service outside the
  home: ask first, with one `ask`, when it needs an account, costs money or sends the person's data off their network,
  and say what that means in plain words.
- **Both are needed**: `LampWish` at home for what's instant, and a service or iCloud for what must reach a device
  away.

A public relay such as an ntfy.sh topic is readable by anyone who guesses the topic's name: don't send anything
personal through one in the clear, and tell the person. Whatever way you choose, keep it in one place in each app's
code, so it can be changed later without touching the rest.
