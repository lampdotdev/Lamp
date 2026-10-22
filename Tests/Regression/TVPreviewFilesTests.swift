import XCTest
@testable import Lamp

/// A TV app reads its own files as bytes (a game's data, a program in WebAssembly) the way it does on a TV: with fetch and
/// XMLHttpRequest by their path beside index.html. WebKit refuses both to a page opened from a file.
@MainActor
final class TVPreviewFilesTests: XCTestCase {
    func testTheAppFetchesItsOwnBinaryFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: staged.appendingPathComponent("roms"), withIntermediateDirectories: true)
        var rom = Data(count: 3_000_000)
        rom.withUnsafeMutableBytes { for i in 0..<$0.count { $0[i] = UInt8(truncatingIfNeeded: i &* 31) } }
        try rom.write(to: staged.appendingPathComponent("roms/game.bin"))
        // The smallest module there is: the magic number and version 1.
        try Data([0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]).write(to: staged.appendingPathComponent("core.wasm"))
        try """
            <html><body><script>
            fetch('roms/game.bin').then(function (r) { return r.arrayBuffer(); })
              .then(function (b) { console.log('fetched ' + b.byteLength + ' ' + new Uint8Array(b)[1]); }, function (e) { console.log('fetch failed ' + e); });
            WebAssembly.instantiateStreaming(fetch('core.wasm'))
              .then(function () { console.log('wasm ok'); }, function (e) { console.log('wasm failed ' + e); });
            var x = new XMLHttpRequest(); x.open('GET', 'roms/game.bin'); x.responseType = 'arraybuffer';
            x.onload = function () { console.log('xhr ' + x.status + ' ' + x.response.byteLength); };
            x.onerror = function () { console.log('xhr failed'); }; x.send();
            fetch('missing.bin').then(function (r) { console.log('missing ' + r.status); }, function (e) { console.log('missing failed'); });
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let project = LampProject(id: "tv-preview-files", name: "Arcade", exe: "Arcade", dir: dir)
        defer { TVPreview.window(project)?.orderOut(nil) }
        let problem = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(problem)

        var log = ""
        for _ in 0..<50 {
            log = (try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? ""
            if ["fetched", "wasm", "xhr", "missing"].allSatisfy(log.contains) { break }
            try await Task.sleep(for: .milliseconds(100))
        }
        XCTAssertTrue(log.contains("fetched 3000000 31"), log)
        XCTAssertTrue(log.contains("wasm ok"), log)
        XCTAssertTrue(log.contains("xhr 200 3000000"), log)
        XCTAssertTrue(log.contains("missing 404"), log)
    }

    /// A page may ask for any range; one ending at the largest number there is still gets the file's bytes.
    func testARangeToTheLargestNumberStaysInTheFile() {
        XCTAssertEqual(StagedFiles.part("bytes=0-\(Int.max)", of: 10), 0..<10)
        XCTAssertEqual(StagedFiles.part("bytes=4-\(Int.max)", of: 10), 4..<10)
        XCTAssertEqual(StagedFiles.part("bytes=2-5", of: 10), 2..<6)
        XCTAssertEqual(StagedFiles.part("bytes=-\(Int.max)", of: 10), 0..<10)
        XCTAssertNil(StagedFiles.part("bytes=\(Int.max)-", of: 10))
    }
}
