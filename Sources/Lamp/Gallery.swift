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
        let make: @MainActor () -> AnyView
        var id: String { group + "/" + name }
    }

    static let entries: [Entry] = chatEntries + screenEntries + askEntries + approvalEntries + buildEntries + activityEntries + progressEntries + pointedEntries + importEntries + wishLinkEntries + publishEntries + transitionEntries + deviceEntries

    static var groups: [String] {
        entries.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Chat

    /// Whole chats, drawn by the chat's own `Transcript`: every kind of line one after another, so a line set in
    /// or sized unlike the rest shows against its neighbours.
    private static let chatEntries: [Entry] = [
        chat("A finished chat", finishedChat),
        // The first request and what the agent said; its steps so far are in the line under them, which opens to them.
        chat("A turn going", Array(finishedChat.prefix(6)), activity: "Thinking"),
        chat("A clicked answer", [LogLine(kind: .user, text: "make a habit tracker"),
                                  LogLine(kind: .ask, text: "", ask: Talk.Ask(layout: .steps, questions: [kind, when], answers: ["Habits", "Morning"])),
                                  LogLine(kind: .agent, text: "I'll make a habit tracker that reminds you each morning.")],
             activity: "Working on the interface"),
        // What the agent said and did in the order it happened: the steps before each message stay above it, and
        // only the steps since the latest are in the line at the bottom.
        chat("Steps between messages", Array(beerTurn.dropLast(3)), activity: "Putting the pieces together"),
        // Over, each stretch folds where it came; the one before the answer is "Worked for…".
        chat("Steps between messages, over", beerTurn),
        // Over, and each fold titled by the small model after the turn, with how long its steps took.
        chat("Steps between messages, titled", titledBeerTurn),
        // An answer with every kind of markdown block: headings, a table, lists, a quote, a rule and code.
        chat("A reply with markdown", [
            LogLine(kind: .user, text: "which files are the biggest?"),
            LogLine(kind: .agent, text: """
            ## Biggest files

            | Lines | File |
            |------:|------|
            | 412 | `TodayView.swift` |
            | 96 | `Theme.swift` |
            | 58 | `HabitStore.swift` |

            - **Today** draws every card itself
              - its week strip too
            - *Theme* holds the colors

            1. Split the week strip out
            2. Then the cards

            > Splitting Today would make
            > changes to it quicker.

            ---

            ```
            swift build
            ```
            """),
        ]),
    ]

    /// What only some chats show: a new wish's intro, Apple's tools installing, the bar's Play, Stop and Try On for a wish
    /// that isn't a Mac window beside the chat, a setup card's header and its sheet, Agent Details' output, and a phone
    /// that didn't take the app.
    private static let screenEntries: [Entry] = [
        screen("A new wish", group: "Chat screen", []) { state in
            state.toolbar = nil
            state.intro = SidebarIntro(icon: nil, name: nil, namePrompt: "", line: introLine, ideas: ideas, canRename: true)
        },
        screen("A wish from the site", group: "Chat screen", []) { state in
            state.toolbar = nil
            state.intro = SidebarIntro(icon: nil, name: "", namePrompt: "A shelf for my hot sauces", line: "Here's your wish. Change anything you like.",
                                       ideas: [], canRename: true)
            state.draft = "A shelf for my hot sauces, with how hot each one is and where I bought it."
            state.draftVersion = 1
        },
        screen("Named, nothing asked yet", group: "Chat screen", []) { state in
            state.toolbar = nil
            state.intro = SidebarIntro(icon: nil, name: "Today", namePrompt: "Today", line: "Describe what Today should do. Lamp builds it and opens it for you.",
                                       ideas: ideas, canRename: true)
        },
        screen("Apple's tools installing", group: "Chat screen", Array(finishedChat.prefix(1))) { state in
            state.banner = SidebarBanner(text: "Installing Apple's app-building tools. Anything you ask for starts as soon as they're in.",
                                         button: "Show Installer")
            state.queued = [SidebarQueued(id: UUID(), text: "make the design more modern", attachments: [])]
            state.waitingForSetup = true
            state.lines = []
        },
        screen("An iPhone app, closed", group: "Chat screen", Array(finishedChat.prefix(11))) { state in
            state.toolbar?.play = SidebarPlay(open: false, enabled: true, help: "Use Today")
            state.tryOn = phoneTryOn
        },
        screen("An iPhone app, open", group: "Chat screen", Array(finishedChat.prefix(11))) { state in
            state.toolbar?.play = SidebarPlay(open: true, enabled: true, help: "Quit Today")
            state.tryOn = phoneTryOn
        },
        screen("A setup card", group: "Chat screen", [
            LogLine(kind: .user, text: "add a picture of each plant"),
            LogLine(kind: .agent, text: "Each plant now has a spot for its picture."),
            LogLine(kind: .summary, text: "Worked for 1m 2s"),
        ]) { state in
            var card = SidebarLine(id: UUID(), kind: .offer, text: "Make pictures with AI", gap: 12)
            card.symbol = Capability.pictures.symbol
            card.status = "Today wants to make pictures, and nothing on this Mac makes them yet."
            card.button = "Set Up…"
            state.lines.append(card)
        },
        Entry(group: "Chat screen", name: "The setup sheet") {
            AnyView(SetupCard(offer: SetupOffer(capability: .pictures), reason: "Today wants to make pictures, and nothing on this Mac makes them yet.",
                              dir: wish.dir))
        },
        screen("Agent Details", group: "Chat screen", [
            LogLine(kind: .user, text: "add some color"),
            LogLine(kind: .tool, text: "Read Sources/Theme.swift"),
            LogLine(kind: .tool, text: "Edit Sources/Theme.swift"),
            LogLine(kind: .status, text: "Ran: swift build"),
            LogLine(kind: .detail, text: (1...20).map { "Compiling Today Theme.swift (\($0) of 20)" }.joined(separator: "\n")),
            LogLine(kind: .agent, text: "The cards have colored headings now."),
            LogLine(kind: .summary, text: "Worked for 41 s"),
        ], details: true),
        screen("A phone that didn't take it", group: "Chat screen", [
            LogLine(kind: .user, text: "put it on my phone"),
            LogLine(kind: .error, text: "Today couldn't go on the iPhone: it's locked. Unlock it, then try again.", retryPhone: "00008110-gallery"),
        ]),
        screen("Keeping it opening on the phone", group: "Chat screen", [
            LogLine(kind: .user, text: "put it on my phone"),
            LogLine(kind: .status, text: "Today is ready on the iPhone"),
            LogLine(kind: .keepOpening, text: ""),
        ]),
        screen("A full phone", group: "Chat screen", [
            LogLine(kind: .user, text: "put it on my phone"),
            LogLine(kind: .phoneSlot, text: "dev.lamp.app.gallery-older.abcde12345", retryPhone: "00008110-gallery"),
        ]),
        screen("A full phone, an app taken off", group: "Chat screen", [
            LogLine(kind: .user, text: "put it on my phone"),
            LogLine(kind: .phoneSlot, text: PhoneSlotLine.done + "dev.lamp.app.gallery-older.abcde12345", retryPhone: "00008110-gallery"),
            LogLine(kind: .status, text: "Building for the iPhone…"),
        ]),
        screen("A new team's copy beside the old one", group: "Chat screen", [
            LogLine(kind: .user, text: "put it on my phone"),
            LogLine(kind: .oldCopy, text: "dev.lamp.app.gallery.abcde12345", retryPhone: "00008110-gallery"),
            LogLine(kind: .status, text: "Today is ready on the iPhone"),
        ]),
        screen("The old team's copy, kept and removed", group: "Chat screen", [
            LogLine(kind: .oldCopy, text: OldCopyLine.kept + "dev.lamp.app.gallery.abcde12345", retryPhone: "00008110-gallery"),
            LogLine(kind: .oldCopy, text: OldCopyLine.removed + "dev.lamp.app.gallery.abcde12345", retryPhone: "00008110-gallery"),
        ]),
        screen("It stopped opening on the phone", group: "Chat screen", [
            LogLine(kind: .error, text: "Today on the iPhone stopped opening: Apple lets an app signed with your account open for a limited time, and Lamp couldn't put it back. Lamp can't reach the iPhone. Connect it to this Mac or join the same Wi‑Fi, unlock it, then click Retry.", retryPhone: "00008110-gallery"),
        ]),
    ]

    private static let introLine = "Say it in your own words: a chore to take off your hands, a habit to keep, a game to play. Lamp makes it for you."

    private static let ideas = [
        SidebarIdea(id: "dinner", symbol: "fork.knife", hue: 0.08, text: "Help me figure out what to make for dinner from what's in my fridge"),
        SidebarIdea(id: "plants", symbol: "leaf", hue: 0.33, text: "Remind me when each of my plants needs water"),
        SidebarIdea(id: "maze", symbol: "circle.grid.cross", hue: 0.6, text: "Make a marble maze I play by tilting my phone"),
        SidebarIdea(id: "budget", symbol: "creditcard", hue: 0.75, text: "Show me where my money went this month"),
    ]

    private static let phoneTryOn = SidebarTryOn(sections: [
        SidebarTryOn.Section(title: "Simulator", items: [
            SidebarTryOn.Item(id: "family:iphone", title: "iPhone", symbol: "iphone", checked: true, disabled: false),
            SidebarTryOn.Item(id: "family:ipad", title: "iPad", symbol: "ipad", checked: false, disabled: false),
        ]),
        SidebarTryOn.Section(title: nil, items: [SidebarTryOn.Item(id: "check:iphone", title: "Check iPhone & iPad Setup…", symbol: "checklist",
                                                                    checked: false, disabled: false)]),
    ], symbol: "iphone", current: "iPhone")

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

    private static func step(_ said: String) -> LogLine { LogLine(kind: .status, text: "Ran: true", said: said) }

    /// The same turn as it's logged now, each line timed, with the titles `StepTitles` gives its folds.
    private static var titledBeerTurn: [LogLine] {
        let start = Date.now.addingTimeInterval(-400)
        let seconds: [TimeInterval] = [0, 4, 9, 15, 22, 31, 70, 80, 120, 150, 230, 260, 300, 372, 373]
        var lines = beerTurn
        for index in lines.indices { lines[index].at = start.addingTimeInterval(seconds[min(index, seconds.count - 1)]) }
        lines[2].foldTitle = "Looked over the shelf, its screens and saved entries"
        lines[6].foldTitle = "Planned the taproom look and drew the icon"
        lines[10].foldTitle = "Set up tasting records and their settings"
        return lines
    }

    private static let beerTurn: [LogLine] = [
        LogLine(kind: .user, text: "Turn Hot Shelf into a beer tracker"),
        LogLine(kind: .agent, text: "I'll turn Hot Shelf into a beer journal, with brewery details and tasting notes."),
        step("Understanding the current shelf and its design"), step("Finding the shelf screens and saved entries"),
        step("Looking at your current shelf"),
        LogLine(kind: .progress, text: "First, a warm taproom look with shelves grouped by beer style."),
        step("Reading the shelf details for the beer conversion"), step("Preparing the taproom look and beer examples"),
        step("Designing the icon"),
        LogLine(kind: .agent, text: "The taproom look awaits Reload. Next, beer styles and tasting records."),
        step("Setting up what your app remembers"), step("Working on the settings"),
        LogLine(kind: .agent, text: "Hot Shelf is now a beer journal: shelves by style, with brewery and tasting notes."),
        LogLine(kind: .summary, text: "Worked for 6m 12s · $0.41"),
    ]

    private static func chat(_ name: String, _ lines: [LogLine], group: String = "Chat", activity: String? = nil) -> Entry {
        screen(name, group: group, lines, progress: activity.map { activity in
            var progress = TurnProgress(newApp: false)
            progress.activity = activity
            progress.started = .now.addingTimeInterval(-7)
            progress.activitySince = progress.started
            return progress
        })
    }

    /// The made-up wish the gallery's chats are for: a Mac app called Today, with no folder.
    static let wish = LampProject(id: "gallery-today", name: "Today", exe: "Today", dir: URL(fileURLWithPath: "/nonexistent"))

    /// The chat as Lamp makes it for a wish (`SidebarServer.lines`), from made-up lines and the turn going on, with the
    /// bar's buttons as a made Mac app has them.
    @MainActor static func state(_ lines: [LogLine], progress: TurnProgress? = nil, details: Bool = false) -> SidebarState {
        let busy = progress.map { $0.finished == nil } ?? false
        let shown = busy && Talk.open(in: lines) == nil ? progress : nil
        var state = SidebarState(app: wish.name, lines: SidebarServer.lines(lines, project: wish, busy: busy, progressShown: shown != nil,
                                                                             details: details, progress: progress),
                                 working: shown?.activity, workingSince: shown?.started, empty: lines.isEmpty, busy: busy,
                                 draft: "", draftVersion: 0, attachments: [])
        state.workingActivitySince = shown?.activitySince
        state.workingSteps = shown == nil ? nil : SidebarServer.liveSteps(lines, project: wish, details: details, doing: shown?.activity)
        state.toolbar = SidebarToolbar(canUndo: !lines.isEmpty, canShare: true, hasVersions: !lines.isEmpty, details: details, usage: nil)
        state.canDictate = true
        return state
    }

    /// A whole chat as people see it, beside an app or in Lamp's panel: the shared screen (`ChatScreen`), its bar and
    /// message box included, at the width picked and a chat's height.
    static func screen(_ name: String, group: String = "Chat", _ lines: [LogLine], progress: TurnProgress? = nil, details: Bool = false,
                       _ change: @escaping (inout SidebarState) -> Void = { _ in }) -> Entry {
        Entry(group: group, name: name) {
            var made = state(lines, progress: progress, details: details)
            change(&made)
            return AnyView(ChatScreen().environmentObject(GalleryChat(made) as ChatLink).frame(height: 640))
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
    /// Words too long to sit four to a row on a wide card: the tiles go one under another there too.
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
        ])],
        offer: true)),
        // Lamp's card before the agent changes one of the person's devices (`device_permission`): only theirs to answer.
        ask("A device of the person's", DevicePermissions.card(device: "Living Room TV", doing: "Press Home and open Netflix to check the buttons")),
        ask("A device of the person's, answered", {
            var card = DevicePermissions.card(device: "Living Room TV", doing: "Press Home and open Netflix to check the buttons")
            card.answers = [DevicePermissions.allowOnce]
            return card
        }(), isOpen: false),
    ]

    private static func ask(_ name: String, _ ask: Talk.Ask, isOpen: Bool = true, waiting: LiveAsk.Waiting? = nil) -> Entry {
        Entry(group: "Ask card", name: name) { AnyView(LiveAsk(ask: ask, isOpen: isOpen, waiting: waiting)) }
    }

    // MARK: Approval

    /// A step the agent won't take without the person (`ChatLook.ApprovalCard`), drawn where the chat has it: under
    /// the turn that asked, over the message box.
    private static let approvalEntries: [Entry] = [
        approval("Working out what it does", command: download, explanation: nil),
        approval("Low risk", command: "rm -rf build && swift build", explanation: rebuilds, why: settingAsks),
        approval("Medium risk", command: download, explanation: downloads),
        approval("High risk", command: upload, explanation: uploads),
        approval("Couldn't tell what it does", command: hidden, explanation: unknown, why: unsure),
        approval("A file outside the app", command: "read ~/Documents/Garden/watering.csv", title: "The agent wants a file outside this app's folder",
                 explanation: .init(summary: "Read ~/Documents/Garden/watering.csv", risk: "medium",
                                    why: "It's outside this app's folder, and what's read goes to the AI model."),
                 why: Store.whyAsked(file: true, flagged: nil)),
        howToDecide("How to Decide, medium risk", command: download, explanation: downloads),
        howToDecide("How to Decide, high risk", command: upload, explanation: uploads),
        howToDecide("How to Decide, couldn't tell", command: hidden, explanation: unknown, why: unsure),
        howToDecide("How to Decide, asked by the setting", command: "rm -rf build && swift build", explanation: rebuilds, why: settingAsks),
        howToDecide("How to Decide, a long command",
                    command: (1...14).map { "brew install --quiet tool-number-\($0) && echo installed \($0)" }.joined(separator: " && "),
                    explanation: .init(summary: "Installs fourteen command-line tools for the whole Mac.", risk: "medium", why: reaches)),
    ]

    /// Why Lamp asked, as `Store.whyAsked` says it: a check flagged the step, the checks couldn't be sure of it, or
    /// "Ask before running commands" is set to ask about every command.
    private static let flaggedAsk = Store.whyAsked(file: false, flagged: .reachesBeyond, always: false)
    private static let unsure = Store.whyAsked(file: false, flagged: nil, always: false)
    private static let settingAsks = Store.whyAsked(file: false, flagged: nil, always: true)

    private static let reaches = "It reaches beyond this app: other apps, the Mac's software, or something published."
    private static let download = "curl -L -o Data/trails.geojson https://example.org/hiking/trails.geojson"
    private static let upload = "curl -X POST -F file=@~/Documents/plants.csv https://example.org/upload"
    private static let hidden = "python3 -c \"$(echo aW1wb3J0IG9z | base64 -d)\""
    private static let rebuilds = ChatLook.Explanation(summary: "Clears out the old build and builds the app again.", risk: "low",
                                                       why: "It only changes files in this app's folder.")
    private static let downloads = ChatLook.Explanation(summary: "Downloads the hiking trails map so the app can show them.", risk: "medium", why: reaches)
    private static let uploads = ChatLook.Explanation(summary: "Uploads your plants list to a website.", risk: "high",
                                                      why: "It sends files or data from this Mac somewhere else.")
    private static let unknown = ChatLook.Explanation(summary: "Lamp couldn't work out what this does.", risk: "", why: "")

    /// The popover's content as it opens from the card, drawn on a popover's ground: the gallery can't open one by itself.
    private static func howToDecide(_ name: String, command: String, explanation: ChatLook.Explanation, why: String = flaggedAsk) -> Entry {
        Entry(group: "Approval", name: name) {
            AnyView(ChatLook.ApprovalHelp(command: command, explanation: explanation, request: trailsRequest, whyAsked: why, onAllowAll: {})
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10))
                .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .fixedSize())
        }
    }

    private static let trailsRequest = "Show the hiking trails near me on the map"

    private static func approval(_ name: String, command: String, title: String = "Can the agent do this?",
                                 explanation: ChatLook.Explanation?, why: String = flaggedAsk) -> Entry {
        var progress = TurnProgress(newApp: false)
        progress.activity = "Waiting for your OK"
        progress.started = .now.addingTimeInterval(-12)
        progress.activitySince = progress.started
        return screen(name, group: "Approval", [LogLine(kind: .user, text: trailsRequest),
                                                LogLine(kind: .agent, text: "I'll add a trails layer to the map."),
                                                LogLine(kind: .tool, text: "Read Sources/MapView.swift")], progress: progress) { state in
            state.approval = SidebarApproval(id: UUID(), title: title, command: command, explanation: explanation, request: trailsRequest,
                                             whyAsked: why)
        }
    }

    // MARK: Device setup

    /// A device's setup step drawn from its integration's data, in each shape a step can take, the approval a command
    /// on the device waits on, and the setup window around them.
    private static let deviceEntries: [Entry] = [
        step("Hands on the device, not tried yet", rokuMode, state: .waiting("Waiting for Living Room Roku…")),
        step("Typing a password", rokuPassword),
        step("This Mac's address and a code", frameAddress),
        step("A sign-in with the maker, checked by Lamp", frameSignIn, known: .init(how: .lamp, model: "QN50LS03B", version: "6.5")),
        step("Worked before, and the sign-in rejected", rokuPassword, known: .init(how: .people, model: "4850X", version: "14.0"),
             state: .failed("The device rejected the sign-in. Check the user name and password, then try again.")),
        Entry(group: "Device setup", name: "Approving a command on the device") {
            AnyView(DeviceCommandCard(approval: DeviceCommandApproval(action: IntegrationAction(ssh: .init(port: 9922, user: "prisoner",
                command: "luna-send-pub -n 1 luna://com.webos.appInstallService/dev/install '{\"id\":\"{appID}\"}'",
                explanation: "Installs your app on the TV from the package Lamp just copied there.")), device: "Bedroom TV"), allow: {}, deny: {}))
        },
        Entry(group: "Device setup", name: "Approving a downloaded tool") {
            AnyView(DeviceCommandCard(approval: DeviceCommandApproval(action: IntegrationAction(tool: .init(download: "https://example.org/frame-cli",
                sha256: String(repeating: "a", count: 64), arguments: ["push", "{package}"],
                explanation: "Sends the app to the photo frame the way its maker's own tool does.")), device: "Hallway frame"), allow: {}, deny: {}))
        },
        Entry(group: "Device setup", name: "The setup window") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id],
                                    content: DeviceStepCard.Content(step: rokuPassword, number: 2, of: 3, device: roku.name, values: [:], state: .idle),
                                    typed: .constant(""), approval: nil, act: {}, decide: { _ in }))
        },
        guideEntry("The setup window, Do It for Me offered", offer: "Lamp opens the developer screen; you set the password."),
        guideEntry("The setup window, Do It for Me under way",
                   guide: .init(lines: [.init(text: "Living Room Roku answers", state: .done), .init(text: "Opening the developer screen…", state: .doing)],
                                ask: "Choose Enable installer and restart.")),
        guideEntry("The setup window, Do It for Me waiting on the person",
                   guide: .init(lines: [.init(text: "Living Room Roku answers", state: .done), .init(text: "Asked Living Room Roku for its developer screen", state: .done)],
                                ask: "Agree to the license, then set a developer password. The Roku restarts; Lamp carries on once it's back.",
                                button: "It Didn't Restart", link: .init(title: "Roku's Developer Setup", url: URL(string: "https://developer.roku.com/")!))),
        guideEntry("The setup window, Do It for Me stopped",
                   guide: .init(lines: [.init(text: "Living Room Roku answers", state: .done)],
                                failure: "Living Room Roku isn't answering. Check it's on and on the same network as this Mac, then click Try Again.")),
        guideEntry("The setup window, Do It for Me handed back",
                   guide: .init(lines: [.init(text: "Living Room Roku is back on", state: .done), .init(text: "Developer mode is on", state: .done)],
                                ask: "Type the developer password you just set on the Roku."), handedBack: true, step: rokuPassword),
        Entry(group: "Device setup", name: "A device with a new certificate") {
            AnyView(DeviceReconnectCard(device: "XBOX", reconnect: {}))
        },
        Entry(group: "Device setup", name: "The setup window, the device's certificate changed") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in }, reconnect: {}))
        },
        Entry(group: "Device setup", name: "The setup window, set up") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in }, tryIt: {}))
        },
        Entry(group: "Device setup", name: "The setup window, a test run under way") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in },
                                    trial: [.init(id: "Make a test app", state: .passed), .init(id: "Put it on and open it", state: .passed),
                                            .init(id: "See its screen", state: .running), .init(id: "Press its keys", state: .waiting),
                                            .init(id: "Take it off", state: .waiting)], tryIt: {}, canTry: false))
        },
        Entry(group: "Device setup", name: "The setup window, a test run that failed") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in },
                                    trial: [.init(id: "Make a test app", state: .passed), .init(id: "Put it on and open it", state: .passed),
                                            .init(id: "Put it on again while it's open", state: .failed("The request timed out.")),
                                            .init(id: "Take it off", state: .skipped)], tryIt: {}))
        },
        Entry(group: "Device setup", name: "The setup window, a test run that passed") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in },
                                    trial: [.init(id: "Make a test app", state: .passed), .init(id: "Put it on and open it", state: .passed),
                                            .init(id: "Take it off", state: .passed)], tryIt: {}, worked: "Apps worked on 3900X, 15.3.4"))
        },
    ]

    /// The setup window with a step's Do It for Me: offered, under way, or ended, each from made-up values.
    private static func guideEntry(_ name: String, offer: String? = nil, guide: SetupGuideView.State? = nil, handedBack: Bool = false,
                                   step: Integration.Step = rokuMode) -> Entry {
        Entry(group: "Device setup", name: name) {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: step.id == rokuMode.id ? [] : [rokuMode.id],
                                    content: DeviceStepCard.Content(step: step, number: step.id == rokuMode.id ? 1 : 2, of: 3, device: roku.name, values: [:], state: .idle),
                                    typed: .constant(""), approval: nil, act: {}, decide: { _ in },
                                    guide: guide, handedBack: handedBack, offer: guide == nil ? offer : nil))
        }
    }

    private static func step(_ name: String, _ step: Integration.Step, known: Integration.Known? = nil, state: DeviceStepCard.State = .idle) -> Entry {
        var step = step
        if let known { step.known = known }
        return Entry(group: "Device setup", name: name) {
            AnyView(DeviceStepCard(content: DeviceStepCard.Content(step: step, number: 1, of: 3, device: "Living Room Roku",
                                                                   values: ["mac": "192.168.1.24", "read:pair": "4827"], state: state),
                                   typed: .constant(""), act: {}))
        }
    }

    private static let roku: Device = {
        var device = Device(id: "roku:X01", kind: .other, maker: "Roku", model: "Roku Ultra", modelID: "4850X", name: "Living Room Roku",
                            os: "Roku OS", osVersion: "14.0", reach: .network)
        device.integration = "roku"
        return device
    }()

    private static let infoCheck = Integration.Condition(http: Request(port: 8060, path: "/query/device-info"), xml: "developer-enabled", equals: "true")
    private static let rokuMode = Integration.Step(
        id: "developer-mode", title: "Turn on developer mode",
        lines: ["Press Home three times on the remote", "Then Up, Up, Right, Left, Right, Left, Right",
                "Choose Enable installer and restart", "Agree to the developer license"],
        accepts: [.softwareRisk], wait: true, check: [infoCheck],
        known: .init(how: .read, source: "https://developer.roku.com/docs/developer-program/getting-started/developer-setup.md"))
    private static let rokuPassword = Integration.Step(
        id: "password", title: "Give Lamp the developer password",
        lines: ["Type the password you set on the Roku"],
        field: .init(key: "password", label: "Developer password", secret: true),
        check: [Integration.Condition(http: Request(port: 80, path: "/", auth: .init(digest: true, user: "rokudev", password: "{field:password}")))],
        known: .init(how: .read))
    private static let rokuLook = Integration.Step(id: "look", title: "Let Lamp see the screen", check: [Integration.Condition(tcp: 80)])
    private static let frameAddress = Integration.Step(
        id: "pair", title: "Point the frame at this Mac",
        lines: ["Open Settings on the frame", "Choose Developer, then Host", "Type this Mac's address", "Scan the code with the frame's camera"],
        show: [.init(label: "This Mac", value: "{mac}"), .init(label: "Pairing code", value: "{read:pair}")], qr: "{mac}",
        wait: true, check: [Integration.Condition(tcp: 26101)], known: .init(how: .read))
    private static let frameSignIn = Integration.Step(
        id: "certificate", title: "Sign in to Samsung",
        lines: ["Sign in with your Samsung account", "Lamp makes the frame's permission for this Mac"],
        accepts: [.account],
        run: [IntegrationAction(vendorSignIn: .init(page: "https://account.samsung.com/accounts/TDC/signInGate?redirect={callback}"))],
        check: [Integration.Condition(signedIn: true)])

    // MARK: Build

    /// A new app's first build as its plan's chapters (`BuildChapters`), under the bar that says where it is, from the
    /// chat's own segments of made-up lines: before the plan, a part going on, asking first and once it's made.
    private static let buildEntries: [Entry] = [
        firstBuild("Before the plan", Array(tipBuild.prefix(4)), plan: []) { $0.sketch = ["Type in the bill", "Pick a tip"] },
        firstBuild("Asking first", tipAsk, plan: []) { $0.wait() },
        firstBuild("Part 2 of 3", Array(tipBuild.prefix(12)), plan: tipPlan) {
            $0.activity = "Working on the interface"
            $0.reached = 1
            $0.plan[0].done = true
        },
        firstBuild("Ready", tipBuild + [tipSummary, LogLine(kind: .status, text: "Tip Calculator is ready")], plan: tipPlan) {
            $0.chaptersClosed = true
            $0.finish(worked: true)
        },
    ]

    private static let tipPlan = [PlanPart(id: 0, title: "Type in the bill", done: false, files: ["BillField.swift"]),
                                  PlanPart(id: 1, title: "Pick a tip percent", done: false, files: ["TipPicker.swift"]),
                                  PlanPart(id: 2, title: "See the tip and the total", done: false, files: ["Totals.swift"])]

    private static func at(_ seconds: TimeInterval) -> Date { Date().addingTimeInterval(seconds - 300) }

    private static func line(_ kind: LogLine.Kind, _ text: String, part: Int?, at seconds: TimeInterval, said: String? = nil) -> LogLine {
        var line = LogLine(kind: kind, text: text, said: said, at: at(seconds))
        line.part = part
        return line
    }

    private static let tipAsk = [
        line(.user, "a tip calculator for dinners with friends", part: nil, at: 0),
        line(.agent, "One thing first, since it changes what I make.", part: nil, at: 6),
        LogLine(kind: .ask, text: "", ask: Talk.Ask(layout: .steps, questions: [Talk.Question(
            question: "Do you split the bill too?", options: [option("Just the tip", "percent"), option("Split it", "person.2"),
                                                          option(TalkCard.youDecide, "wand.and.stars")])])),
    ]

    private static let tipBuild = [
        line(.user, "a tip calculator for dinners with friends", part: nil, at: 0),
        line(.tool, "read App.swift", part: nil, at: 4),
        line(.tool, "plan", part: nil, at: 9),
        line(.progress, "Three parts: the bill, the tip, the totals. The bill first.", part: 0, at: 12),
        line(.tool, "write BillField.swift", part: 0, at: 20, said: "Making the bill field"),
        line(.tool, "edit App.swift", part: 0, at: 31, said: "Putting the field in the window"),
        line(.tool, "look_at_app", part: 0, at: 40, said: "Checking the bill field"),
        line(.status, "Building…", part: 0, at: 41),
        line(.progress, "The bill goes in. Next, picking the tip.", part: 1, at: 70),
        line(.tool, "write TipPicker.swift", part: 1, at: 80, said: "Adding the tip buttons"),
        line(.tool, "look_at_app", part: 1, at: 95, said: "Checking the tip buttons"),
        line(.status, "Building…", part: 1, at: 96),
        line(.progress, "Tips work. Now the totals.", part: 2, at: 130),
        line(.tool, "write Totals.swift", part: 2, at: 140, said: "Showing the tip and total"),
        line(.tool, "look_at_app", part: 2, at: 160, said: "Checking the totals"),
        line(.agent, "Tip Calculator is ready. Type the bill, pick a tip, and the total shows under it.", part: 2, at: 190),
    ]

    private static var tipSummary: LogLine {
        var summary = LogLine(kind: .summary, text: "Worked for 3m 12s", at: at(192))
        summary.plan = tipPlan.map(\.title)
        return summary
    }

    private static func firstBuild(_ name: String, _ lines: [LogLine], plan: [PlanPart],
                                   _ change: @escaping (inout TurnProgress) -> Void) -> Entry {
        var progress = TurnProgress(newApp: true)
        progress.plan = plan
        progress.started = at(0)
        progress.activitySince = progress.started
        change(&progress)
        return screen(name, group: "First build", lines, progress: progress)
    }

    // MARK: Activity

    /// What a turn says it's doing as the wait goes on (`Activity`): the first build's bar and the line under a change, fed
    /// the same activity and clock, at moments of a long think and a long build, and under the agent's progress lines.
    private static let activityEntries: [Entry] = [
        activity("Thinking, just begun", Activity.thinking, waited: 1),
        activity("Thinking, 25 seconds", Activity.thinking, waited: 25),
        activity("Thinking, 70 seconds", Activity.thinking, waited: 70),
        activity("Thinking, 3 minutes", Activity.thinking, waited: 200),
        activity("A named step", "Working on the interface", waited: 40),
        activity("Building, 45 seconds", "Building…", waited: 45),
        activity("Building, 2 minutes", "Building…", waited: 120),
        // A stage of a look, a few seconds in, well into the turn: the clock is the stage's.
        Entry(group: "Activity", name: "A look's stage") {
            AnyView(ChatLook.ActivityLine("Opening Countdowns…", started: Date().addingTimeInterval(-95),
                                          since: Date().addingTimeInterval(-4)))
        },
        // The one line a turn has while it goes on, under the steps done so far (a click folds them): commands the agent
        // named, a few under one name, and one it didn't; the one running is the line. "Worked for…", folded, opens to
        // the same rows once it's over.
        Entry(group: "Activity", name: "Steps the agent named") {
            AnyView(ChatLook.ActivityLine("Checking it builds", started: Date().addingTimeInterval(-48),
                                          since: Date().addingTimeInterval(-6), hasSteps: true) {
                ChatLook.RanCommand("cat .lamp/starter.md\ncat Sources/App.swift Sources/Model.swift\ncat Sources/ShelfView.swift",
                                    said: "Reading how the shelf works")
                ChatLook.RanCommand("ls Assets")
            })
        },
        // The steps as the chat gathers them from what was logged: file work Lamp named after a command (Codex's, by the
        // heading of its reasoning), logged before that command's own row (calls made together, the command still
        // running), is one step with it.
        Entry(group: "Activity", name: "File work before its command") {
            let logged = [LogLine(kind: .user, text: "Turn this into a beer tracker"),
                          LogLine(kind: .tool, text: "bash cat Sources/App.swift", said: "Reading how the shelf works"),
                          LogLine(kind: .status, text: "Ran: cat Sources/App.swift", said: "Reading how the shelf works"),
                          LogLine(kind: .tool, text: "bash grep -rn label Sources", said: "Reading how labels and pictures are found"),
                          LogLine(kind: .tool, text: "read Sources/LabelView.swift", said: "Reading how labels and pictures are found"),
                          LogLine(kind: .status, text: "Ran: grep -rn label Sources", said: "Reading how labels and pictures are found"),
                          LogLine(kind: .tool, text: "bash grep -rn hot Sources", said: "Finding every hot-sauce word and number"),
                          LogLine(kind: .status, text: "Ran: grep -rn hot Sources", said: "Finding every hot-sauce word and number")]
            let steps = ChatItem.live(LogLine.visible(logged, details: false), doing: Activity.thinking).steps
            return AnyView(ChatLook.ActivityLine("Mulling it over", started: Date().addingTimeInterval(-40),
                                                 hasSteps: true) { ChatLines(SidebarServer.stepLines(steps)) }
                .environmentObject(GalleryChat(nil) as ChatLink))
        },
        // Steps that were tried and didn't work, as a fold opens to them: a command that failed, the file
        // work after it in words of its own, and a change that failed.
        Entry(group: "Activity", name: "Steps that failed") {
            var shared = LogLine(kind: .status, text: "Ran: tailscale serve --bg 8080", said: "Share the page over the network")
            shared.failed = true
            var edit = LogLine(kind: .tool, text: "edit Sources/ShelfView.swift", said: "Adding the sort button")
            edit.failed = true
            let logged = [LogLine(kind: .user, text: "Let me open the shelf on my phone"),
                          LogLine(kind: .status, text: "Ran: python3 -m http.server 8080", said: "Start the page server"),
                          shared, LogLine(kind: .tool, text: "read Sources/App.swift"), edit,
                          LogLine(kind: .agent, text: "The page server is running, but sharing it didn't work.")]
            let steps = LogLine.visible(logged, details: false).filter(ChatItem.isStep)
            return AnyView(VStack(alignment: .leading, spacing: 4) { ChatLines(SidebarServer.stepLines(steps)) }
                .environmentObject(GalleryChat(nil) as ChatLink))
        },
        // A change waiting for Reload, under the answer that says so: the action line's symbol and words in the steps'
        // column, with "Worked for…" above.
        Entry(group: "Activity", name: "Reload under a change") {
            AnyView(VStack(alignment: .leading, spacing: 8) {
                ChatLook.AgentText("Once you press Reload, the rack scrolls to each new spice as you add it.")
                ChatLook.Worked("Worked for 54 s") { EmptyView() }
                ChatLook.ActionLine(symbol: "arrow.clockwise", text: ReloadLine.text("Hot Shelf"), button: "Reload", prominent: true) {}
            })
        },
        // Reload pressed while the agent is still at work on the app: it goes in once that's done.
        Entry(group: "Activity", name: "Reload, waiting for the request") {
            AnyView(ChatLook.ActionLine(symbol: "arrow.clockwise", text: ReloadLine.queued("Hot Shelf"), button: "Reload",
                                        disabled: true, prominent: true) {})
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

    private static func activity(_ name: String, _ activity: String, waited: TimeInterval) -> Entry {
        Entry(group: "Activity", name: name) {
            var progress = TurnProgress(newApp: true)
            progress.activity = activity
            progress.started = Date().addingTimeInterval(-waited)
            progress.activitySince = progress.started
            return AnyView(VStack(alignment: .leading, spacing: 16) {
                ChatLook.ActivityLine(progress.activity, started: progress.started, since: progress.activitySince)
            })
        }
    }

    // MARK: Progress

    /// The agent's lines on how the work is going: messages while its turn goes on, and still messages once it's
    /// over, with only its steps gathered into "Worked for…" under its answer.
    private static let progressEntries: [Entry] = [
        chat("After a finished turn", [
            LogLine(kind: .user, text: "add a week view"),
            LogLine(kind: .progress, text: "The week's columns are in. Now the tasks in them."),
            LogLine(kind: .tool, text: "Edit Sources/WeekView.swift"),
            LogLine(kind: .status, text: "Ran: swift build", said: "Checking it builds"),
            LogLine(kind: .progress, text: "Tasks show up. Now dragging them between days, and a few finishing touches."),
            LogLine(kind: .tool, text: "Edit Sources/WeekView.swift"),
            LogLine(kind: .status, text: "Today is ready"),
            LogLine(kind: .agent, text: "The week view is in: a column for each day, and tasks you can drag between them."),
            LogLine(kind: .summary, text: "Worked for 2m 40s · $0.21"),
        ], group: "Progress"),
    ]

    // MARK: Shared wish

    /// The review a shared wish opens with (`ImportReviewCard`), as the sheet draws it: its own width whichever
    /// width is picked, since it's only ever a sheet over Lamp's window, never in the wand's panel.
    private static let importEntries: [Entry] = [
        review("Checking", nil),
        review("Looks safe", ImportReview(summary: "Keeps a list of the plants on your balcony and reminds you when each needs water.",
                                          capabilities: ["Saves your plants and when you last watered them"], concerns: [],
                                          risk: .low, reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false), asked: true,
                                          detected: found("Connects to the internet")),
               app: "Plant Care", description: "Never forget to water the basil again."),
        review("Partly checked", ImportReview(
            summary: "A 3D driving game that builds real streets and buildings from map data for any place you search, starting in San Francisco, with cars, people, trains and street furniture.",
            capabilities: ["Downloads maps of the places you drive", "Remembers the places you searched"],
            concerns: [ImportReview.tooLarge], risk: .low, reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false),
            asked: true, detected: found("Uses the camera or microphone", "Connects to the internet"), partial: true),
               description: "A driving game through real streets anywhere in the world, starting in San Francisco."),
        review("Looks risky", ImportReview(
            summary: "Shows a daily quote, and also reads your browser's saved data and sends it to a website.",
            capabilities: ["Sends what it reads to a website"],
            concerns: ["Reads your browser's saved logins", "Sends them to a website it doesn't name", "Its description leaves this out"],
            risk: .high, reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false), asked: true,
            detected: found("Touches sensitive files (SSH keys, browser data, keychains)", "Connects to the internet")),
               app: "Morning Quote", description: "A quote to start each day."),
        review("Not checked by AI", ImportReview(summary: "", capabilities: [], concerns: [], asked: true,
                                                 detected: found("Runs other programs or shell commands", "Deletes files"),
                                                 note: "The check didn't run: OpenRouter said the key has no credit left.")),
        review("Checked on this Mac", ImportReview(summary: "Tracks how long you spend on each project and totals it by week.",
                                                   capabilities: [], concerns: [], risk: .low,
                                                   reviewer: ImportReview.Reviewer(name: "Qwen 3", onThisMac: true), asked: true,
                                                   detected: found("Listens for keyboard shortcuts in every app")),
               app: "Project Hours"),
        review("Already here", ImportReview(summary: "Keeps a list of the plants on your balcony and reminds you when each needs water.",
                                            capabilities: [], concerns: [], risk: .low,
                                            reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false), asked: true, detected: []),
               app: "Plant Care", existing: "Balcony Plants"),
        review("Android app", ImportReview(summary: "Counts your taps on one screen and remembers the count after closing.",
                                           capabilities: [], concerns: [], risk: .low,
                                           reviewer: ImportReview.Reviewer(name: "Sonnet", onThisMac: false), asked: true,
                                           detected: ["INTERNET", "POST_NOTIFICATIONS"].map(AndroidFiles.capability(for:))
                                               + [Sharing.Capability(label: "Builds in code from outside Lamp (retrofit)", icon: "shippingbox",
                                                                     level: .powerful, patterns: [])]),
               app: "Tap Count", android: true),
    ]

    private static func found(_ labels: String...) -> [Sharing.Capability] {
        labels.compactMap { label in Sharing.checklist.first { $0.label == label } }
    }

    private static func review(_ name: String, _ review: ImportReview?, app: String = "Drive Anywhere", description: String? = nil,
                               existing: String? = nil, android: Bool = false) -> Entry {
        Entry(group: "Shared wish", name: name) {
            AnyView(ImportReviewCard(name: app, description: description,
                                     icon: nil, review: review, existing: existing, cancel: {}, open: {}, update: {}, android: android)
                .background(Color(nsColor: .windowBackgroundColor), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .fixedSize())
        }
    }

    // MARK: Share Link

    /// The card that says what a wish's link will show, before and after it's shared, in Lamp's sheet and at the
    /// narrow width of the chat beside the app.
    private static let wishLinkEntries: [Entry] = [
        wishLink("New link"),
        wishLink("New link, picture left out", values: .init(name: "Disk Map", line: diskMapLine, words: diskMapWish, includePicture: false)),
        wishLink("New link, no picture", picture: false),
        wishLink("New link, nothing to take again", retake: false),
        wishLink("Sharing", stage: .sending),
        wishLink("Couldn't share", stage: .failed("Lamp couldn't reach lamp.dev. Try again in a moment.")),
        wishLink("Shared and copied", link: true, copied: true),
        wishLink("Shared, changed since", link: true, changed: true),
        wishLink("Beside the app", link: true, copied: true, width: nil),
        wishLink("Beside the app, new link", width: nil),
        wishLink("With the wish itself", values: .init(name: "Disk Map", line: diskMapLine, words: diskMapWish, includePicture: true, includeFile: true), canIncludeFile: true),
        wishLink("Beside the app, with the wish itself", values: .init(name: "Disk Map", line: diskMapLine, words: diskMapWish, includePicture: true, includeFile: true),
                 canIncludeFile: true, width: nil),
    ]

    private static let diskMapLine = "Shows where your disk space goes, as rings that fill in while it measures."
    private static let diskMapWish = "A Mac app that shows where my disk space goes, as rings that fill in while it measures. Clicking a ring opens that folder."

    private static func wishLink(_ name: String, values: WishLinkCard.Values? = nil, picture: Bool = true, retake: Bool = true,
                                 stage: WishLinkCard.Stage = .editing, link: Bool = false, copied: Bool = false,
                                 changed: Bool = false, canIncludeFile: Bool = false, width: CGFloat? = 480) -> Entry {
        Entry(group: "Share Link", name: name) {
            let folder = Starters.folder?.appendingPathComponent("diskmap")
            let card = WishLinkCard(
                icon: folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("icon/icon.png")) },
                picture: picture ? folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("preview.png")) } : nil,
                values: .constant(values ?? .init(name: "Disk Map", line: diskMapLine, words: diskMapWish, includePicture: picture)),
                limits: WishLink.cardLimits, link: link ? "https://lamp.dev/w/AyTkit4xCc" : nil, changed: !link || changed,
                stage: stage, copied: copied, retake: retake ? {} : nil, retaking: false, canIncludeFile: canIncludeFile,
                share: {}, copy: {}, stop: {}, close: {}, width: width)
            return AnyView(card
                .frame(width: width == nil ? 340 : nil)
                .background(width == nil ? AnyShapeStyle(ChatLook.paper) : AnyShapeStyle(Color(nsColor: .windowBackgroundColor)),
                            in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .fixedSize(horizontal: false, vertical: true))
        }
    }

    // MARK: Publish

    /// The card that says what a game's page will put up and where, from checking it to its being up, in the chat's
    /// place at its narrowest and widest.
    private static let publishEntries: [Entry] = [
        publish("Checking", stage: .preparing),
        publish("Needs GitHub's tool", stage: .needsGitHub(.install)),
        publish("Needs a sign-in", stage: .needsGitHub(.signIn)),
        publish("No licence", stage: .refused("New York can't be shared. It uses Found Code by someone, which came with no licence. It can still be used on this Mac.")),
        publish("Ready", stage: .ready),
        publish("Ready, share-alike", stage: .ready, notes: ["Engine is GPL-3.0-or-later, so this remix is too: anyone may share it on under the same licence.",
                                                             "2 pictures made with AI, marked as such."]),
        publish("Publishing", stage: .publishing("Waiting for GitHub to put it up…")),
        publish("Couldn't publish", stage: .failed("GitHub didn't take the page: the connection was lost.")),
        publish("Up", stage: .published, page: true),
        publish("Up and copied", stage: .published, page: true, copied: true),
        publish("Up, changed since", stage: .ready, page: true),
        publish("Up, wide", stage: .published, page: true, width: 480),
    ]

    private static func publish(_ name: String, stage: PublishCard.Stage, notes: [String] = [], page: Bool = false, copied: Bool = false,
                                width: CGFloat? = nil) -> Entry {
        Entry(group: "Publish", name: name) {
            let folder = Starters.folder?.appendingPathComponent("newyork")
            let ready = stage != .preparing
            let card = PublishCard(icon: folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("icon/icon.png")) }, name: "New York",
                                   stage: stage, repo: ready ? "someone/new-york" : nil, page: page ? "https://someone.github.io/new-york/" : nil,
                                   credit: "Based on Slop New York by Mr.doob",
                                   openInLamp: page ? "lamp.dev/w/AyTkit4xCc" : nil, notes: notes, size: ready ? "214 files · 12.1 MB" : nil,
                                   copied: copied, republish: page, canPublish: stage == .ready || { if case .failed = stage { true } else { false } }(), publish: {}, fix: {}, openPage: {}, copy: {}, close: {}, width: width)
            return AnyView(card
                .frame(width: width == nil ? 340 : nil)
                .background(AnyShapeStyle(ChatLook.paper), in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.quaternary))
                .shadow(color: .black.opacity(0.15), radius: 12, y: 4)
                .fixedSize(horizontal: false, vertical: true))
        }
    }

    // MARK: Transition

    /// The glow and the light are drawn by the app itself (`LampTransition` in LampSupport.swift). Their layers
    /// (`LampTransition.Look`) are compiled into Lamp too, so they're tried here over pictures of apps, and on a
    /// real one with the same signed requests a build sends, to an app open now.
    private static let transitionEntries: [Entry] = [
        Entry(group: "Transition", name: "On pictures of apps") { AnyView(TransitionPlayground()) },
        Entry(group: "Transition", name: "On an open app") { AnyView(TransitionTrial()) },
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
    /// The widths a card is drawn at: the chat at its widest (cards stop at 620), and at its narrowest, beside an app
    /// or in Lamp's panel.
    enum Width: String, CaseIterable, Identifiable {
        case chat = "Widest", wand = "Narrowest"
        var id: Self { self }
        var points: CGFloat { self == .chat ? 680 : 360 }
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

/// Sends begin, land and end to an app open on this Mac, as a build would.
private struct TransitionTrial: View {
    @ObservedObject private var store = Store.shared
    @State private var chosen: String?

    var body: some View {
        let open = store.projects.filter(AppTransition.canShow)
        VStack(alignment: .leading, spacing: 10) {
            if open.isEmpty {
                Text("Open one of your apps, built by this Lamp, to try it.").foregroundStyle(.secondary)
            } else {
                Picker("App", selection: Binding(get: { chosen ?? open[0].id }, set: { chosen = $0 })) {
                    ForEach(open) { Text($0.name).tag($0.id) }
                }
                if let project = open.first(where: { $0.id == (chosen ?? open[0].id) }) {
                    HStack {
                        Button("Glow") { AppTransition.send(.begin, to: project) }
                        Button("Change Goes In") { AppTransition.send(.land, to: project) }
                        Button("Let Go") { AppTransition.send(.end, to: project) }
                    }
                }
            }
        }
        .padding()
    }
}

/// A made-up chat for the gallery: the shared screen shows its state, and what's clicked goes nowhere.
@MainActor
final class GalleryChat: ChatLink {
    init(_ state: SidebarState?) {
        super.init()
        self.state = state
        connected = true
    }
}
