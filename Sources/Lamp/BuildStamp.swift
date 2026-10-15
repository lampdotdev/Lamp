import SwiftUI
import CryptoKit

/// Which Lamp built an app. Lamp writes it into the app's Info.plist after every build, so an app
/// built by an older Lamp can be told apart and rebuilt when it's next opened from Lamp.
struct BuildStamp: Equatable {
    /// Lamp's version, e.g. "0.2.0". Nil for apps built before stamps existed.
    var lamp: String?
    /// A fingerprint of the LampSupport.swift template the app was compiled with. Two builds of Lamp
    /// can share a version number (every local build is 0.1); this is what says whether the code Lamp
    /// puts in each app has changed.
    /// It covers the reasons a Mac app gives for its permissions too: an app built before one was added is
    /// killed when it asks, until it's built again. And the build's App Intents step: an app built before it
    /// has none of its intents where the system looks for them. And the chat Lamp puts in a Mac app's window
    /// (`Sidebar`): an app installed with an earlier one shows that until it's built again.
    var support: String?

    private static let lampKey = "LampVersion"
    private static let supportKey = "LampSupportVersion"

    /// What this Lamp stamps on the apps it builds.
    static let current = BuildStamp(
        lamp: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
        support: SHA256.hash(data: Data((Template.lampSupportSwift + Template.macUsagePlistLines(name: "") + Template.appIntentsSetup(ios: false) + Template.appIntentsSetup(ios: true)).utf8)
                             + (Bundle.main.url(forResource: "LampSidebar", withExtension: nil).flatMap { try? Data(contentsOf: $0) } ?? Data()))
            .prefix(6).map { String(format: "%02x", $0) }.joined())

    /// The stamp on a built app, or nil when there's no app there. An app without a stamp reads as empty.
    static func read(_ app: URL) -> BuildStamp? {
        guard let info = NSDictionary(contentsOf: infoPlist(of: app)) else { return nil }
        return BuildStamp(lamp: info[lampKey] as? String, support: info[supportKey] as? String)
    }

    /// Stamps a freshly built app, before it's signed.
    /// A Mac bundle keeps its Info.plist under Contents; an iPhone bundle at its top.
    private static func infoPlist(of app: URL) -> URL {
        let mac = app.appendingPathComponent("Contents/Info.plist")
        return FileManager.default.fileExists(atPath: mac.path) ? mac : app.appendingPathComponent("Info.plist")
    }

    static func write(to app: URL) {
        let url = infoPlist(of: app)
        guard let info = NSMutableDictionary(contentsOf: url) else { return }
        info[lampKey] = current.lamp
        info[supportKey] = current.support
        info.write(to: url, atomically: true)
    }

    /// Built by a Lamp whose app code differs from this one's.
    var isOutdated: Bool { support != Self.current.support }

    /// What built the app, to follow "built with": "Lamp 0.2.0", "an older version of Lamp".
    var builder: String {
        guard let lamp else { return "an older version of Lamp" }
        return isOutdated && lamp == Self.current.lamp ? "an earlier build of Lamp \(lamp)" : "Lamp \(lamp)"
    }

    /// The same, to stand alone in the app's info panel.
    var summary: String { builder.prefix(1).uppercased() + builder.dropFirst() }
}
