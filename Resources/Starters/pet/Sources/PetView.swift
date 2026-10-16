import SwiftUI

// Everything about how the pet looks lives in this file: its moods, the accessories its streak earns, its
// colors, the big animated picture in the panel and the small face in the menu bar. To make it a cactus, a
// fish or a robot, redraw `PetFigure` (and `PetFaceGlyph` for the menu bar) and change the words in `PetMood`;
// nothing else in the app knows what the pet looks like.

/// How the pet feels, worked out by `PetModel.mood` from how full it is and the time of day.
enum PetMood {
    case happy, content, hungry, sleepy

    /// A few words for the panel, under the pet's name.
    var title: String {
        switch self {
        case .happy: "Happy and full"
        case .content: "Doing fine"
        case .hungry: "Hungry"
        case .sleepy: "Sleepy"
        }
    }

    /// A short line in the pet's voice, shown under the picture.
    var line: String {
        switch self {
        case .happy: "Best day ever. Thank you!"
        case .content: "A snack would be nice."
        case .hungry: "Tummy rumbling. Feed me a habit?"
        case .sleepy: "Zzz… see you in the morning."
        }
    }
}

/// What the pet wears for its streak of happy days. Each one is kept as the next is earned.
enum PetAccessory: Int, Comparable, CaseIterable {
    case none, flower, scarf, crown

    /// Happy days in a row it takes to earn each one.
    var daysNeeded: Int {
        switch self {
        case .none: 0
        case .flower: 3
        case .scarf: 7
        case .crown: 30
        }
    }

    var name: String {
        switch self {
        case .none: ""
        case .flower: "a flower"
        case .scarf: "a scarf"
        case .crown: "a crown"
        }
    }

    static func forStreak(_ streak: Int) -> PetAccessory {
        allCases.last { streak >= $0.daysNeeded } ?? .none
    }

    /// The next one to earn after a streak, if there's one left.
    static func next(after streak: Int) -> PetAccessory? {
        allCases.first { $0.daysNeeded > streak }
    }

    static func < (a: PetAccessory, b: PetAccessory) -> Bool { a.rawValue < b.rawValue }
}

/// The pet's colors. They read well on both the light and the dark panel, so there's one set.
enum PetLook {
    static let body = Color(red: 0.98, green: 0.71, blue: 0.77)
    static let bodyShade = Color(red: 0.93, green: 0.55, blue: 0.65)
    static let belly = Color(red: 1.0, green: 0.92, blue: 0.90)
    static let innerEar = Color(red: 0.96, green: 0.48, blue: 0.60)
    static let cheek = Color(red: 1.0, green: 0.42, blue: 0.55)
    static let face = Color(red: 0.24, green: 0.15, blue: 0.20)
    static let tongue = Color(red: 1.0, green: 0.45, blue: 0.52)
}

// MARK: - The big picture

/// The pet, alive: it breathes, blinks, wags when happy, dozes at night and bounces when it eats. Every
/// movement is worked out from the clock, so there's no animation state to keep in step.
struct PetView: View {
    let mood: PetMood
    let streak: Int
    /// When it last ate and what (an SF Symbol), for the bounce and the food falling into its mouth.
    var meal: (at: Date, symbol: String)?
    var size: CGFloat = 200

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30)) { context in
            PetFigure(mood: mood,
                      accessory: .forStreak(streak),
                      time: context.date.timeIntervalSinceReferenceDate,
                      sinceMeal: meal.map { context.date.timeIntervalSince($0.at) },
                      mealSymbol: meal?.symbol)
        }
        // Drawn in a 200-point square and scaled, so every position below is a plain number.
        .frame(width: 200, height: 200)
        // It grows a little with its streak, up to 6% bigger after a month.
        .scaleEffect(size / 200 * (1 + min(Double(streak), 30) / 500))
        .frame(width: size, height: size)
    }
}

/// One frame of the pet, in a 200-point square.
private struct PetFigure: View {
    let mood: PetMood
    let accessory: PetAccessory
    let time: TimeInterval
    let sinceMeal: TimeInterval?
    let mealSymbol: String?

    /// How long eating lasts: the hop, the chomping and the hearts.
    private let mealLength = 1.6
    private var eating: Double? { sinceMeal.flatMap { $0 >= 0 && $0 < mealLength ? $0 : nil } }

    private var breath: Double { sin(time * (mood == .sleepy ? 1.2 : 2.4)) * 0.025 }
    private var blinking: Bool { mood != .sleepy && (time + 1.3).truncatingRemainder(dividingBy: 4.2) < 0.14 }
    private var hop: Double {
        guard let eating, eating < 1.2 else { return 0 }
        return abs(sin(eating * .pi * 2.5)) * 22 * (1 - eating / 1.2)
    }

    var body: some View {
        ZStack {
            Ellipse().fill(.black.opacity(0.12))
                .frame(width: 120 - hop, height: 12).position(x: 100, y: 187)
            creature
                .scaleEffect(x: 1 - breath, y: 1 + breath, anchor: .bottom)
                .offset(y: -hop)
            moodExtras
            mealExtras
        }
        .frame(width: 200, height: 200)
    }

