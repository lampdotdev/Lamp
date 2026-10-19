import SwiftUI
import AppKit

extension ChatLook {
    /// A message bubble as Messages draws one: a rounded shape with a small tail at its bottom corner on the
    /// speaker's side, curling out past the edge. The tail is drawn outside the shape's rect, so the row leaves
    /// room for it.
    public struct Bubble: Shape {
        public enum Side: Sendable { case leading, trailing }
        let side: Side
        let radius: CGFloat

        public init(_ side: Side, radius: CGFloat = 17) {
            self.side = side
            self.radius = radius
        }

        public func path(in rect: CGRect) -> Path {
            let r = min(radius, rect.height / 2, rect.width / 2)
            let path = Path(roundedRect: rect, cornerRadius: r, style: .continuous)
            // The tail, drawn for the trailing side and mirrored for the leading one.
            var tail = Path()
            let x = rect.maxX, y = rect.maxY
            tail.move(to: CGPoint(x: x - r * 0.9, y: y))
            tail.addLine(to: CGPoint(x: x - 2, y: y - r * 0.9))
            tail.addCurve(to: CGPoint(x: x + 5, y: y),
                          control1: CGPoint(x: x - 2, y: y - 4), control2: CGPoint(x: x + 1, y: y - 1))
            tail.addCurve(to: CGPoint(x: x - 9, y: y - 3),
                          control1: CGPoint(x: x - 1, y: y + 1), control2: CGPoint(x: x - 5, y: y))
            tail.closeSubpath()
            if side == .leading {
                tail = tail.applying(CGAffineTransform(translationX: rect.minX + rect.maxX, y: 0).scaledBy(x: -1, y: 1))
            }
            // A union, not two subpaths: mirrored, the tail winds the other way, and where it overlaps the
            // bubble the two would cancel out into a gap.
            return path.union(tail)
        }
    }

    /// The colour of what the agent says, Messages' grey for the other person, a touch warm to sit on the chat's
    /// paper. Opaque, so where the tail overlaps the bubble it isn't darker.
    public static let agentBubble = Color(nsColor: NSColor(name: "LampAgentBubble") { appearance in
        appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            ? NSColor(srgbRed: 0x36 / 255, green: 0x35 / 255, blue: 0x33 / 255, alpha: 1)
            : NSColor(srgbRed: 0xE9 / 255, green: 0xE8 / 255, blue: 0xE5 / 255, alpha: 1)
    })

    /// How far a bubble's tail reaches past its side: rows keep this much room so it isn't clipped.
    public static let tailRoom: CGFloat = 6
}
