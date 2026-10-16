import AppKit
import SwiftUI

/// The app's two colors: a warm tomato for focus and a soft sage for breaks, each with a dark-mode version.
/// Text and controls keep the system's colors; these are only for the ring, the dots and the week's bars.
extension Color {
    static let focus = Color(light: NSColor(red: 0.89, green: 0.33, blue: 0.27, alpha: 1),
                             dark: NSColor(red: 1.00, green: 0.45, blue: 0.38, alpha: 1))
    static let rest = Color(light: NSColor(red: 0.36, green: 0.62, blue: 0.50, alpha: 1),
                            dark: NSColor(red: 0.50, green: 0.78, blue: 0.64, alpha: 1))

    static func of(_ phase: Phase) -> Color { phase.isBreak ? .rest : .focus }

    private init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}
