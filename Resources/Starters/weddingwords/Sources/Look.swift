import SwiftUI
import AppKit

/// The wedding's stationery: cream paper, maiolica-blue ink, lemons washed in yellow, and a script for the
/// words a card would write by hand. Every colour, typeface and drawing the pages use is here, so another
/// occasion changes this file.
enum Look {
    static let paper = dynamic(light: 0xFAF5EA, dark: 0x1A1E28)
    static let card = dynamic(light: 0xFFFDF8, dark: 0x232937)
    static let ink = dynamic(light: 0x1F4597, dark: 0xA8BDF2)
    static let lemon = dynamic(light: 0xF2D46E, dark: 0xD2B04A)
    /// A soft ground for what's the person's own (their replies, the milestones' marks): lemon by day, and
    /// blue at night, where a yellow wash turns olive.
    static let wash = dynamic(light: 0xF7E8B6, dark: 0x2D3958)

    /// Handwriting, for the line a card would say in ink ("save the date").
    static func script(_ size: CGFloat) -> Font { .custom("Snell Roundhand", size: size) }
    /// Printed words with a little ceremony: headings and the Italian itself.
    static func serif(_ size: CGFloat, italic: Bool = false) -> Font {
        let font = Font.system(size: size, design: .serif)
        return italic ? font.italic() : font
    }

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
        })
    }
}

/// Letter-spaced capitals in ink, as an invitation prints names and dates.
struct Engraved: View {
    let text: String
    var size: CGFloat = 11
    init(_ text: String, size: CGFloat = 11) { self.text = text; self.size = size }
    var body: some View {
        Text(text).textCase(.uppercase).font(.system(size: size, weight: .medium)).tracking(size * 0.22).foregroundStyle(Look.ink)
    }
}

extension View {
    /// A card of good paper with a fine inner rule, like a printed invitation.
    func invitationCard(padding: CGFloat = 24, radius: CGFloat = 14) -> some View {
        self.padding(padding)
            .background(Look.card, in: RoundedRectangle(cornerRadius: radius))
            .overlay(RoundedRectangle(cornerRadius: radius - 4).strokeBorder(Look.ink.opacity(0.18), lineWidth: 0.75).padding(5))
            .overlay(RoundedRectangle(cornerRadius: radius).strokeBorder(Look.ink.opacity(0.12), lineWidth: 0.5))
            .shadow(color: .black.opacity(0.05), radius: 6, y: 2)
    }
    /// The paper every page is laid on.
    func pageBackground() -> some View { background(Look.paper.ignoresSafeArea()) }
}

/// A page's heading: a word in script over its printed title.
struct PageHeading: View {
    let script: String
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(script).font(Look.script(34)).foregroundStyle(Look.ink).padding(.bottom, -6)
            Text(title).font(Look.serif(30))
            Text(subtitle).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .topTrailing) { LemonBranch().frame(height: 150).padding(.top, -24).padding(.trailing, -28) }
    }
}

/// A thin rule with a lemon in the middle, between parts of a page.
struct LemonRule: View {
    var body: some View {
        HStack(spacing: 12) {
            Rectangle().fill(Look.ink.opacity(0.25)).frame(height: 0.75)
            LemonMark(filled: true).frame(width: 20, height: 14)
            Rectangle().fill(Look.ink.opacity(0.25)).frame(height: 0.75)
        }.accessibilityHidden(true)
    }
}

// MARK: Drawings

