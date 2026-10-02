import Foundation
import AppKit
import Network

/// A tiny HTTP server on 127.0.0.1 that lets generated apps use Forge's AI
/// without ever seeing the key. Apps call it through `ForgeAI` (see Template.forgeSupportSwift).
final class Gateway: @unchecked Sendable {
    static let port: UInt16 = 47811

    struct Request {
        let method: String
        let path: String
        let headers: [String: String]   // lowercased names
        let body: Data
    }

    private var listener: NWListener?
    private let queue = DispatchQueue(label: "dev.forge.gateway")
    private let handler: @Sendable (Request) async -> (Int, [String: Any])

    init(handler: @escaping @Sendable (Request) async -> (Int, [String: Any])) {
        self.handler = handler
    }

    func start() throws {
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: Self.port)!)
        params.allowLocalEndpointReuse = true
        let listener = try NWListener(using: params)
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: self?.queue ?? .main)
            self?.receive(connection, buffer: Data())
        }
        listener.start(queue: queue)
        self.listener = listener
    }

    private func receive(_ connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1 << 16) { [weak self] data, _, done, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            if let request = Self.parse(buffer) {
                Task {
                    let (status, json) = await self.handler(request)
                    self.respond(connection, status: status, json: json)
                }
            } else if done || error != nil || buffer.count > 40_000_000 {
                connection.cancel()
            } else {
                self.receive(connection, buffer: buffer)
            }
        }
    }

    private func respond(_ connection: NWConnection, status: Int, json: [String: Any]) {
        let body = (try? JSONSerialization.data(withJSONObject: json)) ?? Data("{}".utf8)
        let reason = HTTPURLResponse.localizedString(forStatusCode: status).capitalized
        var response = Data("HTTP/1.1 \(status) \(reason)\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n\r\n".utf8)
        response.append(body)
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    /// Returns a request once the headers and the full body have arrived.
    private static func parse(_ data: Data) -> Request? {
        guard let split = data.range(of: Data("\r\n\r\n".utf8)),
              let head = String(data: data[..<split.lowerBound], encoding: .utf8) else { return nil }
        var lines = head.components(separatedBy: "\r\n")
        let start = lines.removeFirst().split(separator: " ")
        guard start.count >= 2 else { return nil }
        var headers: [String: String] = [:]
        for line in lines {
            guard let colon = line.firstIndex(of: ":") else { continue }
            headers[line[..<colon].lowercased()] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
        }
        let length = Int(headers["content-length"] ?? "0") ?? 0
        let body = data[split.upperBound...]
        guard body.count >= length else { return nil }
        return Request(method: String(start[0]), path: String(start[1]), headers: headers, body: Data(body.prefix(length)))
    }
}

/// Runs an in-app AI request with whatever Forge is connected to.
enum AppAI {
    static let models: [(id: String, label: String, openRouter: String)] = [
        ("haiku", "Fast & cheap (Claude Haiku)", "anthropic/claude-haiku-4.5"),
        ("sonnet", "Smarter (Claude Sonnet)", "anthropic/claude-sonnet-5.5"),
    ]

    static var model: (id: String, label: String, openRouter: String) {
        let id = UserDefaults.standard.string(forKey: "appModel") ?? "haiku"
        return models.first { $0.id == id } ?? models[0]
    }

    struct Failure: Error { let message: String }

    /// Returns the model's text and what the call cost in USD.
    /// An image from the app: `media_type` (e.g. image/jpeg) and base64 `data`.
    struct Image {
        let mediaType: String
        let data: String
    }

    /// `model` overrides the in-app model (an OpenRouter model ID), e.g. for Forge's own import review.
    static func complete(prompt: String, images: [Image], system: String, json: Bool,
                         model: String? = nil) async throws -> (String, Double) {
        var system = system
        if json { system += "\n\nRespond with only valid JSON. No prose, no code fences." }
        guard Provider.hasKey else {
            throw Failure(message: "Forge needs an OpenRouter key before apps can use AI. Add one in Forge → Settings (⌘,).")
        }
        let (text, cost) = try await viaOpenRouter(prompt: prompt, images: images, system: system,
                                                   model: model ?? Self.model.openRouter)
        return (json ? stripFences(text) : text, cost)
    }

    /// Creates or edits an image with the image model from Settings, via OpenRouter's image API.
    /// `references` are input images to edit or combine. Returns PNG data and the cost in USD.
    static func image(prompt: String, references: [Image], aspectRatio: String?) async throws -> (Data, Double) {
        guard Provider.hasKey else {
            throw Failure(message: "Forge needs an OpenRouter key before apps can use AI. Add one in Forge → Settings (⌘,).")
        }
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/images")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 240
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
        var body: [String: Any] = ["model": Icons.artModel, "prompt": prompt, "n": 1, "output_format": "png"]
        if let aspectRatio { body["aspect_ratio"] = aspectRatio }
        if !references.isEmpty {
            body["input_references"] = references.map {
                ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
            }
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(message)"))
        }
        guard let base64 = (obj["data"] as? [[String: Any]])?.first?["b64_json"] as? String,
              let decoded = Data(base64Encoded: base64), NSImage(data: decoded) != nil else {
            throw Failure(message: "The image model didn't return a picture.")
        }
        return (decoded, (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0)
    }

    private static func viaOpenRouter(prompt: String, images: [Image], system: String,
                                      model: String) async throws -> (String, Double) {
        var request = URLRequest(url: URL(string: "https://openrouter.ai/api/v1/chat/completions")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 120
        request.setValue("Bearer \(KeyStore.openRouterKey ?? "")", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("Forge", forHTTPHeaderField: "X-Title")
        var messages: [[String: Any]] = []
        if !system.trimmed.isEmpty { messages.append(["role": "system", "content": system]) }
        let content: [[String: Any]] = [["type": "text", "text": prompt]] + images.map {
            ["type": "image_url", "image_url": ["url": "data:\($0.mediaType);base64,\($0.data)"]]
        }
        messages.append(["role": "user", "content": content])
        request.httpBody = try JSONSerialization.data(withJSONObject: [
            "model": model, "messages": messages, "usage": ["include": true],
        ] as [String: Any])

        let (data, response) = try await URLSession.shared.data(for: request)
        let obj = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] ?? [:]
        guard (response as? HTTPURLResponse)?.statusCode == 200,
              let choices = obj["choices"] as? [[String: Any]],
              let text = (choices.first?["message"] as? [String: Any])?["content"] as? String else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let message = (obj["error"] as? [String: Any])?["message"] as? String ?? "HTTP \(status)"
            throw Failure(message: Provider.friendlyError("\(status) \(message)"))
        }
        let cost = (obj["usage"] as? [String: Any])?["cost"] as? Double ?? 0
        return (text, cost)
    }

    private static func stripFences(_ text: String) -> String {
        var t = text.trimmed
        if t.hasPrefix("```") {
            t = String(t.drop(while: { $0 != "\n" }).dropFirst())
            if let end = t.range(of: "```", options: .backwards) { t = String(t[..<end.lowerBound]) }
        }
        return t.trimmed
    }
}
