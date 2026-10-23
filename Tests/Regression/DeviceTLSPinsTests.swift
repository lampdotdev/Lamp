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

    /// A device that makes itself a new certificate from a root of its own (Xbox's Device Portal, at each start) is
    /// still itself once its root is kept: a new certificate that root signed is taken and kept, one any other root
    /// signed is refused, and a root that didn't sign the kept certificate is never kept.
    func testACertificateTheKeptRootSignedIsTakenAndNoOtherIs() throws {
        // Made with openssl for this test: two roots, leaves a and b from the first, c from the second.
        let root = Data(base64Encoded: "MIIBcTCCARigAwIBAgIUEwketKpctt2XBjuqsXXNOFCG7wMwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLRGV2aWNlIFJvb3QwIBcNMjYxMDIzMDMwNDM1WhgPMjEyNjA5MjkwMzA0MzVaMBYxFDASBgNVBAMMC0RldmljZSBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE0/UGgDWhR/x+V0imWGqanYvwx9vqzo7ofoNkZb/MKEslYAQufLFwR+RFZk7DQxP26NcgfET+6TzhXGiZ330FfKNCMEAwHQYDVR0OBBYEFF18d5RNfuk+Ny5rkK+N3Mp0DKO6MA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgIEMAoGCCqGSM49BAMCA0cAMEQCIC1slI4XxTbWXgYbG/w9dsmJ6uiWxC6INzD4K9KEIqIAAiBZw8GB7EQUtMwbILzkv9MzBsiGoTwVrS7CWZeWW8IFiQ==")!
        let otherRoot = Data(base64Encoded: "MIIBcTCCARigAwIBAgIUUqE4ep0icJw97FGbsXXgKfhbnKswCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLRGV2aWNlIFJvb3QwIBcNMjYxMDIzMDMwNDM1WhgPMjEyNjA5MjkwMzA0MzVaMBYxFDASBgNVBAMMC0RldmljZSBSb290MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEo+brvwT1TRYap/VSPOQjW2+pked/eL3xZSIaYabUucFYxmTSeFyz+gw2nb67BslgauaqAz6XdiESud+RDVSxw6NCMEAwHQYDVR0OBBYEFOBiR/gAI5ANYAL8eeUcL0iXhxTdMA8GA1UdEwEB/wQFMAMBAf8wDgYDVR0PAQH/BAQDAgIEMAoGCCqGSM49BAMCA0cAMEQCICFnFRGYIqzhPvC0gHdcFlIu/vVatSgUxUaaUShoSjXfAiB5kyCdEzXMH4KIp/GafrpP/oDgrGYk1E5q0Q802HdNyA==")!
        let a = Data(base64Encoded: "MIIBXTCCAQOgAwIBAgICckgwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLRGV2aWNlIFJvb3QwIBcNMjYxMDIzMDMwNDM1WhgPMjEyNjA5MjkwMzA0MzVaMBMxETAPBgNVBAMMCDEwLjAuMC4yMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEpn4MMmlAZ6Dy98H8fzY0aK3A/hP8IXWpF60bEgSP6esdAzdkcpVN26+64VZD2XceQ01sZvCsldxUN+OObZ5GBaNCMEAwHQYDVR0OBBYEFNzRmBm7JtOg3Wkw/g/CNtWIxxqOMB8GA1UdIwQYMBaAFF18d5RNfuk+Ny5rkK+N3Mp0DKO6MAoGCCqGSM49BAMCA0gAMEUCIQDHpqhYlXlyhm+atY2gcpoca2aSPtrfqY+f1PA6KnvSPAIgcPiYVFv05xrrqX0ew5Tj3IPFq4UNXUYpCyRNgYEhgjc=")!
        let b = Data(base64Encoded: "MIIBXjCCAQOgAwIBAgICeBUwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLRGV2aWNlIFJvb3QwIBcNMjYxMDIzMDMwNDM2WhgPMjEyNjA5MjkwMzA0MzZaMBMxETAPBgNVBAMMCDEwLjAuMC4yMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEIyL6k8WL6je1NEZtjJhluFJDuowKI6UYDCSwTe6CHvBrMFSsu5JmP7YtQVEsoODBmgkpPWaCUEZ+5TvsLfu8SaNCMEAwHQYDVR0OBBYEFNtZwIohSexiutgLGOCO8Eg51pd+MB8GA1UdIwQYMBaAFF18d5RNfuk+Ny5rkK+N3Mp0DKO6MAoGCCqGSM49BAMCA0kAMEYCIQDISP9zmaXW5fJQ4QfkMcnHiX9HsFmuhSy1rLlP9e4vzwIhALK0ATUNrwLF780o52BPDCOVLguoPv8h7/1eRknSpTIQ")!
        let c = Data(base64Encoded: "MIIBXDCCAQOgAwIBAgICOMgwCgYIKoZIzj0EAwIwFjEUMBIGA1UEAwwLRGV2aWNlIFJvb3QwIBcNMjYxMDIzMDMwNDM2WhgPMjEyNjA5MjkwMzA0MzZaMBMxETAPBgNVBAMMCDEwLjAuMC4yMFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAEWr/A+oIfQvRaV4rdcWYrEMhvSfdHCRFPuZ9JXc4x5tSYicmBnu+FJ2z1fKVl1cC2ITibJsvd2M7p+59X1PQ88qNCMEAwHQYDVR0OBBYEFIoWSEYh/TQagoT+lQIQjgl0sDEoMB8GA1UdIwQYMBaAFOBiR/gAI5ANYAL8eeUcL0iXhxTdMAoGCCqGSM49BAMCA0cAMEQCIGWAegOjDV8yHXi8ufvmtA3qZMxui4XOAabPdnuzhoREAiBJP8JvLUUSuPlc8rRmCVr4rSMjDnjKdYP+xodC44KPIw==")!
        let pins = DeviceTLS.Pins(file: file)
        XCTAssertNil(pins.admit(DeviceTLS.fingerprint(a), port: 11443, certificate: a))
        XCTAssertEqual(pins.admit(DeviceTLS.fingerprint(b), port: 11443, certificate: b), .changed, "no root kept yet")
        XCTAssertFalse(pins.keepRoot(otherRoot, signing: a, port: 11443), "a root that didn't sign the kept certificate")
        XCTAssertFalse(pins.keepRoot(root, signing: b, port: 11443), "only for the certificate that's kept")
        XCTAssertTrue(pins.keepRoot(root, signing: a, port: 11443))
        XCTAssertNil(pins.admit(DeviceTLS.fingerprint(b), port: 11443, certificate: b))
        XCTAssertEqual(pins.kept(port: 11443), DeviceTLS.fingerprint(b))
        XCTAssertEqual(pins.admit(DeviceTLS.fingerprint(c), port: 11443, certificate: c), .changed)
        XCTAssertEqual(pins.admit(DeviceTLS.fingerprint(c), port: 11443), .changed, "nothing to check it against")
        XCTAssertEqual(pins.kept(port: 11443), DeviceTLS.fingerprint(b))
    }
}
