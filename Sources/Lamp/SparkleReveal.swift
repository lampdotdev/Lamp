import SwiftUI

extension View {
    /// Brings the view in from top to bottom behind a drift of sparkles, like something let out of a lamp.
    func sparkleReveal(duration: Double = 1.1) -> some View {
        modifier(SparkleReveal(duration: duration))
    }
}

/// The view shows down to a soft edge that sweeps from its top to its bottom; sparkles are born along the edge
/// as it passes, rise a little, twinkle and fade. It runs once, when the view appears, and not at all when
/// the user has asked for less motion.
private struct SparkleReveal: ViewModifier {
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var done = false

    /// How long a sparkle lasts, at most: the effect is over once the last one born has gone.
    private static let life = 0.9
    private static let count = 90
    /// How deep the soft edge is, as a share of the view's height.
    private static let feather = 0.18

    func body(content: Content) -> some View {
        // The same views whether it's running or not, so finishing doesn't make the content anew (and lose,
        // say, a field being typed in).
        TimelineView(.animation(paused: done || reduceMotion)) { timeline in
            let elapsed = done || reduceMotion ? .infinity : start.map { timeline.date.timeIntervalSince($0) } ?? 0
            content
                .mask {
                    LinearGradient(stops: Self.stops(Self.edge(elapsed / duration)), startPoint: .top, endPoint: .bottom)
                }
                .overlay {
                    if elapsed < duration + Self.life {
                        Canvas { context, size in Self.draw(in: &context, size: size, elapsed: elapsed, duration: duration) }
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .onAppear {
            guard start == nil else { return }
            start = .now
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.life) { done = true }
        }
    }

    /// Where the edge is, from 0 (the top) to 1 (the bottom), easing out as it nears the end.
    private static func edge(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return 1 - pow(1 - p, 2.2)
    }

    /// Solid above the edge, clear below it, with the feather between. It starts a feather above the top
    /// and ends a feather below the bottom, so the view is wholly hidden at first and wholly shown at the end.
    private static func stops(_ edge: Double) -> [Gradient.Stop] {
        let lower = edge * (1 + feather)
        let upper = lower - feather
        func clamp(_ x: Double) -> Double { min(max(x, 0), 1) }
        let solid = clamp(upper), clear = clamp(lower)
        // Gradient stops have to go in order; when both sit at an end, the view is all one or the other.
        if clear <= 0 { return [.init(color: .clear, location: 0), .init(color: .clear, location: 1)] }
        if solid >= 1 { return [.init(color: .black, location: 0), .init(color: .black, location: 1)] }
        let mid = (upper + lower) / 2
        return [.init(color: .black, location: 0),
                .init(color: .black, location: solid),
                .init(color: .black.opacity(0.6), location: clamp(mid)),
                .init(color: .clear, location: max(clear, solid + 0.0001)),
                .init(color: .clear, location: 1)]
    }

    /// A number from 0 to 1 that's the same every time for the same sparkle, so they don't jump about.
    private static func random(_ index: Int, _ salt: UInt64) -> Double {
        var x = UInt64(index) &* 0x9E37_79B9_7F4A_7C15 &+ salt &* 0xBF58_476D_1CE4_E5B9
        x ^= x >> 31; x &*= 0x94D0_49BB_1331_11EB; x ^= x >> 29
        return Double(x % 10_000) / 10_000
    }

    private static func draw(in context: inout GraphicsContext, size: CGSize, elapsed: Double, duration: Double) {
        // Warm enough to show on a white page; the paler ones read as glints beside them.
        let gold = Color(red: 0.98, green: 0.68, blue: 0.18)
        let pale = Color(red: 1, green: 0.84, blue: 0.45)

        // A faint glow along the edge while it moves.
        let progress = elapsed / duration
        if progress < 1 {
            let y = (edge(progress) * (1 + feather) - feather / 2) * size.height
            let glow = CGRect(x: size.width * 0.1, y: y - 14, width: size.width * 0.8, height: 28)
            context.fill(Ellipse().path(in: glow),
                         with: .radialGradient(Gradient(colors: [gold.opacity(0.28 * (1 - progress)), .clear]),
                                               center: CGPoint(x: glow.midX, y: glow.midY),
                                               startRadius: 0, endRadius: glow.width / 2))
        }

        for index in 0..<count {
            // Each is born when the edge passes its height, somewhere across the middle of the view.
            let born = random(index, 1) * duration * 0.95
            let age = elapsed - born
            let life = life * (0.55 + 0.45 * random(index, 2))
            guard age >= 0, age < life else { continue }
            let t = age / life
            let x = size.width * (0.12 + 0.76 * random(index, 3)) + CGFloat(sin(age * 3 + Double(index))) * 4
            let y = (edge(born / duration) * (1 + feather) - feather / 2) * size.height - CGFloat(age * 26)
            let twinkle = 0.6 + 0.4 * sin(age * 18 + Double(index))
            let radius = CGFloat(3.5 + 5 * random(index, 4)) * CGFloat(sin(t * .pi)) * CGFloat(twinkle)
            guard radius > 0.2 else { continue }
            let color = random(index, 5) < 0.5 ? gold : pale
            let opacity = (1 - t) * twinkle

            var star = context
            star.opacity = opacity
            star.addFilter(.shadow(color: gold.opacity(0.9), radius: radius * 0.9))
            star.fill(sparkle(at: CGPoint(x: x, y: y), radius: radius), with: .color(color))
        }
    }

    /// A four-pointed star with pinched sides.
    private static func sparkle(at center: CGPoint, radius: CGFloat) -> Path {
        var path = Path()
        let waist = radius * 0.28
        path.move(to: CGPoint(x: center.x, y: center.y - radius))
        path.addQuadCurve(to: CGPoint(x: center.x + radius, y: center.y), control: CGPoint(x: center.x + waist, y: center.y - waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y + radius), control: CGPoint(x: center.x + waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x - radius, y: center.y), control: CGPoint(x: center.x - waist, y: center.y + waist))
        path.addQuadCurve(to: CGPoint(x: center.x, y: center.y - radius), control: CGPoint(x: center.x - waist, y: center.y - waist))
        path.closeSubpath()
        return path
    }
}
