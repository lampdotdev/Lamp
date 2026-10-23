import AppKit
import QuartzCore
import SwiftUI

/// What the person sees while an app uses another app: a glow around the window being used, a cursor of
/// Lamp's own that glides to each spot before anything happens there, and a pulse where it clicks.
///
/// The drivers work in the background and never move the real pointer, so without this a task is invisible
/// until its result appears. Nothing here takes clicks or the keyboard: both windows ignore the mouse.
/// Geometry comes in the drivers' space, screen points with the origin at the top left of the main display.
@MainActor
final class ComputerOverlay {
    static let shared = ComputerOverlay()

    /// Lamplight: warm, and unlike any system highlight.
    static let tint = NSColor(red: 1.0, green: 0.70, blue: 0.26, alpha: 1)

    private var cursorWindow: NSWindow?
    private var cursorLayer: CALayer?
    /// What the cursor is now: an arrow over a Mac window, a fingertip over an iPhone's screen.
    private var cursorFinger = false
    private var cursorPosition: CGPoint?   // in the cursor window's own coordinates
    /// When the glide under way ends: a move to the spot the cursor is already bound for waits for it to get there.
    private var cursorArrival: ContinuousClock.Instant?
    private var glowWindow: NSWindow?
    private var glowTarget: CGWindowID?
    /// The stop control riding on the glow, and what it stops.
    private var stopPill: NSPanel?
    private var onStop: (() -> Void)?
    /// The task was handed back to the person: the pill says so for a moment, in place of Stop.
    private var handedBack = false
    /// The task showing now. Two apps' tasks can run at once; the latest to show takes the overlay, and an
    /// earlier one finishing leaves it alone.
    private var owner: ObjectIdentifier?
    private var tracker: Timer?
    private var hideWork: DispatchWorkItem?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: The window in use

