import SwiftUI
import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// An app someone could ask Lamp for: shown as a tile, and choosing it fills in the request.
struct Idea: Identifiable, Equatable {
    var title: String
    var symbol: String
    /// The hue of its icon, 0–1.
    var hue: Double
    var blurb: String
    var prompt: String

    var id: String { title }

    init(_ title: String, _ symbol: String, _ hue: Double, _ blurb: String, _ prompt: String) {
        self.title = title
        self.symbol = symbol
        self.hue = hue
        self.blurb = blurb
        self.prompt = prompt
    }
}

/// Starting points for a first app. Each shows something different a Mac app can do, and every one is
/// something Lamp builds well. They come six to a page, and each page mixes the kinds: the Mac's own
/// powers (files, the menu bar, shortcuts), the person's calendar, mail and contacts, reading and writing,
/// pictures, and something to play with. The first six are the welcome's first page, and what a new app's
/// empty chat shows until the person has an app of their own.
enum Ideas {
    static let pool: [Idea] = [
        Idea("Downloads Tidy", "folder.badge.gearshape", 0.58, "Sorts what lands in Downloads, from the menu bar.",
             "Downloads Tidy: a menu bar app that watches my Downloads folder and groups new files by what they are (receipts, installers, screenshots, documents), suggesting a clear name for each. Nothing moves or gets renamed until I approve it."),
        Idea("Week Ahead", "calendar", 0.03, "Your calendar and reminders for the week, at a glance.",
             "Week Ahead: reads my calendar and reminders for the coming week and lays the days out calmly, pointing out clashes and days that are too full. It suggests where I could fit some focus time and adds those blocks to my calendar when I approve them."),
        Idea("Screenshot Notes", "camera.viewfinder", 0.75, "Reads the text in screenshots and makes it searchable.",
             "Screenshot Notes: I drop screenshots on it and it pulls out the text and the key details (who, what, dates, amounts) into a searchable list, with the picture alongside."),
        Idea("Inbox Helper", "envelope.badge", 0.6, "Sorts your email and drafts the replies.",
             "Inbox Helper: reads my latest emails in Mail and sorts them into Needs a reply, Good to know and Can wait, with a one-line summary of each. For anything that needs a reply, it drafts one in my tone that opens in Mail for me to check and send."),
        Idea("Clipboard Shelf", "list.clipboard", 0.08, "Remembers what you copy, one shortcut away.",
             "Clipboard Shelf: keeps the last 200 things I copy (text and images). A shortcut (⌃⌥V) opens a small searchable panel from any app; Return copies the item back so I can paste it. Let me pin items and give them short names, for the replies and addresses I type over and over."),
        Idea("Focus Timer", "timer", 0.0, "A menu bar timer with breaks and daily totals.",
             "Focus Timer: a menu bar timer for 25-minute focus sessions with 5-minute breaks. It shows the time left in the menu bar, notifies me when a session or break ends, keeps a daily total, and has an Open at Login option in Settings."),

        Idea("Event Grabber", "calendar.badge.plus", 0.48, "Turns a flyer or an email into a calendar event.",
             "Event Grabber: I drop in a flyer, a screenshot or a pasted invitation and it reads the event's name, date, time and place. It shows me the details to check, then adds the event to my calendar with a reminder the day before."),
        Idea("Reading Queue", "books.vertical", 0.33, "Ranks PDFs and links by what matters to your work.",
             "Reading Queue: I drop in PDFs, documents and links (even a whole pile of open tabs), and it ranks them by how much they matter for what I'm working on, which I describe in a box at the top. Each item gets a one-line summary and why it's ranked there. Mark items as read."),
        Idea("Detective Case", "magnifyingglass", 0.66, "Solve a new little mystery every time.",
             "Detective Case: a mystery game. Each case is a new crime with a handful of suspects, each with a picture. I question them in my own words and they answer in character, letting slip clues; I keep notes as I go, and when I'm ready I name the culprit and find out if I was right."),
        Idea("Receipt Box", "doc.text.magnifyingglass", 0.38, "Turns receipts into a tidy expense list.",
             "Receipt Box: I drop in photos or PDFs of receipts and it reads the shop, date, total and category from each one into a table I can edit. Show a monthly total per category and export everything as a spreadsheet."),
        Idea("Habit Garden", "leaf", 0.3, "Grows a little garden as you keep your habits.",
             "Habit Garden: I list a few daily habits and tick them off each day. Every streak grows a plant in a small illustrated garden, and missed days make it wilt a little. Remind me in the evening if something's left."),
        Idea("Batch Renamer", "character.cursor.ibeam", 0.5, "Renames piles of files the way you describe.",
             "Batch Renamer: I drop in a folder or files and describe how they should be named (\"date taken, then a number\"). It previews the new names next to the old ones and renames only when I confirm, with undo."),

        Idea("Meeting Prep", "person.2.wave.2", 0.62, "A short brief before each of today's meetings.",
             "Meeting Prep: looks at today's meetings in my calendar and, for each one, shows who's coming (with their company and role from my contacts), our latest emails, and my notes from last time. A one-paragraph brief sits at the top so I walk in prepared."),
        Idea("Photo Studio", "photo.on.rectangle.angled", 0.9, "Cleans up product photos and makes new versions.",
             "Photo Studio: I drop in product photos and it puts each one on a clean white background, then lets me ask for variations in plain words (\"on a wooden table\", \"warmer light\"). Show before and after side by side, and export the ones I like."),
        Idea("Tiny Town", "house.and.flag", 0.22, "A little town that lives a life of its own.",
             "Tiny Town: a little town on a grid where I place houses, shops, a park and a farm. The townsfolk have names and personalities, go about their day and react to what I build. Each morning a one-page town newspaper tells me what happened."),
        Idea("Flashcards", "rectangle.on.rectangle.angled", 0.78, "Turns your notes into cards you can study.",
             "Flashcards: I paste notes or a document and it makes question-and-answer cards from them. Study them with spaced repetition, so cards I get wrong come back sooner. Keep separate decks for each subject."),
        Idea("Window Notes", "note.text", 0.14, "Sticky notes that float above your work.",
             "Window Notes: small sticky notes that float above other windows, in a few soft colors. Create one with a shortcut, drag them anywhere, and they're still there after a restart."),
        Idea("Recipe Keeper", "fork.knife", 0.05, "Saves recipes from anywhere and scales them.",
             "Recipe Keeper: I paste a recipe link or text and it saves a clean version with ingredients and steps. I can scale servings up or down, tick ingredients off while cooking, and build a shopping list from a few recipes."),

        Idea("Email to Tasks", "checklist", 0.42, "Finds the to-dos hiding in your email.",
             "Email to Tasks: reads my recent emails in Mail and finds the ones asking me to do something. It lists each task with who asked and a sensible due date, and adds the ones I tick to Reminders."),
        Idea("Podcast Notes", "waveform", 0.8, "Turns an audio file into notes and highlights.",
             "Podcast Notes: I drop in an audio file and it writes a transcript, a short summary and the five most interesting moments with their timestamps. Click a moment to play from there."),
        Idea("Desk Pet", "pawprint", 0.1, "A small pet that lives in your menu bar.",
             "Desk Pet: a little creature that lives in my menu bar. Clicking it opens its home, where I can feed it, play with it and give it a name. It gets hungry and sleepy through the day, says something funny now and then, and is happy to see me in the morning."),
        Idea("Invoice Maker", "doc.richtext", 0.55, "Makes clean invoices for freelance work.",
             "Invoice Maker: I keep a list of clients and add the hours or items for each job, and it makes a clean, good-looking invoice PDF with my details, numbered automatically. Track which invoices are paid and which are overdue."),
        Idea("Meeting Recap", "text.bubble", 0.7, "Turns meeting notes into decisions and to-dos.",
             "Meeting Recap: I paste or type rough notes from a meeting and it writes a short summary, the decisions made, and a to-do list with who owns each item. It adds my own to-dos to Reminders and drafts a recap email to the others in Mail. Keep past meetings in a sidebar, searchable."),
        Idea("Writing Coach", "pencil.and.outline", 0.25, "Gives gentle feedback on anything you write.",
             "Writing Coach: I paste something I've written and say who it's for. It points out unclear sentences and suggests clearer ones, explaining why, without rewriting my voice. Let me accept suggestions one by one, or ask for a shorter or warmer version of the whole thing."),

        Idea("Gift Ideas", "gift", 0.95, "Remembers what people would love, before you forget.",
             "Gift Ideas: I pick the people I buy gifts for from my contacts and add their birthdays. Whenever I think of something someone would like, I jot it under their name. It adds a reminder two weeks before each birthday with my saved ideas."),
        Idea("Kids' Stories", "moon.stars", 0.76, "Makes up bedtime stories with pictures.",
             "Kids' Stories: I give a child's name, an animal and a place, and it writes a short bedtime story with a picture for each page. Read it aloud in a calm voice, and keep a library of our favorites."),
        Idea("Time Report", "chart.pie", 0.35, "Shows where your week's hours went.",
             "Time Report: reads my calendar for the past week and groups my time by kind (meetings, focus, admin, personal) with a clear chart. It compares the week with the one before and gives me one honest, friendly observation."),
        Idea("Trip Planner", "airplane", 0.57, "Builds a day-by-day plan for your next trip.",
             "Trip Planner: I say where I'm going, when, and what I like, and it drafts a day-by-day plan I can rearrange by dragging. Keep a packing list alongside that I can tick off, and let me export the plan as a PDF."),
        Idea("Bill Splitter", "divide.circle", 0.45, "Splits shared costs fairly between friends.",
             "Bill Splitter: for a trip or a shared house, I add people and expenses (who paid, who it was for). It works out who owes whom with as few payments as possible, and keeps a history of each group."),
        Idea("Mood Journal", "face.smiling", 0.15, "A quick daily check-in that shows your patterns.",
             "Mood Journal: once a day I pick how I feel on a five-point scale and write a sentence. It shows a calendar colored by mood and, once a month, a short gentle summary of patterns it notices."),
    ]

