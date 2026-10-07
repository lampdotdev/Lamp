import Foundation

private final class ReportProtocol: URLProtocol {
    static var status = 200
    static var responseBody = Data(#"{"sent":true}"#.utf8)
    static var failure: URLError?
    static var received = Data()
    static var requests = 0

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.requests += 1
        precondition(request.httpMethod == "POST")
        precondition(request.value(forHTTPHeaderField: "Content-Type") == "text/plain; charset=utf-8")
        precondition(request.value(forHTTPHeaderField: "Authorization") == nil)
        if let body = request.httpBody { Self.received = body }
        else if let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            Self.received = Data()
            var bytes = [UInt8](repeating: 0, count: 1024)
            while stream.hasBytesAvailable {
                let size = stream.read(&bytes, maxLength: bytes.count)
                if size <= 0 { break }
                Self.received.append(contentsOf: bytes.prefix(size))
            }
        }
        if let failure = Self.failure { client?.urlProtocol(self, didFailWithError: failure); return }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() { }
}

@main
struct BugReportDeliveryTests {
    static func main() async throws {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReportProtocol.self]
        let session = URLSession(configuration: config)
        defer { session.invalidateAndCancel() }
        let endpoint = URL(string: "https://example.invalid/api/bug-report")!
        let report = "  The exact edited report → café 🪔\nI choose to add this detail.\n"
        try await BugReportDelivery.send(report, to: endpoint, using: session)
        precondition(ReportProtocol.received == Data(report.utf8), "Sender changed the reviewed text")
        for (status, expected) in [(413, "too long"), (429, "Too many"), (503, "unavailable"), (502, "Couldn't confirm"), (308, "Couldn't confirm")] {
            ReportProtocol.status = status
            do { try await BugReportDelivery.send(report, to: endpoint, using: session); preconditionFailure("Accepted HTTP \(status)") }
            catch { precondition(error.localizedDescription.contains(expected)) }
        }
        ReportProtocol.status = 200
        ReportProtocol.responseBody = Data("<html>sign in</html>".utf8)
        do { try await BugReportDelivery.send(report, to: endpoint, using: session); preconditionFailure("Accepted unacknowledged delivery") }
        catch { precondition(error.localizedDescription.contains("Couldn't confirm")) }
        ReportProtocol.failure = URLError(.notConnectedToInternet)
        do { try await BugReportDelivery.send(report, to: endpoint, using: session); preconditionFailure("Accepted offline delivery") }
        catch { precondition(error.localizedDescription.contains("You're offline")) }
        let before = ReportProtocol.requests
        for invalid in [" \n", String(repeating: "🪔", count: 5000)] {
            do { try await BugReportDelivery.send(invalid, to: endpoint, using: session); preconditionFailure("Accepted invalid report") }
            catch { precondition(error.localizedDescription.contains("empty or too long")) }
        }
        precondition(ReportProtocol.requests == before, "Invalid text reached the network")
        print("PASS: exact UTF-8 body, no credential header, acknowledged success, server failures, offline, rejected redirects and invalid/oversize reports")
    }
}
