import SwiftUI
import AppKit
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Something someone could ask Lamp for: shown as a tile, and choosing it puts its wish in the message box.
struct Idea: Identifiable, Equatable {
    /// What part of life it's for. Each page of ideas has one of each, so it never reads as only work, or only
    /// problems: making things easier and making them more fun.
    enum Kind: CaseIterable { case health, money, play, home, work, everyday }
    var kind: Kind
    var title: String
    var symbol: String
    /// The hue of its icon, 0–1.
    var hue: Double
    /// The wish in the person's own words, shown alone on its tile: something they want done ("Tame the
    /// mess of screenshots on my desktop") or the thing they want ("My own detective game").
    var blurb: String

    var id: String { title }

    init(_ kind: Kind, _ title: String, _ symbol: String, _ hue: Double, _ blurb: String) {
        self.kind = kind
        self.title = title
        self.symbol = symbol
        self.hue = hue
        self.blurb = blurb
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
        Idea(.everyday, "Screenshot Pile", "camera.viewfinder", 0.75, "Tame the mess of screenshots on my desktop: named, filed and searchable."),
        Idea(.home, "School Emails", "backpack", 0.08, "Catch the school dates I keep missing, buried in all those school emails."),
        Idea(.work, "Next Meeting", "person.2.wave.2", 0.62, "See who I'm meeting next and what we last emailed about, right on my desktop."),
        Idea(.money, "Invoice Day", "doc.richtext", 0.55, "Turn the client hours in my calendar into invoices, and know which are still unpaid."),
        Idea(.work, "Shop Answers", "bubble.left.and.text.bubble.right", 0.4, "Answer “Do you ship abroad?” for the hundredth time with one keystroke."),
        Idea(.play, "Detective Case", "magnifyingglass", 0.66, "My own detective game, with a new mystery and new suspects every time."),

        Idea(.work, "Job Hunt", "briefcase", 0.58, "Keep track of every job I've applied for, and follow up when they go quiet."),
        Idea(.work, "Marking Pile", "pencil.and.list.clipboard", 0.3, "Get a first pass on thirty essays, marked against my own rubric."),
        Idea(.home, "Bin Day", "trash", 0.33, "Never miss bin day again: which bins go out tonight, right on my desktop."),
        Idea(.home, "Pickup Guard", "figure.and.child.holdinghands", 0.03, "Warn me the moment a meeting lands on school pickup."),
        Idea(.money, "Tax Folder", "tray.full", 0.45, "Gather the receipts scattered across my Mail and Downloads before tax time."),
        Idea(.play, "Tiny Town", "house.and.flag", 0.22, "A little town of my own, whose people live their lives while I build it."),

        Idea(.work, "Waiting On You", "envelope.badge", 0.6, "Show me who's still waiting on an answer from me, and since when."),
        Idea(.money, "Club Dues", "person.3", 0.9, "Know who's paid this season's club dues, and nudge the rest kindly."),
        Idea(.everyday, "Due Dates", "graduationcap", 0.7, "Every deadline this term, counting down on my desktop."),
        Idea(.work, "One-on-Ones", "person.2", 0.5, "Remember what I meant to raise with each person on my team."),
        Idea(.everyday, "Lost Thread", "doc.text.magnifyingglass", 0.38, "Find that file someone sent me just by describing it."),
        Idea(.play, "Desk Pet", "pawprint", 0.1, "A little pet that lives in my menu bar and is happy to see me."),

        Idea(.home, "Kids Today", "figure.2.and.child.holdinghands", 0.95, "See which kid needs to be where today, without opening three calendars."),
        Idea(.everyday, "Busywork", "cursorarrow.motionlines", 0.66, "Do the copy-this-into-that chore between my apps while I watch."),
        Idea(.work, "Parent Emails", "pencil.line", 0.14, "Help me write the tricky email to a parent: kind, but clear."),
        Idea(.everyday, "Photo Dump", "photo.stack", 0.8, "Sort last weekend's 300 photos into folders by day and place."),
        Idea(.work, "Where It Went", "chart.pie", 0.35, "Show me where my week's hours actually went, client by client."),
        Idea(.health, "Habit Garden", "leaf", 0.25, "A little garden that grows as I keep my daily habits."),

        Idea(.money, "Bills Due", "creditcard", 0.48, "Warn me about bills coming due before the late fees hit."),
        Idea(.money, "Free Trials", "clock.badge.exclamationmark", 0.0, "Catch free trials before they quietly turn into charges."),
        Idea(.work, "Friday Wrap-Up", "flag.checkered", 0.2, "Have my week's wins written up for the team by Friday at four."),
        Idea(.everyday, "Exam Cards", "rectangle.on.rectangle.angled", 0.78, "Turn my lecture slides into flashcards for Friday's exam."),
        Idea(.home, "Birthday Radar", "gift", 0.92, "Remind me of birthdays two weeks out, with the gift ideas I saved."),
        Idea(.play, "Kids' Stories", "moon.stars", 0.76, "A new bedtime story every night, starring my kid's favorite toy."),
        Idea(.health, "Stretch Break", "figure.cooldown", 0.3, "Get me off this chair every hour with a quick stretch I'll actually do."),
        Idea(.health, "Week of Dinners", "fork.knife", 0.1, "Plan the week's dinners around what we like, with one shopping list."),
        Idea(.health, "Home Workouts", "figure.strengthtraining.traditional", 0.02, "A few weeks of workouts with just the gear I have at home."),
        Idea(.money, "Spending Check", "chart.bar.xaxis", 0.42, "See where my money actually went this month, from my bank's export."),
        Idea(.money, "Savings Jar", "banknote", 0.36, "Watch my holiday fund fill up, a little jar on my desktop."),
    ]

