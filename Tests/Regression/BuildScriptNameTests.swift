import XCTest
@testable import Lamp

/// A shared app's name comes from the file, and goes into the Info.plist build.sh writes. Whatever it holds is only
/// text there: the shell runs none of it, and the app is called exactly that.
final class BuildScriptNameTests: XCTestCase {
    private var root: URL?

    override func tearDown() {
        if let root { try? FileManager.default.removeItem(at: root) }
    }

    /// Names with a command in them, in each way the shell would run one (a substitution, backquotes, a line that
    /// ends the heredoc and starts another), written into the Mac and iPhone build scripts: the part that writes
    /// Info.plist runs, makes no file, and names the app as it is named.
    func testANameIsNeverRunByTheBuildScript() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-build-name-\(UUID().uuidString)")
        self.root = root
        let names = ["Pwn $(touch ran-dollar) `touch ran-backtick` ${HOME} it's \\",
                     "Pwn\nPLIST\ntouch ran-heredoc\ncat >/dev/null <<PLIST"]
        for (n, name) in names.enumerated() {
            for platform in [Platform.mac, .iphone] {
                let dir = root.appendingPathComponent("\(platform.rawValue)-\(n)")
                try fm.createDirectory(at: dir.appendingPathComponent("Sources"), withIntermediateDirectories: true)
                let project = LampProject(id: "pwn", name: name, exe: "Pwn", dir: dir, platform: platform)
                try Template.writeOwnedFiles(for: project)
                let script = try String(contentsOf: dir.appendingPathComponent("build.sh"), encoding: .utf8)

                let (plist, status) = try runInfoPlistPart(of: script, in: dir)
                let place = "\(platform.rawValue), name \(n)"
                for marker in ["ran-dollar", "ran-backtick", "ran-heredoc"] {
                    XCTAssertFalse(fm.fileExists(atPath: dir.appendingPathComponent(marker).path), "\(place): the name ran \(marker)")
                }
                XCTAssertEqual(status, 0, "\(place): the script stopped")
                // A name with `<` isn't XML, which no name Lamp keeps has (`Template.draft`): only the shell is checked.
                guard !name.contains("<") else { continue }
                let info = try XCTUnwrap(PropertyListSerialization.propertyList(from: Data(contentsOf: plist), format: nil) as? [String: Any],
                                         "\(place): Info.plist didn't parse")
                XCTAssertEqual(info["CFBundleName"] as? String, name, place)
                XCTAssertEqual(info["CFBundleDisplayName"] as? String, name, place)
                XCTAssertEqual(info["NSCameraUsageDescription"] as? String, name + " uses your camera.", place)
            }
        }
    }

    /// Runs what build.sh does before its build (its first lines, up to `set`) and then its Info.plist, as it's written,
    /// in the app's folder: without compiling anything. Returns the Info.plist written, and how the shell exited.
    private func runInfoPlistPart(of script: String, in dir: URL) throws -> (URL, Int32) {
        let lines = script.components(separatedBy: "\n")
        let set = try XCTUnwrap(lines.firstIndex { $0.hasPrefix("set -euo pipefail") })
        let start = try XCTUnwrap(lines.firstIndex { $0.contains("Info.plist\" <<PLIST") })
        let end = try XCTUnwrap(lines[start...].firstIndex { $0.hasPrefix("intents ") })
        let plist = dir.appendingPathComponent("out/Info.plist")
        let part = lines[..<set].joined(separator: "\n") + "\n"
            + "APP=out; mkdir -p out\n"
            + lines[start..<end].joined(separator: "\n").replacingOccurrences(of: "$APP/Contents/Info.plist", with: "$APP/Info.plist") + "\n"
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/zsh")
        process.arguments = ["-c", part]
        process.currentDirectoryURL = dir
        try process.run()
        process.waitUntilExit()
        return (plist, process.terminationStatus)
    }
}
