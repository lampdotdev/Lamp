import Foundation

/// A starter shelf of about twenty bottles, so the shelf is never bare on first open. Swap in your own any time.
enum Seed {
    private struct S {
        var name: String, maker: String, peppers: [String], family: FlavorFamily, heat: Double
        var tastes: String, tag: String
        /// Its cut-out photo in Assets/Bottles.
        var photo: String
        var rating: Int?, daysAgo: Double, lastUsedDaysAgo: Double
        var retiredDaysAgo: Double? = nil, verdict: String? = nil
        var ingredients = ""
    }

    private static let samples: [S] = [
        // Fruity & tropical
        S(name: "Marie Sharp's Fiery Hot", maker: "Marie Sharp's", peppers: ["habanero"], family: .fruity, heat: 7,
          tastes: "Carrot-sweet Belizean habanero, bright and bold", tag: "the reliable one", photo: "marie-sharp-s-fiery-hot",
          rating: 5, daysAgo: 55, lastUsedDaysAgo: 2, ingredients: "Habanero, carrots, onions, lime juice, vinegar, garlic, salt"),
        S(name: "Queen Majesty Scotch Bonnet & Ginger", maker: "Queen Majesty", peppers: ["scotch bonnet"], family: .fruity, heat: 7,
          tastes: "Ginger zing and scotch bonnet sunshine", tag: "dumplings. trust me.", photo: "queen-majesty-scotch-bonnet-ginger",
          rating: nil, daysAgo: 45, lastUsedDaysAgo: 38),
        S(name: "Los Calientes Rojo", maker: "Hot Ones", peppers: ["red habanero", "red jalapeño"], family: .fruity, heat: 5,
          tastes: "Roasted red pepper and apricot warmth", tag: "pizza night", photo: "los-calientes-rojo",
          rating: 4, daysAgo: 35, lastUsedDaysAgo: 4),
        S(name: "West Indian Hot Pepper", maker: "Encona", peppers: ["scotch bonnet"], family: .fruity, heat: 7,
          tastes: "Thick, mustardy scotch bonnet with island swagger", tag: "jerk chicken's best mate", photo: "encona-west-indian-hot-pepper",
          rating: 4, daysAgo: 21, lastUsedDaysAgo: 6),
        S(name: "Ghost Pepper", maker: "Melinda's", peppers: ["ghost pepper"], family: .fruity, heat: 9,
          tastes: "Fruity at first, then a slow, serious burn", tag: "sign the waiver", photo: "melinda-s-ghost-pepper",
          rating: 4, daysAgo: 30, lastUsedDaysAgo: 9),
        // Fermented & funky
        S(name: "Sriracha", maker: "Huy Fong Foods", peppers: ["red jalapeño"], family: .fermented, heat: 3,
          tastes: "Garlicky, a little sweet, gently funky", tag: "pho & leftover rice", photo: "sriracha",
          rating: 3, daysAgo: 60, lastUsedDaysAgo: 3),
        S(name: "Gochujang Hot Sauce", maker: "Mother-in-Law's", peppers: ["Korean red chili"], family: .fermented, heat: 4,
          tastes: "Deep fermented chili paste with garlic, savory-sweet", tag: "fried rice wants this", photo: "gochujang-hot-sauce",
          rating: 4, daysAgo: 50, lastUsedDaysAgo: 34),
        S(name: "Sriracha", maker: "Yellowbird", peppers: ["red jalapeño"], family: .fermented, heat: 4,
          tastes: "Brighter, fruitier sriracha with real garlic", tag: "the upgrade", photo: "yellowbird-sriracha",
          rating: 5, daysAgo: 18, lastUsedDaysAgo: 1),
        // Smoky
        S(name: "Chipotle", maker: "Cholula", peppers: ["chipotle", "arbol"], family: .smoky, heat: 3,
          tastes: "Gentle smoke, earthy and easygoing", tag: "breakfast burritos", photo: "cholula-chipotle",
          rating: 3, daysAgo: 70, lastUsedDaysAgo: 9),
        // Garlic & savory
        S(name: "Drunken Garlic Black Bean", maker: "Secret Aardvark", peppers: ["habanero"], family: .garlicky, heat: 5,
          tastes: "Black bean, roasted garlic and a habanero nudge", tag: "steak, then more steak", photo: "drunken-garlic",
          rating: 4, daysAgo: 28, lastUsedDaysAgo: 12),
        S(name: "Habanero", maker: "Secret Aardvark", peppers: ["habanero"], family: .garlicky, heat: 6,
          tastes: "Roasted tomato, garlic and habanero, a bit Caribbean", tag: "eggs, every time", photo: "secret-aardvark-habanero",
          rating: 5, daysAgo: 70, lastUsedDaysAgo: 2),
        // Green & herby
        S(name: "Green Pepper", maker: "Cholula", peppers: ["jalapeño", "poblano"], family: .green, heat: 2,
          tastes: "Mild, tangy green chile", tag: "for guests", photo: "cholula-green-pepper",
          rating: 2, daysAgo: 80, lastUsedDaysAgo: 50),
        S(name: "Green Habanero", maker: "Marie Sharp's", peppers: ["green habanero"], family: .green, heat: 6,
          tastes: "Grassy, bright, sneakily hot", tag: "fish tacos", photo: "marie-sharp-s-green-habanero",
          rating: 4, daysAgo: 42, lastUsedDaysAgo: 5),
        S(name: "Serrano", maker: "Yellowbird", peppers: ["serrano"], family: .green, heat: 4,
          tastes: "Fresh serrano, lime and cilantro snap", tag: "guac's secret", photo: "yellowbird-serrano",
          rating: 4, daysAgo: 33, lastUsedDaysAgo: 7),
        S(name: "Jalapeño", maker: "Yellowbird", peppers: ["jalapeño"], family: .green, heat: 3,
          tastes: "Bright green jalapeño, tangy and clean", tag: "nachos, obviously", photo: "yellowbird-jalape-o",
          rating: 3, daysAgo: 26, lastUsedDaysAgo: 15),
        // Chili crisp & oils
        S(name: "Spicy Chili Crisp", maker: "Lao Gan Ma", peppers: ["chili"], family: .crunchy, heat: 3,
          tastes: "Crispy shallot and chili crunch", tag: "noodles at midnight", photo: "spicy-chili-crisp",
          rating: 5, daysAgo: 48, lastUsedDaysAgo: 1),
        S(name: "La-Yu Chili Oil", maker: "Sun Luck", peppers: ["chili"], family: .crunchy, heat: 4,
          tastes: "Toasty sesame oil with a clean chili sting", tag: "dumpling dip", photo: "chili-oil",
          rating: 3, daysAgo: 90, lastUsedDaysAgo: 20),
        // Sweet & sticky
        S(name: "Hot Honey", maker: "Mike's Hot Honey", peppers: ["chili"], family: .sweet, heat: 2,
          tastes: "Honey with a chili kick", tag: "pizza crusts & fried chicken", photo: "hot-honey",
          rating: 4, daysAgo: 65, lastUsedDaysAgo: 8),
        S(name: "Sweet Chili Sauce", maker: "Mae Ploy", peppers: ["red chili"], family: .sweet, heat: 1,
          tastes: "Sticky, garlicky, more sweet than hot", tag: "spring rolls only", photo: "sweet-chili-sauce",
          rating: 3, daysAgo: 110, lastUsedDaysAgo: 25),
        // Vinegar-forward
        S(name: "Original Red", maker: "Tabasco", peppers: ["tabasco"], family: .vinegary, heat: 4,
          tastes: "Sharp vinegar, thin heat", tag: "emergency only", photo: "original-red",
          rating: 1, daysAgo: 200, lastUsedDaysAgo: 120),
        S(name: "Original", maker: "Cholula", peppers: ["arbol", "piquin"], family: .vinegary, heat: 3,
          tastes: "Earthy, peppery and easy on the vinegar", tag: "huevos rancheros", photo: "cholula-original",
          rating: 3, daysAgo: 140, lastUsedDaysAgo: 11),
        S(name: "Louisiana Hot Sauce", maker: "Louisiana", peppers: ["cayenne"], family: .vinegary, heat: 3,
          tastes: "Thin, tangy cayenne, gumbo's old friend", tag: "wing night only", photo: "louisiana-hot-sauce",
          rating: 2, daysAgo: 150, lastUsedDaysAgo: 60),
        S(name: "Salsa Picante", maker: "Tapatío", peppers: ["red chili"], family: .vinegary, heat: 3,
          tastes: "Garlicky, peppery, built for chips", tag: "popcorn. try it.", photo: "tapat-o",
          rating: 3, daysAgo: 95, lastUsedDaysAgo: 14),
        // Finished
        S(name: "Hotter Hot Sauce", maker: "Texas Pete", peppers: ["cayenne"], family: .vinegary, heat: 4,
          tastes: "Vinegar first, a little more heat after", tag: "", photo: "texas-pete-hotter",
          rating: 2, daysAgo: 120, lastUsedDaysAgo: 30, retiredDaysAgo: 30, verdict: "fine on chips, that's it"),
        S(name: "Hot Sauce", maker: "Red Rooster", peppers: ["cayenne"], family: .vinegary, heat: 3,
          tastes: "Tangy Louisiana cayenne", tag: "", photo: "red-rooster",
          rating: 3, daysAgo: 160, lastUsedDaysAgo: 40, retiredDaysAgo: 40, verdict: "a solid backup"),
        S(name: "Da Bomb Beyond Insanity", maker: "Da Bomb", peppers: ["habanero", "capsaicin extract"], family: .vinegary, heat: 10,
          tastes: "Chemical pain, zero joy", tag: "", photo: "da-bomb-beyond-insanity",
          rating: 1, daysAgo: 100, lastUsedDaysAgo: 95, retiredDaysAgo: 95, verdict: "never again"),
    ]

