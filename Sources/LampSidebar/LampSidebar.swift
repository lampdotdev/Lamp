import ExtensionKit
import SwiftUI
import AppKit
import UniformTypeIdentifiers
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
final class Link: ObservableObject {
    static let shared = Link()

    @Published var state: SidebarState?
    /// The wish's file after Share…, until the share menu has taken it (`ChatBar`).
    @Published var sharing: SidebarSharing?
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
            ChatBar(state: link.connected ? link.state : nil)
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
        .chatGround()
        // Files and pictures dropped on the chat go with the next message, as in Lamp's window.
        .onDrop(of: [.fileURL, .image], isTargeted: nil) { providers in
            Dropped.load(providers) { files in if !files.isEmpty { link.send(.attach(files)) } }
            return true
        }
    }
}

/// Whether the end of the chat is in view: within a line of it counts. Before macOS 15 there's no telling, and
/// the chat is held at its end as it was (`OpensAtEnd`).
private struct TracksEnd: ViewModifier {
    @Binding var atEnd: Bool

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content.onScrollGeometryChange(for: Bool.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.bottom - geometry.visibleRect.maxY < 24
            } action: { _, now in
                atEnd = now
            }
        } else {
            content
        }
    }
}

/// Where the top of the chat lies in its scroll view, while there's more of it to load.
private struct EarlierTop: PreferenceKey {
    static let defaultValue: CGFloat = -.infinity
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = max(value, nextValue()) }
}

