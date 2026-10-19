import SwiftUI
import LampSidebarKit
import AppKit

/// Lamp Dev's gallery: each of the chat's cards in the states it can be in, drawn from made-up values instead of
/// an app and an agent. A card's rules (the same height from one question to the next, tiles that fill evenly,
/// what a card saved in an earlier shape still shows) are easy to break and slow to reach in a real chat, where
/// getting a card into a given state means a turn of the agent. Here every state is one click, at the chat's
/// width and the wand panel's, light and dark.
///
/// A card is listed here by the view that draws it from plain values (`AskCardView`), the same
/// view the chat uses, so what's here is what people see. A new card, or a new state of one, gets an entry in
/// the same change.
enum Gallery {
    struct Entry: Identifiable {
        let group: String
        let name: String
        let make: () -> AnyView
        var id: String { group + "/" + name }
    }

    static let entries: [Entry] = chatEntries + askEntries + buildEntries + activityEntries + progressEntries + pointedEntries

    static var groups: [String] {
        entries.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Chat

    /// Whole chats, drawn by the chat's own `Transcript`: every kind of line one after another, so a line set in
    /// or sized unlike the rest shows against its neighbours.
    private static let chatEntries: [Entry] = [
        chat("A finished chat", finishedChat, undo: true),
        // The first request, its steps so far, and the progress line under them.
        chat("A turn going", Array(finishedChat.prefix(6)), activity: "Thinking"),
        chat("A clicked answer", [LogLine(kind: .user, text: "make a habit tracker"),
                                  LogLine(kind: .ask, text: "", ask: Talk.Ask(layout: .steps, questions: [kind, when], answers: ["Habits", "Morning"])),
                                  LogLine(kind: .agent, text: "I'll make a habit tracker that reminds you each morning.")],
             activity: "Working on the interface"),
    ]

    private static let finishedChat: [LogLine] = [
        LogLine(kind: .user, text: "make the design more modern"),
        LogLine(kind: .agent, text: "I'll give Today and Week a cleaner look."),
        LogLine(kind: .tool, text: "Read Sources/TodayView.swift"),
        LogLine(kind: .tool, text: "Edit Sources/TodayView.swift"),
        LogLine(kind: .tool, text: "Edit Sources/WeekView.swift"),
        LogLine(kind: .status, text: "Ran: swift build"),
        LogLine(kind: .status, text: "Building…"),
        LogLine(kind: .noted, text: "", noted: NoteReceipt(about: "you", before: Memory.Notes(),
            after: Memory.Notes(summary: "Likes a clean look", text: "- Prefers a clean, modern look (system font, borderless white cards, soft shadows)"))),
        LogLine(kind: .status, text: "Today is ready"),
        LogLine(kind: .agent, text: "Today and Week now have a cleaner, modern look: a soft gray background, borderless white cards and the system font in bold.\n\nIf you'd rather go back, the old look is saved as \"Paper planner look\"."),
        LogLine(kind: .summary, text: "Worked for 3m 14s · $0.31"),
        LogLine(kind: .user, text: "add some color"),
        LogLine(kind: .agent, text: "I'll add color to the cards and the week."),
        LogLine(kind: .tool, text: "Edit Sources/Theme.swift"),
        LogLine(kind: .status, text: "Building…"),
        LogLine(kind: .noted, text: "", noted: NoteReceipt(about: "you", before: Memory.Notes(summary: "x", text: "- Prefers a clean look"),
            after: Memory.Notes(summary: "x", text: "- Prefers a clean look\n- Likes color: a cheerful palette with colored accents, not plain gray"), undone: true)),
        LogLine(kind: .error, text: "The widget didn't build, so it still has the old colors."),
        LogLine(kind: .status, text: "Today is ready"),
        LogLine(kind: .agent, text: "The app is more colorful now. Each card's heading has a colored icon, and each of the three priorities has its own color."),
        LogLine(kind: .summary, text: "Worked for 1m 11s · $0.12"),
    ]

    private static func chat(_ name: String, _ lines: [LogLine], undo: Bool = false, activity: String? = nil) -> Entry {
        Entry(group: "Chat", name: name) {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                Transcript(lines: lines, dir: URL(fileURLWithPath: "/nonexistent"), busy: activity != nil, progressShown: activity != nil)
                if let activity { ChatLook.ActivityLine(activity, started: .now.addingTimeInterval(-7)).padding(.top, 12) }
                if undo { ChatLook.UndoChange {}.padding(.top, 12) }
            })
        }
    }

    // MARK: Ask

    private static func option(_ title: String, _ symbol: String? = nil) -> Talk.Option {
        Talk.Option(title: title, symbol: symbol)
    }

    private static let kind = Talk.Question(question: "What kind of tracker?", options: [
        option("Habits", "checkmark.circle"), option("Workouts", "figure.run"), option("Spending", "creditcard"),
    ])
    private static let when = Talk.Question(question: "When should it remind you each day?", options: [
        option("Morning", "sunrise"), option("Evening", "moon"), option("Never", "bell.slash"),
    ])
    private static let share = Talk.Question(question: "Share with anyone?", options: [
        option("Just me"), option("My family"),
    ])
    private static let four = Talk.Question(question: "Where will you use it most?", options: [
        option("At my desk", "desktopcomputer"), option("On the go", "iphone"),
        option("In the kitchen", "fork.knife"), option("Everywhere", "globe"),
    ])
    /// Words too long to sit four to a row in the wand's panel: the tiles go two by two, or one under another.
    private static let longWords = Talk.Question(question: "Which languages?", options: [
        option("Internationalization", "globe"), option("Accessibility", "accessibility"),
        option("Localization", "character.book.closed"), option("Documentation", "doc.text"),
    ])

    private static let askEntries: [Entry] = [
        ask("One question", Talk.Ask(layout: .steps, questions: [kind])),
        ask("Steps, three questions", Talk.Ask(layout: .steps, questions: [kind, when, share])),
        ask("Steps, four answers", Talk.Ask(layout: .steps, questions: [four])),
        ask("Steps, long words", Talk.Ask(layout: .steps, questions: [longWords, share])),
        ask("Together", Talk.Ask(layout: .together, questions: [kind, when, share])),
        ask("Answered by clicking", Talk.Ask(layout: .steps, questions: [kind, when], answers: ["Habits", Talk.youDecide]), isOpen: false),
        ask("Answered, waiting in line", Talk.Ask(layout: .steps, questions: [kind, when], answers: ["Habits", Talk.youDecide]),
            isOpen: false, waiting: .inLine),
        ask("Answered, waiting for setup", Talk.Ask(layout: .steps, questions: [kind, when], answers: ["Habits", Talk.youDecide]),
            isOpen: false, waiting: .forSetup),
        ask("Answered by typing", Talk.Ask(layout: .steps, questions: [kind, when], typed: true), isOpen: false),
        // What a wish Lamp came with offers to change first (`Starters.card`): Lamp's card, worded as a starter.md is.
        ask("A starter's first changes", Talk.Ask(layout: .steps, questions: [Talk.Question(question: "Make Today yours", options: [
            option("Five priorities instead of three", "list.number"), option("Add a water counter", "drop"),
            option("Remind me to plan at 8", "bell"),
        ], detail: "Today came with Lamp as an example, and it's yours to change. Try one of these, or describe your own.")],
        offer: true)),
    ]

    private static func ask(_ name: String, _ ask: Talk.Ask, isOpen: Bool = true, waiting: LiveAsk.Waiting? = nil) -> Entry {
        Entry(group: "Ask card", name: name) { AnyView(LiveAsk(ask: ask, isOpen: isOpen, waiting: waiting)) }
    }

    // MARK: Build

    private static let buildEntries: [Entry] = [
        build("Working on its plan") {
            $0.activity = "Working on the interface"
            $0.plan = [PlanPart(id: 0, title: "Type in the bill", done: true, files: ["BillField.swift"]),
                       PlanPart(id: 1, title: "Pick a tip percent", done: false, files: ["TipPicker.swift"]),
                       PlanPart(id: 2, title: "See the tip and the total", done: false, files: ["Totals.swift"])]
            $0.files = ["BillField.swift"]
            $0.currentFile = "TipPicker.swift"
        },
        build("Ready") { $0.finish(worked: true) },
        build("Didn't finish") { $0.finish(worked: false) },
        build("Asking first") { $0.wait() },
    ]

    private static func build(_ name: String, _ change: @escaping (inout TurnProgress) -> Void) -> Entry {
        Entry(group: "Build card", name: name) {
            var progress = TurnProgress(newApp: true)
            change(&progress)
            return AnyView(BuildCardView(title: "Tip Calculator", name: "Tip Calculator", iconReady: false, progress: progress) {
                BlueprintIcon(letter: "T", size: 44)
            })
        }
    }

    // MARK: Activity

    /// What a turn says it's doing as the wait goes on (`Activity`): the build card and the line under a change, fed
    /// the same activity and clock, at moments of a long think and a long build, and under the agent's progress lines.
    private static let activityEntries: [Entry] = [
        activity("Thinking, just begun", Activity.thinking, waited: 1),
        activity("Thinking, 25 seconds", Activity.thinking, waited: 25),
        activity("Thinking, 70 seconds", Activity.thinking, waited: 70),
        activity("Thinking, 3 minutes", Activity.thinking, waited: 200),
        activity("A named step", "Working on the interface", waited: 40),
        activity("Building, 45 seconds", "Building…", waited: 45),
        activity("Building, 2 minutes", "Building…", waited: 120),
        cover("Cover, building", "Building…", waited: 12),
        cover("Cover, the turn over", nil, waited: 0),
        // Commands the agent named, a few under one name, and one it didn't: as the steps show while a turn goes on
        // and opened under "Worked for…".
        Entry(group: "Activity", name: "Steps the agent named") {
            AnyView(VStack(alignment: .leading, spacing: 4) {
                ChatLook.RanCommand("cat .lamp/starter.md\ncat Sources/App.swift Sources/Model.swift\ncat Sources/ShelfView.swift",
                                    said: "Reading how the shelf works")
                ChatLook.RanCommand("./build.sh", said: "Checking it builds")
                ChatLook.RanCommand("ls Assets")
                ChatLook.ActivityLine("Checking it builds", started: Date().addingTimeInterval(-48),
                                      since: Date().addingTimeInterval(-6)).padding(.top, 8)
            })
        },
        Entry(group: "Activity", name: "Under the agent's progress lines") {
            let started = Date().addingTimeInterval(-95)
            return AnyView(VStack(alignment: .leading, spacing: 12) {
                ChatLook.AgentText("The week's columns are in. Now the tasks in them.")
                ChatLook.AgentText("Tasks show up. Now dragging them between days.")
                ChatLook.ActivityLine(Activity.thinking, started: started, since: Date().addingTimeInterval(-25))
            })
        },
    ]

    /// The cover while the app reopens, on a starter's picture of its window.
    private static func cover(_ name: String, _ activity: String?, waited: TimeInterval) -> Entry {
        Entry(group: "Activity", name: name) {
            var progress = TurnProgress(newApp: false)
            progress.started = Date().addingTimeInterval(-waited - 20)
            if let activity { progress.activity = activity }
            progress.activitySince = Date().addingTimeInterval(-waited)
            if activity == nil { progress.finish(worked: true) }
            let picture = Starters.folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("countdowns/preview.png")) }
                ?? NSImage(size: NSSize(width: 340, height: 282))
            return AnyView(CoverView(image: picture) { CoverNote(progress: progress) }
                .aspectRatio(picture.size, contentMode: .fit))
        }
    }

    private static func activity(_ name: String, _ activity: String, waited: TimeInterval) -> Entry {
        Entry(group: "Activity", name: name) {
            var progress = TurnProgress(newApp: true)
            progress.activity = activity
            progress.started = Date().addingTimeInterval(-waited)
            progress.activitySince = progress.started
            progress.plan = [PlanPart(id: 0, title: "Add a countdown", done: false),
                             PlanPart(id: 1, title: "See the days left at a glance", done: false)]
            return AnyView(VStack(alignment: .leading, spacing: 16) {
                BuildCardView(title: "Countdowns", name: "Countdowns", iconReady: false, progress: progress) {
                    BlueprintIcon(letter: "C", size: 44)
                }
                ChatLook.ActivityLine(progress.activity, started: progress.started, since: progress.activitySince)
            })
        }
    }

    // MARK: Progress

    /// The agent's lines on how the work is going: messages while its turn goes on, grey among its steps once it's
    /// over (as "Worked for…" shows them opened).
    private static let progressEntries: [Entry] = [
        Entry(group: "Progress", name: "Among a finished turn's steps") {
            AnyView(VStack(alignment: .leading, spacing: 4) {
                ChatLook.ProgressLine("The week's columns are in. Now the tasks in them.")
                ChatLook.StatusLine("Ran: swift build", running: false)
                ChatLook.ProgressLine("Tasks show up. Now dragging them between days, and a few finishing touches.")
            })
        },
    ]

    // MARK: Pointed at

    private static let pointedEntries: [Entry] = [
        pointed("In the message box", detail: "Kitchen basil", typed: "Let me add how much water, too."),
        pointed("In the message box, nothing typed yet", detail: "Kitchen basil", typed: ""),
        pointed("In the message box, app closed", detail: "Kitchen basil", typed: "Let me add how much water, too.", canChooseAgain: false),
        pointed("In the message box, a long name", detail: "Weekly watering schedule for the balcony planters",
                typed: "Make this bigger.", title: "Mark every plant on the balcony as watered today button"),
        pointed("An area", detail: nil, typed: "Put a photo of the plant here.", title: "Top left area"),
        Entry(group: "Pointed at", name: "Sent") {
            AnyView(ChatLook.UserRow(text: "Let me add how much water, too.", busy: false, goBack: nil, sendAgain: {}, isLatest: true) {
                ChatLook.PointedPill(title: "Watered button", detail: "Kitchen basil", preview: {})
            })
        },
    ]

    private static func pointed(_ name: String, detail: String?, typed: String, title: String = "Watered button",
                                canChooseAgain: Bool = true) -> Entry {
        Entry(group: "Pointed at", name: name) {
            AnyView(ChatLook.MessageBar(busy: false, canSend: true, attachHelp: "", attach: {}, send: {}, stop: {}, focus: {}) {
                Text(typed.isEmpty ? ChatLook.placeholder(busy: false, empty: false) : typed)
                    .foregroundStyle(typed.isEmpty ? .tertiary : .primary)
                    .frame(maxWidth: .infinity, minHeight: Composer.lineHeight, alignment: .leading)
                    .padding(.leading, 5)
            } above: {
                ChatLook.PointedPill(title: title, detail: detail, chooseAgain: canChooseAgain ? {} : nil, remove: {})
                    .padding(.top, 4)
            })
        }
    }
}