    /// Fills an empty shelf once. Never touches a shelf that has had bottles.
    @MainActor static func bottles() -> [Bottle] {
        let now = Date()
        func ago(_ days: Double) -> Date { now.addingTimeInterval(-days * 86400) }
        return samples.map { s in
            var b = Bottle(name: s.name, maker: s.maker, peppers: s.peppers, ingredients: s.ingredients, tastes: s.tastes,
                           heat: s.heat, family: s.family.rawValue, tag: s.tag, rating: s.rating,
                           addedAt: ago(s.daysAgo), lastUsedAt: ago(s.lastUsedDaysAgo),
                           retiredAt: s.retiredDaysAgo.map(ago), verdict: s.verdict, imageName: shippedPhoto(s.photo))
            // Out of ten now; a little spread so not every favorite is a flat 10.
            b.stars = s.rating.map { max(1, $0 * 2 - (s.name.count % 3 == 0 ? 1 : 0)) }
            b.rating = nil
            // Its photo comes with the app, so nothing is looked up for it.
            b.labelTried = true
            return b
        }
    }

    /// Copies a sample bottle's photo (Assets/Bottles) to where bottle pictures are kept; a painted bottle without one.
    private static func shippedPhoto(_ name: String) -> String {
        guard let source = LampAssets.url("Bottles/\(name).png") else { return "style:woozy" }
        let file = "sample-\(name).png"
        let target = BottleImages.folder.appendingPathComponent(file)
        try? FileManager.default.removeItem(at: target)
        do { try FileManager.default.copyItem(at: source, to: target) } catch { return "style:woozy" }
        return file
    }
}