    private var creature: some View {
        ZStack {
            tail
            ear(x: 62, tilt: -14)
            ear(x: 138, tilt: 14)
            Ellipse()
                .fill(LinearGradient(colors: [PetLook.body, PetLook.bodyShade], startPoint: .top, endPoint: .bottom))
                .frame(width: 150, height: 128).position(x: 100, y: 112)
            Ellipse().fill(PetLook.belly).frame(width: 84, height: 54).position(x: 100, y: 142)
            foot(x: 74)
            foot(x: 126)
            cheeks
            eye(x: 77)
            eye(x: 123)
            mouth.position(x: 100, y: 124)
            if accessory >= .scarf { scarf }
            if accessory >= .flower { flower }
            if accessory >= .crown { crown }
        }
        .frame(width: 200, height: 200)
    }

    // MARK: Parts

    private var tail: some View {
        let wag = mood == .happy ? sin(time * 7) * 16 : sin(time * 1.5) * 4
        return Capsule().fill(PetLook.bodyShade)
            .frame(width: 16, height: 40)
            .rotationEffect(.degrees(58 + wag), anchor: .bottom)
            .position(x: 152, y: 142)
    }

    private func ear(x: CGFloat, tilt: Double) -> some View {
        ZStack {
            EarShape().fill(PetLook.body).frame(width: 46, height: 52)
            EarShape().fill(PetLook.innerEar).frame(width: 24, height: 30).offset(y: 8)
        }
        .rotationEffect(.degrees(tilt + (mood == .sleepy ? tilt * 0.8 : 0)), anchor: .bottom)
        .position(x: x, y: 58)
    }

    private func foot(x: CGFloat) -> some View {
        Ellipse().fill(PetLook.bodyShade).frame(width: 30, height: 15).position(x: x, y: 174)
    }

    private var cheeks: some View {
        let strength = mood == .happy || eating != nil ? 0.55 : 0.3
        return ZStack {
            Ellipse().fill(PetLook.cheek.opacity(strength)).frame(width: 20, height: 11).position(x: 60, y: 121)
            Ellipse().fill(PetLook.cheek.opacity(strength)).frame(width: 20, height: 11).position(x: 140, y: 121)
        }
    }

    @ViewBuilder private func eye(x: CGFloat) -> some View {
        if mood == .sleepy {
            SleepyEyeShape().stroke(PetLook.face, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                .frame(width: 16, height: 6).position(x: x, y: 106)
        } else {
            ZStack {
                Capsule().fill(PetLook.face).frame(width: 13, height: 19)
                Circle().fill(.white).frame(width: 5, height: 5).offset(x: -2, y: mood == .hungry ? -6 : -4)
                if mood == .happy { Circle().fill(.white).frame(width: 2.5, height: 2.5).offset(x: 3, y: 3) }
            }
            .scaleEffect(y: blinking ? 0.12 : 1)
            .position(x: x, y: 104)
            if mood == .hungry {
                // Brows raised in the middle: a pleading look.
                Capsule().fill(PetLook.face).frame(width: 12, height: 3)
                    .rotationEffect(.degrees(x < 100 ? -18 : 18)).position(x: x, y: 88)
            }
        }
    }

    @ViewBuilder private var mouth: some View {
        if let eating {
            Ellipse().fill(PetLook.face)
                .frame(width: 16, height: 4 + 10 * abs(sin(eating * 16)))
        } else {
            switch mood {
            case .happy:
                SmileShape().fill(PetLook.face).frame(width: 24, height: 12)
                    .overlay(alignment: .bottom) { Ellipse().fill(PetLook.tongue).frame(width: 11, height: 5).offset(y: -1) }
                    .offset(y: 4)
            case .content:
                CatMouthShape().stroke(PetLook.face, style: StrokeStyle(lineWidth: 2.5, lineCap: .round, lineJoin: .round))
                    .frame(width: 18, height: 7)
            case .hungry:
                Ellipse().fill(PetLook.face).frame(width: 10, height: 12 + sin(time * 5) * 1.5).offset(y: 2)
            case .sleepy:
                Ellipse().fill(PetLook.face).frame(width: 8, height: 5 + breath * 60)
            }
        }
    }

    private var scarf: some View {
        ZStack {
            Capsule().fill(Color(red: 0.36, green: 0.56, blue: 0.95)).frame(width: 118, height: 15).position(x: 100, y: 152)
            RoundedRectangle(cornerRadius: 5).fill(Color(red: 0.30, green: 0.48, blue: 0.88))
                .frame(width: 15, height: 30).rotationEffect(.degrees(-10)).position(x: 132, y: 166)
        }
    }

    private var flower: some View {
        Image(systemName: "camera.macro")
            .font(.system(size: 26, weight: .semibold))
            .foregroundStyle(Color(red: 1.0, green: 0.80, blue: 0.25))
            .position(x: 52, y: 62)
    }

    private var crown: some View {
        Image(systemName: "crown.fill")
            .font(.system(size: 30))
            .foregroundStyle(LinearGradient(colors: [.yellow, .orange], startPoint: .top, endPoint: .bottom))
            .position(x: 100, y: 42)
    }

    // MARK: Around the pet

    @ViewBuilder private var moodExtras: some View {
        switch mood {
        case .sleepy:
            // Three Z's drifting up and fading, one after another.
            ForEach(0..<3, id: \.self) { index in
                let phase = (time / 3 + Double(index) / 3).truncatingRemainder(dividingBy: 1)
                Text("z")
                    .font(.system(size: 14 + 8 * phase, weight: .bold, design: .rounded))
                    .foregroundStyle(.secondary)
                    .opacity(1 - phase)
                    .position(x: 150 + 18 * phase, y: 60 - 44 * phase)
            }
        case .hungry:
            Image(systemName: "fork.knife.circle.fill")
                .font(.system(size: 26))
                .foregroundStyle(.secondary)
                .position(x: 168, y: 48 + sin(time * 2) * 3)
        case .happy, .content:
            EmptyView()
        }
    }

    @ViewBuilder private var mealExtras: some View {
        if let eating, let mealSymbol {
            // The food drops into the mouth…
            if eating < 0.5 {
                let fall = eating / 0.5
                Image(systemName: mealSymbol)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(.tint)
                    .scaleEffect(1 - fall * 0.6)
                    .opacity(1 - fall * 0.7)
                    .position(x: 100, y: 12 + 108 * fall)
            }
            // …and hearts float up.
            if eating > 0.4 {
                let rise = (eating - 0.4) / (mealLength - 0.4)
                ForEach(0..<3, id: \.self) { index in
                    Image(systemName: "heart.fill")
                        .font(.system(size: 14 + CGFloat(index) * 3))
                        .foregroundStyle(PetLook.cheek)
                        .opacity(1 - rise)
                        .position(x: 100 + Double(index - 1) * 34 * rise, y: 54 - 46 * rise - Double(index % 2) * 10)
                }
            }
        }
    }
}

// MARK: - The menu bar face

/// The pet's face, small and in one color, for the menu bar. The eyes and mouth are cut out of the head, so
/// it reads like an SF Symbol in light and dark menu bars.
struct PetFaceGlyph: View {
    let mood: PetMood

