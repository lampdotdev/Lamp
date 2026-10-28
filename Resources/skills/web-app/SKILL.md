---
name: web-app
description: Apps made as a web page Lamp shows on each device - lamp.js's building blocks (AI, saved data, the app's files, the wish's other apps), the remote's focus and keys, what the person's own things need from the app around the page, and what each device's browser runs. Read before writing or changing an app's page.
---

# Web apps

A web app is one page (HTML, CSS and JavaScript in Web/) that Lamp shows on each device it's on. The same page, so
write it once for all of them and let each device's differences be handled where they are: lamp.js for what Lamp
gives every page, a few lines of your own where a device needs something else. How a game's page runs is the game
skill's; this one is about the page itself.

## Lamp's building blocks: lamp.js

`Web/lamp.js` is Lamp's, written before every build; index.html loads it before the app's own scripts. Read its
opening comment for the whole list. What it gives:

- **LampAI**: text, pictures and quick judgments, answered by Lamp on the person's Mac with the AI they set up.
  Every call is a Promise. Text from outside the app goes in `data`, never into the prompt. Where a feature depends
  on it, check `LampAI.isAvailable('text')` and show a short note when it can't answer: away from the Mac's Wi‑Fi, or
  with Lamp closed, it can't.
- **LampAI.act**: the person asks the app to do something in their own words, and the app's own reads and writes do
  it; "Doing things for the person" below, with **LampVoice** and **LampAI.hear** for saying it.
- **LampStore**: what the app saves, as JSON on the device. Once something is saved, only ever add to it: a new field
  gets a default where it's read, and a saved one is never renamed or retyped, because people rely on their data
  through every change.
- **LampAssets**: the app's own files that come with it.
- **Lamp.wish**: the wish's other apps (an iPhone, Mac or Android app beside the page), messages and shared values;
  the wish-links skill says how they share data.
- **Lamp.controllers** and `Lamp.phonePage`: phones on the same Wi‑Fi as controllers or a second screen; the
  phone-controllers skill first.

## Doing things for the person

`LampAI.act(request, { about, context, tools, history, onStep })` runs a short loop: the AI picks calls among the
app's tools, the page runs them, the AI sees the results, until it replies (at most 4 AI calls, 6 writes and 25
seconds a turn). Its comment in lamp.js has the shapes. This is the one recipe for it:

- Show the feature only where `LampAI.isAvailable('act')` is true, and keep the app's own buttons for everything: it
  only adds a way in.
- Tools are small reads and writes over the app's own data, ids in and ids out, never "do anything". A read has
  `reads: true`; everything else is a write. Nothing destructive (a delete, a clear) without an Undo the person sees.
- Every write has a `check` that looks its item up again by id and says in a sentence why it can't be done (gone,
  already done, in the past, nobody of that name); `run` changes the data the way the app's own button does, and
  returns the item as it is after.
- Make the ids of what a write adds from `call.key`, or keep the key on the change, so the same request made again
  finds it instead of adding a second.
- Say what happened from the result's `done`, `failed` and `skipped`, which are what the page ran, never from the AI's
  `reply`; add the reply only when it asks something (`ask`) or nothing was changed.
- Keep what each write changed for Undo, and undo only what's still as the write left it; say which ones it left.
- Show each step while it runs (`onStep`), and cancel the turn (`turn.cancel()`) when the person closes it or the page
  is hidden.
- `about` says what the app is and its rules for asking back: which person, which day and time, which of two things
  that both fit.

Saying it instead of typing it: where the app around the page has a microphone (`LampVoice.status()`, which never
prompts: the Mac, iPhone and iPad, Android and Android TV, a TV remote's microphone included) and Lamp can transcribe
(`LampAI.isAvailable('hear')`), `LampVoice.listen({ session, onLevel })` records what's said and `LampAI.hear(audio)`
turns it into text for `act`. Their comments in lamp.js have the details. The recipe:

- One deliberate press starts listening (opening the app's Ask), never a key that means something else on the remote;
  show the level as it's heard, a Stop that the opening press can't trigger, and "Type instead" wherever text can be
  typed. Never hide a typed way in because there's no voice.
- Give every recording a session of the page's own, and cancel it (`LampVoice.cancel`) when the person closes or the
  page hides; drop any recording, transcript or answer that comes back for a session that has ended, and a transcript
  that comes back after the person has typed or talked again.
- Act only on `quiet` and `stopped`: `cap` may have cut the person off, so ask them to say it again shorter; say so
  plainly for `nothing` and `denied`.
- Read the reply out with `LampVoice.speak`, and listen again for an answer only once it has finished.

## The person's own things

A page can't read the person's mail, calendar, contacts, photos or where they are. Where Lamp's app is around the page
(a Mac, an iPhone or iPad), that app can: register a call in Sources/Native.swift and ask for it from the page with
`LampNative.call(name, args)`. Elsewhere `LampNative.available` is false and the calls reject, so the page shows
example content then, never an error. When an app the defaults make web (on a TV, or across several devices) lives on
the person's own things, say what a page can't reach there, and offer it native (the web-or-native skill).

## A remote: focus and keys

On a TV, and anywhere a page is driven by arrows and OK, there's no pointer. lamp.js moves focus with the arrows
between buttons, links, fields and anything marked `data-focus`, to the nearest in that direction, and OK clicks what
has it, so most apps need no key code of their own:

- give the first thing to focus with `Lamp.focus(...)` when a screen opens;
- Back goes back a screen with `Lamp.onBack(fn)` (return true when handled); unhandled on the first screen, it leaves
  the app;
- other keys (play, pause, the color keys, numbers) come by name through `Lamp.onKey(fn)`;
- keep the arrows inside a dialog with `Lamp.scope` while it's open; a game takes them over with
  `Lamp.navigation = false`.

On a phone or a Mac the same page is tapped or clicked, so a page that works with the remote works there too. How to
design for the remote and for a TV across the room (what focus looks like, layouts it moves through, typing) is the
tv-design skill's.

## The browser a page meets

Which devices take a page is `make_app_for`'s table. Where one does, the page meets one of these engines:

| Device | What shows the page | Worth knowing |
|---|---|---|
| Mac, iPhone, iPad | Lamp's app around the page (WebKit) | Modern; LampNative reaches the person's things |
| Android phone or tablet | Lamp's app around the page (Android's WebView, Chromium) | Modern on recent devices |
| Samsung and LG TVs | The TV's own browser engine | Chromium 108 to 132 on recent models, older on older ones; WebGL 2 not on every Samsung |
| Android TV, Google TV, Fire TV | Lamp's app around the page (Android's WebView), on the TV's home screen | As on Android phones |
| Xbox | Lamp's web host (Edge WebView2) | Modern |

A TV keeps the page's syntax to what its older browsers run, as the TV rules say when the app is for one. Designing
what a TV shows, seen from across a room, is the tv-design skill's.

## Speed

A TV or a cheap phone draws far less than a Mac. Keep animations few and on `transform` and `opacity`, lists that
scroll in their own box rather than the page, and pictures no larger than they're shown.
