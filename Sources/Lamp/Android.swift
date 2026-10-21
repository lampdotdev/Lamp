import AppKit
import CryptoKit
import Foundation

/// Android apps: Kotlin and Jetpack Compose, built with Gradle, opened in the Android emulator on this Mac or on
/// the person's own Android phone or tablet through adb. Nothing of Google's is on a Mac by itself, so Lamp
/// downloads what it needs the first time an Android app is made (`install`), each download checked against
/// the checksum its maker publishes: a Java runtime, Google's command-line tools, Gradle, and through Google's
/// own package manager the platform tools, a build-tools, the platform and the emulator with one system image.
/// They go in a folder shared by every Lamp on this Mac (`folder`, under ~/Library/Developer), which the agent's
/// sandbox lets a build read and nothing in it write, so what Lamp runs as itself from there (adb, the emulator)
/// is what Lamp put there. Builds run in the app's sandbox like every build, with Gradle's cache in the caches
/// folder the sandbox opens.
enum AndroidTools {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // MARK: Folders

    /// ~/Library/Developer/Lamp/Android: one copy of the tools for every Lamp on this Mac, since they're large
    /// and the same for each. The sandbox lets a command read the person's developer folder and never write it.
    static let folder = Edition.sharedDeveloperFolder.appendingPathComponent("Android")
    static let jdkFolder = folder.appendingPathComponent("jdk")
    static let sdkFolder = folder.appendingPathComponent("sdk")
    static var gradleFolder: URL { folder.appendingPathComponent("gradle-\(gradleVersion)") }
    /// Gradle's own cache (its daemons' records, every dependency it fetched): shared by every app's build, in the
    /// caches folder the sandbox opens for writing.
    static let gradleUserHome = Edition.sharedCachesFolder.appendingPathComponent("gradle")
    /// What adb and the emulator keep (adb's key, the emulator's settings) and the emulators Lamp made: Lamp's own,
    /// since Lamp runs both as itself.
    static let userHome = Edition.supportFolder.appendingPathComponent("Android/home")
    static let avdHome = Edition.supportFolder.appendingPathComponent("Android/avd")

