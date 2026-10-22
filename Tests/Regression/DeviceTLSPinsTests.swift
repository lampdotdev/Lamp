import XCTest
@testable import Lamp

/// Certificate checks must survive a new request, a corrupt store and a failed write. Each test keeps
/// its store in a temporary folder, never among the person's devices.
final class DeviceTLSPinsTests: XCTestCase {
    private var folder: URL!
    private var file: URL { folder.appendingPathComponent("certificates.json") }

    override func setUpWithError() throws {
        let temporary = ProcessInfo.processInfo.environment["TMPDIR"].map { URL(fileURLWithPath: $0, isDirectory: true) }
            ?? FileManager.default.temporaryDirectory
        folder = temporary.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        if let folder, FileManager.default.fileExists(atPath: folder.path) {
            try FileManager.default.removeItem(at: folder)
        }
    }

    func testNewRequestsKeepEachPortsCertificateAndRefuseChanges() throws {
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
        let pins = DeviceTLS.Pins(file: file)
        XCTAssertNil(pins.admit("first", port: 443))
        XCTAssertEqual(DeviceTLS.Pins(file: file).kept(port: 443), "first")
        XCTAssertNil(DeviceTLS.Pins(file: file).admit("other", port: 11443))
        XCTAssertEqual(DeviceTLS.Pins(file: file).kept(port: 443), "first", "saving another port must keep the first")
        XCTAssertEqual(DeviceTLS.Pins(file: file).kept(port: 11443), "other")
        XCTAssertNil(DeviceTLS.Pins(file: file).admit("first", port: 443))
        XCTAssertNil(DeviceTLS.Pins(file: file).admit("other", port: 11443))
        let saved = try Data(contentsOf: file)
        XCTAssertEqual(pins.admit("replacement", port: 443), .changed)
        XCTAssertEqual(try Data(contentsOf: file), saved, "a refused certificate must leave the store intact")
    }

    func testAnUnreadableStoreIsRefusedAndLeftIntact() throws {
        for text in ["not json", #"{"443":42}"#, "[]"] {
            let saved = Data(text.utf8)
            try saved.write(to: file)
            XCTAssertEqual(DeviceTLS.Pins(file: file).admit("first", port: 443), .unsaved)
            XCTAssertEqual(try Data(contentsOf: file), saved)
        }
        // A directory in the file's place exists but can't be read as a pin store.
        try FileManager.default.removeItem(at: file)
        try FileManager.default.createDirectory(at: file, withIntermediateDirectories: false)
        XCTAssertEqual(DeviceTLS.Pins(file: file).admit("first", port: 443), .unsaved)
    }

    func testAnUnsavedCertificateIsNotTrustedOnTheNextRequest() throws {
        let parent = folder.appendingPathComponent("missing")
        let store = parent.appendingPathComponent("certificates.json")
        let pins = DeviceTLS.Pins(file: store)
        XCTAssertEqual(pins.admit("unsaved", port: 443), .unsaved)
        XCTAssertNil(pins.kept(port: 443))
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false)
        try Data(#"{"443":"saved"}"#.utf8).write(to: store)
        XCTAssertNil(pins.admit("saved", port: 443))
        XCTAssertEqual(DeviceTLS.Pins(file: store).admit("unsaved", port: 443), .changed)
        XCTAssertEqual(pins.kept(port: 443), "saved")
    }

}