    /// Glows around a window and keeps following it, just above it in the stack: a window in front of it
    /// still covers the glow, so a window that's only being read doesn't seem to jump forward.
    /// `label` says whose task it is, on the stop control above the window; `stop` is what it does, and
    /// `escape` shows that Esc does it too (the caller watches for the key).
    func focus(window id: CGWindowID, label: String, owner: ObjectIdentifier, escape: Bool = false, stop: @escaping () -> Void) {
        cancelHide()
        self.owner = owner
        onStop = stop
        handedBack = false
        defer { showStop(label, escape: escape) }   // once the window is known, so it opens in its place
        guard glowTarget != id || glowWindow?.isVisible != true else { return }
        glowTarget = id
        guard let frame = Self.frame(of: id) else { glowWindow?.orderOut(nil); return }
        let window = glowWindow ?? makeGlowWindow()
        glowWindow = window
        place(window, around: frame, above: id)
        window.alphaValue = 0
        window.orderFront(nil)
        place(window, around: frame, above: id)
        NSAnimationContext.runAnimationGroup { $0.duration = 0.25; window.animator().alphaValue = 1 }
        tracker?.invalidate()
        tracker = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.follow() }
        }
    }

    private func follow() {
        guard let id = glowTarget, let window = glowWindow else { return }
        guard let frame = Self.frame(of: id) else { window.orderOut(nil); return }   // closed or minimized
        if !window.isVisible { window.orderFront(nil) }
        place(window, around: frame, above: id)
        placeStop(above: frame)
        stackStop()
    }

    // MARK: Stopping

    /// A small pill just above the window in use: whose task this is, and Stop. Above the window rather
    /// than on it so it covers none of the window's own controls; below it when there's no room above.
    /// It belongs to that window in the stack as the glow does: a window the person brings in front of the app
    /// covers it, so it never floats over whatever else they're doing.
    private func showStop(_ label: String, escape: Bool) {
        let view = StopPill(label: label, escape: escape) { [weak self] in
            guard let self else { return }
            let stop = self.onStop
            self.onStop = nil
            stop?()
            // A task that hands back (`handBack`) keeps the pill to say so; any other goes with it.
            if !self.handedBack { self.stopPill?.orderOut(nil) }
        }
        show(pill: view)
    }

    private func show(pill view: some View) {
        let pill = stopPill ?? {
            let panel = NonKeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.setAccessibilityLabel("Stop the task")
            return panel
        }()
        stopPill = pill
        let middle = pill.isVisible ? pill.frame.midX : nil
        let host = FirstClickHost(rootView: view)
        host.frame.size = host.fittingSize
        pill.contentView = host
        pill.setContentSize(host.fittingSize)
        if let id = glowTarget, let frame = Self.frame(of: id) { placeStop(above: frame) }
        // With no window to sit over any more (it was handed back), it stays centred where it was.
        else if let middle { pill.setFrameOrigin(CGPoint(x: middle - pill.frame.width / 2, y: pill.frame.minY)) }
        if !pill.isVisible {
            pill.alphaValue = 0
            pill.orderFrontRegardless()
            stackStop()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; pill.animator().alphaValue = 1 }
        }
    }

    /// Just above the glow, which is just above the window in use, so the glow's light never draws over the pill.
    /// Lamp coming forward raises all its windows over other apps', so this is done again each time the glow follows.
    private func stackStop() {
        guard let pill = stopPill, pill.isVisible, let id = glowTarget else { return }
        if let glow = glowWindow, glow.isVisible { pill.order(.above, relativeTo: glow.windowNumber) }
        else { pill.order(.above, relativeTo: Int(id)) }
    }

    private func placeStop(above frame: CGRect) {
        guard let pill = stopPill else { return }
        let window = Self.cocoa(frame)
        let size = pill.frame.size
        let screen = (NSScreen.screens.first { $0.frame.intersects(window) } ?? NSScreen.main)?.visibleFrame ?? window
        var origin = CGPoint(x: window.midX - size.width / 2, y: window.maxY + 8)
        if origin.y + size.height > screen.maxY {
            origin.y = window.minY - 8 - size.height                  // below the window
            if origin.y < screen.minY { origin.y = window.maxY - size.height - 40 }   // inside, under the title bar
        }
        origin.x = min(max(origin.x, screen.minX + 8), screen.maxX - size.width - 8)
        if pill.frame.origin != origin { pill.setFrameOrigin(origin) }
    }

    /// How far the glow reaches out from the window's edge before it has faded away.
    private static let glowReach: CGFloat = 14
    /// Room around the window for the glow to fade out in.
    private static let glowMargin: CGFloat = glowReach + 10

    private func place(_ window: NSWindow, around frame: CGRect, above id: CGWindowID) {
        let cocoa = Self.cocoa(frame).insetBy(dx: -Self.glowMargin, dy: -Self.glowMargin)
        if window.frame != cocoa { window.setFrame(cocoa, display: true) }
        window.order(.above, relativeTo: Int(id))
    }

    /// Lamplight around the window: a halo that is brightest at the window's edge and fades out over the room
    /// around it, with a fine line along the edge itself. The halo is the window's own shape lit from behind (a
    /// blurred fill of it), shown only outside the window: the glow sits above the window in the stack, so
    /// anything drawn inside its edge would cover the app.
    private final class Glow {
        let halo = CAShapeLayer()
        let near = CAShapeLayer()      // the brighter light close to the edge, under the wide halo
        let line = CAShapeLayer()
        let outside = CAShapeLayer()   // the mask: everything but the window
        let holder = CALayer()

        init() {
            halo.fillColor = ComputerOverlay.tint.cgColor
            halo.shadowColor = ComputerOverlay.tint.cgColor
            halo.shadowOpacity = 1
            halo.shadowRadius = ComputerOverlay.glowReach / 2
            halo.shadowOffset = .zero
            near.fillColor = ComputerOverlay.tint.cgColor
            near.shadowColor = ComputerOverlay.tint.cgColor
            near.shadowOpacity = 0.9
            near.shadowRadius = ComputerOverlay.glowReach / 5
            near.shadowOffset = .zero
            outside.fillRule = .evenOdd
            outside.fillColor = NSColor.black.cgColor
            holder.mask = outside
            holder.addSublayer(halo)
            holder.addSublayer(near)
            line.fillColor = nil
            line.strokeColor = ComputerOverlay.tint.withAlphaComponent(0.95).cgColor
            line.lineWidth = 2
        }

        func layout(in bounds: CGRect) {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            for layer in [holder, halo, near, outside, line] { layer.frame = bounds }
            // Just outside the window's own edge, with the rounding macOS gives windows.
            let edge = bounds.insetBy(dx: ComputerOverlay.glowMargin - 2, dy: ComputerOverlay.glowMargin - 2)
            let window = CGPath(roundedRect: edge, cornerWidth: 14, cornerHeight: 14, transform: nil)
            halo.path = window
            near.path = window
            line.path = window
            let cut = CGMutablePath()
            cut.addRect(bounds)
            cut.addPath(window)
            outside.path = cut
            CATransaction.commit()
        }
    }

    private func makeGlowWindow() -> NSWindow {
        let window = Self.clearWindow(level: .normal)
        let view = NSView()
        view.wantsLayer = true
        let glow = Glow()
        view.layer?.addSublayer(glow.holder)
        view.layer?.addSublayer(glow.line)
        window.contentView = view
        // Drawn again whenever the window is resized to follow its target.
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { glow.layout(in: view.bounds) }
        }
        glow.layout(in: view.bounds)
        if !reduceMotion {
            // The halo breathes: wider and brighter, then back, like a lamp's light wavering.
            let breathe = CABasicAnimation(keyPath: "shadowRadius")
            breathe.fromValue = Self.glowReach / 2
            breathe.toValue = Self.glowReach / 2 * 1.2
            let brighten = CABasicAnimation(keyPath: "opacity")
            brighten.fromValue = 0.85
            brighten.toValue = 1
            let group = CAAnimationGroup()
            group.animations = [breathe, brighten]
            group.duration = 1.6
            group.autoreverses = true
            group.repeatCount = .infinity
            group.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            glow.halo.add(group, forKey: "breathe")
        }
        return window
    }

    // MARK: The cursor

    // MARK: Handing back

    /// The person took the task back: the glow and the cursor go at once, and the pill says the app is theirs
    /// for a moment before it fades too.
    func handBack(owner: ObjectIdentifier, saying message: String) {
        guard owner == self.owner else { return }
        cancelHide()
        handedBack = true
        onStop = nil
        tracker?.invalidate()
        tracker = nil
        glowTarget = nil
        if let glow = glowWindow {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.2; glow.animator().alphaValue = 0 },
                                                 completionHandler: { glow.orderOut(nil) })
        }
        if let cursor = cursorLayer { fade(cursor, to: 0, duration: 0.2) }
        cursorPosition = nil
        show(pill: HandBackPill(message: message))
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideNow() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: work)
    }

    // MARK: The cursor

    /// Glides Lamp's cursor to a point and returns when it's there. The first move of a task starts from the
    /// middle of the window in use, so the cursor never seems to come from nowhere. `caption` rides beside it
    /// ("Lamp · clicking Add"); `finger` draws a fingertip in place of the arrow, for an iPhone's screen;
    /// `within` caps the glide, for an action that follows after a set time.
    func move(to point: CGPoint, app icon: NSImage?, owner: ObjectIdentifier, caption: String? = nil, finger: Bool = false,
              within: Double? = nil) async {
        // The window, its Stop and the cursor are one task's at a time, taken by `focus`: a task that has
        // been superseded since doesn't move the cursor over another task's window, or take its controls.
        guard self.owner == nil || self.owner == owner, !handedBack else { return }
        cancelHide()
        self.owner = owner
        let (window, layer) = ensureCursor(icon: icon, finger: finger)
        setCaption(caption, on: layer)
        let target = window.convertPoint(fromScreen: Self.cocoa(point))
        guard let bound = cursorPosition, !reduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = target
            CATransaction.commit()
            cursorPosition = target
            fade(layer, to: 1, duration: reduceMotion ? 0.15 : 0.2)
            try? await Task.sleep(for: .milliseconds(200))
            return
        }
        let distance = hypot(target.x - bound.x, target.y - bound.y)
        guard distance > 1 else {
            // Already bound there, sent ahead of this action: it's there once that glide ends.
            if let cursorArrival, cursorArrival > .now { try? await Task.sleep(until: cursorArrival, clock: .continuous) }
            return
        }
        // From where it is now, a glide still under way included, so a new spot never makes it jump.
        let from = layer.presentation()?.position ?? bound
        let span = max(1, hypot(target.x - from.x, target.y - from.y))
        // Quick for a hop, slower across the screen, never sluggish.
        let duration = min(within ?? 0.9, 0.9, max(0.3, 0.25 + Double(span) / 1800))
        // A gentle arc, bowed to one side like a hand's movement rather than a straight slide.
        let mid = CGPoint(x: (from.x + target.x) / 2, y: (from.y + target.y) / 2)
        let normal = CGPoint(x: -(target.y - from.y) / span, y: (target.x - from.x) / span)
        let bow = min(120, span * 0.18)
        let control = CGPoint(x: mid.x + normal.x * bow, y: mid.y + normal.y * bow)
        let path = CGMutablePath()
        path.move(to: from)
        path.addQuadCurve(to: target, control: control)
        let glide = CAKeyframeAnimation(keyPath: "position")
        glide.path = path
        glide.duration = duration
        glide.timingFunction = CAMediaTimingFunction(controlPoints: 0.45, 0, 0.2, 1)
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layer.position = target
        layer.opacity = 1
        CATransaction.commit()
        layer.add(glide, forKey: "glide")
        cursorPosition = target
        cursorArrival = .now + .seconds(duration)
        try? await Task.sleep(for: .seconds(duration))
    }

    /// The cursor's press: it dips, and a ring of light spreads from the spot with a few sparks.
    func click(at point: CGPoint, owner: ObjectIdentifier) {
        guard owner == self.owner else { return }   // see `move`
        cancelHide()
        guard let window = cursorWindow, let root = window.contentView?.layer else { return }
        let center = window.convertPoint(fromScreen: Self.cocoa(point))
        if let cursor = cursorLayer {
            let press = CAKeyframeAnimation(keyPath: "transform.scale")
            press.values = [1, 0.82, 1]
            press.keyTimes = [0, 0.35, 1]
            press.duration = 0.28
            cursor.add(press, forKey: "press")
        }
        for (delay, size) in [(0.0, 64.0), (0.12, 92.0)] {
            let ring = CAShapeLayer()
            ring.path = CGPath(ellipseIn: CGRect(x: -size / 2, y: -size / 2, width: size, height: size), transform: nil)
            ring.position = center
            ring.fillColor = Self.tint.withAlphaComponent(delay == 0 ? 0.18 : 0).cgColor
            ring.strokeColor = Self.tint.cgColor
            ring.lineWidth = 2
            ring.shadowColor = Self.tint.cgColor
            ring.shadowOpacity = 0.8
            ring.shadowRadius = 6
            ring.shadowOffset = .zero
            ring.opacity = 0
            root.insertSublayer(ring, below: cursorLayer)
            let grow = CABasicAnimation(keyPath: "transform.scale")
            grow.fromValue = 0.15
            grow.toValue = 1
            let fadeOut = CAKeyframeAnimation(keyPath: "opacity")
            fadeOut.values = [0.95, 0.6, 0]
            fadeOut.keyTimes = [0, 0.4, 1]
            let group = CAAnimationGroup()
            group.animations = [grow, fadeOut]
            group.duration = reduceMotion ? 0.3 : 0.65
            group.beginTime = CACurrentMediaTime() + delay
            group.timingFunction = CAMediaTimingFunction(name: .easeOut)
            ring.add(group, forKey: "pulse")
            remove(ring, after: delay + group.duration)
        }
        guard !reduceMotion else { return }
        for index in 0..<7 {
            let spark = CAShapeLayer()
            let size = CGFloat.random(in: 5...9)
            spark.path = Self.sparkle(size)
            spark.fillColor = (index.isMultiple(of: 3) ? NSColor.white : Self.tint).cgColor
            spark.shadowColor = Self.tint.cgColor
            spark.shadowOpacity = 1
            spark.shadowRadius = 3
            spark.shadowOffset = .zero
            spark.position = center
            spark.opacity = 0
            root.insertSublayer(spark, below: cursorLayer)
            let angle = CGFloat(index) / 7 * 2 * .pi + CGFloat.random(in: -0.3...0.3)
            let reach = CGFloat.random(in: 30...54)
            let fly = CABasicAnimation(keyPath: "position")
            fly.fromValue = NSValue(point: center)
            fly.toValue = NSValue(point: CGPoint(x: center.x + cos(angle) * reach, y: center.y + sin(angle) * reach))
            fly.timingFunction = CAMediaTimingFunction(controlPoints: 0.1, 0.8, 0.3, 1)
            let spin = CABasicAnimation(keyPath: "transform.rotation")
            spin.toValue = Double.random(in: -2...2)
            let twinkle = CAKeyframeAnimation(keyPath: "opacity")
            twinkle.values = [0, 1, 1, 0]
            twinkle.keyTimes = [0, 0.15, 0.6, 1]
            let shrink = CABasicAnimation(keyPath: "transform.scale")
            shrink.fromValue = 1.2
            shrink.toValue = 0.3
            let group = CAAnimationGroup()
            group.animations = [fly, spin, twinkle, shrink]
            group.duration = Double.random(in: 0.55...0.8)
            group.beginTime = CACurrentMediaTime() + 0.04
            spark.add(group, forKey: "spark")
            remove(spark, after: 0.04 + group.duration)
        }
    }

    /// The task is over: everything fades away shortly after, unless another task picks up.
    func end(owner: ObjectIdentifier) {
        guard owner == self.owner else { return }
        cancelHide()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.hideNow() }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: work)
    }

    private func hideNow() {
        tracker?.invalidate()
        tracker = nil
        glowTarget = nil
        onStop = nil
        owner = nil
        handedBack = false
        if let pill = stopPill {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; pill.animator().alphaValue = 0 },
                                                 completionHandler: { pill.orderOut(nil) })
        }
        if let cursor = cursorLayer { fade(cursor, to: 0, duration: 0.3) }
        cursorPosition = nil
        if let glow = glowWindow {
            NSAnimationContext.runAnimationGroup({ $0.duration = 0.3; glow.animator().alphaValue = 0 },
                                                 completionHandler: { glow.orderOut(nil) })
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.cursorPosition == nil else { return }
                self.cursorWindow?.orderOut(nil)
            }
        }
    }

    private func cancelHide() {
        hideWork?.cancel()
        hideWork = nil
    }

    private func ensureCursor(icon: NSImage?, finger: Bool) -> (NSWindow, CALayer) {
        // One window over every display, above other apps' windows, ignoring the mouse.
        let union = NSScreen.screens.reduce(CGRect.null) { $0.union($1.frame) }
        let window = cursorWindow ?? Self.clearWindow(level: .statusBar)
        if cursorWindow == nil {
            let view = NSView()
            view.wantsLayer = true
            window.contentView = view
            cursorWindow = window
        }
        if window.frame != union { window.setFrame(union, display: false) }
        window.orderFrontRegardless()
        if let layer = cursorLayer, cursorFinger == finger {
            layer.sublayers?.first { $0.name == "badge" }?.contents = icon
            return (window, layer)
        }
        // A different kind of cursor from the last task's: drawn afresh, where the old one was.
        let old = cursorLayer
        let layer = finger ? Self.fingertip() : Self.cursorShape(icon: icon)
        if let old {
            layer.position = old.position
            old.removeFromSuperlayer()
        }
        cursorFinger = finger
        layer.opacity = 0
        window.contentView?.layer?.addSublayer(layer)
        cursorLayer = layer
        return (window, layer)
    }

    // MARK: Drawing

    /// An arrow in lamplight with a white edge, its tip at the layer's position, and the app's icon riding
    /// beside it so it's clear whose cursor this is.
    private static func cursorShape(icon: NSImage?) -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        container.anchorPoint = CGPoint(x: 0, y: 1)
        let arrow = CAShapeLayer()
        let path = CGMutablePath()
        // Tip at (0, 0), pointing up and left in a flipped-y sense: Cocoa's y grows upward, so it goes down.
        path.move(to: CGPoint(x: 0, y: 0))
        path.addLine(to: CGPoint(x: 0, y: -22))
        path.addLine(to: CGPoint(x: 6, y: -16.5))
        path.addLine(to: CGPoint(x: 10.5, y: -26))
        path.addLine(to: CGPoint(x: 14, y: -24.5))
        path.addLine(to: CGPoint(x: 9.5, y: -15.5))
        path.addLine(to: CGPoint(x: 17, y: -15.5))
        path.closeSubpath()
        arrow.path = path
        arrow.fillColor = tint.cgColor
        arrow.strokeColor = NSColor.white.cgColor
        arrow.lineWidth = 1.6
        arrow.lineJoin = .round
        arrow.shadowColor = NSColor.black.cgColor
        arrow.shadowOpacity = 0.35
        arrow.shadowRadius = 3
        arrow.shadowOffset = CGSize(width: 0, height: -1)
        container.addSublayer(arrow)
        let badge = CALayer()
        badge.name = "badge"
        badge.frame = CGRect(x: 14, y: -40, width: 20, height: 20)
        badge.contents = icon
        badge.contentsGravity = .resizeAspect
        badge.shadowColor = NSColor.black.cgColor
        badge.shadowOpacity = 0.3
        badge.shadowRadius = 2
        badge.shadowOffset = .zero
        container.addSublayer(badge)
        return container
    }

    /// A fingertip on glass: a disc in lamplight with a white rim, centred on the layer's position.
    private static func fingertip() -> CALayer {
        let container = CALayer()
        container.bounds = CGRect(x: 0, y: 0, width: 1, height: 1)
        container.anchorPoint = CGPoint(x: 0, y: 1)
        let disc = CAShapeLayer()
        disc.path = CGPath(ellipseIn: CGRect(x: -13, y: -13, width: 26, height: 26), transform: nil)
        disc.fillColor = tint.withAlphaComponent(0.85).cgColor
        disc.strokeColor = NSColor.white.cgColor
        disc.lineWidth = 2.5
        disc.shadowColor = NSColor.black.cgColor
        disc.shadowOpacity = 0.35
        disc.shadowRadius = 4
        disc.shadowOffset = CGSize(width: 0, height: -1)
        container.addSublayer(disc)
        return container
    }

    /// What the cursor is doing, in a tag of lamplight beside it ("Lamp · clicking Add"), or none.
    private func setCaption(_ caption: String?, on cursor: CALayer) {
        let existing = cursor.sublayers?.first { $0.name == "caption" }
        guard let caption, !caption.isEmpty else { existing?.removeFromSuperlayer(); return }
        let scale = cursorWindow?.backingScaleFactor ?? 2
        let font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        let text = NSAttributedString(string: caption, attributes: [.font: font, .foregroundColor: NSColor.black.withAlphaComponent(0.85)])
        let size = text.size()
        let tag = existing ?? CALayer()
        tag.name = "caption"
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        tag.backgroundColor = Self.tint.cgColor
        tag.cornerRadius = 5
        tag.shadowColor = NSColor.black.cgColor
        tag.shadowOpacity = 0.25
        tag.shadowRadius = 3
        tag.shadowOffset = CGSize(width: 0, height: -1)
        // Below and to the right of the arrow's tip or the fingertip, clear of what's being clicked.
        tag.frame = CGRect(x: cursorFinger ? 16 : 18, y: cursorFinger ? -38 : -48, width: ceil(size.width) + 14, height: ceil(size.height) + 6)
        let label = (tag.sublayers?.first as? CATextLayer) ?? CATextLayer()
        label.string = text
        label.contentsScale = scale
        label.frame = CGRect(x: 7, y: 3, width: ceil(size.width), height: ceil(size.height))
        if label.superlayer == nil { tag.addSublayer(label) }
        if tag.superlayer == nil { cursor.addSublayer(tag) }
        CATransaction.commit()
    }

    /// A four-pointed sparkle.
    private static func sparkle(_ size: CGFloat) -> CGPath {
        let path = CGMutablePath()
        let inner = size * 0.28
        path.move(to: CGPoint(x: 0, y: size))
        path.addQuadCurve(to: CGPoint(x: size, y: 0), control: CGPoint(x: inner, y: inner))
        path.addQuadCurve(to: CGPoint(x: 0, y: -size), control: CGPoint(x: inner, y: -inner))
        path.addQuadCurve(to: CGPoint(x: -size, y: 0), control: CGPoint(x: -inner, y: -inner))
        path.addQuadCurve(to: CGPoint(x: 0, y: size), control: CGPoint(x: -inner, y: inner))
        return path
    }

    private func fade(_ layer: CALayer, to opacity: Float, duration: Double) {
        let animation = CABasicAnimation(keyPath: "opacity")
        animation.fromValue = layer.presentation()?.opacity ?? layer.opacity
        animation.toValue = opacity
        animation.duration = duration
        layer.opacity = opacity
        layer.add(animation, forKey: "fade")
    }

    private func remove(_ layer: CALayer, after seconds: Double) {
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds + 0.05) { layer.removeFromSuperlayer() }
    }

    private static func clearWindow(level: NSWindow.Level) -> NSWindow {
        let window = NSWindow(contentRect: .zero, styleMask: .borderless, backing: .buffered, defer: false)
        window.isOpaque = false
        window.backgroundColor = .clear
        window.hasShadow = false
        window.ignoresMouseEvents = true
        window.isReleasedWhenClosed = false
        window.level = level
        window.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle, .fullScreenAuxiliary]
        window.animationBehavior = .none
        return window
    }

    // MARK: Geometry

    /// A window's frame now, in the drivers' space, or nil when it isn't on screen.
    nonisolated static func frame(of id: CGWindowID) -> CGRect? {
        guard let info = (CGWindowListCopyWindowInfo([.optionIncludingWindow], id) as? [[String: Any]])?.first,
              info[kCGWindowIsOnscreen as String] as? Bool == true,
              let bounds = info[kCGWindowBounds as String] as? NSDictionary,
              let rect = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { return nil }
        return rect
    }

    /// From the drivers' space (top-left origin) to AppKit's (bottom-left of the main display).
    static func cocoa(_ rect: CGRect) -> CGRect {
        let height = NSScreen.screens.first?.frame.height ?? 0
        return CGRect(x: rect.minX, y: height - rect.maxY, width: rect.width, height: rect.height)
    }

    static func cocoa(_ point: CGPoint) -> CGPoint {
        CGPoint(x: point.x, y: (NSScreen.screens.first?.frame.height ?? 0) - point.y)
    }

    /// From AppKit's space back to the drivers' (the flip is its own inverse).
    static func drivers(_ point: CGPoint) -> CGPoint { cocoa(point) }
}

