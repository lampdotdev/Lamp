import SwiftUI

/// The shelf's whole mood in one place: its words, colors, type, light and how its shelves are named. Everything
/// on the shelf screen is drawn from `Look.current`, so making the shelf about something else starts here, by
/// writing a new mood rather than nudging this one: `hotShelf` is loud, bold and hard-lit; `cellar` below is the
/// same shelf made quiet and elegant. APP.md says how to choose.
struct Look {
    /// The mood the app is in.
    static let current = Look.hotShelf

    // MARK: Words

    var title: String
    /// What the number under each bottle measures, and its symbol.
    var measure: String
    var measureSymbol: String
    /// The shelf of bottles that are done, and what the summary calls them.
    var finished: String
    /// The summary's last part, before the name of the bottle with the most of `measure`; nil leaves it out.
    var mostLine: String?
    var emptyTitle: String
    var emptyLine: String
    /// The question at the foot of the shelf, its symbol, and the button that answers it.
    var askPrompt: String
    var askSymbol: String
    var askButtonSymbol: String

    // MARK: Colour

    /// The set is one colour: the wall, and the shelves made of the same stuff or of something of their own.
    var wall: Color
    var shelfTop: Color
    var shelfBack: Color
    var shelfFront: Color
    var shelfUnder: Color
    /// Type on the wall, and the one accent (the measure's symbol, the ask bar's).
    var ink: Color
    var accent: Color
    var scheme: ColorScheme = .dark

    // MARK: Light

    /// Where the light comes from, as a point of the window: everything is lit from there and shades away from it.
    var light: UnitPoint
    /// How hard each bottle and shelf is shaded: 0 is flat, 1 is a single hard studio light.
    var contrast: Double
    /// How hard the dodge and burn over the whole picture is: 0 leaves it flat, 1 blows out the lit corner.
    var lightStrength: Double
    /// How far the light reaches across the window, as a share of its longer side: small is a spotlight.
    var reach: Double
    /// The shaft of light falling across the wall: 0 for none.
    var beam: Double
    /// The light's colour: white for a studio, warm for a candle or a lamp.
    var glow: (red: Double, green: Double, blue: Double) = (1, 1, 1)
    /// The wall's grain: 0 for smooth paint, 1 for a board you can feel.
    var grain: Double = 1

    // MARK: Type

    struct Typeface {
        var design: Font.Design = .default
        var width: Font.Width = .standard
        var weight: Font.Weight
        var tracking: CGFloat = 0
        var uppercase = false

        func font(_ size: CGFloat, weight: Font.Weight? = nil) -> Font {
            .system(size: size, weight: weight ?? self.weight, design: design).width(width)
        }
        func text(_ string: String) -> String { uppercase ? string.uppercased() : string }
    }

    /// The title and anything else that speaks up, and the title's size.
    var display: Typeface
    var titleSize: CGFloat
    /// The small type that supports it: the summary, the line under each bottle.
    var label: Typeface

    // MARK: Shelves

    enum ShelfNames {
        /// Painted big on the wall behind each shelf, in the display type, with the bottles in front: loud.
        case painted(size: CGFloat, color: Color, opacity: Double)
        /// A small line over each shelf's left end, in the label type: quiet, like a gallery's.
        case caption
    }
    var shelfNames: ShelfNames
    /// How tall a bottle stands on its shelf, and a finished one.
    var bottleHeight: CGFloat = 160
    var finishedHeight: CGFloat = 110

    func display(_ size: CGFloat) -> Font { display.font(size) }
    func label(_ size: CGFloat, weight: Font.Weight? = nil) -> Font { label.font(size, weight: weight) }
    func glow(_ amount: Double) -> Color { Color(red: glow.red * amount, green: glow.green * amount, blue: glow.blue * amount) }
}

