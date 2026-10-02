import Foundation

/// The signature Forge puts on the apps it builds.
///
/// macOS remembers permissions (Files and Folders, Screen Recording, Accessibility, Keychain access) against
/// an app's signature. An ad-hoc signature is just a hash of that one build, so every rebuild looked like a new
/// app and asked again. Signing with a certificate that stays the same lets permissions survive rebuilds.
/// The certificate is the same self-signed "Forge Local Signing" one Forge's own builds use: it's made in
/// the login keychain the first time (Resources/signing-identity.sh), never leaves this Mac, and isn't
/// trusted for anything else.
enum AppSigning {
    @MainActor private static var cached: String?

    /// The identity to sign with, or "-" (ad-hoc) if one can't be made.
    @MainActor
    static func identity() async -> String {
        if let cached { return cached }
        guard let script = Bundle.main.resourceURL?.appendingPathComponent("signing-identity.sh"),
              FileManager.default.isExecutableFile(atPath: script.path) else { return "-" }
        var lines: [String] = []
        let status = await Shell.run("\"$FORGE_SCRIPT\" 2>/dev/null", cwd: FileManager.default.temporaryDirectory,
                                     env: ["FORGE_SCRIPT": script.path]) { lines.append($0) }
        let name = status == 0 ? lines.last?.trimmed ?? "" : ""
        let identity = name.isEmpty ? "-" : name
        cached = identity
        return identity
    }
}
