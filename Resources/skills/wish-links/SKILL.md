---
name: wish-links
description: How the apps of a wish, and one app open on several devices at once (two iPhones, a screen on an iPad and a TV), share data and send each other messages - Lamp's LampWish block and the shared collections built on it (LampStore.shared, LampStore.sharedFiles) for the same data on every device, what to do while another app of the wish isn't made yet, and when another way fits better. Read before writing how they reach each other.
---

# The apps of a wish, talking to each other

A wish of several apps (a Mac app and an Android app, a TV app and an iPhone app, a game and the phone app that
sends it things to play with, a screen on the wall and the app that fills it) usually needs them to share something:
a score, a list, a "next" button. So does one app open on several devices at once: the same app on two iPhones, or a
screen shown on the kitchen iPad and the TV. There's more than one way to do it. Lamp gives every app one way built
in, `LampWish`, and it's the one to use unless the wish or the person calls for another.

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
- `LampStore.shared` and `LampStore.sharedFiles` (below) keep lists and files the same on every copy of the app.
- The app's own `status` says how its link stands, with a `reason` when something keeps it from the others (on a Mac
  or iPhone, `localNetworkDenied`: the person turned off Local Network for it). An open app built by an earlier Lamp is
  `outOfDate`: still open, with a reason saying to open it from Lamp. More states may come: treat any you don't name as
  not connected.
- An app can be open on several devices at once (a screen on the kitchen iPad, the TV and a photo frame, the same app
  on two iPhones), in a wish of one app as in a wish of several: each is a copy of it, and every copy reaches the others and keeps the same `values`. `peer("screen").copies` lists where it's
  open now (`id`, `device`, `since`); another copy of this same app shows in `peers` while it's open. A message to an app
  goes to every copy of it; a file goes to one copy, the one opened last unless `to` names a copy's `id`. The third
  argument of `onMessage` (`copy`) and `file.copy` say which copy sent it, to answer that one alone. Put what every
  screen shows in `values`, so a copy opened later catches up by itself. An app with no other app in its wish is
  `alone` until another copy of it opens; its copies first meet through Lamp on the Mac, and after that also reach
  each other straight with Lamp closed.
- A game in Lamp's own preview can't reach the others: there `Lamp.wish` is `away`, with a reason saying so. Write the
  sharing the same way for every place, and keep the game or screen whole without it.
- A Roku app (an app for a device through its integration) can't reach the others yet, nor they it: it's not in the
  room's list, so the others don't see it at all, and its own `LampWish` (LampWish.brs) is always `away`. Don't write
  the others to wait for it or send it anything; each keeps what it shows its own. An app on the Mac or an iPhone can
  still steer it as a remote with `LampRoku` (keys, opening it by launching "dev"), which needs no link.
- `LampWishStatus()` (SwiftUI, Compose) and `Lamp.wish.statusView()` (lamp.js) show all of that ready-made, a line
  for each other app, or one app's line with its peer name. Use them, restyle them, or show the statuses your own way.

## The same data on every device: shared collections

When one app is open on several devices (a screen on the Mac, the kitchen iPad, the TV and an Android photo frame) and
each should show the same shopping list, chores, calendar or photos, keep that data in a **shared collection**, not
in `values`:

- `LampStore.shared("groceries", of: Grocery.self)` in Swift (an ObservableObject: `items`, `put`, `get`, `delete`,
  `publish`, `onChange { id, item, from in }`), `LampStore.shared<Grocery>("groceries") { it.id }` in Kotlin (`items`
  is a StateFlow), `LampStore.shared('groceries')` in lamp.js (items are objects with an `id`; `all()`, `put`, `get`,
  `delete`, `publish`, `onChange(fn(id, item, from))`). Each copy keeps the items on its device and works alone; copies
  merge them item by item whenever they meet, through Lamp or straight on the home network with Lamp closed. Two copies
  that changed different items while apart both keep both; where two changed the same item, the later change wins in
  both; a deleted item stays deleted. An item is at most 8 KB as JSON, everything the app shares at most 1 MB
  (thousands of small items).
- Give each item a stable id of its own (a UUID made when it's added, or the id of what it stands for, such as a
  calendar event's), and keep things that change apart in separate items: a list's items, not the list as one.
- `publish(items)`, for what one copy can read and the others can't (the Mac's or the iPad's calendars, through
  `LampNative` on a screen or a game): this copy's items become exactly these; unchanged ones cost nothing, and items
  other copies put are left alone. Publish again each time it's read.
- `LampStore.sharedFiles("photos")`: files kept on every copy (`put(name, data, type)`, `get(name)`, `url(name)`,
  `files`/`all()` with whether each is here yet, `delete`, `onChange`). A copy that can read the album puts each
  picture; every other copy fetches the bytes from a copy that has them, including copies that open later. 64 MB a
  file, 256 MB in all. On a TV the bytes are kept in memory and fetched again each time the app opens.
- Draw from the collection and redraw on `onChange`; never keep a copy of your own. Never split a list into `values`
  by hand, or send the same data around with messages to keep copies in step.
- A shared collection is the app's own, the same on all its copies, unless it's the **wish's own**: with
  `wish: true` (`LampStore.shared("events", of: Event.self, wish: true)` in Swift,
  `LampStore.shared<Event>("events", wish = true) { it.id }` in Kotlin, `LampStore.shared('events', { wish: true })`
  in lamp.js, and `sharedFiles(name, wish: true)` likewise) every app of the wish keeps it the same: a Mac app and the
  iPhone app beside it sharing one calendar, a TV game and the phone controllers sharing a scoreboard. Every app that
  uses it gives the same name. It merges as above; each app's 1 MB counts only the items it set last.
  Use the wish's own collection whenever different apps of the wish show the same records; never make one app the
  keeper of them for the others, since that app is often closed or asleep.
- A collection starts empty: the wish's own and the app's own of the same name are separate, so switching a list to
  `wish: true` doesn't bring its items along. When the person already has items there, copy them over.
- Apps that share a collection agree on what an item looks like: the same fields with the same meaning. Add a field
  as optional, so an app that doesn't know it yet still reads the item, and change every app that uses the collection
  together.

What it gives: the apps find each other on the home Wi‑Fi with nothing to sign up for, pair, host or pay for. While
Lamp is open on the Mac it introduces them; with Lamp closed, the Mac asleep or Lamp updating they go on talking
straight to each other on the same network. What they say is sealed with a key only the wish's apps have, and none of
it leaves the home network. What it doesn't do: reach an app on another network (a phone away from home), keep a
message or a file for an app that isn't open, or hold more than a small amount in `values`.

How to use it well:
- Start it as each app opens.
- Pick by what the data is. Something that happens now (a button pressed, "next round") is a message. A list or
  records every copy of this app shows (groceries, chores, events, photos) is a shared collection, and the wish's own
  (`wish: true`) when the wish's other apps show them too. Something another
  app of the wish should still see after being closed (a score, a setting, what's on the dashboard) fits `values`:
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
  list, use a shared collection: the app's own between its copies, the wish's own (`wish: true`) between different
  apps, so neither undoes the other's.
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
