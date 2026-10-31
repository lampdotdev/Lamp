import AppKit
import QuartzCore

/// How the light on an open app looks while Lamp builds its change and as the change goes in. The app draws it
/// itself (`LampTransition` in LampSupport.swift), so the block between the markers is copied there word for word,
/// and compiled here too so the gallery draws the very same layers over pictures of apps (Transition), without an
/// app or a build. Change it here, then run `scripts/sync-transition-look.sh` to copy it into the template;
/// `TransitionLookTests` fails while the two differ.
enum LampTransition {
    // TransitionLook
    /// The effect's layers, filling the window they're laid over and cut to its rounding. Core Animation runs
    /// them out of the app's process, so they keep moving while the app is busy taking the change in.
    ///
    /// While the change is built, smoke in Lamp's stripe colors curls up from the bottom edge, thick there and thinning
    /// as it rises a third of the way up, with a faint glow round the edge: noticeable on any ground, and out of the way
    /// of most of the window. When the change goes in the smoke surges for a moment, then the stripes roll up the window
    /// on Lamp's slant, as if round a drum: each comes in as a thin line, widens to the middle and thins again as it
    /// leaves, and at the middle of the roll they cover the window whole, leaving it clear behind them.
    @MainActor final class Look: NSView {
        /// Lamp's stripes, in the order they come up: green, lime, yellow, orange, red and magenta.
        static let hues: [NSColor] = [
            NSColor(red: 0.122, green: 0.541, blue: 0.29, alpha: 1),
            NSColor(red: 0.486, green: 0.749, blue: 0.227, alpha: 1),
            NSColor(red: 0.965, green: 0.722, blue: 0.11, alpha: 1),
            NSColor(red: 0.941, green: 0.541, blue: 0.11, alpha: 1),
            NSColor(red: 0.886, green: 0.251, blue: 0.165, alpha: 1),
            NSColor(red: 0.824, green: 0.216, blue: 0.471, alpha: 1),
        ]

        /// The stripes' slant, as on the website: rising to the right.
        private static let slant: CGFloat = .pi / 6

        /// The window's own rounding, so the glow follows its corners.
        var cornerRadius: CGFloat = 12 {
            didSet {
                guard cornerRadius != oldValue else { return }
                layer?.cornerRadius = cornerRadius
                arranged = .zero
                needsLayout = true
            }
        }

        private let glowLayer = CALayer()
        private let wisps = CAEmitterLayer()
        private let stripes = CALayer()
        private var arranged = CGRect.zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            autoresizingMask = [.width, .height]
            layer?.masksToBounds = true
            layer?.cornerRadius = cornerRadius
            for sublayer in [glowLayer, wisps, stripes] {
                sublayer.opacity = 0
                layer?.addSublayer(sublayer)
            }
            wisps.birthRate = 0
        }

        required init?(coder: NSCoder) { nil }

        /// Every click goes through to what's under it.
        override func hitTest(_ point: NSPoint) -> NSView? { nil }

        override func setFrameSize(_ newSize: NSSize) {
            super.setFrameSize(newSize)
            needsLayout = true
        }

        override func layout() {
            super.layout()
            guard bounds != arranged, bounds.width > 0, bounds.height > 0 else { return }
            arranged = bounds
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            arrange()
            CATransaction.commit()
        }