    var body: some View {
        ZStack {
            EarShape().frame(width: 6, height: 6).rotationEffect(.degrees(-14)).position(x: 4.5, y: 4)
            EarShape().frame(width: 6, height: 6).rotationEffect(.degrees(14)).position(x: 13.5, y: 4)
            Ellipse().frame(width: 18, height: 13).position(x: 9, y: 9.5)
            Group {
                eye(x: 6)
                eye(x: 12)
                mouth.position(x: 9, y: 12.5)
            }
            .blendMode(.destinationOut)
        }
        .compositingGroup()
        .frame(width: 18, height: 16)
        .foregroundStyle(.black)
    }

    @ViewBuilder private func eye(x: CGFloat) -> some View {
        if mood == .sleepy {
            Capsule().frame(width: 3.5, height: 1.2).position(x: x, y: 9)
        } else {
            Capsule().frame(width: 2.4, height: 3.4).position(x: x, y: 8.5)
        }
    }

    @ViewBuilder private var mouth: some View {
        switch mood {
        case .happy: SmileShape().frame(width: 6, height: 2.6)
        case .content: CatMouthShape().stroke(style: StrokeStyle(lineWidth: 1, lineCap: .round)).frame(width: 5, height: 1.8)
        case .hungry: Ellipse().frame(width: 2.4, height: 2.8)
        case .sleepy: Capsule().frame(width: 2.4, height: 1)
        }
    }

    /// The face as a template image, the kind macOS tints for the menu bar.
    @MainActor static func image(for mood: PetMood) -> NSImage {
        let renderer = ImageRenderer(content: PetFaceGlyph(mood: mood))
        renderer.scale = 2
        let image = renderer.nsImage ?? NSImage(systemSymbolName: "pawprint.fill", accessibilityDescription: nil) ?? NSImage()
        image.size = NSSize(width: 18, height: 16)
        image.isTemplate = true
        return image
    }
}

// MARK: - Shapes

/// A cat's ear with a soft tip, wide at the bottom.
struct EarShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY),
                          control: CGPoint(x: rect.minX + rect.width * 0.12, y: rect.minY + rect.height * 0.25))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - rect.width * 0.12, y: rect.minY + rect.height * 0.25))
        path.closeSubpath()
        return path
    }
}

/// An open smile: flat along the top, round below.
struct SmileShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.minX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2 - rect.minY))
        path.closeSubpath()
        return path
    }
}

/// A cat's little "w" mouth.
struct CatMouthShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.midX, y: rect.minY), control: CGPoint(x: rect.minX + rect.width / 4, y: rect.maxY * 1.6))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.maxX - rect.width / 4, y: rect.maxY * 1.6))
        return path
    }
}

/// A closed, sleeping eye: a curve dipping down.
struct SleepyEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY), control: CGPoint(x: rect.midX, y: rect.maxY * 2))
        return path
    }
}