/// The stop control: whose task is running, and the button that ends it.
///
/// The outline around it is drawn over the content, so it would take a click as well: a capsule's stroke counts a
/// click on the line through its middle as its own, which is exactly where Stop's middle is, and a click the outline
/// takes in a panel of its own never reaches the button under it. So the outlines here take no clicks.
private struct StopPill: View {
    let label: String
    var escape = false
    let stop: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(Color(nsColor: ComputerOverlay.tint))
                .frame(width: 7, height: 7)
                .accessibilityHidden(true)
            Text(label)
                .font(.callout)
                .lineLimit(1)
            Button("Stop", action: stop)
                .controlSize(.small)
                .accessibilityHint("Ends the task. Nothing more is done.")
            if escape {
                Text("esc")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.secondary.opacity(0.5), lineWidth: 1).allowsHitTesting(false))
                    .accessibilityLabel("or press Escape")
            }
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: ComputerOverlay.tint).opacity(0.6), lineWidth: 1).allowsHitTesting(false))
        .fixedSize()
    }
}

/// In place of the stop control once the person has taken the app back.
private struct HandBackPill: View {
    let message: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.raised.fill")
                .foregroundStyle(Color(nsColor: ComputerOverlay.tint))
                .accessibilityHidden(true)
            Text(message)
                .font(.callout)
                .lineLimit(1)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: ComputerOverlay.tint).opacity(0.6), lineWidth: 1).allowsHitTesting(false))
        .fixedSize()
    }
}
