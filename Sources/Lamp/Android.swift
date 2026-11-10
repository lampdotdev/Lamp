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
    /// Settable so a test can point every check at a folder of its own, never at the real tools.
    nonisolated(unsafe) static var folder = Edition.sharedDeveloperFolder.appendingPathComponent("Android")
    static var jdkFolder: URL { folder.appendingPathComponent("jdk") }
    static var sdkFolder: URL { folder.appendingPathComponent("sdk") }
    static var gradleFolder: URL { folder.appendingPathComponent("gradle-\(gradleVersion)") }
    /// Gradle's own cache (its daemons' records, every dependency it fetched): shared by every app's build, in the
    /// caches folder the sandbox opens for writing.
    static let gradleUserHome = Edition.sharedCachesFolder.appendingPathComponent("gradle")
    /// What adb and the emulator keep (adb's key, the emulator's settings) and the emulators Lamp made: Lamp's own,
    /// since Lamp runs both as itself.
    static let userHome = Edition.supportFolder.appendingPathComponent("Android/home")
    nonisolated(unsafe) static var avdHome = Edition.supportFolder.appendingPathComponent("Android/avd")

    static var javaHome: String { jdkFolder.appendingPathComponent("Contents/Home").path }
    static var java: String { javaHome + "/bin/java" }
    static var adb: String { sdkFolder.appendingPathComponent("platform-tools/adb").path }
    static var emulator: String { sdkFolder.appendingPathComponent("emulator/emulator").path }
    static var sdkmanager: String { sdkFolder.appendingPathComponent("cmdline-tools/latest/bin/sdkmanager").path }
    static var avdmanager: String { sdkFolder.appendingPathComponent("cmdline-tools/latest/bin/avdmanager").path }
    static var gradle: String { gradleFolder.appendingPathComponent("bin/gradle").path }

    /// What every command of Google's or Gradle's that Lamp runs as itself is run with. adb's server is Lamp's own,
    /// on a port of its own (`Edition.androidPorts`), which adb starts there on the first command. It doesn't look
    /// for emulators on adb's usual ports (a maximum below the first): those are the person's, or another Lamp's,
    /// which their own server holds. It learns of Lamp's from the emulator as it boots, or from Lamp
    /// (`Emulator.register`) when the server started after it.
    static var environment: [String: String] {
        ["JAVA_HOME": javaHome, "ANDROID_HOME": sdkFolder.path, "ANDROID_SDK_ROOT": sdkFolder.path,
         "ANDROID_USER_HOME": userHome.path, "ANDROID_AVD_HOME": avdHome.path, "GRADLE_USER_HOME": gradleUserHome.path,
         "LAMP_GRADLE": gradle, "ANDROID_ADB_SERVER_PORT": String(Edition.androidPorts.server),
         "ADB_LOCAL_TRANSPORT_MAX_PORT": "5554"]
    }

    /// The same for a build, which runs in the app's sandbox: its Android home is in the caches folder the sandbox
    /// opens, since the build writes there (the debug signing key every debug build is signed with), where Lamp's
    /// own home (adb's key to the person's devices) stays closed to it. Nothing in a build needs adb, and the
    /// sandbox refuses Lamp's server anyway, so its port isn't passed on.
    static var buildEnvironment: [String: String] {
        var env = environment
        env["ANDROID_USER_HOME"] = Edition.sharedCachesFolder.appendingPathComponent("android-home").path
        env["ANDROID_ADB_SERVER_PORT"] = nil
        env["ADB_LOCAL_TRANSPORT_MAX_PORT"] = nil
        return env
    }

    // MARK: Versions

    /// What's downloaded, pinned so every Lamp builds the same way; moved on purpose, with a build tried first.
    static let gradleVersion = "9.1.0"
    static let buildTools = "36.0.0"
    static let platformLevel = 36
    static let systemImage = "system-images;android-\(platformLevel);google_apis;\(isArm ? "arm64-v8a" : "x86_64")"
    /// What a build and adb need, for a device of the person's; and what the emulator needs besides.
    static let buildPackages = ["platform-tools", "build-tools;\(buildTools)", "platforms;android-\(platformLevel)"]
    static let emulatorPackages = ["emulator", systemImage]
    /// The emulator Lamp makes: one phone, named so Try On can say which.
    static let avdName = "Lamp Phone"
    static let avdProfile = "pixel_9"
    /// An Android TV app's emulator: a 1080p TV, made from its own system image the first time one is wanted, since most
    /// people never make a TV app and the image is about a gigabyte.
    static let tvAVDName = "Lamp TV"
    static let tvProfile = "tv_1080p"
    static let tvSystemImage = "system-images;android-\(platformLevel);android-tv;\(isArm ? "arm64-v8a" : "x86_64")"
    static var hasTVImage: Bool {
        FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("system-images/android-\(platformLevel)/android-tv/\(isArm ? "arm64-v8a" : "x86_64")/system.img").path)
    }

    private static var isArm: Bool {
        #if arch(arm64)
        true
        #else
        false
        #endif
    }

    /// One download: where it comes from and what it must hash to, as its maker publishes it.

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
    static var hasBuildPackages: Bool {
        FileManager.default.isExecutableFile(atPath: adb)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("build-tools/\(buildTools)/aapt2").path)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("platforms/android-\(platformLevel)/android.jar").path)
    }
    static var hasEmulatorPackages: Bool {
        FileManager.default.isExecutableFile(atPath: emulator)
            && FileManager.default.fileExists(atPath: sdkFolder.appendingPathComponent("system-images/android-\(platformLevel)/google_apis/\(isArm ? "arm64-v8a" : "x86_64")/system.img").path)
    }
    static var hasEmulator: Bool { has(.phone) }
    static func has(_ kind: Emulator.Kind) -> Bool { FileManager.default.fileExists(atPath: avdHome.appendingPathComponent("\(kind.avd).avd/config.ini").path) }
    /// Everything a build and adb need: all a device of the person's asks of this Mac.
    static var hasBuildTools: Bool { hasJDK && hasCommandLineTools && hasGradle && hasBuildPackages }
    /// That, and the emulator.
    static var isReady: Bool { hasBuildTools && hasEmulatorPackages && hasEmulator }

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
    /// download, which `install` does whole), the emulator Lamp makes from them, or instead the person's own device
    /// when one is chosen (`serial`), which must be plugged in or on the network with debugging allowed to this Mac.
    /// A device needs no emulator, so neither its download nor its making is asked for.
    static func check(device serial: String? = nil, confirmed: Set<String> = []) async -> Report {
        var report = Report()
        guard hasBuildTools, serial != nil || hasEmulatorPackages else {
            report.issue = Issue(step: .tools, title: "Download Android's tools",
                                 message: "Lamp makes Android apps with Google's free tools, and they aren't on this Mac yet. Click Download: "
                                    + (serial == nil ? "it's about 2 GB, so it can take a while." : "it's under 1 GB, so it can take a few minutes.")
                                    + " Nothing else on your Mac changes.", action: .download)
            return report
        }
        report.passed.append(.tools)
        if let serial {
            let devices = await Adb.devices()
            let device: Device
            switch AndroidTVs.choice(serial, among: devices, confirmed: confirmed) {
            case .use(let found), .adopt(let found):
                device = found
            case .confirm(let other):
                // A choice made over Wi‑Fi names a place, not a device: whatever answers there now is the person's to confirm.
                report.issue = Issue(step: .device, title: "Choose \(other.name) again",
                                     message: "To be sure it's the device you chose, choose \(other.name) under Try On, then press Play.", action: .retry)
                return report
            case .missing:
                // A choice made over Wi‑Fi names the address and port it had then, which may have changed since.
                report.issue = serial.contains(":") || AndroidTVs.isMDNS(serial)
                    ? Issue(step: .device, title: "Choose your device again",
                            message: "Lamp can't see it at the address it had. Turn its debugging back on, then choose it again under Try On. Then click Check Again.", action: .retry)
                    : Issue(step: .device, title: "Connect your Android device",
                            message: "Lamp can't see it. Plug it into this Mac with its cable and unlock it, or for a TV on your Wi‑Fi, turn it on and connect it with Connect Over Wi‑Fi under Try On. Allow debugging when it asks, then click Check Again.", action: .retry)
                return report
            }
            if case .needs(let step) = device.setup() {
                report.issue = Issue(step: .device, title: step,
                                     message: Adb.advice(for: device) + " Then click Check Again.", action: .retry)
                return report
            }
            report.passed.append(.device)
        } else {
            guard hasEmulator else {
                report.issue = Issue(step: .emulator, title: "Set up the emulator",
                                     message: "The emulator is an Android phone on your Mac's screen, where Lamp tries your app. Click Download and Lamp will make one.", action: .download)
                return report
            }
            report.passed.append(.emulator)
        }
        return report
    }

    // MARK: Installing

    /// The tools list, as lamp's command line is handed it (`androidInstall` in cli/calls.mjs): what's downloaded and
    /// from where, with each archive's checksum, the packages, and the emulators' images and names. Written out for the
    /// command line's own copy too (`CLIFilesTests`, cli/lamps/android-host/tools.json).
    static var spec: [String: Any] {
        func release(_ release: Release) -> [String: Any] { ["url": release.url.absoluteString, "sha256": release.sha256, "size": release.size] }
        return ["arch": isArm ? "arm64" : "x86_64", "gradle": gradleVersion, "buildTools": buildTools, "platform": platformLevel,
                "jdk": release(jdk), "commandLineTools": release(commandLineTools), "gradleRelease": release(gradleRelease),
                "buildPackages": buildPackages, "emulatorPackages": emulatorPackages,
                "phone": ["avd": Emulator.Kind.phone.avd, "image": Emulator.Kind.phone.image, "profile": Emulator.Kind.phone.profile],
                "tv": ["avd": Emulator.Kind.tv.avd, "image": Emulator.Kind.tv.image, "profile": Emulator.Kind.tv.profile],
                "apk": "app/build/outputs/apk/debug/app-debug.apk", "banner": GameAndroid.banner, "folder": GameAndroid.folder]
    }

    /// What lamp's command line is told of this Lamp's Android: the tools list, the folder they go in, its own folders
    /// for adb's home and the emulators, and what its tools run with.
    static var lamp: [String: Any] {
        ["spec": spec, "tools": folder.path, "userHome": userHome.path, "avdHome": avdHome.path, "env": environment]
    }

    /// Downloads and puts in place whatever `check` found missing, in order, saying how far it is (0…1) and what
    /// it's doing: lamp's command line's (`androidInstall`), each archive checked against the checksum its maker
    /// publishes and unpacked beside its place before it's moved in whole, then Google's packages through its own
    /// package manager. `emulator` false: for a device of the person's, which needs no emulator, so its download and its
    /// making are left for when one is chosen.
    static func install(emulator: Bool = true, progress: @escaping @Sendable (Double, String) -> Void) async throws {
        try FileManager.default.createDirectory(at: avdHome, withIntermediateDirectories: true)
        // What it's doing and how far it is come apart from the command line: each is shown with the latest of the other.
        final class Doing: @unchecked Sendable { var words = "Downloading Android's tools…"; var part = 0.0 }
        let doing = Doing()
        do {
            _ = try await LampCLI.ask("androidInstall", ["lamp": lamp, "emulator": emulator]) { event in
                if let said = event["said"] as? String { doing.words = said }
                if let part = (event["part"] as? NSNumber)?.doubleValue { doing.part = part }
                progress(doing.part, doing.words)
            }
            if emulator, !hasEmulator {
                progress(0.96, "Making the emulator…")
                try await Emulator.create()
            }
        } catch let failure as LampCLI.Failure {
            throw Failure(message: failure.message)
        }
        progress(1, "Ready")
    }

}

