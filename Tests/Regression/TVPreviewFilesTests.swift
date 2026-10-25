import WebKit
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

    /// What a TV app of a wish saves (the values the wish's apps share among it) is there when its preview is opened
    /// again: a part's instance isn't a UUID, and it gets a store of its own all the same, apart from its wish's other
    /// apps'.
    func testATVAppOfAWishKeepsWhatItSavedWhenOpenedAgain() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        for folder in [dir, staged] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try """
            <html><body><script>
            var n = +(localStorage.getItem('n') || 0);
            console.log('opened ' + n);
            localStorage.setItem('n', String(n + 1));
            </script></body></html>
            """.write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        let wish = UUID().uuidString
        var whole = LampProject(id: "tv-preview-kept", name: "Tally", exe: "Tally", dir: root)
        whole.instance = wish
        var project = LampProject(id: "tv-preview-kept.tv", name: "Tally", exe: "Tally", dir: dir, platform: .tv, partOf: "tv-preview-kept")
        project.instance = Parts.instance(wish: whole, folder: "TV")
        let store = try XCTUnwrap(TVPreview.store(for: project.instance), "a part's page keeps what it saves")
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: store) } }
        XCTAssertEqual(TVPreview.store(for: project.instance), store, "the same store at every opening")
        XCTAssertNotEqual(TVPreview.store(for: wish + ".Mac"), store, "apart from the wish's other apps'")
        XCTAssertEqual(TVPreview.store(for: wish), UUID(uuidString: wish), "an app's own instance keeps its store")

        func opened() async throws -> [String] {
            for _ in 0..<50 {
                let lines = ((try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? "").split(separator: "\n").filter { $0.contains("opened ") }
                if !lines.isEmpty { return lines.map(String.init) }
                try await Task.sleep(for: .milliseconds(100))
            }
            return []
        }
        let shown = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(shown)
        let first = try await opened()
        TVPreview.close(project)
        try? FileManager.default.removeItem(at: Runtime.logURL(project))
        let again = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(again)
        defer { TVPreview.close(project) }
        let second = try await opened()
        XCTAssertEqual(first.last.map { String($0.suffix(8)) }, "opened 0")
        XCTAssertEqual(second.last.map { String($0.suffix(8)) }, "opened 1", "what it saved was there: \(second)")
    }

    /// What a TV app of a wish saved in its preview goes when the app is deleted, with its wish or on its own: a part's
    /// store is named after its instance, so it would otherwise stay for good.
    func testWhatATVAppOfAWishSavedGoesWithIt() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("tv-preview-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let dir = root.appendingPathComponent("app"), staged = root.appendingPathComponent("web")
        for folder in [dir, staged] { try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true) }
        try "<html><body><script>localStorage.setItem('n', '1'); console.log('saved');</script></body></html>"
            .write(to: staged.appendingPathComponent("index.html"), atomically: true, encoding: .utf8)
        var whole = LampProject(id: "tv-preview-gone", name: "Tally", exe: "Tally", dir: root)
        whole.instance = UUID().uuidString
        var project = LampProject(id: "tv-preview-gone.tv", name: "Tally", exe: "Tally", dir: dir, platform: .tv, partOf: "tv-preview-gone")
        project.instance = Parts.instance(wish: whole, folder: "TV")
        let store = try XCTUnwrap(TVPreview.store(for: project.instance))
        defer { Task { try? await WKWebsiteDataStore.remove(forIdentifier: store) } }
        let shown = await TVPreview.show(project, staged: staged, inFront: false)
        XCTAssertNil(shown)
        for _ in 0..<50 where !(((try? String(contentsOf: Runtime.logURL(project), encoding: .utf8)) ?? "").contains("saved")) {
            try await Task.sleep(for: .milliseconds(100))
        }
        let kept = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertTrue(kept.contains(store), "the page saved something in its own store")
        await TVPreview.forget(project).value
        XCTAssertFalse(TVPreview.isOpen(project))
        let left = await WKWebsiteDataStore.allDataStoreIdentifiers
        XCTAssertFalse(left.contains(store), "its store is gone with it")
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
