import SwiftUI
import AppKit
import QuartzCore

extension View {
    /// Brings the view in from top to bottom behind a drift of sparkles, like something let out of a lamp.
    func sparkleReveal(duration: Double = 1.1) -> some View {
        modifier(SparkleReveal(duration: duration))
    }

    /// One glint across the view, after `delay`, shaped to what the view draws (an icon's squircle, say).
    func shine(delay: Double) -> some View {
        modifier(Shine(delay: delay))
    }
}

/// The view shows down to a soft edge that sweeps from its top to its bottom. Sparkles pour out along the edge
/// as it passes: from a narrow stream at the top, where the icon is, widening as it goes down. It runs once,
/// when the view appears, and not at all when the user has asked for less motion.
private struct SparkleReveal: ViewModifier {
    let duration: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var done = false

    /// How long the last sparkles take to fade once the edge has reached the bottom.
    private static let linger = 1.2
    /// How deep the soft edge is, as a share of the view's height.
    private static let feather = 0.18

    func body(content: Content) -> some View {
        // The same views whether it's running or not, so finishing doesn't make the content anew (and lose,
        // say, a field being typed in).
        TimelineView(.animation(paused: done || reduceMotion)) { timeline in
            let elapsed = done || reduceMotion ? .infinity : start.map { timeline.date.timeIntervalSince($0) } ?? 0
            let progress = elapsed / duration
            content
                .mask {
                    LinearGradient(stops: Self.stops(Self.edge(progress)), startPoint: .top, endPoint: .bottom)
                }
                // In front: behind, the chat's own background would hide the sparkles.
                .overlay {
                    if elapsed < duration + Self.linger {
                        GeometryReader { area in
                            let y = (Self.edge(progress) * (1 + Self.feather) - Self.feather / 2) * area.size.height
                            ZStack(alignment: .topLeading) {
                                // A faint warm glow along the edge while it moves.
                                if progress < 1 {
                                    Ellipse()
                                        .fill(RadialGradient(colors: [SparkleEmitter.gold.opacity(0.26 * (1 - progress)), .clear],
                                                             center: .center, startRadius: 0, endRadius: area.size.width * 0.4))
                                        .frame(width: area.size.width * 0.8, height: 28)
                                        .position(x: area.size.width / 2, y: y)
                                }
                                SparkleEmitter(edge: y, spread: Self.spread(progress) * area.size.width, pouring: progress < 1)
                            }
                        }
                        .allowsHitTesting(false)
                        .accessibilityHidden(true)
                    }
                }
        }
        .onAppear {
            guard start == nil else { return }
            start = .now
            DispatchQueue.main.asyncAfter(deadline: .now() + duration + Self.linger) { done = true }
        }
    }

    /// Where the edge is, from 0 (the top) to 1 (the bottom), easing out as it nears the end.
    private static func edge(_ progress: Double) -> Double {
        let p = min(max(progress, 0), 1)
        return 1 - pow(1 - p, 2.2)
    }

    /// How wide the stream of sparkles is, as a share of the view's width: about an icon's width at first,
    /// opening out over the first part of the sweep.
    private static func spread(_ progress: Double) -> Double {
        let p = min(max(progress / 0.45, 0), 1)
        return 0.12 + 0.66 * (1 - pow(1 - p, 2))
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
}

/// The sparkles themselves, from Core Animation's particle emitter: a line at the reveal's edge that gives
/// off many small quick glints and a few larger, slower stars that turn as they rise and fade.
private struct SparkleEmitter: NSViewRepresentable {
    /// Where the edge is, in points from the top, and how wide the stream is.
    let edge: CGFloat
    let spread: CGFloat
    /// Still giving off sparkles; once it stops, the ones already out finish on their own.
    let pouring: Bool

    static let gold = Color(red: 0.98, green: 0.68, blue: 0.18)

    func makeNSView(context: Context) -> EmitterView {
        let view = EmitterView()
        view.emitter.emitterCells = [Self.glints, Self.stars]
        return view
    }

    func updateNSView(_ view: EmitterView, context: Context) {
        let emitter = view.emitter
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        emitter.frame = view.bounds
        // The view's layer counts up from the bottom.
        emitter.emitterPosition = CGPoint(x: view.bounds.midX, y: view.bounds.height - edge)
        emitter.emitterSize = CGSize(width: spread, height: 1)
        emitter.birthRate = pouring ? 1 : 0
        CATransaction.commit()
    }

