import SwiftUI

/// The chat's rows, one under another, and after them the room that lets a request just sent sit at the
/// top of the chat while its answer comes in below it. The room is worked out in the same pass that lays
/// out the rows: measured afterwards, it would lag a step behind each new word, and the chat, following its
/// end, would jump by that much every time.
public struct ChatStack: Layout {
    /// How far the top of the pinned request's bubble is from the end of the chat when it's at the top: the
    /// chat's height less a margin above the bubble.
    public var fill: CGFloat
    /// The room's least height, the space below the last row: it's the chat's margin at the bottom, kept
    /// in the room so that the room's end is the chat's end.
    public var end: CGFloat

    public init(fill: CGFloat, end: CGFloat) {
        self.fill = fill
        self.end = end
    }

    /// Marks the row of the request held at the top, with the gap above its bubble that's part of the row.
    public struct Pinned: LayoutValueKey { public static let defaultValue: CGFloat? = nil }
    /// Marks the room, which takes whatever height is left over.
    public struct Room: LayoutValueKey { public static let defaultValue = false }

    public func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let sizes = measure(proposal.width, subviews)
        let width = proposal.width ?? sizes.map(\.width).max() ?? 0
        return CGSize(width: width, height: sizes.map(\.height).reduce(0, +))
    }

    public func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let sizes = measure(bounds.width, subviews)
        var y = bounds.minY
        for (subview, size) in zip(subviews, sizes) {
            subview.place(at: CGPoint(x: bounds.minX, y: y), anchor: .topLeading,
                          proposal: ProposedViewSize(width: bounds.width, height: size.height))
            y += size.height
        }
    }

    /// Each row as tall as it wants to be at this width, as a stack would have it; the room what's needed
    /// for the pinned request's bubble and what follows it to reach `fill`, and at least `end`.
    private func measure(_ width: CGFloat?, _ subviews: Subviews) -> [CGSize] {
        var sizes = subviews.map { $0[Room.self] ? .zero : $0.sizeThatFits(ProposedViewSize(width: width, height: nil)) }
        guard let room = subviews.firstIndex(where: { $0[Room.self] }) else { return sizes }
        sizes[room].height = end
        guard let pinned = subviews.firstIndex(where: { $0[Pinned.self] != nil }),
              let gap = subviews[pinned][Pinned.self] else { return sizes }
        let below = sizes[pinned..<room].map(\.height).reduce(0, +) - gap
        sizes[room].height = max(end, fill - below)
        return sizes
    }
}

/// A chat opens at its end. Held there as it grows, too, unless `holdsEnd` is off: then only what's done
/// to it moves it. Before macOS 15 the two can't be told apart, and it does both.
public struct OpensAtEnd: ViewModifier {
    var holdsEnd: Bool
    public init(holdsEnd: Bool) { self.holdsEnd = holdsEnd }

    public func body(content: Content) -> some View {
        if #available(macOS 15, *) {
            // The nearer of the two wins for growing: everything else is as the plain one has it.
            content
                .defaultScrollAnchor(holdsEnd ? .bottom : nil, for: .sizeChanges)
                .defaultScrollAnchor(.bottom)
        } else {
            content.defaultScrollAnchor(.bottom)
        }
    }
}