/// One download: where it comes from and what it must hash to, as its maker publishes it.
extension AndroidTools {
    struct Release {
        let url: URL
        let sha256: String
        let size: Int64
    }
}

// MARK: - adb

/// Google's bridge to a device: the emulator and the person's own phones and tablets alike, each by its serial. Every
/// command goes through lamp's command line (cli/android.mjs, the same code lamp uses), which runs Lamp's own adb server
/// with Lamp's key and reads what adb says; what a device is to Lamp (a TV's record, which device Try On means), the
/// words for the person, and the app's log stream are here.
enum Adb {
    /// A call about adb, with this Lamp's tools list, folders and environment.
    private static func ask(_ name: String, _ given: [String: Any] = [:]) async throws -> [String: Any] {
        var all = given
        all["lamp"] = AndroidTools.lamp
        return try await LampCLI.ask(name, all)
    }

    /// One adb command (its arguments after the serial), with `input` on adb's input when given.
    static func run(_ arguments: [String], on serial: String? = nil, timeout: TimeInterval = 60, input: String? = nil) async -> Subprocess.Result {
        var given: [String: Any] = ["args": arguments, "timeout": timeout]
        if let serial { given["serial"] = serial }
        if let input { given["input"] = input }
        guard let done = try? await ask("adb", given) else {
            return Subprocess.Result(status: -1, output: "", errors: "Lamp's own tools didn't answer.", timedOut: false)
        }
        return Subprocess.Result(status: done["ok"] as? Bool == true ? 0 : 1, output: done["out"] as? String ?? "",
                                 errors: done["err"] as? String ?? "", timedOut: done["timedOut"] as? Bool ?? false)
    }

