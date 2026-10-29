import SwiftUI

extension ChatLook {
    /// Lamp's icon, drawn from the same shapes as the app's (Resources/Icon/AppIcon.icon): the site's six stripes,
    /// slanted, under a sheet of its paper that leaves them a thick L up the left and along the bottom. Drawn rather
    /// than loaded, since the sidebar is a lone program with no resources of its own, and it says whose chat this is
    /// inside someone else's app.
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
            // Hard stops, so each color is a band, slanted at the site's 150 degrees across the square.
            let stops = Self.stripes.enumerated().flatMap { i, color in
                [Gradient.Stop(color: color, location: CGFloat(i) / 6), Gradient.Stop(color: color, location: CGFloat(i + 1) / 6)]
            }
            ZStack(alignment: .topTrailing) {
                LinearGradient(stops: stops, startPoint: UnitPoint(x: 0.1585, y: -0.0915), endPoint: UnitPoint(x: 0.8415, y: 1.0915))
                // The paper, in the icon's 1024-point square: from 261 across to the right edge, and down to 763.
                Rectangle().fill(Color(red: 0.949, green: 0.925, blue: 0.855))
                    .frame(width: side * 763 / 1024, height: side * 763 / 1024)
                    .shadow(color: .black.opacity(0.25), radius: side * 0.02, y: side * 0.01)
            }
            .frame(width: side, height: side)
            .clipShape(tile)
            .overlay { tile.strokeBorder(.primary.opacity(0.1), lineWidth: 0.5) }
            .accessibilityHidden(true)
        }
    }
}
