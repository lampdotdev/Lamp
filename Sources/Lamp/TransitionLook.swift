import AppKit
import QuartzCore

/// How an open app shows that Lamp is changing it. The app draws it itself (`LampTransition` in LampSupport.swift), so
/// the block between the markers is copied there word for word, and compiled here too so the gallery draws the very
/// same card over pictures of apps (Transition), without an app or a build. Change it here, then run
/// `scripts/sync-transition-look.sh` to copy it into the template; `TransitionLookTests` fails while the two differ.
/// lamp dev draws the same card over the pages it serves ("The card on a change" in cli/page.js), so a change to how it
/// looks goes there too.
enum LampTransition {
    // TransitionLook
    /// A small card at the foot of the app's window while Lamp builds its change and as it goes in: Lamp's mark
    /// turning, "Updating" and what's changing, in the person's words; then "Updated" for a moment once the change is
    /// in, so every change is seen to land, however quick. It covers nothing but itself, and every click goes through
    /// to the app. Core Animation runs it out of the app's process, so it keeps turning while the app is busy taking
    /// the change in.
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

        /// The window's own rounding: the card keeps its own, so this only says how the window is cut.
        var cornerRadius: CGFloat = 12

        /// What's changing, as the person asked for it, after "Updating": cut to the card's width.
        var words: String? {
            didSet {
                guard words != oldValue else { return }
                arranged = .zero
                needsLayout = true
            }
        }

        /// The card stays at least this long, so a change that lands at once is still seen.
        private static let shownAtLeast = 1.2
        /// "Updated" stays this long before the card goes.
        private static let heldAfter = 1.4
        /// One turn of the mark, in seconds.
        private static let spinEvery = 1.4

        private let card = CALayer()
        private let mark = CALayer()
        private let bands = CALayer()
        private let title = CATextLayer()
        private let detail = CATextLayer()
        private var heading = "Updating"
        private var arranged = CGRect.zero
        private var shownAt: CFTimeInterval?

