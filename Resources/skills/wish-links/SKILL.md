---
name: wish-links
description: How the apps of a wish share data and send each other messages - Lamp's LampWish block, built into every app of a wish of several, what to do while another app of the wish isn't made yet, and when another way fits better. Read before writing how a wish's apps reach each other.
---

# The apps of a wish, talking to each other

A wish of several apps (a Mac app and an Android app, a TV app and an iPhone app) usually needs them to share
something: a score, a list, a "next" button. There's more than one way to do it. Lamp gives every app of such a wish
one way built in, `LampWish`, and it's the one to use unless the wish or the person calls for another.

## LampWish, built in

Every app of the wish has it, the same in each language: `LampWish.shared` in LampSupport.swift, `LampWish` in
LampSupport.kt, `Lamp.wish` in lamp.js. Read the block's own comment there before using it.

- Each app of the wish is a peer named by its folder in the wish, lowercased: "tv", "iphone", "apple" (an app for
  iPhone and Mac), "mac", "android".
- `peers` lists the wish's other apps that are open now (observable: @Published, a StateFlow, onPeers).
- `peer("tv")` is that app, open or not, with its `status`: `state`, a `reason` in words to show as they are ("Open
  the TV app on your TV.", "The TV app was last open 5 min ago. Open it on your TV.", "The TV app isn't ready yet."
  for one Lamp hasn't made) and `lastSeen`. Every app the wish asks for is there, even one not made yet. A reason
  changes as time goes by: watch every app's (`apps`, observable as `peers` is; `onApps` in lamp.js), not only the open
  ones.
- `send(data, to: "tv")` sends JSON of 16 KB at most to one of them, `send(data)` to all; false, with why in the app's
  log, when it wasn't sent. `onMessage { from, data in … }` hears what they send.
- The app's own `status` says how its link stands, with a `reason` when something keeps it from the others (on a Mac
  or iPhone, `localNetworkDenied`: the person turned off Local Network for it). More states may come: treat any you
  don't name as not connected.
- `LampWishStatus()` (SwiftUI, Compose) and `Lamp.wish.statusView()` (lamp.js) show all of that ready-made, a line
  for each other app, or one app's line with its peer name. Use them, restyle them, or show the statuses your own way.

What it gives: the apps find each other on the home Wi‑Fi with nothing to sign up for, pair, host or pay for. While
Lamp is open on the Mac it introduces them; with Lamp closed, the Mac asleep or Lamp updating they go on talking
straight to each other on the same network. What they say is sealed with a key only the wish's apps have, and none of
it leaves the home network. What it doesn't do: reach an app on another network (a phone away from home), or keep a
message for an app that isn't open.

How to use it well:
- Start it as each app opens.
- A message is for now. What must survive one app being closed, keep in that app's own store (LampStore) and send the
  whole of it when the other app appears in `peers`, so they agree again whichever was open meanwhile. Watch `peers` as
  it changes (onChange of it, collecting the StateFlow, onPeers), not by looking now and then: an app closed and opened
  again quickly leaves and comes back between two looks.
- An app that opens sends the whole of its own as well, and an app that gets a whole from another answers once with
  its own, so the two catch up whichever noticed the other first.
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
