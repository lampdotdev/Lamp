import SwiftUI

extension ChatLook {
    /// Lamp's icon, drawn from the same shapes as the app's (Resources/Icon/AppIcon.icon): two rings behind an orange
    /// flame with a yellow one inside it, on a tile. Drawn rather than loaded, since the sidebar is a lone program with
    /// no resources of its own, and it says whose chat this is inside someone else's app.
    public struct LampMark: View {
        let side: CGFloat
        @Environment(\.colorScheme) private var scheme

        public init(side: CGFloat = 18) { self.side = side }

        public var body: some View {
            ZStack {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .fill(scheme == .dark ? Color(red: 0.110, green: 0.102, blue: 0.094) : .white)
                Circle().fill(Color(red: 0.871, green: 0.859, blue: 0.839).opacity(0.8))
                    .frame(width: side * 800 / 1024, height: side * 800 / 1024)
                Circle().fill(Color(red: 0.796, green: 0.780, blue: 0.757).opacity(0.9))
                    .frame(width: side * 600 / 1024, height: side * 600 / 1024)
                Flame(points: Self.outer).fill(Color(red: 1, green: 0.541, blue: 0.110))
                Flame(points: Self.middle).fill(Color(red: 1, green: 0.839, blue: 0.420))
            }
            .frame(width: side, height: side)
            .overlay {
                RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
                    .strokeBorder(.primary.opacity(0.1), lineWidth: 0.5)
            }
            .accessibilityHidden(true)
        }

        /// The flames' paths in the icon's 1024-point square: a start, then curves of two controls and an end.
        fileprivate static let outer: [CGPoint] = [
            .init(x: 540, y: 150),
            .init(x: 560, y: 290), .init(x: 770, y: 380), .init(x: 770, y: 600),
            .init(x: 770, y: 755), .init(x: 655, y: 875), .init(x: 512, y: 875),
            .init(x: 369, y: 875), .init(x: 254, y: 755), .init(x: 254, y: 600),
            .init(x: 254, y: 465), .init(x: 335, y: 395), .init(x: 398, y: 325),
            .init(x: 408, y: 405), .init(x: 440, y: 450), .init(x: 482, y: 472),
            .init(x: 468, y: 350), .init(x: 492, y: 250), .init(x: 540, y: 150),
        ]
        private static let middle: [CGPoint] = [
            .init(x: 524, y: 388),
            .init(x: 560, y: 476), .init(x: 662, y: 525), .init(x: 662, y: 648),
            .init(x: 662, y: 748), .init(x: 597, y: 812), .init(x: 512, y: 812),
            .init(x: 427, y: 812), .init(x: 362, y: 748), .init(x: 362, y: 648),
            .init(x: 362, y: 565), .init(x: 418, y: 522), .init(x: 452, y: 474),
            .init(x: 462, y: 524), .init(x: 480, y: 548), .init(x: 500, y: 558),
            .init(x: 494, y: 486), .init(x: 502, y: 436), .init(x: 524, y: 388),
        ]

        fileprivate struct Flame: Shape {
            let points: [CGPoint]

            func path(in rect: CGRect) -> Path {
                // The icon draws its flames at 90% about the middle.
                let scale = rect.width / 1024 * 0.9
                func at(_ p: CGPoint) -> CGPoint {
                    CGPoint(x: rect.midX + (p.x - 512) * scale, y: rect.midY + (p.y - 512.5) * scale)
                }
                var path = Path()
                path.move(to: at(points[0]))
                for i in stride(from: 1, to: points.count - 2, by: 3) {
                    path.addCurve(to: at(points[i + 2]), control1: at(points[i]), control2: at(points[i + 1]))
                }
                path.closeSubpath()
                return path
            }
        }
    }
}
