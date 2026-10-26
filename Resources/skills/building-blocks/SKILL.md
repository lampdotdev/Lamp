---
name: building-blocks
description: How to call LampSupport.swift's tested building blocks - notifications, schedules and work while the app is closed, text from documents and pictures, dropped files, folders, global shortcuts, the clipboard, login items, photos, location, weather, music, Spotlight, the home, the devices on the home network and a Roku. Read before using any of them.
---

# Lamp's building blocks

LampSupport.swift has tested building blocks for common jobs, the same ones on a Mac and an iPhone where both have
them. Use them instead of writing your own.

## On both

- `LampNotifications.send("Title", body: "…")`, also `at: date` to show it later, even with the app closed, `id:` to
  replace or `cancel(id)` one, `actions: ["Done", "Snooze"]` for buttons that work without opening the app, handled by
  `LampNotifications.onAction { action, id in … }` set where the app starts, and on iPhone `timeSensitive: true`,
  with `{"timeSensitive": true}` in capabilities.json, for what can't wait, sparingly.
- `LampSchedule.daily("briefing", hour: 7) { }` and `LampSchedule.every("inbox", minutes: 15) { }`: work at a time or
  every so often, catching up after sleep; keep it alive. On an iPhone see "Work while the app is closed" below.
- `await LampText.read(url)`: text from PDFs, scanned PDFs, images and screenshots via Live Text, RTF, Word, HTML,
  plain text, all on the device and free; use it before sending documents to LampAI. `await LampText.recognize(in:
  image)` for an `NSImage` on the Mac, a `UIImage` on iPhone.
- `.lampDropFiles { urls in }` on any view and `LampDropZone("Drop screenshots here") { urls in }` for an empty state
  (Finder files, images from other apps, links; on iPad, files and images dragged in from another app).
