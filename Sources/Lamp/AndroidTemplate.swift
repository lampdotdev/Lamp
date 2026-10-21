import Foundation

/// The scaffold of an Android app, and the rules its agent is given. An Android app is a Gradle project in the
/// app's folder: Lamp owns what the build runs before any of the agent's code does (build.sh, the settings and
/// top-level build files, gradle.properties and the versions catalogue, written afresh before every build like a
/// Mac app's Package.swift), and the agent owns `app/`: its build file, manifest, Kotlin and resources. There is
/// no support library of Lamp's for Android yet: the app is plain Kotlin and Jetpack Compose.
extension Template {
    static let androidAppFolder = "app"
    static let androidSources = "app/src/main/kotlin"

    /// The app's package name, which Android ties its data and identity to: Lamp's prefix and the app's folder name,
    /// with what Java's names can't carry (a hyphen, a leading digit) made safe.
    static func androidPackage(for project: LampProject) -> String {
        (Edition.appBundlePrefix + project.id).split(separator: ".").map { part -> String in
            var safe = part.map { $0.isLetter || $0.isNumber ? String($0) : "_" }.joined()
            if safe.first?.isNumber == true { safe = "_" + safe }
            return safe.isEmpty ? "_" : safe
        }.joined(separator: ".")
    }

    /// Whether an app's folder is an Android project, read off what every version keeps (`platform(fromPackageIn:)`).
    static func isAndroid(_ dir: URL) -> Bool {
        FileManager.default.fileExists(atPath: dir.appendingPathComponent("settings.gradle.kts").path)
    }

    /// Lamp's files for an Android app, written afresh before every build.
    static func writeAndroidOwnedFiles(for project: LampProject) throws {
        try write(androidBuildSh, to: "build.sh", for: project, executable: true)
        try write(androidSettingsGradle, to: "settings.gradle.kts", for: project)
        try write(androidRootBuildGradle, to: "build.gradle.kts", for: project)
        try write(androidGradleProperties, to: "gradle.properties", for: project)
        try write(androidVersionsCatalogue, to: "gradle/libs.versions.toml", for: project)
    }

    /// The agent's starting files for a new Android app.
    static func fillAndroid(_ project: LampProject) throws {
        let package = androidPackage(for: project)
        let path = androidSources + "/" + package.replacingOccurrences(of: ".", with: "/")
        try write(androidAppBuildGradle, to: "app/build.gradle.kts", for: project)
        try write(androidManifest, to: "app/src/main/AndroidManifest.xml", for: project)
        try write(androidMainActivity.replacingOccurrences(of: "{{PACKAGE}}", with: package), to: path + "/MainActivity.kt", for: project)
        try write(androidTheme.replacingOccurrences(of: "{{PACKAGE}}", with: package), to: path + "/Theme.kt", for: project)
        try write(androidStrings, to: "app/src/main/res/values/strings.xml", for: project)
        try write(androidThemes, to: "app/src/main/res/values/themes.xml", for: project)
        try write(androidIconBackground, to: "app/src/main/res/drawable/ic_launcher_background.xml", for: project)
        try write(androidIconForeground, to: "app/src/main/res/drawable/ic_launcher_foreground.xml", for: project)
        try write(androidAdaptiveIcon, to: "app/src/main/res/mipmap-anydpi-v26/ic_launcher.xml", for: project)
        try write(androidAdaptiveIcon, to: "app/src/main/res/mipmap-anydpi-v26/ic_launcher_round.xml", for: project)
        try write(androidAppMd, to: "APP.md", for: project)
        try write(".gradle/\nbuild/\n.lamp/\n.kotlin/\nlocal.properties\n", to: ".gitignore", for: project)
        try FileManager.default.createDirectory(at: project.dir.appendingPathComponent(Sharing.Assets.folder), withIntermediateDirectories: true)
        try writeAndroidOwnedFiles(for: project)
    }

