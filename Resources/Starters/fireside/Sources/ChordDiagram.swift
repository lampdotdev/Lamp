import SwiftUI

/// Open-position shapes, low E to high E. -1 is muted, 0 is open.
enum ChordShapes {
    static let frets: [String: [Int]] = [
        "G": [3,2,0,0,0,3], "C": [-1,3,2,0,1,0], "D": [-1,-1,0,2,3,2], "Em": [0,2,2,0,0,0],
        "Am": [-1,0,2,2,1,0], "E": [0,2,2,1,0,0], "A": [-1,0,2,2,2,0], "Dm": [-1,-1,0,2,3,1],
        "F": [-1,-1,3,2,1,1], "B7": [-1,2,1,2,0,2], "D7": [-1,-1,0,2,1,2], "G7": [3,2,0,0,0,1],
        "Cadd9": [-1,3,2,0,3,0], "A7": [-1,0,2,0,2,0], "E7": [0,2,0,1,0,0], "Em7": [0,2,0,0,0,0],
        "Am7": [-1,0,2,0,1,0], "Asus2": [-1,0,2,2,0,0], "Asus4": [-1,0,2,2,3,0], "Dsus2": [-1,-1,0,2,3,0],
        "Dsus4": [-1,-1,0,2,3,3], "C7": [-1,3,2,3,1,0], "Bm": [-1,2,4,4,3,2], "Fmaj7": [-1,-1,3,2,1,0],
        "Dm7": [-1,-1,0,2,1,1], "Esus4": [0,2,2,2,0,0], "Gsus4": [3,3,0,0,1,3], "Bm7": [-1,2,0,2,0,2],
    ]
}

struct ChordDiagram: View {
    let chord: String
    var width: CGFloat = 64
    var highlight: Color = .ink
    var showName = true
    var body: some View {
        VStack(spacing: width * 0.08) {
            if showName { Text(chord).font(.book(width * 0.3, .semibold)).foregroundStyle(Color.ink) }
            if let shape = ChordShapes.frets[chord] {
                Canvas { ctx, size in draw(shape, ctx: ctx, size: size) }
                    .frame(width: width, height: width * 1.15)
            } else {
                RoundedRectangle(cornerRadius: 4).strokeBorder(Color.pencil.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                    .overlay(Text("no\nshape yet").font(.system(size: width * 0.13, design: .serif)).italic().multilineTextAlignment(.center).foregroundStyle(Color.pencil))
                    .frame(width: width, height: width * 1.15)
            }
        }
        .accessibilityElement().accessibilityLabel("\(chord) chord diagram")
    }
    func draw(_ shape: [Int], ctx: GraphicsContext, size: CGSize) {
        let top = size.height * 0.16, bottom = size.height - 2
        let left = size.width * 0.1, right = size.width * 0.9
        let fretted = shape.filter { $0 > 0 }
        let base = (fretted.max() ?? 0) > 4 ? (fretted.min() ?? 1) : 1
        let frets = 4
        let dx = (right - left) / 5, dy = (bottom - top) / Double(frets)
        let ink = GraphicsContext.Shading.color(Color.ink.opacity(0.75))
        for s in 0..<6 {
            var p = Path(); p.move(to: CGPoint(x: left + Double(s) * dx, y: top)); p.addLine(to: CGPoint(x: left + Double(s) * dx, y: bottom))
            ctx.stroke(p, with: ink, lineWidth: s < 3 ? 1.1 : 0.8)
        }
        for f in 0...frets {
            var p = Path(); p.move(to: CGPoint(x: left, y: top + Double(f) * dy)); p.addLine(to: CGPoint(x: right, y: top + Double(f) * dy))
            ctx.stroke(p, with: ink, lineWidth: f == 0 && base == 1 ? 3 : 0.8)
        }
        let r = min(dx, dy) * 0.36
        for (s, fret) in shape.enumerated() {
            let x = left + Double(s) * dx
            if fret == -1 {
                let m = r * 0.7, y = top * 0.45
                var p = Path(); p.move(to: CGPoint(x: x - m, y: y - m)); p.addLine(to: CGPoint(x: x + m, y: y + m))
                p.move(to: CGPoint(x: x + m, y: y - m)); p.addLine(to: CGPoint(x: x - m, y: y + m))
                ctx.stroke(p, with: .color(Color.pencil), lineWidth: 1.2)
            } else if fret == 0 {
                ctx.stroke(Path(ellipseIn: CGRect(x: x - r * 0.7, y: top * 0.45 - r * 0.7, width: r * 1.4, height: r * 1.4)), with: .color(Color.pencil), lineWidth: 1.1)
            } else {
                let y = top + (Double(fret - base) + 0.5) * dy
                ctx.fill(Path(ellipseIn: CGRect(x: x - r, y: y - r, width: r * 2, height: r * 2)), with: .color(highlight))
            }
        }
    }
}
