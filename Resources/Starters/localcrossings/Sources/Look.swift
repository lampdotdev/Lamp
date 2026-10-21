import SwiftUI
import AppKit

/// The paper the puzzle is printed on: warm newsprint and near-black ink, with one yellow for where you are and
/// a paler one for the word you're in. Each has a light and a dark version, so the paper follows the appearance.
enum Paper {
    static let page = Color(light: NSColor(red: 0.969, green: 0.957, blue: 0.925, alpha: 1),
                            dark: NSColor(red: 0.110, green: 0.106, blue: 0.098, alpha: 1))
    static let ink = Color(light: NSColor(red: 0.071, green: 0.071, blue: 0.071, alpha: 1),
                           dark: NSColor(red: 0.925, green: 0.910, blue: 0.875, alpha: 1))
    static let faded = Color(light: NSColor(red: 0.431, green: 0.416, blue: 0.376, alpha: 1),
                             dark: NSColor(red: 0.620, green: 0.600, blue: 0.560, alpha: 1))
    static let square = Color(light: .white, dark: NSColor(red: 0.165, green: 0.161, blue: 0.149, alpha: 1))
    static let sun = Color(light: NSColor(red: 0.965, green: 0.851, blue: 0.396, alpha: 1),
                           dark: NSColor(red: 0.820, green: 0.690, blue: 0.220, alpha: 1))
    static let sunInk = Color(light: NSColor(red: 0.290, green: 0.231, blue: 0.000, alpha: 1),
                              dark: NSColor(red: 0.110, green: 0.090, blue: 0.000, alpha: 1))
    static let haze = Color(light: NSColor(red: 0.984, green: 0.929, blue: 0.710, alpha: 1),
                            dark: NSColor(red: 0.290, green: 0.255, blue: 0.130, alpha: 1))
    static let leaf = Color(light: NSColor(red: 0.420, green: 0.620, blue: 0.330, alpha: 1),
                            dark: NSColor(red: 0.510, green: 0.720, blue: 0.420, alpha: 1))
    static let wrong = Color(light: NSColor(red: 0.800, green: 0.200, blue: 0.180, alpha: 1),
                             dark: NSColor(red: 0.940, green: 0.400, blue: 0.360, alpha: 1))

    /// The masthead's and headlines' type: Apple's serif, the closest thing on a Mac to a newspaper's.
    static func serif(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }

    /// Small capitals for labels: "NO. 12", "ACROSS".
    static let label = Font.system(size: 11, weight: .semibold).width(.condensed)
}

extension Color {
    init(light: NSColor, dark: NSColor) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
        })
    }
}

/// A newspaper's rule: a thick line over a thin one, or just the thin one.
struct Rule: View {
    var heavy = false

    var body: some View {
        Rectangle().fill(Paper.ink).frame(height: heavy ? 2 : 0.75)
    }
}
