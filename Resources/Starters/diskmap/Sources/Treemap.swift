import SwiftUI
import AppKit

/// Squarified treemap layout: splits a rectangle into tiles whose areas match the values.
enum TreemapLayout {
    static func layout(_ values: [Double], in rect: CGRect) -> [CGRect] {
        var result = [CGRect](repeating: .zero, count: values.count)
        let total = values.reduce(0, +)
        guard total > 0, rect.width > 1, rect.height > 1 else { return result }
        let scale = Double(rect.width * rect.height) / total
        let areas = values.map { max(0, $0 * scale) }
        var remaining = rect
        var i = 0

        func worst(_ sum: Double, _ maxA: Double, _ minA: Double, _ side: Double) -> Double {
            guard sum > 0, minA > 0 else { return .infinity }
            let s2 = side * side
            return max(s2 * maxA / (sum * sum), (sum * sum) / (s2 * minA))
        }

        while i < areas.count {
            let side = Double(min(remaining.width, remaining.height))
            guard side > 0 else { break }
            var j = i + 1
            var sum = areas[i], maxA = areas[i], minA = areas[i]
            while j < areas.count {
                let a = areas[j]
                let newSum = sum + a
                if worst(newSum, max(maxA, a), min(minA, a), side) <= worst(sum, maxA, minA, side) {
                    sum = newSum; maxA = max(maxA, a); minA = min(minA, a); j += 1
                } else { break }
            }
            let thickness = CGFloat(sum / side)
            if remaining.width >= remaining.height {
                var y = remaining.minY
                for k in i..<j {
                    let h = thickness > 0 ? CGFloat(areas[k]) / thickness : 0
                    result[k] = CGRect(x: remaining.minX, y: y, width: thickness, height: h)
                    y += h
                }
                remaining = CGRect(x: remaining.minX + thickness, y: remaining.minY,
                                   width: max(0, remaining.width - thickness), height: remaining.height)
            } else {
                var x = remaining.minX
                for k in i..<j {
                    let w = thickness > 0 ? CGFloat(areas[k]) / thickness : 0
                    result[k] = CGRect(x: x, y: remaining.minY, width: w, height: thickness)
                    x += w
                }
                remaining = CGRect(x: remaining.minX, y: remaining.minY + thickness,
                                   width: remaining.width, height: max(0, remaining.height - thickness))
            }
            i = j
        }
        return result
    }
}

struct Tile {
    let node: Node
    let size: Int64
    let rect: CGRect
    let color: Color
    let inner: [(node: Node, rect: CGRect)]
    let headerHeight: CGFloat
    /// Still being measured, so it will grow.
    let measuring: Bool
}

struct TreemapContent {
    var tiles: [Tile] = []
    /// Space set aside for what hasn't been measured yet.
    var gap: CGRect?
    var gapSize: Int64 = 0
}

enum TileColors {
    static let palette: [Color] = [.blue, .purple, .orange, .teal, .pink, .green, .indigo, .red, .cyan, .mint, .yellow, .brown]

    static func color(for node: Node, index: Int) -> Color {
        switch node.kind {
        case .folder: return palette[index % palette.count]
        case .file: return Color(nsColor: .systemGray)
        case .smallFiles: return Color(nsColor: .systemGray).opacity(0.6)
        case .hidden: return Color(nsColor: .tertiaryLabelColor)
        }
    }
}

func buildTiles(for folder: Node, pending: Int64, in rect: CGRect) -> TreemapContent {
    let items = Array(folder.sortedChildren.map { ($0, $0.size) }.filter { $0.1 > 0 }.prefix(400))
    var values = items.map { Double($0.1) }
    if pending > 0 { values.append(Double(pending)) }
    var rects = TreemapLayout.layout(values, in: rect)
    var content = TreemapContent()
    if pending > 0 {
        let gap = rects.removeLast()
        if gap.width > 1, gap.height > 1 { content.gap = gap; content.gapSize = pending }
    }
    var folderIndex = 0
    content.tiles = zip(items, rects).map { item, r in
        let (node, size) = item
        let color = TileColors.color(for: node, index: folderIndex)
        if node.kind == .folder { folderIndex += 1 }
        var inner: [(Node, CGRect)] = []
        var header: CGFloat = 0
        if node.kind == .folder, r.width > 50, r.height > 44 {
            let kids = Array(node.sortedChildren.map { ($0, $0.size) }.filter { $0.1 > 0 }.prefix(150))
            if !kids.isEmpty {
                header = 18
                let area = CGRect(x: r.minX + 2, y: r.minY + header, width: r.width - 4, height: r.height - header - 2)
                let kidRects = TreemapLayout.layout(kids.map { Double($0.1) }, in: area)
                inner = Array(zip(kids.map(\.0), kidRects))
            }
        }
        return Tile(node: node, size: size, rect: r, color: color, inner: inner, headerHeight: header,
                    measuring: node.kind == .folder && !node.isComplete)
    }
    return content
}

struct TreemapView: View {
    let folder: Node
    let revision: Int
    let pending: Int64
    @Binding var selection: Set<Node.ID>
    @Binding var hovered: (outer: Node, inner: Node?)?
    var onOpen: (Node, Node?) -> Void