    static var javaHome: String { jdkFolder.appendingPathComponent("Contents/Home").path }
    static var java: String { javaHome + "/bin/java" }
    static var adb: String { sdkFolder.appendingPathComponent("platform-tools/adb").path }
    static var emulator: String { sdkFolder.appendingPathComponent("emulator/emulator").path }
    static var sdkmanager: String { sdkFolder.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager").path }
    static var avdmanager: String { sdkFolder.appendingPathComponent("cmdline-tools/latest/bin/avdmanager").path }
    static var gradle: String { gradleFolder.appendingPathComponent("bin/gradle").path }

    /// What every command of Google's or Gradle's that Lamp runs as itself is run with.
    static var environment: [String: String] {
        ["JAVA_HOME": javaHome, "ANDROID_HOME": sdkFolder.path, "ANDROID_SDK_ROOT": sdkFolder.path,
         "ANDROID_USER_HOME": userHome.path, "ANDROID_AVD_HOME": avdHome.path, "GRADLE_USER_HOME": gradleUserHome.path,
         "LAMP_GRADLE": gradle]
    }

    /// The same for a build, which runs in the app's sandbox: its Android home is in the caches folder the sandbox
    /// opens, since the build writes there (the debug signing key every debug build is signed with), where Lamp's
    /// own home (adb's key to the person's devices) stays closed to it.
    static var buildEnvironment: [String: String] {
        environment.merging(["ANDROID_USER_HOME": Edition.sharedCachesFolder.appendingPathComponent("android-home").path]) { $1 }
    }

    // MARK: Versions

    /// What's downloaded, pinned so every Lamp builds the same way; moved on purpose, with a build tried first.
    static let gradleVersion = "9.1.0"
    static let buildTools = "36.0.0"
    static let platformLevel = 36
    static let systemImage = "system-images;android-\(platformLevel);google_apis;\(isArm ? "arm64-v8a" : "x86_64")"
    static let packages = ["platform-tools", "build-tools;\(buildTools)", "platforms;android-\(platformLevel)", "emulator", systemImage]
    /// The emulator Lamp makes: one phone, named so Try On can say which.
    static let avdName = "Lamp Phone"
    static let avdProfile = "pixel_9"

    private static var isArm: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// One download: where it comes from and what it must hash to, as its maker publishes it.
    struct Release {
        let url: URL
        let sha256: String
        let size: Int64
    }

    /// Google's command-line tools (sdkmanager, avdmanager), as developer.android.com lists them with their checksums.
    static let commandLineTools = isArm
        ? Release(url: URL(string: "https://dl.google.com/android/repository/commandlinetools-mac_arm64-15859902_latest.zip")!,
                  sha256: "835b62a26162b229b441d1f6d4680383815a270809eb33522c0d480fa5002c4e", size: 156_083_281)
        : Release(url: URL(string: "https://dl.google.com/android/repository/commandlinetools-mac_x86_64-15859902_latest.zip")!,
                  sha256: "c5a6378ab5cf7e0d5701921405115befff13e9ff7417fb588389338f8bd050f3", size: 156_300_000)
    /// Eclipse Temurin's JDK 17, which Gradle and Google's tools run on, with the checksum Adoptium publishes.
    static let jdk = isArm
        ? Release(url: URL(string: "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_aarch64_mac_hotspot_17.0.20.1_1.tar.gz")!,
                  sha256: "196d13ba5f10414bef7f6a05a9b3f00edacb18ebacef2b99485db9e2ee18f0e8", size: 185_851_019)
        : Release(url: URL(string: "https://github.com/adoptium/temurin17-binaries/releases/download/jdk-17.0.20.1%2B1/OpenJDK17U-jdk_x64_mac_hotspot_17.0.20.1_1.tar.gz")!,
                  sha256: "c01975da12ed4235250ff891fe8bba73a9e73037d444b269c9d0922b5dbc8e0a", size: 180_578_248)
    /// Gradle itself, with the checksum services.gradle.org publishes beside it.
    static let gradleRelease = Release(url: URL(string: "https://services.gradle.org/distributions/gradle-\(gradleVersion)-bin.zip")!,
                                       sha256: "a17ddd85a26b6a7f5ddb71ff8b05fc5104c0202c6e64782429790c933686c806", size: 134_528_013)

    // MARK: What's there

    static var hasJDK: Bool { FileManager.default.isExecutableFile(atPath: java) }
    static var hasCommandLineTools: Bool { FileManager.default.isExecutableFile(atPath: sdkmanager) }
    static var hasGradle: Bool { FileManager.default.isExecutableFile(atPath: gradle) }
    static var hasPackages: Bool {
        FileManager.default.isExecutableFile(atPath: adb) && FileManager.default.isExecutableFile(atPath: emulator)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("build-tools/\(buildTools)/aapt2").path)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("platforms/android-\(platformLevel)/android.jar").path)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("system-images/android-\(platformLevel)/google_apis/\(isArm ? "arm64-v8a" : "x86_64")/system.img").path)
    }
    static var hasEmulator: Bool { FileManager.default.fileExists(atPath: avdHome.appendingPathComponent("\(avdName.replacingOccurrences(of: " ", with: "_")).avd/config.ini").path) }
    /// Everything a build and the emulator need is here.
    static var isReady: Bool { hasJDK && hasCommandLineTools && hasGradle && hasPackages && hasEmulator }

    enum Step: CaseIterable { case tools, emulator, device }

    enum Action { case download, retry }
    struct Issue {
        let step: Step
        let title: String
        let message: String
        let action: Action
        var button: String { action == .download ? "Download" : "Check Again" }
    }
    struct Report {
        var passed: [Step] = []
        var issue: Issue?
        var ready: Bool { issue == nil }
    }

    /// What's missing before an Android app can be built and opened, stopping at the first: the tools (one
    /// download, which `install` does whole), the emulator Lamp makes from them, and the person's own device when
    /// one is chosen (`serial`), which must be plugged in or on the network with debugging allowed to this Mac.
    static func check(device serial: String? = nil) async -> Report {
        var report = Report()
        guard hasJDK, hasCommandLineTools, hasGradle, hasPackages else {
            report.issue = Issue(step: .tools, title: "Download Android's tools",
                                 message: "Lamp makes Android apps with Google's free tools, and they aren't on this Mac yet. Click Download: it's about 2 GB, so it can take a while. Nothing else on your Mac changes.", action: .download)
            return report
        }
        report.passed.append(.tools)
        guard hasEmulator else {
            report.issue = Issue(step: .emulator, title: "Set up the emulator",
                                 message: "The emulator is an Android phone on your Mac's screen, where Lamp tries your app. Click Download and Lamp will make one.", action: .download)
            return report
        }
        report.passed.append(.emulator)
        if let serial {
            let devices = await Adb.devices()
            guard let device = devices.first(where: { $0.udid == serial }) else {
                report.issue = Issue(step: .device, title: "Plug in your Android device",
                                     message: "Lamp can't see it. Connect it to this Mac with its cable, unlock it, and allow USB debugging when it asks. Then click Check Again.", action: .retry)
                return report
            }
            if case .needs(let step) = device.setup() {
                report.issue = Issue(step: .device, title: step,
                                     message: Adb.advice(for: device.name, state: device.adbState) + " Then click Check Again.", action: .retry)
                return report
            }
            report.passed.append(.device)
        }
        return report
    }

    // MARK: Installing

    /// Downloads and puts in place whatever `check` found missing, in order, saying how far it is (0…1) and what
    /// it's doing. A download that doesn't match its published checksum isn't used. Nothing is left half done: each
    /// piece is unpacked beside its place and moved in whole.
    static func install(progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        try fm.createDirectory(at: userHome, withIntermediateDirectories: true)
        try fm.createDirectory(at: avdHome, withIntermediateDirectories: true)
        // Weights for the progress, by size: the tools and Gradle are small next to the packages.
        let steps: [(done: Bool, from: Double, to: Double, name: String)] = [
            (hasJDK, 0, 0.1, "Java"), (hasCommandLineTools, 0.1, 0.18, "Google's tools"), (hasGradle, 0.18, 0.26, "Gradle"),
            (hasPackages, 0.26, 0.96, "the Android platform and emulator"), (hasEmulator, 0.96, 1, "the emulator")]
        if !hasJDK {
            try await fetch(jdk, into: jdkFolder, archive: .tar, from: steps[0].from, to: steps[0].to, name: steps[0].name, progress: progress)
            // Temurin's archive holds one folder, jdk-17…/Contents/Home: that folder's contents are what's kept.
            try flatten(jdkFolder)
            guard await Subprocess.run(java, ["-version"], timeout: 60).ok else {
                try? fm.removeItem(at: jdkFolder)
                throw Failure(message: "Java didn't start on this Mac.")
            }
        }
        if !hasCommandLineTools {
            // Google's package manager wants itself at cmdline-tools/latest inside the SDK.
            let latest = sdkFolder.appendingPathComponent("cmdline-tools/latest")
            try fm.createDirectory(at: latest.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await fetch(commandLineTools, into: latest, archive: .zip, from: steps[1].from, to: steps[1].to, name: steps[1].name, progress: progress)
            try flatten(latest)
            for tool in ["sdkmanager", "avdmanager"] {
                try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: latest.appendingPathComponent("bin/\(tool)").path)
            }
        }
        if !hasGradle {
            try await fetch(gradleRelease, into: gradleFolder, archive: .zip, from: steps[2].from, to: steps[2].to, name: steps[2].name, progress: progress)
            try flatten(gradleFolder)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: gradle)
        }
        if !hasPackages {
            progress(steps[3].from, "Downloading \(steps[3].name)…")
            // Google's terms have to be accepted for each package; sdkmanager asks on its input.
            let accept = "/usr/bin/yes | \"$LAMP_SDKMANAGER\" --licenses > /dev/null 2>&1; \"$LAMP_SDKMANAGER\" --install " +
                packages.map { "\"\($0)\"" }.joined(separator: " ") + " 2>&1"
            var output: [String] = []
            let status = await Shell.run(accept, cwd: folder, env: environment.merging(["LAMP_SDKMANAGER": sdkmanager]) { $1 }, login: false) { line in
                output.append(line)
                // sdkmanager prints its own progress bar; the words beside it say which package.
                if line.contains("%"), let percent = Int(line.split(separator: "%").first?.split(separator: "[").last?.trimmingCharacters(in: .whitespaces) ?? "") {
                    progress(steps[3].from + (steps[3].to - steps[3].from) * Double(percent) / 100, "Downloading \(steps[3].name)…")
                }
            }
            guard status == 0, hasPackages else {
                throw Failure(message: "Google's tools couldn't download the Android platform.\n\n" + output.suffix(6).joined(separator: "\n"))
            }
        }
        if !hasEmulator {
            progress(steps[4].from, "Making the emulator…")
            try await Emulator.create()
        }
        progress(1, "Ready")
    }

    enum Archive { case zip, tar }

    /// Downloads one release into a staging folder beside `destination`, checks it, unpacks it and moves it into place.
    private static func fetch(_ release: Release, into destination: URL, archive: Archive, from: Double, to: Double, name: String,
                              progress: @escaping @Sendable (Double, String) -> Void) async throws {
        let fm = FileManager.default
        let staging = destination.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString)")
        try fm.createDirectory(at: staging, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: staging) }
        let download = staging.appendingPathComponent("download")
        progress(from, "Downloading \(name)…")
        try await Download.file(from: release.url, to: download, expected: release.size) { part in progress(from + (to - from) * part * 0.9, "Downloading \(name)…") }
        guard try sha256(of: download) == release.sha256 else {
            throw Failure(message: "The download of \(name) didn't match what its maker published, so Lamp didn't use it.")
        }
        progress(from + (to - from) * 0.9, "Unpacking \(name)…")
        let unpacked = staging.appendingPathComponent("unpacked")
        try fm.createDirectory(at: unpacked, withIntermediateDirectories: true)
        let result = archive == .tar
            ? await Subprocess.run("/usr/bin/tar", ["-xzf", download.path, "-C", unpacked.path], timeout: 600)
            : await Subprocess.run("/usr/bin/unzip", ["-q", download.path, "-d", unpacked.path], timeout: 600)
        guard result.ok else { throw Failure(message: "Lamp couldn't unpack \(name).") }
        if fm.fileExists(atPath: destination.path) { try fm.removeItem(at: destination) }
        try fm.moveItem(at: unpacked, to: destination)
    }

    /// An archive that holds one folder with everything in it: that folder's contents become `folder`'s own.
    private static func flatten(_ folder: URL) throws {
        let fm = FileManager.default
        let names = try fm.contentsOfDirectory(atPath: folder.path).filter { !$0.hasPrefix(".") }
        guard names.count == 1 else { return }
        let inner = folder.appendingPathComponent(names[0])
        var isFolder: ObjCBool = false
        guard fm.fileExists(atPath: inner.path, isDirectory: &isFolder), isFolder.boolValue else { return }
        for name in try fm.contentsOfDirectory(atPath: inner.path) {
            try fm.moveItem(at: inner.appendingPathComponent(name), to: folder.appendingPathComponent(name))
        }
        try fm.removeItem(at: inner)
    }

    private static func sha256(of file: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: file)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 4 << 20), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

