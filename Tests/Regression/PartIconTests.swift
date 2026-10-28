import XCTest
@testable import Lamp

/// Every app of a wish has the wish's icon. The iPhone app made beside a TV app opened in the simulator with none: its
/// icon was drawn into the wish's folder, and the step that puts it into the iPhone app's bundle runs in that app's
/// sandbox, which opens only the app's own folder.
@MainActor
final class PartIconTests: XCTestCase {
    private var root: URL?

    override func tearDown() async throws {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    func testAWishsIPhoneAppReadsItsIconFromInsideItsSandbox() async throws {
        let fm = FileManager.default
        // Under the home folder, like a real wish, so the sandbox's home-folder rule is what's tested.
        let root = fm.homeDirectoryForCurrentUser.appendingPathComponent(".lamp-part-icon-test-\(UUID().uuidString)")
        self.root = root
        let wishDir = root.appendingPathComponent("Apps/remote")
        try fm.createDirectory(at: wishDir.appendingPathComponent("iPhone/.lamp"), withIntermediateDirectories: true)
        let wish = LampProject(id: "remote", name: "Remote", exe: "Remote", dir: wishDir, platform: .tv)
        let phone = LampProject(id: "remote.iphone", name: "Remote", exe: "Remote", dir: wishDir.appendingPathComponent("iPhone"),
                                platform: .iphone, partOf: "remote")
        let spec = IconSpec(subject: "a remote control", symbol: "appletvremote.gen4", background: "blue", tint: "#0A84FF")
        Icons.save(spec, for: wish)

        // The wish has one design, and each of its apps draws it as its own.
        XCTAssertEqual(Icons.load(phone), spec)
        _ = try await Icons.write(spec, art: nil, for: wish)
        _ = try await Icons.write(spec, art: nil, for: phone)

        // What `finishSimulatorBundle` does with it, confined as it is.
        var output: [String] = []
        let status = await Sandbox.run(#"sips -g pixelWidth "$LAMP_ICON""#, for: phone,
                                       env: ["LAMP_ICON": Icons.squareURL(phone).path]) { output.append($0) }
        XCTAssertEqual(status, 0, output.joined(separator: "\n"))
        XCTAssertTrue(output.contains { $0.contains("pixelWidth: 1024") }, output.joined(separator: "\n"))
        XCTAssertTrue(fm.fileExists(atPath: Icons.squareURL(wish).path))
    }
}
