import SwiftUI
import AppKit
import UniformTypeIdentifiers

/// The line between the chat's screen and Lamp, whichever side draws it: the extension beside a Mac app talks to Lamp
/// over its socket (`Link` in LampSidebar), Lamp's own chat panel calls Lamp directly (`LocalChat` in Lamp). The
/// screen shows `state` and hands every click and word to `send`; what only the window around it can do (close
/// the chat, move it) goes to `closeChat` and `startMove`.
@MainActor
open class ChatLink: ObservableObject {
    @Published public var state: SidebarState?
    /// The wish's file after Share…, until the share menu has taken it (`ChatBar`).
    @Published public var sharing: SidebarSharing?
    @Published public var connected = false
    /// Lamp hasn't answered for a while: it isn't open.
    @Published public var lampAway = false
    /// The box's words as last typed here, with the draft version they were typed over. Lamp doesn't send back words
    /// typed here, so a box drawn again (a panel was open in the chat's place) takes them from here, not from Lamp.
    public var typed: (version: Int, text: String)?
    /// The line the chat was scrolled to, kept as the person scrolls, so a chat drawn again elsewhere (it moved
    /// from beside the app to Lamp's panel, or back) opens where they were reading (`SidebarCommand.scrolled`).
    public var readingAt: UUID?

    public init() {}

    open func send(_ command: SidebarCommand) {}
    /// The chat's close button.
    open func closeChat() {}
    /// The person pressed on the bar and started dragging.
    open func startMove() {}
    /// Lamp isn't open: start it.
    open func openLamp() {}
}

/// The chat as everyone sees it: its bar, the chat or a panel in its place, and the message box. Drawn the same
/// beside a Mac app and in Lamp's own panel, from what Lamp sends (`ChatLink.state`).
public struct ChatScreen: View {
    public init() {}

    @EnvironmentObject private var link: ChatLink

