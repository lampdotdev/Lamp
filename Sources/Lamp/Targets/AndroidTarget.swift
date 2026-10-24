import Foundation

extension Platform {
    /// Kotlin and Compose (`AndroidTools`), run in the Android emulator or on the person's own device.
    static let android = Platform(kind: "android")
}

extension Target {
    static let android = Target(
        platform: .android, places: [.android],
        identity: Identity(name: "the Android app", phrase: "an Android app", analytics: "android", made: { _, _ in "Android" },
                           devices: Words(words: [("android", "\"android\" for an Android phone or tablet", "\"android\" for an Android phone or tablet")],
                                            hint: "[\"android\"] when they mention Android, a Pixel, a Samsung phone or Google Play",
                                            claims: { $0 == ["android"] }, alone: false,
                                            asked: ("android", "for an Android phone", "for Android phones")),
                           tryOnHelp: { _ in "Where it opens: the emulator, or your own Android phone or tablet" },
                           place: { _ in .elsewhere("Android", symbol: "smartphone") }),
        guidance: Guidance(prompt: { _ in Agent.androidPrompt() },
                           changeRules: { _ in Agent.Rules.androidEdit + Agent.Rules.androidFrameworks + Agent.Rules.androidAI + Agent.Rules.androidData + Agent.Rules.androidTry },
                           skills: { ["android-design"] },
                           // It reaches AI only through this Mac, in the emulator or over the same Wi‑Fi.
                           elsewhere: { _ in "- On the person's Android device: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, no AI" }),
        recipe: Recipe(language: .kotlin, fill: Template.fillAndroid,
                       // The Gradle project's files and its Kotlin building blocks.
                       ownedFiles: Template.writeAndroidOwnedFiles, support: Template.writeAndroidSupport,
                       isMade: Template.isAndroid, scaffolded: { dir, _ in Template.isAndroid(dir) },
                       // Its code is its `app` module, whose `build` folder is what the build makes.
                       sources: { _ in [Template.androidAppFolder, "icon.json"] }, built: "build",
                       builtURL: { $0.dir.appendingPathComponent("app/build/outputs/apk/debug/app-debug.apk") },
                       shareRefusal: nil),
        // Beside another kind's app (a Mac app's Android app, a TV app's), in a Gradle project of its own.
        part: Part(folder: "Android", family: "android", word: "android", menu: ("Android App", "smartphone"), rules: { Agent.androidPrompt(part: $0) }) { dir, wish in
            AppFile.read(dir.appendingPathComponent(Template.androidSettingsFile), inFolder: wish, last: 1) != nil
        },
        setup: Setup(
            // Not asked for, it's a Mac app until Google's tools are here, with the setup a button away; asked for, the
            // setup opens now, since the build can't go on without them.
            canChoose: { said, _ in
                guard !AndroidTools.isReady else { return true }
                if said { AndroidSetup.shared.show() }
                return said
            },
            notReady: { _, _ in
                guard let issue = await AndroidTools.check().issue else { return nil }
                AndroidSetup.shared.show()
                return "this Mac can't build it for Android. \(issue.title): \(issue.message) Lamp opened its setup steps."
            },
            // Once the setup is done, the Mac app made meanwhile stays (no app is written over again as another kind):
            // the Android app goes beside it.
            later: SetupLater(symbol: "smartphone", needs: "a few things from Google", apps: "Android apps", request: "Make it for Android too, keeping the Mac app.") { _, cancelled, done in
                AndroidSetup.shared.perform(device: nil, cancelled: cancelled, then: done)
            }))
}

extension Language {
    static let kotlin = Language(name: "kotlin", code: "the Kotlin in app/", leftover: "app/ and the Gradle files") {
        "Write the app again in Kotlin and Jetpack Compose under app/ (the scaffold is there), reading \($0) for what it does, then delete \($1) with delete_file. "
    }
}
