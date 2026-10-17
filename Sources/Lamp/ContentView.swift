import SwiftUI
import LampSidebarKit
import AppKit
import AVFoundation
import QuickLook
import ImagePlayground

/// The desk's window: the welcome until it's done, then the desk. Each wish's chat has a window of its own
/// (`WishWindow`).
struct ContentView: View {
    @EnvironmentObject private var store: Store
    @Environment(\.openWindow) private var openWindow
    @AppStorage(Onboarding.key) private var onboarded = false

    var body: some View {
        Group {
            if !onboarded && !store.welcomeFinished {
                OnboardingView().ignoresSafeArea()
            } else {
                Group {
                    // Only Apple's tools missing (say, still installing after the welcome): Lamp stays usable,
                    // and anything asked for waits in its chat until they're in.
                    if store.setup.checked && !store.setup.ready && !(store.setup.hasBuilder && store.setup.hasAgent) {
                        SetupView()
                    } else {
                        main
                    }
                }
                .frame(minWidth: 760, minHeight: 480)
            }
        }
        .modifier(StoreDialogs(active: store.selection == nil))
        .background(WindowKeyWatcher { store.selection = nil })
        .onAppear { LampWindows.open = openWindow }
    }

    private var main: some View {
        VStack(spacing: 0) {
            if store.setup.checked && !store.setup.hasBuildTools { BuildToolsBanner() }
            WishDesk()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            store.markRead()
        }
    }
}

struct AppIcon: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    let size: CGFloat

    var body: some View {
        if let icon = store.icons[project.id] {
            Image(nsImage: icon).resizable().interpolation(.high).frame(width: size, height: size)
        } else {
            StandInIcon(project: project, size: size)
        }
    }
}

/// What stands for an app that has no icon yet: the lamp's light for a wish still waiting to be told or sent
/// (it isn't an app yet), a blueprint for a named one.
struct StandInIcon: View {
    let project: LampProject
    let size: CGFloat

    var body: some View {
        if project.untitled {
            WishIcon(size: size)
        } else {
            BlueprintIcon(letter: project.untitled ? nil : project.name.first, size: size)
        }
    }
}

/// The lamp's light, as the site draws it under a wish: dusk warming to a glow, with one spark in it.
struct WishIcon: View {
    let size: CGFloat

    var body: some View {
        // Same footprint as a real macOS icon: an 824pt tile on a 1024pt canvas.
        let side = size * 824 / 1024
        let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.36, green: 0.27, blue: 0.50), Color(red: 0.93, green: 0.60, blue: 0.33),
                                               Color(red: 1.0, green: 0.80, blue: 0.47)],
                                      startPoint: .topLeading, endPoint: .bottomTrailing))
            shape.fill(RadialGradient(colors: [Color(red: 1.0, green: 0.93, blue: 0.72).opacity(0.95), .clear],
                                      center: .center, startRadius: 0, endRadius: side * 0.42))
            Spark().fill(.white)
                .frame(width: side * 0.34, height: side * 0.34)
                .shadow(color: Color(red: 1.0, green: 0.72, blue: 0.3).opacity(0.9), radius: side / 14)
            shape.strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, side / 160))
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: size / 60, y: size / 80)
        .frame(width: size, height: size)
    }

    /// The four-pointed spark of the site's wish button.
    private struct Spark: Shape {
        func path(in rect: CGRect) -> Path {
            let c = CGPoint(x: rect.midX, y: rect.midY), r = rect.width / 2, pinch = r * 0.2
            var path = Path()
            path.move(to: CGPoint(x: c.x, y: c.y - r))
            for (tip, side) in [(CGPoint(x: c.x + r, y: c.y), CGPoint(x: c.x + pinch, y: c.y - pinch)),
                                (CGPoint(x: c.x, y: c.y + r), CGPoint(x: c.x + pinch, y: c.y + pinch)),
                                (CGPoint(x: c.x - r, y: c.y), CGPoint(x: c.x - pinch, y: c.y + pinch)),
                                (CGPoint(x: c.x, y: c.y - r), CGPoint(x: c.x - pinch, y: c.y - pinch))] {
                path.addQuadCurve(to: tip, control: side)
            }
            path.closeSubpath()
            return path
        }
    }
}

/// The stand-in icon until the real one is designed: a blueprint of an app icon, with Apple's icon grid
/// drawn on it and the app's initial in the middle.
struct BlueprintIcon: View {
    let letter: Character?
    let size: CGFloat

    var body: some View {
        // Same footprint as a real macOS icon: an 824pt tile on a 1024pt canvas.
        let side = size * 824 / 1024
        let shape = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
        ZStack {
            shape.fill(LinearGradient(colors: [Color(red: 0.20, green: 0.46, blue: 0.86),
                                               Color(red: 0.10, green: 0.30, blue: 0.66)],
                                      startPoint: .top, endPoint: .bottom))
            Canvas { context, canvas in
                let w = canvas.width
                let thin = max(0.5, w / 400)
                var grid = Path()
                for i in 1..<8 {
                    let p = w * CGFloat(i) / 8
                    grid.move(to: CGPoint(x: p, y: 0)); grid.addLine(to: CGPoint(x: p, y: w))
                    grid.move(to: CGPoint(x: 0, y: p)); grid.addLine(to: CGPoint(x: w, y: p))
                }
                if w > 40 { context.stroke(grid, with: .color(.white.opacity(0.12)), lineWidth: thin) }
                var guides = Path()
                guides.move(to: .zero); guides.addLine(to: CGPoint(x: w, y: w))
                guides.move(to: CGPoint(x: w, y: 0)); guides.addLine(to: CGPoint(x: 0, y: w))
                for r in [0.19, 0.31] { guides.addEllipse(in: CGRect(x: w * (0.5 - r), y: w * (0.5 - r), width: w * r * 2, height: w * r * 2)) }
                guides.addRect(CGRect(x: w * 0.16, y: w * 0.16, width: w * 0.68, height: w * 0.68))
                context.stroke(guides, with: .color(.white.opacity(0.28)), lineWidth: thin * 1.5)
            }
            .clipShape(shape)
            shape.strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, side / 160))
            if let letter {
                Text(String(letter).uppercased())
                    .font(.system(size: side * 0.48, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.15), radius: side / 60, y: side / 120)
            }
        }
        .frame(width: side, height: side)
        .shadow(color: .black.opacity(0.18), radius: size / 60, y: size / 80)
        .frame(width: size, height: size)
    }
}

/// Shown next to an app when its chat has a finished reply you haven't seen.
struct ReadyDot: View {
    var size: CGFloat = 9
    var body: some View {
        Circle().fill(Color.accentColor).frame(width: size, height: size)
            .help("Ready")
            .accessibilityLabel("Ready")
    }
}

/// Image Playground, opened to make an app's icon when the person chose to draw icons themselves: by New
/// Icon in the app's menu and by the chat's Draw Icon… buttons. The person picks a picture there and Lamp
/// takes it from there. It has no menu item of its own: New Icon draws with whatever Settings says draws.
struct PlaygroundIconSheet: ViewModifier {
    @EnvironmentObject private var store: Store
    /// The window in front: only it shows the sheet.
    var active = true

    func body(content: Content) -> some View {
        if #available(macOS 15.1, *) {
            content.imagePlaygroundSheet(isPresented: Binding(get: { active && store.showingPlayground },
                                                              set: { if active { store.showingPlayground = $0 } }),
                                         concepts: [.text(store.playgroundPrompt)]) { url in
                // The file is Image Playground's own and temporary, so it's read before anything else happens.
                guard let project = store.playgroundIcon, let picture = try? Data(contentsOf: url) else { return }
                Task { await store.useIconPicture(picture, for: project) }
            }
        } else {
            content
        }
    }
}

struct AppMenu: View {
    @EnvironmentObject private var store: Store
    let project: LampProject

    var body: some View {
        let busy = store.busy.contains(project.id)
        Button("Open") { store.openPrepared(project) }
        Button("Rebuild & Open") { store.runPrepared(project) }
            .disabled(busy)
        Button("Quit") { Task { await store.quitApp(project) } }
            .disabled(!store.isOpen(project))
        if project.platform.hasIOS {
            // Which simulator the app opens in (it's built for both), or which of the person's own phones.
            Menu("Try On") { TryOnChoices(project: project) }
                .disabled(busy)
        }
        Divider()
        Button("Rename…") { store.renaming = project }
            // Still being found: the wish it becomes names it.
            .disabled(busy || project.finding)
        Button("Duplicate") { Task { await store.duplicate(project) } }
            .disabled(busy || !project.scaffolded || project.untitled)
        Button("New Icon") { Task { await store.newIcon(project) } }
            .disabled(busy || project.untitled)
        // Only once there's an app to show: a wish not yet made has nothing in Finder.
        if FileManager.default.fileExists(atPath: project.installedURL.path) {
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
            }
        }
        Divider()
        if store.canShare(project) {
            Button("Copy Wish File") { store.copyAppFile(project) }
            Button { Sharing.share(project, from: .app(project.id)) } label: {
                Label("Share…", systemImage: "square.and.arrow.up")
            }
            Button("Export…") { store.chooseExport(project) }
            Divider()
        }
        Button("Delete…", role: .destructive) { store.deleting = project }
    }
}

