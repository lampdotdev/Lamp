import Foundation
import LampRelayKit

/// The sites a page shared with this person may reach (`NetworkPolicy`), as Lamp keeps them: worked out when the app
/// arrives from the reading the safety sheet showed (`WebReach`), its exact sites and whether it may connect elsewhere,
/// and kept in Lamp's own folder, which neither the app nor the agent's commands can write. Every build writes it into
/// the app's Info.plist (`plistLines`), where the app around the page enforces it whether Lamp is open or not; Lamp's
/// previews read it here. An app with none is the person's own, and isn't held to anything.
///
/// Every host of a shared page reads it here: the Mac, iPhone and iPad app (LampPage.swift, from the Info.plist) and
/// Lamp's previews (`StagedFiles`) do, and a phone's controller page is held to its sites (`PhonePageReach`); a host
/// elsewhere (a TV, an Xbox, Android) holds a shared page only once it reads it too.
enum SharedNetwork {
    /// Where the policies are kept: Lamp's own folder, closed to the agent's commands (`Sandbox`), one file an app.
    /// Tests keep theirs in a folder of their own.
    nonisolated(unsafe) static var folder = Edition.supportFolder.appendingPathComponent("Network")

    /// An app's file, by who it is (`instance`, kept through renames), or its folder's name for an app from before.
    static func url(for project: LampProject) -> URL {
        url(key: project.instance.isEmpty ? project.id : project.instance)
    }

    private static func url(key: String) -> URL {
        let safe = key.addingPercentEncoding(withAllowedCharacters: .alphanumerics.union(CharacterSet(charactersIn: "-_."))) ?? key
        return folder.appendingPathComponent(safe + ".json")
    }

    /// The app's policy, or nil for an app the person made (or one whose file can't be read as one: never taken for a
    /// wider one).
    static func policy(for project: LampProject) -> NetworkPolicy? {
        guard let data = try? Data(contentsOf: url(for: project)) else { return nil }
        return (try? JSONDecoder().decode(NetworkPolicy.self, from: data)) ?? NetworkPolicy()
    }

    static func save(_ policy: NetworkPolicy, for project: LampProject) throws {
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(policy).write(to: url(for: project), options: .atomic)
    }

    /// A copy of a wish (a remix) is held as the wish is: its policy, and each of its other apps', by their folders.
    static func carry(from original: LampProject, parts: [LampProject], to copy: LampProject) {
        let fm = FileManager.default
        let pairs = [(url(for: original), url(for: copy))]
            + parts.map { (url(for: $0), url(key: Parts.instance(wish: copy, folder: $0.dir.lastPathComponent))) }
        for (from, to) in pairs where fm.fileExists(atPath: from.path) {
            try? fm.removeItem(at: to)
            do { try fm.copyItem(at: from, to: to) } catch { print("Couldn't keep what \(copy.name) may reach: \(error)") }
        }
    }

    static func forget(_ project: LampProject) {
        try? FileManager.default.removeItem(at: url(for: project))
    }

    /// Whether a kind is held to a policy when it's shared: a page, wherever it's shown (a web app, a screen, a web game,
    /// a TV app). A Swift app or an Android app has no page to hold.
    static func applies(to platform: Platform) -> Bool {
        Sharing.isPage(platform) || platform.target.recipe.language == .web
    }

    /// The policy for one app of a shared file, from the same reading its sheet shows (`TVFiles.reach`): the exact sites
    /// its requests go to, and whether it may connect where Lamp couldn't tell. An app of a kind with no page is kept as
    /// shared too, with nothing in it to hold, so a page the wish makes for it later (`isShared`) is held as the rest.
    /// The libraries Lamp knows by their contents (three.js) are left out, as the sheet leaves them out (`Sharing.inspect`).
    static func reading(of package: Sharing.Package, stock: String? = Sharing.stockNative) -> NetworkPolicy {
        guard applies(to: package.platform) else { return NetworkPolicy() }
        let sources = package.sources.filter { file in
            (try? String(contentsOf: file, encoding: .utf8)).map { !Sharing.knownLibraries.contains(Sharing.fingerprint($0)) } ?? true
        }
        let reach = TVFiles.reach(in: sources, data: package.webData)
        return NetworkPolicy(origins: Array(reach.origins), mayConnect: reach.unknown || reach.unnamed,
                             ownSwift: hasOwnSwift(package, stock: stock))
    }

    /// Whether a wish came from someone else: it, or one of its apps, has a policy.
    static func isShared(_ wish: LampProject, parts: [LampProject]) -> Bool {
        ([wish] + parts).contains { policy(for: $0) != nil }
    }

    /// Swift of the sender's in the app's process, as an app here is judged to have it (`GameKit.hasOwnSwift`): any Swift
    /// file the file brings beside the page (Lamp's own never travel), but a Native.swift that's Lamp's own. `stock` is
    /// Lamp's Native.swift: one that can't be read is never taken for it.
    static func hasOwnSwift(_ package: Sharing.Package, stock: String? = Sharing.stockNative) -> Bool {
        package.sources.contains { file in
            let path = package.path(of: file)
            guard path.hasPrefix("Sources/"), path.hasSuffix(".swift") else { return false }
            return path != GameFiles.native || stock == nil || (try? String(contentsOf: file, encoding: .utf8)) != stock
        }
    }

    /// The policies of a wish's apps as they are, to put back (`restore`) when a change of the wish is undone: they're
    /// kept outside its versions.
    static func snapshot(_ apps: [LampProject]) -> [URL: Data?] {
        Dictionary(apps.map { (url(for: $0), try? Data(contentsOf: url(for: $0))) }, uniquingKeysWith: { first, _ in first })
    }

    /// Puts the policies back as `snapshot` had them, and takes away those of `apps` it didn't have: an app the undone
    /// change made (a part an update added) leaves none behind for a later app in its folder, which would be the same
    /// instance (`Parts.instance`), to take for its own.
    static func restore(_ snapshot: [URL: Data?], apps: [LampProject] = []) {
        for (file, data) in snapshot {
            if let data { try? data.write(to: file, options: .atomic) } else { try? FileManager.default.removeItem(at: file) }
        }
        for app in apps where snapshot[url(for: app)] == nil { forget(app) }
    }

    /// Records what a shared file's app may reach, as it goes into `project`. A fresh import (`arriving`) records it; an
    /// update records it again only for an app that already has one, so an app of the person's own, or a starter, never
    /// comes to have one. The person's own choice to let it reach every site stays through an update.
    static func arrive(_ package: Sharing.Package, in project: LampProject, arriving: Bool) {
        let had = policy(for: project)
        guard arriving || had != nil else { return }
        var policy = reading(of: package)
        policy.unrestricted = had?.unrestricted ?? false
        do { try save(policy, for: project) } catch { print("Couldn't keep what \(project.name) may reach: \(error)") }
    }

    /// The policy's lines in the app's Info.plist (none for an app the person made): Swift of the app's own that came
    /// later (`GameKit.hasOwnSwift`) is said too.
    static func plistLines(for project: LampProject) -> String {
        guard applies(to: project.platform), var policy = policy(for: project) else { return "" }
        if GameKit.hasOwnSwift(project) { policy.ownSwift = true }
        return "\n" + policy.plistLines
    }
}