// MARK: - adb

/// Google's bridge to a device: the emulator and the person's own phones and tablets alike, each by its serial.
enum Adb {
    static func run(_ arguments: [String], on serial: String? = nil, timeout: TimeInterval = 60) async -> Subprocess.Result {
        await Subprocess.run(AndroidTools.adb, (serial.map { ["-s", $0] } ?? []) + arguments, env: AndroidTools.environment,
                             mergeErrors: false, timeout: timeout)
    }

    /// The devices adb can see, each as the record Lamp keeps (`Device`): the emulator, and the person's phones and
    /// tablets plugged in or on the network, with what each still needs (debugging allowed to this Mac).
    static func devices() async -> [Device] {
        guard FileManager.default.isExecutableFile(atPath: AndroidTools.adb) else { return [] }
        let listing = await run(["devices", "-l"], timeout: 30).output
        var found: [Device] = []
        for line in listing.split(separator: "\n").dropFirst() {
            let parts = line.split(whereSeparator: \.isWhitespace).map(String.init)
            guard parts.count >= 2, !parts[0].isEmpty else { continue }
            let serial = parts[0], state = parts[1]
            var properties: [String: String] = [:]
            if state == "device" { properties = await getprop(on: serial) }
            found.append(Device.from(adb: serial, state: state, properties: properties))
        }
        return found.sorted { ($0.kind == .androidEmulator ? 0 : 1, $0.name) < ($1.kind == .androidEmulator ? 0 : 1, $1.name) }
    }

