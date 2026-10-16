import SwiftUI

/// The green baize the game is played on: a soft pool of light in the middle and a fine speckle, so it reads as
/// cloth rather than a flat color. A little deeper in dark mode.
struct Felt: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let dark = colorScheme == .dark
        ZStack {
            RadialGradient(
                colors: dark
                    ? [Color(red: 0.07, green: 0.36, blue: 0.20), Color(red: 0.02, green: 0.16, blue: 0.09)]
                    : [Color(red: 0.13, green: 0.52, blue: 0.29), Color(red: 0.05, green: 0.29, blue: 0.16)],
                center: .center, startRadius: 0, endRadius: 900
            )
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
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// An empty place on the table: a faint outline with a hint of what goes there.
struct PileOutline: View {
    let width: CGFloat
    var symbol: String?
    var letter: String?

    var body: some View {
        RoundedRectangle(cornerRadius: width * 0.08, style: .continuous)
            .fill(.white.opacity(0.06))
            .strokeBorder(.white.opacity(0.28), lineWidth: 1.5)
            .overlay {
                if let symbol {
                    Image(systemName: symbol).font(.system(size: width * 0.3, weight: .medium))
                } else if let letter {
                    Text(letter).font(.system(size: width * 0.36, weight: .semibold, design: .serif))
                }
            }
            .foregroundStyle(.white.opacity(0.35))
            .frame(width: width, height: width * 1.4)
    }
}