    /// Ends Lamp's adb server as Lamp quits, so nothing of Lamp's is left listening. Only Lamp's: the person's own
    /// server, on adb's usual port, is theirs. The emulator goes on running, and Lamp's next server finds it.
    static func stopServer() {
        guard FileManager.default.isExecutableFile(atPath: AndroidTools.adb) else { return }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AndroidTools.adb)
        process.arguments = ["kill-server"]
        process.environment = ProcessInfo.processInfo.environment.merging(AndroidTools.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        guard (try? process.run()) != nil else { return }
        // A server that isn't running answers at once; one that is, within a moment. Quitting doesn't wait longer.
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning, Date() < deadline { usleep(20_000) }
        if process.isRunning { process.terminate() }
    }

    /// The devices adb can see, each as the record Lamp keeps (`Device`): the emulator, and the person's phones and
    /// tablets plugged in or on the network, with what each still needs (debugging allowed to this Mac).
    static func devices() async -> [Device] {
        guard FileManager.default.isExecutableFile(atPath: AndroidTools.adb), var done = try? await ask("androidDevices") else { return [] }
        var services = AndroidTVs.services(done["services"] as? String ?? "")
        if await AndroidTVs.reconnect(listed: rows(done).map(\.serial), services: services, kept: AndroidTVs.kept()),
           let again = try? await ask("androidDevices") {
            done = again
            services = AndroidTVs.services(done["services"] as? String ?? "")
        }
        let read = rows(done).map { Device.from(adb: $0.serial, state: $0.state, properties: $0.properties) }
        return sorted(AndroidTVs.resolve(read, services: services))
    }

    private static func rows(_ done: [String: Any]) -> [(serial: String, state: String, properties: [String: String])] {
        (done["rows"] as? [[String: Any]] ?? []).compactMap { row in
            guard let serial = row["serial"] as? String, let state = row["state"] as? String else { return nil }
            return (serial, state, row["properties"] as? [String: String] ?? [:])
        }
    }

    /// Each line of `adb devices -l`: the selector adb takes with `-s`, and its state, as lamp's command line reads it.
    static func listed(_ listing: String) async -> [(serial: String, state: String)] {
        rows((try? await ask("androidRows", ["listing": listing])) ?? [:]).map { ($0.serial, $0.state) }
    }

    /// The devices in adb's listing, with what each said of itself (by selector) and what adb's own search sees on the
    /// network (`adb mdns services`). Nothing is kept: this is the look alone, as a TV met for the first time.
    static func devices(listing: String, services: String, properties: [String: [String: String]]) async -> [Device] {
        let read = await listed(listing).map { Device.from(adb: $0.serial, state: $0.state, properties: properties[$0.serial] ?? [:]) }
        return sorted(AndroidTVs.merge(read, services: AndroidTVs.services(services), kept: []).devices)
    }

    private static func sorted(_ found: [Device]) -> [Device] {
        found.sorted { ($0.kind == .androidEmulator ? 0 : 1, $0.name) < ($1.kind == .androidEmulator ? 0 : 1, $1.name) }
    }

    /// Connects adb to a device listening at "address:port". True only once adb says it's connected; whether this Mac
    /// is allowed on it is the listing's to say.
    static func connect(target: String) async -> Bool {
        (try? await ask("androidConnect", ["target": target]))?["connected"] as? Bool ?? false
    }

    /// The device's own description of itself: maker, model, Android version, and its screen.
    static func getprop(on serial: String) async -> [String: String] {
        (try? await ask("androidProperties", ["serial": serial]))?["properties"] as? [String: String] ?? [:]
    }

    /// What the person does about a device adb lists in a state it can't be used in.
    static func advice(for device: Device) -> String {
        let name = device.name
        if device.features.contains("tv"), device.reach == .network {
            switch device.adbState {
            case "away" where device.transport == .legacy:
                return "Lamp can't reach \(name). On it, turn on ADB debugging (Settings → My Fire TV → Developer options), and check it's on this Mac's Wi‑Fi."
            case "away":
                return "Lamp can't reach \(name). On it, turn Wireless debugging back on (Settings → System → Developer options), and check it's on this Mac's Wi‑Fi."
            case "unsure":
                return "Lamp sees more than one device answering as \(name). Check Again in a moment, or choose it again under Try On."
            case "unauthorized":
                return "On \(name), choose Allow when it asks whether to allow debugging from this Mac (tick Always allow). If it doesn't ask, connect it again from Try On with its pairing code."
            default:
                return "\(name) isn't answering. Check it's on and on this Mac's Wi‑Fi."
            }
        }
        return advice(for: name, state: device.adbState)
    }

    static func advice(for name: String, state: String) -> String {
        switch state {
        case "unauthorized": return "On \(name), choose Allow when it asks whether to allow debugging from this Mac (tick Always allow)."
        case "offline": return "\(name) isn't answering. Unplug it and plug it in again, and unlock it."
        default: return "On \(name), open Settings → About phone and tap Build number seven times to turn on Developer options, then in Settings → System → Developer options turn on USB debugging, and plug it in."
        }
    }

