import Foundation

enum BugReportDelivery {
    static let maxBytes = 16_384

    enum State: Equatable {
        case ready, sending, sent, failed(String)
        var isSending: Bool { self == .sending }
        var message: String {
            switch self {
            case .ready: "Only the text above will be sent."
            case .sending: "Sending report…"
            case .sent: "Report sent. Thank you for helping improve Lamp."
            case .failed(let message): message
            }
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    // A redirect must not hand the person's report to another destination, including a sign-in page.
    private final class NoRedirects: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
        func urlSession(_ session: URLSession, task: URLSessionTask,
                        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
                        completionHandler: @escaping (URLRequest?) -> Void) { completionHandler(nil) }
    }
    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.httpShouldSetCookies = false
        config.urlCache = nil
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 20
        return URLSession(configuration: config, delegate: NoRedirects(), delegateQueue: nil)
    }()

    static func send(_ report: String, to endpoint: URL = Edition.bugReportEndpoint,
                     using client: URLSession = session) async throws {
        guard !report.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              report.utf8.count <= maxBytes else {
            throw Failure(message: "The report is empty or too long to send. Shorten it, or use Copy Report or Share….")
        }
        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(report.utf8)
        let data: Data
        let response: URLResponse
        do { (data, response) = try await client.data(for: request) }
        catch {
            let offline = (error as? URLError)?.code == .notConnectedToInternet
            throw Failure(message: offline
                          ? "You're offline. Your report is still here. Use Copy Report or Share… when you're ready."
                          : "Couldn't confirm delivery. Your report is still here. Try Copy Report or Share… before sending again.")
        }
        guard let http = response as? HTTPURLResponse else { throw Failure(message: "Couldn't confirm delivery. Use Copy Report or Share….") }
        if http.statusCode == 200,
           let body = try? JSONSerialization.jsonObject(with: data) as? [String: Any], body["sent"] as? Bool == true { return }
        let message: String
        switch http.statusCode {
        case 413: message = "The report is too long to send. Shorten it, or use Copy Report or Share…."
        case 429: message = "Too many reports have been sent recently. Try later, or use Copy Report or Share…."
        case 503: message = "Sending reports is unavailable right now. Your report is still here. Use Copy Report or Share…."
        default: message = "Couldn't confirm delivery. Your report is still here. Use Copy Report or Share…."
        }
        throw Failure(message: message)
    }
}
