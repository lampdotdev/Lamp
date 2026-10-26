import SwiftUI
import CryptoKit

/// Which Lamp built an app. Lamp writes it into the app's Info.plist after every build, so an app
/// built by an older Lamp can be told apart and rebuilt when it's next opened from Lamp.
struct BuildStamp: Equatable {
    /// Lamp's version, e.g. "0.2.0". Nil for apps built before stamps existed.
    var lamp: String?
    /// A fingerprint of the LampSupport.swift template and the build scripts the app was compiled with.
    /// Two builds of Lamp can share a version number (every local build is 0.1); this is what says whether
    /// what Lamp puts in each app has changed. The build scripts are in it because they change the binary
    /// too: an app built before they restricted dyld's environment variables (buildSh) takes injected
    /// libraries until it's built again.
    /// It covers the reasons a Mac app gives for its permissions too: an app built before one was added is
    /// killed when it asks, until it's built again. And the build's App Intents step: an app built before it
    /// has none of its intents where the system looks for them. And the chat Lamp puts in a Mac app's window
    /// (`Sidebar`): an app installed with an earlier one shows that until it's built again. It leaves out `LampWish`,
    /// which has a fingerprint of its own (`wish`), given to every app that carries it (`Template.carriesWish`).
    var support: String?
    /// A fingerprint of `LampWish`, on an app that carries it: one built with an earlier block is built again when it's
    /// opened from Lamp, so the "out of date" its wish's other apps and its own other copies show for it goes once it is.
    var wish: String? = nil

    private static let lampKey = "LampVersion"
    private static let supportKey = "LampSupportVersion"
    private static let wishKey = "LampWishVersion"

    /// What this Lamp stamps on an app of several in a wish, beside `current`.
    static let currentWish = SHA256.hash(data: Data(Template.lampSupportSwift.utf8)).prefix(6).map { String(format: "%02x", $0) }.joined()

    /// What this Lamp stamps on the apps it builds.
    static let current = BuildStamp(
        lamp: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1",
        support: SHA256.hash(data: Data((Template.withoutWish(Template.lampSupportSwift) + Template.lampSceneSwift + Template.macUsagePlistLines(name: "") + Template.appIntentsSetup(ios: false) + Template.appIntentsSetup(ios: true)
                                         + Template.buildSh + Template.universalBuildSh).utf8)
                             + (Bundle.main.url(forResource: "LampSidebar", withExtension: nil).flatMap { try? Data(contentsOf: $0) } ?? Data()))
            .prefix(6).map { String(format: "%02x", $0) }.joined())

    /// The stamp on a built app, or nil when there's no app there. An app without a stamp reads as empty.
    static func read(_ app: URL) -> BuildStamp? {
        guard let info = NSDictionary(contentsOf: infoPlist(of: app)) else { return nil }
        return BuildStamp(lamp: info[lampKey] as? String, support: info[supportKey] as? String, wish: info[wishKey] as? String)
    }

    /// The stamp on a build in the app's folder, read as `AppFile` reads: the agent's commands write that folder, and
    /// a link left at the build's Info.plist would be followed, a pipe there would keep Lamp waiting as it starts.
    static func read(_ app: URL, in project: LampProject) -> BuildStamp? {
        guard let data = AppFile.read(app.appendingPathComponent("Contents/Info.plist"), in: project)
                ?? AppFile.read(app.appendingPathComponent("Info.plist"), in: project),
              let info = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return nil }
        return BuildStamp(lamp: info[lampKey] as? String, support: info[supportKey] as? String, wish: info[wishKey] as? String)
    }

    /// Where an app's stamp is read: a Mac app's installed copy, in Lamp's own apps folder; an app with no Mac half
    /// has none, so its build, which is what the simulator gets.
    static func of(_ project: LampProject) -> BuildStamp? {
        project.hasMac ? read(project.installedURL) : read(project.builtURL, in: project)
    }

    /// Stamps a freshly built app, before it's signed.
    /// A Mac bundle keeps its Info.plist under Contents; an iPhone bundle at its top.
    private static func infoPlist(of app: URL) -> URL {
        let mac = app.appendingPathComponent("Contents/Info.plist")
        return FileManager.default.fileExists(atPath: mac.path) ? mac : app.appendingPathComponent("Info.plist")
    }

    /// The build is in the agent's folder, so the plist is read and written there without following a link.
    static func write(for project: LampProject) {
        let url = infoPlist(of: project.builtURL)
        guard let data = AppFile.read(url, in: project),
              let info = try? PropertyListSerialization.propertyList(from: data, options: .mutableContainers, format: nil) as? NSMutableDictionary
        else { return }
        info[lampKey] = current.lamp
        info[supportKey] = current.support
        info[wishKey] = Template.carriesWish(project) ? currentWish : nil
        guard let out = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0) else { return }
        try? AppFolder.write(out, to: url, in: project.dir)
    }

    /// Stamps an app outside any app's folder (a starter's prebuilt copy in Lamp's own bundle, as it's being built). A
    /// starter is an app on its own, which carries `LampWish` as every app does (`Template.carriesWish`).
    static func stamp(_ app: URL) {
        let url = infoPlist(of: app)
        guard let info = NSMutableDictionary(contentsOf: url) else { return }
        info[lampKey] = current.lamp
        info[supportKey] = current.support
        info[wishKey] = currentWish
        info.write(to: url, atomically: true)
    }

    /// Built by a Lamp whose app code differs from this one's.
    var isOutdated: Bool { support != Self.current.support }

    /// Out of date for this app: built by a Lamp whose app code differs, or, for an app that carries `LampWish`, whose
    /// `LampWish` does.
    func isOutdated(for project: LampProject) -> Bool {
        isOutdated || (Template.carriesWish(project) && wish != Self.currentWish)
    }

    /// What built the app, to follow "built with": "Lamp 0.2.0", "an older version of Lamp".
    var builder: String {
        guard let lamp else { return "an older version of Lamp" }
        return isOutdated && lamp == Self.current.lamp ? "an earlier build of Lamp \(lamp)" : "Lamp \(lamp)"
    }

    /// The same, to stand alone in the app's info panel.
    var summary: String { builder.prefix(1).uppercased() + builder.dropFirst() }
}
