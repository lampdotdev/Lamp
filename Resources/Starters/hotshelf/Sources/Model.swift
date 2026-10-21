import SwiftUI
import AppKit

/// Where a sauce sits on the shelf. Raw values are saved, so never rename them.
enum FlavorFamily: String, Codable, CaseIterable, Identifiable {
    case fruity, fermented, smoky, garlicky, green, crunchy, sweet, vinegary

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fruity: "fruity & tropical"
        case .fermented: "fermented & funky"
        case .smoky: "smoky"
        case .garlicky: "garlic & savory"
        case .green: "green & herby"
        case .crunchy: "chili crisp & oils"
        case .sweet: "sweet & sticky"
        case .vinegary: "vinegar-forward"
        }
    }

    /// What the AI is told each family means.
    var meaning: String {
        switch self {
        case .fruity: "fruit-led: mango, pineapple, papaya, passion fruit, citrus, habanero or scotch bonnet brightness"
        case .fermented: "fermented mash, lacto-fermented, aged, funky, sriracha-style, gochujang"
        case .smoky: "chipotle, smoked peppers, morita, ancho, smoked salt"
        case .garlicky: "garlic, onion, savory, umami, Louisiana-style garlic"
        case .green: "green chiles, jalapeño, serrano, tomatillo, herbs, salsa verde"
        case .crunchy: "chili crisp, chili oil, crunchy oil-based condiments"
        case .sweet: "sweet chili, honey, hot honey, sticky glazes"
        case .vinegary: "mostly vinegar and salt, like a classic Louisiana cayenne sauce"
        }
    }

    static func from(_ text: String) -> FlavorFamily {
        FlavorFamily(rawValue: text) ?? allCases.first { $0.title == text } ?? .fruity
    }
}

struct Usage: Codable, Equatable {
    var at: Date
    var from: Double
    var to: Double
}

struct Bottle: Codable, Identifiable, Equatable {
    var id: String = UUID().uuidString
    var name: String
    var maker: String = ""
    var peppers: [String] = []
    var ingredients: String = ""
    var tastes: String = ""
    /// 0 (none) to 10 (superhot).
    var heat: Double = 5
    var family: String = FlavorFamily.fruity.rawValue
    /// The handwritten tag hanging under it.
    var tag: String = ""
    /// No longer shown: kept so older saved bottles still load.
    var level: Double = 1
    var rating: Int? = nil
    var addedAt: Date = Date()
    var lastUsedAt: Date? = nil
    var retiredAt: Date? = nil
    var verdict: String? = nil
    var imageName: String? = nil
    var barcode: String? = nil
    var usage: [Usage] = []

    var flavor: FlavorFamily { FlavorFamily.from(family) }
    var isRetired: Bool { retiredAt != nil }
    var lastTouched: Date { lastUsedAt ?? addedAt }

    /// How much you like it, 1–10 stars. Older bottles were rated out of 5.
    var stars: Int? = nil
    /// Whether the app has already looked for a real label photo for it.
    var labelTried: Bool? = nil

    var score: Int? { stars ?? rating.map { min(10, $0 * 2) } }
    /// How hot, 1–10 peppers.
    var intensity: Int { max(1, min(10, Int(heat.rounded()))) }
    var hasPhoto: Bool { imageName.map { !$0.hasPrefix("style:") } ?? false }
}

struct Pick: Equatable {
    var bottleID: String
    var dish: String
    var why: String
}

func heatColor(_ heat: Double) -> Color {
    let t = min(max(heat / 10, 0), 1)
    let stops: [(Double, Double, Double)] = [(1.0, 0.94, 0.62), (1.0, 0.72, 0.2), (0.93, 0.33, 0.1), (0.55, 0.03, 0.05)]
    let scaled = t * Double(stops.count - 1)
    let i = min(Int(scaled), stops.count - 2)
    let f = scaled - Double(i)
    let a = stops[i], b = stops[i + 1]
    return Color(red: a.0 + (b.0 - a.0) * f, green: a.1 + (b.1 - a.1) * f, blue: a.2 + (b.2 - a.2) * f)
}

func heatWord(_ heat: Double) -> String {
    switch heat {
    case ..<2: "gentle"
    case ..<4: "mild"
    case ..<6: "medium"
    case ..<8: "hot"
    case ..<9.5: "very hot"
    default: "superhot"
    }
}

let defaultTasteProfile = "I put sauce on nearly everything. I love fruity, fermented heat: habanero, scotch bonnet, anything with mango or smoke. I hate sauces that taste mostly of vinegar."

enum Hand {
    static func font(_ size: CGFloat) -> Font { .custom("Bradley Hand", size: size).weight(.bold) }
}

@MainActor
final class Shelf: ObservableObject {
    static let shared = Shelf()

    @Published private(set) var bottles: [Bottle] = []
    @Published var pick: Pick?
    @Published var picking = false
    @Published var pickError: String?
    @Published var showAdd = false
    @Published var lifted: String?
    /// The bottle whose card is open over the shelf, if any.
    @Published var openID: String?
    @Published var openRetiring = false
    @Published var confirmDeleteID: String?

    func open(_ id: String, retiring: Bool = false) {
        openRetiring = retiring
        withAnimation(.spring(response: 0.45, dampingFraction: 0.72)) { openID = id }
    }