    public var body: some View {
        VStack(spacing: 0) {
            ChatBar(state: link.connected ? link.state : nil)
            if let banner = link.state?.banner, link.connected {
                ChatLook.Banner(banner: banner) { link.send(.banner) }
            }
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

/// Which line the person is reading, said once the scrolling has settled: the first line in view, or nil at the end. Before
/// macOS 15 there's no telling, and a chat drawn again opens at its end.
private struct TracksReading: ViewModifier {
    let atEnd: Bool
    let changed: (UUID?) -> Void
    @State private var first: UUID?

    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            content
                .onScrollTargetVisibilityChange(idType: UUID.self, threshold: 0.2) { ids in first = ids.first }
                .onScrollPhaseChange { _, phase in if phase == .idle { changed(atEnd ? nil : first) } }
                .onChange(of: atEnd) { if atEnd { changed(nil) } }
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
    @EnvironmentObject private var link: ChatLink
    let state: SidebarState
    /// The first line when more was last asked for: the next page is asked for once that page has come.
    @State private var askedEarlierAt: UUID?
    /// Off until the chat has opened at its end, so the top of the chat seen while laying out asks for nothing.
    @State private var settled = false
    /// The end of the chat is in view, or the person hasn't scrolled away from it: while it is, the chat stays
    /// at its end as it and its panel change size, and follows what's added to it.
    @State private var atEnd = true

    var body: some View {
        VStack(spacing: 0) {
            if let card = state.wishLink {
                WishLinkPanel(card: card)
            } else {
                switch state.panel {
                case .versions: VersionsPanel(state: state)
                case .info: InfoPanel(state: state)
                case nil: chat
                }
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
                        // A new wish's empty chat: what it is, and ideas to start from.
                        if let intro = state.intro, state.lines.isEmpty, (state.queued ?? []).isEmpty {
                            ChatLook.Intro(intro: intro, rename: { link.send(.rename($0)) }, choose: { link.send(.idea($0)) },
                                           more: { link.send(.moreIdeas) })
                        }
                        ForEach(state.lines) { line in
                            LineView(line: line, busy: state.busy, state: state).padding(.top, line.gap).id(line.id)
                        }
                        if let change = state.undoChange {
                            ChatLook.UndoChange { link.send(.undoChange(change)) }.padding(.top, 12)
                        }
                        // A first build has its live line in the part being built.
                        if let working = state.working, let since = state.workingSince,
                           !state.lines.contains(where: { $0.build?.parts.contains(where: \.live) == true }) {
                            ChatLook.ActivityLine(working, started: since, since: state.workingActivitySince,
                                                  hasSteps: !(state.workingSteps ?? []).isEmpty) {
                                ForEach(state.workingSteps ?? []) { step in LineView(line: step, busy: false) }
                            }
                            .padding(.top, 12)
                        }
                        if let notResponding = state.notResponding {
                            ChatLook.UnresponsiveNotice(text: notResponding) { link.send(.forceQuit) }.padding(.top, 12)
                        }
                        let queued = state.queued ?? []
                        let places = ChatLook.QueuedPlace.places(sending: queued.map { $0.sendingNow == true })
                        ForEach(Array(queued.enumerated()), id: \.element.id) { index, message in
                            ChatLook.QueuedRow(text: message.text, waitingForSetup: state.waitingForSetup ?? false,
                                               waitingForReload: state.waitingForReload ?? false,
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
                    .scrollTargetLayout()
                    // A readable line length; wide chats get margins instead.
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
                .modifier(TracksReading(atEnd: atEnd) { reading in
                    guard settled, link.readingAt != reading else { return }
                    link.readingAt = reading
                    link.send(.scrolled(reading))
                })
                .onPreferenceChange(EarlierTop.self) { top in
                    guard settled, top > -200, state.hasEarlier == true, askedEarlierAt != state.lines.first?.id else { return }
                    askedEarlierAt = state.lines.first?.id
                    link.send(.earlier)
                }
                // The earlier page goes in above what was being read, which stays where it was.
                .onChange(of: state.lines.first?.id) { old, _ in
                    if let old, old == askedEarlierAt { scroller.scrollTo(old, anchor: .top) }
                }
                // What the person sends is followed wherever they were; anything else only while they're at the end.
                .onChange(of: state.lines.last?.id) { follow(scroller, always: state.lines.last?.kind == .user) }
                .onChange(of: state.lines.last?.text) { follow(scroller) }
                .onChange(of: state.working) { follow(scroller) }
                .onChange(of: state.queued?.count) { old, new in follow(scroller, always: (new ?? 0) > (old ?? 0)) }
                .onChange(of: state.undoChange) { follow(scroller) }
                // Once the lines are laid out: scrolled before then, the chat opens partway up.
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        // Where the person was reading when this chat was last drawn, here or in the other chat: it
                        // moved (beside the app, into Lamp's panel) and opens there, not at its end.
                        if let reading = state.readingAt, state.lines.contains(where: { $0.id == reading }) {
                            atEnd = false
                            link.readingAt = reading
                            scroller.scrollTo(reading, anchor: .top)
                        } else {
                            follow(scroller, animated: false, always: true)
                        }
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
                                      request: approval.request, whyAsked: approval.whyAsked,
                                      onAllow: { link.send(.approve(approval.id, allow: true, allowAll: false)) },
                                      onAllowAll: { link.send(.approve(approval.id, allow: true, allowAll: true)) },
                                      onDeny: { link.send(.approve(approval.id, allow: false, allowAll: false)) })
                    // Each request starts with How to Decide closed, even when one follows another.
                    .id(approval.id)
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20).padding(.top, 8)
                    .frame(maxWidth: .infinity)
            }
            ComposerRow(state: state)
        }
    }

    /// To the end of the chat, unless the person has scrolled up to read and `always` isn't asked for.
    private func follow(_ scroller: ScrollViewProxy, animated: Bool = true, always: Bool = false) {
        guard always || atEnd else { return }
        withAnimation(animated ? .easeOut(duration: 0.2) : nil) { scroller.scrollTo("end", anchor: .bottom) }
    }
}

/// Lines of the chat drawn on their own, as the chat draws them: a turn's steps under its live line, in the gallery.
public struct ChatLines: View {
    let lines: [SidebarLine]
    let busy: Bool

    public init(_ lines: [SidebarLine], busy: Bool = false) {
        self.lines = lines
        self.busy = busy
    }

    public var body: some View {
        ForEach(lines) { line in LineView(line: line, busy: busy).padding(.top, line.gap) }
    }
}

private struct LineView: View {
    @EnvironmentObject private var link: ChatLink
    let line: SidebarLine
    let busy: Bool
    /// The whole chat, for a first build's live line.
    var state: SidebarState?

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
                ChatLook.RanCommand(command, said: line.said)
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
            ChatLook.ErrorNote(line.text) {
                if let button = line.button { Button(button) { link.send(.offer(line.id)) }.disabled(busy) }
            }
        case .detail:
            ChatLook.DetailText(line.text)
        case .build:
            if let build = line.build {
                ChatLook.BuildChapters(build: build) { part in
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(part.lines) { line in LineView(line: line, busy: busy, state: state).padding(.top, line.gap) }
                        if part.live, let state, let working = state.working, let since = state.workingSince {
                            ChatLook.ActivityLine(working, started: since, since: state.workingActivitySince,
                                                  hasSteps: !(part.steps ?? []).isEmpty) {
                                ForEach(part.steps ?? []) { step in LineView(line: step, busy: false) }
                            }
                            .padding(.top, part.lines.isEmpty ? 2 : 10)
                        }
                    }
                }
            }
        case .offer:
            ChatLook.OfferCard(symbol: line.symbol ?? "sparkles", title: line.text, status: line.status ?? "", done: line.done ?? false) {
                // Side by side, as a pair of answers, even where the card puts its buttons under its words.
                HStack {
                    if let decline = line.declineButton { Button(decline) { link.send(.decline(line.id)) } }
                    if let button = line.button { Button(button) { link.send(.offer(line.id)) } }
                }
            }
        case .action:
            ChatLook.ActionLine(symbol: line.symbol ?? "sparkles", text: line.text, button: line.button ?? "",
                                disabled: line.disabled ?? false, prominent: line.prominent ?? false) { link.send(.offer(line.id)) }
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
    @EnvironmentObject private var link: ChatLink
    let line: SidebarLine
    @State private var progress = AskProgress()
    @State private var version = -1
    /// The progress just taken from Lamp, until the change it makes has been seen: that one isn't an edit made
    /// here, so it isn't sent back, where it could undo what was typed in Lamp's window since.
    @State private var applied: AskProgress?

    var body: some View {
        if let ask = line.ask {
            let waiting = line.takeBack.map { id in
                AskWaiting(forSetup: line.waitingForSetup ?? false) { link.send(.unqueue(id)) }
            }
            AskCardView(ask: ask, isOpen: line.askOpen ?? false, progress: $progress, waiting: waiting) { answers in
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
    @EnvironmentObject private var link: ChatLink
    let state: SidebarState
    @State private var text = ""
    @State private var height = Composer.lineHeight
    @State private var version = -1
    @State private var focus = 0
    /// The box was just emptied by Return: that isn't the person's edit, so it isn't sent to Lamp as the draft.
    @State private var emptiedToSend = false

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
        .onChange(of: text) {
            link.typed = (version, text)
            if emptiedToSend { emptiedToSend = false; return }
            link.send(.draft(text))
        }
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
        let words = link.typed.flatMap { $0.version == state.draftVersion ? $0.text : nil } ?? state.draft
        if text != words { text = words }
        focus += 1
    }

    /// Lamp sends it and empties the box as its window does, keeping whatever came after (`afterSubmission`).
    /// The box empties at once rather than when Lamp's answer comes back, which took a round trip and a redraw of
    /// the whole chat: Lamp gives the words back (a new draft) if they weren't sent after all.
    private func submit() {
        guard canSend else { return }
        link.send(.send(text, sends: state.sends ?? 0))
        if !text.isEmpty {
            emptiedToSend = true
            text = ""
        }
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







/// What the chat sits on: the chat's paper, opaque, as the app's card under it is (`LampSidebar.Paper` in
/// LampSupport.swift).
extension View {
    func chatGround() -> some View { background(ChatLook.paper) }
}

/// The bar at the top of the chat, one row: the red button that closes the chat, what the chat is for, and its
/// buttons (for a wish that isn't a Mac app beside the chat, Play or Stop and Try On's device button first), the same at
/// every width: Undo, and a button for the rest, which pressed stays lit and puts them in the title's place: Wish Info,
/// Share, Agent Details, Delete and Versions. Each does what its button in Lamp's window does: the sidebar only passes the click on. Closing
/// and the room between the buttons, which moves the chat, are the app's to do (`Host`): the panel is its window.
struct ChatBar: View {
    @EnvironmentObject private var link: ChatLink
    /// Nil until Lamp is there: the bar still closes and moves the chat.
    let state: SidebarState?
    @State private var more = false
    @State private var deleting = false
    @State private var moving = false
    /// The share button, where the share menu opens once Lamp has made the file.
    @State private var shareAnchor = Anchor()

    var body: some View {
        Group {
            if let state, let toolbar = state.toolbar {
                // One layout at every width, beside an app or on its own: the title, then the buttons used most, and the
                // button for the rest, which puts them in the title's place.
                HStack(spacing: 8) {
                    CloseLight { link.closeChat() }
                    if more {
                        Spacer(minLength: 0)
                        ToolGroup { rest(state, toolbar) }
                            .transition(.opacity.combined(with: .move(edge: .trailing)))
                    } else {
                        title(state).frame(maxWidth: .infinity)
                    }
                    ToolGroup {
                        play(toolbar)
                        tryOn(state)
                        undo(toolbar)
                        if more { versions(state, toolbar) }
                        // Its own symbol says it's on (filled), so it has no lit circle behind it.
                        ToolButton(more ? "ellipsis.rectangle.fill" : "ellipsis.rectangle", more ? "Fewer Buttons" : "More Buttons",
                                   on: more, plain: true) {
                            withAnimation(.snappy(duration: 0.2)) { more.toggle() }
                        }
                        .help(more ? "Show the title again" : "Wish info, sharing, agent details, delete and versions")
                        // Changed where it stands, the symbol simply filled: not faded or slid in as a new button.
                        .transaction { $0.animation = nil }
                    }
                }
            } else {
                HStack(spacing: 8) {
                    CloseLight { link.closeChat() }
                    Spacer(minLength: 0)
                }
            }
        }
        .frame(height: 36)
        .padding(.horizontal, 12)
        .padding(.top, 8).padding(.bottom, 6)
        // Pressing anywhere on the bar but a button and dragging moves the chat, as a title bar moves its window. The
        // app moves it from here on, following the pointer until the button is let go.
        .background {
            Color.clear.contentShape(Rectangle())
                .gesture(DragGesture(minimumDistance: 2, coordinateSpace: .global)
                    .onChanged { _ in
                        if !moving { moving = true; link.startMove() }
                    }
                    .onEnded { _ in moving = false })
        }
        .confirmationDialog("Delete “\(state?.app ?? "")”?", isPresented: $deleting) {
            Button("Move to Trash", role: .destructive) { link.send(.delete) }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The wish, its chat, its history and what it saved are moved to the Trash.")
        }
        .onChange(of: link.sharing?.id) {
            if let sharing = link.sharing { share(sharing) }
            link.sharing = nil
        }
    }

    /// Lamp's icon and name before the app's: the chat sits beside someone else's window, so it says whose it is.
    private func title(_ state: SidebarState) -> some View {
        HStack(spacing: 6) {
            // Back to the desk: Lamp's window, with every wish on it.
            Button { link.send(.showLamp) } label: { ChatLook.LampMark(side: 18) }
                .buttonStyle(.plain)
                .keyboardShortcut("[", modifiers: .command)
                .help("Show Lamp's desk (⌘[)")
                .accessibilityLabel("Show Lamp's Desk")
            Text("Lamp: \(state.app)")
                .font(.system(size: NSFont.systemFontSize, weight: .semibold))
                .lineLimit(1).truncationMode(.tail)
                // The title is part of the room to drag the chat by.
                .allowsHitTesting(false)
        }
    }

    /// Where the wish is played or shown, for a game or a screen: Try On's choices, as in Lamp's toolbar, and each place
    /// it hasn't got yet. Every other wish has none.
    @ViewBuilder private func tryOn(_ state: SidebarState) -> some View {
        if let tryOn = state.tryOn {
            Menu {
                ForEach(Array(tryOn.sections.enumerated()), id: \.offset) { index, section in
                    if index > 0, section.submenu != true { Divider() }
                    if let title = section.title, section.submenu == true {
                        Menu(title) { tryOnItems(section) }
                    } else if let title = section.title {
                        Section(title) { tryOnItems(section) }
                    } else {
                        tryOnItems(section)
                    }
                }
            } label: {
                ToolSymbol(tryOn.symbol, "Try On")
            }
            .menuStyle(.button)
            .buttonStyle(.plain)
            .menuIndicator(.hidden)
            .fixedSize()
            .help(tryOn.current.map { "Where it opens: \($0). Choose another device, or add one" } ?? "Choose where it opens, or add a device")
        }
    }

    @ViewBuilder private func tryOnItems(_ section: SidebarTryOn.Section) -> some View {
        ForEach(section.items) { item in
            Toggle(isOn: Binding(get: { item.checked }, set: { _ in link.send(.tryOn(item.id)) })) {
                Label(item.title, systemImage: item.symbol)
            }
            .disabled(item.disabled)
        }
    }

    /// Play, or Stop while it's open, for a wish that isn't a Mac window beside this chat.
    @ViewBuilder private func play(_ toolbar: SidebarToolbar) -> some View {
        if let play = toolbar.play {
            ToolButton(play.open ? "stop.fill" : "play.fill", play.open ? "Stop" : "Play") { link.send(play.open ? .quit : .play) }
                .disabled(!play.enabled)
                .help(play.help)
        }
    }

    private func undo(_ toolbar: SidebarToolbar) -> some View {
        ToolButton("arrow.uturn.backward", "Undo Last Change") { link.send(.undo) }
            .disabled(!toolbar.canUndo)
            .help(toolbar.canUndo ? "Go back to the version before this one" : "Nothing to undo yet")
    }

    private func versions(_ state: SidebarState, _ toolbar: SidebarToolbar) -> some View {
        ToolButton("clock.arrow.circlepath", "Versions", on: state.panel == .versions) {
            link.send(.panel(state.panel == .versions ? nil : .versions))
        }
        .disabled(!toolbar.hasVersions)
        .help(toolbar.hasVersions ? "See earlier versions of this wish, name them, and go back to one"
              : "No versions yet: each change Lamp makes is saved as one")
    }

    /// What the button for the rest shows (Versions goes beside Undo, the two being about the same thing).
    @ViewBuilder private func rest(_ state: SidebarState, _ toolbar: SidebarToolbar) -> some View {
        ToolButton("info.circle", "Wish Info", on: state.panel == .info) {
            link.send(.panel(state.panel == .info ? nil : .info))
        }
        .help(toolbar.usage.map { "Usage, cost and models. \($0)" } ?? "Usage, cost and models")
        Menu {
            Button("Share Link…") { link.send(.wishLink(.open)) }
            Divider()
            Button("Copy Wish File") { link.send(.copyWishFile) }
            Button("Share…") { link.send(.share) }
            Button("Export…") { link.send(.export) }
        } label: {
            ToolSymbol("square.and.arrow.up", "Share")
        }
        .menuStyle(.button)
        .buttonStyle(.plain)
        .menuIndicator(.hidden)
        .fixedSize()
        .background(AnchorView(anchor: shareAnchor))
        .disabled(!toolbar.canShare)
        .help("Share this wish")
        ToolButton("chevron.left.forwardslash.chevron.right", "Agent Details", on: toolbar.details) { link.send(.details(!toolbar.details)) }
            .help("Agent details")
        ToolButton("trash", "Delete Wish") { deleting = true }
            .help("Delete this wish")
    }

    /// The share menu, at the share button, for the file Lamp made (`SidebarState.sharing`). This process can't read
    /// Lamp's files, so the file comes whole and is kept here, where the service it's shared with reads it.
    private func share(_ sharing: SidebarSharing) {
        SharedCopy.removeEarlierFolders()
        guard let url = try? SharedCopy.keep(sharing), let view = shareAnchor.view, view.window != nil else { return }
        NSSharingServicePicker(items: [url]).show(relativeTo: view.bounds, of: view, preferredEdge: .minY)
    }
}

/// The chat's close button, drawn as a window's red one, since it closes the chat as that closes a window: a red dot
/// that shows its mark when pointed at.
private struct CloseLight: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(nsColor: .systemRed))
                .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
                .overlay {
                    Image(systemName: "xmark")
                        .font(.system(size: 6.5, weight: .heavy))
                        .foregroundStyle(.black.opacity(0.55))
                        .opacity(hovered ? 1 : 0)
                }
                .frame(width: 12, height: 12)
                .padding(6)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .help("Close the chat")
        .accessibilityLabel("Close Chat")
    }
}

/// A group of the toolbar's buttons: on one capsule of glass from macOS 26, as the system's toolbars group theirs;
/// before it, round buttons side by side as the message box's row has them.
private struct ToolGroup<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        if #available(macOS 26, *) {
            HStack(spacing: 0) { content }
                .padding(.horizontal, 4)
                .glassEffect(.regular.interactive(), in: Capsule())
        } else {
            HStack(spacing: 6) { content }
        }
    }
}

