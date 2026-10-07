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
                                // A faint silver glow along the edge while it moves.
                                if progress < 1 {
                                    Ellipse()
                                        .fill(RadialGradient(colors: [SparkleEmitter.glow.opacity(0.3 * (1 - progress)), .clear],
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
/// off points of light.
private struct SparkleEmitter: NSViewRepresentable {
    /// Where the edge is, in points from the top, and how wide the stream is.
    let edge: CGFloat
    let spread: CGFloat
    /// Still giving off sparkles; once it stops, the ones already out finish on their own.
    let pouring: Bool

    /// The edge's glow: a cool, pale silver.
    static let glow = Color(red: 0.72, green: 0.76, blue: 0.84)

    func makeNSView(context: Context) -> EmitterView {
        let view = EmitterView()
        view.emitter.emitterCells = [Self.motes, Self.glints, Self.haze]
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
        // Not before it has a size and a window: until then the line sits in the corner. When it starts, its
        // clock starts too (in the layer's own time, known only once it's in a window); otherwise it gives off
        // at once every sparkle it thinks it missed, in a dense line.
        let on = pouring && !view.bounds.isEmpty && view.window != nil
        if on && !view.started {
            view.started = true
            emitter.beginTime = emitter.convertTime(CACurrentMediaTime(), from: nil)
        }
        emitter.birthRate = on ? 1 : 0
        CATransaction.commit()
    }

    final class EmitterView: NSView {
        let emitter = CAEmitterLayer()
        var started = false

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            emitter.emitterShape = .line
            emitter.emitterMode = .outline
            emitter.birthRate = 0
            layer?.addSublayer(emitter)
        }

        required init?(coder: NSCoder) { fatalError("not from a nib") }
    }

    // Three kinds, for light rather than cartoon stars: fine motes drifting slowly in every direction, glints
    // that flash for a moment and are gone, and a few large, faint, out-of-focus specks that give it depth.

    private static var motes: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = dot
        cell.birthRate = 90
        cell.lifetime = 1.4
        cell.lifetimeRange = 0.6
        cell.velocity = 7
        cell.velocityRange = 7
        cell.emissionRange = .pi * 2
        cell.yAcceleration = 4             // a slight rise, like warm air
        cell.scale = 0.07
        cell.scaleRange = 0.04
        cell.alphaRange = 0.4
        cell.alphaSpeed = -0.7
        silver(cell, alpha: 0.9)
        return cell
    }

    private static var glints: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = glint
        cell.birthRate = 32
        cell.lifetime = 0.22
        cell.lifetimeRange = 0.12
        cell.velocity = 3
        cell.emissionRange = .pi * 2
        cell.scale = 0.4
        cell.scaleRange = 0.16
        cell.scaleSpeed = -1.1           // a flash that shrinks to nothing
        cell.alphaSpeed = -2.5
        silver(cell, alpha: 1)
        return cell
    }

    private static var haze: CAEmitterCell {
        let cell = CAEmitterCell()
        cell.contents = bokeh
        cell.birthRate = 4
        cell.lifetime = 1.6
        cell.lifetimeRange = 0.4
        cell.velocity = 5
        cell.velocityRange = 4
        cell.emissionRange = .pi * 2
        cell.scale = 0.5
        cell.scaleRange = 0.25
        cell.alphaSpeed = -0.12
        silver(cell, alpha: 0.16, lighter: 0.08)
        return cell
    }

    /// Silver: a cool grey, dark enough to show on a white page, with red and blue each nudged a little either
    /// way for every particle, so some lean warm and yellow and some cool and blue.
    private static func silver(_ cell: CAEmitterCell, alpha: CGFloat, lighter: CGFloat = 0) {
        cell.color = NSColor(red: 0.68 + lighter, green: 0.69 + lighter, blue: 0.71 + lighter, alpha: alpha).cgColor
        cell.redRange = 0.1
        cell.greenRange = 0.03
        cell.blueRange = 0.13
    }

    // The particles are white, tinted by each cell's colour.

    /// A point of light: a bright core in a soft halo.
    private static let dot: CGImage? = image { context, size in
        radial(context, size, stops: [(0, 1), (0.18, 0.9), (0.45, 0.25), (1, 0)])
    }

    /// A glint: a hard bright core, a halo, and the faint thin cross of light a lens draws around one.
    private static let glint: CGImage? = image { context, size in
        radial(context, size, stops: [(0, 1), (0.06, 1), (0.16, 0.35), (0.4, 0)])
        let c = CGPoint(x: size.width / 2, y: size.height / 2)
        for horizontal in [true, false] {
            let colors = [CGColor(gray: 1, alpha: 0), CGColor(gray: 1, alpha: 0.7), CGColor(gray: 1, alpha: 0)] as CFArray
            guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: [0, 0.5, 1])
            else { continue }
            let thickness: CGFloat = 1.2
            let rect = horizontal ? CGRect(x: 0, y: c.y - thickness / 2, width: size.width, height: thickness)
                                  : CGRect(x: c.x - thickness / 2, y: 0, width: thickness, height: size.height)
            context.saveGState()
            context.clip(to: rect)
            context.drawLinearGradient(gradient, start: horizontal ? CGPoint(x: 0, y: c.y) : CGPoint(x: c.x, y: 0),
                                       end: horizontal ? CGPoint(x: size.width, y: c.y) : CGPoint(x: c.x, y: size.height), options: [])
            context.restoreGState()
        }
    }

    /// Out of focus: an even disc with a softened rim.
    private static let bokeh: CGImage? = image { context, size in
        radial(context, size, stops: [(0, 0.55), (0.7, 0.7), (0.85, 0.35), (1, 0)])
    }

    private static func radial(_ context: CGContext, _ size: CGSize, stops: [(CGFloat, CGFloat)]) {
        let colors = stops.map { CGColor(gray: 1, alpha: $0.1) } as CFArray
        guard let gradient = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB), colors: colors, locations: stops.map(\.0))
        else { return }
        let center = CGPoint(x: size.width / 2, y: size.height / 2)
        context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: size.width / 2, options: [])
    }

    private static func image(_ draw: (CGContext, CGSize) -> Void) -> CGImage? {
        let side = 64
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: side, height: side, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
        else { return nil }
        draw(context, CGSize(width: side, height: side))
        return context.makeImage()
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