/// Ink drawings in the manner of a hand-drawn invitation: wobbly outlines, a yellow wash a little off its line.
enum Sketch {
    /// A cubic Bézier's point at `t`.
    static func bezier(_ p: [CGPoint], _ t: CGFloat) -> CGPoint {
        let u = 1 - t
        let a = u * u * u, b = 3 * u * u * t, c = 3 * u * t * t, d = t * t * t
        return CGPoint(x: a * p[0].x + b * p[1].x + c * p[2].x + d * p[3].x, y: a * p[0].y + b * p[1].y + c * p[2].y + d * p[3].y)
    }
    static func place(_ p: CGPoint, at origin: CGPoint, angle: CGFloat) -> CGPoint {
        CGPoint(x: origin.x + p.x * cos(angle) - p.y * sin(angle), y: origin.y + p.x * sin(angle) + p.y * cos(angle))
    }
    static func polygon(_ points: [CGPoint]) -> Path {
        var path = Path(); path.addLines(points); path.closeSubpath(); return path
    }

    /// A lemon's outline around `center`, its long axis at `angle`, both ends pointed.
    static func lemonOutline(center: CGPoint, length l: CGFloat, width w: CGFloat, angle: CGFloat, wobble: CGFloat = 0, seed: CGFloat = 0) -> [CGPoint] {
        let top = [CGPoint(x: -l / 2, y: 0), CGPoint(x: -l * 0.3, y: -w * 0.7), CGPoint(x: l * 0.3, y: -w * 0.7), CGPoint(x: l / 2, y: 0)]
        let bottom = [CGPoint(x: l / 2, y: 0), CGPoint(x: l * 0.3, y: w * 0.7), CGPoint(x: -l * 0.3, y: w * 0.7), CGPoint(x: -l / 2, y: 0)]
        let n = 28
        var points: [CGPoint] = []
        for curve in [top, bottom] {
            for i in 0..<n { points.append(bezier(curve, CGFloat(i) / CGFloat(n))) }
        }
        return points.enumerated().map { index, p in
            let k = CGFloat(index)
            let swell = 1 + wobble * (0.6 * sin(k * 0.45 + seed) + 0.4 * sin(k * 1.3 + seed * 2.1))
            return place(CGPoint(x: p.x * swell, y: p.y * swell), at: center, angle: angle)
        }
    }

    /// A lemon as the references draw it: a wash shifted down and left, the ink line, a nub at each end and a
    /// few dots of peel.
    static func drawLemon(_ context: GraphicsContext, center: CGPoint, length: CGFloat, angle: CGFloat, line: CGFloat, ink: Color, wash: Color, seed: CGFloat, filled: Bool = true) {
        let width = length * 0.6
        if filled {
            let shifted = CGPoint(x: center.x - length * 0.06, y: center.y + length * 0.05)
            context.fill(polygon(lemonOutline(center: shifted, length: length * 1.02, width: width * 1.04, angle: angle, wobble: 0.05, seed: seed)), with: .color(wash))
            context.fill(polygon(lemonOutline(center: CGPoint(x: shifted.x - length * 0.08, y: shifted.y - length * 0.1), length: length * 0.45, width: width * 0.3, angle: angle - 0.3, wobble: 0.08, seed: seed + 1)), with: .color(.white.opacity(0.28)))
        }
        let style = StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round)
        var outline = Path()
        let points = lemonOutline(center: center, length: length, width: width, angle: angle, wobble: 0.015, seed: seed)
        outline.addLines(points + [points[0], points[1], points[2]].map { CGPoint(x: $0.x + line * 0.6, y: $0.y - line * 0.4) })
        context.stroke(outline, with: .color(ink), style: style)
        for end in [-1.0, 1.0] as [CGFloat] {
            var nub = Path()
            nub.move(to: place(CGPoint(x: end * length * 0.48, y: 0), at: center, angle: angle))
            nub.addLine(to: place(CGPoint(x: end * length * 0.55, y: 0), at: center, angle: angle))
            context.stroke(nub, with: .color(ink), style: StrokeStyle(lineWidth: line * 1.5, lineCap: .round))
        }
        guard filled else { return }
        for dot in [CGPoint(x: 0.2, y: 0.1), CGPoint(x: 0.27, y: -0.01), CGPoint(x: 0.24, y: 0.21), CGPoint(x: 0.31, y: 0.12)] {
            let p = place(CGPoint(x: dot.x * length, y: dot.y * width), at: center, angle: angle)
            context.fill(Path(ellipseIn: CGRect(x: p.x - line * 0.55, y: p.y - line * 0.55, width: line * 1.1, height: line * 1.1)), with: .color(ink))
        }
    }

    /// An olive-shaped leaf from `base`, with its midrib.
    static func drawLeaf(_ context: GraphicsContext, base: CGPoint, angle: CGFloat, length l: CGFloat, line: CGFloat, ink: Color) {
        let w = l * 0.36
        var leaf = Path()
        leaf.move(to: base)
        leaf.addQuadCurve(to: place(CGPoint(x: l, y: 0), at: base, angle: angle), control: place(CGPoint(x: l * 0.42, y: -w), at: base, angle: angle))
        leaf.addQuadCurve(to: place(CGPoint(x: l * 0.04, y: w * 0.06), at: base, angle: angle), control: place(CGPoint(x: l * 0.58, y: w * 0.88), at: base, angle: angle))
        context.stroke(leaf, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round, lineJoin: .round))
        var rib = Path()
        rib.move(to: place(CGPoint(x: l * 0.08, y: 0), at: base, angle: angle))
        rib.addQuadCurve(to: place(CGPoint(x: l * 0.72, y: -w * 0.04), at: base, angle: angle), control: place(CGPoint(x: l * 0.4, y: w * 0.06), at: base, angle: angle))
        context.stroke(rib, with: .color(ink), style: StrokeStyle(lineWidth: line * 0.7, lineCap: .round))
    }
}

