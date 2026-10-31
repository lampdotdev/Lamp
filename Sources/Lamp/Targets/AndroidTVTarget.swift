import AppKit
import Foundation

extension Platform {
    /// An Android app made for the TV (Google TV, Android TV, Fire TV): the Android kind's Kotlin, with a TV's manifest,
    /// banner and remote, run in Lamp's TV emulator or on the person's own TV over Wi‑Fi.
    static let androidTV = Platform(kind: "android-tv")
}

extension Target {
    static let androidTV = Target(
        platform: .androidTV, places: [.androidTV],
        identity: Identity(name: "the Android TV app", phrase: "an Android TV app", analytics: "android-tv", made: { _, _ in "Android TV" },
                           devices: Words(words: [("android-tv", "\"android-tv\" for Google TV, Android TV and Fire TV",
                                                     "\"android-tv\" for a Google TV, an Android TV, a Fire TV, a Chromecast with Google TV or an NVIDIA Shield")],
                                            hint: "[\"android-tv\"] when they mention Google TV, Android TV, Fire TV, a Chromecast, a Shield or a Sony, TCL or Hisense Google TV",
                                            claims: { $0 == ["android-tv"] }, alone: false,
                                            asked: ("android-tv", "for Google TV or Fire TV", "for Google TV, Android TV and Fire TV")),
                           tryOnHelp: { _ in "Where it opens: the TV emulator, or your own Google TV, Android TV or Fire TV" },
                           place: { _ in .elsewhere("Android TV", symbol: "tv") }),
        guidance: Guidance(prompt: { _ in Agent.androidPrompt(tv: true) },
                           changeRules: { _ in Agent.Rules.androidEdit + Agent.Rules.androidFrameworks + Agent.Rules.androidAI + Agent.Rules.androidData
                               + Agent.Rules.androidTVDesign + Agent.Rules.androidTry + Agent.Rules.androidTVTry },
                           skills: { [] },
                           elsewhere: { _ in "- On the person's TV: the same, while it's on this Mac's Wi‑Fi with Lamp open; away from it, no AI and no LampWish link to the wish's other apps" }),
        // An Android app's files, with a mark of its own and the TV's banner, which Lamp draws from the app's icon.
        recipe: Recipe(language: .kotlin, fill: Template.fillAndroidTV,
                       ownedFiles: Template.writeAndroidTVOwnedFiles, support: Template.writeAndroidSupport,
                       isMade: Template.isAndroidTV, scaffolded: { dir, _ in Template.isAndroidTV(dir) },
                       sources: { _ in [Template.androidAppFolder, "icon.json"] }, built: "build",
                       builtURL: { $0.dir.appendingPathComponent("app/build/outputs/apk/debug/app-debug.apk") },
                       marker: Template.androidTVMarker, refines: .android,
                       shareRefusal: "Android TV apps can't be shared as a file yet."),
        part: Part(folder: "AndroidTV", family: "android-tv", word: "android-tv", menu: ("Android TV App", "tv"),
                   rules: { Agent.androidPrompt(part: $0, alone: $1, tv: true) }) { dir, wish in
            AppFile.read(dir.appendingPathComponent(Template.androidTVMarker), inFolder: wish, last: 1) != nil
        },
        setup: Target.android.setup)
}

extension Template {
    /// The file of Lamp's that marks an Android project as a TV app's.
    static let androidTVMarker = ".lamp-android-tv"
    /// The banner a TV's home screen shows for the app (320x180 at xhdpi), drawn by Lamp from the app's icon.
    static let androidTVBanner = "app/src/main/res/drawable-xhdpi/lamp_banner.png"

    static func isAndroidTV(_ dir: URL) -> Bool {
        isAndroid(dir) && FileManager.default.fileExists(atPath: dir.appendingPathComponent(androidTVMarker).path)
    }

    /// An Android app's scaffold with the TV's manifest and starting screen in place of the phone's.
    static func fillAndroidTV(_ project: LampProject) throws {
        try fillAndroid(project)
        let package = androidPackage(for: project)
        let path = androidSources + "/" + package.replacingOccurrences(of: ".", with: "/")
        try write(androidTVManifest, to: "app/src/main/AndroidManifest.xml", for: project)
        try write(androidTVMainActivity.replacingOccurrences(of: "{{PACKAGE}}", with: package), to: path + "/MainActivity.kt", for: project)
        AppFolder.remove(project.dir.appendingPathComponent(path + "/Theme.kt"), in: project.dir)
        try write(androidAppBuildGradle.replacingOccurrences(of: "    implementation(libs.androidx.compose.material3)\n",
                                                             with: "    implementation(libs.androidx.compose.material3)\n    implementation(libs.androidx.tv.material)\n"),
                  to: "app/build.gradle.kts", for: project)
        try write(androidTVAppMd, to: "APP.md", for: project)
        try writeAndroidTVOwnedFiles(for: project)
    }

    /// An Android app's own files, its mark, and the banner: the app's icon on a dark tile, or the tile alone until it
    /// has one, since the manifest names it.
    static func writeAndroidTVOwnedFiles(for project: LampProject) throws {
        try writeAndroidOwnedFiles(for: project)
        try put("Lamp's mark of an Android TV app. Don't delete it.\n", at: project.dir.appendingPathComponent(androidTVMarker), for: project)
        let icon = AppFile.read(Icons.squareURL(project), in: project).flatMap(NSImage.init(data:))
        try put(DeviceSupport.iconPNG(icon, width: 320, height: 180), at: project.dir.appendingPathComponent(androidTVBanner), for: project)
    }