struct ProjectView: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var draft = ""
    @State private var hasMicrophone = true
    @State private var attachments: [URL] = []
    /// What was pointed at in the app, on its own card in the message box.
    @State private var pointed: PointedAt?
    @State private var composerHeight = Composer.lineHeight
    @State private var focusRequest = 0
    @State private var dropTargeted = false
    @StateObject private var dictation = Dictation()
    @State private var dictationUndo = Composer.DictationUndo()
    @AppStorage("showDetails") private var showDetails = false
    @AppStorage("showInfo") private var showInfo = false
    @State private var iconPreview: URL?
    @AppStorage("showVersions") private var showVersions = false
    @State private var suggestion: String?
    @State private var dismissedSuggestion: String?
    /// The request taken back into the message box, to change and send again. It and everything after it
    /// are out of sight meanwhile; they only leave the chat, and the app only goes back, when it's sent.
    @State private var replacing: UUID?
    /// What was in the message box before that, put back if the request isn't sent again after all. Kept
    /// with the draft, so it's still there after looking at another app.
    @State private var setAside: Store.Draft?
    /// Lamp's line in the chat saying a request couldn't be sent again. It comes after the lines that are
    /// out of sight, so it's shown with what's left: otherwise Send would seem to do nothing.
    @State private var sendProblem: UUID?
    /// Keep the submitted words and files fixed while setup decides whether they can be sent.
    private var submissionPending: Bool { store.pendingSubmissions.contains(store.current(project)?.id ?? project.id) }
    /// A request on its way out again: what it replaces stays out of sight until the chat has let go of it.
    @State private var sendingAgain: UUID?
    /// How many lines before the latest request the chat reaches back for. Scrolling up towards the earliest
    /// of them raises it.
    @State private var reach = LogLine.recentCount
    /// The chat's scrolling is being watched, so earlier messages come in by themselves.
    @State private var earlierOnScroll = false
    /// Whether the chat is at its end, and so follows what's added there.
    @State private var follow = ChatFollow()
    /// Goes up with each message sent from here, which takes the chat to it (see `pinned`).
    @State private var sends = 0
    /// The request sent from here, held at the top of the chat with room below it for the answer, as long
    /// as it's the latest one. Only one sent from here: a chat opens on its end, as ever.
    @State private var pinned: UUID?
    /// A message was sent from here and its request isn't in the chat yet: the next request to arrive after
    /// `pinAfter` (the latest one when it was sent) is pinned.
    @State private var pinWanted = false
    @State private var pinAfter: UUID?
    /// The chat is gliding up to a request just pinned. Nothing else moves it meanwhile: following the end
    /// would go to the same place at once, cutting the glide short.
    @State private var gliding = false
    /// Goes up to start a glide (see `EarlierOnScroll`).
    @State private var glides = 0
    /// What the toolbar knows of the app's history, for which of its buttons can do anything. Nil until read.
    @State private var history: History?

    /// Worked out once per body (see `body`): it filters the whole chat, and body runs on every streamed token.
    private var lines: [LogLine] {
        let all = store.logs[project.id] ?? []
        let hidden = (replacing ?? sendingAgain).flatMap { id in all.firstIndex { $0.id == id } }
        guard let hidden else { return LogLine.visible(all, details: showDetails) }
        let problem = all[hidden...].last { $0.id == sendProblem }
        return LogLine.visible(Array(all[..<hidden]) + (problem.map { [$0] } ?? []), details: showDetails)
    }
    private var busy: Bool { store.busy.contains(project.id) }
    /// How much of its latest message the agent has written so far: a message being written grows without
    /// adding a line, and the chat follows it down.
    private func written(_ lines: [LogLine]) -> Int { busy ? lines.last?.text.count ?? 0 : 0 }
    /// The chat area has to be about twice the build card's height before the card is pinned.
    private static let roomToPinCard: CGFloat = 560
    /// Space above a request held at the top of the chat.
    private static let pinMargin: CGFloat = 16

    /// The first turn of a new app, while it's still running.
    private var building: TurnProgress? {
        store.progress[project.id].flatMap { $0.newApp && $0.finished == nil ? $0 : nil }
    }
    private var queued: [QueuedMessage] { store.queued[project.id] ?? [] }
    /// The finished agent turn a suggestion follows up on. Nil while working, so none shows mid-turn.
    private var suggestionTurn: UUID? { busy ? nil : NextStep.turn(in: store.logs[project.id] ?? []) }
    private var shownSuggestion: String? {
        guard suggestionTurn != nil, let suggestion, suggestion != dismissedSuggestion else { return nil }
        return suggestion
    }

    /// What was pointed at in the app, going with the next message, as its pill in the message box.
    private func pointedPill(_ pointed: PointedAt) -> some View {
        ChatLook.PointedPill(title: pointed.title, detail: pointed.detail,
                             chooseAgain: store.canPoint(in: project) ? { MagicPanel.shared.pointAgain(in: project) } : nil,
                             remove: removePointed)
    }

    /// Lets what was pointed at go, and says so to the chat beside the app at once: words typed here are saved
    /// without telling it, but a pill it still showed would be sent from there as if it were still wanted.
    private func removePointed() {
        pointed = nil
        saveDraft()
        if let current = store.current(project) { store.announceDraft(of: current) }
    }

    /// The files going with the next message, above the message box.
    private var pendingAttachments: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(attachments, id: \.self) { url in
                    AttachmentChip(url: url, siblings: attachments) {
                        attachments.removeAll { $0 == url }
                        saveDraft()
                    }
                }
            }
        }
        .padding(.top, 2)
    }

    /// The chat itself, scrolled to its end. Kept out of `body`, like the rows and the message box, because
    /// as one expression the whole view is more than the compiler can type-check in reasonable time.
    private func chat(_ lines: [LogLine]) -> some View {
        // Only the end of a long chat is shown until more is asked for (see `LogLine.recentStart`).
        let start = LogLine.recentStart(in: lines, atLeast: reach)
        let shown = start > 0 ? Array(lines[start...]) : lines
        let latestRequest = lines.last { $0.kind == .user }?.id
        let pin = pinned(latestRequest)
        return ScrollViewReader { proxy in
            GeometryReader { area in
                following(scroll(shown, all: lines, start: start, pin: pin, proxy: proxy, area: area), lines, pin: pin, proxy: proxy)
            }
        }
    }

    /// The chat's scroll view and what's in it. Apart from `chat` and `following`: together they're more than
    /// the compiler will type-check in reasonable time.
    private func scroll(_ shown: [LogLine], all lines: [LogLine], start: Int, pin: UUID?, proxy: ScrollViewProxy,
                        area: GeometryProxy) -> some View {
        ScrollView {
            // Every row shown is laid out, not only the ones in view. A stack that makes its rows as
            // they scroll into view has to guess the height of the rest, and during a turn that
            // guessing could go round without ever settling, with Lamp stuck for good.
            // With the end in view, the pinned request's bubble is a margin below the top of the chat.
            ChatStack(fill: area.size.height - Self.pinMargin, end: 16) {
                // Earlier messages come in as the chat is scrolled up towards them (see `earlier`).
                // The button is only for when that can't be watched for.
                if start > 0, !earlierOnScroll {
                    Button("Show Earlier Messages") {
                        guard let top = shown.first?.id else { return }
                        showEarlier(lines, from: start)
                        // They come in above what's being read, which stays where it is.
                        Task { @MainActor in
                            await Task.yield()
                            proxy.scrollTo(top, anchor: .top)
                        }
                    }
                    .buttonStyle(.link)
                    .font(.callout)
                    .frame(maxWidth: .infinity)
                    .padding(.bottom, 24)
                }
                // While a new app is being built, its card stays in view above the steps, if there's
                // room: in a short window a pinned card would fill the chat and hide everything else.
                chatRows(shown, pin: pin, height: area.size.height,
                         cardPinned: building != nil && area.size.height >= Self.roomToPinCard)
                // Room for the answer to a request just sent. The answer fills it as it comes; once
                // there's more, the chat follows it down as ever.
                Color.clear.id("bottom").layoutValue(key: ChatStack.Room.self, value: true)
            }
            .background(EarlierOnScroll(more: start > 0, follow: follow, glides: glides, glided: {
                gliding = false
                followEnd(proxy, lines, pin: pin)
            }, watching: $earlierOnScroll) { showEarlier(lines, from: start) })
            // A readable line length; wide windows get margins instead of longer lines.
            .frame(maxWidth: 640)
            // Only at the top: the margin at the bottom is the room's (see `ChatStack.end`).
            .padding(.horizontal, 20).padding(.top, 16)
            .frame(maxWidth: .infinity)
            // At least as tall as the chat area, so a short chat still sits at the top.
            .frame(minHeight: area.size.height, alignment: .top)
        }
    }

    /// How the chat keeps to its end, or to a request just sent, as things are added.
    private func following(_ content: some View, _ lines: [LogLine], pin: UUID?, proxy: ScrollViewProxy) -> some View {
        // Undo Last Change comes a moment after the turn ends, once Lamp knows it can be offered. (Apart from the
        // rest: as one expression it's more than the type checker will take on in reasonable time.)
        content.onChange(of: undoChange) { followEnd(proxy, lines, pin: pin) }
        // A chat opens on its latest messages: the scroll view starts at the bottom, with
        // no scrolling to get there.
        // It stays at its end as the chat grows, except while a request just sent glides to the top
        // (it would be at the end at once) and while the agent's questions wait.
        .modifier(OpensAtEnd(holdsEnd: !gliding && pin == pinned && Talk.open(in: lines) == nil))
        // The chat follows what's added at its end, but only from the end: scrolled up to read
        // something earlier, it stays there. A message sent goes to the top, with room below for the answer.
        // The agent's questions come into view whole as they arrive, and then the chat holds still
        // until they're answered: following anything added meanwhile would slide the answers out
        // from under the pointer.
        .onChange(of: Talk.open(in: lines)?.id) { _, waiting in
            // Answered, by a click or in words: the chat goes back to following its end, where the
            // reply is about to be. It stopped following while the card waited, so it may not be there.
            if waiting == nil { follow.followThroughSettling() }
            // After this pass: the card isn't laid out yet, and the end is still where it was.
            if follow.atEnd { DispatchQueue.main.async { proxy.scrollTo("bottom", anchor: .bottom) } }
        }
        .onChange(of: lines.count) { followEnd(proxy, lines, pin: pin) }
        .onChange(of: written(lines)) { followEnd(proxy, lines, pin: pin) }
        .onChange(of: queued.count) { followEnd(proxy, lines, pin: pin) }
        .onChange(of: store.progress[project.id]?.plan.count) { followEnd(proxy, lines, pin: pin) }
        .onChange(of: sends) {
            follow.atEnd = true
            followEnd(proxy, lines, pin: pin)
        }
    }

    /// The request held at the top: the one pinned, or one sent from here that has just arrived. Worked out
    /// as the chat is drawn, so a request arrives with its room already below it.
    private func pinned(_ latestRequest: UUID?) -> UUID? {
        guard let latestRequest else { return nil }
        if pinWanted, latestRequest != pinAfter { return latestRequest }
        return latestRequest == pinned ? latestRequest : nil
    }

    /// Goes to the end if the chat is following it. With a request pinned, the end is where the request
    /// is at the top, so a request just arrived goes there, gently. Not while the agent's questions wait.
    private func followEnd(_ proxy: ScrollViewProxy, _ lines: [LogLine], pin: UUID?) {
        if let pin, pin != pinned {
            pinned = pin
            pinWanted = false
            follow.atEnd = true
            gliding = true
            glides += 1
            return
        }
        guard follow.atEnd, !gliding, Talk.open(in: lines) == nil else { return }
        proxy.scrollTo("bottom", anchor: .bottom)
    }

    /// Reaches one more lot back. From what's shown, not from what was asked for: a long turn can take the
    /// chat further back than that, and the next lot has to start beyond it.
    private func showEarlier(_ lines: [LogLine], from start: Int) {
        reach = LogLine.reach(in: lines, from: start) + LogLine.recentCount
    }

    /// The chat's rows: the intro for a new app, the transcript with its build card or activity, and the
    /// messages waiting their turn.
    @ViewBuilder
    private func chatRows(_ lines: [LogLine], pin: UUID?, height: CGFloat, cardPinned: Bool) -> some View {
        if lines.isEmpty && queued.isEmpty {
            // In the middle of the chat area: less the scroll view's own padding.
            NewAppIntro(project: project, draft: draftBinding)
                .frame(minHeight: height - 32)
        }
        if let card = store.progress[project.id], card.newApp,
           let request = lines.firstIndex(where: { $0.kind == .user }) {
            // The build card goes straight after the request that began the app, and stays there through
            // the agent's questions and their answers; what the agent says and does follows it.
            transcript(Array(lines[...request]), busy: false, pin: pin)
            BuildCard(project: project, progress: card)
                .padding(.top, 16).padding(.bottom, 12)
                .background(ChatLook.paper)
                // Pinned: once it reaches the top of the chat it stays there, over the steps going by.
                .visualEffect { content, geometry in
                    content.offset(y: cardPinned ? max(0, -geometry.frame(in: .scrollView).minY) : 0)
                }
                .zIndex(1)
            transcript(Array(lines[(request + 1)...]), busy: busy, progressShown: busy, pin: pin)
        } else {
            // No line of activity under the agent's questions: it would go away when the turn ends a moment
            // later, and the card above it would move.
            // Nor until the request it's working on is in: the turn starts a moment before, and the line would
            // show up under the last answer and then jump below the request.
            let awaited = pinWanted && lines.last { $0.kind == .user }?.id == pinAfter
            let progress = busy && !awaited && Talk.open(in: lines) == nil ? store.progress[project.id] : nil
            transcript(lines, busy: busy, progressShown: progress != nil, pin: pin)
            if let progress { ActivityRow(progress: progress).padding(.top, 12) }
        }
        if let change = undoChange {
            ChatLook.UndoChange { Task { await store.undo(project, change: change) } }.padding(.top, 12)
        }
        if store.notResponding[project.id] != nil {
            ChatLook.UnresponsiveNotice(text: ErrorMessages.notResponding(project.name)) { store.forceQuit(project) }.padding(.top, 12)
        }
        let places = ChatLook.QueuedPlace.places(sending: queued.map(\.sendNow))
        let canSendNow = store.canSendNow(in: project)
        ForEach(Array(queued.enumerated()), id: \.element.id) { index, message in
            let place = places[index]
            ChatLook.QueuedRow(text: message.text, waitingForSetup: !store.setup.ready, sending: message.sendNow, place: place,
                               onRemove: { store.unqueue(message, from: project) },
                               sendNow: !message.sendNow && place.last && canSendNow ? { store.sendNow(in: project, latest: message.id) } : nil) {
                if let pointed = message.pointed {
                    ChatLook.PointedPill(title: pointed.title, detail: pointed.detail)
                }
                ForEach(message.attachments, id: \.self) { AttachmentChip(url: $0, siblings: message.attachments) }
            }
                // A group's messages sit close together; the group stands apart from the chat above it.
                .padding(.top, lines.isEmpty && index == 0 ? 0 : place.first ? 32 : 8)
        }
    }

    /// The message box with the buttons around it, floating at the foot of the chat in the chat's own column.
    private func composerRow(_ lines: [LogLine]) -> some View {
        // A request sent again starts from the app as it was, so it can't wait behind other work.
        let canSend = !(submissionPending || draft.trimmed.isEmpty && attachments.isEmpty && pointed == nil || replacing != nil && busy)
        return ChatLook.MessageBar(busy: busy, canSend: canSend,
                                   attachHelp: "Attach files. You can also paste or drop images and files here.",
                                   attach: chooseFiles,
                                   // Pointing at part of the app, while it's open here with something to point at.
                                   point: store.canPoint(in: project) ? { MagicPanel.shared.point(in: project, fromLamp: true) } : nil,
                                   send: send, stop: { store.stop(project) },
                                   focus: { focusRequest += 1 }) {
            Composer(text: shownDraft, height: $composerHeight,
                     placeholder: ChatLook.placeholder(busy: busy, empty: lines.isEmpty),
                     // No suggestion while a request from the chat is in the box: it would be about a turn
                     // that's on its way out, and Escape, which dismisses one, puts the request back instead.
                     suggestion: replacing == nil ? shownSuggestion : nil,
                     onDismissSuggestion: { dismissedSuggestion = suggestion },
                     onEscape: replacing == nil ? nil : putBack,
                     isEnabled: true, focusRequest: focusRequest, dictationUndo: dictationUndo,
                     onDictationUndo: { dictation.cancel() },
                     onSubmit: send, onFiles: attach)
                .frame(height: composerHeight)
        } above: {
            if let pointed { pointedPill(pointed).padding(.top, 4) }
            if !attachments.isEmpty { pendingAttachments }
        } beside: {
            if hasMicrophone {
                Button(action: toggleDictation) {
                    Image(systemName: dictation.isListening ? "mic.fill" : "mic")
                        .foregroundStyle(dictation.isListening ? AnyShapeStyle(.red) : AnyShapeStyle(.secondary))
                        .symbolEffect(.pulse, isActive: dictation.isListening)
                }
                .buttonStyle(ChatLook.Round(prominent: false))
                .disabled(submissionPending)
                .help(dictation.isListening ? "Stop dictation" : "Dictate a change")
                .accessibilityLabel(dictation.isListening ? "Stop dictation" : "Dictate a change")
            }
        }
        // Lined up with the chat above it (see `chat`).
        .frame(maxWidth: 640)
        .padding(.horizontal, 20).padding(.top, 4).padding(.bottom, 16)
        .frame(maxWidth: .infinity)
    }

    struct History: Equatable {
        /// Undo has a version to go back to, or a stopped turn's changes to discard.
        var undoable: Bool
        /// Something has been made: the app is no longer the empty one Lamp starts with. Until then there's
        /// nothing to open, share or look back on. Read from the app's files, not its versions' messages: a
        /// request is saved in its own words, which can look like one of Lamp's own notes ("Rename to …").
        var made: Bool
        /// There's more saved than the version the app started as. Apart from `made`: an Undo back to the
        /// empty app keeps the build it undid, and Versions is how to get it back.
        var saved: Bool

        static func read(_ project: LampProject) async -> History {
            let versions = await Versions.list(project)
            let made = !Template.isScaffold(project)
            let undoable = Versions.undoTarget(in: versions) != nil
            return History(undoable: undoable ? true : await Versions.hasUnsavedChanges(project), made: made,
                           saved: made || versions.count > 1)
        }
    }
    /// The change Undo Last Change is offered under, at the end of the chat: not while anything waits to go after it.
    private var undoChange: String? { busy || !queued.isEmpty ? nil : store.undoOffers[project.id] }
    /// The history is read again whenever a turn starts or ends and whenever the chat changes (a rename, an Undo).
    private var historyKey: String { "\(project.id) \(busy) \(store.logs[project.id]?.count ?? 0)" }
    private var undoable: Bool { history?.undoable ?? true }
    private var made: Bool { history?.made ?? true }
    private var saved: Bool { history?.saved ?? true }
    /// Not for a wish not yet told, whose toolbar has no toggle to close it: the choice is kept for the next app.
    private var inspectorShown: Binding<Bool> {
        Binding(get: { !untold && (showInfo || (showVersions && saved)) }, set: { if !$0 { showInfo = false; showVersions = false } })
    }

    private func chrome(_ lines: [LogLine]) -> some View {
        VStack(spacing: 0) {
            chat(lines)
            if let approval = store.approvals[project.id] {
                ChatLook.ApprovalCard(title: approval.title, command: approval.command, explanation: approval.explanation?.look,
                             onAllow: { store.answerApproval(for: project, allow: true) },
                             onAllowAll: { store.answerApproval(for: project, allow: true, allowAll: true) },
                             onDeny: { store.answerApproval(for: project, allow: false) })
                    // Each request starts with its command hidden, even when one follows another.
                    .id(approval.id)
                    .frame(maxWidth: 640)
                    .padding(.horizontal, 20).padding(.top, 8)
                    .frame(maxWidth: .infinity)
            }
            composerRow(lines)
        }
        .overlay {
            if dropTargeted {
                RoundedRectangle(cornerRadius: 10).strokeBorder(Color.accentColor, lineWidth: 3).padding(4)
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: Attachments.dropTypes, isTargeted: $dropTargeted) { providers in
            Attachments.load(providers) { attach($0) }
            return true
        }
        .background(ChatLook.paper)
        .inspector(isPresented: inspectorShown) {
            Group {
                if showVersions && saved { VersionsView(project: project) } else { AppInfoView(project: project) }
            }
            .inspectorColumnWidth(min: 300, ideal: 340, max: 460)
        }
        .navigationTitle(project.title)
        .navigationSubtitle(usageSummary)
        .toolbarTitleMenu {
            Button("Rename…") { store.renaming = project }
                .disabled(busy || project.finding)
        }
        .toolbar { toolbar }
    }

    // Split in two: as one expression the body is more than the type checker will take on in reasonable time.
    private func observing(_ content: some View) -> some View {
        content
        .task { await store.linkOldRequests(project) }
        .onAppear {
            focusRequest += 1
            loadDraft()
            // A wish made on the desk: its words are in the draft, and go now, as if sent from here.
            if store.sendWhenShown == project.id {
                store.sendWhenShown = nil
                send()
            }
        }
        .onChange(of: store.draftUpdates[store.current(project)?.id ?? project.id]) { loadDraft() }
        .onChange(of: project.platform) { PhoneSetup.shared.refreshIfVisible() }
        .onChange(of: draft) { saveDraft() }
        .onChange(of: attachments) { saveDraft() }
        .onChange(of: pointed) { saveDraft() }
        .onChange(of: replacing) { saveDraft() }
        .onAppear { hasMicrophone = Dictation.hasMicrophone }
        // A microphone plugged in (or taken away) while the chat is open shows or hides the button.
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasConnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
        .onReceive(NotificationCenter.default.publisher(for: .AVCaptureDeviceWasDisconnected)) { _ in hasMicrophone = Dictation.hasMicrophone }
    }

    var body: some View {
        observing(chrome(lines))
        .onDisappear { dictation.cancel() }
        .alert(dictation.problem?.title ?? "Dictation",
               isPresented: Binding(get: { dictation.problem != nil }, set: { if !$0 { dictation.problem = nil } }),
               presenting: dictation.problem) { problem in
            if let url = problem.settingsURL {
                Button(problem.settingsButton) { NSWorkspace.shared.open(url) }
                Button("Not Now", role: .cancel) {}
            } else {
                Button("OK") {}
            }
        } message: { problem in
            Text(problem.message)
        }
        .onChange(of: store.chatFocusRequest) { if store.selection == project.id { focusRequest += 1 } }
        .task(id: historyKey) {
            // A read can outlast the change that started it (the git commands it runs finish even when it's
            // cancelled), so one started before a turn ended mustn't land after the read that followed.
            store.refreshUndoOffer(project)
            let read = await History.read(project)
            guard !Task.isCancelled else { return }
            history = read
        }
        .task(id: suggestionTurn) {
            suggestion = nil
            guard suggestionTurn != nil else { return }
            suggestion = await NextStep.suggest(for: project, lines: store.logs[project.id] ?? [])
        }
    }

    private func transcript(_ lines: [LogLine], busy: Bool, progressShown: Bool = false, pin: UUID? = nil) -> some View {
        Transcript(lines: lines, dir: project.dir, busy: busy, progressShown: progressShown, goBack: { line, before in
            Task { await store.restore(project, toVersionOf: line, before: before) }
        }, sendAgain: self.busy || submissionPending ? nil : takeBack, retryPhone: project.device != nil ? { udid in
            Task { await store.retryPhone(project, udid: udid) }
        } : nil, pinned: pin)
    }

    /// Persist writes synchronously so a check finishing in this event cycle sees the newest input,
    /// including writes from a newly-created chat view after navigation.
    private var draftBinding: Binding<String> {
        Binding(get: { draft }, set: { draft = $0; saveDraft() })
    }

    /// The message box: the draft, or as much of an arriving wish as has been written in (`Wish.Arrival`).
    /// The draft is the whole wish throughout, so that is what Send sends; typing ends the writing.
    private var shownDraft: Binding<String> {
        Binding(get: { store.arrivals[project.id]?.text(over: draft) ?? draft }, set: { typed in
            if let arrival = store.arrivals[project.id] {
                guard typed != arrival.text(over: draft) else { return }
                store.endArrival(for: project.id)
            }
            draft = typed
            saveDraft()
        })
    }

    private func loadDraft() {
        let saved = store.draft(for: store.current(project) ?? project)
        draft = saved.text
        attachments = saved.attachments
        pointed = saved.pointed
        replacing = saved.replacing
        setAside = saved.replacing == nil ? nil
            : Store.Draft(text: saved.setAsideText, attachments: saved.setAsideAttachments, pointed: saved.setAsidePointed)
    }

    private func saveDraft() {
        guard let current = store.current(project) else { return }
        store.saveDraft(Store.Draft(text: draft, attachments: attachments, pointed: pointed, replacing: replacing,
                                    setAsideText: setAside?.text ?? "", setAsideAttachments: setAside?.attachments ?? [],
                                    setAsidePointed: setAside?.pointed),
                        for: current)
    }

    /// Takes a request out of the chat and into the message box, with the files it was sent with.
    private func takeBack(_ line: LogLine) {
        guard !submissionPending else { return }
        if replacing == nil { setAside = Store.Draft(text: draft, attachments: attachments, pointed: pointed) }
        dictation.cancel()
        sendProblem = nil
        draft = line.text
        (attachments, pointed) = line.draftAttachments(in: project)
        replacing = line.id
        focusRequest += 1
    }

    /// Not sending it again after all: the chat is as it was, and so is the message box.
    /// Escape in the message box does this. Emptying the box doesn't: that's how someone starts the request
    /// over in new words.
    private func putBack() {
        guard !submissionPending else { return }
        replacing = nil
        sendProblem = nil
        draft = setAside?.text ?? ""
        attachments = setAside?.attachments ?? []
        pointed = setAside?.pointed
        setAside = nil
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarItem(placement: .navigation) { titleIcon }
                .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .navigation) { titleIcon }
        }
        // A wish not yet told, or still being found, has nothing to open, undo, share or look into: only its
        // icon, until it does.
        if !untold && !project.finding { appTools }
    }

    /// Nothing asked yet: a new wish, with no app behind it.
    private var untold: Bool { !project.scaffolded && (store.logs[project.id] ?? []).isEmpty && !busy }

    @ToolbarContentBuilder
    private var appTools: some ToolbarContent {
        ToolbarItem {
            // One button: Play while the app is closed, Stop while it's open, where Try On points (an app for
            // both can be open on this Mac and in a simulator at once).
            if store.isOpen(project) {
                Button { Task { await store.quitApp(project) } } label: {
                    Label("Quit", systemImage: "stop.fill")
                }
                .help("Quit \(project.name)")
            } else {
                Button { store.openPrepared(project) } label: {
                    Label("Use", systemImage: "play.fill")
                }
                .disabled(!made)
                .help(made ? "Use \(project.name) (right-click it on the desk to rebuild)" : "Lamp opens it once it's made")
            }
        }
        if project.platform.hasIOS {
            ToolbarItem {
                // Which simulator the app opens in, beside the Play button where Xcode keeps its destination.
                Menu {
                    TryOnChoices(project: project)
                } label: {
                    let device = store.devices.first { $0.udid == project.device }
                    Label(store.tryOnName(project), systemImage: !project.onIOS ? "laptopcomputer" : (device?.family ?? project.family) == .ipad ? "ipad" : "iphone")
                }
                .disabled(busy)
                .help(project.platform == .universal ? "Where it opens: this Mac, a simulator, or your own iPhone or iPad"
                      : "Where it opens: a simulator, or your own iPhone or iPad")
            }
        }
        gap
        ToolbarItemGroup {
            Button { Task { await store.undo(project) } } label: {
                Label("Undo Last Change", systemImage: "arrow.uturn.backward")
            }
            .disabled(busy || !undoable)
            .help(undoable ? "Go back to the version before this one" : "Nothing to undo yet")
            Button { store.deleting = project } label: {
                Label("Delete Wish", systemImage: "trash")
            }
            .help("Delete this wish")
            if store.canShare(project) {
                Menu {
                    Button("Copy Wish File") { store.copyAppFile(project) }
                    Button { Sharing.share(project, from: .toolbar) } label: {
                        Label("Share…", systemImage: "square.and.arrow.up")
                    }
                    Button("Export…") { store.chooseExport(project) }
                } label: {
                    Label("Share Wish", systemImage: "square.and.arrow.up")
                }
                .disabled(!made)
                .help(made ? "Send this wish to someone with Lamp" : "Nothing to share until it's made")
                .background(ShareAnchor(origin: .toolbar))
            }
        }
        gap
        ToolbarItemGroup {
            Toggle(isOn: $showDetails) {
                Label("Agent Details", systemImage: "wrench.and.screwdriver")
            }
            .help("Agent details")
            // Versions and Wish Info share the side panel: showing one hides the other.
            Toggle(isOn: Binding(get: { showVersions && saved }, set: { showVersions = $0; if $0 { showInfo = false } })) {
                Label("Versions", systemImage: "clock.arrow.circlepath")
            }
            .disabled(!saved)
            .help(saved ? "See earlier versions of this wish, name them, and go back to one" : "No versions yet: each change Lamp makes is saved as one")
            Toggle(isOn: Binding(get: { showInfo }, set: { showInfo = $0; if $0 { showVersions = false } })) {
                Label("Wish Info", systemImage: "info.circle")
            }
            .help("Show usage, cost and models for this wish")
        }
    }

    /// Separates the toolbar's groups. macOS 26 has a native spacer; earlier versions get a little blank space.
    @ToolbarContentBuilder
    private var gap: some ToolbarContent {
        if #available(macOS 26, *) {
            ToolbarSpacer(.fixed)
        } else {
            ToolbarItem { Color.clear.frame(width: 8, height: 1) }
        }
    }

    private var titleIcon: some View {
        Button { Task { iconPreview = await Icons.largePreview(project) } } label: {
            AppIcon(project: project, size: 30)
        }
        .buttonStyle(.plain)
        .help("Show \(project.title)'s icon")
        .quickLookPreview($iconPreview)
    }

    private var usageSummary: String { store.usageSummary(project) ?? "" }

    /// Dictated words are appended to whatever was already typed.
    private func toggleDictation() {
        if dictation.isListening { return dictation.stop() }
        let typed = draft
        let separator = typed.isEmpty || typed.last!.isWhitespace ? "" : " "
        focusRequest += 1
        Task {
            guard !submissionPending else { return }
            await dictation.start { heard, before in
                guard !submissionPending else { return }
                dictationUndo = .init(phrase: dictation.phrase, restoring: before.isEmpty ? typed : typed + separator + before)
                draft = typed + separator + heard
            }
        }
    }

    private func send() {
        guard !submissionPending, !draft.trimmed.isEmpty || !attachments.isEmpty || pointed != nil else { return }
        let replaced = replacing.flatMap { id in store.logs[project.id]?.first { $0.id == id } }
        guard replaced == nil || !busy else { return }
        dictation.cancel()
        let submitted = Store.Draft(text: draft, attachments: attachments, pointed: pointed, replacing: replacing,
                                    setAsideText: setAside?.text ?? "", setAsideAttachments: setAside?.attachments ?? [],
                                    setAsidePointed: setAside?.pointed)
        guard let token = store.beginSubmission(project) else { return }
        store.endArrival(for: project.id)
        // Decided now: sending makes the app busy at once, so by the time the chat hears of it, it can't tell
        // a request that starts from one that waits, which joins the queue at the end.
        pinWanted = !busy
        pinAfter = lines.last { $0.kind == .user }?.id
        sends += 1
        store.saveDraft(submitted, for: project)
        PhoneSetup.shared.perform(for: project, in: store, cancelled: {
            finishSubmission(token, captured: submitted, sent: false)
        }) { current in
            sendPrepared(submitted, replacing: replaced, to: current, token: token)
        }
    }

    private func sendPrepared(_ submitted: Store.Draft, replacing replaced: LogLine?, to current: LampProject, token: UUID) {
        let text = submitted.text.trimmed
        let files = submitted.attachments
        guard let replaced else {
            store.send(text, attachments: files, pointed: submitted.pointed, to: current)
            finishSubmission(token, captured: submitted, sent: true)
            return
        }
        sendingAgain = replaced.id
        sendProblem = nil
        Task {
            // Nothing was sent: the words go back in the box, so they aren't lost with it, and the chat
            // keeps saying why.
            let sent = await store.sendAgain(replaced, as: text, attachments: files, pointed: submitted.pointed, in: current)
            if !sent { sendProblem = store.logs[current.id]?.last { $0.kind == .error }?.id }
            sendingAgain = nil
            finishSubmission(token, captured: submitted, sent: sent)
        }
    }

    private func finishSubmission(_ token: UUID, captured: Store.Draft, sent: Bool) {
        if !sent { pinWanted = false }
        if let current = store.current(project) {
            let kept = store.draft(for: current).afterSubmission(captured, sent: sent)
            store.updateDraft(kept, for: current)
        }
        store.endSubmission(token)
        // The box takes what's left now, in the same event as the send. Left to the chat hearing of the change
        // (`draftUpdates`), the sent words stay in it until the chat next draws, and a Return pressed meanwhile
        // finds them there, with nothing on its way any more, and sends them again.
        loadDraft()
    }

    private func attach(_ files: [URL]) {
        store.attach(files, to: project)
    }

    private func chooseFiles() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.message = "Attach screenshots, mockups, images, data or documents"
        guard panel.runModal() == .OK else { return }
        let files = panel.urls
        // Changing the composer here can re-enter the chat's lazy layout while AppKit closes the panel.
        DispatchQueue.main.async { attach(files) }
    }
}

