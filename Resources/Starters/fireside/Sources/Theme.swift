import SwiftUI
import AppKit

// The songbook's look: aged paper, pencil ink, rubber stamps and tape.
extension Color {
    static func dynamic(light: (Double,Double,Double), dark: (Double,Double,Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let d = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let c = d ? dark : light
            return NSColor(srgbRed: c.0, green: c.1, blue: c.2, alpha: 1)
        })
    }
    static let paper = dynamic(light: (0.955, 0.925, 0.855), dark: (0.115, 0.095, 0.078))
    static let paperCard = dynamic(light: (0.985, 0.968, 0.925), dark: (0.17, 0.142, 0.118))
    static let paperShade = dynamic(light: (0.91, 0.865, 0.775), dark: (0.21, 0.175, 0.145))
    static let ink = dynamic(light: (0.2, 0.145, 0.105), dark: (0.94, 0.89, 0.8))
    static let pencil = dynamic(light: (0.45, 0.39, 0.33), dark: (0.66, 0.6, 0.53))
    static let rust = dynamic(light: (0.71, 0.31, 0.16), dark: (0.9, 0.48, 0.28))
    static let mustard = dynamic(light: (0.72, 0.53, 0.14), dark: (0.89, 0.71, 0.33))
    static let sage = dynamic(light: (0.33, 0.5, 0.36), dark: (0.55, 0.74, 0.56))
    static let tape = dynamic(light: (0.93, 0.87, 0.68), dark: (0.55, 0.49, 0.36))
}

extension Font {
    static func book(_ size: CGFloat, _ weight: Font.Weight = .regular) -> Font { .system(size: size, weight: weight, design: .serif) }
}

/// A stable number from a string, for tilts and art that never shuffle between launches.
func stableHash(_ s: String) -> Int { s.unicodeScalars.reduce(5381) { ($0 &* 33 &+ Int($1.value)) & 0x7fffffff } }

/// Aged paper: warm base, deterministic grain, soft darkened edges and the odd coffee ring.
struct PaperBackground: View {
    var coffeeRing = true
    var body: some View {
        ZStack {
            Color.paper
            Canvas { ctx, size in
                var seed: UInt64 = 0x9E3779B97F4A7C15
                func rnd() -> Double { seed ^= seed << 13; seed ^= seed >> 7; seed ^= seed << 17; return Double(seed % 10_000) / 10_000 }
                let count = Int(size.width * size.height / 900)
                for _ in 0..<count {
                    let r = CGRect(x: rnd() * size.width, y: rnd() * size.height, width: 1.2, height: 1.2)
                    ctx.fill(Path(ellipseIn: r), with: .color(Color.ink.opacity(0.035 + rnd() * 0.05)))
                }
                for _ in 0..<40 {
                    let x = rnd() * size.width, y = rnd() * size.height, w = 40 + rnd() * 160
                    var p = Path(); p.move(to: CGPoint(x: x, y: y)); p.addLine(to: CGPoint(x: x + w, y: y + rnd() * 6 - 3))
                    ctx.stroke(p, with: .color(Color.ink.opacity(0.018)), lineWidth: 0.6)
                }
                if coffeeRing && size.width > 500 {
                    let c = CGPoint(x: size.width - 120, y: 150), radius = 64.0
                    for i in 0..<3 {
                        let rr = radius - Double(i) * 2.2
                        let ring = Path(ellipseIn: CGRect(x: c.x - rr, y: c.y - rr * 0.97, width: rr * 2, height: rr * 1.94))
                        ctx.stroke(ring, with: .color(Color(red: 0.5, green: 0.3, blue: 0.12).opacity(0.05 - Double(i) * 0.012)), style: StrokeStyle(lineWidth: 3 - Double(i), dash: i == 2 ? [80, 14, 40, 20] : []))
                    }
                }
            }
            RadialGradient(colors: [.clear, Color(red: 0.35, green: 0.2, blue: 0.08).opacity(0.10)], center: .center, startRadius: 280, endRadius: 1100)
                .blendMode(.multiply)
        }
        .ignoresSafeArea()
    }
}

/// A strip of masking tape, slightly crooked.
struct TapeStrip: View {
    var angle: Double = -3
    var body: some View {
        Rectangle()
            .fill(Color.tape.opacity(0.78))
            .overlay(LinearGradient(colors: [.white.opacity(0.25), .clear, .white.opacity(0.12)], startPoint: .leading, endPoint: .trailing))
            .mask(TornEdges())
            .frame(width: 74, height: 20)
            .rotationEffect(.degrees(angle))
            .shadow(color: .black.opacity(0.08), radius: 1, y: 1)
            .accessibilityHidden(true)
    }
}
struct TornEdges: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path(); let teeth = 7
        p.move(to: CGPoint(x: r.minX + 2, y: r.minY))
        p.addLine(to: CGPoint(x: r.maxX - 2, y: r.minY))
        for i in 0...teeth { p.addLine(to: CGPoint(x: r.maxX - (i % 2 == 0 ? 0 : 3), y: r.minY + r.height * Double(i) / Double(teeth))) }
        p.addLine(to: CGPoint(x: r.minX + 2, y: r.maxY))
        for i in 0...teeth { p.addLine(to: CGPoint(x: r.minX + (i % 2 == 0 ? 3 : 0), y: r.maxY - r.height * Double(i) / Double(teeth))) }
        p.closeSubpath(); return p
    }
}

