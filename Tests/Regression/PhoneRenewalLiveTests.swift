import XCTest
@testable import Lamp

/// Putting an app back on a real phone the way Lamp's renewals do (`Devices.renew`): installed and kept as Lamp keeps
/// what's on a phone, then signed again with a new profile and installed over itself, never opened. Only when asked:
/// `LAMP_RENEW_TEAM=<team id> LAMP_RENEW_DEVICE=<udid> swift test --filter PhoneRenewalLiveTests`, on a Mac with Xcode
/// signed in to that team and the phone paired. It uses the same app id as `FreeTeamProbeLiveTests`, so a free team
/// that ran the probe this week spends no more of its ids. The app is taken off the phone again.
@MainActor
final class PhoneRenewalLiveTests: XCTestCase {
    private var root: URL?
    private var project: LampProject?
    private var savedTeam: String?
    private var installed: (device: String, bundleID: String)?

    override func tearDown() async throws {
        if let installed {
            let removed = await Subprocess.run(DeveloperTools.path("devicectl"), ["device", "uninstall", "app", "--device", installed.device, installed.bundleID], timeout: 120)
            XCTAssertTrue(removed.ok, "the test app is still on the phone: " + removed.output + removed.errors)
        }
        let fm = FileManager.default
        if let root { try? fm.removeItem(at: root) }
        if let project {
            try? fm.removeItem(at: Devices.buildFolder(for: project))
            try? fm.removeItem(at: Devices.signingFolder(for: project))
        }
        for folder in [Devices.buildsFolder.appendingPathComponent(".signing"), Devices.buildsFolder]
        where (try? fm.contentsOfDirectory(atPath: folder.path))?.isEmpty == true { try? fm.removeItem(at: folder) }
        if let savedTeam { Devices.team = savedTeam }
    }

    func testAnAppIsPutBackWithANewProfileAndKeepsItsData() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let team = env["LAMP_RENEW_TEAM"], team.count == 10, let device = env["LAMP_RENEW_DEVICE"], !device.isEmpty else {
            throw XCTSkip("Set LAMP_RENEW_TEAM to a team id and LAMP_RENEW_DEVICE to a paired phone's udid.")
        }
        savedTeam = Devices.team
        Devices.team = team
        let fm = FileManager.default
        root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-renew-\(UUID().uuidString)")
        try fm.createDirectory(at: root!, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Lamp Free Probe", platform: .iphone, in: root!)
        self.project = project
        try Template.writeOwnedFiles(for: project)
        try await Devices.stage(project, team: team)
        let built = try await Devices.build(project, team: team, destination: "id=\(device)") { _ in }
        let copy = try await Devices.signedCopy(of: built, for: project, team: team, destination: "id=\(device)") { _ in }
        try await Devices.install(copy, on: device)
        let bundleID = project.deviceBundleID(team: team)
        installed = (device, bundleID)
        await PhoneRenewals.keep(copy, for: project, udid: device, team: team)
        let record = try XCTUnwrap(PhoneRenewals.record(for: project), "what's on the phone is kept")
        XCTAssertEqual(record.bundleID, bundleID)
        XCTAssertTrue(fm.fileExists(atPath: PhoneRenewals.keptApp(for: project).path))

        let devicectl = DeveloperTools.path("devicectl")
        let container = ["--domain-type", "appDataContainer", "--domain-identifier", bundleID, "--device", device]
        let marker = root!.appendingPathComponent("marker.txt")
        try "kept".write(to: marker, atomically: true, encoding: .utf8)
        let put = await Subprocess.run(devicectl, ["device", "copy", "to", "--source", marker.path, "--destination", "Documents/marker.txt"] + container, timeout: 120)
        XCTAssertTrue(put.ok, put.output + put.errors)

        // A second apart at least, so a new profile's dates can't match the first's.
        try await Task.sleep(for: .seconds(2))
        let expires = try await Devices.renew(project, record: record)
        print("first profile runs out \(record.expires), the renewed one \(expires)")
        XCTAssertGreaterThan(expires, record.expires, "the renewed profile runs out later than the one before")

        let back = root!.appendingPathComponent("back.txt")
        let got = await Subprocess.run(devicectl, ["device", "copy", "from", "--source", "Documents/marker.txt", "--destination", back.path] + container, timeout: 120)
        XCTAssertEqual(try? String(contentsOf: back, encoding: .utf8), "kept", got.output + got.errors)
    }
}