    /// The same for an iPhone or iPad app: a moment on the go that a phone handles and a Mac doesn't (the
    /// camera, where you are, the motion sensors, a quick tap with one hand), mixed the same way, six to a page.
    static let phonePool: [Idea] = [
        Idea(.everyday, "Where I Parked", "car", 0.55, "Remember where I parked, with the level, the row and a photo, in one tap."),
        Idea(.home, "Droopy Plant", "leaf.circle", 0.32, "Work out what my droopy houseplant is missing from one photo."),
        Idea(.work, "Shelf Count", "shippingbox", 0.08, "Snap a shelf in my shop and see what I need to reorder."),
        Idea(.money, "Mileage Log", "road.lanes", 0.45, "Log every drive to a client, so tax time takes minutes."),
        Idea(.home, "Hang It Straight", "level", 0.15, "Hang a picture frame straight on the first try."),
        Idea(.play, "Word Ladder", "textformat.abc", 0.76, "A new word puzzle every day, and a streak to keep going."),

        Idea(.home, "Night Feeds", "moon.zzz", 0.7, "Track night feeds one-handed at 3am: which side, how long, and when."),
        Idea(.health, "Fridge Dinner", "refrigerator", 0.05, "Make tonight's dinner out of whatever's left in my fridge."),
        Idea(.money, "Bill by Dish", "fork.knife.circle", 0.4, "Split the restaurant bill by who actually had what."),
        Idea(.work, "Head Count", "checklist", 0.62, "Count thirty kids onto the bus on a school trip, one tap each."),
        Idea(.health, "Between Sets", "dumbbell", 0.0, "Log a set in two taps before my rest is up."),
        Idea(.health, "Step Quest", "figure.walk", 0.25, "Turn my daily walks into an adventure across made-up lands."),

        Idea(.everyday, "Menu Abroad", "character.bubble", 0.58, "Point at a menu abroad and know exactly what I'm ordering."),
        Idea(.everyday, "Trail Back", "location.north.line", 0.35, "Point me back to the car when the trail splits."),
        Idea(.home, "House Viewings", "house", 0.9, "Keep ten flat viewings straight, with photos and notes for each."),
        Idea(.work, "Club Check-In", "person.crop.circle.badge.checkmark", 0.5, "See who came to club tonight, and spot who's drifted away."),
        Idea(.everyday, "Walk Thoughts", "mic", 0.14, "Catch the ideas I have on walks: said once, sorted for me."),
        Idea(.play, "Tilt Maze", "circle.grid.cross", 0.85, "A marble maze I play by tilting my phone."),
    ]

    /// Mac and iPhone ideas in turn: a new app's kind is worked out from what's asked for (Store.chooseKind),
    /// so the ideas are for either.
    static let mixed: [Idea] = (0..<max(pool.count, phonePool.count)).flatMap { index in
        [pool.indices.contains(index) ? pool[index] : nil, phonePool.indices.contains(index) ? phonePool[index] : nil].compactMap { $0 }
    }

    /// Six at a time, one of each kind, each kind's ideas in turn and starting over at its end.
    static func page(_ index: Int) -> [Idea] {
        Idea.Kind.allCases.compactMap { kind in
            let ofKind = mixed.filter { $0.kind == kind }
            return ofKind.isEmpty ? nil : ofKind[index % ofKind.count]
        }
    }

    /// Six for a new app's empty chat, one of each kind. Until the person has an app, the first page, chosen to
    /// be a good first look; after that a random one of each kind, so the chat keeps turning up ones they
    /// haven't seen, leaving out any they've already made (by name).
    static func starters(made names: [String]) -> [Idea] {
        guard !names.isEmpty else { return page(0) }
        let made = Set(names.map { $0.lowercased() })
        return Idea.Kind.allCases.compactMap { kind in
            mixed.filter { $0.kind == kind && !made.contains($0.title.lowercased()) }.randomElement()
        }
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
                  let blurb = try? invented.value(String.self, forProperty: "blurb") else { return nil }
            let title = named.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !title.isEmpty, !seen.contains(title), !blurb.isEmpty else { return nil }
            // A made-up symbol name would draw nothing.
            let wanted = (try? invented.value(String.self, forProperty: "symbol")) ?? ""
            let symbol = NSImage(systemSymbolName: wanted, accessibilityDescription: nil) == nil ? "sparkles" : wanted
            let hue = Double(abs(title.hashValue) % 100) / 100
            return Idea(.everyday, title, symbol, hue, blurb)
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