    /// The device's own description of itself: maker, model, Android version, and its screen.
    static func getprop(on serial: String) async -> [String: String] {
        var properties: [String: String] = [:]
        let keys = ["ro.product.manufacturer", "ro.product.model", "ro.product.device", "ro.build.version.release", "ro.build.version.sdk",
                    "ro.kernel.qemu", "ro.boot.qemu"]
        let shell = keys.map { "echo \($0)=$(getprop \($0))" }.joined(separator: ";") + ";wm size;wm density"
        for line in (await run(["shell", shell], on: serial, timeout: 20)).output.split(separator: "\n") {
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let equals = text.firstIndex(of: "=") {
                properties[String(text[..<equals])] = String(text[text.index(after: equals)...])
            } else if text.hasPrefix("Physical size:") {
                properties["size"] = String(text.dropFirst("Physical size:".count)).trimmingCharacters(in: .whitespaces)
            } else if text.hasPrefix("Physical density:") {
                properties["density"] = String(text.dropFirst("Physical density:".count)).trimmingCharacters(in: .whitespaces)
            }
        }
        return properties
    }

    /// What the person does about a device adb lists in a state it can't be used in.
    static func advice(for name: String, state: String) -> String {
        switch state {
        case "unauthorized": return "On \(name), tap Allow when it asks whether to allow USB debugging from this Mac (tick Always allow)."
        case "offline": return "\(name) isn't answering. Unplug it and plug it in again, and unlock it."
        default: return "On \(name), open Settings → About phone and tap Build number seven times to turn on Developer options, then in Settings → System → Developer options turn on USB debugging, and plug it in."
        }
    }

    /// Puts the app on the device in place of the copy there. One signed with another key (built by hand, or by
    /// an earlier Lamp) can't be updated: it's taken off first, and its data with it, since Android allows no other way.
    static func install(_ apk: URL, package: String, on serial: String) async throws {
        var result = await run(["install", "-r", "-t", apk.path], on: serial, timeout: 300)
        if !result.ok, (result.output + result.errors).contains("INSTALL_FAILED_UPDATE_INCOMPATIBLE") {
            _ = await run(["uninstall", package], on: serial, timeout: 60)
            result = await run(["install", "-r", "-t", apk.path], on: serial, timeout: 300)
        }
        guard result.ok else { throw AndroidTools.Failure(message: "Couldn't put the app on the device: \((result.output + result.errors).trimmed)") }
    }

