---
name: mac-widgets
description: A Mac app's widget for the desktop and Notification Center (Widget/) - how it's written and drawn, the data the app hands it, buttons in it, a widget with no app window, and what to tell the person. Read before writing or changing anything in Widget/.
---

# A widget for the desktop and Notification Center

## Writing it

Write it with WidgetKit and SwiftUI in a `Widget/` folder at the app's root, beside Sources/, starting with
Widget/Widget.swift: one `@main`, on the `Widget` or on a `WidgetBundle` for several. Lamp builds that folder into the
app as its widget. It is a separate program that shares no code with Sources/: nothing from LampSupport.swift exists
there, and a type both sides need is written on both.

- Use `StaticConfiguration` with a `TimelineProvider`, a `configurationDisplayName` and `description` in the user's
  words, `supportedFamilies` from .systemSmall, .systemMedium and .systemLarge, and
  `.containerBackground(for: .widget) { … }` on the view, without which it shows nothing.
- Put `.lampWand()` on each widget's whole view too (`.lampWand(edgeToEdge: true)` with `.contentMarginsDisabled()`):
  it's Lamp's wand in the top right corner, which opens the app's chat, so leave that corner empty.
- A widget is a picture macOS redraws from the timeline, not a running view: no timers, animation, scrolling or text
  fields. `Text(date, style: .timer)` and `.relative` count by themselves, entries dated ahead change it on
  schedule, and macOS refreshes it when it chooses, minutes apart at best. It may load from the web with URLSession.

## The app's data

The widget can't read what the app has saved (LampStore, files, settings), so the app hands it over:

- In the app, `LampWidget.share(Summary(…), as: "summary")` with any Codable value, at launch and whenever the data
  changes (it also redraws the widget).
- In the widget, `LampWidget.read(Summary.self, from: "summary") { summary in … }` in getSnapshot and getTimeline, or
  `await` it. That comes from Widget/LampWidgetSupport.swift, which Lamp writes: never edit it. It gives what the app
  shared last, also while the app is closed, and nil until the app has run once: then show a short line asking to
  open the app.
- Share a small value made for the widget, not everything, and declare its type on both sides.

A button or toggle in the widget changes the app's data through the app: in Widget/, an App Intent whose `perform()`
calls `await LampWidget.perform("addWater", 250)` (a name, and any Codable value or none) and returns `.result()`,
shown with `Button(intent: AddWater()) { … }`; in the app, at launch, `LampWidget.onAction { name, payload in … }`
does it (`payload.decode(Int.self)`) and shares what changed, and the widget redraws. It works with the app closed
too: the app does it when it next starts.

## When the widget is all they asked for

When a widget is all the user asked for ("make me a countdown widget"), they get only the widget, with no app
window: make Sources/App.swift just `@main struct MainApp: App { var body: some Scene { LampWidgetOnly() } }`, with no
commands, delete Sources/ContentView.swift with delete_file, and put everything in the widget, which works out what it
shows by itself (the date, the web). Such an app has no window, no Dock icon and is never opened, so don't call
`look_at_app` or `use_app` for it.

Only when the widget has to show something an app must fetch or keep for it (the user's files, calendar or mail,
what they type in, an AI answer) does it get a real app, which shares that with `LampWidget.share` and lives in the
menu bar (`LampMenuBar`, with its Quit button; the menu-bar skill says how) unless the user asked for a window too.

## What to tell the person

Lamp shows the user a card that says how to add the widget and when it's on their desktop, so never explain how to
add it, and never say you couldn't see it. When the request was for a widget, what you say once it's made is two
sentences at most, on what the widget shows: no list of sizes or options, no assumptions, no "it's ready", no
question at the end. A widget they placed stays through your changes and shows them by itself. To take the widget
away, delete the files in Widget/.