    /// The build: Gradle, from Lamp's own copy, with Google's tools where Lamp put them, in the app's sandbox like
    /// every build. The app's icon, drawn by Lamp as for every app, goes in as the launcher icon when there is one;
    /// until then the scaffold's own. The daemon Gradle keeps between builds is this app's alone (`-Dlamp.app`,
    /// which Gradle matches daemons by): one started in another app's sandbox could read nothing of this one.
    static let androidBuildSh = """
    #!/bin/zsh
    # Written by Lamp before every build; don't edit.
    set -e
    cd "$(dirname "$0")"
    if [ -z "$LAMP_GRADLE" ] || [ -z "$ANDROID_HOME" ]; then
      echo "Android's tools aren't set up. Open the app in Lamp to download them." >&2
      exit 1
    fi
    ICON=".lamp/AppIcon-square.png"
    if [ -f "$ICON" ]; then
      mkdir -p app/src/main/res/mipmap-xxxhdpi
      /usr/bin/sips -z 432 432 "$ICON" --out app/src/main/res/mipmap-xxxhdpi/ic_launcher.png > /dev/null
      cp app/src/main/res/mipmap-xxxhdpi/ic_launcher.png app/src/main/res/mipmap-xxxhdpi/ic_launcher_round.png
      rm -rf app/src/main/res/mipmap-anydpi-v26
    fi
    printf 'sdk.dir=%s\\n' "$ANDROID_HOME" > local.properties
    exec "$LAMP_GRADLE" --console=plain -q "-Dlamp.app={{SLUG}}" assembleDebug
    """

    static let androidSettingsGradle = """
    // Written by Lamp before every build; don't edit.
    pluginManagement {
        repositories {
            google {
                content {
                    includeGroupByRegex("androidx.*")
                    includeGroupByRegex("com\\\\.android.*")
                    includeGroupByRegex("com\\\\.google.*")
                }
            }
            mavenCentral()
            gradlePluginPortal()
        }
    }
    dependencyResolutionManagement {
        repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
        repositories {
            google {
                content {
                    includeGroupByRegex("androidx.*")
                    includeGroupByRegex("com\\\\.android.*")
                    includeGroupByRegex("com\\\\.google.*")
                }
            }
            mavenCentral()
        }
    }

    rootProject.name = "{{EXE}}"
    include(":app")

    """

    static let androidRootBuildGradle = """
    // Written by Lamp before every build; don't edit.
    plugins {
        alias(libs.plugins.android.application) apply false
        alias(libs.plugins.compose.compiler) apply false
        alias(libs.plugins.kotlin.serialization) apply false
    }

    """

    static let androidGradleProperties = """
    # Written by Lamp before every build; don't edit.
    org.gradle.jvmargs=-Xmx2048m -Dfile.encoding=UTF-8 -Dlamp.app={{SLUG}}
    org.gradle.daemon.idletimeout=600000
    org.gradle.caching=true
    org.gradle.configuration-cache=true
    android.useAndroidX=true
    kotlin.code.style=official
    android.nonTransitiveRClass=true

    """