    /// Starts the app's main activity afresh, and gives back its process id once it's running.
    static func launch(_ package: String, on serial: String) async throws -> Int32 {
        _ = await run(["shell", "am", "force-stop", package], on: serial, timeout: 30)
        let result = await run(["shell", "am", "start", "-W", "-n", "\(package)/.MainActivity"], on: serial, timeout: 60)
        guard result.ok, !result.output.contains("Error") else {
            throw AndroidTools.Failure(message: "The app didn't launch: \((result.output + result.errors).trimmed)")
        }
        for _ in 0..<20 {
            if let pid = await pid(of: package, on: serial) { return pid }
            try? await Task.sleep(for: .milliseconds(250))
        }
        throw AndroidTools.Failure(message: "The app started and quit at once.")
    }

    static func pid(of package: String, on serial: String) async -> Int32? {
        Int32((await run(["shell", "pidof", package], on: serial, timeout: 20)).output.trimmed)
    }

    static func stop(_ package: String, on serial: String) async {
        _ = await run(["shell", "am", "force-stop", package], on: serial, timeout: 30)
    }

    /// The app's own log lines, into `log` (a handle the caller opened on the app's folder's terms, `AppFolder`), as
    /// the simulator's output goes there: a process kept so a later launch or Stop can end it. It reads log records
    /// and doesn't end when the app does, so the app's life is watched apart from it.
    static func logcat(pid: Int32, on serial: String, log handle: FileHandle) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AndroidTools.adb)
        process.arguments = ["-s", serial, "logcat", "--pid=\(pid)", "-v", "brief", "-T", "1"]
        process.environment = ProcessInfo.processInfo.environment.merging(AndroidTools.environment) { $1 }
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// A picture of the screen as a PNG, scaled down by the device's density so a pixel in it is a point on the
    /// screen (as the simulator's pictures are). Made in Lamp's own temporary folder, for the caller to put in the
    /// app's folder on that folder's terms (`AppFolder`), never written there through a path a command may have linked.
    static func screenshot(on serial: String, density: Int?) async -> Data? {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-android-\(UUID().uuidString).png")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await Subprocess.run("/bin/sh", ["-c", "\"$LAMP_ADB\" -s \"$LAMP_SERIAL\" exec-out screencap -p > \"$LAMP_FILE\""],
                                          env: AndroidTools.environment.merging(["LAMP_ADB": AndroidTools.adb, "LAMP_SERIAL": serial, "LAMP_FILE": file.path]) { $1 },
                                          timeout: 60)
        guard result.ok, let image = NSImage(contentsOf: file), image.size.width > 0 else { return nil }
        let scale = Self.scale(density: density)
        if scale > 1, let width = (image.representations.first?.pixelsWide).map({ Double($0) / scale }) {
            _ = await Subprocess.run("/usr/bin/sips", ["--resampleWidth", String(Int(width.rounded())), file.path], timeout: 30)
        }
        return try? Data(contentsOf: file)
    }

    /// Android's own scale: 160 dpi is one pixel a point.
    static func scale(density: Int?) -> Double { density.map { max(1, Double($0) / 160) } ?? 1 }

    /// The screen as text (`Screen.text`), from the system's own view of what's on it.
    static func screen(on serial: String, density: Int?) async -> Screen? {
        var result = await run(["exec-out", "uiautomator", "dump", "/dev/tty"], on: serial, timeout: 60)
        // A screen asleep, or one the system is still laying out, answers nothing: woken and asked once more.
        if !result.output.contains("</hierarchy>") {
            _ = await run(["shell", "input", "keyevent", "KEYCODE_WAKEUP"], on: serial, timeout: 20)
            try? await Task.sleep(for: .seconds(1))
            result = await run(["exec-out", "uiautomator", "dump", "/dev/tty"], on: serial, timeout: 60)
        }
        guard let start = result.output.range(of: "<?xml"), let end = result.output.range(of: "</hierarchy>") else { return nil }
        let xml = String(result.output[start.lowerBound..<end.upperBound])
        return Screen.parse(xml, scale: scale(density: density))
    }

    /// What's on the screen, one item per thing the system names, in reading order, with its middle in points.
    struct Screen: Sendable {
        struct Item: Sendable {
            let kind: String      // "button", "text", "field", "switch", "checkbox", "image", "item"
            let name: String
            let value: String
            let frame: CGRect     // points
            let checked: Bool?
            let enabled: Bool
            let clickable: Bool
            let scrollable: Bool
            let focused: Bool
            var id = ""
        }
        var items: [Item]

        static func parse(_ xml: String, scale: Double) -> Screen? {
            let reader = Reader(scale: scale)
            let parser = XMLParser(data: Data(xml.utf8))
            parser.delegate = reader
            guard parser.parse() else { return nil }
            var counts: [String: Int] = [:]
            var items = reader.items
            for index in items.indices {
                let letter = String(items[index].kind.prefix(1))
                counts[letter, default: 0] += 1
                items[index].id = letter + String(counts[letter]!)
            }
            return Screen(items: items)
        }

        private final class Reader: NSObject, XMLParserDelegate {
            let scale: Double
            var items: [Item] = []
            init(scale: Double) { self.scale = scale }

            func parser(_ parser: XMLParser, didStartElement element: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
                guard element == "node" else { return }
                let text = attributes["text"] ?? "", description = attributes["content-desc"] ?? ""
                let className = (attributes["class"] ?? "").split(separator: ".").last.map(String.init) ?? ""
                let clickable = attributes["clickable"] == "true", scrollable = attributes["scrollable"] == "true"
                let checkable = attributes["checkable"] == "true"
                let kind: String
                switch className {
                case "EditText": kind = "field"
                case "Switch", "ToggleButton": kind = "switch"
                case "CheckBox", "RadioButton": kind = "checkbox"
                case "ImageView", "ImageButton": kind = clickable ? "button" : "image"
                case "Button": kind = "button"
                default: kind = checkable ? "checkbox" : clickable ? "button" : scrollable ? "list" : "text"
                }
                // Only what the person can see or act on: a layout with no words of its own is just structure.
                guard !text.isEmpty || !description.isEmpty || clickable || checkable || className == "EditText" || scrollable else { return }
                guard let bounds = attributes["bounds"] else { return }
                let numbers = bounds.split(whereSeparator: { "[],".contains($0) }).compactMap { Double($0) }
                guard numbers.count == 4 else { return }
                let frame = CGRect(x: numbers[0] / scale, y: numbers[1] / scale, width: (numbers[2] - numbers[0]) / scale, height: (numbers[3] - numbers[1]) / scale)
                guard frame.width > 0, frame.height > 0 else { return }
                let name = description.isEmpty ? (kind == "field" ? (attributes["hint"] ?? "") : text) : description
                let value = kind == "field" || !description.isEmpty ? text : ""
                items.append(Item(kind: kind, name: name, value: value == name ? "" : value, frame: frame,
                                  checked: checkable ? attributes["checked"] == "true" : nil,
                                  enabled: attributes["enabled"] != "false", clickable: clickable, scrollable: scrollable,
                                  focused: attributes["focused"] == "true"))
            }
        }

        /// The lines the agent reads, in the shape every device's screen text shares.
        var text: String {
            let limit = 120
            var lines = items.prefix(limit).map { item -> String in
                var line = "\(item.id) \(item.kind)"
                if !item.name.isEmpty { line += " \"\(item.name.replacingOccurrences(of: "\n", with: " ").prefix(80))\"" }
                if !item.value.isEmpty { line += " = \(item.value.replacingOccurrences(of: "\n", with: " ").prefix(60))" }
                if let checked = item.checked { line += checked ? ", on" : ", off" }
                if !item.enabled { line += ", dimmed" }
                return line + " @\(Int(item.frame.midX.rounded())),\(Int(item.frame.midY.rounded())) \(Int(item.frame.width.rounded()))x\(Int(item.frame.height.rounded()))"
            }
            if items.count > limit { lines.append("… and \(items.count - limit) more") }
            return "The screen as text, in reading order. Each line is a thing's id, what it is, its name, \"= \" what it holds, " +
                "then @x,y (its middle in the picture) and its size. Act on a thing with `target` set to its id or exact name; " +
                "x and y are for what isn't listed:\n" + lines.joined(separator: "\n")
        }

        /// The item an action names: its id, or its exact name.
        func find(_ target: String) -> Item? {
            items.first { $0.id == target } ?? items.first { $0.name == target } ?? items.first { $0.name.caseInsensitiveCompare(target) == .orderedSame }
        }
    }

    // MARK: Actions

    /// Carries out `use_app`'s actions on the device, one after another, with the screen read again after each so
    /// the next can name what the last one showed. The report says what each landed on. `stillMine` is asked before
    /// each action: false ends the batch (the app closed, the turn was stopped).
    static func perform(_ actions: [Simulator.Driver.Action], on serial: String, density: Int?, screen first: Screen?,
                        stillMine: @escaping @MainActor () async -> Bool) async -> String {
        var screen = first
        var report: [String] = []
        let scale = scale(density: density)
        func point(_ action: Simulator.Driver.Action) -> (CGPoint, String)? {
            if let target = action.target {
                guard let item = screen?.find(target) else { return nil }
                return (CGPoint(x: item.frame.midX, y: item.frame.midY), "\(item.kind) \"\(item.name)\"")
            }
            guard let x = action.x, let y = action.y else { return nil }
            return (CGPoint(x: x, y: y), "the point \(Int(x)),\(Int(y))")
        }
        func pixels(_ point: CGPoint) -> (Int, Int) { (Int((point.x * scale).rounded()), Int((point.y * scale).rounded())) }
        for (index, action) in actions.enumerated() {
            guard await stillMine() else { report.append("Stopped before action \(index + 1)."); break }
            switch action.action {
            case "click", "tap", "left_click", "double_click", "right_click", "long_press":
                guard let (at, what) = point(action) else { report.append("\(index + 1). Nothing on screen matches \"\(action.target ?? "")\"."); continue }
                let (x, y) = pixels(at)
                if action.action == "right_click" || action.action == "long_press" {
                    _ = await run(["shell", "input", "swipe", "\(x)", "\(y)", "\(x)", "\(y)", "800"], on: serial, timeout: 30)
                    report.append("\(index + 1). Long-pressed \(what).")
                } else {
                    _ = await run(["shell", "input", "tap", "\(x)", "\(y)"], on: serial, timeout: 30)
                    if action.action == "double_click" { _ = await run(["shell", "input", "tap", "\(x)", "\(y)"], on: serial, timeout: 30) }
                    report.append("\(index + 1). Tapped \(what).")
                }
            case "type":
                guard let text = action.text else { report.append("\(index + 1). type needs text."); continue }
                // The field typed into: the target, else the one with the keyboard, read before anything is sent.
                let field = action.target.flatMap { screen?.find($0) } ?? screen?.items.first { $0.kind == "field" && $0.focused }
                if let (at, _) = point(action) {
                    let (x, y) = pixels(at)
                    _ = await run(["shell", "input", "tap", "\(x)", "\(y)"], on: serial, timeout: 30)
                    try? await Task.sleep(for: .milliseconds(300))
                }
                // In place of what the field held, as on the other devices: everything selected and deleted where the
                // device takes a key combination (Android 11 and later); on an older one, to the end and back over
                // every character the field was seen to hold, in calls of a hundred keys.
                _ = await run(["shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A"], on: serial, timeout: 30)
                _ = await run(["shell", "input", "keyevent", "KEYCODE_DEL"], on: serial, timeout: 30)
                var remaining = (field?.value.count ?? 0) + 2
                if let field, (await Self.screen(on: serial, density: density))?.find(field.id)?.value.isEmpty == false, remaining > 0 {
                    _ = await run(["shell", "input", "keyevent", "KEYCODE_MOVE_END"], on: serial, timeout: 30)
                    while remaining > 0 {
                        let batch = min(remaining, 100)
                        _ = await run(["shell", "input", "keyevent"] + Array(repeating: "KEYCODE_DEL", count: batch), on: serial, timeout: 60)
                        remaining -= batch
                    }
                }
                // `input text` takes no spaces and reads % and some punctuation its own way: each is escaped as adb's shell wants.
                let escaped = text.map { character -> String in
                    switch character {
                    case " ": return "%s"
                    case "\n": return "\\n"
                    case "'", "\"", "\\", "(", ")", "<", ">", "|", ";", "&", "*", "~", "`", "$", "%": return "\\\(character)"
                    default: return String(character)
                    }
                }.joined()
                _ = await run(["shell", "input", "text", escaped], on: serial, timeout: 60)
                report.append("\(index + 1). Typed \"\(text)\".")
            case "key":
                let keys = ["return": "KEYCODE_ENTER", "enter": "KEYCODE_ENTER", "escape": "KEYCODE_BACK", "back": "KEYCODE_BACK",
                            "home": "KEYCODE_HOME", "delete": "KEYCODE_DEL", "backspace": "KEYCODE_DEL", "tab": "KEYCODE_TAB",
                            "space": "KEYCODE_SPACE", "up": "KEYCODE_DPAD_UP", "down": "KEYCODE_DPAD_DOWN", "left": "KEYCODE_DPAD_LEFT", "right": "KEYCODE_DPAD_RIGHT"]
                guard let key = action.key?.lowercased(), let code = keys[key] ?? (key.hasPrefix("keycode_") ? key.uppercased() : nil) else {
                    report.append("\(index + 1). Unknown key \"\(action.key ?? "")\"; the keys are \(keys.keys.sorted().joined(separator: ", ")).")
                    continue
                }
                _ = await run(["shell", "input", "keyevent", code], on: serial, timeout: 30)
                report.append("\(index + 1). Pressed \(key).")
            case "scroll", "swipe":
                let (from, what) = point(action) ?? (CGPoint(x: 540 / scale, y: 1200 / scale), "the middle of the screen")
                let distance = action.amount ?? (action.action == "scroll" ? 400 : 300)
                var to = from
                // A scroll's direction is where the content goes; a swipe's is where the finger goes.
                switch (action.direction ?? "down").lowercased() {
                case "up": to.y += action.action == "scroll" ? distance : -distance
                case "down": to.y -= action.action == "scroll" ? distance : -distance
                case "left": to.x += action.action == "scroll" ? distance : -distance
                case "right": to.x -= action.action == "scroll" ? distance : -distance
                default: break
                }
                let (x1, y1) = pixels(from), (x2, y2) = pixels(to)
                _ = await run(["shell", "input", "swipe", "\(x1)", "\(y1)", "\(x2)", "\(y2)", "300"], on: serial, timeout: 30)
                report.append("\(index + 1). \(action.action == "scroll" ? "Scrolled" : "Swiped") \(action.direction ?? "down") at \(what).")
                if action.action == "swipe", let item = action.item {
                    try? await Task.sleep(for: .milliseconds(500))
                    screen = await Self.screen(on: serial, density: density)
                    if let found = screen?.find(item) {
                        let (x, y) = pixels(CGPoint(x: found.frame.midX, y: found.frame.midY))
                        _ = await run(["shell", "input", "tap", "\(x)", "\(y)"], on: serial, timeout: 30)
                        report.append("\(index + 1). Then tapped \"\(found.name)\".")
                    } else {
                        report.append("\(index + 1). The swipe uncovered nothing named \"\(item)\".")
                    }
                }
            case "wait":
                try? await Task.sleep(for: .seconds(min(action.amount ?? 1, 10)))
                report.append("\(index + 1). Waited.")
            default:
                report.append("\(index + 1). Unknown action \"\(action.action)\".")
                continue
            }
            try? await Task.sleep(for: .milliseconds(600))
            screen = await Self.screen(on: serial, density: density)
        }
        return report.joined(separator: "\n")
    }
}

