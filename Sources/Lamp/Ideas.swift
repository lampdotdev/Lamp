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
    /// The wish in the person's own words, shown alone on its tile: something they want done ("Tame the
    /// mess of screenshots on my desktop") or the thing they want ("My own detective game").
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

/// Starting points for a first app. Each starts from a moment someone would recognise as their own (the
/// screenshots piling up, the dates buried in a school newsletter), not a kind of app they could download,
/// and leans on what only an app made for them can do: their own mail, calendar, contacts, reminders and
/// folders, the menu bar, a shortcut from anywhere, a desktop widget, watching quietly in the background,
/// working other apps. Every one is something Lamp builds well. They come six to a page, and each page mixes
/// the kinds and the people (a freelancer, a parent, a teacher, a shop owner, a student, a team lead, someone
/// running a household or a club), with at least one widget and something to play with, which is free to be
/// just fun. The first six are the welcome's first page, and what a new app's empty chat shows until the
/// person has an app of their own.
enum Ideas {
    static let pool: [Idea] = [
        Idea("Screenshot Pile", "camera.viewfinder", 0.75, "Tame the mess of screenshots on my desktop: named, filed and searchable.",
             "Screenshot Pile: a menu bar app that keeps an eye on where my screenshots land. It reads the text in each new one and suggests a clear name and a folder (receipts, work, recipes, funny), and makes old ones searchable by what's in them. Nothing is renamed or moved until I approve it."),
        Idea("School Emails", "backpack", 0.08, "Catch the school dates I keep missing, buried in all those school emails.",
             "School Emails: I tell it which senders are my kids' school and clubs, and it reads their emails in Mail for the things that matter: dates, trips, forms to sign, things to bring, money to pay. It lists them by child and by week, and adds the ones I tick to my calendar or Reminders."),
        Idea("Next Meeting", "person.2.wave.2", 0.62, "See who I'm meeting next and what we last emailed about, right on my desktop.",
             "Next Meeting: a desktop widget for my next meeting today: the time, who's coming (with their role from my contacts) and the subject of our last email. The app sits in the menu bar and keeps it fresh from my calendar and Mail, and clicking a meeting there shows a one-paragraph brief."),
        Idea("Invoice Day", "doc.richtext", 0.55, "Turn the client hours in my calendar into invoices, and know which are still unpaid.",
             "Invoice Day: I put the client's name in my calendar events, and at the end of the month it totals the hours per client from my calendar at each client's rate. I check the lines, and it makes a clean, numbered invoice PDF with my details for each one, and keeps track of which are paid and which are overdue."),
        Idea("Shop Answers", "bubble.left.and.text.bubble.right", 0.4, "Answer “Do you ship abroad?” for the hundredth time with one keystroke.",
             "Shop Answers: I run a small online shop and answer the same customer questions all day (shipping, sizes, returns). I keep my answers here, and ⌃⌥A opens a small panel from any app; I type a few letters, pick one, and it's copied ready to paste. If I've copied the customer's message first, it adjusts the answer to fit it."),
        Idea("Detective Case", "magnifyingglass", 0.66, "My own detective game, with a new mystery and new suspects every time.",
             "Detective Case: a mystery game. Each case is a new crime with a handful of suspects, each with a picture. I question them in my own words and they answer in character, letting slip clues; I keep notes as I go, and when I'm ready I name the culprit and find out if I was right."),

        Idea("Job Hunt", "briefcase", 0.58, "Keep track of every job I've applied for, and follow up when they go quiet.",
             "Job Hunt: I add each job I apply for (company, role, date), and it watches my Mail for replies from those companies, moving each one along: applied, heard back, interview, offer, no. When a week goes by in silence it reminds me, and drafts a short, polite follow-up in Mail for me to check and send."),
        Idea("Marking Pile", "pencil.and.list.clipboard", 0.3, "Get a first pass on thirty essays, marked against my own rubric.",
             "Marking Pile: I'm a teacher. I drop in a folder of students' essays and my rubric, and it gives each essay a suggested mark per criterion with two kind, specific comments, quoting the student's own words. I adjust the marks and comments, and export them all as one document per student."),
        Idea("Bin Day", "trash", 0.33, "Never miss bin day again: which bins go out tonight, right on my desktop.",
             "Bin Day: a desktop widget that shows which bins go out tonight (it alternates weekly, and I set the pattern once), and the next household chore from a Reminders list I choose. The evening before bin day it sends me a notification so it never gets missed."),
        Idea("Pickup Guard", "figure.and.child.holdinghands", 0.03, "Warn me the moment a meeting lands on school pickup.",
             "Pickup Guard: runs quietly in the menu bar and watches my calendar for new events that clash with times I protect (school pickup, lunch, the gym), which I set once. When one lands on top of them it notifies me straight away and suggests the nearest free slot, which I can copy into a reply."),
        Idea("Tax Folder", "tray.full", 0.45, "Gather the receipts scattered across my Mail and Downloads before tax time.",
             "Tax Folder: I'm self-employed. It keeps an eye on my Downloads folder for new receipts and invoices, and finds receipts in my Mail, reading the seller, date, amount and category of each into a table I can correct. It shows totals per category for the tax year and exports a spreadsheet for my accountant; it asks before copying any file into my tax folder."),
        Idea("Tiny Town", "house.and.flag", 0.22, "A little town of my own, whose people live their lives while I build it.",
             "Tiny Town: a little town on a grid where I place houses, shops, a park and a farm. The townsfolk have names and personalities, go about their day and react to what I build. Each morning a one-page town newspaper tells me what happened."),

        Idea("Waiting On You", "envelope.badge", 0.6, "Show me who's still waiting on an answer from me, and since when.",
             "Waiting On You: reads the last two weeks of my inbox in Mail and picks out the emails where someone is asking me a question or waiting on a decision. It lists them oldest first with who's waiting and what they need in one line, lets me tick off the ones I've handled, and drafts a reply in Mail for me to check and send."),
        Idea("Club Dues", "person.3", 0.9, "Know who's paid this season's club dues, and nudge the rest kindly.",
             "Club Dues: I run a local club. I pick the members from a group in my contacts and tick who's paid this season's dues, with the amount and date. For the ones who haven't, it drafts a short, friendly reminder in Mail for each, which I check and send myself."),
        Idea("Due Dates", "graduationcap", 0.7, "Every deadline this term, counting down on my desktop.",
             "Due Dates: I'm a student. I drop in each course's syllabus and it finds every assignment and exam with its date, and adds the ones I approve to my calendar. A desktop widget counts down the next three, and it nudges me a week and a day before each."),
        Idea("One-on-Ones", "person.2", 0.5, "Remember what I meant to raise with each person on my team.",
             "One-on-Ones: I lead a small team. ⌃⌥1 from any app opens a box where I jot something to raise with someone, filed under their name from my contacts. An hour before each one-on-one in my calendar it shows me that person's list, and afterwards I tick off what we covered."),
        Idea("Lost Thread", "doc.text.magnifyingglass", 0.38, "Find that file someone sent me just by describing it.",
             "Lost Thread: a shortcut (⌃⌥F) opens a search box where I describe what I'm looking for in my own words (\"the PDF Sam sent about the venue\"). It searches my Mail and Downloads folder and shows the likeliest matches with why, and opens the one I pick."),
        Idea("Desk Pet", "pawprint", 0.1, "A little pet that lives in my menu bar and is happy to see me.",
             "Desk Pet: a little creature that lives in my menu bar. Clicking it opens its home, where I can feed it, play with it and give it a name. It gets hungry and sleepy through the day, says something funny now and then, and is happy to see me in the morning."),

        Idea("Kids Today", "figure.2.and.child.holdinghands", 0.95, "See which kid needs to be where today, without opening three calendars.",
             "Kids Today: I have three kids with their own calendars. A desktop widget shows today's drop-offs, pickups and activities, a color for each child, with who's driving if it's in the event. The app in the menu bar keeps it fresh and warns me if two things need me at once."),
        Idea("Busywork", "cursorarrow.motionlines", 0.66, "Do the copy-this-into-that chore between my apps while I watch.",
             "Busywork: I describe a dull chore that moves information between apps on my Mac, like copying each row of a spreadsheet into a form. It does it step by step in the apps themselves while I watch, asks before anything is saved or submitted, and tells me what it did."),
        Idea("Parent Emails", "pencil.line", 0.14, "Help me write the tricky email to a parent: kind, but clear.",
             "Parent Emails: I'm a teacher. I describe what happened with a student and how I feel about it, and it drafts an email to the parents that's warm, clear and specific, with a next step. I can ask for it gentler or firmer, and it opens in Mail for me to check and send."),
        Idea("Photo Dump", "photo.stack", 0.8, "Sort last weekend's 300 photos into folders by day and place.",
             "Photo Dump: I drop in a folder of photos from a trip or a weekend, and it suggests names from when and where each was taken (\"2026-05-03 Lisbon 014\"), grouped into folders by day. It shows the old and new names side by side and changes nothing until I confirm, with undo."),
        Idea("Where It Went", "chart.pie", 0.35, "Show me where my week's hours actually went, client by client.",
             "Where It Went: reads my calendar for the past week and groups my time by client and by kind (meetings, focus, admin), with a clear chart. It compares the week with the one before and gives me one honest, friendly observation."),
        Idea("Habit Garden", "leaf", 0.25, "A little garden that grows as I keep my daily habits.",
             "Habit Garden: I list a few daily habits and tick them off each day. Every streak grows a plant in a small illustrated garden, and missed days make it wilt a little. Remind me in the evening if something's left."),

        Idea("Bills Due", "creditcard", 0.48, "Warn me about bills coming due before the late fees hit.",
             "Bills Due: reads the bill and statement emails in my Mail and lists what's due, how much and when. A desktop widget shows the next bill and how many days are left, and it adds a reminder three days before each due date once I approve it."),
        Idea("Free Trials", "clock.badge.exclamationmark", 0.0, "Catch free trials before they quietly turn into charges.",
             "Free Trials: keeps an eye on my Mail for sign-up emails for free trials and subscriptions, and works out when each one starts charging and how much. It lists them by date and notifies me two days before a charge, so I can decide in time."),
        Idea("Friday Wrap-Up", "flag.checkered", 0.2, "Have my week's wins written up for the team by Friday at four.",
             "Friday Wrap-Up: through the week I jot quick wins with ⌃⌥W from any app. On Friday at four it notifies me with a short summary of my week from my calendar and those notes, written for my team's update, which I can edit and copy."),
        Idea("Exam Cards", "rectangle.on.rectangle.angled", 0.78, "Turn my lecture slides into flashcards for Friday's exam.",
             "Exam Cards: I drop in lecture slides and notes for a course and it makes question-and-answer cards from them. I study with spaced repetition, so cards I miss come back sooner, and it reads the exam date from my calendar to pace how many cards I see each day."),
        Idea("Birthday Radar", "gift", 0.92, "Remind me of birthdays two weeks out, with the gift ideas I saved.",
             "Birthday Radar: reads the birthdays in my calendar, and whenever I think of a gift someone would like, I jot it under their name. Two weeks before each birthday it reminds me with my saved ideas, so I'm never stuck the night before."),
        Idea("Kids' Stories", "moon.stars", 0.76, "A new bedtime story every night, starring my kid's favorite toy.",
             "Kids' Stories: I give my child's name, their favorite toy and a place, and it writes a short bedtime story with a picture for each page. Read it aloud in a calm voice, and keep a library of our favorites."),
    ]

