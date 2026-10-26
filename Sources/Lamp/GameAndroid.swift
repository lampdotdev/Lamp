import Foundation

/// A three.js game on Android: a small Android app of Lamp's own in the game's `Lamp/Android` folder, none of it the agent's
/// (never a folder of its own at the top, where Lamp would take it for another app of the wish's: `Parts.folders`),
/// which shows the game's page (`Web/`, copied into the app's assets by the build) full screen in a WebView. It serves the
/// page from the app at an address of its own (so modules and fetch work as in every other place), plays its sound with
/// no tap first, keeps its saves in the WebView's storage, and reads the controllers itself (Android's own key and
/// motion events), handing them to Lamp's runtime in the page (`lampNativePad`), since a WebView doesn't promise the
/// Gamepad API. The touch controls are the runtime's own. The build is Lamp's Android build (Gradle from Lamp's tools,
/// in the app's sandbox), and the app is installed, launched, looked at and used like any Android app of Lamp's
/// (`Store.installOnAndroid`, its package and `.MainActivity`).
enum GameAndroid {
    static let folder = "Lamp/Android"

    static func apk(_ project: LampProject) -> URL {
        project.dir.appendingPathComponent("\(folder)/app/build/outputs/apk/debug/app-debug.apk")
    }

    /// Lamp's Android project for the game, written before every build like the rest of its files. A game with other
    /// apps in its wish is one of the wish's peers here as on the Mac: the app carries Lamp's Kotlin building blocks
    /// (`LampWish` among them, `Template.androidSupportKotlin`), with what they need to build and run (Compose and the rest
    /// of an Android app's libraries, and Lamp's debug manifest: the network and the provider that hands them the app's
    /// context), and answers the page's `Lamp.wish` with them (`pageWish`). A game on its own has none of it.
    static func write(for project: LampProject) throws {
        let package = Template.androidPackage(for: project)
        let kotlin = "\(folder)/app/src/main/kotlin/" + package.replacingOccurrences(of: ".", with: "/")
        let talks = Template.talksToOtherApps(project)
        try Template.write(Template.androidSettingsGradle, to: "\(folder)/settings.gradle.kts", for: project)
        try Template.write(talks ? Template.androidRootBuildGradle : rootBuildGradle, to: "\(folder)/build.gradle.kts", for: project)
        try Template.write(Template.androidGradleProperties, to: "\(folder)/gradle.properties", for: project)
        try Template.write(Template.androidVersionsCatalogue, to: "\(folder)/gradle/libs.versions.toml", for: project)
        try Template.write(talks ? wishBuildGradle : appBuildGradle, to: "\(folder)/app/build.gradle.kts", for: project)
        try Template.write(manifest, to: "\(folder)/app/src/main/AndroidManifest.xml", for: project)
        try Template.write((talks ? mainActivity : withoutWish(activity: mainActivity)).replacingOccurrences(of: "{{PACKAGE}}", with: package),
                           to: kotlin + "/MainActivity.kt", for: project)
        try Template.write(".gradle/\n.kotlin/\nlocal.properties\n", to: "\(folder)/.gitignore", for: project)
        let wish = [(kotlin + "/" + Template.androidSupportFile, Template.androidSupportKotlin(for: project)),
                    (kotlin + "/LampPageWish.kt", pageWish),
                    ("\(folder)/" + Template.androidDebugManifest, Template.androidDebugManifestXML)]
        for (path, text) in wish {
            let url = project.dir.appendingPathComponent(path)
            if talks { try Template.put(text.replacingOccurrences(of: "{{PACKAGE}}", with: package), at: url, for: project) }
            else if FileManager.default.fileExists(atPath: url.path) { AppFolder.remove(url, in: project.dir) }
        }
    }

    /// Every path Lamp owns there, for the agent's file checks and the versions' diffs.
    static func paths(for project: LampProject) -> [String] {
        let package = Template.androidPackage(for: project).replacingOccurrences(of: ".", with: "/")
        return [".gitignore", "settings.gradle.kts", "build.gradle.kts", "gradle.properties", "gradle/libs.versions.toml", "app/build.gradle.kts",
                "app/src/main/AndroidManifest.xml", "app/src/main/kotlin/\(package)/MainActivity.kt",
                "app/src/main/kotlin/\(package)/\(Template.androidSupportFile)", "app/src/main/kotlin/\(package)/LampPageWish.kt",
                Template.androidDebugManifest].map { "\(folder)/\($0)" }
    }