private struct ToolSymbol: View {
    let symbol: String
    let name: String
    var on = false
    /// Nothing behind the symbol when it's on: the symbol shows it.
    var plain = false
    @Environment(\.isEnabled) private var isEnabled

    init(_ symbol: String, _ name: String, on: Bool = false, plain: Bool = false) {
        self.symbol = symbol
        self.name = name
        self.on = on
        self.plain = plain
    }

    var body: some View {
        let side: CGFloat = 30
        Image(systemName: symbol)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(on ? AnyShapeStyle(Color.accentColor) : isEnabled ? AnyShapeStyle(.secondary) : AnyShapeStyle(.tertiary))
            .frame(width: side, height: side)
            .background {
                if #available(macOS 26, *) {
                    if on && !plain { Circle().fill(Color.accentColor.opacity(0.15)).padding(2) }
                } else {
                    Circle().fill(on && !plain ? AnyShapeStyle(Color.accentColor.opacity(0.15)) : AnyShapeStyle(Color(nsColor: .textBackgroundColor)))
                        .overlay(Circle().strokeBorder(Color(nsColor: .separatorColor)))
                }
            }
            .contentShape(Circle())
            .accessibilityLabel(name)
    }
}

private struct ToolButton: View {
    let symbol: String
    let name: String
    var on = false
    var plain = false
    let action: () -> Void