    /// Six at a time from the pool, in order and starting over at the end.
    static func page(_ index: Int) -> [Idea] {
        let start = (index * 6) % pool.count
        return (0..<6).map { pool[(start + $0) % pool.count] }
    }

    /// Six for a new app's empty chat. Until the person has an app, the first six, chosen to be a good first
    /// look; after that a random six, so the chat keeps turning up ones they haven't seen, leaving out any
    /// they've already made (by name).
    static func starters(made names: [String]) -> [Idea] {
        guard !names.isEmpty else { return Array(pool.prefix(6)) }
        let made = Set(names.map { $0.lowercased() })
        return Array(pool.filter { !made.contains($0.title.lowercased()) }.shuffled().prefix(6))
    }

    /// Whether this Mac can make up new ideas with Apple's on-device model.
    static var canInvent: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.availability == .available }
        #endif
        return false
    }

    /// Six new ideas from Apple's on-device model, or nil when it's unavailable or fails. Free and private,
    /// so it can run before the user has chosen what builds their apps.
    static func invent(avoiding seen: [String]) async -> [Idea]? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *), canInvent {
            return await Inventor.invent(avoiding: seen)
        }
        #endif
        return nil
    }
}

/// The six ideas on show, and the next six on request: made up on this Mac when it can, otherwise the next
/// page of the built-in ones. The welcome and a new app's empty chat both page through ideas this way.
@MainActor
final class IdeaDeck: ObservableObject {
    @Published private(set) var ideas: [Idea]
    /// The next six, already made up, so asking for more is instant.
    @Published private(set) var invented: [Idea]?
    private var page = 0
    private var inventing = false
    private var seen: Set<String>

