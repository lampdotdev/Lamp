import Foundation
import CryptoKit

/// Signing an app for the person's Apple team without letting Xcode near anything the agent wrote.
///
/// Xcode's automatic signing needs what the sandbox closes (the person's keys, Xcode's sign-in), so a build it signs
/// has to run as Lamp; and a build of the agent's project runs whatever that project says, as whoever runs it. So the
/// app itself is built in its sandbox with signing off (`Devices.build`, the Mac half's build.sh), and only signing
/// happens as Lamp, on a copy Lamp made in its own folder. What it's signed with comes from a project of Lamp's own:
/// the app's project as Lamp writes it (the same targets, ids, Info.plists and entitlements, from checked
/// capabilities), over a few lines of Lamp's own code in place of the app's (`stubCode`). Xcode builds and signs that
/// as usual, registering ids and making profiles with the account signed in to Xcode, and its signature says what each
/// piece is entitled to; each piece of the real build is then given that profile and those entitlements, and signed
/// with the team's certificate (`sign`). Nothing the agent wrote is read for any of it.
enum TeamSigning {
    enum Place: String { case mac, iphone }

    /// One piece Lamp signs: the app ("" as its path) or a bundle inside it, by where it sits in the app.
    struct Piece: Codable, Equatable {
        let path: String
        let id: String
        let entitlements: String   // a file in the plan's folder
        let profile: String?
    }

    struct Plan: Codable {
        let stamp: String
        let expires: Date
        let pieces: [Piece]
        var app: Piece? { pieces.first { $0.path.isEmpty } }
    }

    /// The program name of Lamp's own project, and so of its targets and bundles.
    static let stubExe = "LampSigning"

    struct Problem: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Lamp's own folder for one app's signing for one place: the small project, Xcode's build of it, and the plan.
    static func folder(for project: LampProject, place: Place) -> URL {
        Devices.signingFolder(for: project).appendingPathComponent(place.rawValue)
    }

    /// What each piece of the app is signed with for `place`, made by Xcode from Lamp's own project the first time and
    /// whenever that project, the team or the destination changes (a phone's profile must list that phone), or its
    /// profiles are about to run out. `destination` is xcodebuild's;
    /// a phone's (`id=…`) has Xcode register the phone in its profile. `renew` asks for new profiles even while the ones
    /// made before are good (`PhoneRenewals`): Xcode hands back the profile it keeps while it has one, so its copies of
    /// this app's profiles are taken away first, and it makes new ones good for their whole term from now.
    static func plan(for project: LampProject, team: String, place: Place, destination: String, renew: Bool = false,
                     started: (@MainActor (Process) -> Void)? = nil,
                     onLine: @escaping @MainActor (String) -> Void = { _ in }) async throws -> (plan: Plan, folder: URL) {
        let fm = FileManager.default
        let dir = folder(for: project, place: place)
        let projectDir = dir.appendingPathComponent("Project"), code = dir.appendingPathComponent("Code")
        let planDir = dir.appendingPathComponent("Plan")
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        // Under names of Lamp's own: the app's name and program name are in its meta.json, which the agent can write,
        // and would go into a project Xcode builds as Lamp. What's kept is what isn't the agent's: the folder name the
        // ids are made from, the team, the kind of app and its checked capabilities.
        let stub = project.named("Lamp Signing", exe: stubExe)
        try fm.createDirectory(at: projectDir, withIntermediateDirectories: true)
        try? fm.removeItem(at: projectDir.appendingPathComponent("\(stubExe).xcodeproj"))
        try writeStubCode(for: project, in: code)
        try Template.writeDeviceProject(for: stub, team: team, in: projectDir, reading: code, forSigning: true)
        let stamp = self.stamp(of: [projectDir, code], extra: [team, place.rawValue, destination].joined(separator: "\n"))
        let saved = (try? Data(contentsOf: planDir.appendingPathComponent("plan.json"))).flatMap { try? JSONDecoder().decode(Plan.self, from: $0) }
        if !renew, let saved, saved.stamp == stamp, saved.expires > Date().addingTimeInterval(3600) {
            return (saved, planDir)
        }
        if renew, let saved { await forgetXcodeProfiles(for: saved.pieces.map { "\(team).\($0.id)" }) }
        let derived = dir.appendingPathComponent("DerivedData")
        let registration = destination.hasPrefix("id=") ? " -allowProvisioningDeviceRegistration" : ""
        var output: [String] = []
        let status = await Shell.run("""
            "$LAMP_XCODEBUILD" -project "$LAMP_PROJECT" -scheme "$LAMP_SCHEME" -configuration Release -destination "$LAMP_DESTINATION" \\
              -derivedDataPath "$LAMP_DERIVED" -allowProvisioningUpdates\(registration) DEVELOPMENT_TEAM="$LAMP_TEAM" build 2>&1
            """, cwd: dir, env: ["LAMP_XCODEBUILD": DeveloperTools.path("xcodebuild"), "LAMP_PROJECT": projectDir.appendingPathComponent("\(stubExe).xcodeproj").path, "LAMP_SCHEME": stubExe,
                                 "LAMP_DESTINATION": destination, "LAMP_DERIVED": derived.path, "LAMP_TEAM": team],
            started: started) { line in output.append(line); onLine(line) }
        let product = derived.appendingPathComponent("Build/Products/\(place == .mac ? "Release" : "Release-iphoneos")/\(stubExe).app")
        guard status == 0, fm.fileExists(atPath: product.path) else {
            throw Problem(message: "Xcode couldn't sign for your team:\n" + Devices.tail(output.filter { $0.contains("error") }.joined(separator: "\n"), lines: 6))
        }
        try? fm.removeItem(at: planDir)
        try fm.createDirectory(at: planDir, withIntermediateDirectories: true)
        var pieces: [Piece] = []
        var expires = Date.distantFuture
        for (index, bundle) in ([product] + nestedBundles(in: product)).enumerated() {
            guard let id = bundleID(of: bundle) else { throw Problem(message: "Xcode's build of Lamp's project has a piece with no id.") }
            let entitlements = await Subprocess.run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", bundle.path], mergeErrors: false, timeout: 60)
            guard entitlements.ok else { throw Problem(message: "Lamp couldn't read what Xcode signed \(id) with.") }
            let entitlementsName = "\(index).entitlements"
            try entitlementsFile(entitlements.output, for: place).write(to: planDir.appendingPathComponent(entitlementsName))
            var profileName: String?
            if let profile = [bundle.appendingPathComponent("embedded.mobileprovision"),
                              bundle.appendingPathComponent("Contents/embedded.provisionprofile")].first(where: { fm.fileExists(atPath: $0.path) }) {
                profileName = "\(index).profile"
                try fm.copyItem(at: profile, to: planDir.appendingPathComponent(profileName!))
                if let date = await expiry(of: profile) { expires = min(expires, date) }
            }
            pieces.append(Piece(path: relative(bundle, in: product), id: id, entitlements: entitlementsName, profile: profileName))
        }
        let plan = Plan(stamp: stamp, expires: expires, pieces: pieces)
        try JSONEncoder().encode(plan).write(to: planDir.appendingPathComponent("plan.json"))
        return (plan, planDir)
    }

