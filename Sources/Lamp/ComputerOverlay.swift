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
    private var cursorPosition: CGPoint?   // in the cursor window's own coordinates
    private var glowWindow: NSWindow?
    private var glowTarget: CGWindowID?
    /// The stop control riding on the glow, and what it stops.
    private var stopPill: NSPanel?
    private var onStop: (() -> Void)?
    private var tracker: Timer?
    private var hideWork: DispatchWorkItem?

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    // MARK: The window in use

    /// Glows around a window and keeps following it, just above it in the stack: a window in front of it
    /// still covers the glow, so a window that's only being read doesn't seem to jump forward.
    /// `label` says whose task it is, on the stop control above the window; `stop` is what it does.
    func focus(window id: CGWindowID, label: String, stop: @escaping () -> Void) {
        cancelHide()
        onStop = stop
        defer { showStop(label) }   // once the window is known, so it opens in its place
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
    }

    // MARK: Stopping

    /// A small pill just above the window in use: whose task this is, and Stop. Above the window rather
    /// than on it so it covers none of the window's own controls; below it when there's no room above.
    private func showStop(_ label: String) {
        let view = StopPill(label: label) { [weak self] in
            guard let self else { return }
            let stop = self.onStop
            self.onStop = nil
            self.stopPill?.orderOut(nil)
            stop?()
        }
        let pill = stopPill ?? {
            let panel = NonKeyPanel(contentRect: .zero, styleMask: [.nonactivatingPanel, .borderless], backing: .buffered, defer: false)
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.level = .statusBar   // over whatever else is in front: it's how the person stops the task
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .ignoresCycle, .stationary]
            panel.isReleasedWhenClosed = false
            panel.hidesOnDeactivate = false
            panel.setAccessibilityLabel("Stop the task")
            return panel
        }()
        stopPill = pill
        let host = FirstClickHost(rootView: view)
        host.frame.size = host.fittingSize
        pill.contentView = host
        pill.setContentSize(host.fittingSize)
        if let id = glowTarget, let frame = Self.frame(of: id) { placeStop(above: frame) }
        if !pill.isVisible {
            pill.alphaValue = 0
            pill.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { $0.duration = 0.25; pill.animator().alphaValue = 1 }
        }
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

    private static let glowMargin: CGFloat = 24

    private func place(_ window: NSWindow, around frame: CGRect, above id: CGWindowID) {
        let cocoa = Self.cocoa(frame).insetBy(dx: -Self.glowMargin, dy: -Self.glowMargin)
        if window.frame != cocoa { window.setFrame(cocoa, display: true) }
        window.order(.above, relativeTo: Int(id))
    }

    private func makeGlowWindow() -> NSWindow {
        let window = Self.clearWindow(level: .normal)
        let view = NSView()
        view.wantsLayer = true
        let ring = CAShapeLayer()
        ring.fillColor = nil
        ring.strokeColor = Self.tint.withAlphaComponent(0.95).cgColor
        ring.lineWidth = 2.5
        ring.shadowColor = Self.tint.cgColor
        ring.shadowOpacity = 0.9
        ring.shadowRadius = 12
        ring.shadowOffset = .zero
        view.layer?.addSublayer(ring)
        window.contentView = view
        // Redraw the ring whenever the window is resized to follow its target.
        NotificationCenter.default.addObserver(forName: NSWindow.didResizeNotification, object: window, queue: .main) { _ in
            MainActor.assumeIsolated { Self.layout(ring, in: view.bounds) }
        }
        Self.layout(ring, in: view.bounds)
        if !reduceMotion {
            let breathe = CABasicAnimation(keyPath: "shadowRadius")
            breathe.fromValue = 8
            breathe.toValue = 18
            breathe.duration = 1.4
            breathe.autoreverses = true
            breathe.repeatCount = .infinity
            breathe.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            ring.add(breathe, forKey: "breathe")
        }
        return window
    }

    private static func layout(_ ring: CAShapeLayer, in bounds: CGRect) {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        ring.frame = bounds
        // Just outside the window's own edge, with the rounding macOS gives windows.
        let rect = bounds.insetBy(dx: glowMargin - 3, dy: glowMargin - 3)
        ring.path = CGPath(roundedRect: rect, cornerWidth: 14, cornerHeight: 14, transform: nil)
        CATransaction.commit()
    }

    // MARK: The cursor

    /// Glides Lamp's cursor to a point and returns when it's there. The first move of a task starts from the
    /// middle of the window in use, so the cursor never seems to come from nowhere.
    func move(to point: CGPoint, app icon: NSImage?) async {
        cancelHide()
        let (window, layer) = ensureCursor(icon: icon)
        let target = window.convertPoint(fromScreen: Self.cocoa(point))
        guard let from = cursorPosition, !reduceMotion else {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            layer.position = target
            CATransaction.commit()
            cursorPosition = target
            fade(layer, to: 1, duration: reduceMotion ? 0.15 : 0.2)
            try? await Task.sleep(for: .milliseconds(200))
            return
        }
        let distance = hypot(target.x - from.x, target.y - from.y)
        guard distance > 1 else { return }
        // Quick for a hop, slower across the screen, never sluggish.
        let duration = min(0.9, max(0.3, 0.25 + Double(distance) / 1800))
        // A gentle arc, bowed to one side like a hand's movement rather than a straight slide.
        let mid = CGPoint(x: (from.x + target.x) / 2, y: (from.y + target.y) / 2)
        let normal = CGPoint(x: -(target.y - from.y) / distance, y: (target.x - from.x) / distance)
        let bow = min(120, distance * 0.18)
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
        try? await Task.sleep(for: .seconds(duration))
    }

    /// The cursor's press: it dips, and a ring of light spreads from the spot with a few sparks.
    func click(at point: CGPoint) {
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
    func end() {
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

    private func ensureCursor(icon: NSImage?) -> (NSWindow, CALayer) {
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
        if let layer = cursorLayer {
            layer.sublayers?.last?.contents = icon
            return (window, layer)
        }
        let layer = Self.cursorShape(icon: icon)
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
}

/// The stop control: whose task is running, and the button that ends it.
private struct StopPill: View {
    let label: String
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
        }
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .padding(.vertical, 5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color(nsColor: ComputerOverlay.tint).opacity(0.6), lineWidth: 1))
        .fixedSize()
    }
}