/// The chat as Lamp's window draws it (`Transcript`, the composer row), from the same pieces (`ChatLook`).
private struct Chat: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState
    /// The first line when more was last asked for: the next page is asked for once that page has come.
    @State private var askedEarlierAt: UUID?
    /// Off until the chat has opened at its end, so the top of the chat seen while laying out asks for nothing.
    @State private var settled = false
    /// The end of the chat is in view, or the person hasn't scrolled away from it: while it is, the chat stays
    /// at its end as it and its panel change size.
    @State private var atEnd = true

    var body: some View {
        VStack(spacing: 0) {
            switch state.panel {
            case .versions: VersionsPanel(state: state)
            case .info: InfoPanel(state: state)
            case nil: chat
            }
        }
        .chatGround()
    }

    private var chat: some View {
        VStack(spacing: 0) {
            ScrollViewReader { scroller in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        // Scrolled near the top of a long chat: more of it, as Lamp's window loads it. Told by where
                        // this lies in the scroll view, since the stack draws every line whether or not it's seen.
                        if state.hasEarlier == true {
                            Color.clear.frame(height: 1).background(GeometryReader { geometry in
                                Color.clear.preference(key: EarlierTop.self, value: geometry.frame(in: .named("chat")).minY)
                            })
                        }
                        ForEach(state.lines) { line in
                            LineView(line: line, busy: state.busy).padding(.top, line.gap).id(line.id)
                        }
                        if let change = state.undoChange {
                            ChatLook.UndoChange { link.send(.undoChange(change)) }.padding(.top, 12)
                        }
                        if let working = state.working, let since = state.workingSince {
                            ChatLook.ActivityLine(working, started: since).padding(.top, 12)
                        }
                        if let notResponding = state.notResponding {
                            ChatLook.UnresponsiveNotice(text: notResponding) { link.send(.forceQuit) }.padding(.top, 12)
                        }
                        let queued = state.queued ?? []
                        let places = ChatLook.QueuedPlace.places(sending: queued.map { $0.sendingNow == true })
                        ForEach(Array(queued.enumerated()), id: \.element.id) { index, message in
                            ChatLook.QueuedRow(text: message.text, waitingForSetup: state.waitingForSetup ?? false,
                                               sending: message.sendingNow == true, place: places[index],
                                               onRemove: { link.send(.unqueue(message.id)) },
                                               sendNow: message.canSendNow == true ? { link.send(.sendNow(message.id)) } : nil) {
                                if let pointed = message.pointed { PointedPill(pointed: pointed) }
                                ForEach(message.attachments.indices, id: \.self) { index in
                                    AttachmentChip(attachment: message.attachments[index])
                                }
                            }
                            .padding(.top, state.lines.isEmpty && index == 0 ? 0 : places[index].first ? 32 : 8)
                        }
                        Color.clear.frame(height: 16).id("end")
                    }
                    // A readable line length, as in Lamp's window; wide sidebars get margins instead.
                    .frame(maxWidth: 640, alignment: .leading)
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: .infinity)
                }
                .coordinateSpace(name: "chat")
                // A reopened app (a reload to apply a change) brings its chat back in a new panel. The one scroll
                // to the end a moment after it appears (below) misses on a busy Mac, and the chat then stays at its
                // top. So the chat starts at its end and stays there as it and its panel change size, unless the
                // person has scrolled up to read.
                .modifier(OpensAtEnd(holdsEnd: atEnd))
                .modifier(TracksEnd(atEnd: $atEnd))
                .onPreferenceChange(EarlierTop.self) { top in
                    guard settled, top > -200, state.hasEarlier == true, askedEarlierAt != state.lines.first?.id else { return }
                    askedEarlierAt = state.lines.first?.id
                    link.send(.earlier)
                }
                // The earlier page goes in above what was being read, which stays where it was.
                .onChange(of: state.lines.first?.id) { old, _ in
                    if let old, old == askedEarlierAt { scroller.scrollTo(old, anchor: .top) }
                }
                .onChange(of: state.lines.last?.id) { follow(scroller) }
                .onChange(of: state.lines.last?.text) { follow(scroller) }
                .onChange(of: state.working) { follow(scroller) }
                .onChange(of: state.queued?.count) { follow(scroller) }
                .onChange(of: state.undoChange) { follow(scroller) }
                // Once the lines are laid out: scrolled before then, the chat opens partway up.
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        follow(scroller, animated: false)
                        DispatchQueue.main.async { settled = true }
                    }
                }
            }
            // As Lamp's window shows it: why dictation didn't start, and the way to System Settings to fix it.
            .alert(state.dictationProblem?.title ?? "Dictation",
                   isPresented: Binding(get: { state.dictationProblem != nil },
                                        set: { if !$0 { link.send(.dictationProblem(openSettings: false)) } }),
                   presenting: state.dictationProblem) { problem in
                if let button = problem.settingsButton {
                    Button(button) { link.send(.dictationProblem(openSettings: true)) }
                    Button("Not Now", role: .cancel) {}
                } else {
                    Button("OK") {}
                }
            } message: { problem in
                Text(problem.message)
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
    }

    private func follow(_ scroller: ScrollViewProxy, animated: Bool = true) {
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { scroller.scrollTo("end", anchor: .bottom) }
    }
}

private struct LineView: View {
    @EnvironmentObject private var link: Link
    let line: SidebarLine
    let busy: Bool