    init(_ symbol: String, _ name: String, on: Bool = false, plain: Bool = false, action: @escaping () -> Void) {
        self.symbol = symbol
        self.name = name
        self.on = on
        self.plain = plain
        self.action = action
    }

    var body: some View {
        Button(action: action) { ToolSymbol(symbol, name, on: on, plain: plain) }
            .buttonStyle(.plain)
            .accessibilityAddTraits(on ? .isSelected : [])
    }
}

/// The view a menu or panel is shown from, found once it's on screen.
final class Anchor {
    weak var view: NSView?
}

private struct AnchorView: NSViewRepresentable {
    let anchor: Anchor

    final class Marker: NSView {
        // Behind its button, never in its way.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> Marker {
        let view = Marker()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: Marker, context: Context) { anchor.view = view }
}

/// The agent's steps with Agent Details on, as Lamp's window shows them: one step as it is, several summed up in a
/// line that opens to each of them.
struct ToolsLine: View {
    let line: SidebarLine
    @State private var expanded = false

    var body: some View {
        let calls = line.calls ?? []
        if calls.count == 1 {
            row(calls[0], running: line.running).padding(.leading, ChatLook.stepIndent)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                Button {
                    withAnimation(.snappy(duration: 0.2)) { expanded.toggle() }
                } label: {
                    HStack(spacing: 6) {
                        Group {
                            if line.running { ProgressView().controlSize(.mini) } else { Image(systemName: line.symbol ?? "wrench.adjustable") }
                        }
                        .frame(width: 16)
                        Text(line.text)
                        Image(systemName: "chevron.right")
                            .font(.caption2.weight(.semibold))
                            .foregroundStyle(.tertiary)
                            .rotationEffect(.degrees(expanded ? 90 : 0))
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .pointingHand()
                if expanded {
                    ForEach(calls.indices, id: \.self) { index in
                        row(calls[index], running: line.running && index == calls.count - 1)
                    }
                    .padding(.leading, 10)
                }
            }
            .font(ChatLook.stepFont)
            .foregroundStyle(.secondary)
            .padding(.leading, ChatLook.stepIndent)
        }
    }

    private func row(_ call: SidebarToolCall, running: Bool) -> some View {
        HStack(spacing: 6) {
            Group {
                if running { ProgressView().controlSize(.mini) } else { Image(systemName: call.symbol) }
            }
            .frame(width: 16)
            Text(call.verb)
            if !call.argument.isEmpty {
                Text(call.argument)
                    .font(.system(.subheadline, design: .monospaced))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1).truncationMode(.middle)
            }
        }
        .font(ChatLook.stepFont)
        .foregroundStyle(.secondary)
    }
}

