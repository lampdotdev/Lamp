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
                SidebarView().environmentObject(Link.shared)
            } onConnection: { connection in
                // The app only says where the sidebar is on screen.
                connection.exportedInterface = NSXPCInterface(with: SidebarPlacement.self)
                connection.exportedObject = Placement()
                connection.resume()
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

/// The line to Lamp: a connection on this Mac's own address, at the port Lamp wrote into this extension's
/// Info.plist. Tried again until Lamp is there.
@MainActor
final class Link: ObservableObject {
    static let shared = Link()

    @Published var state: SidebarState?
    @Published var connected = false
    /// Lamp hasn't answered for a while: it isn't open.
    @Published var lampAway = false

    private var fd: Int32 = -1
    private var outbox: SidebarOutbox?
    private var source: DispatchSourceRead?
    private var buffer = Data()
    private var since = Date()

    private init() {
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { _ in
            MainActor.assumeIsolated { Link.shared.tryConnecting() }
        }
        tryConnecting()
    }

    private func tryConnecting() {
        guard fd < 0 else { return }
        lampAway = Date().timeIntervalSince(since) > 3
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
        for line in SidebarWire.lines(from: &buffer) {
            if let state = try? JSONDecoder().decode(SidebarState.self, from: line) { self.state = state }
        }
    }

    private func drop() {
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

    func send(_ command: SidebarCommand) {
        guard let outbox, let data = SidebarWire.encode(command) else { return }
        outbox.send(data)
    }

    /// Starts Lamp when it isn't open, by its link, without bringing it in front.
    func openLamp() {
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

struct SidebarView: View {
    @EnvironmentObject private var link: Link

    var body: some View {
        VStack(spacing: 0) {
            if let state = link.state, link.connected {
                Chat(state: state)
            } else {
                VStack(spacing: 12) {
                    if link.lampAway {
                        Text("Lamp isn't open").font(.headline)
                        Button("Open Lamp") { link.openLamp() }
                    } else {
                        ProgressView().controlSize(.small)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(minWidth: 280, maxWidth: .infinity, maxHeight: .infinity)
        .background(ChatLook.paper)
    }
}

/// The chat as Lamp's window draws it (`Transcript`, the composer row), from the same pieces (`ChatLook`).
private struct Chat: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(state.lines) { line in
                            LineView(line: line).padding(.top, line.gap).id(line.id)
                        }
                        if let working = state.working, let since = state.workingSince {
                            ChatLook.ActivityLine(working, started: since).padding(.top, 12)
                        }
                        if let notResponding = state.notResponding {
                            ChatLook.UnresponsiveNotice(text: notResponding) { link.send(.forceQuit) }.padding(.top, 12)
                        }
                        ForEach(state.queued ?? []) { message in
                            ChatLook.QueuedRow(text: message.text, waitingForSetup: state.waitingForSetup ?? false,
                                               onRemove: { link.send(.unqueue(message.id)) }) {
                                ForEach(message.attachments.indices, id: \.self) { index in
                                    AttachmentChip(attachment: message.attachments[index])
                                }
                            }
                            .padding(.top, state.lines.isEmpty ? 0 : 32)
                        }
                        Color.clear.frame(height: 16).id("end")
                    }
                    // A readable line length, as in Lamp's window; wide sidebars get margins instead.
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: .infinity)
                }
                .onChange(of: state.lines.last?.id) { follow(scroller) }
                .onChange(of: state.lines.last?.text) { follow(scroller) }
                .onChange(of: state.working) { follow(scroller) }
                .onChange(of: state.queued?.count) { follow(scroller) }
                // Once the lines are laid out: scrolled before then, the chat opens partway up.
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { follow(scroller, animated: false) } }
            }
            if let approval = state.approval {
                ChatLook.ApprovalCard(title: approval.title, command: approval.command, explanation: approval.explanation,
                                      onAllow: { link.send(.approve(approval.id, allow: true, allowAll: false)) },
                                      onAllowAll: { link.send(.approve(approval.id, allow: true, allowAll: true)) },
                                      onDeny: { link.send(.approve(approval.id, allow: false, allowAll: false)) })
                    // Each request starts with its command hidden, even when one follows another.
                    .id(approval.id)
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20).padding(.top, 8)
                    .frame(maxWidth: .infinity)
            }
            ComposerRow(state: state)
        }
        .background(ChatLook.paper)
    }

    private func follow(_ scroller: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { scroller.scrollTo("end", anchor: .bottom) }
    }
}

private struct LineView: View {
    @EnvironmentObject private var link: Link
    let line: SidebarLine

