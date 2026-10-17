import XCTest
@testable import Lamp

/// The phone's project leaves a watch app's complications out of the watch app's own target (Xcode takes them per
/// file), listed from the app's files as they are when the project is written, before they're copied beside it.
@MainActor
final class PhoneWatchStageTests: XCTestCase {
    private var root: URL?
    private var project: LampProject?

    override func tearDown() {
        let fm = FileManager.default
        if let root { try? fm.removeItem(at: root) }
        if let project { try? fm.removeItem(at: Devices.buildFolder(for: project)) }
        if (try? fm.contentsOfDirectory(atPath: Devices.buildsFolder.path))?.isEmpty == true { try? fm.removeItem(at: Devices.buildsFolder) }
    }

    func testAStagedPhoneProjectLeavesTheComplicationsOutOfTheWatchApp() async throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-watch-stage-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Watch Stage", platform: .iphone, in: root)
        self.project = project
        let complications = project.dir.appendingPathComponent(Template.watchFolder).appendingPathComponent(Template.complicationsFolder)
        try fm.createDirectory(at: complications, withIntermediateDirectories: true)
        try "import SwiftUI\n".write(to: project.dir.appendingPathComponent(Template.watchFolder).appendingPathComponent("WatchApp.swift"),
                                     atomically: true, encoding: .utf8)
        try "import WidgetKit\n".write(to: complications.appendingPathComponent("Faces.swift"), atomically: true, encoding: .utf8)
        try await Devices.stage(project, team: "ABCDE12345")
        let pbxproj = try String(contentsOf: Devices.buildFolder(for: project).appendingPathComponent("\(project.exe).xcodeproj/project.pbxproj"),
                                 encoding: .utf8)
        XCTAssertTrue(pbxproj.contains("\(Template.complicationsFolder)/Faces.swift"), "the watch app's target would compile its complications")
    }
}