    /// The versions Lamp builds with, the ones Google's own project template pairs; moved on purpose, with a build tried first.
    static let androidVersionsCatalogue = """
    # Written by Lamp before every build; don't edit. Add other libraries in app/build.gradle.kts with their full names.
    [versions]
    androidGradlePlugin = "9.0.1"
    androidxCore = "1.18.0"
    androidxLifecycle = "2.10.0"
    androidxActivity = "1.13.0"
    androidxComposeBom = "2026.03.01"
    androidxNavigation3 = "1.0.1"
    androidxDatastore = "1.1.7"
    coroutines = "1.10.2"
    kotlin = "2.3.20"
    serialization = "1.9.0"

    [libraries]
    androidx-core-ktx = { module = "androidx.core:core-ktx", version.ref = "androidxCore" }
    androidx-activity-compose = { module = "androidx.activity:activity-compose", version.ref = "androidxActivity" }
    androidx-compose-bom = { group = "androidx.compose", name = "compose-bom", version.ref = "androidxComposeBom" }
    androidx-compose-material3 = { group = "androidx.compose.material3", name = "material3" }
    androidx-compose-material-icons = { group = "androidx.compose.material", name = "material-icons-extended" }
    androidx-compose-ui = { group = "androidx.compose.ui", name = "ui" }
    androidx-compose-ui-tooling-preview = { group = "androidx.compose.ui", name = "ui-tooling-preview" }
    androidx-compose-ui-tooling = { group = "androidx.compose.ui", name = "ui-tooling" }
    androidx-lifecycle-viewmodel-compose = { module = "androidx.lifecycle:lifecycle-viewmodel-compose", version.ref = "androidxLifecycle" }
    androidx-lifecycle-runtime-compose = { module = "androidx.lifecycle:lifecycle-runtime-compose", version.ref = "androidxLifecycle" }
    androidx-lifecycle-runtime-ktx = { module = "androidx.lifecycle:lifecycle-runtime-ktx", version.ref = "androidxLifecycle" }
    androidx-navigation3-runtime = { module = "androidx.navigation3:navigation3-runtime", version.ref = "androidxNavigation3" }
    androidx-navigation3-ui = { module = "androidx.navigation3:navigation3-ui", version.ref = "androidxNavigation3" }
    androidx-datastore-preferences = { module = "androidx.datastore:datastore-preferences", version.ref = "androidxDatastore" }
    kotlinx-coroutines-android = { module = "org.jetbrains.kotlinx:kotlinx-coroutines-android", version.ref = "coroutines" }
    kotlinx-serialization-json = { module = "org.jetbrains.kotlinx:kotlinx-serialization-json", version.ref = "serialization" }

    [plugins]
    android-application = { id = "com.android.application", version.ref = "androidGradlePlugin" }
    compose-compiler = { id = "org.jetbrains.kotlin.plugin.compose", version.ref = "kotlin" }
    kotlin-serialization = { id = "org.jetbrains.kotlin.plugin.serialization", version.ref = "kotlin" }

    """

    static let androidAppBuildGradle = """
    plugins {
        alias(libs.plugins.android.application)
        alias(libs.plugins.compose.compiler)
        alias(libs.plugins.kotlin.serialization)
    }

    android {
        namespace = "{{ANDROID_PACKAGE}}"
        compileSdk = 36
        defaultConfig {
            applicationId = "{{ANDROID_PACKAGE}}"
            minSdk = 26
            targetSdk = 36
            versionCode = 1
            versionName = "1.0"
        }
        compileOptions {
            sourceCompatibility = JavaVersion.VERSION_17
            targetCompatibility = JavaVersion.VERSION_17
        }
        buildFeatures {
            compose = true
            buildConfig = false
        }
        sourceSets["main"].kotlin.srcDirs("src/main/kotlin")
        packaging {
            resources {
                excludes += "/META-INF/{AL2.0,LGPL2.1}"
            }
        }
    }

    kotlin {
        jvmToolchain(17)
    }

    dependencies {
        val composeBom = platform(libs.androidx.compose.bom)
        implementation(composeBom)
        implementation(libs.androidx.core.ktx)
        implementation(libs.androidx.lifecycle.runtime.ktx)
        implementation(libs.androidx.lifecycle.runtime.compose)
        implementation(libs.androidx.lifecycle.viewmodel.compose)
        implementation(libs.androidx.activity.compose)
        implementation(libs.androidx.compose.ui)
        implementation(libs.androidx.compose.ui.tooling.preview)
        implementation(libs.androidx.compose.material3)
        implementation(libs.androidx.compose.material.icons)
        implementation(libs.androidx.navigation3.ui)
        implementation(libs.androidx.navigation3.runtime)
        implementation(libs.androidx.datastore.preferences)
        implementation(libs.kotlinx.coroutines.android)
        implementation(libs.kotlinx.serialization.json)
        debugImplementation(libs.androidx.compose.ui.tooling)
    }

    """

