import XCTest
@testable import Lamp

/// Apple Health through `LampHealth` in LampSupport.swift: signed for on the iPhone alone, with every kind
/// of data named with its unit, and told to the agent for apps with an iPhone half.
@MainActor
final class HealthTests: XCTestCase {
    private var root: URL?
    private var team: Any?

    override func setUp() {
        team = UserDefaults.standard.object(forKey: "appleTeam")
        UserDefaults.standard.set("ABCDE12345", forKey: "appleTeam")
    }

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
        UserDefaults.standard.set(team, forKey: "appleTeam")
    }

    private func app(_ platform: Platform) throws -> LampProject {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        self.root = root
        return try Template.draft(name: "Step Count", platform: platform, in: root)
    }

    func testTheHealthEntitlementIsTheIPhonesOnly() throws {
        var capabilities = Template.Capabilities()
        capabilities.healthkit = true
        let both = try app(.universal)
        XCTAssertTrue(capabilities.entitlementsPlist(for: both, platform: .ios).contains("<key>com.apple.developer.healthkit</key><true/>"))
        XCTAssertFalse(capabilities.entitlementsPlist(for: both, platform: .mac).contains("healthkit"), "a Mac's signature can't claim Health")
        try Template.fill(both)
        try #"{"healthkit": true}"#.write(to: both.dir.appendingPathComponent("capabilities.json"), atomically: true, encoding: .utf8)
        try Template.writeDeviceProject(for: both, team: "ABCDE12345")
        XCTAssertTrue(try String(contentsOf: both.dir.appendingPathComponent(".lamp/device/App.entitlements"), encoding: .utf8).contains("healthkit"))
        XCTAssertFalse(try String(contentsOf: both.dir.appendingPathComponent(".lamp/device/App-macOS.entitlements"), encoding: .utf8).contains("healthkit"))
        // The simulator's build takes them from a section of the binary, which build.sh puts there from the file Lamp writes.
        try Template.writeOwnedFiles(for: both)
        let simulator = try String(contentsOf: both.dir.appendingPathComponent(".lamp/entitlements.plist"), encoding: .utf8)
        XCTAssertTrue(simulator.contains("healthkit"))
        // With the app's identity, which Health and iCloud look for; a plain app's file stays empty of keys.
        XCTAssertTrue(simulator.contains("<key>application-identifier</key><string>ABCDE12345.\(both.bundleID)</string>"))
        XCTAssertTrue(simulator.contains("<key>com.apple.developer.team-identifier</key><string>ABCDE12345</string>"))
        XCTAssertFalse(Template.Capabilities().simulatorEntitlementsPlist(for: both).contains("application-identifier"))
        XCTAssertTrue(try String(contentsOf: both.dir.appendingPathComponent("build.sh"), encoding: .utf8).contains("-sectcreate -Xlinker __TEXT -Xlinker __entitlements -Xlinker \"$HASHED\""))
        var mac = both; mac.platform = .mac
        try Template.saveMeta(mac)
        try Template.writeOwnedFiles(for: mac)
        XCTAssertFalse(try String(contentsOf: mac.dir.appendingPathComponent("build.sh"), encoding: .utf8).contains("__entitlements"))
    }

    func testTheAgentIsToldForAppsWithAnIPhoneHalf() throws {
        let both = try app(.universal)
        XCTAssertTrue(Agent.systemPrompt(for: both).contains("`LampHealth` from LampSupport.swift"))
        var phone = both; phone.platform = .iphone
        XCTAssertTrue(Agent.systemPrompt(for: phone).contains("`LampHealth` from LampSupport.swift"))
        var mac = both; mac.platform = .mac
        XCTAssertFalse(Agent.systemPrompt(for: mac).contains("LampHealth"))
    }

    /// The app's copy of the block, cut out of the template and compiled: every kind has a unit the person
    /// would write, sleep is the one read as time, and what adds up is told from what doesn't.
    func testEveryKindOfHealthDataHasItsUnit() throws {
        let support = Template.lampSupportSwift
        let start = try XCTUnwrap(support.range(of: "    enum LampHealth {"))
        let end = try XCTUnwrap(support.range(of: "    // MARK: - Photos", range: start.upperBound..<support.endIndex))
        let program = """
        import Foundation
        import HealthKit
        \(support[start.lowerBound..<end.lowerBound])
        for kind in LampHealth.Kind.allCases {
            print(kind.rawValue, kind.unitName, kind.isCumulative ? "sum" : "latest", kind.unit.unitString)
        }
        let night = Date(timeIntervalSince1970: 0)
        func at(_ hours: Double) -> Date { night.addingTimeInterval(hours * 3600) }
        // A watch's stages over the same hours as a sleep app's one record: eight hours, not sixteen.
        print("asleep", LampHealth.asleepSeconds([(at(0), at(8)), (at(0), at(3)), (at(3), at(5.5)), (at(6), at(8)), (at(10), at(11))]) / 3600)
        """
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-health-unit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: work) }
        try program.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        let built = try run(Shell.compatibleSDK + "xcrun swiftc -o health main.swift 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let lines = try run("./health", in: work).output.split(separator: "\n").map(String.init)
        XCTAssertEqual(lines.count, 32)
        XCTAssertTrue(lines.contains("asleep 9.0"))
        XCTAssertTrue(lines.contains("steps steps sum count"))
        XCTAssertTrue(lines.contains("heartRate bpm latest count/min"))
        XCTAssertTrue(lines.contains("caloriesEaten kcal sum kcal"))
        XCTAssertTrue(lines.contains("weight kg latest kg"))
        XCTAssertTrue(lines.contains("bloodOxygen % latest %"))
        XCTAssertTrue(lines.contains("sleep hours latest hr"))
        // Only the one kind with no unit to write.
        XCTAssertEqual(lines.filter { $0.hasPrefix("bodyMassIndex ") }, ["bodyMassIndex  latest count"])
    }

    private func run(_ command: String, in directory: URL) throws -> (status: Int32, output: String) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", command]
        process.currentDirectoryURL = directory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return (process.terminationStatus, String(decoding: data, as: UTF8.self))
    }
}
