import AppKit

/// A three.js game on Android: a small Android app of Lamp's own in the game's `Lamp/Android` folder, none of it the agent's
/// (never a folder of its own at the top, where Lamp would take it for another app of the wish's: `Parts.folders`),
/// which shows the game's page (`Web/`, copied into the app's assets by the build) full screen in a WebView. It serves the
/// page from the app at an address of its own (so modules and fetch work as in every other place), plays its sound with
/// no tap first, keeps its saves in the WebView's storage, and reads the controllers itself (Android's own key and
/// motion events), handing them to Lamp's runtime in the page (`lampNativePad`), since a WebView doesn't promise the
/// Gamepad API. The touch controls are the runtime's own. The build is Lamp's Android build (Gradle from Lamp's tools,
/// in the app's sandbox), and the app is installed, launched, looked at and used like any Android app of Lamp's
/// (`Store.installOnAndroid`, its package and `.MainActivity`). It's Lamp's one host for a page on Android
/// (`PageHost.androidWebView`): the same app goes on a phone, a tablet and a Google TV, Android TV or Fire TV, where it's on
/// the TV's home screen with a banner (the leanback launcher, no touch screen needed) and the remote's keys reach the
/// page as a TV's do (the d-pad as the controller's for a game; Back, OK and the media keys as Web/lamp.js reads them for
/// a screen). A screen on Android is the same app around its page
/// (`ScreenKit`), not a game to the system, laid out as its viewport asks (filling the screen, or a fixed 1920x1080 page
/// fitted to it), and kept awake, as a photo frame's own app would be.
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
        let talks = Template.carriesWish(project)
        try Template.write(Template.androidSettingsGradle, to: "\(folder)/settings.gradle.kts", for: project)
        try Template.write(talks ? Template.androidRootBuildGradle : rootBuildGradle, to: "\(folder)/build.gradle.kts", for: project)
        try Template.write(Template.androidGradleProperties, to: "\(folder)/gradle.properties", for: project)
        try Template.write(Template.androidVersionsCatalogue, to: "\(folder)/gradle/libs.versions.toml", for: project)
        try Template.write(talks ? wishBuildGradle : aloneBuildGradle, to: "\(folder)/app/build.gradle.kts", for: project)
        let screen = ScreenKit.isScreen(project)
        try Template.write(screen ? screenManifest : manifest, to: "\(folder)/app/src/main/AndroidManifest.xml", for: project)
        let activity = screen ? screenActivity : gameActivity
        try Template.write((talks ? activity : withoutWish(activity: activity)).replacingOccurrences(of: "{{PACKAGE}}", with: package),
                           to: kotlin + "/MainActivity.kt", for: project)
        try Template.write(pageGateway.replacingOccurrences(of: "{{PACKAGE}}", with: package), to: kotlin + "/LampPageGateway.kt", for: project)
        try Template.write(".gradle/\n.kotlin/\nlocal.properties\n", to: "\(folder)/.gitignore", for: project)
        // The banner a TV's home screen shows: the app's icon on a dark tile, or the tile alone until it has one.
        let icon = AppFile.read(Icons.squareURL(project), in: project).flatMap(NSImage.init(data:))
        try Template.put(DeviceSupport.iconPNG(icon, width: 320, height: 180), at: project.dir.appendingPathComponent("\(folder)/\(banner)"), for: project)
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
                "app/src/main/AndroidManifest.xml", "app/src/main/kotlin/\(package)/MainActivity.kt", "app/src/main/kotlin/\(package)/LampPageGateway.kt",
                "app/src/main/kotlin/\(package)/\(Template.androidSupportFile)", "app/src/main/kotlin/\(package)/LampPageWish.kt",
                Template.androidDebugManifest, banner].map { "\(folder)/\($0)" }
    }

    /// Where the banner goes, in the app's own resources (the icon is the game's build/, drawn by build.sh).
    static let banner = "app/src/main/res/drawable-xhdpi/lamp_banner.png"

    /// The activity for a game, without a screen's lines, and for a screen, without a game's; each kind's own unmarked.
    static var gameActivity: String {
        mainActivity.components(separatedBy: "\n").filter { !$0.hasSuffix(screenLine) }.joined(separator: "\n")
            .replacingOccurrences(of: " " + gameLine, with: "")
    }
    static var screenActivity: String {
        mainActivity.components(separatedBy: "\n").filter { !$0.hasSuffix(gameLine) }.joined(separator: "\n")
            .replacingOccurrences(of: " " + screenLine, with: "")
    }
    private static let screenLine = "// a screen", gameLine = "// a game"

    /// A screen's manifest: no game to the system, and it may listen.
    static var screenManifest: String {
        manifest.replacingOccurrences(of: "        android:isGame=\"true\"\n", with: "")
            .replacingOccurrences(of: internetLine, with: internetLine + recordLine)
    }
    private static let internetLine = "    <uses-permission android:name=\"android.permission.INTERNET\" />\n"
    /// A screen's Ask listens (LampPageVoice), asked for only when the person first talks to it.
    private static let recordLine = "    <uses-permission android:name=\"android.permission.RECORD_AUDIO\" />\n"
        + "    <uses-feature android:name=\"android.hardware.microphone\" android:required=\"false\" />\n"

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

    /// The build of a page on its own: AndroidX's WebKit alone, whose message listener lets only the page's own origin in
    /// its main frame reach Lamp (`pageGateway`).
    static let aloneBuildGradle = appBuildGradle + """

    dependencies {
        implementation(libs.androidx.webkit)
    }

    """

    /// What a new Lamp's Android host is made of, for the builds it changes (`Target.Recipe.inputs`): its folder isn't
    /// among a page's sources.
    static var stamp: String { manifest + screenManifest + mainActivity + pageGateway + aloneBuildGradle + wishBuildGradle }

    /// The page's LampAI (Web/lamp.js's `lampGatewayHost`), answered by the app with its own token, which Lamp writes
    /// into the app's storage as it installs it (`Adb.tellApp`), as the app around the page answers it on the Mac
    /// (`lampGateway`, LampPage.swift): only LampAI's routes, only from the page's own origin in its main frame. The page
    /// never sees the token.
    static let pageGateway = #"""
    // Written by Lamp before every build; don't edit. The page's LampAI (Web/lamp.js), answered through this app.
    package {{PACKAGE}}

    import android.webkit.WebView
    import androidx.webkit.WebViewCompat
    import androidx.webkit.WebViewFeature
    import java.io.File
    import java.net.InetSocketAddress
    import java.net.Socket
    import org.json.JSONObject
    import kotlin.concurrent.thread

    object LampPageGateway {
        private val routes = setOf("/ai", "/ai/status", "/ai/image", "/ai/decide", "/ai/act", "/ai/hear")

        /** Answers the page at `origin`, the page's own, in its main frame: no other page or frame reaches Lamp. */
        fun attach(web: WebView, origin: String) {
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
            val files = web.context.filesDir
            WebViewCompat.addWebMessageListener(web, "lampGatewayHost", setOf(origin)) { _, message, _, isMainFrame, reply ->
                val call = try { JSONObject(message.data ?: "") } catch (e: Exception) { null }
                if (!isMainFrame || call == null) return@addWebMessageListener
                val id = call.optInt("id")
                val path = call.optString("path")
                val body = call.optString("body", "{}")
                // The page's own wait for an answer (a status check's few seconds, a question's minutes).
                val timeout = call.optInt("timeout", 240_000).coerceIn(1_000, 240_000)
                thread {
                    val (status, text) = if (path in routes) post(files, path, body, timeout) else 404 to JSONObject().put("error", "Not found").toString()
                    val answer = JSONObject().put("id", id).put("status", status).put("body", text).toString()
                    web.post { reply.postMessage(answer) }
                }
            }
        }

        private fun failure(message: String) = 503 to JSONObject().put("error", message).toString()

        /** Plain HTTP on the Mac's own network, on a socket, as the Kotlin building blocks speak it: each way to the Mac
         *  Lamp wrote down in turn, and all of them once more after a moment, in case Lamp is just starting. */
        private fun post(files: File, path: String, body: String, timeout: Int): Pair<Int, String> {
            val deadline = System.currentTimeMillis() + timeout
            val install = try { JSONObject(File(files, "lamp-install.json").readText()) } catch (e: Exception) {
                return failure("This copy of the app wasn't opened from Lamp, so it can't use AI. Open it from Lamp on your Mac.")
            }
            val token = install.optString("token")
            val list = install.optJSONArray("routes") ?: return failure("Couldn't reach Lamp. Open Lamp on your Mac and try again.")
            val bytes = body.toByteArray(Charsets.UTF_8)
            // What the person said is paid for once heard: tried on each way to the Mac once, never again after a moment.
            for (attempt in 0 until (if (path == "/ai/hear") 1 else 2)) {
                for (i in 0 until list.length()) {
                    val route = list.optJSONObject(i) ?: continue
                    val left = (deadline - System.currentTimeMillis()).toInt()
                    if (left <= 0) break
                    try {
                        return exchange(route, path, token, bytes, left)
                    } catch (e: Exception) {
                        continue
                    }
                }
                if (attempt == 0 && deadline - System.currentTimeMillis() > 3000) Thread.sleep(3000) else break
            }
            return failure(if (install.optBoolean("device")) "Couldn't reach Lamp on your Mac. Keep this device on the same Wi‑Fi as the Mac, with Lamp open, and try again."
                           else "Couldn't reach Lamp. Open Lamp on your Mac and try again.")
        }

        private fun exchange(route: JSONObject, path: String, token: String, body: ByteArray, timeout: Int): Pair<Int, String> {
            Socket().use { socket ->
                socket.connect(InetSocketAddress(route.getString("address"), route.getInt("port")), minOf(4000, timeout))
                socket.soTimeout = timeout
                val head = "POST $path HTTP/1.1\r\nHost: ${route.getString("host")}\r\nAuthorization: Bearer $token\r\n" +
                    "Content-Type: application/json\r\nContent-Length: ${body.size}\r\nConnection: close\r\n\r\n"
                socket.getOutputStream().apply { write(head.toByteArray()); write(body); flush() }
                val all = socket.getInputStream().readBytes()
                val split = (0..all.size - 4).firstOrNull { all[it] == '\r'.code.toByte() && all[it + 1] == '\n'.code.toByte() && all[it + 2] == '\r'.code.toByte() && all[it + 3] == '\n'.code.toByte() }
                    ?: throw java.io.IOException("Lamp's answer was cut short.")
                val status = String(all, 0, split).split("\r\n").first().split(" ").getOrNull(1)?.toIntOrNull()
                    ?: throw java.io.IOException("Lamp's answer couldn't be read.")
                return status to String(all, split + 4, all.size - split - 4)
            }
        }
    }

    /** The page's LampVoice (Web/lamp.js's `lampVoiceHost`): what the person says, recorded by whatever microphone this
     *  device gives an app (a TV remote's included, which Android hands over as the voice-recognition source), as
     *  16 kHz mono 16-bit PCM in a WAV for the page to have transcribed (`LampAI.hear`); and what the page says back,
     *  read out. Asking what's possible never prompts: only `listen` asks for the microphone. One recording at a time,
     *  tagged with the page's session; a stop keeps it, a cancel throws it away, and the app leaving the screen or the
     *  page loading again cancels it whether the page says so or not. Only the page's own origin, in its main frame. */
    object LampPageVoice {
        private const val RATE = 16000
        private const val MAX_SECONDS = 15.0; private const val WAIT_SECONDS = 6.0; private const val QUIET_SECONDS = 1.2
        private var activity: android.app.Activity? = null
        private var web: WebView? = null
        private var reply: androidx.webkit.JavaScriptReplyProxy? = null
        @Volatile private var session = ""
        @Volatile private var stopAs: String? = null
        private var waiting: Pair<String, Int>? = null      // the session and call asking for the microphone
        private var tts: android.speech.tts.TextToSpeech? = null
        private var ttsReady = false
        private val spoken = mutableMapOf<String, Int>()     // utterance -> call id

        fun attach(activity: android.app.Activity, web: WebView, origin: String) {
            if (!WebViewFeature.isFeatureSupported(WebViewFeature.WEB_MESSAGE_LISTENER)) return
            this.activity = activity; this.web = web
            WebViewCompat.addWebMessageListener(web, "lampVoiceHost", setOf(origin)) { _, message, _, isMainFrame, proxy ->
                val call = try { JSONObject(message.data ?: "") } catch (e: Exception) { null }
                if (!isMainFrame || call == null) return@addWebMessageListener
                reply = proxy
                val id = call.optInt("id"); val tag = call.optString("session")
                when (call.optString("cmd")) {
                    "status" -> answer(id, status())
                    "listen" -> listen(tag, id)
                    "stop" -> { if (tag == session) stopAs = "stopped"; answer(id, JSONObject().put("ok", true)) }
                    "cancel" -> { if (tag == session) cancel() else if (waiting?.first == tag) waiting = null; answer(id, JSONObject().put("ok", true)) }
                    "speak" -> speak(call.optString("text"), id)
                    "hush" -> { tts?.stop(); answer(id, JSONObject().put("ok", true)) }
                    else -> answer(id, JSONObject().put("error", "Unknown."))
                }
            }
        }

        /** The app left the screen, or the page loads again: nothing goes on being heard. */
        fun cancel() { waiting = null; if (session.isNotEmpty()) stopAs = "cancelled"; tts?.stop() }

        private fun granted() = activity?.checkSelfPermission(android.Manifest.permission.RECORD_AUDIO) == android.content.pm.PackageManager.PERMISSION_GRANTED

        fun status(): JSONObject {
            val a = activity
            val permission = when {
                granted() -> "granted"
                a != null && a.shouldShowRequestPermissionRationale(android.Manifest.permission.RECORD_AUDIO) -> "denied"
                else -> "ask"
            }
            val inputs = (a?.getSystemService(android.content.Context.AUDIO_SERVICE) as? android.media.AudioManager)
                ?.getDevices(android.media.AudioManager.GET_DEVICES_INPUTS)?.size ?: 0
            return JSONObject().put("listen", inputs > 0).put("speak", true).put("permission", permission)
                .put("why", if (inputs > 0) "" else "This device has no microphone.").put("maxSeconds", MAX_SECONDS)
        }

        private fun listen(tag: String, id: Int) {
            cancel()
            if (!granted()) {
                waiting = tag to id
                activity?.requestPermissions(arrayOf(android.Manifest.permission.RECORD_AUDIO), 7307)
                return
            }
            record(tag, id)
        }

        /** The person's answer to the system's question (MainActivity passes it on). Closed meanwhile: nothing starts. */
        fun permissionResult(code: Int, allowed: Boolean) {
            if (code != 7307) return
            val (tag, id) = waiting ?: return
            waiting = null
            if (!allowed) { answer(id, JSONObject().put("ended", "denied")); return }
            record(tag, id)
        }

        private fun record(tag: String, id: Int) {
            tts?.stop()
            session = tag; stopAs = null
            thread {
                val result = try { capture(tag) } catch (e: Exception) { JSONObject().put("ended", "error").put("error", e.message ?: "The microphone failed.") }
                if (session == tag) session = ""
                answer(id, result)
            }
        }

        /** Records until the person stops speaking, a stop, a cancel or the limit; levels go to the page as it goes. */
        private fun capture(tag: String): JSONObject {
            val min = android.media.AudioRecord.getMinBufferSize(RATE, android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT)
            @Suppress("MissingPermission")
            val rec = android.media.AudioRecord(android.media.MediaRecorder.AudioSource.VOICE_RECOGNITION, RATE,
                android.media.AudioFormat.CHANNEL_IN_MONO, android.media.AudioFormat.ENCODING_PCM_16BIT, maxOf(min, RATE))
            if (rec.state != android.media.AudioRecord.STATE_INITIALIZED) { rec.release(); return JSONObject().put("ended", "error").put("error", "The microphone didn't open.") }
            val pcm = java.io.ByteArrayOutputStream()
            val buf = ShortArray(RATE / 25)                  // 40 ms
            val bytes = java.nio.ByteBuffer.allocate(buf.size * 2).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            var noise = 0.0; var peak = 0.0; var speechAt = -1.0; var quietSince = -1.0
            var ended = "cap"
            rec.startRecording()
            val routed = rec.routedDevice?.type ?: -1
            try {
                while (true) {
                    val asked = stopAs
                    if (asked != null) { ended = asked; break }
                    val n = rec.read(buf, 0, buf.size)
                    if (n <= 0) continue
                    bytes.clear(); var sum = 0.0; var top = 0.0
                    for (i in 0 until n) { val v = buf[i] / 32768.0; sum += v * v; top = maxOf(top, kotlin.math.abs(v)); bytes.putShort(buf[i]) }
                    pcm.write(bytes.array(), 0, n * 2)
                    val level = kotlin.math.sqrt(sum / n); peak = maxOf(peak, top)
                    val t = pcm.size() / 2.0 / RATE
                    if (t < 0.3) noise = maxOf(noise, level)
                    if (level > maxOf(noise * 3, 0.02)) { if (speechAt < 0) speechAt = t; quietSince = -1.0 } else if (speechAt >= 0 && quietSince < 0) quietSince = t
                    event(JSONObject().put("event", "level").put("session", tag).put("level", minOf(1.0, level * 4)).put("speech", speechAt >= 0))
                    if (t >= MAX_SECONDS) { ended = "cap"; break }
                    if (speechAt < 0 && t >= WAIT_SECONDS) { ended = "nothing"; break }
                    if (quietSince >= 0 && t - quietSince >= QUIET_SECONDS) { ended = "quiet"; break }
                }
            } finally { rec.stop(); rec.release() }
            val audio = pcm.toByteArray()
            val out = JSONObject().put("ended", ended).put("seconds", audio.size / 2.0 / RATE).put("peak", peak)
                .put("speech", speechAt >= 0).put("input", routed)
            if (ended == "stopped" || ended == "quiet" || ended == "cap") out.put("audio", android.util.Base64.encodeToString(wav(audio), android.util.Base64.NO_WRAP))
            return out
        }

        private fun wav(pcm: ByteArray): ByteArray {
            val h = java.nio.ByteBuffer.allocate(44).order(java.nio.ByteOrder.LITTLE_ENDIAN)
            h.put("RIFF".toByteArray()).putInt(36 + pcm.size).put("WAVEfmt ".toByteArray()).putInt(16).putShort(1).putShort(1)
                .putInt(RATE).putInt(RATE * 2).putShort(2).putShort(16).put("data".toByteArray()).putInt(pcm.size)
            return h.array() + pcm
        }

        private fun speak(text: String, id: Int) {
            val a = activity ?: return answer(id, JSONObject().put("done", false))
            if (text.isEmpty() || session.isNotEmpty()) return answer(id, JSONObject().put("done", false))
            fun say() {
                val utterance = "u$id"
                spoken[utterance] = id
                tts?.speak(text, android.speech.tts.TextToSpeech.QUEUE_FLUSH, null, utterance)
            }
            if (tts != null && ttsReady) return say()
            tts = android.speech.tts.TextToSpeech(a) { status ->
                ttsReady = status == android.speech.tts.TextToSpeech.SUCCESS
                if (!ttsReady) { answer(id, JSONObject().put("done", false)); return@TextToSpeech }
                tts?.setOnUtteranceProgressListener(object : android.speech.tts.UtteranceProgressListener() {
                    override fun onStart(u: String) {}
                    override fun onDone(u: String) { spoken.remove(u)?.let { answer(it, JSONObject().put("done", true)) } }
                    @Deprecated("Deprecated in Java") override fun onError(u: String) { spoken.remove(u)?.let { answer(it, JSONObject().put("done", false)) } }
                    override fun onStop(u: String, interrupted: Boolean) { spoken.remove(u)?.let { answer(it, JSONObject().put("done", false)) } }
                })
                say()
            }
        }

        private fun answer(id: Int, body: JSONObject) = post(body.put("id", id))
        private fun event(body: JSONObject) = post(body)
        private fun post(body: JSONObject) {
            val w = web ?: return; val r = reply ?: return
            w.post { try { r.postMessage(body.toString()) } catch (e: Exception) {} }
        }
    }

    """#

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
        <!-- Back reaches the page as a key (the game's B, a TV page's Back), not Android's predictive back, which would
             leave the app before the page says what going back means. -->
        <!-- One app for phones and TVs: no touch screen needed, and on a TV's home screen through the leanback launcher. -->
        <uses-feature android:name="android.hardware.touchscreen" android:required="false" />
        <uses-feature android:name="android.hardware.gamepad" android:required="false" />
        <uses-feature android:name="android.software.leanback" android:required="false" />
        <!-- A page may read the web (a screen's weather, a game's scores), as it does in every other place. -->
        <uses-permission android:name="android.permission.INTERNET" />
        <application
            android:allowBackup="true"
            android:banner="@drawable/lamp_banner"
            android:enableOnBackInvokedCallback="false"
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
                    <category android:name="android.intent.category.LEANBACK_LAUNCHER" />
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
    import android.webkit.JavascriptInterface // a screen
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
            // A screen is laid out at the width its viewport asks for (the device's own, or a fixed 1920 for a page made // a screen
            // before screens filled any shape) and shown whole, and the display stays on. // a screen
            web.settings.useWideViewPort = true // a screen
            web.settings.loadWithOverviewMode = true // a screen
            window.addFlags(android.view.WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON) // a screen
            // Back on the page's first view leaves the app, as on a TV (Web/lamp.js's exit). // a screen
            web.addJavascriptInterface(object { @JavascriptInterface fun exit() { runOnUiThread { finish() } } }, "lampAndroid") // a screen
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
                override fun onPageStarted(view: WebView, url: String?, favicon: android.graphics.Bitmap?) { LampPageVoice.cancel() } // a screen
            }
            web.webChromeClient = object : WebChromeClient() {
                override fun onConsoleMessage(message: ConsoleMessage): Boolean {
                    Log.i("Lamp", message.message())
                    return true
                }
            }
            setContentView(web)
            LampPageGateway.attach(web, "https://$HOST")
            LampPageVoice.attach(this, web, "https://$HOST") // a screen
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

        override fun onPause() {
            super.onPause()
            LampPageVoice.cancel() // a screen
            web.onPause()
        }
        // The person's answer to the microphone question LampPageVoice asked. // a screen
        override fun onRequestPermissionsResult(code: Int, permissions: Array<String>, results: IntArray) { // a screen
            super.onRequestPermissionsResult(code, permissions, results) // a screen
            LampPageVoice.permissionResult(code, results.firstOrNull() == android.content.pm.PackageManager.PERMISSION_GRANTED) // a screen
        } // a screen

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

        // A TV remote's d-pad is a controller's to a game: its arrows the d-pad, OK the A button, play/pause Start.
        private fun fromController(event: KeyEvent) =
            event.isFromSource(InputDevice.SOURCE_GAMEPAD) || event.isFromSource(InputDevice.SOURCE_JOYSTICK) || KeyEvent.isGamepadButton(event.keyCode)
                || event.isFromSource(InputDevice.SOURCE_DPAD) || event.keyCode == KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE // a game
        private fun remote(code: Int) = when (code) { // a game
            KeyEvent.KEYCODE_DPAD_CENTER -> KeyEvent.KEYCODE_BUTTON_A; KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> KeyEvent.KEYCODE_BUTTON_START; else -> code // a game
        } // a game

        // The keys of a TV's remote a WebView passes on as nothing, as the page reads them on a TV (Web/lamp.js's // a screen
        // key codes): Back, the media, color and channel keys. The arrows, OK and the digits reach the page by themselves. // a screen
        private fun tvKey(code: Int) = when (code) { // a screen
            KeyEvent.KEYCODE_BACK -> 27; KeyEvent.KEYCODE_MEDIA_PLAY -> 415; KeyEvent.KEYCODE_MEDIA_PAUSE -> 19 // a screen
            KeyEvent.KEYCODE_MEDIA_PLAY_PAUSE -> 10252; KeyEvent.KEYCODE_MEDIA_STOP -> 413 // a screen
            KeyEvent.KEYCODE_MEDIA_FAST_FORWARD -> 417; KeyEvent.KEYCODE_MEDIA_REWIND -> 412 // a screen
            KeyEvent.KEYCODE_PROG_RED -> 403; KeyEvent.KEYCODE_PROG_GREEN -> 404; KeyEvent.KEYCODE_PROG_YELLOW -> 405; KeyEvent.KEYCODE_PROG_BLUE -> 406 // a screen
            KeyEvent.KEYCODE_CHANNEL_UP -> 427; KeyEvent.KEYCODE_CHANNEL_DOWN -> 428; KeyEvent.KEYCODE_INFO -> 457 // a screen
            else -> 0 // a screen
        } // a screen

        override fun dispatchKeyEvent(event: KeyEvent): Boolean {
            val key = tvKey(event.keyCode) // a screen
            if (key == 0) return super.dispatchKeyEvent(event) // a screen
            if (event.action == KeyEvent.ACTION_DOWN) web.evaluateJavascript(PRESS.replace("KEY", "$key"), null) // a screen
            return true // a screen
            // Back is the game's B, as on a console: the game says what going back means, and stays open. // a game
            val code = if (event.keyCode == KeyEvent.KEYCODE_BACK) KeyEvent.KEYCODE_BUTTON_B else remote(event.keyCode) // a game
            val b = bit(code) // a game
            if (b != 0 && (fromController(event) || event.keyCode == KeyEvent.KEYCODE_BACK)) { // a game
                if (fromController(event)) vendor = event.device?.vendorId ?: 0 // a game
                down = if (event.action == KeyEvent.ACTION_DOWN) down or b else down and b.inv() // a game
                send() // a game
                return true // a game
            } // a game
            return super.dispatchKeyEvent(event) // a game
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

        companion object {
            const val HOST = "lamp.game"
            // A key pressed on the page where it has focus, with the code a TV's browser gives it. // a screen
            const val PRESS = "(function(){var e=new KeyboardEvent('keydown',{bubbles:true,cancelable:true});" + // a screen
                "Object.defineProperty(e,'keyCode',{get:function(){return KEY}});Object.defineProperty(e,'which',{get:function(){return KEY}});" + // a screen
                "(document.activeElement||document.body).dispatchEvent(e)})()" // a screen
        }
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
                // The shared collections the page uses (LampStore.shared in lamp.js), which this app keeps: told whole once,
                // then as they change.
                "shared" -> {
                    val name = call.optString("s")
                    if (!LampWish.isCollection(name)) return
                    hearItems(name)
                    tellItems(name, LampWish.items(name).map { it.first to (it.second as Any?) }, true, LampWish.me)
                }
                "put", "publish" -> {
                    val list = json(call.optString("items")) as? JSONArray ?: return
                    val given = (0 until list.length()).mapNotNull { i ->
                        val pair = list.optJSONArray(i)?.takeIf { it.length() == 2 } ?: return@mapNotNull null
                        val id = pair.opt(0) as? String ?: return@mapNotNull null
                        id to pair.opt(1)?.takeIf { it != JSONObject.NULL }
                    }
                    val name = call.optString("s")
                    val kept = if (call.optString("op") == "put") LampWish.putItems(name, given)
                        else LampWish.publishItems(name, given.mapNotNull { (id, value) -> value?.let { id to it } })
                    // Turned down (past a limit): the page, which showed it at once, is told the collection as it really is.
                    if (!kept) tellItems(name, LampWish.items(name).map { it.first to (it.second as Any?) }, true, LampWish.me)
                }
                "putFile" -> {
                    val bytes = try { Base64.decode(call.optString("data"), Base64.DEFAULT) } catch (e: Exception) { return }
                    val kept = LampWish.putFile(call.optString("s"), call.optString("id"), bytes, call.optString("type"))
                    if (call.has("ask")) tell(JSONObject().put("t", "fileDone").put("ask", call.optInt("ask")).put("ok", kept))
                }
                "fileBytes" -> {
                    val file = LampWish.fileOf(call.optString("s"), call.optString("id"))
                    val bytes = try { file?.readBytes() } catch (e: Exception) { null }
                    tell(JSONObject().put("t", "fileBytes").put("ask", call.optInt("ask")).put("data", bytes?.let { Base64.encodeToString(it, Base64.NO_WRAP) } ?: JSONObject.NULL))
                }
            }
        }

        private fun tellItems(name: String, items: List<Pair<String, Any?>>, whole: Boolean, from: String) {
            val said = JSONObject()
            val here = JSONObject()
            for ((id, value) in items) {
                said.put(id, value ?: JSONObject.NULL)
                if (name.startsWith("files:")) here.put(id, LampWish.fileOf(name, id) != null)
            }
            tell(JSONObject().put("t", "items").put("s", name).put("items", said).put("whole", whole).put("from", from).put("here", here))
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
                val copies = JSONArray()
                for (each in peer.copies) copies.put(JSONObject().put("id", each.id).put("device", each.device).put("since", each.since))
                list.put(JSONObject().put("peer", peer.peer).put("kind", peer.kind).put("name", peer.name).put("device", peer.device)
                    .put("open", peer.isOpen).put("copies", copies).put("status", JSONObject().put("state", peer.status.state.name).put("reason", peer.status.reason)
                        .put("lastSeen", peer.status.lastSeen ?: JSONObject.NULL)))
            }
            tell(JSONObject().put("t", "state").put("me", LampWish.me).put("copy", LampWish.copy).put("apps", list)
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
            private val heardItems = mutableSetOf<String>()

            private fun hearItems(name: String) {
                if (!heardItems.add(name)) return
                LampWish.onItems(name) { changed, from -> current?.get()?.tellItems(name, changed, false, from) }
            }

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
                LampWish.onMessage { from, data, copy ->
                    current?.get()?.tell(JSONObject().put("t", "message").put("from", from).put("copy", copy).put("data", data ?: JSONObject.NULL))
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
                    current?.get()?.tell(JSONObject().put("t", "file").put("from", from).put("copy", file.copy).put("name", file.name).put("type", file.type)
                        .put("data", Base64.encodeToString(file.bytes, Base64.NO_WRAP)))
                }
            }
        }
    }

    """#
}
