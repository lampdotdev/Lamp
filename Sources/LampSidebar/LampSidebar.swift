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

private struct Chat: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Text("Editing \(state.app)").font(.headline).lineLimit(1)
                Spacer()
                Button { link.send(.point) } label: { Image(systemName: "scope") }
                    .help("Point at what you want to change")
                    .accessibilityLabel("Point at Something")
                Button { link.send(.openInLamp) } label: { Image(systemName: "arrow.up.left.and.arrow.down.right") }
                    .help("Open this chat in Lamp")
                    .accessibilityLabel("Open in Lamp")
            }
            .buttonStyle(.plain)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .frame(height: 36)
            Divider()
            ScrollViewReader { scroller in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 12) {
                        ForEach(state.lines) { line in
                            LineView(line: line).id(line.id)
                        }
                        if let working = state.working {
                            HStack(spacing: 8) {
                                ProgressView().controlSize(.small)
                                Text(working).foregroundStyle(.secondary)
                                Spacer()
                                Button("Stop") { link.send(.stop) }.controlSize(.small)
                            }
                            .id("working")
                        }
                    }
                    .padding(14)
                }
                .onChange(of: state.lines.last?.id) { follow(scroller) }
                .onChange(of: state.working) { follow(scroller) }
                .onAppear { follow(scroller) }
            }
            Divider()
            Composer(state: state)
        }
    }

    private func follow(_ scroller: ScrollViewProxy) {
        withAnimation(.easeOut(duration: 0.2)) {
            if state.working != nil { scroller.scrollTo("working", anchor: .bottom) } else if let last = state.lines.last { scroller.scrollTo(last.id, anchor: .bottom) }
        }
    }
}

private struct LineView: View {
    @EnvironmentObject private var link: Link
    let line: SidebarLine

    var body: some View {
        switch line.kind {
        case .user:
            HStack {
                Spacer(minLength: 40)
                Text(line.text)
                    .textSelection(.enabled)
                    .padding(.horizontal, 12).padding(.vertical, 7)
                    .background(Color.secondary.opacity(0.18), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        case .agent:
            Text((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.text))
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        case .status:
            Label(line.text, systemImage: "checkmark.circle")
                .font(.callout).foregroundStyle(.secondary)
        case .error:
            Label(line.text, systemImage: "exclamationmark.triangle")
                .font(.callout).foregroundStyle(.orange)
        case .ask:
            if let questions = line.questions {
                QuestionCard(id: line.id, questions: questions)
            } else {
                Text(line.text).font(.callout).foregroundStyle(.secondary)
            }
        case .result:
            VStack(alignment: .leading, spacing: 8) {
                Text(line.text).fixedSize(horizontal: false, vertical: true)
                if let untried = line.untried {
                    HStack(alignment: .firstTextBaseline) {
                        Text(untried).font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Try It") { link.send(.tryIt(line.id)) }.controlSize(.small)
                    }
                }
            }
        }
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

private struct Composer: View {
    @EnvironmentObject private var link: Link
    let state: SidebarState
    @State private var text = ""
    @State private var version = -1
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !state.attachments.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(state.attachments.indices, id: \.self) { index in
                            let attachment = state.attachments[index]
                            HStack(spacing: 6) {
                                if let data = attachment.thumbnail, let image = NSImage(data: data) {
                                    Image(nsImage: image).resizable().scaledToFill().frame(width: 22, height: 22)
                                        .clipShape(RoundedRectangle(cornerRadius: 4))
                                }
                                Text(attachment.name).font(.caption).lineLimit(1)
                                Button { link.send(.removeAttachment(index)) } label: { Image(systemName: "xmark.circle.fill") }
                                    .buttonStyle(.plain).foregroundStyle(.secondary)
                            }
                            .padding(.horizontal, 8).padding(.vertical, 4)
                            .background(Color.secondary.opacity(0.14), in: Capsule())
                        }
                    }
                }
            }
            HStack(alignment: .bottom, spacing: 8) {
                TextField("Describe a change", text: $text, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...8)
                    .focused($focused)
                    .onKeyPress(.return, phases: .down) { press in
                        if press.modifiers.contains(.shift) || press.modifiers.contains(.option) {
                            text += "\n"
                            return .handled
                        }
                        submit()
                        return .handled
                    }
                Button(action: submit) {
                    Image(systemName: "arrow.up.circle.fill").font(.system(size: 20))
                }
                .buttonStyle(.plain)
                .foregroundStyle(canSend ? Color.accentColor : Color.secondary)
                .disabled(!canSend)
            }
        }
        .padding(12)
        .onAppear { take(state) }
        .onChange(of: state.draftVersion) { take(state) }
        .onChange(of: text) { link.send(.draft(text)) }
    }

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || !state.attachments.isEmpty }

    /// Lamp's draft, when it was changed elsewhere.
    private func take(_ state: SidebarState) {
        guard state.draftVersion != version else { return }
        version = state.draftVersion
        if text != state.draft { text = state.draft }
        focused = true
    }

    private func submit() {
        guard canSend else { return }
        link.send(.send(text))
        text = ""
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
