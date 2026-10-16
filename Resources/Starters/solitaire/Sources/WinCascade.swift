import SwiftUI

/// The cards bouncing off the foundations after a win, leaving trails behind them, as Windows Solitaire did.
/// Each card is stamped into one picture as it moves, so the trails cost nothing to keep. A click ends it early.
struct WinCascade: View {
    let layout: TableLayout
    let foundations: [[Card]]
    let onFinish: () -> Void

    @Environment(\.displayScale) private var scale
    @State private var cascade: Cascade?
    @State private var frame: CGImage?
    @State private var ticker = Timer.publish(every: 1.0 / 60, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            Color.clear
            if let frame {
                Image(decorative: frame, scale: scale)
            }
        }
        .frame(width: layout.size.width, height: layout.size.height)
        .contentShape(Rectangle())
        .onTapGesture(perform: onFinish)
        .onAppear { cascade = Cascade(layout: layout, foundations: foundations, scale: scale) }
        .onReceive(ticker) { _ in
            guard let cascade else { return }
            if cascade.step() { frame = cascade.image } else { onFinish() }
        }
        .accessibilityLabel("You won. Click to continue.")
        .accessibilityAddTraits(.isButton)
    }
}

/// The physics and the picture behind `WinCascade`: cards leave the foundations kings first, a new one every
/// third of a second, fall, bounce off the bottom of the window, and are done once they're off its side.
@MainActor private final class Cascade {
    private struct Flying {
        let image: CGImage
        var position: CGPoint
        var velocity: CGVector
    }

    private let layout: TableLayout
    private let context: CGContext?
    private var waiting: [(image: CGImage, from: CGPoint)] = []
    private var flying: [Flying] = []
    private var ticks = 0

    init(layout: TableLayout, foundations: [[Card]], scale: CGFloat) {
        self.layout = layout
        context = CGContext(
            data: nil, width: Int(layout.size.width * scale), height: Int(layout.size.height * scale),
            bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )
        // Draw in points with y going down, as SwiftUI does.
        context?.translateBy(x: 0, y: layout.size.height * scale)
        context?.scaleBy(x: scale, y: -scale)

        for rank in stride(from: 13, through: 1, by: -1) {
            for (index, pile) in foundations.enumerated() {
                guard let card = pile.first(where: { $0.rank == rank }) else { continue }
                let renderer = ImageRenderer(content: CardFace(card: card, width: layout.cardWidth))
                renderer.scale = scale
                if let image = renderer.cgImage {
                    waiting.append((image, layout.spot(of: .foundation(index))))
                }
            }
        }
    }

    var image: CGImage? { context?.makeImage() }

    /// One sixtieth of a second; false once every card has gone.
    func step() -> Bool {
        if ticks % 20 == 0, !waiting.isEmpty {
            let next = waiting.removeFirst()
            let speed = CGFloat.random(in: 3...7) * (Bool.random() ? 1 : -1)
            flying.append(Flying(image: next.image, position: next.from,
                                 velocity: CGVector(dx: speed, dy: -CGFloat.random(in: 0...8))))
        }
        ticks += 1

        let size = layout.cardSize, floor = layout.size.height - size.height / 2
        for index in flying.indices {
            // Two small steps a tick keep the trail unbroken.
            for _ in 0..<2 {
                flying[index].velocity.dy += 0.3
                flying[index].position.x += flying[index].velocity.dx / 2
                flying[index].position.y += flying[index].velocity.dy / 2
                if flying[index].position.y > floor {
                    flying[index].position.y = floor
                    flying[index].velocity.dy *= -0.78
                }
                stamp(flying[index])
            }
        }
        flying.removeAll { $0.position.x < -size.width || $0.position.x > layout.size.width + size.width }
        return !(waiting.isEmpty && flying.isEmpty)
    }

    private func stamp(_ card: Flying) {
        guard let context else { return }
        let rect = layout.cardFrame(at: card.position)
        context.saveGState()
        // Images draw upside down in a flipped context, so flip back around the card.
        context.translateBy(x: rect.minX, y: rect.maxY)
        context.scaleBy(x: 1, y: -1)
        context.draw(card.image, in: CGRect(origin: .zero, size: rect.size))
        context.restoreGState()
    }
}