    var body: some View {
        switch line.kind {
        case .user:
            VStack(alignment: .trailing, spacing: 6) {
                if let attachments = line.attachments, !attachments.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(attachments.indices, id: \.self) { index in
                            if attachments[index].isImage ?? (attachments[index].thumbnail != nil) {
                                Thumbnail(attachment: attachments[index], size: 72)
                            } else {
                                AttachmentChip(attachment: attachments[index])
                            }
                        }
                    }
                }
                if !line.text.isEmpty { ChatLook.UserBubble(line.text) }
            }
            .frame(maxWidth: 480, alignment: .trailing)
            .frame(maxWidth: .infinity, alignment: .trailing)
        case .agent:
            ChatLook.AgentText(line.text, keep: !line.growing)
        case .status:
            if let command = ChatLook.ranCommand(in: line.text) {
                ChatLook.RanCommand(command)
            } else {
                ChatLook.StatusLine(line.text, running: line.running)
            }
        case .summary:
            ChatLook.SummaryLine(line.text)
        case .error:
            ChatLook.ErrorNote(line.text)
        case .note:
            ChatLook.NoteLine(title: line.text, added: line.added ?? [], removed: line.removed ?? [], undone: line.undone ?? false,
                              problem: line.problem, undo: { link.send(.undoNote(line.id)) })
        case .ask:
            AskLine(line: line)
        case .result:
            if let result = line.result {
                ResultCardView(result: result, isCurrent: line.resultCurrent ?? false,
                               picture: line.picture.flatMap(NSImage.init(data:))) { _ in link.send(.tryIt(line.id)) }
            } else {
                ChatLook.AgentText(line.text)
            }
        }
    }
}

/// The agent's questions as Lamp's window draws them. How far they've been answered is kept here as it changes
/// and told to Lamp, which tells it back: begun here, an answer carries on in Lamp's window, and the other way.
private struct AskLine: View {
    @EnvironmentObject private var link: Link
    let line: SidebarLine
    @State private var progress = AskProgress()

    var body: some View {
        if let ask = line.ask {
            AskCardView(ask: ask, isOpen: line.askOpen ?? false, progress: $progress) { answers in
                link.send(.answer(line.id, answers))
            }
            .onAppear { if let given = line.progress { progress = given } }
            .onChange(of: line.progress) { if let given = line.progress, given != progress { progress = given } }
            .onChange(of: progress) { if progress != line.progress { link.send(.askProgress(line.id, progress)) } }
        } else {
            Text(line.text).font(.callout).foregroundStyle(.secondary)
        }
    }
}


private struct Thumbnail: View {
    let attachment: SidebarAttachment
    let size: CGFloat

    var body: some View {
        Group {
            if let data = attachment.thumbnail, let image = NSImage(data: data) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Image(systemName: "doc").foregroundStyle(.secondary)
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: 5))
        .help(attachment.name)
    }
}

/// An attachment as Lamp's window shows it in a chip.
private struct AttachmentChip: View {
    let attachment: SidebarAttachment
    var onRemove: (() -> Void)?

    var body: some View {
        ChatLook.Chip(onRemove: onRemove) {
            ChatLook.ChipLabel(name: attachment.name) { Thumbnail(attachment: attachment, size: 28) }
        }
    }
}

/// The message box with the buttons around it, as in Lamp's window.
private struct ComposerRow: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState
    @State private var text = ""
    @State private var height = Composer.lineHeight
    @State private var version = -1
    @State private var focus = 0

    var body: some View {
        ChatLook.MessageBar(busy: state.busy, canSend: canSend, attachHelp: "Attach files. You can also paste images and files here.",
                            attach: chooseFiles, send: submit, stop: { link.send(.stop) }, focus: { focus += 1 }) {
            Composer(text: $text, height: $height, placeholder: ChatLook.placeholder(busy: state.busy, empty: state.empty),
                     isEnabled: true, focusRequest: focus, onSubmit: submit, onFiles: attach)
                .frame(height: height)
        } above: {
            if !state.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.attachments.indices, id: \.self) { index in
                            AttachmentChip(attachment: state.attachments[index]) { link.send(.removeAttachment(index)) }
                        }
                    }
                }
                .padding(.top, 2)
            }
        }
        // Lined up with the chat above it, as in Lamp's window.
        .frame(maxWidth: 640)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
        .onAppear { take(state) }
        .onChange(of: state.draftVersion) { take(state) }
        .onChange(of: text) { link.send(.draft(text)) }
    }

    private var canSend: Bool {
        !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.attachments.isEmpty
    }

    /// Lamp's draft, when it was changed elsewhere.
    private func take(_ state: SidebarState) {
        guard state.draftVersion != version else { return }
        version = state.draftVersion
        if text != state.draft { text = state.draft }
        focus += 1
    }

    private func submit() {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.attachments.isEmpty else { return }
        link.send(.send(text))
        text = ""
    }

    /// Only this process can read what was pasted or chosen here: the files go to Lamp whole.
    private func attach(_ urls: [URL]) {
        let files = urls.compactMap { url -> SidebarFile? in
            guard let data = try? Data(contentsOf: url), data.count < 50_000_000 else { return nil }
            return SidebarFile(name: url.lastPathComponent, data: data)
        }
        if !files.isEmpty { link.send(.attach(files)) }
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        if panel.runModal() == .OK { attach(panel.urls) }
    }
}



private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
