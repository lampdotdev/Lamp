import ExtensionKit
import SwiftUI
import AppKit
import LampSidebarKit

/// The chat inside an app's own window: an extension Lamp puts in every Mac app it builds, which the app shows
/// beside its content when the 🪄 is clicked (`LampSidebar` in LampSupport.swift). It runs in a process of its
/// own, sandboxed, so the app's code can neither draw it nor read it, and it speaks only to Lamp, which checks
/// that it's this program before it listens. It shows what Lamp sends and passes on what the person does.
@main
struct SidebarExtension: AppExtension {
    init() {}

    var configuration: AppExtensionSceneConfiguration {
        AppExtensionSceneConfiguration(
            PrimitiveAppExtensionScene(id: "chat") {
                ChatScreen().environmentObject(Link.shared as ChatLink)
            } onConnection: { connection in
                // The app only says where the sidebar is on screen; the sidebar asks it to close or move its panel.
                connection.exportedInterface = NSXPCInterface(with: SidebarPlacement.self)
                connection.exportedObject = Placement()
                connection.remoteObjectInterface = NSXPCInterface(with: SidebarHost.self)
                connection.resume()
                DispatchQueue.main.async { MainActor.assumeIsolated { Host.add(connection) } }
                return true
            })
    }
}

private final class Placement: NSObject, SidebarPlacement {
    func place(x: Double, y: Double) {
        DispatchQueue.main.async {
            Composer.hostOrigin = CGPoint(x: x, y: y)
            // A popup already showing for the caret (an input method's candidates) is moved with it.
            NSTextInputContext.current?.invalidateCharacterCoordinates()
        }
    }
}

/// The app hosting the chat, for what only it can do with the chat's panel (`SidebarHost`). An app with a chat beside
/// each of several windows has one connection for each, and nothing here says which connection is which chat's: each
/// is asked, and the app acts on the chat the pointer is on (`LampSidebar.Answering`), where the click was.
@MainActor
enum Host {
    private static var connections: [NSXPCConnection] = []

    static func add(_ connection: NSXPCConnection) {
        connections.append(connection)
        connection.invalidationHandler = { [weak connection] in
            DispatchQueue.main.async { MainActor.assumeIsolated { connections.removeAll { $0 === connection || $0 == nil } } }
        }
    }

    private static var apps: [SidebarHost] { connections.compactMap { $0.remoteObjectProxy as? SidebarHost } }

    static func closeChat() {
        let request = UUID().uuidString
        apps.forEach { $0.closeChat(request: request) }
    }
    static func startMove() {
        let request = UUID().uuidString
        apps.forEach { $0.startMove(request: request) }
    }
}

/// The line to Lamp: a connection on this Mac's own address, at the port Lamp wrote into this extension's
/// Info.plist. Tried again until Lamp is there.
@MainActor
final class Link: ChatLink {
    static let shared = Link()


    private var fd: Int32 = -1
    private var outbox: SidebarOutbox?
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var since = Date()

    private var lookedForLamp = Date.distantPast

    private override init() {
        super.init()
        // What the chat offers on a Mac without Lamp, from what Lamp wrote into this extension as it installed the app.
        let info = Bundle.main.infoDictionary ?? [:]
        remix = RemixOffer(name: info["CFBundleName"] as? String ?? "this app",
                           about: (info["LampAbout"] as? String).flatMap { $0.isEmpty ? nil : $0 },
                           suggestions: RemixIdea.from(plist: info["LampSuggestions"]),
                           shareLink: (info["LampShareLink"] as? String).flatMap { $0.isEmpty ? nil : URL(string: $0) })
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { Link.shared.tryConnecting() }
        }
        tryConnecting()
    }

    private func tryConnecting() {
        guard fd < 0 else { return }
        lampAway = Date().timeIntervalSince(since) > 3
        // Whether Lamp is on this Mac at all, asked of macOS now and then while Lamp is away: an app built from its
        // code, or kept after Lamp was removed, gets the remix panel rather than a wait for Lamp.
        if lampAway, Date().timeIntervalSince(lookedForLamp) > 5, let host = Bundle.main.object(forInfoDictionaryKey: "LampHost") as? String {
            lookedForLamp = Date()
            lampInstalled = NSWorkspace.shared.urlForApplication(withBundleIdentifier: host) != nil
        }
        guard let port = (Bundle.main.object(forInfoDictionaryKey: "LampPort") as? NSNumber)?.uint16Value else { return }
        let socket = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard socket >= 0 else { return }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = inet_addr("127.0.0.1")
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(socket, $0, socklen_t(MemoryLayout<sockaddr_in>.size)) }
        }
        guard result == 0 else { close(socket); return }
        var on: Int32 = 1
        setsockopt(socket, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        fd = socket
        outbox = SidebarOutbox(fd: socket)
        send(.hello(SidebarWire.version))
        connected = true
        lampAway = false
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: .main)
        source.setEventHandler { MainActor.assumeIsolated { Link.shared.read() } }
        source.resume()
        self.source = source
    }

    private func read() {
        var chunk = [UInt8](repeating: 0, count: 65536)
        let count = Darwin.read(fd, &chunk, chunk.count)
        if count < 0, errno == EAGAIN || errno == EINTR { return }
        guard count > 0 else { return drop() }
        buffer.append(contentsOf: chunk[0..<count])
        // A long line (a shared file) comes in many pieces: the buffer is looked through only once one ends a line.
        guard chunk[0..<count].contains(0x0A) else { return }
        for line in SidebarWire.lines(from: &buffer) {
            if let state = try? JSONDecoder().decode(SidebarState.self, from: line) {
                // Sent once: kept here as it arrives, since a state decoded after it in the same read replaces this one.
                if let sharing = state.sharing { self.sharing = sharing }
                self.state = state
            }
        }
    }

    private func drop() {
        // Versions are counted afresh by each Lamp that connects: words kept against one could be taken for another's.
        typed = nil
        outbox?.close()
        outbox = nil
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd) }
        fd = -1
        buffer = Data()
        connected = false
        since = Date()
    }

    override func send(_ command: SidebarCommand) {
        guard let outbox, let data = SidebarWire.encode(command) else { return }
        outbox.send(data)
    }

    override func closeChat() { Host.closeChat() }
    override func startMove() { Host.startMove() }

    /// The request goes to the wish's page, or Lamp's site, in the browser: Lamp isn't here to take it.
    override func continueWithLamp(_ ask: String) {
        guard let offer = remix, let url = RemixLink.url(for: offer, ask: ask) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Starts Lamp when it isn't open, by its link, without bringing it in front.
    override func openLamp() {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "LampScheme") as? String,
              let app = Bundle.main.object(forInfoDictionaryKey: "LampApp") as? String,
              let url = URL(string: "\(scheme)://sidebar?app=\(app)") else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        NSWorkspace.shared.open(url, configuration: configuration)
        since = Date()
        lampAway = false
    }
}