    /// The game's activity for a game on its own: without the lines that answer the page's `Lamp.wish`, each marked so.
    static func withoutWish(activity: String) -> String {
        activity.components(separatedBy: "\n").filter { !$0.hasSuffix("// the wish's other apps") }.joined(separator: "\n")
    }

    /// build.sh's Android part: the page into the game's build/ (which no version keeps), its files only, the icon,
    /// then Gradle.
    static func buildSteps() -> String {
        """
        if [[ "$PLACE" == "android" ]]; then
          if [ -z "${LAMP_GRADLE:-}" ] || [ -z "${ANDROID_HOME:-}" ]; then
            echo "Android's tools aren't set up. Open the game in Lamp to download them." >&2
            exit 1
          fi
          stage_page build/android-assets/Web
          # The game's icon, once Lamp has drawn it; until then the system's own for an app.
          ICON=".lamp/AppIcon-square.png"
          [ -f "$ICON" ] || ICON=/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns
          mkdir -p build/android-res/mipmap-xxxhdpi
          /usr/bin/sips -s format png -z 432 432 "$ICON" --out build/android-res/mipmap-xxxhdpi/ic_launcher.png > /dev/null
          cd Lamp/Android
          printf 'sdk.dir=%s\\n' "$ANDROID_HOME" > local.properties
          exec "$LAMP_GRADLE" --console=plain -q "-Dlamp.app={{SLUG}}" assembleDebug
        fi

        """
    }

    static let rootBuildGradle = """
    // Written by Lamp before every build; don't edit.
    plugins {
        alias(libs.plugins.android.application) apply false
    }

    """

    static let appBuildGradle = """
    // Written by Lamp before every build; don't edit.
    plugins {
        alias(libs.plugins.android.application)
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
        buildFeatures { buildConfig = false }
        sourceSets["main"].kotlin.srcDirs("src/main/kotlin")
        // The page and the icon, which build.sh puts in the game's build/ before Gradle runs.
        sourceSets["main"].assets.srcDirs("../../../build/android-assets")
        sourceSets["main"].res.srcDirs("../../../build/android-res")
        // The page's files are served as they are: a compressed asset can't be streamed to the WebView.
        androidResources { noCompress += listOf("js", "html", "css", "json", "glb", "gltf", "bin", "png", "jpg", "wav", "ogg", "mp3", "m4a") }
    }

    kotlin {
        jvmToolchain(17)
    }

    """

    /// The build of a game with other apps in its wish: an Android app's plugins and libraries, which Lamp's Kotlin
    /// building blocks are written against, and AndroidX's WebKit, whose message listener lets only the game's own page
    /// in its main frame reach `LampWish`.
    static let wishBuildGradle = appBuildGradle
        .replacingOccurrences(of: """
            alias(libs.plugins.android.application)
        }
        """, with: """
            alias(libs.plugins.android.application)
            alias(libs.plugins.compose.compiler)
            alias(libs.plugins.kotlin.serialization)
        }
        """)
        .replacingOccurrences(of: "buildFeatures { buildConfig = false }", with: "buildFeatures {\n        compose = true\n        buildConfig = false\n    }")
        .replacingOccurrences(of: """
        kotlin {
            jvmToolchain(17)
        }
        """, with: """
        kotlin {
            jvmToolchain(17)
        }

        dependencies {
            val composeBom = platform(libs.androidx.compose.bom)
            implementation(composeBom)
            implementation(libs.androidx.core.ktx)
            implementation(libs.androidx.lifecycle.runtime.ktx)
            implementation(libs.androidx.activity.compose)
            implementation(libs.androidx.compose.ui)
            implementation(libs.androidx.compose.material3)
            implementation(libs.kotlinx.coroutines.android)
            implementation(libs.kotlinx.serialization.json)
            implementation(libs.androidx.webkit)
        }
        """)