extension Look {
    /// Hot sauce: one saturated red set under a single hard light, wide black type, and the shelves' names painted
    /// on the wall like a poster. Loud, edgy and a bit cheeky.
    static let hotShelf = Look(
        title: "The Hot Shelf",
        measure: "Heat", measureSymbol: "flame.fill",
        finished: "Finished", mostLine: "handle with care",
        emptyTitle: "Nothing hot yet.",
        emptyLine: "Snap a bottle or drop a photo here, and it gets read, lit and put in its place.",
        askPrompt: "What's cooking tonight?", askSymbol: "frying.pan", askButtonSymbol: "flame.fill",
        wall: Color(red: 0.80, green: 0.06, blue: 0.04),
        shelfTop: Color(red: 0.98, green: 0.2, blue: 0.1),
        shelfBack: Color(red: 0.52, green: 0.05, blue: 0.04),
        shelfFront: Color(red: 0.70, green: 0.05, blue: 0.04),
        shelfUnder: Color(red: 0.38, green: 0.02, blue: 0.03),
        ink: .white,
        accent: Color(red: 1.0, green: 0.78, blue: 0.2),
        light: UnitPoint(x: 0.12, y: -0.15), contrast: 0.85, lightStrength: 0.5, reach: 0.75, beam: 1,
        display: Typeface(width: .expanded, weight: .black, tracking: -0.5, uppercase: true), titleSize: 52,
        label: Typeface(width: .expanded, weight: .semibold, tracking: 1.6, uppercase: true),
        shelfNames: .painted(size: 52, color: .black, opacity: 0.22))

    /// Wine, as an example of a quiet mood: a dark oxblood cellar with walnut shelves under one warm light from
    /// above, no beam, a serif title in its own case, and the shelves named in small captions. Elegant, not edgy.
    static let cellar = Look(
        title: "The Cellar",
        measure: "Body", measureSymbol: "drop.fill",
        finished: "Opened", mostLine: nil,
        emptyTitle: "An empty cellar.",
        emptyLine: "Photograph a bottle or drop a picture here, and it's read and laid down in its place.",
        askPrompt: "What's for dinner?", askSymbol: "fork.knife", askButtonSymbol: "wineglass.fill",
        wall: Color(red: 0.16, green: 0.05, blue: 0.06),
        shelfTop: Color(red: 0.42, green: 0.27, blue: 0.18),
        shelfBack: Color(red: 0.17, green: 0.10, blue: 0.07),
        shelfFront: Color(red: 0.28, green: 0.17, blue: 0.11),
        shelfUnder: Color(red: 0.13, green: 0.07, blue: 0.05),
        ink: Color(red: 0.96, green: 0.92, blue: 0.84),
        accent: Color(red: 0.84, green: 0.68, blue: 0.42),
        light: UnitPoint(x: 0.5, y: -0.3), contrast: 0.7, lightStrength: 0.45, reach: 0.9, beam: 0,
        glow: (1, 0.72, 0.42), grain: 0.5,
        display: Typeface(design: .serif, weight: .regular, tracking: 0.3), titleSize: 46,
        label: Typeface(weight: .medium, tracking: 1.8, uppercase: true),
        shelfNames: .caption, bottleHeight: 170)
}

/// The illustrated look the dialogs and sheets still use.
enum Zine {
    static let pink = Color(red: 0.97, green: 0.73, blue: 0.79)
    static let pinkShadow = Color(red: 0.88, green: 0.56, blue: 0.66)
    static let red = Color(red: 0.91, green: 0.26, blue: 0.17)
    static let orange = Color(red: 0.95, green: 0.55, blue: 0.18)
    static let yellow = Color(red: 0.98, green: 0.78, blue: 0.27)
    static let teal = Color(red: 0.17, green: 0.68, blue: 0.69)
    static let navy = Color(red: 0.17, green: 0.19, blue: 0.47)
    static let cream = Color(red: 0.99, green: 0.95, blue: 0.86)
    static let wood = Color(red: 0.84, green: 0.42, blue: 0.24)
    static let woodDark = Color(red: 0.66, green: 0.29, blue: 0.17)
}