/// A lemon branch coming in from the top right, three lemons hanging from it, as on the invitations.
struct LemonBranch: View {
    static let size = CGSize(width: 520, height: 360)
    var body: some View {
        Canvas { context, size in
            let s = min(size.width / Self.size.width, size.height / Self.size.height)
            context.translateBy(x: size.width - Self.size.width * s, y: 0)
            context.scaleBy(x: s, y: s)
            let ink = Look.ink, wash = Look.lemon, line: CGFloat = 2.1
            let stem = [CGPoint(x: 560, y: -30), CGPoint(x: 430, y: 10), CGPoint(x: 260, y: 30), CGPoint(x: 70, y: 175)]
            let twig = [CGPoint(x: 360, y: 32), CGPoint(x: 330, y: 90), CGPoint(x: 300, y: 130), CGPoint(x: 250, y: 190)]
            for branch in [stem, twig] {
                var path = Path()
                path.move(to: branch[0]); path.addCurve(to: branch[3], control1: branch[1], control2: branch[2])
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: line * (branch == stem ? 1.4 : 1.1), lineCap: .round))
            }
            func heading(_ branch: [CGPoint], _ t: CGFloat) -> CGFloat {
                let a = Sketch.bezier(branch, max(0, t - 0.01)), b = Sketch.bezier(branch, min(1, t + 0.01))
                return atan2(b.y - a.y, b.x - a.x)
            }
            // Leaves first, so the lemons hang over them: where on the branch, which side, how far they lean off it.
            let leaves: [(branch: [CGPoint], t: CGFloat, turn: CGFloat, length: CGFloat)] = [
                (stem, 0.04, -0.9, 84), (stem, 0.1, 0.8, 92), (stem, 0.2, -0.7, 80), (stem, 0.3, 1.0, 76),
                (stem, 0.4, -0.85, 90), (stem, 0.52, 0.75, 86), (stem, 0.6, -1.0, 78), (stem, 0.7, 0.9, 82),
                (stem, 0.8, -0.8, 74), (stem, 0.9, 0.7, 70), (stem, 1.0, -0.25, 66), (stem, 1.0, 0.45, 60),
                (twig, 0.3, -0.9, 70), (twig, 0.55, 0.8, 74), (twig, 0.8, -0.7, 64), (twig, 1.0, 0.1, 58),
            ]
            for leaf in leaves {
                Sketch.drawLeaf(context, base: Sketch.bezier(leaf.branch, leaf.t), angle: heading(leaf.branch, leaf.t) + leaf.turn, length: leaf.length, line: line, ink: ink)
            }
            let lemons: [(branch: [CGPoint], t: CGFloat, twig: CGVector, angle: CGFloat, length: CGFloat)] = [
                (stem, 0.14, CGVector(dx: -4, dy: 22), 1.68, 112), (twig, 0.92, CGVector(dx: -6, dy: 14), 1.95, 100), (stem, 0.66, CGVector(dx: 6, dy: 16), 1.4, 92),
            ]
            for (index, lemon) in lemons.enumerated() {
                let from = Sketch.bezier(lemon.branch, lemon.t)
                let top = CGPoint(x: from.x + lemon.twig.dx, y: from.y + lemon.twig.dy)
                var path = Path()
                path.move(to: from); path.addQuadCurve(to: top, control: CGPoint(x: from.x + lemon.twig.dx * 0.1, y: from.y + lemon.twig.dy * 0.6))
                context.stroke(path, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
                let center = CGPoint(x: top.x + cos(lemon.angle) * lemon.length * 0.55, y: top.y + sin(lemon.angle) * lemon.length * 0.55)
                Sketch.drawLemon(context, center: center, length: lemon.length, angle: lemon.angle, line: line, ink: ink, wash: wash, seed: CGFloat(index) * 2.7)
            }
        }
        .aspectRatio(Self.size.width / Self.size.height, contentMode: .fit)
        .accessibilityHidden(true)
    }
}