    /// Opens on `first`: the welcome's first page, or the six a new app's chat drew.
    init(first: [Idea] = Ideas.page(0)) {
        ideas = first
        seen = Set(first.map(\.title))
    }

    /// What the button for more shows: one icon for both kinds, since either way it's a fresh idea.
    static let moreSymbol = "lightbulb"

    func more() {
        let next: [Idea]
        if let invented {
            next = invented
            self.invented = nil
        } else {
            page += 1
            next = Ideas.page(page)
        }
        seen.formUnion(next.map(\.title))
        withAnimation { ideas = next }
        prefetch()
    }

    func prefetch() {
        guard Ideas.canInvent, invented == nil, !inventing else { return }
        inventing = true
        Task {
            let avoiding = Array(seen) + Ideas.pool.map(\.title)
            invented = await Ideas.invent(avoiding: avoiding)
            inventing = false
        }
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
private enum Inventor {
    /// What the model has to fill in for each idea, and that there are six of them. Described to the
    /// model as data rather than with the framework's macros, whose compiler plugin comes only with
    /// Xcode: this way Lamp builds with just the Command Line Tools.
    private static let schema: GenerationSchema? = {
        let text = DynamicGenerationSchema(type: String.self)
        let idea = DynamicGenerationSchema(name: "Invented", properties: [
            .init(name: "title", description: "A short, friendly app name of one to three words", schema: text),
            .init(name: "blurb", description: "What the app does, in under ten plain words", schema: text),
            .init(name: "request", description: "Two or three sentences asking for the app, written as the person would describe it, starting with the app name and a colon", schema: text),
            .init(name: "symbol", description: "An SF Symbols name that fits the app, such as calendar, leaf or music.note", schema: text),
        ])
        let batch = DynamicGenerationSchema(name: "Batch", properties: [
            .init(name: "ideas", schema: DynamicGenerationSchema(arrayOf: idea, minimumElements: 6, maximumElements: 6)),
        ])
        return try? GenerationSchema(root: batch, dependencies: [])
    }()

    /// Who the ideas are for this time, so pressing again gives a different mix.
    private static let audiences = ["a student", "a small business owner", "a parent", "a freelancer", "a home cook",
                                    "a writer", "someone who loves travel", "a musician", "a teacher", "someone getting fit",
                                    "a photographer", "someone organizing their home", "a team at work", "a gardener"]

    static func invent(avoiding seen: [String]) async -> [Idea]? {
        let session = LanguageModelSession(instructions: """
            You suggest small, useful Mac apps that a person with no programming experience could ask for. \
            Each app does one thing well and works on the person's own Mac: no accounts, no servers, no websites. \
            Use plain, warm, everyday words, never technical terms.
            """)
        let audience = audiences.randomElement()!
        let prompt = """
            Suggest six different Mac apps that would make life easier for \(audience). \
            Don't suggest any of these: \(seen.suffix(40).joined(separator: ", ")).
            """
        guard let schema,
              let batch = try? await session.respond(to: prompt, schema: schema).content,
              let invented = try? batch.value([GeneratedContent].self, forProperty: "ideas") else { return nil }
        let ideas = invented.compactMap { invented -> Idea? in
            guard let named = try? invented.value(String.self, forProperty: "title"),
                  let blurb = try? invented.value(String.self, forProperty: "blurb"),
                  let request = try? invented.value(String.self, forProperty: "request") else { return nil }
            let title = named.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !seen.contains(title), !request.isEmpty else { return nil }
            // A made-up symbol name would draw nothing.
            let wanted = (try? invented.value(String.self, forProperty: "symbol")) ?? ""
            let symbol = NSImage(systemSymbolName: wanted, accessibilityDescription: nil) == nil ? "sparkles" : wanted
            let hue = Double(abs(title.hashValue) % 100) / 100
            return Idea(title, symbol, hue, blurb, request)
        }
        return ideas.count >= 4 ? Array(ideas.prefix(6)) : nil
    }
}
#endif

/// An idea's icon: its symbol on a squircle, like an app icon. Quiet gray until it's `lit` (hovered or
/// chosen), when it takes its own color.
struct IdeaIcon: View {
    let symbol: String
    let hue: Double
    var size: CGFloat = 44
    var lit = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.26, style: .continuous)
        ZStack {
            shape.fill(lit ? AnyShapeStyle(LinearGradient(colors: [Color(hue: hue, saturation: 0.45, brightness: 1),
                                                                  Color(hue: hue, saturation: 0.75, brightness: 0.88)],
                                                         startPoint: .top, endPoint: .bottom))
                           : AnyShapeStyle(Color(white: 0.93)))
            shape.strokeBorder(lit ? .white.opacity(0.35) : .black.opacity(0.05), lineWidth: 1)
            Image(systemName: symbol)
                .font(.system(size: size * 0.46, weight: .semibold))
                .foregroundStyle(lit ? Color.white : Color(white: 0.45))
        }
        .frame(width: size, height: size)
        .shadow(color: lit ? Color(hue: hue, saturation: 0.7, brightness: 0.7).opacity(0.25) : .clear,
                radius: size * 0.16, y: size * 0.08)
        .animation(.easeOut(duration: 0.2), value: lit)
    }
}