    final class EmitterView: NSView {
        let emitter = CAEmitterLayer()

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            emitter.emitterShape = .line
            emitter.emitterMode = .outline
            layer?.addSublayer(emitter)
        }

        required init?(coder: NSCoder) { fatalError("not from a nib") }
    }

    private static var glints: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = dot
        cell.birthRate = 70
        cell.lifetime = 0.75
        cell.lifetimeRange = 0.3
        cell.velocity = 22
        cell.velocityRange = 16
        cell.emissionLongitude = .pi / 2   // up
        cell.emissionRange = .pi / 2.5
        cell.yAcceleration = -8            // slowing as it rises
        cell.scale = 0.16
        cell.scaleRange = 0.08
        cell.scaleSpeed = -0.12
        cell.alphaSpeed = -1.1
        cell.color = NSColor(red: 1, green: 0.8, blue: 0.4, alpha: 1).cgColor
        cell.greenRange = 0.1
        return cell
    }

    private static var stars: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = star
        cell.birthRate = 10
        cell.lifetime = 1.1
        cell.lifetimeRange = 0.3
        cell.velocity = 14
        cell.velocityRange = 8
        cell.emissionLongitude = .pi / 2
        cell.emissionRange = .pi / 3
        cell.yAcceleration = -5
        cell.spinRange = 2.5
        cell.scale = 0.34
        cell.scaleRange = 0.14
        cell.scaleSpeed = -0.22
        cell.alphaSpeed = -0.8
        cell.color = NSColor(red: 0.98, green: 0.68, blue: 0.18, alpha: 1).cgColor
        cell.greenRange = 0.12
        return cell
    }

    /// The particles are white, tinted by each cell's colour.
    private static let star: CGImage? = image { context, size in
        context.addPath(sparkle(in: CGRect(origin: .zero, size: size)))
        context.fillPath()
    }

    private static let dot: CGImage? = image { context, size in
        let colors = [CGColor(gray: 1, alpha: 1), CGColor(gray: 1, alpha: 0)] as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0.15, 1])
        else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
    }

    private static func image(_ draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let side = 48
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        draw(context, CGSize(width: side, height: side))
        return context.makeImage()
    }

    /// A four-pointed star with pinched sides, filling `rect`.
    private static func sparkle(in rect: CGRect) -> CGPath {
        let path = CGMutablePath()
        let c = CGPoint(x: rect.midX, y: rect.midY)
        let r = rect.width / 2, waist = r * 0.22
        path.move(to: CGPoint(x: c.x, y: c.y - r))
        path.addQuadCurve(to: CGPoint(x: c.x + r, y: c.y), control: CGPoint(x: c.x + waist, y: c.y - waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y + r), control: CGPoint(x: c.x + waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x - r, y: c.y), control: CGPoint(x: c.x - waist, y: c.y + waist))
        path.addQuadCurve(to: CGPoint(x: c.x, y: c.y - r), control: CGPoint(x: c.x - waist, y: c.y - waist))
        path.closeSubpath()
        return path
    }
}

/// A band of light that crosses the view once, the way a new app's icon catches the light. Timed from when
/// it appears rather than animated, like the reveal around it, so nothing above can cut it short.
private struct Shine: ViewModifier {
    let delay: Double
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var start: Date?
    @State private var done = false

    private static let duration = 0.75

    func body(content: Content) -> some View {
        content
            .overlay {
                if !reduceMotion && !done {
                    TimelineView(.animation) { timeline in
                        let elapsed = start.map { timeline.date.timeIntervalSince($0) - delay } ?? -1
                        let p = min(max(elapsed / Self.duration, 0), 1)
                        let eased = p * p * (3 - 2 * p)
                        GeometryReader { area in
                            LinearGradient(colors: [.white.opacity(0), .white.opacity(0.55), .white.opacity(0)],
                                           startPoint: .leading, endPoint: .trailing)
                                .frame(width: area.size.width * 0.4, height: area.size.height * 1.6)
                                .rotationEffect(.degrees(22))
                                .position(x: area.size.width * (-0.35 + 1.7 * eased), y: area.size.height / 2)
                        }
                    }
                    // Only where the view draws, so the light stays on the icon and off the page around it.
                    .mask(content)
                    .allowsHitTesting(false)
                    .accessibilityHidden(true)
                }
            }
            .onAppear {
                guard start == nil, !reduceMotion else { return }
                start = .now
                DispatchQueue.main.asyncAfter(deadline: .now() + delay + Self.duration) { done = true }
            }
    }
}