        private func arrange() {
            // Only blur, no line: each band of the glow is drawn just outside the window, where the window's own
            // rounding cuts it off, so all that shows is its shadow coming in from the edge, going round the colors.
            glowLayer.frame = bounds
            glowLayer.sublayers?.forEach { $0.removeFromSuperlayer() }
            for (blur, strength) in [(CGFloat(54), Float(0.8)), (24, 1)] {
                let width: CGFloat = 40
                let edge = CAShapeLayer()
                edge.frame = bounds
                edge.path = CGPath(roundedRect: bounds.insetBy(dx: -width / 2, dy: -width / 2), cornerWidth: cornerRadius + width / 2,
                                   cornerHeight: cornerRadius + width / 2, transform: nil)
                edge.fillColor = nil
                edge.strokeColor = NSColor.white.cgColor
                edge.lineWidth = width
                edge.shadowColor = Self.hues[0].cgColor
                edge.shadowOpacity = strength
                edge.shadowRadius = blur
                edge.shadowOffset = .zero
                let cycle = CAKeyframeAnimation(keyPath: "shadowColor")
                cycle.values = (Self.hues + [Self.hues[0]]).map(\.cgColor)
                cycle.duration = 5
                cycle.repeatCount = .infinity
                edge.add(cycle, forKey: "hue")
                glowLayer.addSublayer(edge)
            }

            // Smoke rising from below the bottom edge, a stream of puffs for each color. How far it rises goes with
            // the window's height (speed times life, and the puffs growing), so it reaches about a third of the way
            // up at any size.
            wisps.frame = bounds
            wisps.emitterShape = .line
            wisps.emitterPosition = CGPoint(x: bounds.midX, y: -24)
            wisps.emitterSize = CGSize(width: bounds.width * 1.1, height: 0)
            let rise = bounds.height * 0.1, life: Float = 6
            wisps.emitterCells = Self.hues.enumerated().map { index, hue in
                let cell = CAEmitterCell()
                cell.contents = Self.puff
                cell.color = hue.withAlphaComponent(0.42).cgColor
                cell.redRange = 0.08; cell.greenRange = 0.08; cell.blueRange = 0.08
                cell.birthRate = Float(bounds.width / 66)
                cell.lifetime = life; cell.lifetimeRange = 1.5
                cell.velocity = rise; cell.velocityRange = rise * 0.45
                cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.55
                cell.xAcceleration = index.isMultiple(of: 2) ? 3 : -3
                cell.scale = 0.8; cell.scaleRange = 0.35; cell.scaleSpeed = 0.16
                cell.alphaSpeed = -0.42 / life
                cell.spinRange = 0.6
                return cell
            }

            // The stripes: level in a layer turned to the slant and just big enough that, across its height, they reach
            // from one corner of the window to the opposite one. Each starts with no height, waiting at the bottom.
            let along = bounds.width * cos(Self.slant) + bounds.height * sin(Self.slant)
            let across = bounds.width * sin(Self.slant) + bounds.height * cos(Self.slant)
            stripes.bounds = CGRect(x: 0, y: 0, width: along, height: across)
            stripes.position = CGPoint(x: bounds.midX, y: bounds.midY)
            stripes.setAffineTransform(CGAffineTransform(rotationAngle: Self.slant))
            stripes.sublayers?.forEach { $0.removeFromSuperlayer() }
            for (index, hue) in Self.hues.enumerated() {
                let stripe = CALayer()
                stripe.backgroundColor = hue.cgColor
                stripe.allowsEdgeAntialiasing = true
                stripe.anchorPoint = .zero
                Self.place(stripe, index: index, roll: 0, across: across, along: along)
                stripes.addSublayer(stripe)
            }
        }

        /// Where a stripe's edges are at a point of the roll, from 0 to 2π: the stripes lie side by side round a drum
        /// whose near half is the window. An edge's height is the drum's seen from the front, so the stripes are thin
        /// where the drum turns away, top and bottom, and the six together are as tall as the window at π.
        private static func edges(index: Int, roll: CGFloat, across: CGFloat) -> (bottom: CGFloat, top: CGFloat) {
            let share = CGFloat.pi / CGFloat(hues.count)
            func height(_ angle: CGFloat) -> CGFloat { (1 - cos(min(max(angle, 0), .pi))) / 2 * across }
            return (height(roll - CGFloat(index + 1) * share), height(roll - CGFloat(index) * share))
        }

        /// A stripe at a point of the roll, held a point past its lower edge so no line of the window shows between two.
        private static func place(_ stripe: CALayer, index: Int, roll: CGFloat, across: CGFloat, along: CGFloat) {
            let edge = edges(index: index, roll: roll, across: across)
            stripe.position = CGPoint(x: 0, y: edge.bottom)
            stripe.bounds = CGRect(x: 0, y: 0, width: along, height: edge.top > edge.bottom ? edge.top - edge.bottom + 1 : 0)
        }