    static let androidManifest = """
    <?xml version="1.0" encoding="utf-8"?>
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">

        <application
            android:allowBackup="true"
            android:icon="@mipmap/ic_launcher"
            android:label="@string/app_name"
            android:roundIcon="@mipmap/ic_launcher_round"
            android:supportsRtl="true"
            android:windowSoftInputMode="adjustResize"
            android:theme="@style/Theme.App">
            <activity
                android:name=".MainActivity"
                android:exported="true">
                <intent-filter>
                    <action android:name="android.intent.action.MAIN" />
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </activity>
        </application>

    </manifest>

    """

    static let androidMainActivity = """
    package {{PACKAGE}}

    import android.os.Bundle
    import androidx.activity.ComponentActivity
    import androidx.activity.compose.setContent
    import androidx.activity.enableEdgeToEdge
    import androidx.compose.foundation.layout.fillMaxSize
    import androidx.compose.foundation.layout.padding
    import androidx.compose.material3.MaterialTheme
    import androidx.compose.material3.Scaffold
    import androidx.compose.material3.Text
    import androidx.compose.runtime.Composable
    import androidx.compose.ui.Alignment
    import androidx.compose.ui.Modifier
    import androidx.compose.foundation.layout.Box
    import androidx.compose.ui.unit.dp

    class MainActivity : ComponentActivity() {
        override fun onCreate(savedInstanceState: Bundle?) {
            super.onCreate(savedInstanceState)
            enableEdgeToEdge()
            setContent {
                AppTheme {
                    Scaffold(modifier = Modifier.fillMaxSize()) { padding ->
                        MainScreen(modifier = Modifier.padding(padding))
                    }
                }
            }
        }
    }

    @Composable
    fun MainScreen(modifier: Modifier = Modifier) {
        Box(modifier = modifier.fillMaxSize().padding(24.dp), contentAlignment = Alignment.Center) {
            Text("Lamp is making this app.", style = MaterialTheme.typography.titleLarge)
        }
    }

    """

    static let androidTheme = """
    package {{PACKAGE}}

    import android.os.Build
    import androidx.compose.foundation.isSystemInDarkTheme
    import androidx.compose.material3.MaterialTheme
    import androidx.compose.material3.darkColorScheme
    import androidx.compose.material3.dynamicDarkColorScheme
    import androidx.compose.material3.dynamicLightColorScheme
    import androidx.compose.material3.lightColorScheme
    import androidx.compose.runtime.Composable
    import androidx.compose.ui.platform.LocalContext

    @Composable
    fun AppTheme(darkTheme: Boolean = isSystemInDarkTheme(), content: @Composable () -> Unit) {
        val colorScheme = when {
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.S -> {
                val context = LocalContext.current
                if (darkTheme) dynamicDarkColorScheme(context) else dynamicLightColorScheme(context)
            }
            darkTheme -> darkColorScheme()
            else -> lightColorScheme()
        }
        MaterialTheme(colorScheme = colorScheme, content = content)
    }

    """

    static let androidStrings = """
    <resources>
        <string name="app_name">{{NAME}}</string>
    </resources>

    """

    static let androidThemes = """
    <?xml version="1.0" encoding="utf-8"?>
    <resources>
        <style name="Theme.App" parent="android:Theme.Material.Light.NoActionBar" />
    </resources>

    """

    static let androidIconBackground = """
    <?xml version="1.0" encoding="utf-8"?>
    <vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
        <path android:fillColor="#4A4A4A" android:pathData="M0,0h108v108h-108z" />
    </vector>

    """