    func close() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.9)) { openID = nil }
    }

    private let store = LampStore.collection("bottles", of: Bottle.self)

    init() {
        bottles = store.all(orderBy: "addedAt")
        seedIfNeeded()
        // The starter tag from when the shelf tracked fill levels.
        if let i = bottles.firstIndex(where: { $0.tag == "almost gone, restock!" }) {
            bottles[i].tag = "bright & clean"
            store.put(bottles[i])
        }
        Nudges.reschedule(bottles)
    }

    /// A starter shelf, once, the first time it's empty.
    func seedIfNeeded() {
        guard bottles.isEmpty, !UserDefaults.standard.bool(forKey: "shelf.seeded") else { return }
        UserDefaults.standard.set(true, forKey: "shelf.seeded")
        let starters = Seed.bottles()
        store.put(starters)
        bottles = starters
        changed()
    }

    var active: [Bottle] { bottles.filter { !$0.isRetired } }
    var retired: [Bottle] { bottles.filter(\.isRetired).sorted { ($0.retiredAt ?? .distantPast) > ($1.retiredAt ?? .distantPast) } }

    func bottle(_ id: String) -> Bottle? { bottles.first { $0.id == id } }

    // MARK: Changes

    func add(_ bottle: Bottle) {
        var bottle = bottle
        if self.bottle(bottle.id) != nil { bottle.id = UUID().uuidString }
        bottles.append(bottle)
        store.put(bottle)
        changed()
        if !bottle.hasPhoto { LabelFinder.shared.find(bottle.id) }
    }

    func update(_ bottle: Bottle) {
        guard let i = bottles.firstIndex(where: { $0.id == bottle.id }) else { return }
        bottles[i] = bottle
        store.put(bottle)
        changed()
    }

    func binding(_ id: String) -> Binding<Bottle> {
        Binding(get: { self.bottle(id) ?? Bottle(name: "") }, set: { self.update($0) })
    }

    func retire(_ id: String, verdict: String) {
        guard var b = bottle(id) else { return }
        b.retiredAt = Date()
        b.lastUsedAt = Date()
        b.verdict = verdict.trimmingCharacters(in: .whitespacesAndNewlines)
        withAnimation(.spring(duration: 0.6)) { update(b) }
    }

    func unretire(_ id: String) {
        guard var b = bottle(id) else { return }
        b.retiredAt = nil
        withAnimation(.spring(duration: 0.6)) { update(b) }
    }

    func delete(_ id: String) {
        if let name = bottle(id)?.imageName { BottleImages.remove(name) }
        bottles.removeAll { $0.id == id }
        store.delete(id)
        if pick?.bottleID == id { pick = nil; lifted = nil }
        changed()
    }

    private func changed() {
        Nudges.reschedule(bottles)
    }

    // MARK: Learning

    var topRated: [Bottle] {
        bottles.filter { $0.score != nil }.sorted { ($0.score ?? 0) > ($1.score ?? 0) }
    }

    private func summary(_ b: Bottle) -> [String: Any] {
        var d: [String: Any] = [
            "id": b.id, "name": b.name, "maker": b.maker, "family": b.flavor.title,
            "peppers": b.peppers.joined(separator: ", "), "intensity_peppers_of_10": b.intensity,
            "tastes": b.tastes,
        ]
        if let r = b.score { d["my_stars_of_10"] = r }
        if let used = b.lastUsedAt { d["last_used"] = LampAI.when(used) }
        if let v = b.verdict { d["my_verdict"] = v }
        if b.isRetired { d["finished"] = true }
        return d
    }

    private var profile: String {
        UserDefaults.standard.string(forKey: "tasteProfile") ?? defaultTasteProfile
    }

    // MARK: Tonight

    func choose(for dish: String, avoiding: [String] = []) async throws -> Pick {
        let options = active.filter { !avoiding.contains($0.id) }
        guard !options.isEmpty else {
            throw LampAI.Failure(message: avoiding.isEmpty ? "The shelf is empty. Bring a bottle home first." : "That's every bottle on the shelf. Go with your gut.")
        }
        struct Answer: Decodable { let id: String; let why: String }
        let data = try JSONSerialization.data(withJSONObject: options.map(summary), options: [.prettyPrinted])
        let answer = try await LampAI.ask(
            "Tonight I'm cooking: \(dish). Pick the ONE bottle from my shelf (in the data) that suits it best, " +
            "weighing flavor match first, then my star ratings, the intensity that suits the dish, and my taste. Nudge me toward " +
            "something I haven't used lately when it's a close call. Explain why in one or two warm, slightly cheeky sentences " +
            "like a friend who cooks a lot (no more than 35 words, don't repeat the dish name verbatim). " +
            #"Reply as JSON: {"id": "<bottle id>", "why": "..."}"#,
            data: String(decoding: data, as: UTF8.self),
            system: "You know this person's kitchen. Their taste: \(profile)",
            as: Answer.self)
        let id = options.contains { $0.id == answer.id } ? answer.id : options[0].id
        return Pick(bottleID: id, dish: dish, why: answer.why)
    }

    func pickForTonight(_ dish: String, another: Bool = false) {
        let dish = dish.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !dish.isEmpty, !picking else { return }
        let avoiding = another ? (pick.map { [$0.bottleID] } ?? []) + skipped : []
        if another, let p = pick { skipped.append(p.bottleID) } else { skipped = [] }
        picking = true
        pickError = nil
        withAnimation(.spring(duration: 0.5)) { lifted = nil }
        Task {
            defer { picking = false }
            do {
                let result = try await choose(for: dish, avoiding: avoiding)
                withAnimation(.spring(response: 0.55, dampingFraction: 0.62)) {
                    pick = result
                    lifted = result.bottleID
                }
            } catch {
                pickError = error.localizedDescription
            }
        }
    }
    private var skipped: [String] = []

    func putBack() {
        withAnimation(.spring(response: 0.5, dampingFraction: 0.75)) {
            lifted = nil
            pick = nil
        }
        skipped = []
    }
}
