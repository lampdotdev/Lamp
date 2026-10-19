import Foundation

/// A starter shelf of about twenty bottles, so the shelf is never bare on first open. Swap in your own any time.
enum Seed {
    private struct S {
        var name: String, maker: String, peppers: [String], family: FlavorFamily, heat: Double
        var tastes: String, tag: String, style: String
        var level: Double, rating: Int?, daysAgo: Double, lastUsedDaysAgo: Double
        var retiredDaysAgo: Double? = nil, verdict: String? = nil
        var ingredients = ""
    }

    private static let samples: [S] = [
        // Fruity & tropical
        S(name: "Melinda's Mango Habanero", maker: "Melinda's", peppers: ["habanero"], family: .fruity, heat: 6,
          tastes: "Ripe mango up front, habanero glow behind", tag: "eggs, tacos, life", style: "woozy",
          level: 0.62, rating: 5, daysAgo: 40, lastUsedDaysAgo: 1, ingredients: "Mango, habanero, carrots, lime juice, garlic, salt"),
        S(name: "Marie Sharp's Fiery Hot", maker: "Marie Sharp's", peppers: ["habanero"], family: .fruity, heat: 7,
          tastes: "Carrot-sweet Belizean habanero, bright and bold", tag: "the reliable one", style: "dasher",
          level: 0.35, rating: 5, daysAgo: 55, lastUsedDaysAgo: 2, ingredients: "Habanero, carrots, onions, lime juice, vinegar, garlic, salt"),
        S(name: "Walkerswood Scotch Bonnet", maker: "Walkerswood", peppers: ["scotch bonnet"], family: .fruity, heat: 7,
          tastes: "Floral Jamaican scotch bonnet, proper island heat", tag: "jerk chicken's best mate", style: "woozy",
          level: 0.8, rating: 4, daysAgo: 21, lastUsedDaysAgo: 6),
        S(name: "Yellowbird Habanero", maker: "Yellowbird", peppers: ["habanero"], family: .fruity, heat: 6,
          tastes: "Carrot, tangerine and habanero, clean and fresh", tag: "bright & clean", style: "squeeze",
          level: 0.12, rating: 4, daysAgo: 30, lastUsedDaysAgo: 0.5),
        S(name: "Queen Majesty Scotch Bonnet & Ginger", maker: "Queen Majesty", peppers: ["scotch bonnet"], family: .fruity, heat: 7,
          tastes: "Ginger zing and scotch bonnet sunshine", tag: "dumplings. trust me.", style: "woozy",
          level: 0.9, rating: nil, daysAgo: 45, lastUsedDaysAgo: 38),
        S(name: "Los Calientes Rojo", maker: "Hot Ones", peppers: ["red habanero", "red jalapeño"], family: .fruity, heat: 5,
          tastes: "Roasted red pepper and apricot warmth", tag: "pizza night", style: "dasher",
          level: 0.55, rating: 4, daysAgo: 35, lastUsedDaysAgo: 4),
        // Fermented & funky
        S(name: "Sriracha", maker: "Huy Fong Foods", peppers: ["red jalapeño"], family: .fermented, heat: 3,
          tastes: "Garlicky, a little sweet, gently funky", tag: "pho & leftover rice", style: "squeeze",
          level: 0.5, rating: 3, daysAgo: 60, lastUsedDaysAgo: 3),
        S(name: "Gochujang Hot Sauce", maker: "Mother-in-Law's", peppers: ["Korean red chili"], family: .fermented, heat: 4,
          tastes: "Deep fermented chili paste, savory-sweet", tag: "fried rice wants this", style: "woozy",
          level: 0.7, rating: 4, daysAgo: 50, lastUsedDaysAgo: 34),
        // Smoky
        S(name: "Cholula Chipotle", maker: "Cholula", peppers: ["chipotle", "arbol"], family: .smoky, heat: 3,
          tastes: "Gentle smoke, earthy and easygoing", tag: "breakfast burritos", style: "dasher",
          level: 0.45, rating: 3, daysAgo: 70, lastUsedDaysAgo: 9),
        // Garlic & savory
        S(name: "Garlic Reaper", maker: "TorchBearer Sauces", peppers: ["Carolina Reaper"], family: .garlicky, heat: 9,
          tastes: "Roasted garlic, then a very rude reaper", tag: "one drop. ONE.", style: "woozy",
          level: 0.88, rating: 4, daysAgo: 90, lastUsedDaysAgo: 41),
        S(name: "Black Garlic Carolina Reaper", maker: "Bravado Spice", peppers: ["Carolina Reaper"], family: .garlicky, heat: 9,
          tastes: "Molasses-dark black garlic and serious heat", tag: "steak, carefully", style: "dasher",
          level: 0.75, rating: 4, daysAgo: 28, lastUsedDaysAgo: 12),
        // Green & herby
        S(name: "Green Habanero", maker: "El Yucateco", peppers: ["green habanero"], family: .green, heat: 7,
          tastes: "Grassy, bright, sneakily hot", tag: "fish tacos", style: "dasher",
          level: 0.55, rating: 4, daysAgo: 42, lastUsedDaysAgo: 5),
        S(name: "Green Pepper", maker: "Cholula", peppers: ["jalapeño", "poblano"], family: .green, heat: 2,
          tastes: "Mild, tangy green chile", tag: "for guests", style: "dasher",
          level: 0.85, rating: 2, daysAgo: 80, lastUsedDaysAgo: 50),
        // Chili crisp & oils
        S(name: "Sichuan Chili Crisp", maker: "Fly By Jing", peppers: ["erjingtiao", "facing heaven"], family: .crunchy, heat: 4,
          tastes: "Crunchy, numbing, deeply savory", tag: "on everything. sorry.", style: "jar",
          level: 0.38, rating: 5, daysAgo: 25, lastUsedDaysAgo: 1),
        S(name: "Spicy Chili Crisp", maker: "Lao Gan Ma", peppers: ["chili"], family: .crunchy, heat: 3,
          tastes: "Crispy shallot and chili crunch", tag: "noodles at midnight", style: "jar",
          level: 0.22, rating: 4, daysAgo: 48, lastUsedDaysAgo: 2),
        // Sweet & sticky
        S(name: "Hot Honey", maker: "Mike's Hot Honey", peppers: ["chili"], family: .sweet, heat: 2,
          tastes: "Honey with a chili kick", tag: "pizza crusts & fried chicken", style: "squeeze",
          level: 0.6, rating: 4, daysAgo: 65, lastUsedDaysAgo: 8),
        // Vinegar-forward
        S(name: "Original Red", maker: "Tabasco", peppers: ["tabasco"], family: .vinegary, heat: 4,
          tastes: "Sharp vinegar, thin heat", tag: "emergency only", style: "dasher",
          level: 0.9, rating: 1, daysAgo: 200, lastUsedDaysAgo: 120),
        S(name: "Frank's RedHot", maker: "Frank's", peppers: ["cayenne"], family: .vinegary, heat: 2,
          tastes: "Tangy cayenne, butter's best friend", tag: "wing night only", style: "woozy",
          level: 0.7, rating: 2, daysAgo: 150, lastUsedDaysAgo: 60),
        // Retired
        S(name: "Secret Aardvark Habanero", maker: "Secret Aardvark", peppers: ["habanero"], family: .fruity, heat: 6,
          tastes: "Roasted tomato and habanero, Caribbean-ish", tag: "", style: "woozy",
          level: 0, rating: 5, daysAgo: 70, lastUsedDaysAgo: 12, retiredDaysAgo: 12, verdict: "buy again"),
        S(name: "Valentina Extra Hot", maker: "Valentina", peppers: ["puya"], family: .vinegary, heat: 3,
          tastes: "Thick, tangy, chip-friendly", tag: "", style: "woozy",
          level: 0, rating: 3, daysAgo: 120, lastUsedDaysAgo: 30, retiredDaysAgo: 30, verdict: "fine on chips, that's it"),
        S(name: "Da Bomb Beyond Insanity", maker: "Da Bomb", peppers: ["habanero", "capsaicin extract"], family: .vinegary, heat: 10,
          tastes: "Chemical pain, zero joy", tag: "", style: "dasher",
          level: 0, rating: 1, daysAgo: 100, lastUsedDaysAgo: 95, retiredDaysAgo: 95, verdict: "never again"),
    ]