    /// The same for an iPhone or iPad app: a moment on the go that a phone handles and a Mac doesn't (the
    /// camera, where you are, the motion sensors, a quick tap with one hand), mixed the same way, six to a page.
    static let phonePool: [Idea] = [
        Idea("Where I Parked", "car", 0.55, "Remember where I parked, with the level, the row and a photo, in one tap.",
             "Where I Parked: one big button saves where I parked, with a photo of the pillar and a note (level, row). Later it shows how far away the car is and which way to walk, and reminds me before the meter runs out."),
        Idea("Droopy Plant", "leaf.circle", 0.32, "Work out what my droopy houseplant is missing from one photo.",
             "Droopy Plant: I take a photo of a houseplant that looks unhappy and it tells me what it is and what's probably wrong (too much water, too little light). It keeps my plants with their photos and reminds me when each one needs watering."),
        Idea("Shelf Count", "shippingbox", 0.08, "Snap a shelf in my shop and see what I need to reorder.",
             "Shelf Count: I run a small shop. I photograph a shelf and it counts what's there against the stock levels I set, then lists what's running low. Keep a reorder list I can share as a spreadsheet."),
        Idea("Mileage Log", "road.lanes", 0.45, "Log every drive to a client, so tax time takes minutes.",
             "Mileage Log: I tap Start when I drive to a client and Stop when I arrive, and it records the distance from where I am, with the date and a client I pick. It totals the miles by month and client and shares them as a spreadsheet."),
        Idea("Hang It Straight", "level", 0.15, "Hang a picture frame straight on the first try.",
             "Hang It Straight: a level that uses the phone's motion sensors, with a bubble, the exact angle, and a click when it's perfectly level. Tap to hold the reading, and a second mode helps me space three frames evenly."),
        Idea("Word Ladder", "textformat.abc", 0.76, "A new word puzzle every day, and a streak to keep going.",
             "Word Ladder: a daily puzzle where I change one letter at a time to get from one word to another. Hints when I'm stuck, a streak counter, and a gentle reminder each evening if I haven't played."),

        Idea("Night Feeds", "moon.zzz", 0.7, "Track night feeds one-handed at 3am: which side, how long, and when.",
             "Night Feeds: big, dim buttons I can tap one-handed at 3am: start and stop a feed (left or right), a nap, a change. It shows how long since the last feed at a glance, and the week's pattern so I can tell the doctor."),
        Idea("Fridge Dinner", "refrigerator", 0.05, "Make tonight's dinner out of whatever's left in my fridge.",
             "Fridge Dinner: I take a photo of what's in my fridge and it suggests three dinners I could make with it tonight, with simple steps and how long each takes. Save the ones we liked."),
        Idea("Bill by Dish", "fork.knife.circle", 0.4, "Split the restaurant bill by who actually had what.",
             "Bill by Dish: I photograph the restaurant bill, tap who had each dish, and it works out everyone's share with tip and splits the shared plates. Keep a running tab for a trip with friends."),
        Idea("Head Count", "checklist", 0.62, "Count thirty kids onto the bus on a school trip, one tap each.",
             "Head Count: I'm a teacher on a school trip. I keep my class list in it, and at each stop I tap each child as they get on; it shows who's missing in big letters and how long since the last count."),
        Idea("Between Sets", "dumbbell", 0.0, "Log a set in two taps before my rest is up.",
             "Between Sets: I log the weight and reps for a set in two taps, and a rest timer starts. It shows what I lifted last time for each exercise and suggests what to try next."),
        Idea("Step Quest", "figure.walk", 0.25, "Turn my daily walks into an adventure across made-up lands.",
             "Step Quest: counts my steps through the day and turns them into a journey across a map of made-up lands, unlocking a new place every few thousand steps. Show today's steps, my best week, and what the next place is."),

        Idea("Menu Abroad", "character.bubble", 0.58, "Point at a menu abroad and know exactly what I'm ordering.",
             "Menu Abroad: I point the camera at a menu in another language and it tells me what each dish is in plain words, flags what I said I can't eat, and reads my order aloud in the local language."),
        Idea("Trail Back", "location.north.line", 0.35, "Point me back to the car when the trail splits.",
             "Trail Back: I tap once at the trailhead, and wherever I end up it shows an arrow pointing back and how far it is, using where I am and which way the phone faces. It also marks spots I tap along the way."),
        Idea("House Viewings", "house", 0.9, "Keep ten flat viewings straight, with photos and notes for each.",
             "House Viewings: at each viewing I tap New, and it saves where I am, the photos I take and a few quick ratings (light, noise, storage). Afterwards it lines them up side by side so we can compare."),
        Idea("Club Check-In", "person.crop.circle.badge.checkmark", 0.5, "See who came to club tonight, and spot who's drifted away.",
             "Club Check-In: I run a club's weekly session. I tap each member as they arrive, add newcomers in a few taps, and see who hasn't come for a month so I can check in with them."),
        Idea("Walk Thoughts", "mic", 0.14, "Catch the ideas I have on walks: said once, sorted for me.",
             "Walk Thoughts: I tap once and speak. It writes down what I said, tidies it into a short note with a title, and sorts it into ideas, to-dos and things to remember. Search everything I've said."),
        Idea("Tilt Maze", "circle.grid.cross", 0.85, "A marble maze I play by tilting my phone.",
             "Tilt Maze: a marble game where I tilt the phone to roll a ball through a maze to the hole, avoiding traps. A new maze each level, a little harder each time, with my best times."),
    ]