        /// A puff of smoke: white, soft all the way to its edge, tinted by the cell that uses it.
        private static let puff: CGImage? = {
            let size = 128
            guard let context = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8, bytesPerRow: 0,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue),
                  let gradient = CGGradient(colorsSpace: nil, colors: [NSColor(white: 1, alpha: 0.9).cgColor, NSColor(white: 1, alpha: 0.45).cgColor,
                                                                       NSColor(white: 1, alpha: 0).cgColor] as CFArray, locations: [0, 0.45, 1])
            else { return nil }
            let center = CGPoint(x: size / 2, y: size / 2)
            context.drawRadialGradient(gradient, startCenter: center, startRadius: 0, endCenter: center, endRadius: CGFloat(size / 2), options: [])
            return context.makeImage()
        }()

        /// The glow and the smoke come up; where motion is reduced, only the glow, still.
        func glow(still: Bool) {
            layoutSubtreeIfNeeded()
            Self.animate(glowLayer, "opacity", from: 0, to: 0.22, duration: 0.6)
            guard !still else { return }
            Self.animate(wisps, "opacity", from: 0, to: 1, duration: 1.2)
            wisps.birthRate = 1
        }

        /// The change went in: the smoke surges and the stripes roll up (the stripes fading where motion is reduced), and
        /// the glow and the smoke go. Answers how long that takes, after which the layers can go.
        func reveal(still: Bool) -> TimeInterval {
            layoutSubtreeIfNeeded()
            let glowing = glowLayer.presentation()?.opacity ?? glowLayer.opacity
            let across = stripes.bounds.height, along = stripes.bounds.width
            let layers = stripes.sublayers ?? []
            if still {
                wisps.birthRate = 0
                Self.animate(glowLayer, "opacity", from: glowing, to: 0, duration: 0.6)
                Self.animate(wisps, "opacity", from: wisps.presentation()?.opacity ?? wisps.opacity, to: 0, duration: 0.6)
                CATransaction.begin()
                CATransaction.setDisableActions(true)
                for (index, stripe) in layers.enumerated() {
                    Self.place(stripe, index: index, roll: .pi, across: across, along: along)
                }
                CATransaction.commit()
                Self.animate(stripes, "opacity", from: 0.35, to: 0, duration: 0.7)
                return 0.8
            }
            // The smoke gathers itself, more of it and rising faster, for a moment before the roll. Timed by
            // animations, not by the main thread, which may be busy with the new code.
            let gather = 0.3
            wisps.opacity = 1
            Self.animate(wisps, "velocity", from: 1, to: 3.5, duration: gather, timing: CAMediaTimingFunction(name: .easeIn))
            let surge = CAKeyframeAnimation(keyPath: "birthRate")
            surge.values = [1, 3, 0]
            surge.keyTimes = [0, 0.95, 1]
            surge.duration = gather
            surge.calculationMode = .discrete
            wisps.birthRate = 0
            wisps.add(surge, forKey: "surge")

            // Then the stripes roll up at the drum's steady turn, which is what eases them in and out at the edges, and
            // the smoke and the glow go with them. Each stripe's edges are worked out ahead along the roll, so Core
            // Animation can run them without the app.
            let roll = 1.1
            let steps = 60
            let times = (0...steps).map { NSNumber(value: Double($0) / Double(steps)) }
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            stripes.opacity = 1
            for (index, stripe) in layers.enumerated() {
                let frames = (0...steps).map { Self.edges(index: index, roll: 2 * .pi * CGFloat($0) / CGFloat(steps), across: across) }
                Self.follow(stripe, "position.y", values: frames.map(\.bottom), times: times, duration: roll, delay: gather)
                Self.follow(stripe, "bounds.size.height", values: frames.map { $0.top > $0.bottom ? $0.top - $0.bottom + 1 : 0 },
                            times: times, duration: roll, delay: gather)
                Self.place(stripe, index: index, roll: 2 * .pi, across: across, along: along)
            }
            CATransaction.commit()
            Self.animate(wisps, "opacity", from: 1, to: 0, duration: 0.6, delay: gather + 0.1)
            Self.animate(glowLayer, "opacity", from: glowing, to: 0, duration: 0.6, delay: gather)
            return gather + roll + 0.2
        }

        private static func follow(_ layer: CALayer, _ key: String, values: [CGFloat], times: [NSNumber], duration: Double, delay: Double) {
            let animation = CAKeyframeAnimation(keyPath: key)
            animation.values = values
            animation.keyTimes = times
            animation.duration = duration
            animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
            animation.fillMode = .backwards
            layer.add(animation, forKey: key)
        }

        /// The glow and the smoke go without a change going in. Answers how long that takes.
        func fade() -> TimeInterval {
            wisps.birthRate = 0
            Self.animate(glowLayer, "opacity", from: glowLayer.presentation()?.opacity ?? glowLayer.opacity, to: 0, duration: 0.5)
            Self.animate(wisps, "opacity", from: wisps.presentation()?.opacity ?? wisps.opacity, to: 0, duration: 1.0)
            return 1.1
        }

        private static func animate(_ layer: CALayer, _ key: String, from: Float, to: Float, duration: Double, delay: Double = 0,
                                    timing: CAMediaTimingFunction = CAMediaTimingFunction(name: .easeOut)) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.timingFunction = timing
            if delay > 0 {
                animation.beginTime = layer.convertTime(CACurrentMediaTime(), from: nil) + delay
                animation.fillMode = .backwards
            }
            layer.setValue(to, forKey: key)
            layer.add(animation, forKey: key)
        }
    }
    // end TransitionLook
}