    static let manifest = """
    <?xml version="1.0" encoding="utf-8"?>
    <!-- Written by Lamp before every build; don't edit. -->
    <manifest xmlns:android="http://schemas.android.com/apk/res/android">
        <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
        <uses-feature android:name="android.hardware.gamepad" android:required="false" />
        <application
            android:allowBackup="true"
            android:icon="@mipmap/ic_launcher"
            android:label="{{NAME}}"
            android:hardwareAccelerated="true"
            android:isGame="true"
            android:theme="@android:style/Theme.Black.NoTitleBar.Fullscreen">
            <activity
                android:name=".MainActivity"
                android:exported="true"
                android:screenOrientation="sensorLandscape"
                android:configChanges="orientation|screenSize|screenLayout|keyboard|keyboardHidden|navigation|uiMode">
                <intent-filter>
                    <action android:name="android.intent.action.MAIN" />
                    <category android:name="android.intent.category.LAUNCHER" />
                </intent-filter>
            </activity>
        </application>
    </manifest>

    """

    static let mainActivity = #"""
    // Written by Lamp before every build; don't edit. The game is the page in Web/.
    package {{PACKAGE}}

    import android.annotation.SuppressLint
    import android.app.Activity
    import android.hardware.input.InputManager
    import android.os.Bundle
    import android.util.Log
    import android.view.InputDevice
    import android.view.KeyEvent
    import android.view.MotionEvent
    import android.view.View
    import android.view.WindowInsets
    import android.view.WindowInsetsController
    import android.webkit.ConsoleMessage
    import android.webkit.WebChromeClient
    import android.webkit.WebResourceRequest
    import android.webkit.WebResourceResponse
    import android.webkit.WebView
    import android.webkit.WebViewClient
    import kotlin.math.abs

    class MainActivity : Activity(), InputManager.InputDeviceListener {
        private lateinit var web: WebView
        // The first controller, as the page's pad 0 is: sticks -1 to 1 (up positive), triggers 0 to 1, buttons as Lamp's bits.
        private var lx = 0f; private var ly = 0f; private var rx = 0f; private var ry = 0f; private var lt = 0f; private var rt = 0f
        private var down = 0
        // The controller's USB vendor, so the page names its buttons as they're marked (a PlayStation's shapes).
        private var vendor = 0
        private var sent = ""