    static let androidIconForeground = """
    <?xml version="1.0" encoding="utf-8"?>
    <vector xmlns:android="http://schemas.android.com/apk/res/android"
        android:width="108dp" android:height="108dp" android:viewportWidth="108" android:viewportHeight="108">
        <path android:fillColor="#FFFFFF" android:pathData="M54,30a24,24 0 1,0 0.01,0z" />
    </vector>

    """

    static let androidAdaptiveIcon = """
    <?xml version="1.0" encoding="utf-8"?>
    <adaptive-icon xmlns:android="http://schemas.android.com/apk/res/android">
        <background android:drawable="@drawable/ic_launcher_background" />
        <foreground android:drawable="@drawable/ic_launcher_foreground" />
    </adaptive-icon>

    """

    static let androidAppMd = """
    # {{NAME}}

    An Android app in Kotlin and Jetpack Compose, built and changed with Lamp. It opens in the Android emulator on this Mac, or on the person's own Android phone or tablet.

    ## What it does
    Nothing yet: fresh scaffold.

    ## Structure
    - `app/src/main/kotlin/…/MainActivity.kt`: the entry point and the main screen.
    - `app/src/main/kotlin/…/Theme.kt`: the Material 3 theme.
    - `app/src/main/AndroidManifest.xml`, `app/src/main/res/`: the manifest and resources.
    - `app/build.gradle.kts`: the app's dependencies.
    - `build.sh`, `settings.gradle.kts`, `build.gradle.kts`, `gradle.properties`, `gradle/libs.versions.toml`: Lamp's; don't edit.

    """
}

extension Agent {
    /// The rules for an Android app: the same shape as the Mac's and the iPhone's, said for Kotlin and Compose. No
    /// building block of Lamp's is in it yet, so the rules say so, and the agent builds on Android's own.
    static func androidPrompt() -> String {
        let rules = [Rules.androidEdit, Rules.ask, Rules.shell, Rules.androidFrameworks, Rules.androidData, Rules.androidPermissions,
                     Rules.androidKinds, Rules.androidDesign, Rules.androidGenerated, Rules.icon, Rules.about, Rules.androidAttachments,
                     Rules.androidLogs, Rules.androidTry, Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        return (Rules.androidHeader + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: "Android")
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "an Android phone")
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "builds it and opens it in the emulator")
    }
}

extension Agent.Rules {
    static let androidHeader = """
    You are Lamp's builder agent. The current directory is a standalone Android app in Kotlin and Jetpack Compose \
    (a Gradle project, Android 8.0 and later, Material 3, no Android Studio). Lamp builds it and opens it in the \
    Android emulator on the user's Mac, which is what the user sees, or on their own Android phone or tablet when \
    they choose it under Try On and press Play. Read APP.md first for context.
    """

    static let androidEdit = """
    - Make the change the user asks for by editing the Kotlin under app/src/main/kotlin, the resources under \
    app/src/main/res and app/src/main/AndroidManifest.xml. Split code into files as it grows. Keep the package \
    name the scaffold has.
    """

    static let androidFrameworks = """
    - Write code that compiles first time: Kotlin and Jetpack Compose with Material 3, AndroidX and the Kotlin \
    libraries already in app/build.gradle.kts (Compose, Material 3 with its extended icons, lifecycle and \
    ViewModel, Navigation 3, DataStore, coroutines, serialization). Another library goes in app/build.gradle.kts \
    with its full name and version; nothing from Google Play services or Firebase, which need accounts, and nothing \
    that needs an API key you don't have. build.sh, settings.gradle.kts, build.gradle.kts at the root, \
    gradle.properties and gradle/libs.versions.toml belong to Lamp and are rewritten before every build: never \
    edit them. There is no library of Lamp's in this app: no LampStore, no LampAI, no connectors. Build on \
    Android's own instead, and when the user asks for AI or an account the app can't have yet, say so plainly \
    and build the rest.
    """

