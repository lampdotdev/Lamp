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
/// something Lamp builds well. The first six are the ones a new app's empty chat shows.
enum Ideas {
    static let pool: [Idea] = [
        Idea("Downloads Tidy", "folder.badge.gearshape", 0.58, "Sorts what lands in Downloads, from the menu bar.",
             "Downloads Tidy: a menu bar app that watches my Downloads folder and groups new files by what they are (receipts, installers, screenshots, documents), suggesting a clear name for each. Nothing moves or gets renamed until I approve it."),
        Idea("Screenshot Notes", "camera.viewfinder", 0.75, "Reads the text in screenshots and makes it searchable.",
             "Screenshot Notes: I drop screenshots on it and it pulls out the text and the key details (who, what, dates, amounts) into a searchable list, with the picture alongside."),
        Idea("Clipboard Shelf", "list.clipboard", 0.08, "Remembers what you copy, one shortcut away.",
             "Clipboard Shelf: keeps the last 200 things I copy (text and images). A shortcut (⌃⌥V) opens a small searchable panel from any app; Return copies the item back so I can paste it. Let me pin items so they stay at the top."),
        Idea("Reading Queue", "books.vertical", 0.33, "Ranks PDFs and links by what matters to your work.",
             "Reading Queue: I drop in PDFs, documents and links, and it ranks them by how much they matter for what I'm working on, which I describe in a box at the top. Each item gets a one-line summary and why it's ranked there."),
        Idea("Focus Timer", "timer", 0.0, "A menu bar timer with breaks and daily totals.",
             "Focus Timer: a menu bar timer for 25-minute focus sessions with 5-minute breaks. It shows the time left in the menu bar, notifies me when a session or break ends, keeps a daily total, and has an Open at Login option in Settings."),
        Idea("Photo Studio", "photo.on.rectangle.angled", 0.9, "Cleans up product photos and makes new versions.",
             "Photo Studio: I drop in product photos and it puts each one on a clean white background, then lets me ask for variations in plain words (\"on a wooden table\", \"warmer light\"). Show before and after side by side, and export the ones I like."),

        Idea("Receipt Box", "doc.text.magnifyingglass", 0.38, "Turns receipts into a tidy expense list.",
             "Receipt Box: I drop in photos or PDFs of receipts and it reads the shop, date, total and category from each one into a table I can edit. Show a monthly total per category and export everything as a spreadsheet."),
        Idea("Meeting Recap", "person.2.wave.2", 0.62, "Turns meeting notes into decisions and to-dos.",
             "Meeting Recap: I paste or type rough notes from a meeting and it writes a short summary, the decisions made, and a to-do list with who owns each item. Keep past meetings in a sidebar, searchable."),
        Idea("Habit Garden", "leaf", 0.3, "Grows a little garden as you keep your habits.",
             "Habit Garden: I list a few daily habits and tick them off each day. Every streak grows a plant in a small illustrated garden, and missed days make it wilt a little. Remind me in the evening if something's left."),
        Idea("Recipe Keeper", "fork.knife", 0.05, "Saves recipes from anywhere and scales them.",
             "Recipe Keeper: I paste a recipe link or text and it saves a clean version with ingredients and steps. I can scale servings up or down, tick ingredients off while cooking, and build a shopping list from a few recipes."),
        Idea("Plant Care", "drop", 0.45, "Tells you which plants need water today.",
             "Plant Care: I add my houseplants with a photo and how often each needs water. It shows which ones need watering today, lets me mark them done, and sends a gentle morning reminder."),
        Idea("Trip Planner", "airplane", 0.55, "Builds a day-by-day plan for your next trip.",
             "Trip Planner: I say where I'm going, when, and what I like, and it drafts a day-by-day plan I can rearrange by dragging. Keep a packing list alongside, and let me export the plan as a PDF."),
        Idea("Subscriptions", "creditcard", 0.7, "Keeps every subscription and its renewal in one place.",
             "Subscriptions: I add the services I pay for, with price and renewal date. It shows what I spend per month and per year, sorts by next renewal, and reminds me three days before anything renews."),
        Idea("Word of the Day", "character.book.closed", 0.12, "A new word each morning, from the menu bar.",
             "Word of the Day: a menu bar app that shows a new interesting English word each morning with its meaning, an example sentence and where it comes from. Keep a list of words I've starred."),
        Idea("Gift Ideas", "gift", 0.95, "Remembers what people would love, before you forget.",
             "Gift Ideas: a list of the people I buy gifts for, with birthdays. Whenever I think of something someone would like, I jot it under their name. Remind me two weeks before each birthday with my saved ideas."),
        Idea("Invoice Maker", "doc.richtext", 0.6, "Makes clean invoices for freelance work.",
             "Invoice Maker: I keep a list of clients and add the hours or items for each job, and it makes a clean, good-looking invoice PDF with my details, numbered automatically. Track which invoices are paid and which are overdue."),
        Idea("Mood Journal", "face.smiling", 0.15, "A quick daily check-in that shows your patterns.",
             "Mood Journal: once a day I pick how I feel on a five-point scale and write a sentence. It shows a calendar colored by mood and, once a month, a short gentle summary of patterns it notices."),
        Idea("Workout Log", "figure.run", 0.02, "Logs workouts and shows your progress.",
             "Workout Log: I log exercises with sets, reps and weight in a few clicks, reusing my usual routines. Show charts of progress for each exercise and my personal bests."),
        Idea("Flashcards", "rectangle.on.rectangle.angled", 0.78, "Turns your notes into cards you can study.",
             "Flashcards: I paste notes or a document and it makes question-and-answer cards from them. Study them with spaced repetition, so cards I get wrong come back sooner. Keep separate decks for each subject."),
        Idea("Tab Sweeper", "safari", 0.57, "Saves today's browser tabs into a readable list.",
             "Tab Sweeper: I paste a bunch of links I had open, and it groups them by topic with the page title and a one-line summary each, so I can close my tabs without losing anything. Mark items as read."),
        Idea("Color Picker", "eyedropper", 0.85, "Grabs colors from anywhere on screen.",
             "Color Picker: a menu bar app with a shortcut that lets me pick a color from anywhere on screen. It keeps a history of picked colors and copies them as hex, RGB or SwiftUI with one click. Let me save palettes."),
        Idea("Bill Splitter", "divide.circle", 0.35, "Splits shared costs fairly between friends.",
             "Bill Splitter: for a trip or a shared house, I add people and expenses (who paid, who it was for). It works out who owes whom with as few payments as possible, and keeps a history of each group."),
        Idea("Daily Brief", "sun.horizon", 0.1, "A calm morning page with your day at a glance.",
             "Daily Brief: a window that opens in the morning with today's date, the weather where I am, my top three priorities (which I type in) and a short motivating quote. Carry over unfinished priorities from yesterday."),
        Idea("Quote Board", "quote.bubble", 0.68, "Collects lines worth remembering.",
             "Quote Board: I save quotes with who said them and where I found them, and tag them. Show them as cards on a board, searchable, with a random quote each time I open the app."),
        Idea("Batch Renamer", "character.cursor.ibeam", 0.5, "Renames piles of files the way you describe.",
             "Batch Renamer: I drop in a folder or files and describe how they should be named (\"date taken, then a number\"). It previews the new names next to the old ones and renames only when I confirm, with undo."),
        Idea("Image Shrinker", "arrow.down.right.and.arrow.up.left", 0.4, "Makes photos smaller for email and the web.",
             "Image Shrinker: I drop in photos and it makes smaller copies for email or the web, with a slider for size and quality and a preview of how they'll look. Save the copies next to the originals."),
        Idea("Podcast Notes", "waveform", 0.8, "Turns an audio file into notes and highlights.",
             "Podcast Notes: I drop in an audio file and it writes a transcript, a short summary and the five most interesting moments with their timestamps. Click a moment to play from there."),
        Idea("Writing Coach", "pencil.and.outline", 0.25, "Gives gentle feedback on anything you write.",
             "Writing Coach: I paste something I've written and say who it's for. It points out unclear sentences and suggests clearer ones, explaining why, without rewriting my voice. Let me accept suggestions one by one."),
        Idea("Contact Notes", "person.text.rectangle", 0.65, "Remembers the little things about people you meet.",
             "Contact Notes: for each person I meet, I jot who they are, where we met and what we talked about. Search by anything, and remind me to follow up with people I said I'd get back to."),
        Idea("Wallpaper Maker", "paintpalette", 0.88, "Paints a new desktop picture from a description.",
             "Wallpaper Maker: I describe a scene or a mood and it makes a desktop picture at my screen's size. Keep a gallery of the ones I've made and set any of them as my wallpaper with one click."),
        Idea("Countdowns", "calendar.badge.clock", 0.03, "Counts down to the days you're looking forward to.",
             "Countdowns: I add events I'm looking forward to (a holiday, a launch, a birthday) and it shows big friendly countdowns, each with its own color and emoji. Show the nearest one in the menu bar."),
        Idea("Language Buddy", "globe", 0.52, "Practise a language a few minutes a day.",
             "Language Buddy: I choose a language I'm learning and my level, and it gives me five short exercises a day (translate, fill the gap, pick the word), explaining my mistakes. Track my streak."),
        Idea("Pitch Polisher", "megaphone", 0.07, "Tightens a pitch or bio into something punchy.",
             "Pitch Polisher: I paste a rough pitch, bio or product description and say how long it should be. It gives me three versions with different tones (friendly, confident, formal) that I can edit and copy."),
        Idea("Snippets", "text.badge.plus", 0.72, "Saves the replies you type over and over.",
             "Snippets: I save bits of text I type often (addresses, replies, sign-offs) with a short name. A shortcut opens a search panel from any app, and Return copies the snippet so I can paste it."),
        Idea("Book Shelf", "book", 0.18, "Tracks what you've read and what's next.",
             "Book Shelf: I add books by title and it fills in the author and cover. Sort them into To Read, Reading and Read, give stars and notes, and show how many I've read this year."),
        Idea("Chore Wheel", "arrow.triangle.2.circlepath", 0.28, "Shares out household chores fairly.",
             "Chore Wheel: I list the people at home and the chores, and it rotates who does what each week, fairly. Everyone can tick things off, and it shows who's done what this month."),
        Idea("Study Planner", "graduationcap", 0.6, "Plans your revision around your exam dates.",
             "Study Planner: I add my exams with dates and the topics for each, and how many hours a day I can study. It makes a revision timetable, adjusts it when I fall behind, and shows how ready I am for each exam."),
        Idea("Menu Bar Weather", "cloud.sun", 0.56, "The forecast at a glance, in the menu bar.",
             "Menu Bar Weather: shows the current temperature and an icon in the menu bar. Clicking it shows the next 12 hours and the week ahead, and warns me in the morning if it'll rain later."),
        Idea("Social Scheduler", "bubble.left.and.text.bubble.right", 0.83, "Drafts a week of posts for your small business.",
             "Social Scheduler: I describe my small business and what's happening this week, and it drafts a week of short social posts with suggested times. I can edit each one, and mark them as posted."),
        Idea("Smart Albums", "photo.stack", 0.92, "Sorts a folder of photos by what's in them.",
             "Smart Albums: I point it at a folder of photos and it groups them by what's in them (people, food, beaches, documents) and by date, so I can find things fast. Let me rename groups and export a group to a folder."),
        Idea("Packing List", "suitcase", 0.48, "Makes a packing list for any trip.",
             "Packing List: I say where I'm going, for how long and what I'll be doing, and it makes a packing list grouped by category. Tick things off as I pack, and save lists to reuse."),
        Idea("Decision Helper", "scalemass", 0.42, "Weighs up a tough choice with you.",
             "Decision Helper: I describe a decision and the options. It helps me list what matters, scores each option against it, and shows the result as a clear table with a short explanation. Save past decisions."),
        Idea("Lyric Sheets", "music.note.list", 0.97, "Keeps song lyrics and chords for practice.",
             "Lyric Sheets: I paste lyrics with chords and it lays them out cleanly with chords above the words. Transpose up or down a key, auto-scroll while I play, and keep a setlist."),
        Idea("Email Drafter", "envelope.badge", 0.6, "Writes the email you've been putting off.",
             "Email Drafter: I say who I'm writing to and roughly what I need to say, and it drafts a clear, polite email in my tone. Offer a shorter version and a warmer version, and copy the one I choose."),
        Idea("Kids' Stories", "moon.stars", 0.76, "Makes up bedtime stories with pictures.",
             "Kids' Stories: I give a child's name, an animal and a place, and it writes a short bedtime story with a picture for each page. Read it aloud in a calm voice, and keep a library of our favorites."),
        Idea("Window Notes", "note.text", 0.14, "Sticky notes that float above your work.",
             "Window Notes: small sticky notes that float above other windows, in a few soft colors. Create one with a shortcut, drag them anywhere, and they're still there after a restart."),
        Idea("Price Watch", "tag", 0.36, "Keeps track of things you want to buy.",
             "Price Watch: I keep a list of things I want to buy with a link, the price I saw and the price I'd pay. Mark the ones I've bought and show how much I've saved by waiting."),
    ]

    /// Six at a time from the pool, in order and starting over at the end.
    static func page(_ index: Int) -> [Idea] {
        let start = (index * 6) % pool.count
        return (0..<6).map { pool[(start + $0) % pool.count] }
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

/// An idea's icon: its symbol on a squircle, like an app icon. Quiet grey until it's `lit` (hovered or
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
