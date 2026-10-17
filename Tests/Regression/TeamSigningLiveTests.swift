import XCTest
@testable import Lamp

/// Signing for a real Apple team, as Lamp does it: the app built in its sandbox with signing off, then Lamp's copy
/// signed with what Xcode signed Lamp's own project with. Builds and signs only (nothing is installed, opened or put
/// on a phone), and only when asked, since Xcode registers the apps' ids with the team and makes their profiles:
/// `LAMP_TEAM_CHECK=<team id> swift test --filter TeamSigningLiveTests`, on a Mac with Xcode signed in to that team
/// and its Apple Development certificate. `LAMP_TEAM_CHECK_OUT=<file>` keeps what was checked.
@MainActor
final class TeamSigningLiveTests: XCTestCase {
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
        if let out = ProcessInfo.processInfo.environment["LAMP_TEAM_CHECK_OUT"] {
            let before = (try? String(contentsOfFile: out, encoding: .utf8)) ?? ""
            try? (before + report.joined(separator: "\n") + "\n\n").write(toFile: out, atomically: true, encoding: .utf8)
        }
    }

    private func team() throws -> String {
        guard let team = ProcessInfo.processInfo.environment["LAMP_TEAM_CHECK"], team.count == 10 else {
            throw XCTSkip("Set LAMP_TEAM_CHECK to a team id to sign for it.")
        }
        savedTeam = Devices.team
        Devices.team = team
        let fm = FileManager.default
        if root == nil {
            root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-team-check-\(UUID().uuidString)")
            try fm.createDirectory(at: root!, withIntermediateDirectories: true)
        }
        return team
    }

    /// How a bundle is signed, as codesign says it: the team and authority, or that it's only the linker's ad hoc one.
    private func signatureLines(_ output: String) -> String {
        let keys = ["Signature=", "TeamIdentifier=", "Authority=", "CodeDirectory", "code object"]
        return output.split(separator: "\n").filter { line in keys.contains { line.contains($0) } }.joined(separator: " | ")
    }

    /// What the signed bundle says about itself, with no device ids.
    private func describe(_ bundle: URL, profile: URL) async -> (signature: String, entitlements: [String: Any], profile: [String: Any]) {
        let signature = await Subprocess.run("/usr/bin/codesign", ["-dvv", bundle.path], timeout: 60).output
        let entitlements = await Subprocess.run("/usr/bin/codesign", ["-d", "--entitlements", "-", "--xml", bundle.path], mergeErrors: false, timeout: 60).output
        let decoded = await Subprocess.run("/usr/bin/security", ["cms", "-D", "-i", profile.path], mergeErrors: false, timeout: 60).output
        let plist = (try? PropertyListSerialization.propertyList(from: Data(entitlements.utf8), format: nil) as? [String: Any]) ?? [:]
        let profileInfo = (try? PropertyListSerialization.propertyList(from: Data(decoded.utf8), format: nil) as? [String: Any]) ?? [:]
        let keys = ["Identifier=", "Authority=", "TeamIdentifier=", "Signature size"]
        let lines = signature.split(separator: "\n").filter { line in keys.contains { line.hasPrefix($0) } }
        report.append("\(bundle.lastPathComponent):\n  " + lines.joined(separator: "\n  "))
        report.append("  entitlements: \(plist.keys.sorted().joined(separator: ", "))")
        report.append("  profile: \(profileInfo["Name"] ?? "?"), team \((profileInfo["TeamIdentifier"] as? [String])?.joined() ?? "?"), "
                      + "expires \(profileInfo["ExpirationDate"] ?? "?"), \((profileInfo["ProvisionedDevices"] as? [Any])?.count ?? 0) devices")
        return (signature, plist, profileInfo)
    }

    func testTheMacHalfOfAnAppForBothIsSignedForTheTeam() async throws {
        let team = try team()
        let project = try Template.scaffold(name: "Lamp Signing Both", platform: .universal, in: root!)
        projects.append(project)
        try Template.writeOwnedFiles(for: project)
        var output: [String] = []
        let status = await Store.runBuild("./build.sh mac", for: project, env: ["LAMP_TEAM": team]) { output.append($0) }
        XCTAssertEqual(status, 0, output.suffix(30).joined(separator: "\n"))
        let unsigned = await Subprocess.run("/usr/bin/codesign", ["-dv", project.builtURL.path], timeout: 60)
        report.append("Mac half as built in the sandbox: " + signatureLines(unsigned.output))

        let staging = Devices.buildFolder(for: project).appendingPathComponent("Check")
        let copy = try Store.stage(project, in: staging)
        let signing = staging.appendingPathComponent("signing")
        try FileManager.default.createDirectory(at: signing, withIntermediateDirectories: true)
        let signed = try await Store.signForTeam(copy, for: project, team: team,
                                                env: Sidebar.signingEnvironment(in: copy, entitlementsIn: signing))
        XCTAssertTrue(signed)
        let check = await Subprocess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", copy.path], timeout: 60)
        XCTAssertTrue(check.ok, check.output)
        report.append("codesign --verify --deep --strict: " + (check.ok ? "passes" : check.output))
        let (signature, entitlements, profile) = await describe(copy, profile: copy.appendingPathComponent("Contents/embedded.provisionprofile"))
        XCTAssertTrue(signature.contains("TeamIdentifier=\(team)"), signature)
        // What Xcode signed Lamp's own project with: a Mac app gets a profile only when what it's entitled to needs one.
        let (plan, planDir) = try await TeamSigning.plan(for: project, team: team, place: .mac, destination: "platform=macOS")
        let piece = try XCTUnwrap(plan.app)
        let planned = try XCTUnwrap(try PropertyListSerialization.propertyList(from: Data(contentsOf: planDir.appendingPathComponent(piece.entitlements)), format: nil) as? [String: Any])
        XCTAssertEqual(NSDictionary(dictionary: entitlements), NSDictionary(dictionary: planned))
        XCTAssertNil(entitlements["com.apple.security.get-task-allow"], "a Mac app Lamp signs lets a debugger in")
        if piece.profile != nil { XCTAssertEqual(profile["TeamIdentifier"] as? [String], [team]) }
        report.append("  Xcode's own signing of Lamp's project: \(planned.keys.sorted().joined(separator: ", ")), " + (piece.profile == nil ? "no profile" : "a profile"))
    }

    func testAPhoneAppIsSignedForTheTeam() async throws {
        let team = try team()
        let project = try Template.scaffold(name: "Lamp Signing Phone", platform: .iphone, in: root!)
        projects.append(project)
        try Template.writeOwnedFiles(for: project)
        try await Devices.stage(project, team: team)
        var output: [String] = []
        let built = try await Devices.build(project, team: team, destination: "generic/platform=iOS") { output.append($0) }
        let unsigned = await Subprocess.run("/usr/bin/codesign", ["-dv", built.path], timeout: 60)
        report.append("Phone app as built in the sandbox: " + signatureLines(unsigned.output))
        let copy = try await Devices.signedCopy(of: built, for: project, team: team, destination: "generic/platform=iOS") { output.append($0) }
        let check = await Subprocess.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", copy.path], timeout: 60)
        XCTAssertTrue(check.ok, check.output)
        report.append("codesign --verify --deep --strict: " + (check.ok ? "passes" : check.output))
        let (signature, entitlements, profile) = await describe(copy, profile: copy.appendingPathComponent("embedded.mobileprovision"))
        XCTAssertTrue(signature.contains("TeamIdentifier=\(team)"), signature)
        XCTAssertEqual(entitlements["application-identifier"] as? String, "\(team).\(project.deviceBundleID(team: team))")
        XCTAssertEqual(profile["TeamIdentifier"] as? [String], [team])
    }
}
