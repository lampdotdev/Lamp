import SwiftUI

/// The back of every card. It's its own small view so a different design is a change to this file alone: the
/// colors below, and the pattern drawn in `pattern`.
struct CardBack: View {
    let width: CGFloat

    private let deep = Color(red: 0.10, green: 0.23, blue: 0.55)
    private let light = Color(red: 0.20, green: 0.40, blue: 0.78)

    var body: some View {
        let corner = width * 0.08
        ZStack {
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .fill(Color.cardPaper)
            RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                .fill(LinearGradient(colors: [light, deep], startPoint: .topLeading, endPoint: .bottomTrailing))
                .overlay { pattern }
                .overlay {
                    RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous)
                        .strokeBorder(.white.opacity(0.35), lineWidth: max(0.5, width * 0.01))
                }
                .clipShape(RoundedRectangle(cornerRadius: corner * 0.6, style: .continuous))
                .padding(width * 0.06)
            RoundedRectangle(cornerRadius: corner, style: .continuous)
                .strokeBorder(.black.opacity(0.18), lineWidth: 0.5)
        }
    }

    /// A lattice of diagonal lines with a small diamond where they cross.
    private var pattern: some View {
        Canvas { context, size in
            let step = max(4, width * 0.11)
            let first = -(size.height / step).rounded(.up)
            let last = ((size.width + size.height) / step).rounded(.up)
            var lines = Path()
            for k in stride(from: first, through: last, by: 1) {
                let x = k * step
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x + size.height, y: size.height))
                lines.move(to: CGPoint(x: x, y: 0))
                lines.addLine(to: CGPoint(x: x - size.height, y: size.height))
            }
            context.stroke(lines, with: .color(.white.opacity(0.22)), lineWidth: max(0.5, width * 0.008))

            // The lines cross every half step, at columns and rows of the same parity.
            let half = step / 2, dot = step * 0.16
            var diamonds = Path()
            for row in 0...Int(size.height / half) + 1 {
                for column in 0...Int(size.width / half) + 1 where (row + column).isMultiple(of: 2) {
                    let center = CGPoint(x: CGFloat(column) * half, y: CGFloat(row) * half)
                    diamonds.move(to: CGPoint(x: center.x, y: center.y - dot))
                    diamonds.addLine(to: CGPoint(x: center.x + dot, y: center.y))
                    diamonds.addLine(to: CGPoint(x: center.x, y: center.y + dot))
                    diamonds.addLine(to: CGPoint(x: center.x - dot, y: center.y))
                    diamonds.closeSubpath()
                }
            }
            context.fill(diamonds, with: .color(.white.opacity(0.3)))
        }
    }
}
