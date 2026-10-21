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
    /// While the change is built, smoke in many colours curls up from the bottom edge, thick there and thinning as
    /// it rises a third of the way up, with a faint glow round the edge: noticeable on any ground, and out of the way
    /// of most of the window. When the change goes in the smoke surges for a moment, then a level band of white,
    /// the window's width, whooshes from the bottom to the top with a soft gray shadow just ahead of it, covering the
    /// moment the new code draws and leaving the window clear behind it.
    @MainActor final class Look: NSView {
        /// The colours the smoke mixes: blue, violet, pink, orange and teal.
        static let hues: [NSColor] = [
            NSColor(red: 0.25, green: 0.5, blue: 1, alpha: 1),
            NSColor(red: 0.6, green: 0.38, blue: 1, alpha: 1),
            NSColor(red: 1, green: 0.38, blue: 0.68, alpha: 1),
            NSColor(red: 1, green: 0.6, blue: 0.22, alpha: 1),
            NSColor(red: 0.2, green: 0.82, blue: 0.9, alpha: 1),
        ]

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
        private let band = CAGradientLayer()
        private let wash = CALayer()
        private var arranged = CGRect.zero

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            autoresizingMask = [.width, .height]
            layer?.masksToBounds = true
            layer?.cornerRadius = cornerRadius
            for sublayer in [glowLayer, wash, wisps, band] {
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
            // rounding cuts it off, so all that shows is its shadow coming in from the edge, going round the colours.
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

            // Smoke rising from below the bottom edge, a stream of puffs for each colour. How far it rises goes with
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
                cell.birthRate = Float(bounds.width / 55)
                cell.lifetime = life; cell.lifetimeRange = 1.5
                cell.velocity = rise; cell.velocityRange = rise * 0.45
                cell.emissionLongitude = .pi / 2; cell.emissionRange = 0.55
                cell.xAcceleration = index.isMultiple(of: 2) ? 3 : -3
                cell.scale = 0.8; cell.scaleRange = 0.35; cell.scaleSpeed = 0.16
                cell.alphaSpeed = -0.42 / life
                cell.spinRange = 0.6
                return cell
            }

            // The band: the window's width and level, white through its body, fading out below where it's been, and
            // a narrow gray shadow just above its top edge, ahead of it. Its colours run from the bottom of the layer up.
            let height = max(bounds.height * 0.4, 120), shadow: CGFloat = 24
            band.frame = CGRect(x: 0, y: -height - shadow, width: bounds.width, height: height + shadow)
            band.startPoint = CGPoint(x: 0.5, y: 0)
            band.endPoint = CGPoint(x: 0.5, y: 1)
            let top = Double(height / (height + shadow))
            band.colors = [NSColor(white: 1, alpha: 0), NSColor(white: 1, alpha: 0.85), NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 1),
                           NSColor(white: 0.35, alpha: 0.22), NSColor(white: 0.2, alpha: 0)].map(\.cgColor)
            band.locations = [0, NSNumber(value: top * 0.45), NSNumber(value: top * 0.7), NSNumber(value: top),
                              NSNumber(value: top + 0.001), 1]

            wash.frame = bounds
            wash.backgroundColor = NSColor(white: 1, alpha: 0.35).cgColor
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

        /// The change went in: the smoke surges and the band whooshes up (a soft wash where motion is reduced), and
        /// the glow and the smoke go. Answers how long that takes, after which the layers can go.
        func reveal(still: Bool) -> TimeInterval {
            layoutSubtreeIfNeeded()
            let glowing = glowLayer.presentation()?.opacity ?? glowLayer.opacity
            if still {
                wisps.birthRate = 0
                Self.animate(glowLayer, "opacity", from: glowing, to: 0, duration: 0.6)
                Self.animate(wisps, "opacity", from: wisps.presentation()?.opacity ?? wisps.opacity, to: 0, duration: 0.6)
                Self.animate(wash, "opacity", from: 1, to: 0, duration: 0.7)
                return 0.8
            }
            // The smoke gathers itself, more of it and rising faster, for a moment before the whoosh. Timed by
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

            // Then the band goes up, quickening as it goes, and the smoke and the glow go with it.
            let whoosh = 0.8
            band.opacity = 1
            Self.animate(band, "position.y", from: Float(band.position.y), to: Float(bounds.height + band.bounds.height / 2),
                         duration: whoosh, delay: gather, timing: CAMediaTimingFunction(controlPoints: 0.55, 0, 0.3, 1))
            Self.animate(wisps, "opacity", from: 1, to: 0, duration: 0.6, delay: gather + 0.1)
            Self.animate(glowLayer, "opacity", from: glowing, to: 0, duration: 0.6, delay: gather)
            return gather + whoosh + 0.2
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
