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
        // The chat's own doing: whichever way the scroll view goes meanwhile, it's still following.
        if movingItself || settling.map({ Date() < $0 }) == true {
            place = y
            return
        }
        guard let from = place else { return place = y }
        let move: Move = y < from - 0.5 ? .up : y > from ? .down : .neither
        if move != .neither { place = y }
        atEnd = Self.following(was: atEnd, move: move, fromEnd: fromEnd)
    }

    /// Until when the scroll view's moves are the chat rearranging itself, not the person scrolling.
    private var settling: Date?

    /// Goes to following the end, and stays there while the chat settles: a card that folds as it's answered
    /// makes the chat shorter over a few frames, and the scroll view moving up with it would read as the
    /// person scrolling away from the end.
    func followThroughSettling() {
        atEnd = true
        settling = Date().addingTimeInterval(0.6)
    }

    /// The chat is moving the scroll view to its end, so the move isn't the person scrolling.
    private var movingItself = false

    /// Runs a move of the scroll view that is the chat's own. Going to the end can be a move up, when the
    /// chat has just got shorter, and read as the person's it would stop the following for the rest of the turn.
    func byItself(_ move: () -> Void) {
        movingItself = true
        move()
        movingItself = false
    }

    /// The agent's questions waiting for their answer, and when they arrived.
    private var asked: (id: UUID, at: Date)?

    /// How long after the questions arrive the chat still follows its end: long enough for their card to be
    /// laid out and come into view whole.
    static let arrival: TimeInterval = 0.6

    /// The agent's questions that are waiting changed: these arrived, or (nil) the last were answered.
    func waiting(for questions: UUID?, at now: Date = Date()) {
        if let questions {
            if asked?.id != questions { asked = (questions, now) }
        } else {
            asked = nil
            followThroughSettling()
        }
    }

    /// Whether what's added at the end is followed now. Not once the agent's questions are in view: anything
    /// added under them would slide the answers out from under the pointer.
    func followsEnd(at now: Date = Date()) -> Bool {
        guard atEnd else { return false }
        guard let asked else { return true }
        return now < asked.at.addingTimeInterval(Self.arrival)
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
/// `ChatFollow`), and keeps it there as the chat grows. Sits inside the scroll view's content, which is how
/// it finds the scroll view. SwiftUI on macOS 14 can't say how far a scroll view has scrolled, nor hold it
/// still while rows are added above, so this works with the scroll view underneath.
struct EarlierOnScroll: NSViewRepresentable {
    /// There are earlier messages that aren't shown yet.
    let more: Bool
    let follow: ChatFollow
    /// Goes up each time the chat is to go to its end wherever it is: a message was sent.
    var ends = 0
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
        if ends != probe.ends {
            probe.ends = ends
            follow.atEnd = true
            probe.followEnd(whatever: true)
        }
    }

    final class Probe: NSView {
        /// How close to the top of what's shown, in points, before more is brought in: a few screens, so
        /// the messages are there before the scrolling reaches them.
        static let lead: CGFloat = 1200

        var more = false
        var follow: ChatFollow?
        var load: (() -> Void)?
        var found: (() -> Void)?
        var ends = 0
        private var opened = false
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
            scroll.contentView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(self, selector: #selector(scrolled), name: NSView.boundsDidChangeNotification,
                                                   object: scroll.contentView)
            NotificationCenter.default.addObserver(self, selector: #selector(resized), name: NSView.frameDidChangeNotification,
                                                   object: content)
            // The chat area changing size (the message box growing a line, the window resized) keeps the end
            // in view too.
            NotificationCenter.default.addObserver(self, selector: #selector(areaResized), name: NSView.frameDidChangeNotification,
                                                   object: scroll.contentView)
            Task { @MainActor in self.found?() }
            // A chat opens at its end, and following it. SwiftUI leaves it a little short: once it's laid
            // out, it goes the rest of the way. Only when it opens, not when it's moved later.
            guard !opened else { return }
            opened = true
            DispatchQueue.main.async { [weak self] in
                self?.follow?.atEnd = true
                self?.followEnd()
            }
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

        @objc private func areaResized() { followEnd() }

        /// Goes to the end of the chat if it's following it. Here and not with SwiftUI's own scrolling, for
        /// two reasons. This runs as the chat is laid out, whatever made it grow, so nothing added at the end
        /// arrives out of sight for want of having been thought of. And the move is known to be the chat's:
        /// SwiftUI's comes a frame later, and one that went up, after the chat got shorter, was taken for the
        /// person scrolling away and stopped the following until the next message was sent.
        /// `whatever` goes there even past the agent's waiting questions: a message was sent.
        func followEnd(whatever: Bool = false) {
            guard let follow, whatever || follow.followsEnd(), let scroll, let content = scroll.documentView, content.isFlipped else { return }
            let clip = scroll.contentView
            // Not before the chat area has its size: the end isn't anywhere yet.
            guard clip.bounds.height > 0 else { return }
            // The end as the scroll view has it, which keeps a chat shorter than its area at the top.
            let end = clip.constrainBoundsRect(NSRect(x: clip.bounds.minX, y: content.frame.height - clip.bounds.height,
                                                      width: clip.bounds.width, height: clip.bounds.height)).minY
            guard abs(end - clip.bounds.minY) > 0.5 else { return }
            follow.byItself {
                clip.scroll(to: NSPoint(x: clip.bounds.minX, y: end))
                scroll.reflectScrolledClipView(clip)
            }
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

        /// The content changed height. If it grew and that's the earlier messages arriving, they went in
        /// above, so everything below moved down by their height. Scrolling by the same amount, before it's
        /// drawn, leaves what was on screen where it was. Anything else is the chat changing at its end,
        /// which it follows.
        @objc private func resized() {
            guard let before = heightBefore, let scroll, let content = scroll.documentView else { return followEnd() }
            let grown = content.frame.height - before
            guard grown > 0 else { return followEnd() }
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

/// A chat opens at its end, with no scrolling to get there. Keeping it there as it grows is `EarlierOnScroll`'s:
/// SwiftUI would keep it there through everything, the agent's waiting questions included. Before macOS 15
/// the two can't be told apart, and SwiftUI does both.
struct OpensAtEnd: ViewModifier {
    func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // The nearer of the two wins for growing: everything else is as the plain one has it.
            content
                .defaultScrollAnchor(nil, for: .sizeChanges)
                .defaultScrollAnchor(.bottom)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}
