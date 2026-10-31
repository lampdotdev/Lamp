import XCTest
@testable import Lamp

/// An iPhone app has no installed copy, so Lamp reads its stamp from its build, in the app's folder, every time it
/// reloads its apps, which it does as it starts. A build (or any command of the agent's) can leave a pipe or a link at
/// that build's Info.plist: Lamp must neither wait on the one nor read through the other.
final class BuildStampReadTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    func testAnIPhoneBuildsStampIsReadOnlyFromAPlainFileInItsFolder() throws {
        let fm = FileManager.default
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-stamp-test-\(UUID().uuidString)")
        self.root = root
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let project = try Template.scaffold(name: "Pocket", platform: .iphone, in: root)
        XCTAssertFalse(project.hasMac)
        let plist = project.builtURL.appendingPathComponent("Info.plist")
        try fm.createDirectory(at: project.builtURL, withIntermediateDirectories: true)
        let stamped = #"<?xml version="1.0" encoding="UTF-8"?><plist version="1.0"><dict><key>LampVersion</key><string>0.1</string><key>LampSupportVersion</key><string>000000</string></dict></plist>"#

        // A plain file: its stamp is read.
        try stamped.write(to: plist, atomically: true, encoding: .utf8)
        XCTAssertEqual(BuildStamp.of(project)?.support, "000000")

        // A link to a plist outside the app: not followed.
        let outside = root.appendingPathComponent("outside.plist")
        try stamped.write(to: outside, atomically: true, encoding: .utf8)
        try fm.removeItem(at: plist)
        try fm.createSymbolicLink(at: plist, withDestinationURL: outside)
        XCTAssertNil(BuildStamp.of(project), "Lamp read a stamp through a link the build left")

        // A pipe: Lamp doesn't wait for anything to be written into it.
        try fm.removeItem(at: plist)
        XCTAssertEqual(mkfifo(plist.path, 0o644), 0)
        let done = expectation(description: "read the stamp")
        DispatchQueue.global().async {
            XCTAssertNil(BuildStamp.of(project))
            done.fulfill()
        }
        let waited = XCTWaiter().wait(for: [done], timeout: 3)
        if waited != .completed {
            // Let the read that's stuck go, so the run can finish.
            let fd = open(plist.path, O_WRONLY | O_NONBLOCK)
            if fd >= 0 { close(fd) }
            XCTFail("Lamp waited on a pipe left at the build's Info.plist")
        }
    }
}
