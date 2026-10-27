import XCTest
@testable import Lamp

/// The Chrome sidebar's `/lamp.css` gives a page one tint among Apple's system colors (`data-tint`). Each one's
/// text shade must read at 4.5:1 on the page, on a group and on the tint's own wash, and a button's words on its
/// fill, in both appearances: the strip above the page writes the app's offer in that text shade too.
final class SidebarTintTests: XCTestCase {
    private struct Tint { var text: String; var fill: String; var onTint: String; var wash: String }

    func testEveryTintReadsInBothAppearances() throws {
        let css = Template.lampSupportSwift
        // The second block of tints is the dark one.
        let first = try XCTUnwrap(css.range(of: ":root,html[data-tint=blue]{"))
        let dark = try XCTUnwrap(css.range(of: ":root,html[data-tint=blue]{", range: first.upperBound..<css.endIndex))
        let light = tints(in: String(css[..<dark.lowerBound])), night = tints(in: String(css[dark.lowerBound...]))
        XCTAssertEqual(Set(light.keys), ["blue", "green", "orange", "red", "pink", "purple", "indigo", "teal", "brown"])
        XCTAssertEqual(Set(night.keys), Set(light.keys))
        let surfaces = [(light, ["#ffffff", "#f2f2f7"]), (night, ["#2c2c2e", "#1c1c1e"])]
        for (tints, grounds) in surfaces {
            for (name, tint) in tints {
                for ground in grounds + [tint.wash] {
                    XCTAssertGreaterThanOrEqual(ratio(tint.text, ground), 4.5, "\(name) text on \(ground)")
                }
                XCTAssertGreaterThanOrEqual(ratio(tint.onTint, tint.fill), 4.5, "\(name) button")
            }
        }
        // Secondary words on the page and on a group.
        for (muted, grounds) in [("#6e6e73", ["#ffffff", "#f2f2f7"]), ("#98989d", ["#2c2c2e", "#1c1c1e"])] {
            for ground in grounds { XCTAssertGreaterThanOrEqual(ratio(muted, ground), 4.5, "\(muted) on \(ground)") }
        }
    }

    /// Each `html[data-tint=…]` block's colors, the first of each name in the text (blue's comes with `:root`).
    private func tints(in css: String) -> [String: Tint] {
        var found: [String: Tint] = [:]
        let blocks = try! NSRegularExpression(pattern: #"html\[data-tint=(\w+)\]\{([^}]*)\}"#)
        for match in blocks.matches(in: css, range: NSRange(css.startIndex..., in: css)) {
            let name = String(css[Range(match.range(at: 1), in: css)!])
            guard found[name] == nil else { continue }
            let body = String(css[Range(match.range(at: 2), in: css)!])
            func value(_ key: String) -> String {
                body.components(separatedBy: ";").first { $0.hasPrefix(key + ":") }.map { String($0.dropFirst(key.count + 1)) } ?? ""
            }
            found[name] = Tint(text: value("--tint-text"), fill: value("--tint-fill"), onTint: value("--on-tint"), wash: value("--tint-wash"))
        }
        return found
    }

    private func ratio(_ a: String, _ b: String) -> Double {
        func luminance(_ hex: String) -> Double {
            let value = Int(hex.dropFirst(), radix: 16) ?? 0
            return [16, 8, 0].map { Double((value >> $0) & 255) / 255 }
                .map { $0 <= 0.03928 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
                .enumerated().map { [0.2126, 0.7152, 0.0722][$0.offset] * $0.element }.reduce(0, +)
        }
        let x = luminance(a), y = luminance(b)
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }
}
