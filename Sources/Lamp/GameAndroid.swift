import Foundation

/// A three.js game on Android: a small Android app of Lamp's own in the game's `Android/` folder, none of it the agent's,
/// which shows the game's page (`Web/`, copied into the app's assets by the build) full screen in a WebView. It serves the
/// page from the app at an address of its own (so modules and fetch work as in every other place), plays its sound with
/// no tap first, keeps its saves in the WebView's storage, and reads the controllers itself (Android's own key and
/// motion events), handing them to Lamp's runtime in the page (`lampNativePad`), since a WebView doesn't promise the
/// Gamepad API. The touch controls are the runtime's own. The build is Lamp's Android build (Gradle from Lamp's tools,
/// in the app's sandbox), and the app is installed, launched, looked at and used like any Android app of Lamp's
/// (`Store.installOnAndroid`, its package and `.MainActivity`). A C++ game isn't played on Android: the kit has no
/// host there yet, and the NDK isn't among the tools Lamp downloads.
enum GameAndroid {
    static let folder = "Android"

    static func apk(_ project: LampProject) -> URL {
        project.dir.appendingPathComponent("\(folder)/app/build/outputs/apk/debug/app-debug.apk")
    }

    /// Lamp's Android project for the game, written before every build like the rest of its files.
    static func write(for project: LampProject) throws {
        let package = Template.androidPackage(for: project)
        let kotlin = "\(folder)/app/src/main/kotlin/" + package.replacingOccurrences(of: ".", with: "/")
        try Template.write(Template.androidSettingsGradle, to: "\(folder)/settings.gradle.kts", for: project)
        try Template.write(rootBuildGradle, to: "\(folder)/build.gradle.kts", for: project)
        try Template.write(Template.androidGradleProperties, to: "\(folder)/gradle.properties", for: project)
        try Template.write(Template.androidVersionsCatalogue, to: "\(folder)/gradle/libs.versions.toml", for: project)
        try Template.write(appBuildGradle, to: "\(folder)/app/build.gradle.kts", for: project)
        try Template.write(manifest, to: "\(folder)/app/src/main/AndroidManifest.xml", for: project)
        try Template.write(mainActivity.replacingOccurrences(of: "{{PACKAGE}}", with: package), to: kotlin + "/MainActivity.kt", for: project)
    }

    /// Every path Lamp owns there, for the agent's file checks and the versions' diffs.
    static func paths(for project: LampProject) -> [String] {
        let package = Template.androidPackage(for: project).replacingOccurrences(of: ".", with: "/")
        return ["settings.gradle.kts", "build.gradle.kts", "gradle.properties", "gradle/libs.versions.toml", "app/build.gradle.kts",
                "app/src/main/AndroidManifest.xml", "app/src/main/kotlin/\(package)/MainActivity.kt"].map { "\(folder)/\($0)" }
    }

    /// build.sh's Android part: the page into the app's assets (its files only), the icon, then Gradle.
    static let buildSteps = """
    if [[ "$PLACE" == "android" ]]; then
      if [ -z "${LAMP_GRADLE:-}" ] || [ -z "${ANDROID_HOME:-}" ]; then
        echo "Android's tools aren't set up. Open the game in Lamp to download them." >&2
        exit 1
      fi
      if find Web -type l | grep -q .; then echo "Web/ holds a shortcut to another file. Put the file itself there." >&2; exit 1; fi
      mkdir -p Android/app/src/main/assets
      rsync -a --delete Web/ Android/app/src/main/assets/Web/
      # The game's icon, once Lamp has drawn it; until then the system's own for an app.
      ICON=".lamp/AppIcon-square.png"
      [ -f "$ICON" ] || ICON=/System/Library/CoreServices/CoreTypes.bundle/Contents/Resources/GenericApplicationIcon.icns
      mkdir -p Android/app/src/main/res/mipmap-xxxhdpi
      /usr/bin/sips -s format png -z 432 432 "$ICON" --out Android/app/src/main/res/mipmap-xxxhdpi/ic_launcher.png > /dev/null
      cd Android
      printf 'sdk.dir=%s\\n' "$ANDROID_HOME" > local.properties
      exec "$LAMP_GRADLE" --console=plain -q "-Dlamp.app={{SLUG}}" assembleDebug
    fi

    """

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
        // The page's files are served as they are: a compressed asset can't be streamed to the WebView.
        androidResources { noCompress += listOf("js", "html", "css", "json", "glb", "gltf", "bin", "png", "jpg", "wav", "ogg", "mp3", "m4a") }
    }

    kotlin {
        jvmToolchain(17)
    }

    """

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

    class MainActivity : Activity() {
        private lateinit var web: WebView
        // The first controller, as the page's pad 0 is: sticks -1 to 1 (up positive), triggers 0 to 1, buttons as Lamp's bits.
        private var lx = 0f; private var ly = 0f; private var rx = 0f; private var ry = 0f; private var lt = 0f; private var rt = 0f
        private var down = 0
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
                down = if (event.action == KeyEvent.ACTION_DOWN) down or b else down and b.inv()
                send()
                return true
            }
            return super.dispatchKeyEvent(event)
        }

        private fun dead(v: Float) = if (abs(v) < 0.15f) 0f else (v - Math.signum(v) * 0.15f) / 0.85f

        override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
            if (!event.isFromSource(InputDevice.SOURCE_JOYSTICK) || event.action != MotionEvent.ACTION_MOVE) return super.dispatchGenericMotionEvent(event)
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
            val now = "$lx,$ly,$rx,$ry,$lt,$rt,$down"
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
}
