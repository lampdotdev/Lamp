import SwiftUI

extension ChatLook {
    /// Lamp's icon, drawn from the same shapes as the app's (Resources/Icon/AppIcon.icon): the site's six stripes,
    /// slanted, under a pane of frosted glass with a white square at its top right. Drawn rather than loaded, since
    /// the sidebar is a lone program with no resources of its own, and it says whose chat this is inside someone
    /// else's app.
    public struct LampMark: View {
        let side: CGFloat

        public init(side: CGFloat = 18) { self.side = side }

        /// The stripes' colors, top left to bottom right, as the site has them.
        private static let stripes: [Color] = [
            Color(red: 0.122, green: 0.541, blue: 0.290), Color(red: 0.486, green: 0.749, blue: 0.227),
            Color(red: 0.965, green: 0.722, blue: 0.110), Color(red: 0.941, green: 0.541, blue: 0.110),
            Color(red: 0.886, green: 0.251, blue: 0.165), Color(red: 0.824, green: 0.216, blue: 0.471),
        ]

        public var body: some View {
            let tile = RoundedRectangle(cornerRadius: side * 0.225, style: .continuous)
            // Hard stops, so each color is a band, running corner to corner as the icon's do.
            let stops = Self.stripes.enumerated().flatMap { i, color in
                [Gradient.Stop(color: color, location: CGFloat(i) / 6), Gradient.Stop(color: color, location: CGFloat(i + 1) / 6)]
            }
            ZStack(alignment: .topLeading) {
                LinearGradient(stops: stops, startPoint: .topLeading, endPoint: .bottomTrailing)
                // The glass and the white square, as fractions of the icon's tile.
                RoundedRectangle(cornerRadius: side * 0.1, style: .continuous).fill(.white.opacity(0.5))
                    .frame(width: side * 0.595, height: side * 0.57)
                    .offset(x: side * 0.2, y: side * 0.225)
                RoundedRectangle(cornerRadius: side * 0.08, style: .continuous).fill(.white)
                    .frame(width: side * 0.362, height: side * 0.365)
                    .offset(x: side * 0.432, y: side * 0.207)
                    .shadow(color: .black.opacity(0.15), radius: side * 0.02, y: side * 0.01)
            }
            .frame(width: side, height: side)
            .clipShape(tile)
            .overlay { tile.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
            .accessibilityHidden(true)
        }
    }
}
