import Foundation

/// Phones as controllers for a TV app, through Lamp's controller relay (`relay/` in the repository). The relay hands a
/// session's phone page out over https at an address of the session's own, which phones' browsers need before they
/// give a page their motion sensors, and passes each phone's buttons, sticks and tilt to the session's host and small
/// messages back. Lamp opens a session for an app and puts its phone page there (`open`); an app on a TV then joins
/// it as host itself, with the credential Lamp hands it (`/app/controller`), and the TV preview on this Mac joins
/// through Lamp, which keeps the socket and passes it to the page (`connectPreview`). The relay's credentials are its
/// own, short-lived, and never Lamp's token for the app's AI.
@MainActor
final class ControllerRelay {
    static let shared = ControllerRelay()

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Session: Decodable {
        let session: String
        let host: String
        let socket: String
        let page: String
    }

    /// Where the relay is. None is hosted yet, so it's set per Mac (the `controllerRelay` setting, or
    /// `LAMP_CONTROLLER_RELAY`), to a relay run with `node relay/server.js`.
    static var base: URL? {
        let set = UserDefaults.standard.string(forKey: "controllerRelay") ?? ProcessInfo.processInfo.environment["LAMP_CONTROLLER_RELAY"]
        guard let set, let url = URL(string: set), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }

    /// The person is told once per app, in its chat, that controllers go through the internet.
    private static let toldKey = "controllerRelayTold"

    /// Opens a session for the app at the relay, with its phone page (the staged Phone/ folder) in place.
    func open(for project: LampProject) async throws -> Session {
        guard let base = Self.base else { throw Failure(message: "Phone controllers aren't set up on this Mac yet.") }
        let files = try Self.pageFiles(of: project)
        var request = URLRequest(url: base.appendingPathComponent("v1/sessions"))
        request.httpMethod = "POST"
        request.timeoutInterval = 10
        let (data, answer) = try await URLSession.shared.data(for: request)
        guard (answer as? HTTPURLResponse)?.statusCode == 201, let session = try? JSONDecoder().decode(Session.self, from: data) else {
            throw Failure(message: "Lamp's controller relay didn't open a game: \(String(decoding: data.prefix(200), as: UTF8.self))")
        }
        var upload = URLRequest(url: base.appendingPathComponent("v1/sessions/\(session.session)/page"))
        upload.httpMethod = "PUT"
        upload.timeoutInterval = 30
        upload.setValue("Bearer " + session.host, forHTTPHeaderField: "Authorization")
        upload.setValue("application/json", forHTTPHeaderField: "Content-Type")
        upload.httpBody = try JSONSerialization.data(withJSONObject: ["files": files.mapValues { $0.base64EncodedString() }])
        let (sent, put) = try await URLSession.shared.data(for: upload)
        guard (put as? HTTPURLResponse)?.statusCode == 204 else {
            throw Failure(message: "Lamp's controller relay didn't take the phone page: \(String(decoding: sent.prefix(200), as: UTF8.self))")
        }
        tellOnce(project)
        return session
    }

    /// The staged phone page's files by their paths, read as the gateway reads them: plain files reached through no
    /// link (`TVs.phoneFile`).
    static func pageFiles(of project: LampProject) throws -> [String: Data] {
        let root = TVs.phoneFolder(for: project)
        guard TVs.hasPhonePage(project) else { throw Failure(message: "The app has no phone page yet: put one in Phone/index.html.") }
        var files: [String: Data] = [:]
        let base = root.standardizedFileURL.path + "/"
        let found = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.isRegularFileKey])?.allObjects as? [URL] ?? []
        for url in found {
            let path = String(url.standardizedFileURL.path.dropFirst(base.count))
            let names = path.split(separator: "/").map(String.init)
            guard !names.contains(where: { $0.hasPrefix(".") }), let file = TVs.phoneFile(names, in: root),
                  let data = try? Data(contentsOf: file) else { continue }
            files[path] = data
        }
        return files
    }

    private func tellOnce(_ project: LampProject) {
        var told = Set(UserDefaults.standard.stringArray(forKey: Self.toldKey) ?? [])
        guard !told.contains(project.instance) else { return }
        told.insert(project.instance)
        UserDefaults.standard.set(Array(told), forKey: Self.toldKey)
        Store.shared.log(project, .status, "Phones control \(project.name) through Lamp's relay on the internet, so their presses and tilts leave your home network.")
    }

    // MARK: The TV preview

    /// The preview's link to the relay: Lamp keeps the socket, since the preview's page is a file on this Mac, and
    /// passes what comes to the page and what the page sends on.
    private final class Link {
        let task: URLSessionWebSocketTask
        let deliver: (String) -> Void
        var beat: Timer?
        init(task: URLSessionWebSocketTask, deliver: @escaping (String) -> Void) {
            self.task = task
            self.deliver = deliver
        }
    }
    private var links: [String: Link] = [:]

    /// Joins the preview to a new session as its host. What the relay sends goes to `deliver` as it comes, and
    /// `{"t":"closed"}` when the link is gone, so the page lets go of every button held.
    func connectPreview(_ project: LampProject, deliver: @escaping (String) -> Void) async throws {
        disconnectPreview(project)
        let session = try await open(for: project)
        guard let url = URL(string: session.socket) else { throw Failure(message: "Lamp's controller relay gave no address.") }
        let task = URLSession.shared.webSocketTask(with: url)
        let link = Link(task: task, deliver: deliver)
        links[project.id] = link
        task.resume()
        let hello = ["t": "hello", "session": session.session, "credential": session.host]
        try await task.send(.string(String(decoding: try JSONSerialization.data(withJSONObject: hello), as: UTF8.self)))
        link.beat = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { _ in
            task.send(.string(#"{"t":"beat"}"#)) { _ in }
        }
        receive(link, project: project.id)
    }

    private func receive(_ link: Link, project id: String) {
        link.task.receive { [weak self] result in
            Task { @MainActor in
                guard let self, self.links[id] === link else { return }
                switch result {
                case .success(.string(let text)):
                    link.deliver(text)
                    self.receive(link, project: id)
                case .success:
                    self.receive(link, project: id)
                case .failure:
                    self.drop(id)
                }
            }
        }
    }

    /// What the preview's page sends: only asking for a phone link, a message to phones, and the beat.
    func sendFromPreview(_ project: LampProject, _ message: [String: Any]) {
        guard let link = links[project.id], let kind = message["t"] as? String, ["link", "send", "beat"].contains(kind),
              let data = try? JSONSerialization.data(withJSONObject: message), data.count <= 1024 else { return }
        link.task.send(.string(String(decoding: data, as: UTF8.self))) { _ in }
    }

    func disconnectPreview(_ project: LampProject) {
        drop(project.id)
    }

    private func drop(_ id: String) {
        guard let link = links.removeValue(forKey: id) else { return }
        link.beat?.invalidate()
        link.task.cancel(with: .normalClosure, reason: nil)
        link.deliver(#"{"t":"closed"}"#)
    }
}