- Photos: `LampPhotos` (`authorize()`, `photos(days:)`, `photos(near:_:km:)`, `favorites()`, `albums()`,
  `photos(in:)`, `image(_:size:)`, `tags(of:)` for what a picture shows (empty in the simulator), `save(_:)`;
  choosing one is SwiftUI's `PhotosPicker`).
- Location: `LampLocation` (`current()` with a name from the map, `find(address)`, `distance(from:to:)`,
  `shared.watch()` for big moves, `shared.watchVisits()` on the iPhone for where the person stops and for how long,
  which needs `"backgroundModes": ["location"]`).
- Weather: `LampWeather` (`now(latitude:longitude:)`, `hours`, `days`, `here()`), after `{"weather": true}` in
  capabilities.json, for apps with an iPhone half only; the team also turns WeatherKit on for the app at
  developer.apple.com once, and the call's message says so until then (otherwise, Open-Meteo through `connectors`).
  Apple's terms ask for `LampWeatherAttribution()` (its Weather mark, linking to its sources) wherever its weather is
  shown, allow forecasts to be kept only briefly (never saved with the app's data), and rule out apps meant for
  emergencies or safety.
- Music: `LampMusic` (`authorize()`, `recentlyPlayed()`, `library()`, `search(_:)`, `play(_:)`, `pause()`, and on the
  iPhone `nowPlaying`), Apple Music only, with MusicKit turned on for the app at developer.apple.com the same way.
- Spotlight: for the app's own things people would look for by name (notes, recipes, people, trips),
  `LampSpotlight.index(id:title:details:keywords:)` when one is added or changed and `LampSpotlight.remove(id)` when
  it's deleted, and `.lampSpotlightOpen { id in … }` on the view that shows them, to show the one tapped in Spotlight.

- The home network: `LampNetwork`, for an app on the Mac or a phone that controls, plays to or reads the person's
  devices (a remote for the TV and speakers, what's playing, a light). The system asks the person about the local
  network before anything answers, so the app says why first, in its own words and on its own screen, and asks with
  `await LampNetwork.requestAccess()` (`.allowed`, `.denied` with `LampNetwork.allowHint` saying where to turn it on,
  or `.unknown` off a home network), never at launch. Then `await LampNetwork.find()`: every device that answers, each
  with `address`, `name`, `maker`, `model`, what it answered SSDP for (`ssdp`, `server`, `location`) and its Bonjour
  services (`bonjour`). An iPhone app sees only the Bonjour types in capabilities.json's `bonjourServices` (add the
  types of the devices the app is for: `"_sonos._tcp"`, `"_googlecast._tcp"`), and the system's question shows
  `"localNetwork"` there, the app's own reason ("TV Remote finds your TV and speakers to control them."). Work out how
  to reach each device from what it says of itself; a Roku is `LampRoku`'s. Its maker and model say what a device is;
  its services say only what it can do: a console and a TV both answer as media renderers, and a Mac offers AirPlay,
  so none of them is a speaker for that.
- Roku: `LampRoku`, for an app on the Mac or a phone that controls the person's Roku (a remote of its own, buttons
  that open Netflix or a show, what's playing, a Roku TV's power, volume and input), with nothing installed on the
  Roku. An app that runs on the Roku itself is a Roku app instead. `await LampRoku.find()` (every Roku that answers,
  each with `name`, `isTV` and `canBeControlled`), then `launch(named:)` or `launch(appID:contentID:mediaType:)` for a
  deep link, `press(.home)` and the other keys, `type(_:)` into its on-screen keyboard, `activeApp()`, `playing()`,
  `apps()`, and on a Roku TV `power(on:)`, `press(.volumeUp)` and `input(.hdmi1)`. The one setup is on the Roku:
  Settings, System, Advanced system settings, Control by mobile apps, Network access set to Enabled
  (`LampRoku.setUp` says it); show that when `canBeControlled` is false or a call says so, and never suggest
  Permissive. The first `find()` makes the system ask about the local network, so give the person a way to look
  again; remember the Roku they chose by its `id`, and offer a choice when more than one answers.

## On the Mac only

These exist only in a Mac app's copy of the library (in an app for both, only under `#if os(macOS)`):

- `LampFolderWatcher(folder) { changedURLs in }`: files added or changed in a folder; keep it alive.
- `LampFolders`: downloads, desktop, documents, screenshots, `files(in:)` newest first.
- `LampHotKey("cmd+shift+space") { }`: a shortcut that works from any app; keep it alive.
- `LampLoginItem.isEnabled`: open at login. Offer it as a toggle in Settings, never turn it on yourself; an app that
  declares `"background": true` is opened at login by Lamp.
- `LampClipboardWatcher { item in }` (item.text / image / fileURLs; keep it alive) and
  `LampClipboardWatcher.copy(text)`.

## On iPhone only

An iPhone app's copy of the library has none of the Mac-only blocks above, nor Mail, other apps, the menu bar or the
permission screens: never call them there.

- Home: `LampHome` (after `{"homekit": true}` in capabilities.json): `accessories()` (lights, locks, thermostats,
  sensors, switches, each with its room and state), `set(_:on:)`, `set(_:brightness:)`, `set(_:locked:)`,
  `read(_:)`. Apple's terms allow it only in an app whose job is controlling the home, and what it reads never
  leaves the phone: not to LampAI, a server, LampSync or the Mac.

### Work while the app is closed

When the app should do something while it's closed (fetch the news before breakfast, check a price, tidy up,
remind), declare `{"background": true}` in capabilities.json, put `.lampBackground()` on its WindowGroup, and make
`@State private var check = LampSchedule.every("prices", minutes: 60) { … }` or
`LampSchedule.daily("briefing", hour: 7) { … }` in the App, the same calls as on a Mac. iOS runs them while the app
is closed when it judges best: near the time, not on the dot, at most a few times an hour, and less for an app the
person rarely opens; while the app is open they run on time. Keep each run short (seconds) and tell the person what
came of it with a notification. Something that must happen at an exact time and only needs to tell the person is a
notification sent with `at:`, not a schedule. The simulator never wakes a closed app by itself, so try the work by
running it from the app.
