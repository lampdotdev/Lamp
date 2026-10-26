import XCTest
@testable import Lamp

/// What Apple allows a free Apple account (a Personal Team), found by asking it the way Lamp signs: Lamp's own project
/// planned by Xcode for that team (`TeamSigning.plan`). Only when asked, since every plan registers ids with the team
/// and a free team gets 10 a week: `LAMP_FREE_TEAM=<team id> LAMP_FREE_TEAM_DEVICE=<udid> swift test --filter
/// FreeTeamProbeLiveTests`, on a Mac with Xcode signed in to that account and the phone paired. Every probe uses the same
/// app id, so the whole run costs two of the week's ids (the app's and a widget's). `LAMP_FREE_TEAM_OUT=<file>` keeps
/// what was found. The reinstall test puts a small app on the phone, never opens it, and takes it off again.
@MainActor
final class FreeTeamProbeLiveTests: XCTestCase {
    private var root: URL?
    private var projects: [LampProject] = []
    private var savedTeam: String?
    private var report: [String] = []

    override func tearDown() async throws {
        let fm = FileManager.default
        if let root { try? fm.removeItem(at: root) }
        for project in projects {
            try? fm.removeItem(at: Devices.buildFolder(for: project))
            try? fm.removeItem(at: Devices.signingFolder(for: project))
        }
        for folder in [Devices.buildsFolder.appendingPathComponent(".signing"), Devices.buildsFolder]
        where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
        if let savedTeam { Devices.team = savedTeam }
        if let out = ProcessInfo.processInfo.environment["LAMP_FREE_TEAM_OUT"] {
            let before = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
            try? (before + report.joined(separator: "\n") + "\n\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    private func setUp() throws -> (team: String, device: String, project: LampProject) {
        let env = ProcessInfo.processInfo.environment
        guard let team = env["LAMP_FREE_TEAM"], team.count == 10, let device = env["LAMP_FREE_TEAM_DEVICE"], !device.isEmpty else {
            throw XCTSkip("Set LAMP_FREE_TEAM to a free team's id and LAMP_FREE_TEAM_DEVICE to a paired phone's udid.")
        }
        // Xcode lists a newly added account's team only once something has been signed for it, so its mark is reported, not required.
        report.append("Xcode marks \(team) as free: \(PhoneTools.xcodeFreeTeams().contains(team))")
        savedTeam = Devices.team
        Devices.team = team
        let fm = FileManager.default
        root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-free-team-\(UUID().uuidString)")
        try fm.createDirectory(at: root!, withIntermediateDirectories: true)
        // The same folder name every run, so the app id is the same and a second run costs no more ids.
        let project = try Template.scaffold(name: "Lamp Free Probe", platform: .iphone, in: root!)
        projects.append(project)
        try Template.writeOwnedFiles(for: project)
        return (team, device, project)
    }

    private func setCapabilities(_ json: String, of project: LampProject) throws {
        try json.write(to: project.dir.appendingPathComponent(Template.Capabilities.file), atomically: true, encoding: .utf8)
    }

    /// The decoded profile: its UUID, expiry and entitlements.
    private func profile(_ url: URL) async -> [String: Any] {
        let decoded = await Subprocess.run("/usr/bin/security", ["cms", "-D", "-i", url.path], mergeErrors: false, timeout: 30).output
        return (try? PropertyListSerialization.propertyList(from: Data(decoded.utf8), format: nil) as? [String: Any]) ?? [:]
    }

    private func planned(_ project: LampProject, team: String, device: String) async throws -> (plan: TeamSigning.Plan, profile: [String: Any]) {
        let (plan, dir) = try await TeamSigning.plan(for: project, team: team, place: .iphone, destination: "id=\(device)")
        let app = try XCTUnwrap(plan.app?.profile)
        return (plan, await profile(dir.appendingPathComponent(app)))
    }

    private func describe(_ profile: [String: Any]) -> String {
        let entitlements = (profile["Entitlements"] as? [String: Any])?.keys.sorted().joined(separator: ", ") ?? "?"
        return "profile \(profile["UUID"] ?? "?"), made \(profile["CreationDate"] ?? "?"), expires \(profile["ExpirationDate"] ?? "?"); entitlements: \(entitlements)"
    }

    /// Each capability Lamp declares, on its own, planned for the free team: signed, or Apple's refusal.
    func testWhichCapabilitiesAFreeTeamSigns() async throws {
        let (team, device, project) = try setUp()
        report.append("# Capabilities for a free team (\(Date()))")
        try setCapabilities("{}", of: project)
        let (_, baseline) = try await planned(project, team: team, device: device)
        report.append("none: signs; " + describe(baseline))
        let capabilities = ["healthkit", "nfc", "siri", "icloud", "weather", "homekit", "timeSensitive"]
        for capability in capabilities {
            try setCapabilities("{\"\(capability)\": true}", of: project)
            do {
                let (_, profile) = try await planned(project, team: team, device: device)
                report.append("\(capability): signs; " + describe(profile))
            } catch {
                report.append("\(capability): refused: " + error.localizedDescription.replacingOccurrences(of: "\n", with: " | "))
            }
        }
        // A widget is a second id, and Lamp gives the app and its widget an app group to share through.
        try setCapabilities("{}", of: project)
        let widget = project.dir.appendingPathComponent(Template.widgetFolder)
        try FileManager.default.createDirectory(at: widget, withIntermediateDirectories: true)
        try "import WidgetKit\n".write(to: widget.appendingPathComponent("Widget.swift"), atomically: true, encoding: .utf8)
        do {
            let (plan, profile) = try await planned(project, team: team, device: device)
            report.append("widget (app group): signs, \(plan.pieces.count) pieces; " + describe(profile))
        } catch {
            report.append("widget (app group): refused: " + error.localizedDescription.replacingOccurrences(of: "\n", with: " | "))
        }
    }

    /// Whether Xcode gives a new seven-day profile before the old one runs out: planned again as it is, then again with
    /// Xcode's own copy of the profile removed.
    func testWhetherAProfileRenewsEarly() async throws {
        let (team, device, project) = try setUp()
        report.append("# Renewing a free team's profile early (\(Date()))")
        try setCapabilities("{}", of: project)
        let (_, first) = try await planned(project, team: team, device: device)
        report.append("first: " + describe(first))

        let planFile = TeamSigning.folder(for: project, place: .iphone).appendingPathComponent("Plan/plan.json")
        try? FileManager.default.removeItem(at: planFile)
        let (_, replanned) = try await planned(project, team: team, device: device)
        report.append("planned again: " + describe(replanned)
                      + ((replanned["UUID"] as? String) == (first["UUID"] as? String) ? " (the same profile)" : " (a new profile)"))

        let appID = "\(team).\(project.deviceBundleID(team: team))"
        var removed: [String] = []
        let home = FileManager.default.homeDirectoryForCurrentUser
        for folder in ["Library/Developer/Xcode/UserData/Provisioning Profiles", "Library/MobileDevice/Provisioning Profiles"] {
            let dir = home.appendingPathComponent(folder)
            for file in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                let info = await profile(file)
                guard (info["Entitlements"] as? [String: Any])?["application-identifier"] as? String == appID else { continue }
                try? FileManager.default.removeItem(at: file)
                removed.append("\(folder)/\(file.lastPathComponent)")
            }
        }
        report.append("removed Xcode's copies: " + (removed.isEmpty ? "none found" : removed.joined(separator: ", ")))
        try? FileManager.default.removeItem(at: planFile)
        let (_, regenerated) = try await planned(project, team: team, device: device)
        report.append("planned with Xcode's copy gone: " + describe(regenerated)
                      + ((regenerated["UUID"] as? String) == (first["UUID"] as? String) ? " (the same profile)" : " (a new profile)"))
    }

    /// An app signed again and put back over itself keeps what it saved, as a weekly renewal would. Never opened.
    func testAReinstallKeepsTheAppsData() async throws {
        let (team, device, project) = try setUp()
        report.append("# Reinstalling over itself (\(Date()))")
        try setCapabilities("{}", of: project)
        let devicectl = DeveloperTools.path("devicectl")
        let bundleID = project.deviceBundleID(team: team)
        try await Devices.stage(project, team: team)
        var output: [String] = []
        let built = try await Devices.build(project, team: team, destination: "id=\(device)") { output.append($0) }
        let copy = try await Devices.signedCopy(of: built, for: project, team: team, destination: "id=\(device)") { output.append($0) }
        try await Devices.install(copy, on: device)
        defer {
            Task { _ = await Subprocess.run(devicectl, ["device", "uninstall", "app", "--device", device, bundleID], timeout: 120) }
        }
        let marker = root!.appendingPathComponent("marker.txt")
        try "kept".write(to: marker, atomically: true, encoding: .utf8)
        let container = ["--domain-type", "appDataContainer", "--domain-identifier", bundleID, "--device", device]
        let put = await Subprocess.run(devicectl, ["device", "copy", "to", "--source", marker.path, "--destination", "Documents/marker.txt"] + container, timeout: 120)
        XCTAssertTrue(put.ok, put.output + put.errors)
        report.append("marker put in the app's container: \(put.ok)")

        try? FileManager.default.removeItem(at: TeamSigning.folder(for: project, place: .iphone).appendingPathComponent("Plan/plan.json"))
        let again = try await Devices.signedCopy(of: built, for: project, team: team, destination: "id=\(device)") { output.append($0) }
        try await Devices.install(again, on: device)
        let back = root!.appendingPathComponent("back.txt")
        let got = await Subprocess.run(devicectl, ["device", "copy", "from", "--source", "Documents/marker.txt", "--destination", back.path] + container, timeout: 120)
        let kept = (try? String(contentsOf: back, encoding: .utf8)) == "kept"
        report.append("after signing again and reinstalling, the marker is " + (kept ? "still there" : "gone: " + got.output + got.errors))
        XCTAssertTrue(kept)
        _ = await Subprocess.run(devicectl, ["device", "uninstall", "app", "--device", device, bundleID], timeout: 120)
    }
}