    /// Signs `app`, a copy in Lamp's own folder, piece by piece as `plan` says, the innermost first: its profile put
    /// in, then the piece with its entitlements. Pieces are matched by id, the one thing about them that comes from Lamp
    /// (Lamp's project has names of its own). A build holding a piece Lamp's plan doesn't have, or missing one, or
    /// holding a program or library that isn't a piece's own (`checkCode`), isn't signed: Lamp signs only the app it planned.
    static func sign(_ app: URL, with plan: Plan, in planDir: URL, identity: String) async throws {
        let fm = FileManager.default
        var bundles: [(URL, Piece)] = []
        for bundle in [app] + nestedBundles(in: app) {
            guard let piece = plan.pieces.first(where: { $0.id == bundleID(of: bundle) && $0.path.isEmpty == (bundle == app) }),
                  !bundles.contains(where: { $0.1 == piece }) else {
                throw Problem(message: "its build holds pieces Lamp didn't make, so Lamp won't sign it.")
            }
            bundles.append((bundle, piece))
        }
        guard bundles.count == plan.pieces.count else { throw Problem(message: "its build is missing a piece Lamp made, so Lamp won't sign it.") }
        try checkCode(in: app, allowing: bundles.map(\.0))
        _ = await Subprocess.run("/usr/bin/xattr", ["-cr", app.path], timeout: 60)
        for (bundle, piece) in bundles.sorted(by: { $0.0.pathComponents.count > $1.0.pathComponents.count }) {
            let mac = fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path)
            let embedded = bundle.appendingPathComponent(mac ? "Contents/embedded.provisionprofile" : "embedded.mobileprovision")
            try? fm.removeItem(at: embedded)
            if let profile = piece.profile { try fm.copyItem(at: planDir.appendingPathComponent(profile), to: embedded) }
            let signed = await Subprocess.run("/usr/bin/codesign", ["--force", "--sign", identity, "--generate-entitlement-der",
                                                                    "--entitlements", planDir.appendingPathComponent(piece.entitlements).path, bundle.path],
                                              timeout: 120)
            guard signed.ok else { throw Problem(message: "Lamp couldn't sign \(piece.id):\n" + Devices.tail(signed.output, lines: 4)) }
        }
        let check = await Subprocess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", app.path], timeout: 120)
        guard check.ok else { throw Problem(message: "The signed app doesn't check out:\n" + Devices.tail(check.output, lines: 4)) }
    }

    /// What Xcode signed a piece with, as it's kept. On the Mac without `get-task-allow`, which Xcode adds to a
    /// development signature: it lets a debugger into the app, and the app holds its own secrets while it runs
    /// (`AppSecrets`), so no Mac app Lamp signs has it. A phone keeps it: there, only a Mac it trusts can attach.
    private static func entitlementsFile(_ xml: String, for place: Place) throws -> Data {
        guard place == .mac else { return Data(xml.utf8) }
        guard var plist = try PropertyListSerialization.propertyList(from: Data(xml.utf8), format: nil) as? [String: Any] else {
            throw Problem(message: "Lamp couldn't read what Xcode signed the app with.")
        }
        plist["com.apple.security.get-task-allow"] = nil
        return try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
    }

    // MARK: - Lamp's own project

    /// The code Lamp's project is built from: for each target, the least that builds as that kind of program. It's
    /// never run; Xcode only needs something to sign.
    private static func writeStubCode(for project: LampProject, in code: URL) throws {
        let fm = FileManager.default
        try? fm.removeItem(at: code)
        let widgetBundle: (String) -> String = { name in
            """
            import SwiftUI
            import WidgetKit

            @main struct \(name)Bundle: WidgetBundle { var body: some Widget { \(name)() } }
            struct \(name)Entry: TimelineEntry { let date: Date }
            struct \(name)Timeline: TimelineProvider {
                func placeholder(in context: Context) -> \(name)Entry { \(name)Entry(date: .now) }
                func getSnapshot(in context: Context, completion: @escaping (\(name)Entry) -> Void) { completion(\(name)Entry(date: .now)) }
                func getTimeline(in context: Context, completion: @escaping (Timeline<\(name)Entry>) -> Void) { completion(Timeline(entries: [], policy: .never)) }
            }
            struct \(name): Widget {
                var body: some WidgetConfiguration { StaticConfiguration(kind: "lamp", provider: \(name)Timeline()) { _ in EmptyView() } }
            }

            """
        }
        var files = [("Sources/App.swift", """
            import SwiftUI

            @main struct LampSigningApp: App { var body: some Scene { WindowGroup { EmptyView() } } }

            """)]
        if Template.hasWidget(project) {
            files.append(("Widget/Widget.swift", widgetBundle("LampSigningWidget")))
            files.append(("Widget/\(Template.sharedWidgetFolder)/Shared.swift", "// Nothing shared.\n"))
        }
        if Template.hasShare(project) {
            files.append(("Share/Share.swift", "import UIKit\n\nfinal class LampShareController: UIViewController {}\n"))
        }
        if Template.hasWatch(project) {
            files.append(("Watch/Watch.swift", """
                import SwiftUI

                @main struct LampSigningWatch: App { var body: some Scene { WindowGroup { EmptyView() } } }

                """))
            if Template.hasComplications(project) {
                files.append(("Watch/\(Template.complicationsFolder)/Complications.swift", widgetBundle("LampSigningComplication")))
            }
        }
        try fm.createDirectory(at: code.appendingPathComponent(Sharing.Assets.folder), withIntermediateDirectories: true)
        for (path, text) in files {
            let url = code.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(text.utf8).write(to: url)
        }
    }

    struct ForeignCode: LocalizedError {
        var errorDescription: String? { "its build holds a program Lamp didn't make, so Lamp won't sign it." }
    }

    /// Throws when `app` holds a program or library (anything macOS would load or run) other than the main program of
    /// one of `bundles`: Lamp's project builds nothing else, and what the build left there would be sealed inside
    /// what's signed for the team.
    static func checkCode(in app: URL, allowing bundles: [URL]) throws {
        let fm = FileManager.default
        let allowed = Set(bundles.compactMap { bundle -> String? in
            let mac = fm.fileExists(atPath: bundle.appendingPathComponent("Contents/Info.plist").path)
            let info = NSDictionary(contentsOf: bundle.appendingPathComponent(mac ? "Contents/Info.plist" : "Info.plist"))
            guard let executable = info?["CFBundleExecutable"] as? String else { return nil }
            return bundle.appendingPathComponent(mac ? "Contents/MacOS/\(executable)" : executable).standardizedFileURL.path
        })
        // What can't be read or listed counts as code Lamp didn't make: unread, it can't be told apart.
        var unreadable = false
        let items = fm.enumerator(at: app, includingPropertiesForKeys: [.isRegularFileKey], errorHandler: { _, _ in unreadable = true; return false })?
            .compactMap { $0 as? URL } ?? []
        guard !unreadable else { throw ForeignCode() }
        for file in items where (try? file.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true && isCode(file) {
            guard allowed.contains(file.standardizedFileURL.path) else { throw ForeignCode() }
        }
    }

    /// Whether the file starts like a program or library macOS would run: Mach-O, either byte order, or fat. A file
    /// that can't be opened counts as one.
    private static func isCode(_ file: URL) -> Bool {
        guard let handle = try? FileHandle(forReadingFrom: file) else { return true }
        defer { try? handle.close() }
        guard let head = try? handle.read(upToCount: 4), head.count == 4 else { return false }
        let magic = head.withUnsafeBytes { $0.loadUnaligned(as: UInt32.self) }
        return [0xfeedface, 0xfeedfacf, 0xcefaedfe, 0xcffaedfe, 0xcafebabe, 0xbebafeca, 0xcafebabf, 0xbfbafeca].contains(magic)
    }

    // MARK: - Reading bundles

    /// The bundles inside `app` that are signed on their own: extensions and the watch app, at any depth.
    static func nestedBundles(in app: URL) -> [URL] {
        let items = FileManager.default.enumerator(at: app, includingPropertiesForKeys: [.isSymbolicLinkKey])?.compactMap { $0 as? URL } ?? []
        return items.filter { ["app", "appex"].contains($0.pathExtension) && (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink != true }
            .sorted { $0.path < $1.path }
    }

    static func bundleID(of bundle: URL) -> String? {
        let plists = [bundle.appendingPathComponent("Contents/Info.plist"), bundle.appendingPathComponent("Info.plist")]
        return plists.lazy.compactMap { NSDictionary(contentsOf: $0)?["CFBundleIdentifier"] as? String }.first
    }

    private static func relative(_ bundle: URL, in app: URL) -> String {
        let base = app.standardizedFileURL.path, path = bundle.standardizedFileURL.path
        return path == base ? "" : String(path.dropFirst(base.count + 1))
    }

    /// Removes Xcode's own copies of the development profiles for these app ids ("TEAM.bundle.id"), so its next signing
    /// makes new ones. Only profiles Xcode made for its automatic signing, matched by their exact app id.
    private static func forgetXcodeProfiles(for appIDs: [String]) async {
        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"] {
            for file in (try? FileManager.default.contentsOfDirectory(at: home.appendingPathComponent(folder), includingPropertiesForKeys: nil)) ?? []
            where file.pathExtension == "mobileprovision" {
                let decoded = await Subprocess.run("/usr/bin/security", ["cms", "-D", "-i", file.path], mergeErrors: false, timeout: 30)
                guard decoded.ok, let plist = try? PropertyListSerialization.propertyList(from: Data(decoded.output.utf8), format: nil) as? [String: Any],
                      plist["IsXcodeManaged"] as? Bool == true,
                      let appID = (plist["Entitlements"] as? [String: Any])?["application-identifier"] as? String, appIDs.contains(appID) else { continue }
                try? FileManager.default.removeItem(at: file)
            }
        }
    }

    static func expiry(of profile: URL) async -> Date? {
        let decoded = await Subprocess.run("/usr/bin/security", ["cms", "-D", "-i", profile.path], mergeErrors: false, timeout: 30)
        guard decoded.ok, let plist = try? PropertyListSerialization.propertyList(from: Data(decoded.output.utf8), format: nil) as? [String: Any]
        else { return nil }
        return plist["ExpirationDate"] as? Date
    }

    /// A hash of every file Lamp's project is made of (Xcode's build of it left out), and `extra`.
    private static func stamp(of folders: [URL], extra: String) -> String {
        var hash = SHA256()
        hash.update(data: Data(extra.utf8))
        for folder in folders {
            let files = (FileManager.default.enumerator(at: folder, includingPropertiesForKeys: [.isRegularFileKey])?.compactMap { $0 as? URL } ?? [])
                .filter { (try? $0.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true }
                .sorted { $0.path < $1.path }
            for file in files {
                hash.update(data: Data(file.path.dropFirst(folder.path.count).utf8))
                hash.update(data: (try? Data(contentsOf: file)) ?? Data())
            }
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

extension LampProject {
    /// The same app under other names, everything else kept: for a project of Lamp's own that mustn't carry the
    /// names in the app's meta.json, which the agent can write.
    func named(_ name: String, exe: String) -> LampProject {
        var copy = LampProject(id: id, name: name, exe: exe, dir: dir)
        copy.instance = instance
        copy.untitled = untitled
        copy.fromWish = fromWish
        copy.finding = finding
        copy.platform = platform
        copy.family = family
        copy.device = device
        copy.chosen = chosen
        copy.simulator = simulator
        return copy
    }
}