/// An ask card that can be clicked through: it keeps its own answers, and shows what it would have sent.
private struct LiveAsk: View {
    enum Waiting { case inLine, forSetup }
    let ask: Talk.Ask
    let isOpen: Bool
    var waiting: Waiting?
    @State private var progress = AskProgress()
    @State private var sent: [String]?
    @State private var takenBack = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Taken back, the card opens again, as in the chat.
            AskCardView(ask: ask, isOpen: isOpen || takenBack, progress: $progress,
                        waiting: takenBack ? nil : waiting.map { AskWaiting(forSetup: $0 == .forSetup) { takenBack = true } }) { sent = $0 }
            if let sent {
                HStack {
                    Text("Sent: " + sent.joined(separator: " · ")).font(.callout).foregroundStyle(.secondary)
                    Button("Again") { progress = AskProgress(); self.sent = nil }
                }
            }
        }
    }
}

struct GalleryCommand: View {
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if Edition.isDev {
            Button("Gallery") { openWindow(id: "gallery") }
                .keyboardShortcut("g", modifiers: [.command, .option, .shift])
        }
    }
}

struct GalleryScene: Scene {
    var body: some Scene {
        Window("Gallery", id: "gallery") {
            GalleryView()
        }
        .defaultSize(width: 1000, height: 700)
        .commandsRemoved()   // listed in the Window menu by `GalleryCommand`, only in Lamp Dev
    }
}

