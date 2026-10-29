import SwiftUI
import AppKit

/// Lamp's colors, as lamp.dev has them: dark ink on warm paper, and six stripes from green to magenta that mark what's
/// Lamp's own (the welcome's band, a remix's line back to its original, work under way). The desk, the welcome and the
/// chat all draw from here, so the three never drift apart. Each color has a dark form for the chat beside an app in
/// dark mode; the desk and the welcome are always light.
public enum Paper {
    /// The page everything sits on.
    public static let page = shade(light: 0xF6F1E4, dark: 0x1F1D19)
    /// A side panel, a little deeper than the page.
    public static let panel = shade(light: 0xEFE8D6, dark: 0x191714)
    /// What's lifted off the page: a card, a field, the selected row.
    public static let card = shade(light: 0xFFFDF6, dark: 0x2A2722)
    /// Words, and the main button.
    public static let ink = shade(light: 0x1B1A17, dark: 0xF2ECDA)
    /// The main button's words: the page's color on ink.
    public static let onInk = shade(light: 0xF2ECDA, dark: 0x1B1A17)
    /// Words that come second.
    public static let muted = shade(light: 0x5D574B, dark: 0xB9B2A1)
    /// A small heading in capitals ("YOUR DEVICES").
    public static let label = shade(light: 0xA8361F, dark: 0xF08A1C)
    /// A thin line between things, and a field's edge.
    public static let rule = shade(light: 0x1B1A17, dark: 0xF2ECDA, alpha: 0.14)

    /// The stripes, in order: green, lime, yellow, orange, red, magenta.
    public static let stripes: [Color] = [0x1F8A4A, 0x7CBF3A, 0xF6B81C, 0xF08A1C, 0xE2402A, 0xD23778].map { Color(hex: $0) }
    public static var stripeGradient: Gradient { Gradient(colors: stripes) }

    private static func shade(light: UInt32, dark: UInt32, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(hex: dark, alpha: alpha)
        })
    }
}

/// The six stripes side by side, as on the site: a band across (`.horizontal`, each stripe a row) or down
/// (`.vertical`, each a column).
public struct Stripes: View {
    let axis: Axis
    public init(_ axis: Axis = .horizontal) { self.axis = axis }

    public var body: some View {
        let layout = axis == .horizontal ? AnyLayout(VStackLayout(spacing: 0)) : AnyLayout(HStackLayout(spacing: 0))
        layout {
            ForEach(Paper.stripes.indices, id: \.self) { Paper.stripes[$0] }
        }
        .accessibilityHidden(true)
    }
}

/// The two kinds of button the new screens use: `.ink`, the one to press, filled with ink; `.outline`, the others.
public struct PaperButtonStyle: ButtonStyle {
    public enum Kind { case ink, outline }
    let kind: Kind
    let height: CGFloat
    public init(_ kind: Kind, height: CGFloat = 30) {
        self.kind = kind
        self.height = height
    }

    public func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .bold))
            .padding(.horizontal, 12)
            .frame(minHeight: height)
            .foregroundStyle(kind == .ink ? Paper.onInk : Paper.ink)
            .background(kind == .ink ? Paper.ink : Color.clear, in: RoundedRectangle(cornerRadius: 7, style: .continuous))
            .overlay {
                if kind == .outline { RoundedRectangle(cornerRadius: 7, style: .continuous).strokeBorder(Paper.rule, lineWidth: 1) }
            }
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Rectangle())
    }
}

extension Color {
    public init(hex: UInt32) { self.init(nsColor: NSColor(hex: hex)) }
}

extension NSColor {
    public convenience init(hex: UInt32, alpha: CGFloat = 1) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }
}
