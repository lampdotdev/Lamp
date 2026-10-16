import SwiftUI
import LampSidebarKit
import AppKit

/// Lamp Dev's gallery: each of the chat's cards in the states it can be in, drawn from made-up values instead of
/// an app and an agent. A card's rules (the same height from one question to the next, tiles that fill evenly,
/// what a card saved in an earlier shape still shows) are easy to break and slow to reach in a real chat, where
/// getting a card into a given state means a turn of the agent. Here every state is one click, at the chat's
/// width and the wand panel's, light and dark.
///
/// A card is listed here by the view that draws it from plain values (`AskCardView`, `ResultCardView`), the same
/// view the chat uses, so what's here is what people see. A new card, or a new state of one, gets an entry in
/// the same change.
enum Gallery {
    struct Entry: Identifiable {
        let group: String
        let name: String
        let make: () -> AnyView
        var id: String { group + "/" + name }
    }

    static let entries: [Entry] = askEntries + resultEntries + buildEntries + pointedEntries

    static var groups: [String] {
        entries.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
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
        ask("Answered by typing", Talk.Ask(layout: .steps, questions: [kind, when], typed: true), isOpen: false),
        // What a wish Lamp came with offers to change first (`Starters.card`): Lamp's card, worded as a starter.md is.
        ask("A starter's first changes", Talk.Ask(layout: .steps, questions: [Talk.Question(question: "Make Today yours", options: [
            option("Five priorities instead of three", "list.number"), option("Add a water counter", "drop"),
            option("Remind me to plan at 8", "bell"),
        ], detail: "Today came with Lamp as an example, and it's yours to change. Try one of these, or describe your own.")],
        offer: true)),
    ]

    private static func ask(_ name: String, _ ask: Talk.Ask, isOpen: Bool = true) -> Entry {
        Entry(group: "Ask card", name: name) { AnyView(LiveAsk(ask: ask, isOpen: isOpen)) }
    }

    // MARK: Result

    private static let resultEntries: [Entry] = [
        result("New app", Talk.Result(summary: "Your habit tracker is ready to try.", guesses: [])),
        result("Change", Talk.Result(summary: "Reminders now come at the time you pick.", guesses: [])),
        result("New app, ready", Talk.Result(summary: "A week of habits, with a streak beside each.", guesses: [],
                                             status: "Habit Tracker is ready")),
        result("Change, updated in place", Talk.Result(summary: "Added a weekly chart under your habits.", guesses: [],
                                                       status: "Habit Tracker is updated")),
        result("Latest change, with Undo", Talk.Result(summary: "Watering entries can now include an amount.", guesses: []), undo: true),
        result("Saved with what's new", Talk.Result(summary: "Added streaks and a dark look.", guesses: [], news: [
            Talk.News(what: "Streaks", place: "beside each habit"), Talk.News(what: "Dark look", place: "View menu"),
        ])),
        result("Saved with a guess turned", Talk.Result(summary: "Your habit tracker is ready to try.", guesses: [
            Talk.Guess(guess: "Habits reset at midnight", instead: "Reset at 4 am instead", request: "Reset habits at 4 am"),
        ], switched: [0])),
    ]

    private static func result(_ name: String, _ result: Talk.Result, undo: Bool = false) -> Entry {
        Entry(group: "Result card", name: name) {
            AnyView(VStack(spacing: 0) {
                ResultCardView(result: result)
                // Undo Last Change goes under the latest change, as the chat puts it (`UndoOffer`).
                if undo { ChatLook.UndoChange {}.padding(.top, 12) }
            })
        }
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
    let ask: Talk.Ask
    let isOpen: Bool
    @State private var progress = AskProgress()
    @State private var sent: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            AskCardView(ask: ask, isOpen: isOpen, progress: $progress) { sent = $0 }
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
