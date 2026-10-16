import SwiftUI
import AppKit

/// The paper-planner look: warm paper behind everything, slightly lighter sheets for each part of the day,
/// and the sun's orange for what's done. Text and controls keep the system's colors, so dark mode and
/// accessibility settings work as everywhere else.
extension Color {
    static let paper = Color(light: 0xFAF6EE, dark: 0x1D1B18)
    static let sheet = Color(light: 0xFFFDF8, dark: 0x282521)
    static let sun = Color(light: 0xD9731A, dark: 0xF0953F)

    init(light: UInt32, dark: UInt32) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                           green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255,
                           alpha: 1)
        })
    }
}

extension Font {
    /// Headings in a serif face, like a printed planner; the rest stays the system font.
    static func planner(_ style: Font.TextStyle, weight: Font.Weight = .regular) -> Font {
        .system(style, design: .serif).weight(weight)
    }
}

/// One part of the day on its own sheet of paper, with a small heading.
struct PaperSheet<Content: View>: View {
    let title: String
    var trailing: String?
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(title)
                    .font(.planner(.headline, weight: .semibold))
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                if let trailing {
                    Text(trailing)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .contentTransition(.numericText())
                }
            }
            content
        }
        .padding(18)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(Color.sheet, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).strokeBorder(.separator.opacity(0.6)))
        .shadow(color: .black.opacity(0.04), radius: 6, y: 2)
    }
}