        override init(frame: NSRect) {
            super.init(frame: frame)
            wantsLayer = true
            autoresizingMask = [.width, .height]
            card.opacity = 0
            card.backgroundColor = NSColor(white: 0.08, alpha: 0.86).cgColor
            card.borderColor = NSColor(white: 1, alpha: 0.12).cgColor
            card.borderWidth = 1
            card.shadowColor = NSColor.black.cgColor
            card.shadowOpacity = 0.3
            card.shadowRadius = 12
            card.shadowOffset = CGSize(width: 0, height: -3)
            layer?.addSublayer(card)
            // Lamp's mark: its stripes on their slant, in a disc, which turns while the change is under way.
            mark.masksToBounds = true
            for (index, hue) in Self.hues.enumerated() {
                let band = CALayer()
                band.backgroundColor = hue.cgColor
                band.name = String(index)
                bands.addSublayer(band)
            }
            mark.addSublayer(bands)
            card.addSublayer(mark)
            for text in [title, detail] {
                text.isWrapped = false
                text.truncationMode = .end
                text.alignmentMode = .left
                text.foregroundColor = NSColor.white.cgColor
                card.addSublayer(text)
            }
            title.font = NSFont.systemFont(ofSize: 13, weight: .semibold)
            title.fontSize = 13
            detail.font = NSFont.systemFont(ofSize: 13)
            detail.fontSize = 13
            detail.opacity = 0.72
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

        private static func width(of text: String, weight: NSFont.Weight) -> CGFloat {
            ceil(NSAttributedString(string: text, attributes: [.font: NSFont.systemFont(ofSize: 13, weight: weight)]).size().width)
        }

        private func arrange() {
            let scale = window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2
            let words = (self.words ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            let height: CGFloat = 36, side: CGFloat = 18, inset: CGFloat = 12
            let titleWidth = Self.width(of: heading, weight: .semibold)
            let wordsWidth = words.isEmpty ? 0 : Self.width(of: words, weight: .regular) + 8
            let widest = max(160, min(bounds.width - 32, 460))
            let width = min(widest, inset + side + 8 + titleWidth + wordsWidth + inset + 4)
            card.frame = CGRect(x: ((bounds.width - width) / 2).rounded(), y: min(20, bounds.height * 0.06), width: width, height: height)
            card.cornerRadius = height / 2
            card.shadowPath = CGPath(roundedRect: card.bounds, cornerWidth: height / 2, cornerHeight: height / 2, transform: nil)
            mark.frame = CGRect(x: inset, y: (height - side) / 2, width: side, height: side)
            mark.cornerRadius = side / 2
            // Wider than the disc, so its stripes reach the edge however it's turned.
            let across = side * 1.6
            bands.bounds = CGRect(x: 0, y: 0, width: across, height: across)
            bands.position = CGPoint(x: side / 2, y: side / 2)
            for band in bands.sublayers ?? [] {
                let index = CGFloat(Int(band.name ?? "0") ?? 0)
                band.frame = CGRect(x: 0, y: across - (index + 1) * across / 6, width: across, height: across / 6 + 0.5)
            }
            if bands.animation(forKey: "spin") == nil { bands.transform = CATransform3DMakeRotation(.pi / 6, 0, 0, 1) }
            let line: CGFloat = 17, textY = (height - line) / 2
            let textX = inset + side + 8
            title.contentsScale = scale
            detail.contentsScale = scale
            title.string = heading
            title.frame = CGRect(x: textX, y: textY, width: min(titleWidth, width - textX - inset), height: line)
            detail.string = words
            let detailX = textX + titleWidth + 8
            detail.frame = CGRect(x: detailX, y: textY, width: max(0, width - detailX - inset - 4), height: line)
        }

        /// A change is being built: the card comes up with "Updating" and the mark turning.
        func glow(still: Bool) {
            say("Updating")
            show(still: still)
            spin(still: still)
        }

        /// The app stands still taking the change in (a game running its code again): the card stays as it is.
        func turn(still: Bool) { glow(still: still) }

        /// The change is in: "Updated", the mark stops, and the card goes after a moment. A change that lands without
        /// a begin (a copy just opened with it) shows the card all the same.
        func reveal(still: Bool) -> TimeInterval {
            show(still: still)
            say("Updated")
            bands.removeAnimation(forKey: "spin")
            bands.transform = CATransform3DMakeRotation(.pi / 6, 0, 0, 1)
            if !still {
                let pop = CABasicAnimation(keyPath: "transform.scale")
                pop.fromValue = 1.25
                pop.toValue = 1
                pop.duration = 0.3
                pop.timingFunction = CAMediaTimingFunction(name: .easeOut)
                mark.add(pop, forKey: "pop")
            }
            let now = CACurrentMediaTime()
            let wait = max(Self.heldAfter, Self.shownAtLeast - (now - (shownAt ?? now)))
            Self.animate(card, "opacity", from: 1, to: 0, duration: 0.3, delay: wait)
            return wait + 0.35
        }

        /// Nothing goes in after all (the build failed, or the change waits for the person): the card goes.
        func fade() -> TimeInterval {
            guard shownAt != nil else { return 0 }
            Self.animate(card, "opacity", from: card.presentation()?.opacity ?? card.opacity, to: 0, duration: 0.25)
            return 0.3
        }

        private func say(_ heading: String) {
            guard heading != self.heading else { return }
            self.heading = heading
            arranged = .zero
            needsLayout = true
            layoutSubtreeIfNeeded()
        }

        private func show(still: Bool) {
            guard shownAt == nil else { return }
            shownAt = CACurrentMediaTime()
            layoutSubtreeIfNeeded()
            Self.animate(card, "opacity", from: 0, to: 1, duration: still ? 0.15 : 0.25)
            guard !still else { return }
            let rise = CABasicAnimation(keyPath: "transform.translation.y")
            rise.fromValue = -10
            rise.toValue = 0
            rise.duration = 0.3
            rise.timingFunction = CAMediaTimingFunction(name: .easeOut)
            card.add(rise, forKey: "rise")
        }

        private func spin(still: Bool) {
            guard !still, bands.animation(forKey: "spin") == nil else { return }
            let spin = CABasicAnimation(keyPath: "transform.rotation.z")
            spin.fromValue = CGFloat.pi / 6
            spin.toValue = CGFloat.pi / 6 - 2 * .pi
            spin.duration = Self.spinEvery
            spin.repeatCount = .infinity
            bands.add(spin, forKey: "spin")
        }

        private static func animate(_ layer: CALayer, _ key: String, from: Float, to: Float, duration: Double, delay: Double = 0) {
            let animation = CABasicAnimation(keyPath: key)
            animation.fromValue = from
            animation.toValue = to
            animation.duration = duration
            animation.beginTime = CACurrentMediaTime() + delay
            animation.fillMode = .backwards
            animation.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            layer.setValue(to, forKeyPath: key)
            layer.add(animation, forKey: key)
        }
    }
    // end TransitionLook
}
