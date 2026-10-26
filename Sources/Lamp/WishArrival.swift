import AppKit
import SwiftUI

/// A wish made on the desk doesn't pop its chat up out of nowhere: the bar it was typed in lifts off the desk and
/// grows into the chat's window, lit warm the way Lamp's light is, with a few sparks rising off it, and the chat
/// fades in where it lands. Drawn in a window of its own over the desk, so the chat itself is laid out once, at its
/// real size, rather than at every step of the way.
@MainActor
enum WishArrival {
    /// Where a wish was just typed (the desk's bar, on screen) and what was typed, for the chat that opens for it.
    private static var pending: (frame: CGRect, text: String, at: Date)?
    private static var overlays: [NSWindow] = []

    static func wished(_ text: String, from frame: CGRect) {
        pending = (frame, text, Date())
    }

    /// The bar a wish came from, for a chat opening now. Only just after it was sent: a chat opened later for
    /// anything else comes up as it always has.
    static func take() -> (frame: CGRect, text: String)? {
        defer { pending = nil }
        guard let pending, Date().timeIntervalSince(pending.at) < 1 else { return nil }
        return (pending.frame, pending.text)
    }

    /// Plays the way from the bar to the chat's window, which waits unseen until the light reaches it.
    static func play(from start: (frame: CGRect, text: String), into panel: NSWindow) {
        guard !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion,
              let screen = NSScreen.screens.first(where: { $0.frame.intersects(panel.frame) }) ?? NSScreen.main else { return }
        let area = screen.frame
        func local(_ rect: CGRect) -> CGRect {
            CGRect(x: rect.minX - area.minX, y: area.maxY - rect.maxY, width: rect.width, height: rect.height)
        }
        let overlay = NSWindow(contentRect: area, styleMask: .borderless, backing: .buffered, defer: false)
        overlay.isOpaque = false
        overlay.backgroundColor = .clear
        overlay.hasShadow = false
        overlay.ignoresMouseEvents = true
        overlay.isReleasedWhenClosed = false
        overlay.collectionBehavior = [.transient, .ignoresCycle, .fullScreenAuxiliary]
        overlay.contentView = NSHostingView(rootView: ArrivalView(from: local(start.frame), to: local(panel.frame), text: start.text))
        overlay.orderFront(nil)
        overlays.append(overlay)

        panel.alphaValue = 0
        Task {
            try? await Task.sleep(for: .milliseconds(430))
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.28
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }, completionHandler: nil)
            try? await Task.sleep(for: .milliseconds(380))
            await NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.3
                overlay.animator().alphaValue = 0
            }
            overlay.orderOut(nil)
            overlays.removeAll { $0 === overlay }
        }
    }
}

/// The bar on its way to becoming the chat: a white card that grows from the bar's frame to the chat's, warm light
/// gathering round it and a band of it rising across it, the wish's words lifting away as it opens.
private struct ArrivalView: View {
    let from: CGRect
    let to: CGRect
    let text: String
    @State private var landed = false
    @State private var lit = false
    @State private var swept = false
    @State private var started = Date()

    private static let warm = Color(red: 1, green: 0.78, blue: 0.42)
    private var frame: CGRect { landed ? to : from }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Sparks(origin: from, started: started)
            card
                .frame(width: frame.width, height: frame.height)
                .offset(x: frame.minX, y: frame.minY)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .ignoresSafeArea()
        .task {
            started = Date()
            // A frame at the bar first, so the card is seen leaving it.
            try? await Task.sleep(for: .milliseconds(20))
            withAnimation(.easeOut(duration: 0.25)) { lit = true }
            withAnimation(.spring(response: 0.58, dampingFraction: 0.84)) { landed = true }
            withAnimation(.easeInOut(duration: 0.7)) { swept = true }
            try? await Task.sleep(for: .milliseconds(450))
            withAnimation(.easeIn(duration: 0.5)) { lit = false }
        }
    }

    private var shape: RoundedRectangle {
        RoundedRectangle(cornerRadius: landed ? 16 : 26, style: .continuous)
    }

    private var card: some View {
        shape
            .fill(Color(nsColor: .textBackgroundColor))
            .overlay(alignment: .topLeading) {
                // The wish's words, where they were in the bar, rising off the card as it opens.
                Text(text)
                    .font(.title3)
                    .foregroundStyle(.primary)
                    .lineLimit(1)
                    .padding(.leading, 46).padding(.trailing, 50)
                    .frame(height: from.height)
                    .offset(y: landed ? -18 : 0)
                    .opacity(landed ? 0 : 1)
                    .animation(.easeOut(duration: 0.22), value: landed)
            }
            .overlay {
                // A band of warm light rising through the card as it grows.
                GeometryReader { proxy in
                    LinearGradient(colors: [Self.warm.opacity(0), Self.warm.opacity(0.55), .white.opacity(0.7), Self.warm.opacity(0)],
                                   startPoint: .bottom, endPoint: .top)
                        .frame(height: proxy.size.height * 0.45)
                        .offset(y: swept ? -proxy.size.height * 0.5 : proxy.size.height)
                }
                .clipShape(shape)
                .opacity(swept ? 0 : 1)
            }
            .clipShape(shape)
            .overlay(shape.strokeBorder(Self.warm.opacity(lit ? 0.7 : 0), lineWidth: 1.5))
            .shadow(color: Self.warm.opacity(lit ? 0.6 : 0), radius: lit ? 42 : 8)
            .shadow(color: .black.opacity(0.1), radius: 18, y: 8)
            .environment(\.colorScheme, .light)
    }
}

/// A few warm sparks rising off the bar as the wish leaves it.
private struct Sparks: View {
    let origin: CGRect
    let started: Date

    private struct Spark {
        let x: CGFloat, rise: CGFloat, drift: CGFloat, size: CGFloat, delay: Double, life: Double
    }

    private static let sparks: [Spark] = {
        var generator = SystemRandomNumberGenerator()
        return (0..<22).map { _ in
            Spark(x: .random(in: 0.05...0.95, using: &generator), rise: .random(in: 70...220, using: &generator),
                  drift: .random(in: -26...26, using: &generator), size: .random(in: 2...4.5, using: &generator),
                  delay: .random(in: 0...0.25, using: &generator), life: .random(in: 0.6...1.1, using: &generator))
        }
    }()

    var body: some View {
        TimelineView(.animation) { timeline in
            Canvas { context, _ in
                let elapsed = timeline.date.timeIntervalSince(started)
                for spark in Self.sparks {
                    let t = (elapsed - spark.delay) / spark.life
                    guard t > 0, t < 1 else { continue }
                    let eased = 1 - pow(1 - t, 3)
                    let point = CGPoint(x: origin.minX + origin.width * spark.x + spark.drift * eased,
                                        y: origin.midY - spark.rise * eased)
                    let alpha = t < 0.2 ? t / 0.2 : 1 - (t - 0.2) / 0.8
                    let size = spark.size * (1 - 0.4 * t)
                    let glow = CGRect(x: point.x - size * 2.5, y: point.y - size * 2.5, width: size * 5, height: size * 5)
                    context.fill(Path(ellipseIn: glow), with: .color(Color(red: 1, green: 0.75, blue: 0.35).opacity(alpha * 0.25)))
                    let core = CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
                    context.fill(Path(ellipseIn: core), with: .color(Color(red: 1, green: 0.93, blue: 0.75).opacity(alpha)))
                }
            }
        }
        .allowsHitTesting(false)
    }
}