        @SuppressLint("SetJavaScriptEnabled")
        override fun onCreate(saved: Bundle?) {
            super.onCreate(saved)
            web = WebView(this)
            web.setBackgroundColor(0xFF000000.toInt())
            web.settings.javaScriptEnabled = true
            web.settings.domStorageEnabled = true
            web.settings.mediaPlaybackRequiresUserGesture = false
            web.settings.allowFileAccess = false
            web.webViewClient = object : WebViewClient() {
                // The page's files, from the app's own assets, at an address of the game's own.
                override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? {
                    val url = request.url
                    if (url.host != HOST) return null
                    val path = (url.path ?: "/").trimStart('/').ifEmpty { "index.html" }
                    if (path.split('/').any { it == ".." }) return notFound()
                    return try {
                        WebResourceResponse(type(path), "utf-8", assets.open("Web/$path"))
                    } catch (e: Exception) { notFound() }
                }
                override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.host != HOST
            }
            web.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    Log.i("Lamp", message.message())
                    return true
                }
            }
            setContentView(web)
            LampPageWish.attach(web, "https://$HOST") // the wish's other apps
            (getSystemService(INPUT_SERVICE) as InputManager).registerInputDeviceListener(this, null)
            immerse()
            web.loadUrl("https://$HOST/index.html")
        }

        override fun onWindowFocusChanged(focused: Boolean) {
            super.onWindowFocusChanged(focused)
            if (focused) immerse()
        }

        private fun immerse() {
            if (android.os.Build.VERSION.SDK_INT >= 30) {
                window.insetsController?.let {
                    it.hide(WindowInsets.Type.systemBars())
                    it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            }
        }

        override fun onPause() { super.onPause(); web.onPause() }

        // A controller that goes away mid-press leaves nothing held: the page sees it let go, and its touch controls
        // can come back.
        override fun onInputDeviceRemoved(id: Int) {
            lx = 0f; ly = 0f; rx = 0f; ry = 0f; lt = 0f; rt = 0f; down = 0
            send()
        }
        override fun onInputDeviceAdded(id: Int) {}
        override fun onInputDeviceChanged(id: Int) {}
        override fun onDestroy() {
            (getSystemService(INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(this)
            LampPageWish.detach(web) // the wish's other apps
            super.onDestroy()
        }
        override fun onResume() { super.onResume(); web.onResume() }

        // MARK: The controller

        private fun bit(code: Int): Int = when (code) {
            KeyEvent.KEYCODE_BUTTON_A -> 1; KeyEvent.KEYCODE_BUTTON_B -> 2; KeyEvent.KEYCODE_BUTTON_X -> 4; KeyEvent.KEYCODE_BUTTON_Y -> 8
            KeyEvent.KEYCODE_BUTTON_L1 -> 16; KeyEvent.KEYCODE_BUTTON_R1 -> 32
            KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> 64; KeyEvent.KEYCODE_BUTTON_SELECT -> 128
            KeyEvent.KEYCODE_DPAD_UP -> 256; KeyEvent.KEYCODE_DPAD_DOWN -> 512; KeyEvent.KEYCODE_DPAD_LEFT -> 1024; KeyEvent.KEYCODE_DPAD_RIGHT -> 2048
            KeyEvent.KEYCODE_BUTTON_THUMBL -> 4096; KeyEvent.KEYCODE_BUTTON_THUMBR -> 8192
            else -> 0
        }

        private fun fromController(event: KeyEvent) =
            event.isFromSource(InputDevice.SOURCE_GAMEPAD) || event.isFromSource(InputDevice.SOURCE_JOYSTICK) || KeyEvent.isGamepadButton(event.keyCode)

        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            // Back is the game's B, as on a console: the game says what going back means, and stays open.
            val code = if (event.keyCode == KeyEvent.KEYCODE_BACK) KeyEvent.KEYCODE_BUTTON_B else event.keyCode
            val b = bit(code)
            if (b != 0 && (fromController(event) || event.keyCode == KeyEvent.KEYCODE_BACK)) {
                if (fromController(event)) vendor = event.device?.vendorId ?: 0
                down = if (event.action == KeyEvent.ACTION_DOWN) down or b else down and b.inv()
                send()
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        private fun dead(v: Float) = if (abs(v) < 0.15f) 0f else (v - Math.signum(v) * 0.15f) / 0.85f

        override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
            if (!event.isFromSource(InputDevice.SOURCE_JOYSTICK) || event.action != MotionEvent.ACTION_MOVE) return super.dispatchGenericMotionEvent(event)
            vendor = event.device?.vendorId ?: 0
            lx = dead(event.getAxisValue(MotionEvent.AXIS_X)); ly = -dead(event.getAxisValue(MotionEvent.AXIS_Y))
            rx = dead(event.getAxisValue(MotionEvent.AXIS_Z)); ry = -dead(event.getAxisValue(MotionEvent.AXIS_RZ))
            lt = maxOf(event.getAxisValue(MotionEvent.AXIS_LTRIGGER), event.getAxisValue(MotionEvent.AXIS_BRAKE))
            rt = maxOf(event.getAxisValue(MotionEvent.AXIS_RTRIGGER), event.getAxisValue(MotionEvent.AXIS_GAS))
            // A d-pad that reports as a hat.
            val hx = event.getAxisValue(MotionEvent.AXIS_HAT_X); val hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            down = down and (256 or 512 or 1024 or 2048).inv() or
                (if (hy < -0.5f) 256 else 0) or (if (hy > 0.5f) 512 else 0) or (if (hx < -0.5f) 1024 else 0) or (if (hx > 0.5f) 2048 else 0)
            send()
            return true
        }

        private fun send() {
            val now = "$lx,$ly,$rx,$ry,$lt,$rt,$down,$vendor"
            if (now == sent) return
            sent = now
            web.evaluateJavascript("window.lampNativePad&&lampNativePad($now)", null)
        }

        private fun type(path: String) = when (path.substringAfterLast('.', "").lowercase()) {
            "html", "htm" -> "text/html"; "js", "mjs" -> "text/javascript"; "css" -> "text/css"; "json" -> "application/json"
            "png" -> "image/png"; "jpg", "jpeg" -> "image/jpeg"; "webp" -> "image/webp"; "svg" -> "image/svg+xml"
            "glb" -> "model/gltf-binary"; "gltf" -> "model/gltf+json"; "wav" -> "audio/wav"; "ogg" -> "audio/ogg"
            "mp3" -> "audio/mpeg"; "m4a" -> "audio/mp4"; "wasm" -> "application/wasm"
            else -> "application/octet-stream"
        }

        private fun notFound() = WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), "".byteInputStream())

        companion object { const val HOST = "lamp.game" }
    }

    """#

    /// The page's `Lamp.wish` (Web/lamp.js), answered by the app's own `LampWish` (LampSupport.kt), as `LampPageWish` in
    /// LampPage.swift answers it on the Mac: the app is the wish's peer (it listens, is found, keeps the values on the
    /// device, so it goes on with Lamp closed), and the page mirrors it. Only the game's own page, in its main frame, is
    /// heard (AndroidX WebKit's message listener, by origin), and what the app hears goes to the page's `window.__lampWish`.
    static let pageWish = #"""
    // Written by Lamp before every build; don't edit. The page's Lamp.wish (Web/lamp.js), answered by this app's own
    // LampWish (LampSupport.kt): the app is the wish's peer, and the page mirrors it.
    package {{PACKAGE}}

    import android.util.Base64
    import android.webkit.WebView
    import androidx.webkit.WebViewCompat
    import androidx.webkit.WebViewFeature
    import java.lang.ref.WeakReference
    import kotlinx.coroutines.Job
    import kotlinx.coroutines.MainScope
    import kotlinx.coroutines.cancel
    import kotlinx.coroutines.flow.StateFlow
    import kotlinx.coroutines.flow.combine
    import kotlinx.coroutines.launch
    import org.json.JSONArray
    import org.json.JSONObject
    import org.json.JSONTokener

    /** One activity's page. It lives as long as its activity (`detach` in onDestroy) and holds the page's web view only
     *  weakly: LampWish's handlers are the whole app's, so they reach the page of the activity open now, never one
     *  that's gone. */
    class LampPageWish private constructor(web: WebView) {
        private val page = WeakReference(web)
        private val scope = MainScope()
        private val transfers = mutableMapOf<Int, LampTransfer>()
        private val watching = mutableMapOf<Int, Job>()
        // LampWish's flows, taken once: their getters join the wish, so reading them to report a stop would undo it.
        private var apps: StateFlow<List<LampWish.Peer>>? = null
        private var status: StateFlow<LampWish.Status>? = null
        private var values: StateFlow<Map<String, Any>>? = null

        private fun heard(text: String) {
            val call = try { JSONObject(text) } catch (e: Exception) { return }
            when (call.optString("op")) {
                "start" -> {
                    listen()
                    LampWish.start()
                    tellState()
                    tellValues(JSONArray())
                }
                "stop" -> LampWish.stop()
                "send" -> {
                    val data = json(call.optString("data")) ?: return
                    LampWish.send(if (data == JSONObject.NULL) null else data, if (call.isNull("to")) null else call.optString("to"))
                }
                "set" -> {
                    if (call.isNull("key")) return
                    val value = json(call.optString("value"))
                    LampWish.set(call.optString("key"), if (value == null || value == JSONObject.NULL) null else value)
                }
                "files" -> hearFiles()
                "sendFile" -> {
                    val id = call.optInt("id")
                    val bytes = try { Base64.decode(call.optString("data"), Base64.DEFAULT) } catch (e: Exception) { return }
                    val transfer = LampWish.sendFile(bytes, call.optString("name", "file"), call.optString("type", "application/octet-stream"), call.optString("to"))
                    transfers[id] = transfer
                    watching[id] = scope.launch { transfer.sent.combine(transfer.state) { _, _ -> }.collect { tellTransfer(id) } }
                }
                "cancel" -> transfers[call.optInt("id")]?.cancel()
            }
        }

        private fun listen() {
            if (apps != null) return
            val apps = LampWish.apps.also { this.apps = it }
            val status = LampWish.status.also { this.status = it }
            values = LampWish.values
            hearWish()
            // Who is open and how this app's link stands, as each changes.
            scope.launch { apps.combine(status) { _, _ -> }.collect { tellState() } }
        }

        private fun tellState() {
            val apps = apps?.value ?: return
            val status = status?.value ?: return
            val list = JSONArray()
            for (peer in apps) {
                list.put(JSONObject().put("peer", peer.peer).put("kind", peer.kind).put("name", peer.name).put("device", peer.device)
                    .put("open", peer.isOpen).put("status", JSONObject().put("state", peer.status.state.name).put("reason", peer.status.reason)
                        .put("lastSeen", peer.status.lastSeen ?: JSONObject.NULL)))
            }
            tell(JSONObject().put("t", "state").put("me", LampWish.me).put("apps", list)
                .put("status", JSONObject().put("state", status.state.name).put("reason", status.reason)))
        }

        private fun tellValues(changed: JSONArray) {
            val now = values?.value ?: return
            val json = JSONObject()
            for ((key, value) in now) json.put(key, value)
            tell(JSONObject().put("t", "values").put("values", json).put("changed", changed))
        }

        private fun tellTransfer(id: Int) {
            val transfer = transfers[id] ?: return
            val said = JSONObject().put("t", "transfer").put("id", id).put("sent", transfer.sent.value)
            when (val state = transfer.state.value) {
                is LampTransfer.State.Failed -> said.put("state", "failed").put("error", state.reason)
                LampTransfer.State.Done -> said.put("state", "done")
                else -> said.put("state", "sending")
            }
            if (transfer.state.value != LampTransfer.State.Sending) {
                transfers.remove(id)
                watching.remove(id)?.cancel()
            }
            tell(said)
        }

        private fun tell(message: JSONObject) {
            val web = page.get() ?: return
            val script = "window.__lampWish && window.__lampWish(" + message.toString() + ")"
            web.post { web.evaluateJavascript(script, null) }
        }

        private fun json(text: String): Any? = try { JSONTokener(text).nextValue() } catch (e: Exception) { null }

        private fun close() {
            scope.cancel()
            transfers.clear()
            watching.clear()
            if (current?.get() === this) current = null
        }

        companion object {
            /** The page of the activity open now. */
            private var current: WeakReference<LampPageWish>? = null
            private var heardWish = false
            private var heardFiles = false

            /** Answers the page at `origin`, the game's own, in its main frame: no other page or frame reaches the wish. */
            fun attach(web: WebView, origin: String) {
                if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
                val bridge = LampPageWish(web)
                current = WeakReference(bridge)
                WebViewCompat.addWebMessageListener(web, "lampWishHost", setOf(origin)) { _, message, _, isMainFrame, _ ->
                    if (isMainFrame) message.data?.let { bridge.heard(it) }
                }
            }

            /** The activity is going: its page hears nothing more, and nothing here keeps it. */
            fun detach(web: WebView) {
                val bridge = current?.get()
                if (bridge != null && bridge.page.get() === web) bridge.close()
                if (WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) WebViewCompat.removeWebMessageListener(web, "lampWishHost")
            }

            // LampWish's handlers can't be taken back, so each is given once for the whole app, and passes on to the page
            // open now.
            private fun hearWish() {
                if (heardWish) return
                heardWish = true
                LampWish.onMessage { from, data ->
                    current?.get()?.tell(JSONObject().put("t", "message").put("from", from).put("data", data ?: JSONObject.NULL))
                }
                // Who made each change; the page says to its onChange every value that differs from its copy.
                LampWish.onChange { key, value, from ->
                    current?.get()?.tellValues(JSONArray().put(JSONObject().put("key", key).put("value", value ?: JSONObject.NULL).put("from", from)))
                }
            }

            private fun hearFiles() {
                if (heardFiles) return
                heardFiles = true
                LampWish.onFile { from, file ->
                    current?.get()?.tell(JSONObject().put("t", "file").put("from", from).put("name", file.name).put("type", file.type)
                        .put("data", Base64.encodeToString(file.bytes, Base64.NO_WRAP)))
                }
            }
        }
    }

    """#
}