/// One small lemon: washed when it counts, an outline when it doesn't yet.
struct LemonMark: View {
    var filled: Bool
    var body: some View {
        Canvas { context, size in
            let length = min(size.width, size.height / 0.66) * 0.82
            Sketch.drawLemon(context, center: CGPoint(x: size.width / 2, y: size.height / 2), length: length, angle: -0.35, line: max(1, length / 16),
                             ink: filled ? Look.ink : Look.ink.opacity(0.35), wash: Look.lemon, seed: 1, filled: filled)
        }.accessibilityHidden(true)
    }
}

/// The coach's confidence, out of five lemons.
struct LemonScore: View {
    let score: Int?
    var body: some View {
        HStack(spacing: 2) {
            ForEach(0..<5, id: \.self) { LemonMark(filled: $0 < (score ?? 0)).frame(width: 18, height: 13) }
        }
        .accessibilityElement().accessibilityLabel(score.map { "Coach confidence \($0) of 5" } ?? "Not rehearsed yet")
    }
}

/// A square maiolica tile: blue quarter-circles in its corners and a flower with a lemon-yellow heart.
struct MaiolicaTile: View {
    var body: some View {
        Canvas { context, size in
            let s = min(size.width, size.height)
            let rect = CGRect(x: (size.width - s) / 2, y: (size.height - s) / 2, width: s, height: s)
            let ink = Look.ink, line = s / 40
            context.fill(Path(roundedRect: rect, cornerRadius: s * 0.08), with: .color(Look.card))
            context.stroke(Path(roundedRect: rect.insetBy(dx: line, dy: line), cornerRadius: s * 0.07), with: .color(ink), lineWidth: line)
            let c = CGPoint(x: rect.midX, y: rect.midY)
            for corner in [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY), CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)] {
                var arc = Path()
                arc.addEllipse(in: CGRect(x: corner.x - s * 0.24, y: corner.y - s * 0.24, width: s * 0.48, height: s * 0.48))
                context.drawLayer { layer in
                    layer.clip(to: Path(roundedRect: rect.insetBy(dx: line * 2, dy: line * 2), cornerRadius: s * 0.06))
                    layer.fill(arc, with: .color(ink.opacity(0.9)))
                    layer.stroke(Path(ellipseIn: CGRect(x: corner.x - s * 0.31, y: corner.y - s * 0.31, width: s * 0.62, height: s * 0.62)), with: .color(ink), lineWidth: line * 0.8)
                }
            }
            for i in 0..<4 {
                let a = CGFloat(i) * .pi / 2 + .pi / 4
                let petal = Sketch.polygon(Sketch.lemonOutline(center: Sketch.place(CGPoint(x: s * 0.15, y: 0), at: c, angle: a), length: s * 0.26, width: s * 0.14, angle: a))
                context.fill(petal, with: .color(ink.opacity(0.85)))
            }
            context.fill(Path(ellipseIn: CGRect(x: c.x - s * 0.08, y: c.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(Look.lemon))
            context.stroke(Path(ellipseIn: CGRect(x: c.x - s * 0.08, y: c.y - s * 0.08, width: s * 0.16, height: s * 0.16)), with: .color(ink), lineWidth: line * 0.8)
        }.accessibilityHidden(true)
    }
}