    /// What the taste map says about the shelf above, so it reads well before the AI has looked at anything.
    static let tasteMap = TasteMap(
        summary: "You're a habanero and scotch bonnet devotee, and mango, ginger and tangerine are your love language. Add a Sichuan crunch and a reaper-grade garlic habit, and vinegar-heavy bottles clearly don't get a seat at your table.",
        gaps: [Gap(family: "smoky", line: "only one gentle smoky bottle"),
               Gap(family: "fermented", line: "only two fermented bottles"),
               Gap(family: "sweet", line: "just one hot honey")])

    /// Fills an empty shelf once. Never touches a shelf that has had bottles.
    @MainActor static func bottles() -> [Bottle] {
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86400) }
        return samples.map { s in
            var b = Bottle(name: s.name, maker: s.maker, peppers: s.peppers, ingredients: s.ingredients, tastes: s.tastes,
                           heat: s.heat, family: s.family.rawValue, tag: s.tag, level: s.level, rating: s.rating,
                           addedAt: ago(s.daysAgo), lastUsedAt: ago(s.lastUsedDaysAgo),
                           retiredAt: s.retiredDaysAgo.map(ago), verdict: s.verdict, imageName: "style:" + s.style)
            // Out of ten now; a little spread so not every favorite is a flat 10.
            b.stars = s.rating.map { max(1, $0 * 2 - (s.name.count % 3 == 0 ? 1 : 0)) }
            b.rating = nil
            // Its drawing comes with the app, so the shelf opens finished, with nothing to look up or draw.
            if let art = shippedArt(for: s.name) {
                b.artName = art; b.artStyle = Illustrator.version; b.artTried = true; b.labelTried = true
            }
            return b
        }
    }

    /// Copies a sample bottle's drawing (Assets/Bottles, named after the bottle) to where bottle pictures are kept.
    private static func shippedArt(for name: String) -> String? {
        let slug = name.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted)
            .filter { !$0.isEmpty }.joined(separator: "-")
        guard let source = LampAssets.url("Bottles/\(slug).png") else { return nil }
        let file = "sample-\(slug).png"
        let target = BottleImages.folder.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: source, to: target) } catch { return nil }
        return file
    }
}
