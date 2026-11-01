import XCTest
@testable import Lamp

/// What the setup screens say when the network fails: one plain sentence for a connection that didn't work, and
/// nothing borrowed from it for an error that isn't one.
@MainActor
final class NetworkErrorWordsTests: XCTestCase {
    private let connection = "Lamp couldn't connect. Check your internet connection and try again."

    func testAConnectionThatDidNotWorkIsSaidPlainly() {
        XCTAssertEqual(EngineDownloads.message(URLError(.cannotConnectToHost)), connection)
    }

    /// A real refused connection, through the download itself, which is where the error's type could be lost.
    func testARefusedDownloadIsSaidPlainly() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-refused-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        do {
            try await Download.file(from: URL(string: "http://127.0.0.1:1/file")!, to: folder.appendingPathComponent("file"),
                                    expected: nil) { _ in }
            XCTFail("Nothing listens there")
        } catch {
            XCTAssertEqual(EngineDownloads.message(error), connection)
        }
    }

    func testEveryKindOfConnectivityError() {
        let codes: [URLError.Code] = [.notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotFindHost,
                                      .cannotConnectToHost, .dnsLookupFailed, .internationalRoamingOff, .dataNotAllowed]
        for code in codes { XCTAssertEqual(ErrorMessages.reason(URLError(code)), connection, "\(code)") }
    }

    func testOtherNetworkErrorsKeepTheirOwnWords() {
        let codes: [URLError.Code] = [.serverCertificateUntrusted, .serverCertificateHasBadDate, .clientCertificateRequired,
                                      .secureConnectionFailed, .userAuthenticationRequired, .badURL, .unsupportedURL,
                                      .cannotDecodeRawData, .cannotDecodeContentData, .cannotParseResponse, .badServerResponse,
                                      .fileDoesNotExist, .cannotCreateFile, .cannotWriteToFile]
        for code in codes {
            let error = URLError(code)
            XCTAssertEqual(ErrorMessages.reason(error), error.localizedDescription, "\(code)")
        }
    }

    /// The domain decides: another domain's error can carry the same number.
    func testTheSameCodeInAnotherDomainIsNotAConnection() {
        let error = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorCannotConnectToHost)
        XCTAssertEqual(ErrorMessages.reason(error), error.localizedDescription)
        let stopped = NSError(domain: NSCocoaErrorDomain, code: NSURLErrorCancelled)
        XCTAssertEqual(ErrorMessages.reason(stopped), stopped.localizedDescription)
    }

    func testACancelledRequestHasNothingToSay() {
        XCTAssertNil(ErrorMessages.reason(CancellationError()))
        XCTAssertNil(ErrorMessages.reason(URLError(.cancelled)))
        XCTAssertEqual(EngineDownloads.message(CancellationError()), "The download was stopped.")
    }

    func testLampsOwnMessagesStand() {
        let checksum = "The download didn't match what Anthropic published, so Lamp didn't use it."
        XCTAssertEqual(EngineDownloads.message(EngineInstall.Failure(message: checksum)), checksum)
        let status = "The download site answered 503."
        XCTAssertEqual(EngineDownloads.message(EngineInstall.Failure(message: status)), status)
        let file = CocoaError(.fileWriteOutOfSpace)
        XCTAssertEqual(EngineDownloads.message(file), file.localizedDescription)
    }
}
