import Foundation

/// Runs an iPhone app in Apple's iOS Simulator: the app is built for the Simulator (build.sh), installed
/// into a booted iPhone, launched with its output going to the app's log, and photographed on request.
/// Needs Xcode (the Simulator and its iOS runtime come with it), not just the Command Line Tools.
enum Simulator {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether Xcode and an iPhone simulator are on this Mac, with a plain message when not.
    static func problem() -> String? {
        let developer = Subprocess.runBlocking("/usr/bin/xcode-select", ["-p"], mergeErrors: false, timeout: 10).output.trimmed
        guard developer.hasSuffix("Xcode.app/Contents/Developer") || developer.contains("/Xcode") else {
            return "iPhone apps need Xcode (free on the Mac App Store), which brings the iPhone simulator."
        }
        return device() == nil ? "No iPhone simulator with iOS \(minimumIOS) or later is installed. Open Xcode once and add one in Settings → Components." : nil
    }

    /// The apps Lamp makes need this iOS (the scaffold's deployment target), so only simulators that run it count.
    static let minimumIOS = 17

    /// The iPhone to use: one that's already booted, else the newest available, among those on a runtime
    /// the apps can run on. Sorted by name after the runtime, so the choice is the same every time.
    static func device() -> String? {
        let listing = Subprocess.runBlocking("/usr/bin/xcrun", ["simctl", "list", "devices", "available", "-j"], mergeErrors: false, timeout: 30).output
        guard let data = listing.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = json["devices"] as? [String: [[String: Any]]] else { return nil }
        // Runtime keys look like com.apple.CoreSimulator.SimRuntime.iOS-18-6.
        typealias Candidate = (version: Int, name: String, booted: Bool, udid: String)
        var candidates: [Candidate] = []
        for (runtime, list) in devices {
            guard let range = runtime.range(of: "SimRuntime.iOS-"),
                  let major = Int(runtime[range.upperBound...].split(separator: "-").first ?? ""), major >= minimumIOS else { continue }
            for device in list {
                guard let name = device["name"] as? String, name.hasPrefix("iPhone"), let udid = device["udid"] as? String else { continue }
                candidates.append((major, name, device["state"] as? String == "Booted", udid))
            }
        }
        let ordered = candidates.sorted { ($0.booted ? 1 : 0, $0.version, $0.name) > ($1.booted ? 1 : 0, $1.version, $1.name) }
        return ordered.first?.udid
    }

    /// Boots the iPhone (a no-op when it already is) and opens the Simulator app so the user can see it.
    static func boot(_ udid: String, show: Bool) async throws {
        _ = await Subprocess.run("/usr/bin/xcrun", ["simctl", "boot", udid], timeout: 60)   // "already booted" is fine
        let status = await Subprocess.run("/usr/bin/xcrun", ["simctl", "bootstatus", udid, "-b"], timeout: 120)
        guard status.ok else { throw Failure(message: "The iPhone simulator didn't start.") }
        if show { _ = await Subprocess.run("/usr/bin/open", ["-a", "Simulator"], timeout: 30) }
    }

    static func install(_ app: URL, on udid: String) async throws {
        let result = await Subprocess.run("/usr/bin/xcrun", ["simctl", "install", udid, app.path], timeout: 120)
        guard result.ok else { throw Failure(message: "Couldn't put the app on the simulator: \(result.output.trimmed)") }
    }

    /// Launches the app with its output going to `log`. Returns its process id.
    static func launch(_ bundleID: String, on udid: String, log: URL) async throws -> Int32 {
        let result = await Subprocess.run("/usr/bin/xcrun", ["simctl", "launch", "--stdout=\(log.path)", "--stderr=\(log.path)", udid, bundleID],
                                          mergeErrors: false, timeout: 60)
        // "bundle.id: 12345"
        guard result.ok, let pid = result.output.split(separator: ":").last.flatMap({ Int32(String($0).trimmed) }) else {
            throw Failure(message: "The app didn't launch: \(result.errors.trimmed)")
        }
        return pid
    }

    static func terminate(_ bundleID: String, on udid: String) async {
        _ = await Subprocess.run("/usr/bin/xcrun", ["simctl", "terminate", udid, bundleID], timeout: 30)
    }

    /// Whether the launched app is still running (it crashed if not).
    static func isRunning(pid: Int32) -> Bool { kill(pid, 0) == 0 }

    /// A picture of the iPhone's screen.
    static func screenshot(on udid: String, to file: URL) async -> Bool {
        await Subprocess.run("/usr/bin/xcrun", ["simctl", "io", udid, "screenshot", "--type=png", file.path], timeout: 30).ok
    }

    /// Brings the Simulator window to the front.
    static func show() async { _ = await Subprocess.run("/usr/bin/open", ["-a", "Simulator"], timeout: 30) }
}