/// A rubber stamp, as if pressed a little unevenly.
struct Stamp: View {
    let text: String
    var color: Color = .rust
    var angle: Double = -7
    var size: CGFloat = 10
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: size, weight: .heavy, design: .rounded)).tracking(1.6)
            .foregroundStyle(color)
            .padding(.horizontal, 7).padding(.vertical, 3)
            .overlay(RoundedRectangle(cornerRadius: 3).strokeBorder(color, lineWidth: 1.6))
            .opacity(0.82)
            .rotationEffect(.degrees(angle))
    }
}

/// How a song's state looks on paper.
struct StateMark: View {
    let state: String
    var big = false
    var body: some View {
        switch state {
        case "know it by heart": Stamp(text: "By heart", color: .rust, angle: -8, size: big ? 13 : 10)
        case "can play it": Stamp(text: "Can play", color: .sage, angle: 4, size: big ? 13 : 10)
        default:
            Text("reading it").font(.system(size: big ? 14 : 11, design: .serif)).italic().foregroundStyle(Color.pencil)
        }
    }
}

/// A guitar pick, for counting the twenty.
struct PickShape: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.midX, y: r.maxY))
        p.addCurve(to: CGPoint(x: r.minX, y: r.minY + r.height * 0.28), control1: CGPoint(x: r.midX - r.width * 0.2, y: r.maxY - r.height * 0.1), control2: CGPoint(x: r.minX, y: r.minY + r.height * 0.55))
        p.addCurve(to: CGPoint(x: r.maxX, y: r.minY + r.height * 0.28), control1: CGPoint(x: r.minX, y: r.minY - r.height * 0.05), control2: CGPoint(x: r.maxX, y: r.minY - r.height * 0.05))
        p.addCurve(to: CGPoint(x: r.midX, y: r.maxY), control1: CGPoint(x: r.maxX, y: r.minY + r.height * 0.55), control2: CGPoint(x: r.midX + r.width * 0.2, y: r.maxY - r.height * 0.1))
        return p
    }
}

/// The twenty songs to know by heart, as twenty picks.
struct PickTally: View {
    let earned: Int
    var body: some View {
        let columns = Array(repeating: GridItem(.fixed(15), spacing: 4), count: 10)
        LazyVGrid(columns: columns, alignment: .leading, spacing: 5) {
            ForEach(0..<20, id: \.self) { i in
                PickShape()
                    .fill(i < earned ? AnyShapeStyle(LinearGradient(colors: [.rust, .mustard], startPoint: .topLeading, endPoint: .bottomTrailing)) : AnyShapeStyle(Color.clear))
                    .overlay(PickShape().stroke(i < earned ? Color.clear : Color.pencil.opacity(0.45), style: StrokeStyle(lineWidth: 1, dash: [2, 1.5])))
                    .frame(width: 13, height: 15)
                    .rotationEffect(.degrees(Double(stableHash("\(i)") % 30) - 15))
            }
        }
        .accessibilityElement().accessibilityLabel("\(earned) of 20 songs known by heart")
    }
}

/// The art for each song and folder, all painted in the same hand.
enum SongArt {
    static let all: [(file: String, meaning: String)] = [
        ("campfire.png", "campfire: rousing singalongs with friends outdoors"),
        ("lantern.png", "lantern: hymns, spirituals, old folk songs about home and hope"),
        ("harmonica.png", "harmonica: country, blues, cowboy and traveling songs"),
        ("mug.png", "mug: cosy, easygoing, morning or kitchen songs"),
        ("pine.png", "pine tree: songs about land, mountains, the West, nature"),
        ("boat.png", "rowboat: songs about rivers, the sea, water, sailing, leaving"),
        ("moon.png", "moon: lullabies, gentle bedtime and night songs"),
        ("feather.png", "feather: sad, wistful, tender fingerpicked songs"),
        ("guitar.png", "guitar: anything else"),
    ]
    static func file(for song: Song) -> String {
        if let art = song.art, all.contains(where: { $0.file == art }) { return art }
        return all[stableHash(song.title) % (all.count - 1)].file
    }
    static func file(forFolder id: String) -> String {
        switch id {
        case "camp": "campfire.png"
        case "sad": "feather.png"
        case "bed": "moon.png"
        case "all": "guitar.png"
        default: all[stableHash(id) % all.count].file
        }
    }
    private static var cache: [String: NSImage] = [:]
    static func image(_ file: String) -> Image {
        if let ns = cache[file] { return Image(nsImage: ns) }
        if let ns = LampAssets.image(file) { cache[file] = ns; return Image(nsImage: ns) }
        return Image(systemName: "music.note")
    }
}

/// Lifts a card toward you under the pointer.
struct LiftOnHover: ViewModifier {
    let tilt: Double
    @State private var hover = false
    func body(content: Content) -> some View {
        content
            .rotationEffect(.degrees(hover ? 0 : tilt))
            .scaleEffect(hover ? 1.025 : 1)
            .shadow(color: Color(red: 0.25, green: 0.15, blue: 0.05).opacity(hover ? 0.22 : 0.1), radius: hover ? 16 : 5, y: hover ? 10 : 3)
            .animation(.spring(response: 0.35, dampingFraction: 0.7), value: hover)
            .onHover { hover = $0 }
    }
}
