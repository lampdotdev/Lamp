import SwiftUI
import AppKit

/// Whether the chat is following its end: it does until someone scrolls up to read, and again once they
/// scroll back to the end or send a message. Not observed: scrolling changes it, and nothing is redrawn for it.
final class ChatFollow {
    var atEnd = true

    /// How near the end, in points, counts as being at it when scrolling back down.
    static let slack: CGFloat = 24

    /// Where the scroll view was, to tell a move up from a move down. It stays where it is through moves up
    /// too small to count, so that a slow scroll in steps of half a point adds up to one.
    private var place: CGFloat?

    /// Which way the scroll view went. `.neither` is a move up still too small to count, or none at all.
    enum Move { case up, down, neither }

    /// The scroll view moved: `y` is how far down the chat it is, `fromEnd` how far the end is below what's
    /// in view.
    func moved(to y: CGFloat, fromEnd: CGFloat) {
        guard let from = place else { return place = y }
        let move: Move = y < from - 0.5 ? .up : y > from ? .down : .neither
        if move != .neither { place = y }
        atEnd = Self.following(was: atEnd, move: move, fromEnd: fromEnd)
    }

    /// The scroll view is another one, or the same one somewhere new: where it was says nothing now.
    func forgetPlace() { place = nil }

    /// What a move of the scroll view makes of it. Any move up that leaves the end stops the following,
    /// however small: a reply written quickly would otherwise pull back each small step of a scroll before
    /// the next. Only a move down that ends near the end starts it again, so the small steps of a slow
    /// scroll up can't. New words or lines arriving don't move the scroll view, so they never stop it.
    static func following(was: Bool, move: Move, fromEnd: CGFloat) -> Bool {
        switch move {
        case .up: return fromEnd <= 1
        case .down: return was || fromEnd <= slack
        case .neither: return was || fromEnd <= 1
        }
    }
}

/// Brings in a chat's earlier messages as someone scrolls up towards them, and keeps what they're reading
/// where it is while the messages arrive above it. It also notes whether the chat is at its end (see
/// `ChatFollow`). Sits inside the scroll view's content, which is how it finds the scroll view. SwiftUI on
/// macOS 14 can't say how far a scroll view has scrolled, nor hold it still while rows are added above, so
/// this works with the scroll view underneath.
struct EarlierOnScroll: NSViewRepresentable {
    /// There are earlier messages that aren't shown yet.
    let more: Bool
    let follow: ChatFollow
    /// Set once the scroll view is found: until then the chat offers a button instead.
    @Binding var watching: Bool
    let load: () -> Void

    func makeNSView(context: Context) -> Probe { Probe() }

    func updateNSView(_ probe: Probe, context: Context) {
        probe.more = more
        probe.follow = follow
        probe.load = load
        probe.found = { [binding = $watching] in binding.wrappedValue = true }
        probe.check()
    }

    final class Probe: NSView {
        /// How close to the top of what's shown, in points, before more is brought in: a few screens, so
        /// the messages are there before the scrolling reaches them.
        static let lead: CGFloat = 1200

        var more = false
        var follow: ChatFollow?
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
            follow?.forgetPlace()
            scroll.contentView.postsBoundsChangedNotifications = true
            content.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                                   object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification,
                                                   object: content)
            Task { @MainActor in self.found?() }
        }

        @objc private func scrolled() {
            if let scroll, let content = scroll.documentView {
                let visible = scroll.contentView.bounds
                let flipped = content.isFlipped
                follow?.moved(to: flipped ? visible.minY : -visible.minY,
                              fromEnd: flipped ? content.frame.height - visible.maxY : visible.minY)
            }
            check()
        }

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
