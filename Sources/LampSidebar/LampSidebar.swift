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
                // The app asks for nothing: it only shows the scene.
                connection.invalidate()
                return true
            })
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
        guard count > 0 else { return drop() }
        buffer.append(contentsOf: chunk[0..<count])
        for line in SidebarWire.lines(from: &buffer) {
            if let state = try? JSONDecoder().decode(SidebarState.self, from: line) { self.state = state }
        }
    }

    private func drop() {
        source?.cancel()
        source = nil
        if fd >= 0 { close(fd) }
        fd = -1
        buffer = Data()
        connected = false
        since = Date()
    }

    func send(_ command: SidebarCommand) {
        guard fd >= 0, let data = SidebarWire.encode(command) else { return }
        data.withUnsafeBytes { bytes in
            var offset = 0
            while offset < bytes.count {
                let written = Darwin.write(fd, bytes.baseAddress! + offset, bytes.count - offset)
                if written <= 0 { break }
                offset += written
            }
        }
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
        .background(Color(nsColor: .windowBackgroundColor))
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
                        Color.clear.frame(height: 16).id("end")
                    }
                    .padding(.horizontal, 20).padding(.top, 16)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .onChange(of: state.lines.last?.id) { follow(scroller) }
                .onChange(of: state.lines.last?.text) { follow(scroller) }
                .onChange(of: state.working) { follow(scroller) }
                // Once the lines are laid out: scrolled before then, the chat opens partway up.
                .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { follow(scroller, animated: false) } }
            }
            Divider()
            ComposerRow(state: state)
        }
        .background(Color(nsColor: .textBackgroundColor))
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
                            Thumbnail(attachment: attachments[index], size: 72)
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
        case .ask:
            if let questions = line.questions {
                QuestionCard(id: line.id, questions: questions)
            } else {
                Text(line.text).font(.callout).foregroundStyle(.secondary)
            }
        case .result:
            VStack(alignment: .leading, spacing: 8) {
                ChatLook.AgentText(line.text)
                if let untried = line.untried {
                    HStack(alignment: .firstTextBaseline) {
                        Text(untried).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Try It") { link.send(.tryIt(line.id)) }
                    }
                }
            }
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
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .help(attachment.name)
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
        VStack(spacing: 0) {
            if !state.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.attachments.indices, id: \.self) { index in
                            Thumbnail(attachment: state.attachments[index], size: 48)
                                .overlay(alignment: .topTrailing) {
                                    Button { link.send(.removeAttachment(index)) } label: {
                                        Image(systemName: "xmark.circle.fill").symbolRenderingMode(.palette)
                                            .foregroundStyle(.white, .black.opacity(0.6))
                                    }
                                    .buttonStyle(.plain)
                                    .offset(x: 5, y: -5)
                                }
                        }
                    }
                    .padding(.horizontal, 12).padding(.top, 10)
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                Button(action: chooseFiles) { Image(systemName: "paperclip").font(.title3) }
                    .buttonStyle(.borderless)
                    .help("Attach files. You can also paste images and files here.")
                    .accessibilityLabel("Attach files")
                    .frame(height: Composer.lineHeight)
                Composer(text: $text, height: $height, placeholder: ChatLook.placeholder(busy: state.busy, empty: state.empty),
                         isEnabled: true, focusRequest: focus, onSubmit: submit, onFiles: attach)
                    .frame(height: height)
                if state.busy { ChatLook.StopButton { link.send(.stop) } }
                ChatLook.SendButton(busy: state.busy, action: submit)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && state.attachments.isEmpty)
            }
            .padding(12)
        }
        .onAppear { take(state) }
        .onChange(of: state.draftVersion) { take(state) }
        .onChange(of: text) { link.send(.draft(text)) }
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

/// The agent's questions: each answered with a click, sent once every one has its answer.
private struct QuestionCard: View {
    @EnvironmentObject private var link: Link
    let id: UUID
    let questions: [SidebarQuestion]
    @State private var chosen: [Int: String] = [:]

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ForEach(questions.indices, id: \.self) { index in
                let question = questions[index]
                VStack(alignment: .leading, spacing: 8) {
                    Text(question.question).font(.headline)
                    FlowRow(spacing: 6) {
                        ForEach(question.options.indices, id: \.self) { option in
                            let title = question.options[option]
                            Button {
                                chosen[index] = title
                                if chosen.count == questions.count {
                                    link.send(.answer(id, questions.indices.map { chosen[$0] ?? "" }))
                                }
                            } label: {
                                HStack(spacing: 5) {
                                    if let symbol = question.symbols[safe: option] ?? nil { Image(systemName: symbol) }
                                    Text(title)
                                }
                                .padding(.horizontal, 10).padding(.vertical, 6)
                                .background(chosen[index] == title ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.14),
                                            in: Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

/// Chips that wrap onto the next row as the width runs out.
private struct FlowRow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(subviews, width: proposal.width ?? .infinity)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.items {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: bounds.minY + row.y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
        }
    }

    private struct Row { var items: [Int] = []; var width: CGFloat = 0; var height: CGFloat = 0; var y: CGFloat = 0 }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if !rows[rows.count - 1].items.isEmpty, rows[rows.count - 1].width + spacing + size.width > width {
                let y = rows[rows.count - 1].y + rows[rows.count - 1].height + spacing
                rows.append(Row(y: y))
            }
            var row = rows[rows.count - 1]
            row.width += (row.items.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.items.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