    var body: some View {
        GeometryReader { geo in
            let content = buildTiles(for: folder, pending: pending, in: CGRect(origin: .zero, size: geo.size))
            let tiles = content.tiles
            Canvas { context, _ in
                draw(tiles, in: &context)
                if let gap = content.gap { drawGap(gap, size: content.gapSize, in: &context) }
            }
            .onContinuousHover { phase in
                switch phase {
                case .active(let p): hovered = hit(p, tiles)
                case .ended: hovered = nil
                }
            }
            .onTapGesture(coordinateSpace: .local) { p in
                let h = hit(p, tiles)
                if (NSApp.currentEvent?.clickCount ?? 1) >= 2, let h {
                    onOpen(h.outer, h.inner)
                } else {
                    // ⌘-click adds or takes away one item, ⇧-click adds; a plain click selects just that one.
                    let flags = NSApp.currentEvent?.modifierFlags ?? []
                    if let id = h?.outer.id, flags.contains(.command) {
                        if selection.contains(id) { selection.remove(id) } else { selection.insert(id) }
                    } else if let id = h?.outer.id, flags.contains(.shift) {
                        selection.insert(id)
                    } else {
                        selection = Set([h?.outer.id].compactMap { $0 })
                    }
                }
            }
        }
    }

    private func drawGap(_ rect: CGRect, size: Int64, in context: inout GraphicsContext) {
        let r = rect.insetBy(dx: 1.5, dy: 1.5)
        guard r.width > 2, r.height > 2 else { return }
        let shape = Path(roundedRect: r, cornerRadius: min(4, r.width / 4, r.height / 4))
        context.fill(shape, with: .color(.primary.opacity(0.04)))
        context.stroke(shape, with: .color(.secondary.opacity(0.6)), style: StrokeStyle(lineWidth: 1, dash: [5, 4]))
        guard r.width > 70, r.height > 30 else { return }
        var c = context
        c.clip(to: Path(r.insetBy(dx: 4, dy: 4)))
        let text = Text("Not measured yet").font(.caption.weight(.semibold)).foregroundColor(.secondary)
            + Text("\nabout " + formatBytes(size)).font(.caption2).foregroundColor(.secondary.opacity(0.8))
        c.draw(c.resolve(text), at: CGPoint(x: r.midX, y: r.midY), anchor: .center)
    }

    private func hit(_ p: CGPoint, _ tiles: [Tile]) -> (outer: Node, inner: Node?)? {
        guard let tile = tiles.first(where: { $0.rect.contains(p) }) else { return nil }
        let inner = tile.inner.first(where: { $0.rect.contains(p) })?.node
        return (tile.node, inner)
    }

    private func draw(_ tiles: [Tile], in context: inout GraphicsContext) {
        let hoveredID = hovered?.outer.id
        let hoveredInner = hovered?.inner.map { ObjectIdentifier($0) }
        for tile in tiles {
            let r = tile.rect.insetBy(dx: 0.5, dy: 0.5)
            guard r.width > 0, r.height > 0 else { continue }
            let shape = Path(roundedRect: r, cornerRadius: min(4, r.width / 4, r.height / 4))
            context.fill(shape, with: .color(tile.measuring ? tile.color.opacity(0.6) : tile.color))
            if tile.node.kind == .hidden {
                context.fill(shape, with: .color(.primary.opacity(0.08)))
            }

            for (i, item) in tile.inner.enumerated() {
                let ir = item.rect.insetBy(dx: 0.5, dy: 0.5)
                guard ir.width > 0.5, ir.height > 0.5 else { continue }
                let shade = item.node.kind == .folder ? 0.18 + Double(i % 4) * 0.05 : 0.1
                let p = Path(roundedRect: ir, cornerRadius: min(2, ir.width / 4, ir.height / 4))
                context.fill(p, with: .color(.black.opacity(shade)))
                if ObjectIdentifier(item.node) == hoveredInner && tile.node.id == hoveredID {
                    context.fill(p, with: .color(.white.opacity(0.25)))
                }
                if ir.width > 60, ir.height > 16 {
                    label(item.node.title, size: nil, in: ir, context: &context, font: .caption2)
                }
            }

            if tile.node.id == hoveredID && hoveredInner == nil {
                context.fill(shape, with: .color(.white.opacity(0.18)))
            }
            if selection.contains(tile.node.id) {
                context.stroke(shape, with: .color(.white), lineWidth: 3)
                context.stroke(shape, with: .color(.accentColor), lineWidth: 1.5)
            }

            if tile.headerHeight > 0 {
                let header = CGRect(x: r.minX, y: r.minY, width: r.width, height: tile.headerHeight)
                label(tile.node.title, size: tile.size, in: header, context: &context, font: .caption.weight(.semibold))
            } else if r.width > 44, r.height > 16 {
                label(tile.node.title, size: r.height > 32 ? tile.size : nil, in: r, context: &context, font: .caption.weight(.semibold))
            }
        }
    }

    private func label(_ text: String, size: Int64?, in rect: CGRect, context: inout GraphicsContext, font: Font) {
        var c = context
        c.clip(to: Path(rect.insetBy(dx: 3, dy: 1)))
        var t = Text(text).font(font).foregroundColor(.white)
        if let size, rect.width > 90 {
            t = t + Text("  " + formatBytes(size)).font(.caption2).foregroundColor(.white.opacity(0.8))
        }
        c.draw(c.resolve(t), at: CGPoint(x: rect.minX + 5, y: rect.minY + 2), anchor: .topLeading)
    }
}

func formatBytes(_ bytes: Int64) -> String {
    ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
}
