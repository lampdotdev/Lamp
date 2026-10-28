import SwiftUI

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
