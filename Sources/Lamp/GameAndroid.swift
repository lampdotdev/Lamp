import Foundation

/// A three.js game on Android: a small Android app of Lamp's own in the game's `Lamp/Android` folder, none of it the agent's
/// (never a folder of its own at the top, where Lamp would take it for another app of the wish's: `Parts.folders`),
/// which shows the game's page (`Web/`, copied into the app's assets by the build) full screen in a WebView. It serves the
/// page from the app at an address of its own (so modules and fetch work as in every other place), plays its sound with
/// no tap first, keeps its saves in the WebView's storage, and reads the controllers itself (Android's own key and
/// motion events), handing them to Lamp's runtime in the page (`lampNativePad`), since a WebView doesn't promise the
/// Gamepad API. The touch controls are the runtime's own. The build is Lamp's Android build (Gradle from Lamp's tools,
/// in the app's sandbox), and the app is installed, launched, looked at and used like any Android app of Lamp's
/// (`Store.installOnAndroid`, its package and `.MainActivity`). A C++ game's app is the same around a SurfaceView
/// instead, drawn by the kit's Android host (`lamp_android.cpp`, built with the NDK into `libgame.so`), with the touch
/// controls drawn natively over it.
enum GameAndroid {
    static let folder = "Lamp/Android"

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
        let native = GameKit.engine(project) == .native
        try Template.write((native ? nativeActivity : mainActivity).replacingOccurrences(of: "{{PACKAGE}}", with: package),
                           to: kotlin + "/MainActivity.kt", for: project)
        let bridge = project.dir.appendingPathComponent("\(folder)/app/src/main/kotlin/dev/lamp/game/Native.kt")
        if native { try Template.write(nativeBridge, to: "\(folder)/app/src/main/kotlin/dev/lamp/game/Native.kt", for: project) }
        else { AppFolder.remove(bridge, in: project.dir) }
        try Template.write(".gradle/\n.kotlin/\nlocal.properties\n", to: "\(folder)/.gitignore", for: project)
    }

    /// Every path Lamp owns there, for the agent's file checks and the versions' diffs.
    static func paths(for project: LampProject) -> [String] {
        let package = Template.androidPackage(for: project).replacingOccurrences(of: ".", with: "/")
        return [".gitignore", "settings.gradle.kts", "build.gradle.kts", "gradle.properties", "gradle/libs.versions.toml", "app/build.gradle.kts",
                "app/src/main/AndroidManifest.xml", "app/src/main/kotlin/\(package)/MainActivity.kt",
                "app/src/main/kotlin/dev/lamp/game/Native.kt"].map { "\(folder)/\($0)" }
    }

    /// build.sh's Android part: what the app shows into the game's build/ (which no version keeps), its files only (a
    /// three.js game's page, a C++ game's library for each kind of processor and its Assets/), the icon, then Gradle.
    static func buildSteps(_ engine: GameKit.Engine) -> String {
        let content = engine == .web ? """
          if find Web -type l | grep -q .; then echo "Web/ holds a shortcut to another file. Put the file itself there." >&2; exit 1; fi
          mkdir -p build/android-assets
          rsync -a --delete Web/ build/android-assets/Web/
          rm -rf build/android-jni
        """ : """
          if [ -z "${ANDROID_NDK:-}" ]; then echo "Android's tools for games in C++ aren't here. Open the game in Lamp to get them." >&2; exit 1; fi
          sh Lamp/build.sh android
          if [ -d Assets ] && find Assets -type l | grep -q .; then echo "Assets/ holds a shortcut to another file. Put the file itself there." >&2; exit 1; fi
          mkdir -p build/android-assets/Assets
          rsync -a --delete --exclude '.*' Assets/ build/android-assets/Assets/ 2>/dev/null || true
        """
        return """
        if [[ "$PLACE" == "android" ]]; then
          if [ -z "${LAMP_GRADLE:-}" ] || [ -z "${ANDROID_HOME:-}" ]; then
            echo "Android's tools aren't set up. Open the game in Lamp to download them." >&2
            exit 1
          fi
        \(content)
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
        // A C++ game's host and game, built with the NDK for each kind of processor.
        sourceSets["main"].jniLibs.srcDirs("../../../build/android-jni")
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

    /// The bridge to a C++ game's host (`lamp_android.cpp`), in a package of its own so the host's names are the same in
    /// every game.
    static let nativeBridge = #"""
    // Written by Lamp before every build; don't edit. The game's host, in libgame.so (Lamp/lamp_android.cpp).
    package dev.lamp.game

    import android.content.res.AssetManager
    import android.view.Surface

    object Native {
        init { System.loadLibrary("game") }
        @JvmStatic external fun start(assets: AssetManager, saves: String)
        @JvmStatic external fun surface(surface: Surface?)
        @JvmStatic external fun pad(index: Int, connected: Boolean, lx: Float, ly: Float, rx: Float, ry: Float, lt: Float, rt: Float, down: Int, tapped: Int)
        @JvmStatic external fun touchButtons(): Int
        @JvmStatic external fun rumble(index: Int): Int
        @JvmStatic external fun pause(paused: Boolean)
    }

    """#

    /// A C++ game's activity: the host's surface at the game's 16:9, black around it, the touch controls over it, and
    /// the controllers read here and handed to the host by player.
    static let nativeActivity = #"""
    // Written by Lamp before every build; don't edit. The game is the C++ in Game/, drawn by Lamp/lamp_android.cpp.
    package {{PACKAGE}}

    import android.app.Activity
    import android.content.Context
    import android.graphics.Canvas
    import android.graphics.Color
    import android.graphics.Paint
    import android.graphics.Typeface
    import android.hardware.input.InputManager
    import android.os.Build
    import android.os.Bundle
    import android.os.Handler
    import android.os.Looper
    import android.os.VibrationEffect
    import android.view.Gravity
    import android.view.InputDevice
    import android.view.KeyEvent
    import android.view.MotionEvent
    import android.view.SurfaceHolder
    import android.view.SurfaceView
    import android.view.View
    import android.view.WindowInsets
    import android.view.WindowInsetsController
    import android.widget.FrameLayout
    import dev.lamp.game.Native
    import kotlin.math.abs
    import kotlin.math.hypot
    import kotlin.math.min

    class MainActivity : Activity(), InputManager.InputDeviceListener {
        /// One controller's state, by the device that's playing it.
        class Pad { var lx = 0f; var ly = 0f; var rx = 0f; var ry = 0f; var lt = 0f; var rt = 0f; var down = 0 }
        private val pads = LinkedHashMap<Int, Pad>()   // device id → pad, in the order they were first played
        private lateinit var touch: TouchControls
        private val ticks = Handler(Looper.getMainLooper())

        override fun onCreate(saved: Bundle?) {
            super.onCreate(saved)
            val root = object : FrameLayout(this) {
                // The surface at the game's 16:9, as large as fits.
                override fun onLayout(changed: Boolean, l: Int, t: Int, r: Int, b: Int) {
                    val w = r - l; val h = b - t
                    val scale = min(w / 1920f, h / 1080f)
                    val sw = (1920 * scale).toInt(); val sh = (1080 * scale).toInt()
                    val x = (w - sw) / 2; val y = (h - sh) / 2
                    getChildAt(0).layout(x, y, x + sw, y + sh)
                    getChildAt(1).layout(0, 0, w, h)
                }
            }
            root.setBackgroundColor(Color.BLACK)
            val surface = SurfaceView(this)
            surface.holder.addCallback(object : SurfaceHolder.Callback {
                override fun surfaceCreated(holder: SurfaceHolder) = Native.surface(holder.surface)
                override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Native.surface(holder.surface)
                override fun surfaceDestroyed(holder: SurfaceHolder) = Native.surface(null)
            })
            touch = TouchControls(this) { send() }
            root.addView(surface)
            root.addView(touch)
            setContentView(root)
            Native.start(assets, filesDir.absolutePath)
            (getSystemService(INPUT_SERVICE) as InputManager).registerInputDeviceListener(this, null)
            immerse()
            send()
            ticks.post(object : Runnable {
                override fun run() { rumble(); touch.buttons = Native.touchButtons(); ticks.postDelayed(this, 50) }
            })
        }

        override fun onWindowFocusChanged(focused: Boolean) { super.onWindowFocusChanged(focused); if (focused) immerse() }
        override fun onPause() { super.onPause(); Native.pause(true) }
        // A copy of the activity that's gone (Android makes another for a change it doesn't hand over) neither polls nor
        // hears controllers any more: the game has one activity's input at a time.
        override fun onDestroy() {
            ticks.removeCallbacksAndMessages(null)
            (getSystemService(INPUT_SERVICE) as InputManager).unregisterInputDeviceListener(this)
            super.onDestroy()
        }
        override fun onResume() { super.onResume(); Native.pause(false) }

        private fun immerse() {
            if (Build.VERSION.SDK_INT >= 30) {
                window.insetsController?.let {
                    it.hide(WindowInsets.Type.systemBars())
                    it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
                }
            } else {
                @Suppress("DEPRECATION")
                window.decorView.systemUiVisibility = View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY or View.SYSTEM_UI_FLAG_FULLSCREEN or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
            }
        }

        // MARK: The controllers

        private fun bit(code: Int): Int = when (code) {
            KeyEvent.KEYCODE_BUTTON_A -> 1; KeyEvent.KEYCODE_BUTTON_B -> 2; KeyEvent.KEYCODE_BUTTON_X -> 4; KeyEvent.KEYCODE_BUTTON_Y -> 8
            KeyEvent.KEYCODE_BUTTON_L1 -> 16; KeyEvent.KEYCODE_BUTTON_R1 -> 32
            KeyEvent.KEYCODE_BUTTON_START, KeyEvent.KEYCODE_MENU -> 64; KeyEvent.KEYCODE_BUTTON_SELECT -> 128
            KeyEvent.KEYCODE_DPAD_UP -> 256; KeyEvent.KEYCODE_DPAD_DOWN -> 512; KeyEvent.KEYCODE_DPAD_LEFT -> 1024; KeyEvent.KEYCODE_DPAD_RIGHT -> 2048
            KeyEvent.KEYCODE_BUTTON_THUMBL -> 4096; KeyEvent.KEYCODE_BUTTON_THUMBR -> 8192
            else -> 0
        }

        private fun pad(device: Int): Pad = pads.getOrPut(device) { Pad() }

        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            val back = event.keyCode == KeyEvent.KEYCODE_BACK
            val fromController = event.isFromSource(InputDevice.SOURCE_GAMEPAD) || event.isFromSource(InputDevice.SOURCE_JOYSTICK) || KeyEvent.isGamepadButton(event.keyCode)
            // Back is the game's B, as on a console: the game says what going back means, and stays open.
            val b = bit(if (back) KeyEvent.KEYCODE_BUTTON_B else event.keyCode)
            if (b == 0 || !(fromController || back)) return super.dispatchKeyEvent(event)
            if (back && !fromController) {
                if (event.action == KeyEvent.ACTION_DOWN) touch.tap(b)
            } else {
                val p = pad(event.deviceId)
                p.down = if (event.action == KeyEvent.ACTION_DOWN) p.down or b else p.down and b.inv()
                if (event.action == KeyEvent.ACTION_DOWN) touch.controllerUsed()
            }
            send()
            return true
        }

        private fun dead(v: Float) = if (abs(v) < 0.15f) 0f else (v - Math.signum(v) * 0.15f) / 0.85f

        override fun dispatchGenericMotionEvent(event: MotionEvent): Boolean {
            if (!event.isFromSource(InputDevice.SOURCE_JOYSTICK) || event.action != MotionEvent.ACTION_MOVE) return super.dispatchGenericMotionEvent(event)
            val p = pad(event.deviceId)
            p.lx = dead(event.getAxisValue(MotionEvent.AXIS_X)); p.ly = -dead(event.getAxisValue(MotionEvent.AXIS_Y))
            p.rx = dead(event.getAxisValue(MotionEvent.AXIS_Z)); p.ry = -dead(event.getAxisValue(MotionEvent.AXIS_RZ))
            p.lt = maxOf(event.getAxisValue(MotionEvent.AXIS_LTRIGGER), event.getAxisValue(MotionEvent.AXIS_BRAKE))
            p.rt = maxOf(event.getAxisValue(MotionEvent.AXIS_RTRIGGER), event.getAxisValue(MotionEvent.AXIS_GAS))
            val hx = event.getAxisValue(MotionEvent.AXIS_HAT_X); val hy = event.getAxisValue(MotionEvent.AXIS_HAT_Y)
            p.down = p.down and (256 or 512 or 1024 or 2048).inv() or
                (if (hy < -0.5f) 256 else 0) or (if (hy > 0.5f) 512 else 0) or (if (hx < -0.5f) 1024 else 0) or (if (hx > 0.5f) 2048 else 0)
            if (abs(p.lx) + abs(p.ly) + abs(p.rx) + abs(p.ry) > 0.3f) touch.controllerUsed()
            send()
            return true
        }

        // A controller that goes away mid-press leaves nothing held.
        override fun onInputDeviceRemoved(id: Int) { pads.remove(id); send() }
        override fun onInputDeviceAdded(id: Int) {}
        override fun onInputDeviceChanged(id: Int) {}

        /// The pads as the host takes them: the first controller with the touch controls in it, then the rest.
        private fun send() {
            val playing = pads.values.toList()
            for (i in 0 until 4) {
                val p = playing.getOrNull(i)
                if (i == 0) {
                    val t = touch.pad
                    fun further(a: Float, b: Float) = if (abs(b) > abs(a)) b else a
                    Native.pad(0, true, further(p?.lx ?: 0f, t.lx), further(p?.ly ?: 0f, t.ly), further(p?.rx ?: 0f, t.rx), further(p?.ry ?: 0f, t.ry),
                               maxOf(p?.lt ?: 0f, t.lt), maxOf(p?.rt ?: 0f, t.rt), (p?.down ?: 0) or t.down, touch.takeTapped())
                } else if (p != null) {
                    Native.pad(i, true, p.lx, p.ly, p.rx, p.ry, p.lt, p.rt, p.down, 0)
                } else {
                    Native.pad(i, false, 0f, 0f, 0f, 0f, 0f, 0f, 0, 0)
                }
            }
        }

        private val shaking = IntArray(4)
        private fun rumble() {
            val ids = pads.keys.toList()
            for (i in 0 until 4) {
                val want = Native.rumble(i)
                if (want == shaking[i]) continue
                shaking[i] = want
                val device = ids.getOrNull(i)?.let { InputDevice.getDevice(it) } ?: continue
                @Suppress("DEPRECATION") val vibrator = device.vibrator
                if (!vibrator.hasVibrator()) continue
                val strength = maxOf(want shr 8, want and 255)
                if (strength == 0) vibrator.cancel() else vibrator.vibrate(VibrationEffect.createOneShot(10_000, strength.coerceIn(1, 255)))
            }
        }

        /// The controller drawn over the game while no controller is played: a stick wherever the left thumb goes down,
        /// a right-hand drag as the right stick when the game asks for it, and the game's buttons (`lamp_touch_buttons`).
        class TouchControls(context: Context, val changed: () -> Unit) : View(context) {
            val pad = Pad()
            var buttons = 1 or 2 or 64
                set(value) { if (field != value) { field = value; invalidate() } }
            private var tapped = 0
            private var shown = true
            private val sticks = HashMap<Int, Triple<Boolean, Float, Float>>()   // pointer → (left?, start x, start y)
            private val now = HashMap<Int, Pair<Float, Float>>()
            private val pressing = HashMap<Int, Int>()                           // pointer → button bit
            private val fill = Paint(Paint.ANTI_ALIAS_FLAG)
            private val label = Paint(Paint.ANTI_ALIAS_FLAG).apply { color = Color.WHITE; textAlign = Paint.Align.CENTER; typeface = Typeface.DEFAULT_BOLD }
            private val dp = context.resources.displayMetrics.density

            fun tap(bit: Int) { tapped = tapped or bit }
            fun takeTapped(): Int { val t = tapped; tapped = 0; return t }
            fun controllerUsed() { if (shown) { shown = false; invalidate() } }

            private fun layout(): List<Triple<Int, String, FloatArray>> {
                val w = width.toFloat(); val h = height.toFloat(); val r = 32 * dp; val small = 22 * dp
                return listOf(
                    Triple(1, "A", floatArrayOf(w - 110 * dp, h - 72 * dp, r)), Triple(2, "B", floatArrayOf(w - 40 * dp, h - 142 * dp, r)),
                    Triple(4, "X", floatArrayOf(w - 180 * dp, h - 142 * dp, r)), Triple(8, "Y", floatArrayOf(w - 110 * dp, h - 212 * dp, r)),
                    Triple(16, "LB", floatArrayOf(52 * dp, 42 * dp, small)), Triple(128, "⧉", floatArrayOf(112 * dp, 42 * dp, small)),
                    Triple(64, "≡", floatArrayOf(w - 112 * dp, 42 * dp, small)), Triple(32, "RB", floatArrayOf(w - 52 * dp, 42 * dp, small)))
                    .filter { buttons and it.first != 0 }
            }

            override fun onTouchEvent(event: MotionEvent): Boolean {
                if (!shown) { shown = true }
                val i = event.actionIndex; val id = event.getPointerId(i)
                when (event.actionMasked) {
                    MotionEvent.ACTION_DOWN, MotionEvent.ACTION_POINTER_DOWN -> {
                        val x = event.getX(i); val y = event.getY(i)
                        val hit = layout().firstOrNull { hypot(x - it.third[0], y - it.third[1]) < it.third[2] * 1.3f }
                        if (hit != null) { pressing[id] = hit.first; pad.down = pad.down or hit.first; tap(hit.first) }
                        else if (x < width / 2f || (buttons and 8192) != 0) { sticks[id] = Triple(x < width / 2f, x, y); now[id] = x to y }
                    }
                    MotionEvent.ACTION_MOVE -> for (p in 0 until event.pointerCount) {
                        val pid = event.getPointerId(p)
                        if (sticks.containsKey(pid)) now[pid] = event.getX(p) to event.getY(p)
                    }
                    MotionEvent.ACTION_UP, MotionEvent.ACTION_POINTER_UP, MotionEvent.ACTION_CANCEL -> {
                        pressing.remove(id)?.let { b -> if (pressing.values.none { it == b }) pad.down = pad.down and b.inv() }
                        sticks.remove(id); now.remove(id)
                        if (event.actionMasked == MotionEvent.ACTION_CANCEL) { pressing.clear(); sticks.clear(); now.clear(); pad.down = 0 }
                    }
                }
                pad.lx = 0f; pad.ly = 0f; pad.rx = 0f; pad.ry = 0f
                val reach = 60 * dp
                for ((pid, s) in sticks) {
                    val (x, y) = now[pid] ?: continue
                    var dx = x - s.second; var dy = y - s.third
                    val length = hypot(dx, dy); if (length > reach) { dx *= reach / length; dy *= reach / length }
                    if (s.first) { pad.lx = dx / reach; pad.ly = -dy / reach } else { pad.rx = dx / reach; pad.ry = -dy / reach }
                }
                changed()
                invalidate()
                return true
            }

            override fun onDraw(canvas: Canvas) {
                if (!shown) return
                val reach = 60 * dp
                fill.style = Paint.Style.STROKE; fill.strokeWidth = 2 * dp; fill.color = Color.argb(64, 255, 255, 255)
                if (sticks.values.none { it.first }) canvas.drawCircle(40 * dp + reach, height - 32 * dp - reach, reach, fill)
                fill.style = Paint.Style.FILL
                for ((pid, s) in sticks) {
                    val (x, y) = now[pid] ?: continue
                    var dx = x - s.second; var dy = y - s.third
                    val length = hypot(dx, dy); if (length > reach) { dx *= reach / length; dy *= reach / length }
                    fill.color = Color.argb(46, 255, 255, 255); canvas.drawCircle(s.second, s.third, reach, fill)
                    fill.color = Color.argb(115, 255, 255, 255); canvas.drawCircle(s.second + dx, s.third + dy, 27 * dp, fill)
                }
                for ((bit, title, at) in layout()) {
                    fill.color = Color.argb(if (pad.down and bit != 0) 128 else 56, 255, 255, 255)
                    canvas.drawCircle(at[0], at[1], at[2], fill)
                    label.textSize = at[2] * 0.7f
                    canvas.drawText(title, at[0], at[1] + label.textSize * 0.35f, label)
                }
            }
        }
    }

    """#

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
