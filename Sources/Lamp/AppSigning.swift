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
///
/// When the person has chosen their Apple team (Settings → Building) and this Mac has that team's Apple
/// Development certificate, a Mac app is signed with that instead (`Store.deploy`): macOS runs an app's App
/// Intents only for an app signed for a team. Its permissions then go with that certificate, which keeps its
/// name through Apple's yearly renewal.
enum AppSigning {
    @MainActor private static var cached: String?

    /// Lamp's own keychain, which holds the identity (see signing-identity.sh).
    static let keychain = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Lamp/Signing/lamp-signing.keychain-db").path

    /// Whether an app is signed with a certificate (as opposed to ad hoc), judged by its designated requirement.
    static func isCertificateSigned(_ app: URL) -> Bool {
        Subprocess.runBlocking("/usr/bin/codesign", ["-d", "-r-", app.path], timeout: 30).output.contains("certificate leaf")
    }

    /// The shell command that signs a built app, reading `LAMP_APP` and, with a certificate, `LAMP_IDENTITY`
    /// and `LAMP_KEYCHAIN`. An app with a widget is signed from the inside out: the widget first, with the
    /// entitlements in `LAMP_WIDGET_ENTITLEMENTS` (macOS shows no widget that isn't sandboxed, and the app
    /// itself must stay unsandboxed), then the app around it, whose signature seals the widget's.
    /// With `ownKeychain` false the identity is looked for where codesign looks by itself (the login keychain,
    /// where Xcode keeps the person's Apple Development certificates).
    /// With `appEntitlements` the app is signed with those in `LAMP_APP_ENTITLEMENTS` (the app group it shares
    /// with its extensions, when signed for a team). A share extension (`share`) is signed like the widget, from
    /// `LAMP_SHARE` with `LAMP_SHARE_ENTITLEMENTS`.
    static func command(adHoc: Bool, widget: Bool, share: Bool = false, ownKeychain: Bool = true, appEntitlements: Bool = false) -> String {
        let keychain = ownKeychain ? " --keychain \"$LAMP_KEYCHAIN\"" : ""
        let sign = adHoc ? "codesign --force -s -" : "codesign --force\(keychain) -s \"$LAMP_IDENTITY\""
        let app = "\(sign)\(appEntitlements ? " --entitlements \"$LAMP_APP_ENTITLEMENTS\"" : "") \"$LAMP_APP\" 2>&1"
        var steps: [String] = []
        if widget { steps.append("\(sign) --entitlements \"$LAMP_WIDGET_ENTITLEMENTS\" \"$LAMP_WIDGET\" 2>&1") }
        if share { steps.append("\(sign) --entitlements \"$LAMP_SHARE_ENTITLEMENTS\" \"$LAMP_SHARE\" 2>&1") }
        return (steps + [app]).joined(separator: " && ")
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

    /// What the chat says when an app could only be signed ad hoc. The app works, so nothing else would tell
    /// the person why macOS keeps asking for what they already allowed.
    static func adHocNotice(for name: String) -> String { "Lamp couldn't sign \(name) properly, " + adHocNoticeEnd }
    private static let adHocNoticeEnd = "so macOS will ask for its permissions again after every change."

    /// Whether a chat with these lines should be told: once, not after every build, and under any name the
    /// app has had.
    static func needsAdHocNotice(after lines: [LogLine]) -> Bool {
        !lines.contains { $0.kind == .status && $0.text.hasSuffix(adHocNoticeEnd) }
    }

    /// What macOS checks an app against before honoring a permission it was given: its bundle ID and the
    /// certificate it's signed with ("designated => identifier … and certificate leaf = H"…""), or for an
    /// ad-hoc signature the hash of that one build. Nil when there's no signed app there.
    static func requirement(of app: URL) async -> String? {
        guard FileManager.default.fileExists(atPath: app.path) else { return nil }
        var lines: [String] = []
        _ = await Shell.run("codesign -d -r- \"$LAMP_APP\" 2>&1", cwd: FileManager.default.temporaryDirectory,
                            env: ["LAMP_APP": app.path]) { lines.append($0) }
        return requirement(in: lines)
    }

    /// The requirement in what codesign printed. For a certificate signature the line is "designated => …";
    /// for an ad hoc one codesign has no stored requirement and prints the one it worked out as
    /// "# designated => cdhash …". Both are a signature to compare: read only the first way, an app going
    /// from ad hoc to Lamp's certificate looked as if nothing had been there before, and its old permissions
    /// were left in System Settings.
    static func requirement(in output: [String]) -> String? {
        output.lazy.map { $0.hasPrefix("# ") ? String($0.dropFirst(2)) : $0 }.first { $0.hasPrefix("designated => ") }
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
