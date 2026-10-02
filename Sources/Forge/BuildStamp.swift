import SwiftUI
import CryptoKit

/// Which Forge built an app. Forge writes it into the app's Info.plist after every build, so an app
/// built by an older Forge can be told apart and its owner warned to rebuild it.
struct BuildStamp: Equatable {
    /// Forge's version, e.g. "0.2.0". Nil for apps built before stamps existed.
    var forge: String?
    /// A fingerprint of the ForgeSupport.swift template the app was compiled with. Two builds of Forge
    /// can share a version number (every local build is 0.1); this is what says whether the code Forge
    /// puts in each app has changed.
    var support: String?

    private static let forgeKey = "ForgeVersion"
    private static let supportKey = "ForgeSupportVersion"

    /// What this Forge stamps on the apps it builds.
    static let current = BuildStamp(
        forge: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
        support: SHA256.hash(data: Data(Template.forgeSupportSwift.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined())

    /// The stamp on a built app, or nil when there's no app there. An app without a stamp reads as empty.
    static func read(_ app: URL) -> BuildStamp? {
        guard let info = NSDictionary(contentsOf: app.appendingPathComponent("Contents/Info.plist")) else { return nil }
        return BuildStamp(forge: info[forgeKey] as? String, support: info[supportKey] as? String)
    }

    /// Stamps a freshly built app, before it's signed.
    static func write(to app: URL) {
        let url = app.appendingPathComponent("Contents/Info.plist")
        guard let info = NSMutableDictionary(contentsOf: url) else { return }
        info[forgeKey] = current.forge
        info[supportKey] = current.support
        info.write(to: url, atomically: true)
    }

    /// Built by a Forge whose app code differs from this one's.
    var isOutdated: Bool { support != Self.current.support }

    /// What built the app, to follow "built with": "Forge 0.2.0", "an older version of Forge".
    var builder: String {
        guard let forge else { return "an older version of Forge" }
        return isOutdated && forge == Self.current.forge ? "an earlier build of Forge \(forge)" : "Forge \(forge)"
    }

    /// The same, to stand alone in the app's info panel.
    var summary: String { builder.prefix(1).uppercased() + builder.dropFirst() }
}

/// Shown above the message box when the app on screen was built by an older Forge.
struct OutdatedBanner: View {
    let name: String
    let stamp: BuildStamp
    let onRebuild: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.arrow.triangle.2.circlepath").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("\(name) was built with \(stamp.builder)").font(.callout)
                Text("Rebuild it to bring it up to date with this Forge (\(BuildStamp.current.forge ?? "")).")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Button("Rebuild", action: onRebuild)
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 10))
    }
}