/// The Versions panel, in place of the chat: every saved version, newest first, with a picture of how the app
/// looked. Any of them can be named or gone back to, as in Lamp's window.
struct VersionsPanel: View {
    @EnvironmentObject private var link: ChatLink
    let state: SidebarState
    @State private var selected: String?
    @State private var restoring: SidebarVersion?
    @State private var naming: SidebarVersion?
    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Versions").font(.headline)
                Spacer()
                Button("Name Current…") { if let current = state.versions?.first { startNaming(current) } }
                    .controlSize(.small)
                    .disabled(state.versions?.isEmpty ?? true)
            }
            .padding(.horizontal, 20).padding(.vertical, 8)
            if let versions = state.versions, !versions.isEmpty {
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(versions) { version in
                            row(version)
                                .contentShape(Rectangle())
                                .onTapGesture {
                                    withAnimation(.snappy(duration: 0.2)) { selected = selected == version.id ? nil : version.id }
                                }
                        }
                    }
                    .padding(.horizontal, 12)
                    if state.hasEarlierVersions == true {
                        Button("Show Earlier Versions") { link.send(.earlierVersions) }
                            .controlSize(.small)
                            .padding(.top, 4)
                    }
                    Color.clear.frame(height: 12)
                }
            } else {
                Spacer()
                if state.versions == nil {
                    ProgressView().controlSize(.small)
                } else {
                    Text("No versions yet").font(.headline)
                    Text("Lamp saves a version every time the app changes.").font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
            }
        }
        .confirmationDialog("Go back to “\(restoring?.label ?? "")”?", isPresented: Binding(
            get: { restoring != nil }, set: { if !$0 { restoring = nil } })) {
            Button("Go Back") { if let version = restoring { link.send(.goBackToVersion(version.id)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The app is rebuilt as it was then. Later versions are kept, so you can undo this.")
        }
        .alert(naming?.named == true ? "Rename This Version" : "Name This Version", isPresented: Binding(
            get: { naming != nil }, set: { if !$0 { naming = nil } })) {
            TextField("Name", text: $name)
            Button("Save") { if let version = naming { link.send(.nameVersion(version.id, name)) } }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("A name makes this version easy to find, and to go back to later.")
        }
    }

    private func startNaming(_ version: SidebarVersion) {
        name = version.named ? version.label : ""
        naming = version
    }

    private func row(_ version: SidebarVersion) -> some View {
        let expanded = selected == version.id
        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                if !expanded { picture(version, width: 64, height: 42) }
                VStack(alignment: .leading, spacing: 2) {
                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        if version.named { Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow) }
                        Text(version.label)
                            .fontWeight(version.named ? .semibold : .regular)
                            .lineLimit(expanded ? nil : 2)
                    }
                    HStack(spacing: 4) {
                        if version.current { Text("Current").foregroundStyle(Color.accentColor) }
                        Text(version.date, format: .relative(presentation: .named))
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
                Spacer(minLength: 0)
            }
            if expanded {
                picture(version, width: nil, height: nil)
                HStack {
                    Button(version.named ? "Rename…" : "Name…") { startNaming(version) }
                    Spacer()
                    if !version.current {
                        Button("Go Back to This Version") { restoring = version }
                            .buttonStyle(.borderedProminent)
                            .disabled(state.busy)
                    }
                }
                .controlSize(.small)
            }
        }
        .padding(8)
        .background(RoundedRectangle(cornerRadius: 8).fill(expanded ? Color.accentColor.opacity(0.1) : .clear))
        .contextMenu {
            Button(version.named ? "Rename…" : "Name…") { startNaming(version) }
            if version.named { Button("Remove Name") { link.send(.nameVersion(version.id, "")) } }
            if !version.current {
                Divider()
                Button("Go Back to This Version") { restoring = version }.disabled(state.busy)
            }
        }
    }

    /// How the app looked, or a plain stand-in for versions from before pictures were kept.
    @ViewBuilder
    private func picture(_ version: SidebarVersion, width: CGFloat?, height: CGFloat?) -> some View {
        let shape = RoundedRectangle(cornerRadius: 5)
        if let data = version.picture, let image = NSImage(data: data) {
            Image(nsImage: image)
                .resizable()
                .aspectRatio(contentMode: width == nil ? .fit : .fill)
                .frame(width: width, height: height)
                .clipShape(shape)
                .overlay(shape.strokeBorder(.separator))
        } else if width != nil {
            shape.fill(.quaternary)
                .frame(width: width, height: height)
                .overlay(Image(systemName: "macwindow").foregroundStyle(.tertiary))
        }
    }
}