    var body: some View {
        switch line.kind {
        case .user:
            ChatLook.UserRow(text: line.text, busy: busy,
                             goBack: line.canGoBack == true ? { before in link.send(.goBack(line.id, before: before)) } : nil,
                             sendAgain: line.canSendAgain == true ? { link.send(.takeBack(line.id)) } : nil,
                             isLatest: line.isLatest ?? false) {
                let attachments = line.attachments ?? []
                // What was pointed at keeps its pill; its picture counts after the other files.
                if let pointed = line.pointed {
                    PointedPill(pointed: pointed, preview: { link.send(.preview(line.id, attachments.count)) })
                }
                ForEach(attachments.indices, id: \.self) { index in
                    // A click shows it in Quick Look, as in Lamp's window.
                    Button { link.send(.preview(line.id, index)) } label: {
                        if attachments[index].isImage ?? (attachments[index].thumbnail != nil) {
                            Thumbnail(attachment: attachments[index], size: 72)
                        } else {
                            AttachmentChip(attachment: attachments[index])
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        case .agent:
            ChatLook.AgentText(line.text, keep: !line.growing)
        case .status:
            if line.symbol == ChatLook.progressSymbol {
                // The agent's line on how the work went, among a finished turn's steps.
                ChatLook.ProgressLine(line.text)
            } else if let command = ChatLook.ranCommand(in: line.text) {
                ChatLook.RanCommand(command)
            } else {
                ChatLook.StatusLine(line.text, running: line.running)
            }
        case .summary:
            ChatLook.SummaryLine(line.text)
        case .work:
            ChatLook.Worked(line.text) {
                ForEach(line.steps ?? []) { step in LineView(line: step, busy: busy) }
            }
        case .error:
            ChatLook.ErrorNote(line.text)
        case .offer:
            ChatLook.OfferCard(symbol: line.symbol ?? "sparkles", title: line.text, status: line.status ?? "", done: line.done ?? false) {
                if let button = line.button { Button(button) { link.send(.offer(line.id)) } }
            }
        case .action:
            ChatLook.ActionLine(symbol: line.symbol ?? "sparkles", text: line.text, button: line.button ?? "",
                                disabled: line.disabled ?? false) { link.send(.offer(line.id)) }
        case .note:
            ChatLook.NoteLine(title: line.text, added: line.added ?? [], removed: line.removed ?? [], undone: line.undone ?? false,
                              problem: line.problem, undo: { link.send(.undoNote(line.id)) })
        case .ask:
            AskLine(line: line)
        case .result:
            EmptyView()
        case .tools:
            ToolsLine(line: line)
        }
    }
}

/// The agent's questions as Lamp's window draws them. How far they've been answered is kept here as it changes
/// and told to Lamp, which tells it back: begun here, an answer carries on in Lamp's window, and the other way.
private struct AskLine: View {
    @EnvironmentObject private var link: Link
    let line: SidebarLine
    @State private var progress = AskProgress()
    @State private var version = -1
    /// The progress just taken from Lamp, until the change it makes has been seen: that one isn't an edit made
    /// here, so it isn't sent back, where it could undo what was typed in Lamp's window since.
    @State private var applied: AskProgress?

    var body: some View {
        if let ask = line.ask {
            AskCardView(ask: ask, isOpen: line.askOpen ?? false, progress: $progress) { answers in
                link.send(.answer(line.id, answers))
            }
            .onAppear { take() }
            // Only a change made in Lamp's window: an echo of this sidebar's own edit keeps its number, so an
            // older one arriving late never undoes what was typed since.
            .onChange(of: line.progressVersion) { take() }
            .onChange(of: progress) {
                // The change `take` made isn't sent back; every one after it is.
                if let applied, progress == applied { self.applied = nil; return }
                applied = nil
                link.send(.askProgress(line.id, progress))
            }
        } else {
            Text(line.text).font(.callout).foregroundStyle(.secondary)
        }
    }

    private func take() {
        let given = line.progressVersion ?? 0
        guard given != version else { return }
        version = given
        if let progress = line.progress, progress != self.progress {
            applied = progress
            self.progress = progress
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

/// What was pointed at, as Lamp's window shows it.
private struct PointedPill: View {
    let pointed: SidebarPointed
    var chooseAgain: (() -> Void)?
    var preview: (() -> Void)?
    var remove: (() -> Void)?

    var body: some View {
        ChatLook.PointedPill(title: pointed.title, detail: pointed.detail, chooseAgain: chooseAgain, preview: preview, remove: remove)
    }
}

/// An attachment as Lamp's window shows it in a chip.
private struct AttachmentChip: View {
    let attachment: SidebarAttachment
    var preview: (() -> Void)?
    var onRemove: (() -> Void)?

    var body: some View {
        ChatLook.Chip(onRemove: onRemove) {
            if let preview {
                Button(action: preview) {
                    ChatLook.ChipLabel(name: attachment.name) { Thumbnail(attachment: attachment, size: 28) }.contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            } else {
                ChatLook.ChipLabel(name: attachment.name) { Thumbnail(attachment: attachment, size: 28) }
            }
        }
    }
}

/// What's dropped on the chat, as files only this process can read: a file as it is, a picture (from a browser,
/// Photos, a screenshot's thumbnail) as a PNG.
private enum Dropped {
    static func load(_ providers: [NSItemProvider], completion: @escaping @MainActor ([SidebarFile]) -> Void) {
        let group = DispatchGroup()
        let lock = NSLock()
        var files: [SidebarFile] = []
        func add(_ file: SidebarFile) { lock.lock(); files.append(file); lock.unlock() }
        for provider in providers {
            group.enter()
            if provider.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                _ = provider.loadObject(ofClass: URL.self) { url, _ in
                    if let url, let data = try? Data(contentsOf: url), data.count < 50_000_000 {
                        add(SidebarFile(name: url.lastPathComponent, data: data))
                    }
                    group.leave()
                }
            } else {
                provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                    if let data, let image = NSImage(data: data), let tiff = image.tiffRepresentation,
                       let png = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                        add(SidebarFile(name: "Dropped image.png", data: png))
                    }
                    group.leave()
                }
            }
        }
        group.notify(queue: .main) { MainActor.assumeIsolated { completion(files) } }
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
                            attach: chooseFiles, point: { link.send(.point) }, send: submit, stop: { link.send(.stop) },
                            focus: { focus += 1 }) {
            Composer(text: $text, height: $height, placeholder: ChatLook.placeholder(busy: state.busy, empty: state.empty),
                     // No suggestion while a request from the chat is in the box, as in Lamp's window.
                     suggestion: state.replacing == true ? nil : state.suggestion,
                     onDismissSuggestion: { link.send(.dismissSuggestion) },
                     onEscape: state.replacing == true ? { link.send(.putBack) } : nil,
                     isEnabled: true, focusRequest: focus, onSubmit: submit, onFiles: attach)
                .frame(height: height)
        } above: {
            if let pointed = state.pointed {
                // Its picture counts after the other files (`SidebarState.pointed`).
                PointedPill(pointed: pointed, chooseAgain: pointed.canChooseAgain == true ? { link.send(.pointAgain) } : nil,
                            remove: { link.send(.removeAttachment(state.attachments.count)) })
                    .padding(.top, 4)
            }
            if !state.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach(state.attachments.indices, id: \.self) { index in
                            AttachmentChip(attachment: state.attachments[index], preview: { link.send(.preview(nil, index)) }) {
                                link.send(.removeAttachment(index))
                            }
                        }
                    }
                }
                .padding(.top, 2)
            }
        } inside: {
            // Dictation runs in Lamp, which has the microphone, and writes into the box as Lamp's window does.
            // Once something's typed the person has chosen the keyboard; while it listens, it's how dictation stops.
            if state.canDictate == true, state.listening == true || text.isEmpty {
                let listening = state.listening ?? false
                ChatLook.MicButton(listening: listening) { link.send(.dictate(!listening)) }
                    .disabled(state.submitting == true)
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

    /// As in Lamp's window: not while a message is on its way in, and a request sent again can't wait behind a turn.
    private var canSend: Bool {
        (!text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.attachments.isEmpty || state.pointed != nil)
            && state.submitting != true && !(state.replacing == true && state.busy)
    }

    /// Lamp's draft, when it was changed elsewhere.
    private func take(_ state: SidebarState) {
        guard state.draftVersion != version else { return }
        version = state.draftVersion
        if text != state.draft { text = state.draft }
        focus += 1
    }

    /// Lamp sends it and empties the box as its window does, keeping whatever came after (`afterSubmission`).
    private func submit() {
        guard canSend else { return }
        link.send(.send(text, sends: state.sends ?? 0))
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
