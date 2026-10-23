---
name: apple-watch
description: The app's Apple Watch app and its complications (Watch/) - the watch app, complications on a watch face, the data the phone shares with them, taps sent back to the phone, and workouts saved to Health. Read before writing or changing anything in Watch/.
---

# An Apple Watch app with complications

## The watch app

Write it in SwiftUI in a `Watch/` folder at the app's root, starting with Watch/WatchApp.swift: one `@main` App whose
WindowGroup ends in `.lampWatch()`, which keeps complications current while the watch app is closed, and a screen or
two of big controls. The watch app's icon is the app's.

## Complications

They go in Watch/Complications/: one `@main` `WidgetBundle` of `StaticConfiguration`s with `.supportedFamilies` from
`.accessoryCircular`, `.accessoryRectangular`, `.accessoryInline` and `.accessoryCorner`, and
`.containerBackground(.fill.tertiary, for: .widget)`.

Neither the watch app nor its complications share code with Sources/ or have LampSupport.swift: declare the Codable
types they read in each folder. Watch/LampWatchSupport.swift and its copy in Complications/ are Lamp's: never edit
them.

## The data

- In the app, `LampWatch.share(Today(…), as: "today")` at launch and whenever it changes.
- On the watch, `@LampWatched("today") var today: Today?` in a view, or `LampWatch.read(Today.self, from: "today")` in
  a complication's timeline, nil until the phone has first shared.
- A tap on the watch: `LampWatch.send("addGlass", 1)`, done in the app by `LampWatch.onAction { name, payload in … }`
  set at launch (`payload.decode(Int.self)`), which shares what changed.

## Workouts

A workout on the watch, saved to Health with heart rate, calories and distance: `@StateObject private var workout =
LampWorkout()` from Watch/LampWatchSupport.swift, `try await workout.start(.running)`, `pause()`, `resume()`,
`await workout.end()`, with `{"healthkit": true}` in capabilities.json. The simulator's watch measures nothing, so
check it starts and ends.

## Trying it and saying so

Lamp opens the watch app on an Apple Watch simulator beside the iPhone; `look_at_app` and `use_app` see only the
iPhone, so don't try them on the watch. Say in a sentence that it's on the watch, and that a complication is added by
editing a watch face.
