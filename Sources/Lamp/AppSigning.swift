import Foundation

/// The signature Lamp puts on the apps it builds.
///
/// macOS remembers permissions (Files and Folders, Screen Recording, Accessibility, Keychain access) against
/// an app's signature. An ad-hoc signature is just a hash of that one build, so every rebuild looked like a new
/// app and asked again. Signing with a certificate that stays the same lets permissions survive rebuilds.
/// The certificate is the same self-signed "Lamp App Signing" one Lamp's own builds use, and both the
/// release and the development build share it (Edition), so an app keeps its permissions whichever rebuilds it. It's made the
/// first time (scripts/signing-identity.sh) in Lamp's own keychain, which Lamp can unlock itself, so
/// signing never asks for keychain access the way the login keychain does. It never leaves this Mac and
/// isn't trusted for anything else.
enum AppSigning {
    @MainActor private static var cached: String?

    /// Lamp's own keychain, which holds the identity (see signing-identity.sh).
    static let keychain = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lamp/Signing/lamp-signing.keychain-db").path

    /// Whether an app is signed with a certificate (as opposed to ad hoc), judged by its designated requirement.
    static func isCertificateSigned(_ app: URL) -> Bool {
        Subprocess.runBlocking("/usr/bin/codesign", ["-d", "-r-", app.path], timeout: 30).output.contains("certificate leaf")
    }

    /// The identity to sign with, or "-" (ad-hoc) if one can't be made.
    @MainActor
    static func identity() async -> String {
        if let cached { return cached }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("signing-identity.sh"),
              FileManager.default.isExecutableFile(atPath: script.path) else {
            print("AppSigning: signing-identity.sh is missing from the app; signing ad hoc")
            return "-"
        }
        var lines: [String] = []
        let status = await Shell.run("\"$LAMP_SCRIPT\"", cwd: FileManager.default.temporaryDirectory,
                                     env: ["LAMP_SCRIPT": script.path]) { lines.append($0) }
        let name = status == 0 ? lines.last?.trimmed ?? "" : ""
        if name.isEmpty {
            // Ad hoc signing loses the app's permissions on every rebuild and stops macOS asking for
            // Location Services at all, so say why it happened.
            print("AppSigning: couldn't make the signing identity (exit \(status)); signing ad hoc:\n" + lines.joined(separator: "\n"))
        }
        let identity = name.isEmpty ? "-" : name
        // A failure isn't remembered: the next install tries again (the keychain may have been fixed since).
        if identity != "-" { cached = identity }
        return identity
    }

    /// What macOS checks an app against before honouring a permission it was given: its bundle ID and the
    /// certificate it's signed with ("designated => identifier … and certificate leaf = H"…""), or for an
    /// ad-hoc signature the hash of that one build. Nil when there's no signed app there.
    static func requirement(of app: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: app.path) else { return nil }
        var lines: [String] = []
        _ = await Shell.run("codesign -d -r- \"$LAMP_APP\" 2>&1", cwd: FileManager.default.temporaryDirectory,
                            env: ["LAMP_APP": app.path]) { lines.append($0) }
        return lines.first { $0.hasPrefix("designated => ") }
    }

    /// Clears what macOS remembers of an app's permissions (System Settings ▸ Privacy & Security).
    ///
    /// A permission is kept with the signature it was given to. When an app's signature changes (Lamp moved
    /// from ad-hoc signing to "Forge Local Signing", then to "Lamp App Signing"; or its keychain was lost and
    /// made again), the old entries stay in System Settings, switched on, but no longer apply to the app:
    /// it has no access, and switching them off and on doesn't help. With them cleared the app is simply an
    /// app that hasn't been given anything yet, and asking again works. macOS has to know the app (lsregister).
    static func forgetPermissions(of bundleID: String) async -> Bool {
        var lines: [String] = []
        let status = await Shell.run("tccutil reset All \"$LAMP_BUNDLE\" 2>&1", cwd: FileManager.default.temporaryDirectory,
                                     env: ["LAMP_BUNDLE": bundleID]) { lines.append($0) }
        if status != 0 { print("AppSigning: couldn't clear the permissions of \(bundleID):\n" + lines.joined(separator: "\n")) }
        return status == 0
    }
}