/// A label and its value on one row when they fit, else the value under the label, both left-aligned: the
/// info panel is narrow, and a value squeezed to the right edge in two lines is hard to read.
private struct InfoRow<Value: View>: View {
    let title: String
    let value: Value

    init(_ title: String, @ViewBuilder value: () -> Value) {
        self.title = title
        self.value = value()
    }

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                Spacer(minLength: 12)
                value.fixedSize()
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                value
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

extension InfoRow where Value == Text {
    init(_ title: String, value: String) {
        self.init(title) { Text(value).foregroundStyle(.secondary) }
    }
}

/// The info panel: what an app has cost, which models it uses, and where it lives.
struct AppInfoView: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    /// This app's own model choices, from an earlier Lamp that let it make them; nil fields follow Settings.
    @State private var models: AppModels

    init(project: LampProject) {
        self.project = project
        _models = State(initialValue: AppModels.load(project))
    }
    /// Bumped when Settings changes, so the defaults shown are current.
    @State private var settingsRevision = 0
    @AppStorage("settingsTab") private var settingsTab = "building"
    @Environment(\.openSettings) private var openSettings
    // What the AI rows resolve from, besides Settings: the models on this Mac (text, decisions, pictures).
    @ObservedObject private var local = LocalModels.shared
    @ObservedObject private var images = ImageModels.shared

