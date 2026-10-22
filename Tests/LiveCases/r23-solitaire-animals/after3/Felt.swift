import SwiftUI

extension Color {
    /// The gold of the table's printing, pinstripe and stitching.
    static let casinoGold = Color(red: 0.86, green: 0.71, blue: 0.40)
    static let railLeather = Color(red: 0.24, green: 0.11, blue: 0.07)
}

/// A casino card table: a padded leather rail with gold stitching around the edge, deep green baize inside it
/// with a soft pool of light, a gold pinstripe, and the game's name and rules printed in gold on the cloth.
struct Felt: View {
    @Environment(\.colorScheme) private var colorScheme

    /// How wide the leather rail is; `TableLayout.margin` keeps the cards inside it.
    static let rail: CGFloat = 18

    var body: some View {
        let dark = colorScheme == .dark
        GeometryReader { geometry in
            let size = geometry.size
            let inner = Self.rail
            ZStack {
                // The cloth.
                cloth(size: size, dark: dark)
                    .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    // The rail's cushion casts a shadow onto the cloth.
                    .overlay {
                        RoundedRectangle(cornerRadius: 26, style: .continuous)
                            .strokeBorder(.black.opacity(0.55), lineWidth: 8)
                            .blur(radius: 7)
                            .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                    }
                    .padding(inner)

                // The gold pinstripe just inside the rail.
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .strokeBorder(Color.casinoGold.opacity(0.5), lineWidth: 1.25)
                    .padding(inner + 9)

                printing(in: size)
            }
            .background { rail }
        }
        .accessibilityHidden(true)
    }

    /// Painted photographs of the baize and the leather, loaded once.
    private static let feltTexture = LampAssets.image("felt.png")
    private static let leatherTexture = LampAssets.image("leather.png")

    /// The baize: the felt photograph tinted to a casino green, lit in the middle and darker toward the rail.
    @ViewBuilder private func cloth(size: CGSize, dark: Bool) -> some View {
        let reach = max(size.width, size.height) * 0.75
        if let felt = Self.feltTexture {
            ZStack {
                Image(nsImage: felt)
                    .resizable()
                    .scaledToFill()
                    .frame(width: size.width, height: size.height)
                    .saturation(1.15)
                Color(red: 0.0, green: 0.30, blue: 0.16).blendMode(.multiply).opacity(0.35)
                RadialGradient(colors: [.clear, .black.opacity(dark ? 0.65 : 0.45)],
                               center: .center, startRadius: reach * 0.25, endRadius: reach)
            }
        } else {
            RadialGradient(
                colors: dark
                    ? [Color(red: 0.05, green: 0.38, blue: 0.22), Color(red: 0.01, green: 0.15, blue: 0.08)]
                    : [Color(red: 0.08, green: 0.52, blue: 0.30), Color(red: 0.02, green: 0.26, blue: 0.14)],
                center: .center, startRadius: 0, endRadius: reach
            )
            .overlay { speckle }
        }
    }

    /// The padded leather around the edge, lit from above, with a line of stitching along it.
    private var rail: some View {
        ZStack {
            Group {
                if let leather = Self.leatherTexture {
                    Image(nsImage: leather).resizable().scaledToFill()
                } else {
                    Color.railLeather
                }
            }
            .overlay {
                LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.45)],
                               startPoint: .top, endPoint: .bottom)
            }
            .ignoresSafeArea()
            RoundedRectangle(cornerRadius: 30, style: .continuous)
                .strokeBorder(style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .foregroundStyle(Color.casinoGold.opacity(0.45))
                .padding(Self.rail / 2 - 0.5)
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                .padding(Self.rail - 1)
        }
    }

    private var speckle: some View {
        Canvas { context, size in
            // The same seed every time, so the texture holds still as the window changes size.
            var generator = SeededGenerator(seed: 42)
            let count = Int(size.width * size.height / 70)
            for index in 0..<count {
                let x = Double.random(in: 0..<size.width, using: &generator)
                let y = Double.random(in: 0..<size.height, using: &generator)
                let shade: Color = index.isMultiple(of: 2) ? .white.opacity(0.035) : .black.opacity(0.06)
                context.fill(Path(CGRect(x: x, y: y, width: 1, height: 1)), with: .color(shade))
            }
        }
    }

    /// The name and the house rules, printed in arcs low on the cloth as on a blackjack table.
    private func printing(in size: CGSize) -> some View {
        let title = min(max(size.width * 0.045, 22), 46)
        let radius = size.width * 0.75
        let center = CGPoint(x: size.width / 2, y: size.height * 0.80 + radius)
        return ZStack {
            ArcText(text: "SOLITAIRE", radius: radius, fontSize: title, weight: .bold, spacing: 0.9)
            ArcText(text: "♠  KINGS TO EMPTY COLUMNS  ·  ACES BUILD UP BY SUIT  ♥",
                    radius: radius - title * 1.3, fontSize: title * 0.32, weight: .semibold, spacing: 0.72)
        }
        .foregroundStyle(Color.casinoGold.opacity(0.42))
        .position(center)
    }
}

/// Letters set along the top of a circle around this view's center.
private struct ArcText: View {
    let text: String
    let radius: CGFloat
    let fontSize: CGFloat
    var weight: Font.Weight = .bold
    /// Each letter's advance, as a share of the font size.
    var spacing: CGFloat = 0.8

    var body: some View {
        let letters = Array(text)
        let step = fontSize * spacing / radius
        let start = -step * CGFloat(letters.count - 1) / 2
        ZStack {
            ForEach(Array(letters.enumerated()), id: \.offset) { index, letter in
                Text(String(letter))
                    .font(.system(size: fontSize, weight: weight, design: .serif))
                    .offset(y: -radius)
                    .rotationEffect(.radians(Double(start + step * CGFloat(index))))
            }
        }
    }
}

/// An empty place on the table: a faint gold outline with a hint of what goes there.
struct PileOutline: View {
    let width: CGFloat
    var symbol: String?
    var letter: String?

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
            .fill(.black.opacity(0.08))
            .strokeBorder(Color.casinoGold.opacity(0.45), lineWidth: 1.5)
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: width * 0.3, weight: .medium))
                } else if let letter {
                    Text(letter).font(.system(size: width * 0.36, weight: .semibold, design: .serif))
                }
            }
            .foregroundStyle(Color.casinoGold.opacity(0.5))
            .frame(width: width, height: width * 1.4)
    }
}
