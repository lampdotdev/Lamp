# Android apps

One of the guides to working on Lamp. Start from `AGENTS.md` at the top of the repository: it has the rules every change follows and the list of guides; a section named in quotes may be in another guide on that list.

An app can be made for Android (`Platform.android`, chosen by the naming call when the wish names Android, a Pixel, a
Samsung or Google Play, or by `make_app_for` with "android" alone: an Android app stands by itself, never one code
with Apple's devices). It is Kotlin and Jetpack Compose in a Gradle project in the app's folder: Lamp owns what the
build runs before the agent's code does (`build.sh`, `settings.gradle.kts`, the top-level `build.gradle.kts`,
`gradle.properties` and `gradle/libs.versions.toml`, written afresh before every build by
`Template.writeAndroidOwnedFiles`, with the versions Google's own project template pairs), and the agent owns `app/`
(its build file, manifest, Kotlin and resources; the scaffold is `Template.fillAndroid`), all but Lamp's building
blocks. Those are `LampSupport.kt` in the app's package (`Template.androidSupportKotlin`, AndroidSupport.swift, written
by `writeSupport` before every turn and build like LampSupport.swift): `LampAI` (ask with `data` fencing, pictures,
the decisions and their `each` forms), `LampStore` (values and collections as JSON on SQLite) and `LampAssets`, under
the names and with the doc comments the Swift ones have, so a change to one of those is made to both. A Lamp-owned
debug manifest beside it (`app/src/debug/AndroidManifest.xml`, merged into every build Lamp makes) adds the network
and `LampInit`, a provider that hands the blocks the app's context before any of its code runs. There are no
connectors yet, and the rules say so (`Agent.androidPrompt`, `Rules.androidAI`). How an Android app should look and behave (theme, every
screen size, navigation, components, states) is the `android-design` skill, which only its prompt offers. The app's token is never built in:
after each install Lamp writes what the app is told (`Template.androidInstallValues`: its token and the ways to the
gateway) into the app's own storage on the device, on adb's input through `run-as` (`Adb.tellApp`), so the APK in the
app's folder holds no secret. The emulator reaches the gateway at 10.0.2.2, naming this Mac as 127.0.0.1; a device
reaches it over the Wi‑Fi, by the Mac's Bonjour name or else its addresses, always naming it by that name, which is
what the gateway admits from the network, and the gateway listens there while an Android app is set to open on a
device (`Store.syncLocalNetwork`). The blocks speak HTTP on a socket, since Android's own clients refuse plain HTTP
without a change to the agent's manifest. Away from the Mac a device has no AI, and `AIStatus.line` says so. Nothing of Google's is on
a Mac by itself, so Lamp downloads what it needs the first time (`AndroidTools.install`, from the Android Setup
window, `AndroidSetup`, which the first Android request, Play and Try On open through `AndroidTools.check`): a Java
runtime, Google's command-line tools and Gradle, each checked against the checksum its maker publishes, and through
Google's own package manager the platform tools, a build-tools, the platform and the emulator with one system image.
They go in `Edition.sharedDeveloperFolder` (~/Library/Developer/Lamp), one copy for every Lamp on this Mac, which the
agent's sandbox lets a build read and never write, so what Lamp runs from there as itself (adb, the emulator) is what
Lamp put there; Gradle's cache is in `Edition.sharedCachesFolder`, which the sandbox opens for writing, and each app's
Gradle daemon is its own (`-Dlamp.app`), since one started in another app's sandbox could read nothing of this one.
The build runs build.sh in the app's sandbox like every build, with `AndroidTools.buildEnvironment`: its Android home is in the caches folder, since every debug build is signed with a key Gradle keeps there, while Lamp's own (adb's key to the person's devices, the emulators) stays in Lamp's folder. Where the
app opens is Try On's choice (`TryOnMenu.choices`): the emulator Lamp made (`Emulator`, one AVD,
`AndroidTools.avdName`, started by Lamp as itself and shown as its own window) or one of the person's Android
devices, which adb lists (`Adb.devices`, each a `Device` with its state: debugging allowed, or the next step) and which
`LampProject.device` keeps by serial (`Store.setAndroidDevice`). Play and a look install the APK with adb and start
the main activity (`Store.installOnAndroid`), with its log read into the app's log by `adb logcat` for the app's
process. A change opens where the person was: before an install replaces a running copy, Lamp has it save
its state (`Adb.saveState`, a broadcast only adb's shell may send, holding DUMP), and the new copy's activity, a
`LampActivity`, starts from it (`LampState` in LampSupport.kt), as after Android closed it in the background. The state
is used once, only across that install and into the same activity; a launch it ends at once is opened again fresh, and
a look with `reopen` always starts fresh. A look pictures the screen with `screencap`, scaled by the device's density so a pixel is a point, and reads
it as text from `uiautomator dump` (`Adb.Screen`, the same line shape as the Mac's and the iPhone's);
`use_app` taps, types, swipes and presses keys through `adb shell input` (`Adb.perform`), reading the screen again
between actions. On the emulator it happens in plain sight as on the simulator (`Handover`): its window glows, Lamp's
fingertip goes to each spot, placed by the device's screen size in the window as it is now (`Emulator.Glass`), and the
person's own click in that window takes the app back, and so does Esc where Lamp hears it (`Handover`'s `escape`: other
apps' keys reach Lamp only once it's allowed to control the computer, which driving the emulator doesn't need, so it
isn't asked for and the pill then offers Stop alone). Every input goes out only while the app is still Lamp's to use,
checked again right before each one (`Adb.perform`'s `send`, which the key that wakes a sleeping screen goes through
too), and the takeover is asked again once that check is back, since it waits on the device, so a takeover during the
fingertip's glide, a screen read or the check itself stops the rest (`AndroidHandoverTests`). A look leaves the emulator hidden, so `use_app` brings its window
back first (`Emulator.unhide`), without taking the keyboard. A device of the person's has nothing on the Mac to show it on. The chat is Lamp's panel, beside the emulator's window and following it, or on its own for a device of the person's (`ChatPanel`; no sidebar, no live reload: both are the Mac's). An Android app
is shared as a `.lampapp` of format 9 (`AndroidFiles`, SharingAndroid.swift): its `app/` whole (Kotlin, manifest,
resources, `app/build.gradle.kts`), without `app/build`, hidden folders, `local.properties` or Lamp's own Gradle files,
and `platform` "android" in `lamp-app.json`. The Mac that opens it writes Lamp's Gradle files and renames the code to
its own package for the app (`Template.androidPackage`), which Lamp installs and launches it by. The review reads its
manifests' `uses-permission` lines (INTERNET is going online, the rest said in plain words) and the libraries its build
files bring in beyond Lamp's catalogue. Converting to or from Android is a rewrite in the other
language: `convert` puts the new kind's scaffold beside the old code and tells the agent to write the app again and
delete the rest.

**Android TV** (`Platform.androidTV`, "android-tv", Targets/AndroidTVTarget.swift) is an Android app made for a Google
TV, Android TV or Fire TV: the same Gradle project and building blocks, with a mark of its own (`.lamp-android-tv`,
`recipe.refines` Android), a TV's manifest (the leanback launcher, no touch screen required, a banner) and Compose for
TV (`androidx.tv:tv-material`, in Lamp's catalogue), and rules for the remote and the room (`Rules.androidTVDesign`,
`androidTVTry`) in place of the phone's design skill. The banner (`lamp_banner.png`, 320x180) is drawn by Lamp from the
app's icon before every build, the tile alone until there is one (`writeAndroidTVOwnedFiles`, `DeviceSupport.iconPNG`).
The naming call reads a device that's a TV (it has the `android.software.leanback` feature: `Device.from(adb:)` gives
it the "tv" feature) as "android-tv". It opens where Android TV does (`Destination.androidTV`), in Lamp's TV emulator (`Emulator.Kind.tv`, "Lamp TV", a 1080p
TV made from the Android TV system image the first time one is wanted: `Emulator.prepareTV`), which runs beside the
phone on ports of its own (`Edition.androidPorts`, `Emulator.Kind.serial`), so a screen open in both stays open in
each; `Destination.emulator` says which one an app opens in, and Stop closes it there even when Lamp didn't open it. A
game or a screen given Android TV opens there too, in Lamp's Android app around its page ("Pages and their hosts" in
the devices guide), and Try On lists the TV emulator and the person's TVs apart from the phone and the phones. `use_app` presses the
remote's keys (select, menu and play beside the arrows, back and home). A TV has no cable to the Mac, so Try On's
Connect Over Wi‑Fi… (`AndroidWiFi`) pairs and connects adb over the network: Android 11 and later's wireless debugging,
found by adb's own search (`Adb.networkServices`, `adb mdns services`), pairs with the code the TV shows (`Adb.pair`,
the code on adb's input) and connects on the port it offers; a Fire TV or an older device connects on 5555 and asks on
its screen to allow this Mac. Phones can connect the same way. Android TV apps can't be shared as a file yet.
