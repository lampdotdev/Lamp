import Foundation

/// The signature Forge puts on the apps it builds.
///
/// macOS remembers permissions (Files and Folders, Screen Recording, Accessibility, Keychain access) against
/// an app's signature. An ad-hoc signature is just a hash of that one build, so every rebuild looked like a new
/// app and asked again. Signing with a certificate that stays the same lets permissions survive rebuilds.
/// The certificate is the same self-signed "Forge App Signing" one Forge's own builds use. It's made the
/// first time (scripts/signing-identity.sh) in Forge's own keychain, which Forge can unlock itself, so
/// signing never asks for keychain access the way the login keychain does. It never leaves this Mac and
/// isn't trusted for anything else.
enum AppSigning {
    @MainActor private static var cached: String?

    /// Forge's own keychain, which holds the identity (see signing-identity.sh).
    static let keychain = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Forge/Signing/forge-signing.keychain-db").path

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
        let status = await Shell.run("\"$FORGE_SCRIPT\"", cwd: FileManager.default.temporaryDirectory,
                                     env: ["FORGE_SCRIPT": script.path]) { lines.append($0) }
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
}
