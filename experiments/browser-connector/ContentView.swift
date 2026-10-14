import SwiftUI

struct PageCapture: Codable {
    let title: String
    let url: String
    let text: String
    let capturedAt: String
    let app: String
}
@MainActor
final class ShelfCompanion: ObservableObject {
    static let shared = ShelfCompanion()
    @Published var clicks = 0
    init() {
        Task {
            await LampBrowser.serve(surface: {
                .init(title: "@@NAME@@", detail: "Clicks: \(self.clicks)", actions: [.init(id: "count", label: "Count click")])
            }, handle: { event in if event.action == "count" { self.clicks += 1 } })
        }
    }
}
struct ContentView: View {
    @State private var capture: PageCapture? = LampStore.load(PageCapture.self, from: "browser-page")
    @State private var message = "Ask once, then read without opening the extension."
    @State private var waiting = false
    @State private var automatic = false
    @State private var reads = 0
    @StateObject private var companion = ShelfCompanion.shared
    @State private var site = "http://127.0.0.1:8765"
    @State private var grants: [[String: Any]] = []
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Image(systemName: "books.vertical.fill").font(.largeTitle).foregroundStyle(.orange)
                Text("@@NAME@@").font(.largeTitle.bold())
                Spacer()
                Text("Reads: \(reads)").monospacedDigit()
                Text("Companion clicks: \(companion.clicks)").monospacedDigit()
            }
            Picker("Site", selection: $site) {
                Text("Harbor Supply").tag("http://127.0.0.1:8765")
                Text("Other site").tag("http://localhost:8765")
            }.pickerStyle(.segmented).disabled(waiting)
            HStack {
                Button("Ask for site access") { Task { await request("approve") } }.disabled(waiting)
                Button("Read page") { Task { await request("read") } }.disabled(waiting)
                Toggle("Read every 5 seconds", isOn: $automatic).toggleStyle(.checkbox)
            }
            Text(grants.contains { $0["origin"] as? String == site } ? "Standing access approved for this app and site" : "No standing access for this app and site")
                .foregroundStyle(.secondary)
            Text(message).foregroundStyle(.secondary)
            Divider()
            if let capture {
                Text(capture.title).font(.title2.bold())
                Text(capture.url).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Saved at \(capture.capturedAt)").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(capture.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            } else {
                ContentUnavailableView("No page yet", systemImage: "doc.text", description: Text("Approve this app and site in Lamp Page Connector."))
            }
            Spacer(minLength: 0)
        }.padding(24).frame(minWidth: 680, minHeight: 600)
        .task {
            var tick = 0
            while !Task.isCancelled {
                if let state = try? await call("status", [:]) { grants = state["grants"] as? [[String: Any]] ?? [] }
                tick += 1
                if automatic && !waiting && tick % 5 == 0 { await request("read") }
                try? await Task.sleep(for: .seconds(1))
            }
        }
    }
    func call(_ route: String, _ body: [String: Any]) async throws -> [String: Any] {
        var req = URLRequest(url: URL(string: "http://127.0.0.1:@@PORT@@/prototype/browser/" + route)!)
        req.httpMethod = "POST"
        req.setValue("Bearer @@TOKEN@@", forHTTPHeaderField: "Authorization")
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = try JSONSerialization.data(withJSONObject: body)
        req.timeoutInterval = 5
        let (data, _) = try await URLSession.shared.data(for: req)
        let value = try JSONSerialization.jsonObject(with: data) as! [String: Any]
        if let error = value["error"] as? String { throw NSError(domain: "Browser", code: 1, userInfo: [NSLocalizedDescriptionKey: error]) }
        return value
    }
    @MainActor func request(_ mode: String) async {
        waiting = true
        defer { waiting = false }
        do {
            let response = try await call("request", ["url": site + "/orders", "mode": mode])
            let requestID = response["id"] as! String
            message = mode == "approve" ? "Open Lamp Page Connector in Chrome to approve this app and site." : "Reading through Chrome…"
            for _ in 0..<125 {
                try await Task.sleep(for: .seconds(1))
                let reply = try await call("result", ["id": requestID])
                if let result = reply["result"] as? [String: Any] {
                    if let error = result["error"] as? String { message = error; return }
                    if result["approved"] as? Bool == true { message = "Approved. Read again whenever you need."; return }
                    let page = try JSONDecoder().decode(PageCapture.self, from: JSONSerialization.data(withJSONObject: result))
                    capture = page
                    LampStore.save(page, to: "browser-page")
                    reads += 1
                    message = "Read completed without an extension click."
                    return
                }
            }
        } catch { message = error.localizedDescription }
    }
}
