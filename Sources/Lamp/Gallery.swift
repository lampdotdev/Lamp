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

    static let entries: [Entry] = chatEntries + askEntries + approvalEntries + buildEntries + activityEntries + progressEntries + pointedEntries + importEntries + wishLinkEntries + transitionEntries + deviceEntries

    static var groups: [String] {
        entries.map(\.group).reduce(into: []) { if !$0.contains($1) { $0.append($1) } }
    }

    // MARK: Chat

    /// Whole chats, drawn by the chat's own `Transcript`: every kind of line one after another, so a line set in
    /// or sized unlike the rest shows against its neighbours.
    private static let chatEntries: [Entry] = [
        chat("A finished chat", finishedChat, undo: true),
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

    private static func chat(_ name: String, _ lines: [LogLine], group: String = "Chat", undo: Bool = false,
                             activity: String? = nil) -> Entry {
        Entry(group: group, name: name) {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                Transcript(lines: lines, dir: URL(fileURLWithPath: "/nonexistent"), busy: activity != nil, progressShown: activity != nil)
                // The line the chat has under a turn going on, as Lamp's window draws it (`ProjectView`).
                if let activity {
                    let progress = { () -> TurnProgress in
                        var progress = TurnProgress(newApp: false)
                        progress.activity = activity
                        progress.started = .now.addingTimeInterval(-7)
                        progress.activitySince = progress.started
                        return progress
                    }()
                    ActivityRow(progress: progress, lines: lines, dir: URL(fileURLWithPath: "/nonexistent")).padding(.top, 12)
                }
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
        Entry(group: "Approval", name: name) {
            AnyView(VStack(alignment: .leading, spacing: 0) {
                Transcript(lines: [LogLine(kind: .user, text: trailsRequest),
                                   LogLine(kind: .agent, text: "I'll add a trails layer to the map."),
                                   LogLine(kind: .tool, text: "Read Sources/MapView.swift")],
                           dir: URL(fileURLWithPath: "/nonexistent"), busy: true, progressShown: true)
                ChatLook.ActivityLine("Waiting for your OK", started: .now.addingTimeInterval(-12)).padding(.top, 12)
                ChatLook.ApprovalCard(title: title, command: command, explanation: explanation, request: trailsRequest, whyAsked: why,
                                      onAllow: {}, onAllowAll: {}, onDeny: {})
                    .padding(.top, 12)
                ChatLook.MessageBar(busy: true, canSend: false, attachHelp: "", attach: {}, send: {}, stop: {}, focus: {}) {
                    Text(ChatLook.placeholder(busy: true, empty: true))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, minHeight: Composer.lineHeight, alignment: .leading)
                        .padding(.leading, 5)
                } above: { EmptyView() }
                    .padding(.top, 8)
            })
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
        step("Done by people, and the sign-in rejected", rokuPassword, known: .init(how: .people, model: "4850X", version: "14.0"),
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
        Entry(group: "Device setup", name: "A device with a new certificate") {
            AnyView(DeviceReconnectCard(device: "XBOX", reconnect: {}))
        },
        Entry(group: "Device setup", name: "The setup window, the device's certificate changed") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in }, reconnect: {}))
        },
        Entry(group: "Device setup", name: "The setup window, set up") {
            AnyView(DeviceSetupPage(device: roku, steps: [rokuMode, rokuPassword, rokuLook], passed: [rokuMode.id, rokuPassword.id, rokuLook.id],
                                    content: nil, typed: .constant(""), approval: nil, act: {}, decide: { _ in }))
        },
    ]

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

    private static let buildEntries: [Entry] = [
        // A new app before the model has first answered, which has no plan yet.
        build("Just started") { _ in },
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
        // A long first build: the steps so far behind one line under the plan, as "Worked for…" holds them after.
        Entry(group: "Build card", name: "With its steps so far") {
            var progress = TurnProgress(newApp: true)
            progress.activity = "Building…"
            progress.activitySince = Date().addingTimeInterval(-95)
            progress.plan = [PlanPart(id: 0, title: "The big number and the + button", done: true, files: ["Counter.swift"]),
                             PlanPart(id: 1, title: "Remembering the count after closing", done: true, files: ["Model.swift"])]
            let steps = [LogLine(kind: .status, text: "Ran: cat APP.md", said: "Reading how the app is laid out"),
                         LogLine(kind: .status, text: "Working on the interface"),
                         LogLine(kind: .status, text: "Ran: ./gradlew assembleDebug", said: "Building the app"),
                         LogLine(kind: .status, text: "Ran: ./gradlew assembleDebug", said: "Building the app again")]
            return AnyView(BuildCardView(title: "Droid Lab", name: "Droid Lab", iconReady: false, progress: progress, steps: steps) {
                BlueprintIcon(letter: "D", size: 44)
            })
        },
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
                                                 hasSteps: true) { StepList(steps: steps) })
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
            return AnyView(VStack(alignment: .leading, spacing: 4) { StepList(steps: steps) })
        },
        // A change waiting for Reload, under the answer that says so: the action line's symbol and words in the steps'
        // column, with "Worked for…" above and Undo Last Change below.
        Entry(group: "Activity", name: "Reload under a change") {
            AnyView(VStack(alignment: .leading, spacing: 8) {
                ChatLook.AgentText("Once you press Reload, the rack scrolls to each new spice as you add it.")
                ChatLook.Worked("Worked for 54 s") { EmptyView() }
                ChatLook.ActionLine(symbol: "arrow.clockwise", text: ReloadLine.text("Hot Shelf"), button: "Reload", prominent: true) {}
                ChatLook.UndoChange {}
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
    ]

    private static let diskMapLine = "Shows where your disk space goes, as rings that fill in while it measures."
    private static let diskMapWish = "A Mac app that shows where my disk space goes, as rings that fill in while it measures. Clicking a ring opens that folder."

    private static func wishLink(_ name: String, values: WishLinkCard.Values? = nil, picture: Bool = true, retake: Bool = true,
                                 stage: WishLinkCard.Stage = .editing, link: Bool = false, copied: Bool = false,
                                 changed: Bool = false, width: CGFloat? = 480) -> Entry {
        Entry(group: "Share Link", name: name) {
            let folder = Starters.folder?.appendingPathComponent("diskmap")
            let card = WishLinkCard(
                icon: folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("icon/icon.png")) },
                picture: picture ? folder.flatMap { NSImage(contentsOf: $0.appendingPathComponent("preview.png")) } : nil,
                values: .constant(values ?? .init(name: "Disk Map", line: diskMapLine, words: diskMapWish, includePicture: picture)),
                limits: WishLink.cardLimits, link: link ? "https://lamp.dev/w/AyTkit4xCc" : nil, changed: !link || changed,
                stage: stage, copied: copied, retake: retake ? {} : nil, retaking: false,
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
