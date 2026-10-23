---
name: iphone-widgets
description: An iPhone app's home screen widgets, Live Activities and Control Center controls (Widget/) - how they're written, the code they share with the app, the data the app hands them, buttons in them, and how to see them in the simulator. Read before writing or changing anything in Widget/.
---

# Home screen widgets, Live Activities and controls

## Writing them

Write them with WidgetKit, SwiftUI and ActivityKit in a `Widget/` folder at the app's root, beside Sources/, starting
with Widget/Widget.swift: one `@main` on a `WidgetBundle` holding the widgets (`StaticConfiguration` with a
`TimelineProvider`, `.containerBackground(.fill.tertiary, for: .widget)`, `.supportedFamilies` for the sizes that fit)
and any `ActivityConfiguration` (the lock screen's view and the `dynamicIsland` regions). Lamp builds that folder into
the app as its extension.

It shares no code with Sources/ and has nothing from LampSupport.swift, except Widget/Shared/: Swift there is compiled
into both the app and the extension (Lamp links it into Sources/ as Sources/WidgetShared; edit it in Widget/Shared/),
the place for an `ActivityAttributes` type and anything else both sides need.

## The widget's data

- In the app, `LampWidget.share(Summary(…), as: "summary")` with any Codable value, at launch and whenever it changes
  (it redraws the widgets too).
- In the widget, `LampWidget.read(Summary.self, from: "summary") { summary in … }` in getSnapshot and getTimeline, or
  `await` it, from Widget/LampWidgetSupport.swift, which Lamp writes: never edit it. It gives what the app shared
  last, also while the app is closed, and nil until then: show a short line asking to open the app.

## Live Activities

A Live Activity starts from the app, `Activity.request(attributes:content:)`, and is changed with `update` and ended
with `end` from the app while it runs; there's no server to push changes, so give a timer or progress an end date
(`Text(timerInterval:countsDown:)`, `ProgressView(timerInterval:)`) and it moves by itself.

## Buttons and controls

A button or toggle in a widget or Live Activity runs an App Intent, `Button(intent: AddCupIntent()) { … }` or
`Toggle(isOn:intent:)`: write that intent in Widget/Shared/ as a `LiveActivityIntent`, which iOS performs in the app
(starting it out of sight when it's closed), and keep the work under `#if !LAMP_WIDGET` (defined only in the widget,
which can't reach the app's code): change the data there and `LampWidget.share` it, and the widget redraws.

A Control Center control is a `ControlWidget` in the same `WidgetBundle`, marked `@available(iOS 18, *)`:
`StaticControlConfiguration(kind: "AddCup") { ControlWidgetButton(action: AddCupIntent()) { Label("Add a Cup",
systemImage: "cup.and.saucer") } }`.

## Seeing them, and what to tell the person

- `use_app` with `key` "lock" shows the lock screen, where a Live Activity is, and "home" the home screen; then the
  picture.
- Not every iPhone has a Dynamic Island (the iPhone 14 Pro and Pro Max, and every iPhone 15 and later but the 16e
  have one; iPads don't): `look_at_app` says which simulator the app is open on, and when it has none, say so and
  that the person can choose one under Try On.
- Only the person can add a widget to the home screen, and Lamp shows them how: don't explain it, and say in a
  sentence that it's ready to add.
