import XCTest
@testable import Lamp

/// Lamp compares the signature of the copy it replaces with the new one's, to clear the permissions macOS
/// kept for the old signature. An ad hoc signature has to count as one too, or an app going from ad hoc to
/// Lamp's certificate keeps entries in System Settings that no longer apply to it.
final class SignatureSwitchTests: XCTestCase {
    private var root: URL?
    override func tearDown() { if let root { try? FileManager.default.removeItem(at: root) } }

    /// A minimal app signed ad hoc, as Lamp leaves one when it can't use its certificate.
    private func adHocApp() throws -> URL {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-signature-test-\(UUID().uuidString)")
        self.root = root
        let app = root.appendingPathComponent("Probe.app")
        let macOS = app.appendingPathComponent("Contents/MacOS")
        try fm.createDirectory(at: macOS, withIntermediateDirectories: true)
        try fm.copyItem(atPath: "/usr/bin/true", toPath: macOS.appendingPathComponent("Probe").path)
        let info: [String: Any] = ["CFBundleIdentifier": "dev.lamp.test.probe", "CFBundleExecutable": "Probe",
                                   "CFBundlePackageType": "APPL"]
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
            .write(to: app.appendingPathComponent("Contents/Info.plist"))
        let signed = Subprocess.runBlocking("/usr/bin/codesign", ["--force", "-s", "-", app.path], timeout: 60)
        XCTAssertEqual(signed.status, 0, signed.output)
        return app
    }

    func testAnAdHocSignatureIsASignatureToCompare() async throws {
        let app = try adHocApp()
        let read = await AppSigning.requirement(of: app)
        let requirement = try XCTUnwrap(read, "an ad hoc app's signature wasn't read")
        XCTAssertTrue(requirement.contains("cdhash"), requirement)
        XCTAssertFalse(AppSigning.isCertificateSigned(app))
    }

    func testNoAppIsNoSignature() async {
        let missing = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-no-such-\(UUID().uuidString).app")
        let requirement = await AppSigning.requirement(of: missing)
        XCTAssertNil(requirement)
    }

    /// codesign marks the requirement it worked out for an ad hoc signature with "# "; a certificate's has none.
    func testBothSpellingsAreRead() {
        XCTAssertEqual(AppSigning.requirement(in: ["Executable=/x", "# designated => cdhash H\"ab12\""]), "designated => cdhash H\"ab12\"")
        XCTAssertEqual(AppSigning.requirement(in: ["designated => identifier \"a.b\" and certificate leaf = H\"cd34\""]),
                       "designated => identifier \"a.b\" and certificate leaf = H\"cd34\"")
        XCTAssertNil(AppSigning.requirement(in: ["/x: code object is not signed at all"]))
    }
}