// MARK: - The emulator

/// The Android phone on this Mac's screen: one emulator Lamp makes from the system image it downloaded, started
/// by Lamp as itself, which adb then lists like a device of the person's.
enum Emulator {
    /// Makes Lamp's emulator from the downloaded system image, as a recent Pixel.
    static func create() async throws {
        let result = await Subprocess.run("/bin/sh", ["-c", "echo no | \"$LAMP_AVDMANAGER\" create avd -n \"$LAMP_AVD\" -k \"$LAMP_IMAGE\" -d \"$LAMP_PROFILE\" --force 2>&1"],
                                          env: AndroidTools.environment.merging(["LAMP_AVDMANAGER": AndroidTools.avdmanager, "LAMP_AVD": AndroidTools.avdName.replacingOccurrences(of: " ", with: "_"),
                                                                                 "LAMP_IMAGE": AndroidTools.systemImage, "LAMP_PROFILE": AndroidTools.avdProfile]) { $1 },
                                          timeout: 120)
        guard result.ok, AndroidTools.hasEmulator else { throw AndroidTools.Failure(message: "Lamp couldn't make the emulator.\n\n" + result.output.trimmed) }
    }

    /// The running emulator's serial, as adb lists it, or nil when none is running.
    static func running() async -> String? {
        (await Adb.devices()).first { $0.kind == .androidEmulator && $0.adbState == "device" }?.udid
    }