    /// Puts the app on the device in place of the copy there. One signed with another key (built by hand, or by
    /// an earlier Lamp) can't be updated: it's taken off first, and its data with it, since Android allows no other way.
    static func install(_ apk: URL, package: String, on serial: String) async throws {
        do { _ = try await ask("androidInstallApp", ["serial": serial, "apk": apk.path, "package": package]) }
        catch { throw AndroidTools.Failure(message: error.localizedDescription) }
    }

    /// Writes what the app is told about itself and Lamp (`Template.androidInstallValues`: its token among them) into
    /// its own storage on the device, as Lamp writes a Mac app's into its installed copy: on adb's input, never in a
    /// command's arguments, and through `run-as`, so it lands in a folder only the app reads. A failure is logged, not
    /// thrown: the app opens, and its first call to Lamp says it can't reach it.
    static func tellApp(_ values: [String: Any], package: String, on serial: String) async {
        let problem = (try? await ask("androidTell", ["serial": serial, "package": package, "values": values]))?["problem"] as? String
        if let problem { NSLog("Lamp couldn't tell \(package) where Lamp is: \(problem)") }
    }

    /// Asks the running app to save where the person is (`LampState` in LampSupport.kt), so the copy installed next
    /// opens there. Sent by adb's shell, the only sender the app takes it from; true once the app says it saved.
    static func saveState(_ package: String, on serial: String) async -> Bool {
        (try? await ask("androidSaveState", ["serial": serial, "package": package]))?["saved"] as? Bool ?? false
    }

    /// Starts the app's main activity afresh, and gives back its process id once it's running.
    static func launch(_ package: String, on serial: String) async throws -> Int32 {
        do {
            guard let pid = (try await ask("androidLaunch", ["serial": serial, "package": package]))["pid"] as? Int else {
                throw AndroidTools.Failure(message: "The app started and quit at once.")
            }
            return Int32(pid)
        } catch let failure as LampCLI.Failure {
            throw AndroidTools.Failure(message: failure.message)
        }
    }