    static let androidData = """
    - Keep the user's data with DataStore for settings and small state, and for lists of things a Room database \
    (add androidx.room with its KSP compiler to app/build.gradle.kts when you need it) or a JSON file in \
    `filesDir` written with kotlinx.serialization, whichever fits. People rely on their data through every change \
    you make, so once a type is saved, only ever add to it: new properties get defaults, and never rename, remove \
    or retype a saved property.
    """

    static let androidPermissions = """
    - What the app needs beyond its code goes in the manifest: `<uses-permission>` for the camera, location, \
    notifications (POST_NOTIFICATIONS), the microphone, contacts and the rest, each requested at runtime with \
    `rememberLauncherForActivityResult(RequestPermission())` where it's first needed, with the screen still \
    usable when it's refused. Internet needs `android.permission.INTERNET`.
    """

    static let androidKinds = """
    - Decide what kind of app it is before its look, and keep it in APP.md: a tool with one screen and one job; \
    a collection of things (notes, recipes, places) with a list, a detail screen and search; a dashboard of \
    numbers that reads at a glance; a companion for something under way (a timer, a trip) with its state large and \
    one action; a game, which draws itself in a Canvas or with Compose animations rather than Material controls. \
    Most apps are one activity with Compose screens and Navigation 3 between them.
    """

    static let androidDesign = """
    - Make it look like a good Android app, not a web page: Material 3 with the dynamic color the theme gives it, \
    edge to edge with `Scaffold` and its padding, a top app bar only when the screen has a title or actions, a \
    bottom navigation bar for three to five top-level screens, a floating action button for the one main thing \
    to add, cards and list items from Material, large touch targets, and text from `MaterialTheme.typography`. \
    Respect the system's dark mode. No hard-coded colors but an accent the app is about.
    """

    static let androidGenerated = """
    - The app opens in the emulator, an Android phone on the user's Mac, and Lamp reopens it with every change: \
    keep what the person was looking at (the selected item or tab) with `rememberSaveable`, and their data \
    saved as above, so it comes back as they left it.
    """

    static let androidAttachments = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac and never \
    ship with the app. When the app should use one (a logo, a data file, a sound), copy it into \
    app/src/main/assets/ (make the folder if needed) and read it with `context.assets.open("name")`, or into \
    app/src/main/res/ as a resource. Screenshots and mockups are usually just references for you: leave them \
    in Attachments/.
    """

    static let androidLogs = """
    - Beyond `look_at_app` and `use_app`, you can't watch the app run, but Lamp saves what it logs (Log.d and \
    the rest, printed output, uncaught exceptions with their stack traces) in .lamp/runtime/log.txt for the \
    latest launch and .lamp/runtime/previous-log.txt for the one before. When the user says something doesn't \
    work, read the log before guessing. If the code doesn't show the cause, add `Log.d` calls around it: the \
    output will be there on your next turn, after the user has tried again. When Lamp mentions a screenshot of \
    the app, that is what the user was looking at: use it to check layout and visual problems rather than \
    imagining the result from the code.
    """

    static let androidTry = """
    - `look_at_app` builds the app and opens it in the emulator (or on the person's device when Try On points \
    there) and shows you the screen; `use_app` then taps, types, scrolls and swipes on it like a finger (click to \
    tap, right_click for a long press, type into the field you tapped last, which replaces what it held, key \
    return, back, home, delete, up, down, left or right, scroll, swipe with a direction and `item` to tap what the \
    swipe uncovered), and tells you what each action landed on. Both also give you the screen as text: every \
    control and piece of text on it with an id, its name, what it holds and where it is. Act on things by name: \
    set `target` to an id or exact name from that list, and trust it over the picture for exact words and \
    values. Use x and y (pixels in the picture) only for what the list doesn't have: a drawing, a canvas, a game \
    board. A control it lists with no name has no content description: give it one (`contentDescription`, or \
    `Modifier.semantics`). The emulator has no SIM, no real camera and no fingerprint: try everything else \
    there, and for those parts tell the user plainly that they're for their phone, never that they're broken.
    """
}
