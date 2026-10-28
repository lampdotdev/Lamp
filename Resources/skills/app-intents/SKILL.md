---
name: app-intents
description: Giving the app's main actions to Siri, Shortcuts, Spotlight and the Action button with App Intents - the intent structs, AppShortcuts phrases, entities, what the build needs, and what to tell the person. Read before writing or changing Sources/Intents.swift.
---

# App Intents

## Writing them

In Sources/Intents.swift, `import AppIntents` and write a struct per action: `struct AddItemIntent: AppIntent` with
`static let title: LocalizedStringResource = "Add Item"`, its inputs as `@Parameter(title: "Item") var item:
String`, and `func perform() async throws -> some IntentResult & ProvidesDialog` that does the work with the app's own
code (LampStore and the rest: it runs in the app, started without a window when it isn't open) and ends
`return .result(dialog: "Added \(item)")`; `static let openAppWhenRun = true` only for one that has to show the app.

Then one `struct AppShortcuts: AppShortcutsProvider` whose `static var appShortcuts` lists them,
`AppShortcut(intent: AddItemIntent(), phrases: ["Add an item to \(.applicationName)"], shortTitle: "Add Item",
systemImageName: "cart")`: that is what Siri hears and Spotlight and Shortcuts show with no setup. Every phrase names
`\(.applicationName)`, and a phrase can name only a parameter that is an `AppEnum` or `AppEntity`, never a String. For
the app's own things (lists, notes, places), an `AppEntity` with an `EntityQuery` lets Shortcuts pick one.

Titles and phrases are plain literals: the build reads them from the code and fails on what it can't read.

## Checking and telling the person

When the build warns that Xcode isn't installed, the app works but the system doesn't see its intents: say so.
Nothing here can run an intent, so check that the build succeeds and that what perform calls works in the app, then
tell the user in a sentence what to say to Siri or search for.

A Mac app's App Intents work when Lamp signs it for the user's Apple developer team; when it can't, `look_at_app`
says so, and you tell the user how to turn them on as it says.