private struct GalleryView: View {
    /// The widths a card is drawn at: the chat in Lamp's window (cards stop at 620), and the wand's panel beside
    /// an app at its narrowest.
    enum Width: String, CaseIterable, Identifiable {
        case chat = "Chat", wand = "Wand Panel"
        var id: Self { self }
        var points: CGFloat { self == .chat ? 680 : 280 }
    }

    enum Look: String, CaseIterable, Identifiable {
        case system = "System", light = "Light", dark = "Dark"
        var id: Self { self }
        var scheme: ColorScheme? { self == .light ? .light : self == .dark ? .dark : nil }
    }

    @AppStorage("galleryEntry") private var selection = Gallery.entries[0].id
    @AppStorage("galleryWidth") private var width = Width.chat
    @AppStorage("galleryLook") private var look = Look.system

    var body: some View {
        NavigationSplitView {
            List(selection: Binding(get: { selection }, set: { if let id = $0 { selection = id } })) {
                ForEach(Gallery.groups, id: \.self) { group in
                    Section(group) {
                        ForEach(Gallery.entries.filter { $0.group == group }) { entry in
                            Text(entry.name).tag(entry.id)
                        }
                    }
                }
            }
            .navigationSplitViewColumnWidth(min: 200, ideal: 240)
        } detail: {
            ScrollView {
                if let entry = Gallery.entries.first(where: { $0.id == selection }) {
                    entry.make()
                        // A fresh card for each entry and width, so answers clicked in one don't carry over.
                        .id(entry.id + width.rawValue)
                        .padding(20)
                        .frame(width: width.points)
                        .background(Color(nsColor: .windowBackgroundColor))
                        .overlay(Rectangle().strokeBorder(.quaternary, style: StrokeStyle(lineWidth: 1, dash: [4])))
                        .padding(30)
                        .frame(maxWidth: .infinity)
                }
            }
            .toolbar {
                Picker("Width", selection: $width) {
                    ForEach(Width.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                Picker("Appearance", selection: $look) {
                    ForEach(Look.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
            }
        }
        .preferredColorScheme(look.scheme)
    }
}