    /// Starts Lamp's emulator when it isn't running, waits for Android to boot, and gives back its serial. The
    /// emulator is a window of its own on the Mac, which `show` says whether to bring forward.
    static func start(show: Bool) async throws -> String {
        if let serial = await running() {
            if show { await bringForward() }
            return serial
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AndroidTools.emulator)
        process.arguments = ["-avd", AndroidTools.avdName.replacingOccurrences(of: " ", with: "_"), "-no-boot-anim", "-netdelay", "none", "-netspeed", "full"]
        process.environment = ProcessInfo.processInfo.environment.merging(AndroidTools.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Booting takes half a minute the first time, a few seconds from a snapshot after that.
        for _ in 0..<120 {
            try await Task.sleep(for: .seconds(1))
            guard process.isRunning else { throw AndroidTools.Failure(message: "The emulator quit while starting.") }
            if let serial = await running() {
                let booted = await Adb.run(["shell", "getprop", "sys.boot_completed"], on: serial, timeout: 10).output.trimmed
                if booted == "1" {
                    if !show { await putBehind() }
                    return serial
                }
            }
        }
        throw AndroidTools.Failure(message: "The emulator didn't finish starting.")
    }

    private static func app() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { $0.executableURL?.path.hasPrefix(AndroidTools.sdkFolder.appendingPathComponent("emulator").path) == true }
    }
    static func bringForward() async { app()?.activate() }
    static func putBehind() async { app()?.hide() }
    static var isRunning: Bool { app() != nil }
}
