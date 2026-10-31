import XCTest
@testable import Lamp

/// What a TV app saved in its preview is removed when the app is deleted, even when nothing of WebKit has started yet in
/// Lamp (opened again, and the preview not opened since): WebKit's calls about stores that aren't open crashed a process
/// in that state. `PreviewStores` is built into a program of its own, so it runs in such a process.
final class PreviewStoresTests: XCTestCase {
    private static let harness = """
        import AppKit
        import WebKit
        @MainActor func make(_ id: UUID) {
            // A page saves something in a store of its own, as the TV preview's page does.
            _ = NSApplication.shared
            let configuration = WKWebViewConfiguration()
            configuration.websiteDataStore = WKWebsiteDataStore(forIdentifier: id)
            let view = WKWebView(frame: .zero, configuration: configuration)
            view.loadHTMLString("<script>localStorage.setItem('n', '1')</script>", baseURL: URL(string: "https://lamp.test/"))
            let end = Date().addingTimeInterval(3)
            while Date() < end { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
        }
        @main struct Harness {
            @MainActor static func main() async {
                setvbuf(stdout, nil, _IONBF, 0)
                let env = ProcessInfo.processInfo.environment
                let id = UUID(uuidString: env["LAMP_STORE"]!)!
                if env["LAMP_DO"] == "make" {
                    make(id)
                } else {
                    // Nothing of WebKit has started in this process.
                    print("removed \\(await PreviewStores.remove(id, tries: 40))")
                }
                let ids: [UUID] = await withCheckedContinuation { done in WKWebsiteDataStore.fetchAllDataStoreIdentifiers { done.resume(returning: $0) } }
                print("there \\(ids.contains(id))")
            }
        }
        """

    func testAStoreIsRemovedInAProcessWhereWebKitHasntStarted() throws {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-preview-stores-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: work, withIntermediateDirectories: true)
        let bundle = "dev.lamp.test.previewstores.\(UUID().uuidString.prefix(8).lowercased())"
        let folder = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/WebKit/\(bundle)")
        defer { try? FileManager.default.removeItem(at: work); try? FileManager.default.removeItem(at: folder) }
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../Sources/Lamp/PreviewStores.swift")
        try FileManager.default.copyItem(at: source, to: work.appendingPathComponent("PreviewStores.swift"))
        try Self.harness.write(to: work.appendingPathComponent("main.swift"), atomically: true, encoding: .utf8)
        try "<?xml version=\"1.0\" encoding=\"UTF-8\"?><plist version=\"1.0\"><dict><key>CFBundleIdentifier</key><string>\(bundle)</string></dict></plist>"
            .write(to: work.appendingPathComponent("info.plist"), atomically: true, encoding: .utf8)
        let built = TestShell.run(Shell.compatibleSDK + "xcrun swiftc -parse-as-library -o stores main.swift PreviewStores.swift -Xlinker -sectcreate -Xlinker __TEXT -Xlinker __info_plist -Xlinker info.plist 2>&1", in: work)
        XCTAssertEqual(built.status, 0, built.output)
        let id = UUID().uuidString
        let made = TestShell.run("LAMP_STORE=\(id) LAMP_DO=make ./stores 2>&1", in: work)
        XCTAssertTrue(made.output.contains("there true"), "the page saved something: \(made.output)")
        let removed = TestShell.run("LAMP_STORE=\(id) LAMP_DO=remove ./stores 2>&1", in: work)
        XCTAssertEqual(removed.status, 0, "it didn't crash: \(removed.output)")
        XCTAssertTrue(removed.output.contains("removed true") && removed.output.contains("there false"), removed.output)
        let left = (try? FileManager.default.contentsOfDirectory(atPath: folder.appendingPathComponent("WebsiteDataStore").path)) ?? []
        XCTAssertFalse(left.contains(id.lowercased()), "its folder is gone: \(left)")
    }
}
