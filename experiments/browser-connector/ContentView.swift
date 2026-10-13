import SwiftUI

struct PageCapture: Codable {
    let title: String
    let url: String
    let text: String
    let capturedAt: String
    let app: String
}
struct ContentView: View {
    @State private var capture: PageCapture? = LampStore.load(PageCapture.self, from: "browser-page")
    @State private var message = "Choose a page in your browser to add it here."
    @State private var waiting = false
    @State private var requestID = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Image(systemName: "books.vertical.fill").font(.largeTitle).foregroundStyle(.orange)
                VStack(alignment: .leading) {
                    Text("@@NAME@@").font(.largeTitle.bold())
                    Text("Your saved browser page").foregroundStyle(.secondary)
                }
                Spacer()
                Button("Get current page") { Task { await getPage() } }.disabled(waiting)
            }
            Text(message).foregroundStyle(.secondary)
            Divider()
            if let capture {
                Text(capture.title).font(.title2.bold())
                Text(capture.url).font(.callout).foregroundStyle(.secondary).textSelection(.enabled)
                Text("Saved at \(capture.capturedAt)").font(.caption).foregroundStyle(.secondary)
                ScrollView { Text(capture.text).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
            } else {
                ContentUnavailableView("No page yet", systemImage: "doc.text", description: Text("Ask for a page, then click Lamp Page Connector in Chrome."))
            }
            Spacer(minLength: 0)
        }.padding(28).frame(minWidth: 680, minHeight: 540)
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
    @MainActor func getPage() async {
        waiting = true
        defer { waiting = false }
        do {
            let response = try await call("request", ["origin": "http://127.0.0.1:8765"])
            requestID = response["id"] as! String
            message = "In Chrome, open your page and click Lamp Page Connector."
            for _ in 0..<125 {
                try await Task.sleep(for: .seconds(1))
                let reply = try await call("result", ["id": requestID])
                if let result = reply["result"] as? [String: Any] {
                    if let error = result["error"] as? String { message = error; return }
                    let page = try JSONDecoder().decode(PageCapture.self, from: JSONSerialization.data(withJSONObject: result))
                    capture = page
                    LampStore.save(page, to: "browser-page")
                    message = "Page received. Saved only in @@NAME@@ on this Mac."
                    return
                }
            }
        } catch { message = error.localizedDescription }
    }
}