/// The wish's info, in place of the chat: what it has cost, what answers its AI, how Lamp builds it and where it
/// lives, the same rows as Lamp's info panel. It chooses nothing: its buttons lead to where things are chosen.
struct InfoPanel: View {
    @EnvironmentObject private var link: ChatLink
    let state: SidebarState

    var body: some View {
        Form {
            ForEach(state.info ?? []) { section in
                Section {
                    ForEach(section.rows, id: \.label) { row in
                        LabeledContent(row.label) {
                            if let value = row.value {
                                Text(value).textSelection(.enabled)
                            } else {
                                HStack(spacing: 4) { Image(systemName: "exclamationmark.circle.fill"); Text("Not Ready") }
                                    .foregroundStyle(.orange)
                            }
                        }
                    }
                } header: {
                    if let title = section.title { Text(title) }
                } footer: {
                    if !section.buttons.isEmpty {
                        // One under another: the panel is narrow.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(section.buttons, id: \.action) { button in
                                Button(button.title) { link.send(.infoAction(button.action)) }
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .overlay {
            if state.info == nil { ProgressView().controlSize(.small) }
        }
    }
}

/// The Share Link card in the chat's place (`WishLinkCard`, as Lamp's window shows it in a sheet). What's typed is
/// kept here while it's open, and taken afresh from Lamp only when Lamp changes it (a new picture).
struct WishLinkPanel: View {
    @EnvironmentObject private var link: ChatLink
    let card: SidebarWishLink
    @State private var values: WishLinkCard.Values
    @State private var revision: Int

    init(card: SidebarWishLink) {
        self.card = card
        _values = State(initialValue: Self.values(of: card))
        _revision = State(initialValue: card.revision)
    }

    private static func values(of card: SidebarWishLink) -> WishLinkCard.Values {
        WishLinkCard.Values(name: card.name, line: card.line, words: card.words, includePicture: card.includePicture)
    }

    private var changed: Bool {
        guard let shown = card.shown else { return true }
        let typed = SidebarWishLinkValues(name: values.name.trimmingCharacters(in: .whitespacesAndNewlines),
                                          line: values.line.trimmingCharacters(in: .whitespacesAndNewlines),
                                          words: values.words.trimmingCharacters(in: .whitespacesAndNewlines),
                                          includePicture: values.includePicture)
        return typed != shown || (values.includePicture && card.newPicture)
    }

    var body: some View {
        ScrollView {
            WishLinkCard(icon: card.icon.flatMap(NSImage.init(data:)), picture: card.picture.flatMap(NSImage.init(data:)),
                         values: $values,
                         limits: WishLinkCard.Limits(name: card.limits[safe: 0] ?? 60, line: card.limits[safe: 1] ?? 140,
                                                     words: card.limits[safe: 2] ?? 2000),
                         link: card.link, changed: changed,
                         stage: card.sending ? .sending : card.problem.map(WishLinkCard.Stage.failed) ?? .editing,
                         copied: card.copied && !changed,
                         retake: card.canRetake ? { link.send(.wishLink(.retake)) } : nil, retaking: card.retaking,
                         share: {
                             link.send(.wishLink(.share(SidebarWishLinkValues(name: values.name, line: values.line, words: values.words,
                                                                               includePicture: values.includePicture))))
                         },
                         copy: { link.send(.wishLink(.copy)) }, stop: { link.send(.wishLink(.stop)) },
                         close: { link.send(.wishLink(.close)) }, width: nil)
        }
        // A new picture is all Lamp changes on the card by itself: what's typed here stays as it is.
        .onChange(of: card.revision) {
            guard card.revision != revision else { return }
            revision = card.revision
            values.includePicture = card.includePicture
        }
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
