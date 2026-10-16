import SwiftUI
import AppKit

/// The app's colors: a warm honey for what changed and the goal, each with a light and a dark version.
/// Everything else uses system colors, so the app follows the appearance and accent the person chose.
enum Palette {
    static let honey = Color(light: NSColor(red: 0.98, green: 0.76, blue: 0.20, alpha: 1),
                             dark: NSColor(red: 0.93, green: 0.68, blue: 0.16, alpha: 1))
    static let honeyInk = Color(light: NSColor(red: 0.36, green: 0.22, blue: 0.00, alpha: 1),
                                dark: NSColor(red: 0.20, green: 0.12, blue: 0.00, alpha: 1))
    static let goal = Color(light: NSColor(red: 0.20, green: 0.55, blue: 0.36, alpha: 1),
                            dark: NSColor(red: 0.30, green: 0.68, blue: 0.46, alpha: 1))
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// How a letter tile looks, by what it is in the ladder.
enum TileStyle {
    case start      // the first word
    case word       // a letter kept from the step before
    case changed    // the letter this step changed
    case goal       // the end word, waiting at the bottom
    case typing     // a letter being typed
    case ghost      // an empty slot, showing the letter it would keep
    case hint       // an empty slot the hint points at
}

/// One square letter. A tile that `flips` turns over into place when it appears, the way a changed letter
/// arrives on the ladder.
struct LetterTile: View {
    let letter: Character?
    let style: TileStyle
    var flips = false
    var delay = 0.0

    @State private var turn = 0.0
    static let size: CGFloat = 54

    var body: some View {
        RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(fill)
            .overlay {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .strokeBorder(border, style: StrokeStyle(lineWidth: style == .ghost || style == .hint ? 1.5 : 1,
                                                             dash: style == .goal ? [5, 4] : []))
            }
            .overlay {
                Text(letter.map { String($0).uppercased() } ?? "")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundStyle(ink)
            }
            .frame(width: Self.size, height: Self.size)
            .shadow(color: .black.opacity(raised ? 0.12 : 0), radius: 2, y: 1)
            .rotation3DEffect(.degrees(turn), axis: (x: 1, y: 0, z: 0), perspective: 0.4)
            .onAppear {
                guard flips else { return }
                turn = -90
                withAnimation(.spring(response: 0.45, dampingFraction: 0.7).delay(delay)) { turn = 0 }
            }
            .accessibilityHidden(true)
    }

    private var raised: Bool { [.start, .word, .changed, .typing].contains(style) }

    private var fill: Color {
        switch style {
        case .start: Color.accentColor
        case .word, .typing: Color(nsColor: .controlBackgroundColor)
        case .changed: Palette.honey
        case .goal: Palette.goal.opacity(0.12)
        case .ghost: .clear
        case .hint: Palette.honey.opacity(0.18)
        }
    }

    private var border: Color {
        switch style {
        case .start, .changed: .clear
        case .word: Color.primary.opacity(0.12)
        case .typing: Color.primary.opacity(0.35)
        case .goal: Palette.goal.opacity(0.7)
        case .ghost: Color.primary.opacity(0.15)
        case .hint: Palette.honey
        }
    }

    private var ink: Color {
        switch style {
        case .start: .white
        case .word, .typing: .primary
        case .changed: Palette.honeyInk
        case .goal: Palette.goal
        case .ghost: Color.secondary.opacity(0.35)
        case .hint: .primary
        }
    }
}

/// Moves a view side to side once each time `shakes` goes up: a word that wasn't taken.
struct Shake: GeometryEffect {
    var shakes: CGFloat

    var animatableData: CGFloat {
        get { shakes }
        set { shakes = newValue }
    }

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: 8 * sin(shakes * .pi * 4), y: 0))
    }
}