/// A painted plate from the table, its rim a ring of yellow flowers and blue scrolls.
struct MaiolicaPlate: View {
    var body: some View {
        Canvas { context, size in
            let r = min(size.width, size.height) / 2 - 2
            let c = CGPoint(x: size.width / 2, y: size.height / 2), line = max(1, r / 70)
            let ink = Look.ink, wash = Look.lemon
            func circle(_ radius: CGFloat) -> Path { Path(ellipseIn: CGRect(x: c.x - radius, y: c.y - radius, width: radius * 2, height: radius * 2)) }
            context.fill(circle(r), with: .color(Look.card))
            context.stroke(circle(r), with: .color(ink), lineWidth: line * 1.4)
            context.stroke(circle(r * 0.66), with: .color(ink.opacity(0.6)), lineWidth: line)
            let count = 12
            for i in 0..<count {
                let a = CGFloat(i) / CGFloat(count) * 2 * .pi
                let flower = Sketch.place(CGPoint(x: r * 0.83, y: 0), at: c, angle: a)
                for p in 0..<4 {
                    let pa = a + CGFloat(p) * .pi / 2
                    let petal = Sketch.polygon(Sketch.lemonOutline(center: Sketch.place(CGPoint(x: r * 0.045, y: 0), at: flower, angle: pa), length: r * 0.09, width: r * 0.06, angle: pa))
                    context.fill(petal, with: .color(wash))
                    context.stroke(petal, with: .color(ink.opacity(0.7)), lineWidth: line * 0.6)
                }
                // A scroll between each flower and the next.
                let mid = a + .pi / CGFloat(count)
                var scroll = Path()
                scroll.move(to: Sketch.place(CGPoint(x: r * 0.74, y: 0), at: c, angle: mid - 0.08))
                scroll.addQuadCurve(to: Sketch.place(CGPoint(x: r * 0.92, y: 0), at: c, angle: mid + 0.08), control: Sketch.place(CGPoint(x: r * 0.86, y: 0), at: c, angle: mid - 0.16))
                context.stroke(scroll, with: .color(ink), style: StrokeStyle(lineWidth: line, lineCap: .round))
            }
            // A lemon and its leaf, set down on the plate.
            let lemon = CGPoint(x: c.x - r * 0.06, y: c.y + r * 0.08)
            let end = Sketch.place(CGPoint(x: r * 0.33, y: 0), at: lemon, angle: -0.5)
            Sketch.drawLeaf(context, base: end, angle: -1.9, length: r * 0.34, line: line * 1.2, ink: ink)
            Sketch.drawLeaf(context, base: end, angle: -0.2, length: r * 0.28, line: line * 1.2, ink: ink)
            Sketch.drawLemon(context, center: lemon, length: r * 0.62, angle: -0.5, line: line * 1.2, ink: ink, wash: wash, seed: 4)
        }.accessibilityHidden(true)
    }
}
