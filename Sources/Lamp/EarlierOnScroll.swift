import SwiftUI
import AppKit

/// Brings in a chat's earlier messages as someone scrolls up towards them, and keeps what they're reading
/// where it is while the messages arrive above it. Sits inside the scroll view's content, which is how it
/// finds the scroll view. SwiftUI on macOS 14 can't say how far a scroll view has scrolled, nor hold it
/// still while rows are added above, so this works with the scroll view underneath.
struct EarlierOnScroll: NSViewRepresentable {
    /// There are earlier messages that aren't shown yet.
    let more: Bool
    /// Set once the scroll view is found: until then the chat offers a button instead.
    @Binding var watching: Bool
    let load: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.more = more
        probe.load = load
        probe.found = { [binding = $watching] in binding.wrappedValue = true }
        probe.check()
    }

    final class Probe: NSView {
        /// How close to the top of what's shown, in points, before more is brought in: a few screens, so
        /// the messages are there before the scrolling reaches them.
        static let lead: CGFloat = 1200

        var more = false
        var load: (() -> Void)?
        var found: (() -> Void)?
        private weak var scroll: NSScrollView?
        /// The content's height when more was asked for, until it has arrived.
        private var heightBefore: CGFloat?
        private var asked = 0

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            NotificationCenter.default.removeObserver(self)
            scroll = nil
            guard window != nil, let scroll = enclosingScrollView, let content = scroll.documentView else { return }
            self.scroll = scroll
            scroll.contentView.postsBoundsChangedNotifications = true
            content.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                                   object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification,
                                                   object: content)
            Task { @MainActor in self.found?() }
        }

        @objc private func scrolled() { check() }

        /// Asks for more when the top of what's shown is near. One lot at a time: the next is asked for once
        /// this one is in and the place has been kept.
        func check() {
            guard more, heightBefore == nil, let scroll, let content = scroll.documentView else { return }
            let visible = scroll.contentView.bounds
            let above = content.isFlipped ? visible.minY : content.frame.height - visible.maxY
            guard above < Self.lead else { return }
            heightBefore = content.frame.height
            asked += 1
            let asking = asked
            Task { @MainActor in
                self.load?()
                // If nothing came of it (the chat changed meanwhile), don't wait for it forever.
                try? await Task.sleep(for: .seconds(1))
                if self.asked == asking { self.heightBefore = nil }
            }
        }

        /// The content grew: if that's the earlier messages arriving, they went in above, so everything
        /// below moved down by their height. Scrolling by the same amount, before it's drawn, leaves what
        /// was on screen where it was.
        @objc private func resized() {
            guard let before = heightBefore, let scroll, let content = scroll.documentView else { return }
            let grown = content.frame.height - before
            guard grown > 0 else { return }
            heightBefore = nil
            if content.isFlipped {
                var origin = scroll.contentView.bounds.origin
                origin.y += grown
                scroll.contentView.scroll(to: origin)
                scroll.reflectScrolledClipView(scroll.contentView)
            }
            check()
        }
    }
}