    /// Mac and iPhone ideas in turn: a new app's kind is worked out from what's asked for (Store.chooseKind),
    /// so the ideas are for either.
    static let mixed: [Idea] = (0..<max(pool.count, phonePool.count)).flatMap { index in
        [pool.indices.contains(index) ? pool[index] : nil, phonePool.indices.contains(index) ? phonePool[index] : nil].compactMap { $0 }
    }

    /// Six at a time, in order and starting over at the end.
    static func page(_ index: Int) -> [Idea] {
        let pool = mixed
        let start = (index * 6) % pool.count
        return (0..<6).map { pool[(start + $0) % pool.count] }
    }

    /// Six for a new app's empty chat. Until the person has an app, the first six, chosen to be a good first
    /// look; after that a random six, so the chat keeps turning up ones they haven't seen, leaving out any
    /// they've already made (by name).
    static func starters(made names: [String]) -> [Idea] {
        let pool = mixed
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
            return await Inventor.invent(avoiding: seen, device: "Mac or iPhone")
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
    /// What the ideas are for: a Mac, or an iPhone or iPad.
    private var page = 0
    private var inventing = false
    private var seen: Set<String>

    /// Opens on `first`: the welcome's first page, or the six a new app's chat drew.
    init(first: [Idea]? = nil) {
        let first = first ?? Ideas.page(0)
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
            let avoiding = Array(seen) + Ideas.mixed.map(\.title)
            let made = await Ideas.invent(avoiding: avoiding)
            inventing = false
            invented = made
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
            .init(name: "title", description: "One to three words naming the situation, such as Waiting On You or Bin Day", schema: text),
            .init(name: "blurb", description: "The wish in the person's own words, eight to fourteen words: what they want done, such as Tame the mess of screenshots on my desktop, or the thing they want, such as My own detective game, with a new mystery every time", schema: text),
            .init(name: "request", description: "Two to four sentences in the person's own voice, starting with the title and a colon: their situation, what the app reads or watches, and what it shows. Anything it changes, it asks first", schema: text),
            .init(name: "symbol", description: "An SF Symbols name that fits the app, such as calendar, leaf or music.note", schema: text),
        ])
        let batch = DynamicGenerationSchema(name: "Batch", properties: [
            .init(name: "ideas", schema: DynamicGenerationSchema(arrayOf: idea, minimumElements: 6, maximumElements: 6)),
        ])
        return try? GenerationSchema(root: batch, dependencies: [])
    }()

    /// Who the ideas are for this time, so pressing again gives a different mix. Each is a person in a
    /// situation, not a category, so the ideas come out specific.
    private static let audiences = ["a freelance designer juggling five clients", "a parent coordinating three kids' schedules",
                                    "a teacher with thirty essays to mark by Monday", "someone who runs a small online shop alone",
                                    "a student with four courses and a part-time job", "someone job hunting and losing track of applications",
                                    "a new team lead with six people to look after", "the volunteer who runs a local sports club",
                                    "someone sharing a house with three flatmates", "a self-employed plumber doing their own books",
                                    "someone caring for an elderly parent from a distance", "a nurse working rotating shifts",
                                    "a wedding photographer with thousands of photos a week", "someone planning a house move"]

    /// `device` is what the apps are for: Mac, iPhone or iPad.
    static func invent(avoiding seen: [String], device: String) async -> [Idea]? {
        // What a made-up app can lean on that a downloaded one can't, so the ideas reach for it.
        let powers = device == "Mac"
            ? "their Mail, Calendar, Contacts, Reminders and folders, the menu bar, a shortcut from any app, a desktop widget, or watching quietly in the background"
            : "the camera, where they are, the motion sensors, a quick tap on the go"
        let session = LanguageModelSession(instructions: """
            You suggest small \(device) apps a person with no programming experience could ask for. \
            Each starts from one specific situation the person would recognise as their own, not a kind of app \
            they could download. Where it fits, it uses what's already on their \(device): \(powers). \
            No accounts, no servers, no websites. Plain, warm, everyday words, never technical terms.
            """)
        let audience = audiences.randomElement()!
        let prompt = """
            Suggest six different \(device) apps for \(audience), each for a different moment in their week. \
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