    private var lastBuilt: Date? {
        try? project.installedURL.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
    }

    var body: some View {
        Form {
            Section {
                VStack(spacing: 8) {
                    AppIcon(project: project, size: 64)
                    Text(project.title).font(.headline)
                    if let lastBuilt {
                        Text("Built \(lastBuilt, format: .relative(presentation: .named))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity)
            }
            let _ = settingsRevision
            ForEach(Self.sections(for: project, models: models, store: store)) { section in
                Section {
                    ForEach(section.rows, id: \.label) { row in
                        if let value = row.value {
                            InfoRow(row.label) { Text(value).foregroundStyle(.secondary).textSelection(.enabled) }
                        } else {
                            InfoRow(row.label) { NotReadyBadge() }
                        }
                    }
                } header: {
                    if let title = section.title { Text(title) }
                } footer: {
                    if !section.buttons.isEmpty {
                        HStack {
                            ForEach(section.buttons, id: \.action) { button in
                                Button(button.title) { perform(button.action) }
                            }
                        }
                        .controlSize(.small)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onReceive(NotificationCenter.default.publisher(for: UserDefaults.didChangeNotification)) { _ in
            settingsRevision += 1
        }
        // Keys and this app's own choices change what answers it too.
        .onReceive(NotificationCenter.default.publisher(for: KeyStore.changed)) { _ in settingsRevision += 1 }
        .onReceive(NotificationCenter.default.publisher(for: AppModels.changed)) { _ in models = AppModels.load(project) }
        .onChange(of: project.id) { models = AppModels.load(project) }
    }

    private func perform(_ action: String) {
        if action == Self.useSettingsChoices { models = AppModels() }
        Self.perform(action, for: project) { tab in settingsTab = tab; openSettings() }
    }

    static let useSettingsChoices = "settingsChoices"

    /// A button of the panel's, here or in the chat beside the app: Settings opened at its tab, the app or its code
    /// shown in Finder, or this app's own model choices undone.
    @MainActor static func perform(_ action: String, for project: LampProject, openSettings: (String) -> Void) {
        switch action {
        case "providers", "building": openSettings(action)
        case useSettingsChoices: AppModels().save(project)
        case "showApp": NSWorkspace.shared.activateFileViewerSelecting([project.installedURL])
        case "showSource": NSWorkspace.shared.activateFileViewerSelecting([project.dir])
        default: break
        }
    }

    /// What the panel says, as plain rows (a nil value is Not Ready) and the buttons under them: drawn here and in
    /// the chat beside the app (`SidebarServer`) from this one list, so the two never say different things.
    @MainActor static func sections(for project: LampProject, models: AppModels, store: Store) -> [SidebarInfoSection] {
        let usage = store.usage[project.id] ?? AppUsage()
        let requests = (store.logs[project.id] ?? []).filter { $0.kind == .user }.count
        var sections = [SidebarInfoSection(title: "Usage", rows: [
            SidebarInfoRow(label: "Total cost", value: dollars(usage.totalCost)),
            SidebarInfoRow(label: "Changes requested", value: "\(requests)"),
            SidebarInfoRow(label: "Building the app", value: runs(usage.agentRuns ?? 0, "agent run") + " · " + dollars(usage.agentCost ?? 0)),
            SidebarInfoRow(label: "AI inside the app", value: runs(usage.calls, "call") + " · " + dollars(usage.cost)),
        ])]
        // What answers this app, read-only: models are chosen in Settings. Nothing that answers is Not Ready.
        func answer(_ title: String, _ resolution: Resolution) -> SidebarInfoRow {
            SidebarInfoRow(label: title, value: resolution.tier == .none ? nil : short(resolution.answer ?? ""))
        }
        var ai = Capability.allCases.filter { $0 != .browser }.map { answer($0.title, AppAI.resolve($0, for: project)) }
        if project.platform.hasIOS {
            // Away from the Mac a phone answers only through the OpenRouter key: without one, one row says so.
            if Provider.hasKey {
                ai += Capability.allCases.filter { $0 != .browser }.map { answer("\($0.title) away", AppAI.resolve($0, for: project, in: .phoneAway)) }
            } else {
                ai.append(SidebarInfoRow(label: "Away from this Mac", value: nil))
            }
        }
        var aiButtons = [SidebarInfoButton(title: "Configure Providers…", action: "providers")]
        // Choices an earlier Lamp let this app make for itself: the one thing left to change here.
        if models != AppModels() { aiButtons.append(SidebarInfoButton(title: "Use Settings' Choices", action: useSettingsChoices)) }
        sections.append(SidebarInfoSection(title: "AI inside this app", rows: ai, buttons: aiButtons))
        var building = [SidebarInfoRow(label: "Agent", value: Builder.engine.title)]
        if Builder.engine == .claude || Builder.engine == .codex {
            let model = Builder.engineModel(Builder.engine)
            let names = Builder.engine == .claude ? Builder.claudeModels : Builder.codexModels
            building.append(SidebarInfoRow(label: "Building with", value: model.isEmpty ? "\(Builder.engine.title)'s default"
                                           : names.first { $0.id == model }?.label ?? model))
        }
        if Builder.engine == .pi {
            building.append(SidebarInfoRow(label: "Provider", value: providerName))
            if !Builder.piModel.isEmpty { building.append(SidebarInfoRow(label: "Building with", value: buildModel)) }
        }
        sections.append(SidebarInfoSection(title: "Building", rows: building,
                                           buttons: [SidebarInfoButton(title: "Building Settings…", action: "building")]))
        var app: [SidebarInfoRow] = []
        if let stamp = store.stamps[project.id] { app.append(SidebarInfoRow(label: "Built with", value: stamp.summary)) }
        app.append(SidebarInfoRow(label: "Bundle ID", value: project.bundleID))
        sections.append(SidebarInfoSection(title: "App", rows: app, buttons: [
            SidebarInfoButton(title: "Show App in Finder", action: "showApp"),
            SidebarInfoButton(title: "Show Source Code in Finder", action: "showSource"),
        ]))
        return sections
    }

    /// A model's name without the description Settings shows: "Fast & cheap (Claude Haiku)" → "Claude Haiku",
    /// "Nano Banana 2 (Gemini 3.1 Flash Image)" → "Nano Banana 2". The panel is narrow.
    static func short(_ label: String) -> String {
        guard let open = label.firstIndex(of: "(") else { return label }
        let inside = String(label[label.index(after: open)...].prefix { $0 != ")" }).components(separatedBy: ",")[0]
        return inside.hasPrefix("Claude") ? inside : String(label[..<open]).trimmed
    }

    private static var providerName: String {
        switch Builder.piProvider {
        case Builder.localProvider: "Native Mac AI"
        case let id where id.hasPrefix("ext-"): LocalModels.externalName(id)
        case Builder.myPiProvider: "Your pi setup"
        case let id: Provider.apiProvider(id)?.name ?? id
        }
    }

    private static var buildModel: String {
        let id = Builder.piModel
        return Builder.piProvider == "openrouter" ? Provider.models.first { $0.id == id }?.label ?? id : id
    }

    private static func dollars(_ amount: Double) -> String { String(format: "$%.2f", amount) }
    private static func runs(_ n: Int, _ noun: String) -> String { "\(n) \(noun)\(n == 1 ? "" : "s")" }
}

/// While Apple's tools install, above everything: what's happening, and that requests wait for it.
struct BuildToolsBanner: View {
    @EnvironmentObject private var store: Store

    var body: some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text("Installing Apple's app-building tools. Anything you ask for starts as soon as they're in.")
                .font(.callout)
            Spacer()
            Button(store.setup.installRequested ? "Show Installer" : "Install…") {
                if store.setup.installRequested { SetupCheck.showInstaller() } else { store.requestBuildTools() }
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
    }
}

/// An app's empty chat: its icon, its name (editable), and what to do next.
struct NewAppIntro: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @Binding var draft: String
    @State private var name = ""
    @State private var fresh = false   // nothing built yet (not, say, an imported app)
    /// Drawn once when the chat first shows, so they don't change under the reader or when a draft is cleared.
    @State private var ideas: [Idea] = []
    @FocusState private var editingName: Bool

    private var busy: Bool { store.busy.contains(project.id) }

    var body: some View {
        VStack(spacing: 14) {
            // Catches the light once the reveal has passed it.
            AppIcon(project: project, size: 112).shine(delay: 0.4)
            if project.untitled && !project.fromWish {
                // Nothing to name yet: what's asked is what the person wants, a chore taken off their hands or
                // something fun, not what to make. Lamp names what it makes.
                Text("What would make your day easier, or more fun?")
                    .font(.title.weight(.semibold))
                    .multilineTextAlignment(.center)
            } else {
            // A wish reads as a title; a name typed here is the app's, and Lamp names it otherwise.
            TextField("Name", text: $name, prompt: !project.untitled ? Text(project.name)
                      : project.fromWish ? Text("") : Text("Name it, or Lamp will"))
                .textFieldStyle(.plain)
                .font(.title.weight(.semibold))
                .multilineTextAlignment(.center)
                .focused($editingName)
                .onSubmit(commit)
                .disabled(busy)
                .frame(maxWidth: 360)
                .overlay {
                    // A hint is drawn gray whatever it's told; a wish's title is drawn as one, and steps
                    // back while a name is being typed over it.
                    if project.untitled && project.fromWish && name.isEmpty {
                        Text(project.title).font(.title.weight(.semibold))
                            .opacity(editingName ? 0.3 : 1)
                            .allowsHitTesting(false)
                    }
                }
                .help("Rename this wish")
            }
            Text(project.untitled && project.fromWish ? "Here's your wish. Change anything you like."
                 : project.untitled
                 ? "Say it in your own words: a chore to take off your hands, a habit to keep, a game to play. Lamp makes it for you."
                 : "Describe what \(project.name) should do. Lamp builds it and opens it for you.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 400)
            if fresh && draft.trimmed.isEmpty && !ideas.isEmpty {
                StarterIdeas(ideas: ideas) { wish in
                    draft = wish
                    store.chatFocusRequest += 1
                }
                .padding(.top, 18)
                .padding(.horizontal, 24)
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .sparkleReveal()
        .onAppear {
            name = project.untitled ? "" : project.name
            fresh = Template.isScaffold(project)
            if ideas.isEmpty { drawIdeas() }
        }
        .onChange(of: editingName) { if !editingName { commit() } }
    }

    private func drawIdeas() {
        let others = store.projects.filter { $0.id != project.id && !$0.untitled }
        ideas = Ideas.starters(made: others.map(\.name))
    }

    private func commit() {
        let typed = name.trimmed
        guard !typed.isEmpty, typed != project.name || project.untitled else { return }
        Task { await store.rename(project, to: typed) }
    }
}

/// Hands over the window a view is in, once it is in one.
private struct WindowFinder: NSViewRepresentable {
    let found: (NSWindow) -> Void

    final class Probe: NSView {
        var found: ((NSWindow) -> Void)?
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            // After this pass: a sheet's window knows its parent only once it has been attached.
            if let window { DispatchQueue.main.async { [weak self] in self?.found?(window) } }
        }
    }

    func makeNSView(context: Context) -> Probe {
        let view = Probe()
        view.found = found
        return view
    }

    func updateNSView(_ view: Probe, context: Context) { view.found = found }
}

/// Shown before building an app someone else shared: what it does, what it can access, and any red flags.
struct ImportReviewView: View {
    @EnvironmentObject private var store: Store
    let pending: Store.PendingImport

    private var review: ImportReview? { pending.review }
    /// The app's own icon, once drawn from the file; the plain app icon until then, and for a file without one.
    @State private var icon: NSImage?
    /// What the app says it does, in its sender's words, when the file has that.
    /// How tall the sheet may be where it hangs: from its top down to the bottom of the screen's usable area
    /// (above the Dock). Unlimited until the sheet is on screen.
    @State private var room = CGFloat.infinity
    @State private var sheet: NSWindow?
    /// The heights of what stays put, measured as laid out: the app's name and description at the top, the
    /// verdict under the middle, the line about the copy already here when there is one, and the buttons.
    @State private var fixed: [Part: CGFloat] = [:]
    private enum Part { case name, verdict, existing, buttons }
    /// How tall the scrolling middle may be: the height a long review always stopped at, or less when the
    /// screen below the sheet's top is shorter than that. Taken off besides the fixed parts: the sheet's
    /// padding (48) and a 16-point gap after each part but the last.
    private var limit: CGFloat { max(60, min(400, room - fixed.values.reduce(0, +) - 48 - 16 * CGFloat(fixed.count))) }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                // Lamp's icons carry their own margin, so one fills a larger frame to sit like the plain icon did.
                Image(nsImage: icon ?? NSWorkspace.shared.icon(for: .applicationBundle)).resizable()
                    .frame(width: icon == nil ? 44 : 56, height: icon == nil ? 44 : 56)
                    .frame(width: 56, height: 56)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 2) {
                    // The name is the sender's: shown as written, never as formatting, and on one line whose
                    // end (the closing quote and the question mark) stays in view however long it is.
                    Text(verbatim: "Open “\(pending.package.name)”?").font(.title2.bold())
                        .lineLimit(1).truncationMode(.middle)
                    if pending.waited {
                        Text("You opened this during setup.").font(.callout).foregroundStyle(.secondary)
                    }
                    // The sender's words, so the line under them says whose they are.
                    if let description = pending.package.description {
                        Text(verbatim: description).font(.callout).lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 2)
                    }
                    Text(pending.package.description == nil
                         ? "Someone shared this wish with you. Lamp builds it and opens it here, where it can do anything an app you run can do."
                         : "Someone shared this wish with you, and the description above is theirs. Lamp builds it and opens it here, where it can do anything an app you run can do.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .task {
                icon = await Sharing.icon(of: pending.package)
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.name] = $0 }

            if let review {
              // What the app does scrolls when it's long (an app that does many things) or the screen is short;
              // the app's name above, and the verdict and buttons below, stay put, so the conclusion is never
              // off screen.
              ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                if !review.summary.isEmpty {
                    section("What it does") { Text(review.summary).fixedSize(horizontal: false, vertical: true) }
                }
                section("What it can do on your Mac") { capabilities(review) }
                if !pending.package.attachments.isEmpty {
                    section("Files the app uses") {
                        Text(pending.package.attachments.map(\.lastPathComponent).joined(separator: ", "))
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                if !review.concerns.isEmpty {
                    section("Concerns") {
                        ForEach(review.concerns, id: \.self) {
                            Label($0, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                        }
                    }
                }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
              }
              .frame(maxHeight: limit)
              .fixedSize(horizontal: false, vertical: true)   // no taller than its content, up to the limit
              VStack(alignment: .leading, spacing: 16) {
                verdict(review)
                if let line = review.reviewerLine {
                    Text(verbatim: line).font(.callout).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                }
                if let note = review.note {
                    // Why the check didn't run can be a provider's own words, of any length, and this part
                    // doesn't scroll: a few lines here, the whole of it on hover.
                    Text(note).font(.callout).foregroundStyle(.secondary).lineLimit(4)
                        .fixedSize(horizontal: false, vertical: true).help(note)
                }
                Text("Lamp's check is a guide, not a guarantee. Only open apps from people you trust.")
                    .font(.caption).foregroundStyle(.secondary)
              }
              .frame(maxWidth: .infinity, alignment: .leading)
              .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.verdict] = $0 }
            } else {
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking what this wish does…").foregroundStyle(.secondary)
                }
                .padding(.vertical, 20)
            }

            if let existing = pending.existing {
                // The buttons say what each does; this is what someone would worry about before choosing Update.
                Label {
                    Text(verbatim: "You already have this wish\(existing.name == pending.package.name ? "" : ", as “\(existing.name)”"). Updating keeps your data, and you can go back if you change your mind.")
                        .font(.callout).foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                } icon: {
                    Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.secondary)
                }
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.existing] = $0 }
            }

            HStack {
                Spacer()
                // Escape always cancels. Return builds only when the review is in and vouches for the app
                // (`ImportReview.opening`); anything less takes a deliberate click.
                Button("Cancel", role: .cancel) { store.cancelImport() }
                    .keyboardShortcut(.cancelAction)
                if pending.existing != nil {
                    // The app is already here: the file either becomes its next version or a second app.
                    // Either way its code runs, so both follow the same rule as opening does. Return is
                    // only ever Update: keeping both is the choice someone makes on purpose.
                    switch review?.opening {
                    case .byReturn:
                        Button("Keep Both") { store.confirmImport() }
                        Button("Update") { store.confirmUpdate() }
                            .keyboardShortcut(.defaultAction)
                    case .anyway:
                        Button("Keep Both Anyway", role: .destructive) { store.confirmImport() }
                        Button("Update Anyway", role: .destructive) { store.confirmUpdate() }
                    case .byClick, nil:
                        Button("Keep Both") { store.confirmImport() }
                            .disabled(review == nil)
                        Button("Update") { store.confirmUpdate() }
                            .disabled(review == nil)
                    }
                } else {
                    switch review?.opening {
                    case .byReturn:
                        Button("Build & Open") { store.confirmImport() }
                            .keyboardShortcut(.defaultAction)
                    case .anyway:
                        Button("Open Anyway", role: .destructive) { store.confirmImport() }
                    case .byClick, nil:
                        Button("Build & Open") { store.confirmImport() }
                            .disabled(review == nil)
                    }
                }
            }
            .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { fixed[.buttons] = $0 }
        }
        .padding(24)
        .frame(width: 500)
        .background(WindowFinder { sheet = $0; fit() })
        // The window can be moved with the sheet down, and the Dock can come and go.
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMoveNotification)) { _ in fit() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didChangeScreenParametersNotification)) { _ in fit() }
    }

    private func fit() {
        guard let window = sheet?.sheetParent, let screen = window.screen else { return }
        room = Self.room(below: window.frame.minY + window.contentLayoutRect.maxY, on: screen.visibleFrame)
    }

    /// The height a sheet can take when its top edge sits at `top` (screen coordinates, y up) on a screen
    /// whose usable area is `visible`: down to the bottom of that area, less a margin.
    nonisolated static func room(below top: CGFloat, on visible: CGRect) -> CGFloat {
        (top - visible.minY - 12).rounded(.down)
    }

    /// One row per kind of access the code was seen to use, worst first, like the permissions list in System
    /// Settings: an icon in a tinted square, the plain-words line, and a word on the right for anything beyond
    /// ordinary. What the AI noticed follows as a line of text: it mostly restates the rows in its own words,
    /// and now and then adds something the fixed checks have no pattern for.
    private func capabilities(_ review: ImportReview) -> some View {
        let found = review.detected.sorted { $0.level > $1.level }
        return VStack(alignment: .leading, spacing: 8) {
            VStack(spacing: 0) {
                if found.isEmpty {
                    // Says what the fixed checks found, not what the app can't do: the AI's line below, or
                    // a check that didn't run, may know more.
                    row(icon: "magnifyingglass", tint: .secondary, text: "Nothing found by Lamp's own checks.")
                }
                ForEach(found) { capability in
                    row(icon: capability.icon, tint: tint(for: capability.level), text: capability.label, badge: badge(for: capability.level))
                    if capability != found.last { Divider().padding(.leading, 44) }
                }
            }
            .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 10))
            if !review.capabilities.isEmpty {
                Text("The AI also noticed: " + review.capabilities.joined(separator: "; ") + ".")
                    .font(.callout).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private func row(icon: String, tint: Color, text: String, badge: String? = nil) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white)
                .frame(width: 26, height: 26)
                .background(tint, in: RoundedRectangle(cornerRadius: 6, style: .continuous))
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            if let badge {
                Text(badge).font(.caption.weight(.medium)).foregroundStyle(tint == .secondary ? Color.secondary : tint)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .accessibilityElement(children: .combine)
    }

    private func tint(for level: Sharing.Capability.Level) -> Color {
        switch level {
        case .ordinary: .blue
        case .powerful: .orange
        case .sensitive: .red
        }
    }

    private func badge(for level: Sharing.Capability.Level) -> String? {
        switch level {
        case .ordinary: nil
        case .powerful: "Powerful"
        case .sensitive: "Sensitive"
        }
    }

    private func section<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.headline)
            content()
        }
    }

    /// The one-line verdict: the AI's rating, lifted by what the code was seen to do.
    private func verdict(_ review: ImportReview) -> some View {
        let (text, color, icon): (String, Color, String) = switch review.verdict {
        case .risky: ("Looks risky. Don't open unless you trust the sender", .red, "xmark.octagon.fill")
        case .sensitive: ("Does sensitive things. Open only if you expected that", .red, "exclamationmark.octagon.fill")
        case .partlyChecked: ("Only partly checked. Open only if you trust the sender", .yellow, "exclamationmark.circle.fill")
        case .powerful: ("Powerful, check it's what you expect", .yellow, "exclamationmark.circle.fill")
        case .safe: ("Looks safe", .green, "checkmark.seal.fill")
        case .checkedOnThisMac: ("Nothing worrying found, but not by a check Lamp can vouch for", .secondary, "questionmark.circle")
        case .unchecked: ("Not checked by AI", .secondary, "questionmark.circle")
        }
        return Label(text, systemImage: icon)
            .font(.callout.bold())
            .foregroundStyle(color)
            .padding(.horizontal, 10).padding(.vertical, 6)
            .background(color.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Wishes to start from, under a new app's empty chat: what someone might want, in their own words, one from
/// each part of life (`Idea.Kind`), never an app's name. Choosing one puts the wish in the message box (it isn't sent) so the person can
/// make it theirs; what to make of it is the agent's to ask about. It opens on the six it's given; Show Me
/// Others pages on from there.
struct StarterIdeas: View {
    let choose: (String) -> Void
    @StateObject private var deck: IdeaDeck
    @State private var hovered: String?

    init(ideas: [Idea], choose: @escaping (String) -> Void) {
        self.choose = choose
        _deck = StateObject(wrappedValue: IdeaDeck(first: ideas))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Need inspiration?").font(.callout).foregroundStyle(.secondary)
                Spacer()
                Button(action: deck.more) {
                    HStack(spacing: 5) {
                        Image(systemName: IdeaDeck.moreSymbol)
                        Text("Show me others")
                    }
                    .font(.callout.weight(.medium))
                    .foregroundStyle(.secondary)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 8)], spacing: 8) {
                ForEach(Array(deck.ideas.enumerated()), id: \.element.id) { index, example in
                    Button { choose(example.blurb) } label: {
                        HStack(alignment: .top, spacing: 8) {
                            IdeaIcon(symbol: example.symbol, hue: example.hue, size: 22, lit: hovered == example.title)
                            // The wish alone. Every tile keeps room for three lines, so the grid doesn't change
                            // height when the ideas change (another page, another kind).
                            Text(example.blurb).font(.subheadline)
                                .lineLimit(3, reservesSpace: true)
                            Spacer(minLength: 0)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        // Just an outline, so the ideas stay quieter than what the user is writing.
                        .overlay(RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(hovered == example.title ? 0.2 : 0.1), lineWidth: 1))
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .onHover { hovered = $0 ? example.title : (hovered == example.title ? nil : hovered) }
                    .help("Puts this in the message box so you can change it before sending")
                    .transition(.asymmetric(
                        insertion: .opacity.combined(with: .scale(scale: 0.94)).animation(.spring(response: 0.5, dampingFraction: 0.8).delay(Double(index) * 0.04)),
                        removal: .opacity.animation(.easeOut(duration: 0.15))))
                }
            }
        }
        .frame(maxWidth: 600)
        .onAppear { deck.prefetch() }
    }
}