    static let androidTVManifest = """
    <?xml version="1.0" encoding="utf-8"?>
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">

        <!-- A TV app: no touch screen needed, and on a TV's home screen through the leanback launcher. -->
        <uses-feature android:name="android.software.leanback" android:required="false" />
        <uses-feature android:name="android.hardware.touchscreen" android:required="false" />

        <application
            android:allowBackup="true"
            android:banner="@drawable/lamp_banner"
            android:icon="@mipmap/ic_launcher"
            android:label="@string/app_name"
            android:roundIcon="@mipmap/ic_launcher_round"
            android:supportsRtl="true"
            android:theme="@style/Theme.App">
            <activity
                android:name=".MainActivity"
                android:exported="true"
                android:screenOrientation="landscape">
                <intent-filter>
                    <action android:name="android.intent.action.MAIN" />
                    <category android:name="android.intent.category.LAUNCHER" />
                    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
                </intent-filter>
            </activity>
        </application>

    </manifest>

    """

    static let androidTVMainActivity = """
    package {{PACKAGE}}

    import android.os.Bundle
    import androidx.activity.compose.setContent
    import androidx.compose.foundation.layout.Box
    import androidx.compose.foundation.layout.fillMaxSize
    import androidx.compose.foundation.layout.padding
    import androidx.compose.runtime.Composable
    import androidx.compose.ui.Alignment
    import androidx.compose.ui.Modifier
    import androidx.compose.ui.unit.dp
    import androidx.tv.material3.MaterialTheme
    import androidx.tv.material3.Surface
    import androidx.tv.material3.Text
    import androidx.tv.material3.darkColorScheme

    class MainActivity : LampActivity() {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            setContent {
                MaterialTheme(colorScheme = darkColorScheme()) {
                    Surface(modifier = Modifier.fillMaxSize()) {
                        MainScreen()
                    }
                }
            }
        }
    }

    @Composable
    fun MainScreen() {
        // The TV's safe area: 48dp in from the sides, 27dp from the top and bottom.
        Box(modifier = Modifier.fillMaxSize().padding(horizontal = 48.dp, vertical = 27.dp), contentAlignment = Alignment.Center) {
            Text("Lamp is making this app.", style = MaterialTheme.typography.headlineMedium)
        }
    }

    """

    static let androidTVAppMd = """
    # {{NAME}}

    An Android TV app in Kotlin and Compose for TV, built and changed with Lamp. It opens in the Android TV emulator on this Mac, or on the person's own Google TV, Android TV or Fire TV.

    ## What it does
    Nothing yet: fresh scaffold.

    ## Structure
    - `app/src/main/kotlin/…/MainActivity.kt`: the entry point and the main screen.
    - `app/src/main/AndroidManifest.xml`, `app/src/main/res/`: the manifest (a TV's, with the leanback launcher) and resources.
    - `app/build.gradle.kts`: the app's dependencies.
    - `app/src/main/kotlin/…/LampSupport.kt`: Lamp's building blocks (LampAI, LampStore, LampAssets); Lamp's, don't edit.
    - `app/src/main/res/drawable-xhdpi/lamp_banner.png`: the banner on the TV's home screen, drawn by Lamp from the app's icon; don't edit.
    - `build.sh`, `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`, `app/src/debug/AndroidManifest.xml`, `.lamp-android-tv`: Lamp's; don't edit.

    """
}

extension Agent.Rules {
    static let androidTVHeader = """
    You are Lamp's builder agent. The current directory is a standalone Android TV app in Kotlin and Compose for TV \
    (a Gradle project, Android 8.0 and later, no Android Studio). Lamp builds it and opens it in the Android TV \
    emulator on the user's Mac, which is what the user sees, or on their own Google TV, Android TV or Fire TV when \
    they choose it under Try On and press Play. Read APP.md first for context.
    """

    static let androidTVDesign = """
    - It's on a 1920x1080 TV (960x540dp), driven by the remote's D-pad: up, down, left, right, select, back and home; \
    there's no touch and no pointer. Use Compose for TV (androidx.tv.material3, already in app/build.gradle.kts) for \
    what the person moves between: its Button, Card, ListItem, Carousel, Tab and NavigationDrawer show focus by \
    themselves, and anything else clickable needs a focused look of its own. Give each screen's first item focus as it \
    opens (a FocusRequester), and Back goes back a screen and leaves the app from the first. A text field brings up \
    the TV's keyboard. How to design what a TV shows, seen from across the room, is the tv-design skill's: open it \
    with `read_skill` before designing or restyling the app's screens. Keep the manifest's leanback launcher and \
    banner, and never edit app/src/main/res/drawable-xhdpi/lamp_banner.png, which Lamp draws from the app's icon.
    """

    static let androidTVTry = """
    - It's a TV: try it with `key` actions as the person would with the remote (up, down, left, right, select, \
    back, home, menu and play), not taps, and look at where focus is after each.
    """
}