    /// Whether the process launched as `pid` is gone within its first two seconds.
    static func quitSoon(_ pid: Int32, package: String, on serial: String) async -> Bool {
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(250))
            if await self.pid(of: package, on: serial) != pid { return true }
        }
        return false
    }

    static func pid(of package: String, on serial: String) async -> Int32? {
        if case .running(let pid) = await process(of: package, on: serial) { return pid }
        return nil
    }

    /// What `pidof` said of an app: its process, none, or nothing at all because the device didn't answer.
    enum AppProcess: Equatable { case running(Int32), gone, unreachable }

    private static func process(_ done: [String: Any]?) -> AppProcess {
        switch done?["state"] as? String {
        case "running": (done?["pid"] as? Int).map { .running(Int32($0)) } ?? .gone
        case "gone": .gone
        default: .unreachable
        }
    }

    /// adb itself says when it couldn't reach the device ("device '…' not found", "device offline", "no devices"), and a
    /// command that ran out of time says nothing: neither is the app having quit (read by lamp's command line).
    static func process(of package: String, on serial: String, said result: Subprocess.Result) async -> AppProcess {
        process(try? await ask("androidProcess", ["said": ["ok": result.ok, "out": result.output, "err": result.errors, "timedOut": result.timedOut]]))
    }

    static func process(of package: String, on serial: String) async -> AppProcess {
        process(try? await ask("androidProcess", ["serial": serial, "package": package]))
    }

    /// The serial a device reads, to check a selector still reaches the device it did.
    static func serialNumber(on serial: String) async -> String? {
        let result = await run(["shell", "getprop", "ro.serialno"], on: serial, timeout: 10)
        let value = result.output.trimmed
        return result.ok && !value.isEmpty ? value : nil
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
    /// screen (as the simulator's pictures are), by lamp's command line.
    static func screenshot(on serial: String, density: Int?) async -> Data? {
        var given: [String: Any] = ["serial": serial]
        if let density { given["density"] = density }
        return ((try? await ask("androidScreenshot", given))?["png"] as? String).flatMap { Data(base64Encoded: $0) }
    }

    /// The screen's size in pixels as the system draws it now: a size set with `wm size` over the panel's own.
    static func displaySize(on serial: String) async -> CGSize? {
        guard let size = (try? await ask("androidDisplaySize", ["serial": serial]))?["size"] as? [String: Any],
              let width = (size["width"] as? NSNumber)?.doubleValue, let height = (size["height"] as? NSNumber)?.doubleValue else { return nil }
        return CGSize(width: width, height: height)
    }

    /// Android's own scale: 160 dpi is one pixel a point.
    static func scale(density: Int?) -> Double { density.map { max(1, Double($0) / 160) } ?? 1 }

    /// The screen as text (`Screen.text`), from the system's own view of what's on it.
    /// `mayWake` is asked before the key that wakes a screen asleep: false once the person has taken the app back.
    static func screen(on serial: String, density: Int?, mayWake: @escaping @MainActor () -> Bool = { true }) async -> Screen? {
        await screen(density: density, adb: { await run($0, on: serial, timeout: $1) }, input: { arguments, timeout in
            guard await mayWake() else { return false }
            _ = await run(arguments, on: serial, timeout: timeout)
            return true
        })
    }

    /// Commands for one device: adb's arguments after the serial, and how long to give them.
    typealias Commands = ([String], TimeInterval) async -> Subprocess.Result

    /// `input` sends the key that wakes the screen, which is input like any tap: while Lamp tries the app it's the one
    /// way input goes (`perform`'s `send`), and false means the app isn't Lamp's to touch any more.
    static func screen(density: Int?, adb: Commands, input: (([String], TimeInterval) async -> Bool)? = nil) async -> Screen? {
        var result = await adb(["exec-out", "uiautomator", "dump", "/dev/tty"], 60)
        // A screen asleep, or one the system is still laying out, answers nothing: woken and asked once more.
        if !result.output.contains("</hierarchy>") {
            let wake = ["shell", "input", "keyevent", "KEYCODE_WAKEUP"]
            if let input {
                guard await input(wake, 20) else { return nil }
            } else {
                _ = await adb(wake, 20)
            }
            try? await Task.sleep(for: .seconds(1))
            result = await adb(["exec-out", "uiautomator", "dump", "/dev/tty"], 60)
        }
        return await Screen.parse(result.output, scale: scale(density: density))
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

        /// The screen from what `uiautomator dump` said, read by lamp's command line (`screenItems` in cli/android.mjs):
        /// one item per thing the person can see or act on, its frame in points at `scale`; nil when it held no dump.
        static func parse(_ said: String, scale: Double) async -> Screen? {
            guard let items = (try? await LampCLI.ask("androidScreenItems", ["said": said, "scale": scale]))?["items"] as? [[String: Any]] else { return nil }
            return Screen(items: items.compactMap { item in
                guard let id = item["id"] as? String, let kind = item["kind"] as? String, let frame = item["frame"] as? [String: Any],
                      let x = (frame["x"] as? NSNumber)?.doubleValue, let y = (frame["y"] as? NSNumber)?.doubleValue,
                      let width = (frame["width"] as? NSNumber)?.doubleValue, let height = (frame["height"] as? NSNumber)?.doubleValue else { return nil }
                var read = Item(kind: kind, name: item["name"] as? String ?? "", value: item["value"] as? String ?? "",
                                frame: CGRect(x: x, y: y, width: width, height: height), checked: item["checked"] as? Bool,
                                enabled: item["enabled"] as? Bool ?? true, clickable: item["clickable"] as? Bool ?? false,
                                scrollable: item["scrollable"] as? Bool ?? false, focused: item["focused"] as? Bool ?? false)
                read.id = id
                return read
            })
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
    /// each action: false ends the batch (the app closed, the turn was stopped, or the person took the app back,
    /// `tookOver`, which the report then says). `aim` shows where each action is about to happen, a point on the
    /// device, with what it's doing and whether it presses there (`Handover`), and returns once Lamp's fingertip is there.
    static func perform(_ actions: [Simulator.Driver.Action], on serial: String, density: Int?, screen first: Screen?,
                        aim: @escaping @MainActor (CGPoint, String?, Bool) async -> Void = { _, _, _ in },
                        tookOver: @escaping @MainActor () -> Bool = { false },
                        adb commands: Commands? = nil,
                        stillMine: @escaping @MainActor () async -> Bool) async -> String {
        let adb: Commands = commands ?? { await run($0, on: serial, timeout: $1) }
        var screen = first
        var report: [String] = []
        let scale = scale(density: density)
        let middle = CGPoint(x: 540 / scale, y: 1200 / scale)
        func point(_ action: Simulator.Driver.Action, on screen: Screen?) -> (CGPoint, String, Screen.Item?)? {
            if let target = action.target {
                guard let item = screen?.find(target) else { return nil }
                return (CGPoint(x: item.frame.midX, y: item.frame.midY), "\(item.kind) \"\(item.name)\"", item)
            }
            guard let x = action.x, let y = action.y else { return nil }
            return (CGPoint(x: x, y: y), "the point \(Int(x)),\(Int(y))", nil)
        }
        func pixels(_ point: CGPoint) -> (Int, Int) { (Int((point.x * scale).rounded()), Int((point.y * scale).rounded())) }
        /// Where an action happens on the device, what the fingertip's caption says, and whether it presses there.
        /// Nil for what happens nowhere in particular (a key, a wait) or isn't on the screen read.
        func spot(of action: Simulator.Driver.Action, on screen: Screen?) -> (point: CGPoint, doing: String?, press: Bool)? {
            switch action.action {
            case "click", "tap", "left_click", "double_click", "right_click", "long_press":
                guard let (at, _, item) = point(action, on: screen) else { return nil }
                return (at, item.map { tapping($0, as: action.action) } ?? tapping(nil, as: action.action), true)
            case "type":
                if let (at, _, item) = point(action, on: screen) { return (at, item.map { "typing into " + shortName($0) } ?? "typing", true) }
                guard let field = screen?.items.first(where: { $0.kind == "field" && $0.focused }) else { return nil }
                return (CGPoint(x: field.frame.midX, y: field.frame.midY), "typing into " + shortName(field), false)
            case "scroll", "swipe":
                return (point(action, on: screen)?.0 ?? middle, action.action == "scroll" ? "scrolling" : "swiping", false)
            default:
                return nil
            }
        }
        // Every input goes through here. The person may take the app back at any moment, the fingertip's glide, a
        // pause and a screen read included, and nothing more of Lamp's reaches the device once they have.
        var stopped: Int?
        var current = 0
        var begun = false   // some of the current action's input went out, so it was cut short rather than not done
        func send(_ arguments: [String], _ timeout: TimeInterval) async -> Bool {
            // Asked again once the check is back: it waits on the device (whether the app still runs), and the
            // person may take the app back meanwhile.
            guard stopped == nil, await stillMine(), await !tookOver() else {
                stopped = stopped ?? current
                return false
            }
            _ = await adb(arguments, timeout)
            begun = true
            return true
        }
        actions: for (index, action) in actions.enumerated() {
            current = index
            begun = false
            guard await stillMine() else { stopped = index; break }
            if let spot = spot(of: action, on: screen) { await aim(spot.point, spot.doing, spot.press) }
            switch action.action {
            case "click", "tap", "left_click", "double_click", "right_click", "long_press":
                guard let (at, what, _) = point(action, on: screen) else { report.append("\(index + 1). Nothing on screen matches \"\(action.target ?? "")\"."); continue }
                let (x, y) = pixels(at)
                if action.action == "right_click" || action.action == "long_press" {
                    guard await send(["shell", "input", "swipe", "\(x)", "\(y)", "\(x)", "\(y)", "800"], 30) else { break actions }
                    report.append("\(index + 1). Long-pressed \(what).")
                } else {
                    guard await send(["shell", "input", "tap", "\(x)", "\(y)"], 30) else { break actions }
                    if action.action == "double_click" { guard await send(["shell", "input", "tap", "\(x)", "\(y)"], 30) else { break actions } }
                    report.append("\(index + 1). Tapped \(what).")
                }
            case "type":
                guard let text = action.text else { report.append("\(index + 1). type needs text."); continue }
                if let (at, _, _) = point(action, on: screen) {
                    let (x, y) = pixels(at)
                    guard await send(["shell", "input", "tap", "\(x)", "\(y)"], 30) else { break actions }
                    try? await Task.sleep(for: .milliseconds(300))
                }
                // The field typed into, read once the tap has landed: the one with the keyboard now, else the target.
                let before = await Self.screen(density: density, adb: adb, input: send)
                let field = before?.items.first { $0.kind == "field" && $0.focused } ?? action.target.flatMap { before?.find($0) }
                // In place of what the field held, as on the other devices: everything selected and deleted where the
                // device takes a key combination (Android 11 and later); on an older one, to the end and back over
                // every character the field was seen to hold, in calls of a hundred keys.
                guard await send(["shell", "input", "keycombination", "KEYCODE_CTRL_LEFT", "KEYCODE_A"], 30) else { break actions }
                guard await send(["shell", "input", "keyevent", "KEYCODE_DEL"], 30) else { break actions }
                var remaining = (field?.value.count ?? 0) + 2
                if let field, (await Self.screen(density: density, adb: adb, input: send))?.find(field.id)?.value.isEmpty == false, remaining > 0 {
                    guard await send(["shell", "input", "keyevent", "KEYCODE_MOVE_END"], 30) else { break actions }
                    while remaining > 0 {
                        let batch = min(remaining, 100)
                        guard await send(["shell", "input", "keyevent"] + Array(repeating: "KEYCODE_DEL", count: batch), 60) else { break actions }
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
                guard await send(["shell", "input", "text", escaped], 60) else { break actions }
                report.append("\(index + 1). Typed \"\(text)\".")
            case "key":
                let keys = ["return": "KEYCODE_ENTER", "enter": "KEYCODE_ENTER", "escape": "KEYCODE_BACK", "back": "KEYCODE_BACK",
                            "home": "KEYCODE_HOME", "delete": "KEYCODE_DEL", "backspace": "KEYCODE_DEL", "tab": "KEYCODE_TAB",
                            "space": "KEYCODE_SPACE", "up": "KEYCODE_DPAD_UP", "down": "KEYCODE_DPAD_DOWN", "left": "KEYCODE_DPAD_LEFT", "right": "KEYCODE_DPAD_RIGHT",
                            // A TV remote's.
                            "select": "KEYCODE_DPAD_CENTER", "menu": "KEYCODE_MENU", "play": "KEYCODE_MEDIA_PLAY_PAUSE"]
                guard let key = action.key?.lowercased(), let code = keys[key] ?? (key.hasPrefix("keycode_") ? key.uppercased() : nil) else {
                    report.append("\(index + 1). Unknown key \"\(action.key ?? "")\"; the keys are \(keys.keys.sorted().joined(separator: ", ")).")
                    continue
                }
                guard await send(["shell", "input", "keyevent", code], 30) else { break actions }
                report.append("\(index + 1). Pressed \(key).")
            case "scroll", "swipe":
                let (from, what) = point(action, on: screen).map { ($0.0, $0.1) } ?? (middle, "the middle of the screen")
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
                // The fingertip follows the finger, from where it went down to where it lifts.
                let lifted = to
                async let followed: Void = aim(lifted, nil, false)
                guard await send(["shell", "input", "swipe", "\(x1)", "\(y1)", "\(x2)", "\(y2)", "300"], 30) else { break actions }
                await followed
                report.append("\(index + 1). \(action.action == "scroll" ? "Scrolled" : "Swiped") \(action.direction ?? "down") at \(what).")
                if action.action == "swipe", let item = action.item {
                    try? await Task.sleep(for: .milliseconds(500))
                    screen = await Self.screen(density: density, adb: adb, input: send)
                    if let found = screen?.find(item) {
                        let spot = CGPoint(x: found.frame.midX, y: found.frame.midY)
                        await aim(spot, tapping(found, as: "tap"), true)
                        let (x, y) = pixels(spot)
                        guard await send(["shell", "input", "tap", "\(x)", "\(y)"], 30) else { break actions }
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
            // The pause for the app to take the action up, and the screen read again. Lamp's fingertip goes on to
            // where the next action looks to be meanwhile, so that action needn't wait for it: only to show the way,
            // since the action finds its target afresh on the screen read now, and the press shows then.
            let next = index + 1 < actions.count ? spot(of: actions[index + 1], on: screen) : nil
            async let ahead: Void = { if let next { await aim(next.point, next.doing, false) } }()
            try? await Task.sleep(for: .milliseconds(600))
            screen = await Self.screen(density: density, adb: adb, input: send)
            await ahead
        }
        if let stopped {
            let place = begun ? "partway through action \(stopped + 1) of \(actions.count)"
                : "after \(stopped) of \(actions.count) action\(actions.count == 1 ? "" : "s")"
            report.append(await tookOver()
                ? "Stopped \(place): the person took the app over. Nothing after that was done."
                : "Stopped \(place).")
        }
        return report.joined(separator: "\n")
    }

    /// What the fingertip says beside a tap: "tapping Add", "double-tapping", "pressing Delete".
    private static func tapping(_ item: Screen.Item?, as action: String) -> String {
        let verb = action == "right_click" || action == "long_press" ? "pressing" : action == "double_click" ? "double-tapping" : "tapping"
        return item.map { verb + " " + shortName($0) } ?? verb
    }

    /// What a thing is called, short enough to ride beside the fingertip.
    private static func shortName(_ item: Screen.Item) -> String {
        let name = item.name.replacingOccurrences(of: "\n", with: " ").trimmed
        guard !name.isEmpty else { return item.kind }
        return name.count > 30 ? String(name.prefix(29)) + "…" : name
    }
}

// MARK: - The emulator

/// The Android phone on this Mac's screen: one emulator Lamp makes from the system image it downloaded, started
/// by Lamp as itself, which adb then lists like a device of the person's.
enum Emulator {
    /// Which of Lamp's emulators: the phone every Android app opens in, or the TV an Android TV app opens in. Each has
    /// ports of its own (`Edition.androidPorts`), so both can run at once: a screen open on the phone and the TV stays
    /// open in each.
    enum Kind: Equatable, CaseIterable {
        case phone, tv
        var avd: String { (self == .tv ? AndroidTools.tvAVDName : AndroidTools.avdName).replacingOccurrences(of: " ", with: "_") }
        var console: Int { self == .tv ? Edition.androidPorts.tvConsole : Edition.androidPorts.console }
        var bridge: Int { console + 1 }
        var control: Int { self == .tv ? Edition.androidPorts.tvControl : Edition.androidPorts.control }
        /// The serial adb gives it, by the console port it was started on.
        var serial: String { "emulator-\(console)" }
        var image: String { self == .tv ? AndroidTools.tvSystemImage : AndroidTools.systemImage }
        var profile: String { self == .tv ? AndroidTools.tvProfile : AndroidTools.avdProfile }
    }

    /// Makes one of Lamp's emulators from its downloaded system image: a recent Pixel, or a 1080p TV (lamp's command
    /// line's `androidMakeEmulator`, in Lamp's own folder of emulators).
    static func create(_ kind: Kind = .phone) async throws {
        do {
            _ = try await LampCLI.ask("androidMakeEmulator", ["lamp": AndroidTools.lamp, "kind": kind == .tv ? "tv" : "phone"])
        } catch let failure as LampCLI.Failure {
            throw AndroidTools.Failure(message: "Lamp couldn't make the emulator.\n\n" + failure.message)
        }
        guard AndroidTools.has(kind) else { throw AndroidTools.Failure(message: "Lamp couldn't make the emulator.") }
    }

    /// The TV emulator, downloaded and made the first time an Android TV app wants it: Google's terms for its image are
    /// accepted as the rest of Android's tools' were, in the setup the person went through.
    static func prepareTV(note: @escaping @MainActor (String) -> Void) async throws {
        guard !AndroidTools.has(.tv) else { return }
        if !AndroidTools.hasTVImage {
            await note("Downloading the Android TV emulator, about a gigabyte, once…")
            do {
                _ = try await LampCLI.ask("androidInstall", ["lamp": AndroidTools.lamp, "tv": true])
            } catch let failure as LampCLI.Failure {
                throw AndroidTools.Failure(message: "Google's tools couldn't download the Android TV emulator.\n\n" + failure.message)
            }
            guard AndroidTools.hasTVImage else { throw AndroidTools.Failure(message: "Google's tools couldn't download the Android TV emulator.") }
        }
        await note("Making the Android TV emulator…")
        try await create(.tv)
    }

    /// Which of Lamp's emulators has this serial, or nil for a device of the person's.
    static func kind(of serial: String) -> Kind? { Kind.allCases.first { $0.serial == serial } }

    /// The serial of Lamp's emulator of that kind when it's running, else nil. Another emulator adb lists isn't Lamp's
    /// to use.
    static func running(_ kind: Kind = .phone) async -> String? {
        let serial = kind.serial
        guard ownProcesses().contains(where: { $0.kind == kind && $0.onLampsPorts }) else { return nil }
        func listed() async -> Bool { (await Adb.devices()).contains { $0.udid == serial && $0.adbState == "device" } }
        if await listed() { return serial }
        // Started under an earlier server of Lamp's (one that ended as Lamp quit): this one is told where it is.
        guard register(kind) else { return nil }
        try? await Task.sleep(for: .milliseconds(500))
        return await listed() ? serial : nil
    }

    /// The emulators this Lamp started. Every Lamp's runs the same tools and the same emulator's name, so they're told
    /// apart by the folder of emulators each was started with (`ANDROID_AVD_HOME`, Lamp's own), read from the
    /// process's environment, as `ps -E` does.
    /// Each is the kind its emulator's name says, on that kind's ports or (one an earlier Lamp started) elsewhere.
    private static func ownProcesses() -> [(pid: pid_t, onLampsPorts: Bool, kind: Kind?)] {
        let tools = AndroidTools.sdkFolder.appendingPathComponent("emulator").path + "/"
        let home = "ANDROID_AVD_HOME=" + AndroidTools.avdHome.path
        var pids = [pid_t](repeating: 0, count: 4096)
        let count = Int(proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size)))
        return pids.prefix(max(0, count)).compactMap { pid in
            // The emulator itself, not the helpers it starts from the same folder with the same environment
            // (its crash handler, its network simulator), which are never given the emulator's name.
            guard pid > 0, let (path, arguments, environment) = commandLine(of: pid), path.hasPrefix(tools),
                  arguments.contains("-avd"), environment.contains(home) else { return nil }
            func after(_ flag: String) -> String? {
                arguments.firstIndex(of: flag).flatMap { arguments.index(after: $0) < arguments.endIndex ? arguments[arguments.index(after: $0)] : nil }
            }
            let kind = Kind.allCases.first { $0.avd == after("-avd") }
            let onLampsPorts = kind.map { after("-ports") == "\($0.console),\($0.bridge)" } ?? false
            return (pid, onLampsPorts, kind)
        }
    }

    /// A process's program, arguments and environment, from the kernel (`KERN_PROCARGS2`): the argument count, the
    /// program's path, then the arguments and the environment, each ending in a zero byte.
    private static func commandLine(of pid: pid_t) -> (String, [String], [String])? {
        var name = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&name, 3, nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&name, 3, &buffer, &size, nil, 0) == 0 else { return nil }
        let argc = buffer.withUnsafeBytes { Int($0.loadUnaligned(as: Int32.self)) }
        var strings: [String] = []
        var start = MemoryLayout<Int32>.size
        for index in start..<size where buffer[index] == 0 {
            if index > start { strings.append(String(decoding: buffer[start..<index], as: UTF8.self)) }
            start = index + 1
        }
        guard strings.count > argc, let path = strings.first else { return nil }
        // The path, then the arguments (the first being the program again), then the environment.
        return (path, Array(strings[1...argc]), Array(strings.dropFirst(argc + 1)))
    }

    /// Tells Lamp's adb server about its emulator of that kind on its ports, in the message an emulator sends it as it boots
    /// (adb's `host:emulator:<port>`, its length first in hex). The server connects to it there, if it's running.
    /// False when the server couldn't be reached.
    private static func register(_ kind: Kind) -> Bool {
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return false }
        defer { close(socket) }
        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = in_port_t(UInt16(Edition.androidPorts.server)).bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let connected = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard connected == 0 else { return false }
        let request = "host:emulator:\(kind.bridge)"
        let message = Array((String(format: "%04x", request.utf8.count) + request).utf8)
        return write(socket, message, message.count) == message.count
    }

    /// Starts Lamp's emulator of that kind when it isn't running, waits for Android to boot, and gives back its serial.
    /// The emulator is a window of its own on the Mac, which `show` says whether to bring forward. The other kind, if
    /// it's running, is left as it is.
    static func start(show: Bool, kind: Kind = .phone) async throws -> String {
        // One an earlier Lamp started on other ports (adb's usual, or the phone's for the TV) holds the emulator Lamp
        // made, so another can't start on this kind's. Lamp doesn't end it: it doesn't close for a signal while it saves
        // its state, and one started while the other still held the emulator's files crashed. The person closes its
        // window, as they would any.
        if let stale = ownProcesses().first(where: { !$0.onLampsPorts && ($0.kind == kind || $0.kind == nil) }) {
            NSRunningApplication(processIdentifier: stale.pid)?.activate()
            throw AndroidTools.Failure(message: "The Android \(kind == .tv ? "TV " : "")emulator is still open from before Lamp was updated. Close its window, then try again.")
        }
        if let serial = await running(kind) {
            if show { await bringForward(kind) }
            return serial
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: AndroidTools.emulator)
        // On Lamp's own ports (`Edition.androidPorts`), where only Lamp's adb server looks for it and the agent's
        // commands can't reach it. After a crash the emulator would otherwise open with a dialog asking to send
        // Google a report, and start nothing until it's answered.
        process.arguments = ["-avd", kind.avd, "-ports", "\(kind.console),\(kind.bridge)", "-grpc", "\(kind.control)",
                             "-crash-report-mode", "never", "-no-boot-anim", "-netdelay", "none", "-netspeed", "full"]
        process.environment = ProcessInfo.processInfo.environment.merging(AndroidTools.environment) { $1 }
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        process.standardInput = FileHandle.nullDevice
        try process.run()
        // Booting takes half a minute the first time, a few seconds from a snapshot after that.
        for _ in 0..<120 {
            try await Task.sleep(for: .seconds(1))
            guard process.isRunning else { throw AndroidTools.Failure(message: "The emulator quit while starting.") }
            if let serial = await running(kind) {
                let booted = await Adb.run(["shell", "getprop", "sys.boot_completed"], on: serial, timeout: 10).output.trimmed
                if booted == "1" {
                    if !show { await putBehind(kind) }
                    return serial
                }
            }
        }
        throw AndroidTools.Failure(message: "The emulator didn't finish starting.")
    }

    /// The window of Lamp's own emulator of that kind, not another Lamp's or the person's.
    private static func app(_ kind: Kind) -> NSRunningApplication? {
        ownProcesses().lazy.filter { $0.kind == kind }.compactMap { NSRunningApplication(processIdentifier: $0.pid) }.first
    }
    static func bringForward(_ kind: Kind) async { app(kind)?.activate() }
    /// The process whose window shows the device, for the chat beside it (`ChatPanel`).
    static func windowOwner(_ kind: Kind) -> pid_t? { app(kind)?.processIdentifier }
    static func putBehind(_ kind: Kind) async { app(kind)?.hide() }
    /// Its window back on screen where it was, without taking the keyboard from whatever the person is in.
    static func unhide(_ kind: Kind) async { app(kind)?.unhide() }
    static var isRunning: Bool { !ownProcesses().isEmpty }

    /// The window Lamp's emulator draws the device's screen in, for Lamp's fingertip to go where each tap lands. The
    /// emulator keeps its buttons in a window of their own beside it, so the screen is its largest window on screen.
    struct Glass {
        let window: CGWindowID
        let pid: pid_t
        /// The device's screen in points (adb's pixels over its density), as the actions' points are.
        let size: CGSize

        /// Where a point on the device is on the Mac's display, in the drivers' space, as the window is now: the
        /// person may move or resize it between actions. The window holds the screen whole, at its own scale.
        func point(_ point: CGPoint) -> CGPoint? {
            guard let frame = ComputerOverlay.frame(of: window), size.width > 0, size.height > 0 else { return nil }
            // Turned on its side, the window is wider than tall while adb still gives the upright size.
            let shown = (frame.width > frame.height) == (size.width > size.height) ? size : CGSize(width: size.height, height: size.width)
            let zoom = min(frame.width / shown.width, frame.height / shown.height)
            let origin = CGPoint(x: frame.midX - shown.width * zoom / 2, y: frame.midY - shown.height * zoom / 2)
            return CGPoint(x: origin.x + point.x * zoom, y: origin.y + point.y * zoom)
        }
    }

    /// Lamp's emulator's screen on the Mac's, or nil when its window isn't on screen (minimized, or hidden and not
    /// back within a moment of `unhide`).
    static func glass(_ kind: Kind, size: CGSize) async -> Glass? {
        for _ in 0..<10 {
            if let found = onScreen(kind, size: size) { return found }
            try? await Task.sleep(for: .milliseconds(100))
        }
        return nil
    }

    private static func onScreen(_ kind: Kind, size: CGSize) -> Glass? {
        let pids = Set(ownProcesses().filter { $0.kind == kind }.map(\.pid))
        guard !pids.isEmpty else { return nil }
        let windows = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] ?? []
        let largest = windows.compactMap { info -> (CGWindowID, pid_t, Double)? in
            guard let pid = info[kCGWindowOwnerPID as String] as? pid_t, pids.contains(pid), (info[kCGWindowLayer as String] as? Int) == 0,
                  let bounds = info[kCGWindowBounds as String] as? NSDictionary,
                  let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary),
                  let id = info[kCGWindowNumber as String] as? CGWindowID else { return nil }
            return (id, pid, rect.width * rect.height)
        }.max { $0.2 < $1.2 }
        return largest.map { Glass(window: $0.0, pid: $0.1, size: size) }
    }
}