/// The Try On choices: the iPhone and iPad simulators and each of the person's paired phones. The simulator choice is the family the agent builds and looks at; a phone is where
/// Play puts the app.
private struct TryOnChoices: View {
    @EnvironmentObject private var store: Store
    let project: LampProject
    @State private var olderPhones: [PhoneTools.OlderPhone] = []

    var body: some View {
        if project.platform == .universal {
            // An app for both: this Mac is a place to open it too, beside the simulators and phones.
            Picker("This Mac", selection: Binding(get: { project.onIOS ? nil : Destination.mac },
                                                  set: { if $0 != nil { store.setMac(project) } })) {
                Label("My Mac", systemImage: "laptopcomputer").tag(Optional(Destination.mac))
            }
            .pickerStyle(.inline)
        }
        Picker("Simulator", selection: Binding(get: { project.device == nil && project.onIOS && project.simulator == nil ? project.family : nil },
                                               set: { if let family = $0 { store.setSimulator(project, family) } })) {
            Label("iPhone", systemImage: "iphone").tag(Optional(DeviceFamily.iphone))
            Label("iPad", systemImage: "ipad").tag(Optional(DeviceFamily.ipad))
        }
        .pickerStyle(.inline)
        // A particular model, for what only some have (a Dynamic Island, an iPad's size). Listed once the
        // simulators installed on this Mac are known.
        if !store.simulators.isEmpty {
            Menu("Choose Simulator") {
                Picker("Choose Simulator", selection: Binding(get: { project.device == nil && project.onIOS ? project.simulator : nil },
                                                              set: { udid in
                    if let choice = store.simulators.first(where: { $0.udid == udid }) { store.setSimulator(project, choice) }
                })) {
                    ForEach(store.simulators) { choice in
                        Label(choice.label, systemImage: choice.family == .ipad ? "ipad" : "iphone").tag(Optional(choice.udid))
                    }
                }
                .pickerStyle(.inline)
            }
        }
        do {
            let paired = store.devices.filter(\.paired), unpaired = store.devices.filter { !$0.paired }
            Picker("Your Devices", selection: Binding(get: { project.onIOS ? project.device : nil }, set: { chosen in
                store.choosePreparedDevice(project, chosen)
            })) {
                ForEach(paired) { device in
                    Label(device.name + (device.developerMode ? "" : " (Developer Mode is off)"), systemImage: device.family == .ipad ? "ipad" : "iphone")
                        .tag(Optional(device.udid))
                }
                if let chosen = project.device, !paired.contains(where: { $0.udid == chosen }) {
                    Label("Chosen phone (not paired)", systemImage: "iphone.slash").tag(Optional(chosen))
                }
            }
            .pickerStyle(.inline)
            // A phone that's plugged in but hasn't trusted this Mac yet: pairing puts the question on it.
            ForEach(unpaired) { device in
                Button(store.pairing.contains(device.udid) ? "Pairing with \(device.name)…" : "Pair \(device.name)…") {
                    store.pairDevice(device, for: project)
                }
                .disabled(store.pairing.contains(device.udid))
            }
            ForEach(olderPhones.filter { old in !store.devices.contains(where: { $0.udid == old.id }) }) { phone in
                Button("\(phone.name) (needs iOS \(PhoneTools.minimumIOS))…") {
                    PhoneSetup.shared.show(family: phone.family, phone: phone.id)
                }
            }
            if store.devices.isEmpty && olderPhones.isEmpty {
                Text("No iPhone or iPad found. Plug one in with a cable and unlock it, then look again.")
            }
        }
        Divider()
        Button("Check iPhone & iPad Setup…") { PhoneSetup.shared.show(family: project.family, phone: project.device) }
        Button("Look for Devices Again") { refresh() }
            .onAppear { refresh() }
    }

    private func refresh() {
        store.refreshDevices()
        store.refreshSimulators()
        Task { olderPhones = await PhoneTools.olderPhones() }
    }
}

extension Store {
    /// What the app's AI has cost, under its name in the toolbar ("AI: 3 calls · $0.02"); nil before it's used any.
    func usageSummary(_ project: LampProject) -> String? {
        guard let usage = usage[project.id], usage.calls > 0 else { return nil }
        return String(format: "AI: %d call%@ · $%.2f", usage.calls, usage.calls == 1 ? "" : "s", usage.cost)
    }
}
