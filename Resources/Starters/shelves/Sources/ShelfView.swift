import SwiftUI

/// A bookcase: the items stand in rows on wooden planks, as many to a row as fit the window's width, with
/// empty planks below so the case reaches the bottom of the window.
struct ShelfView: View {
    @EnvironmentObject private var library: Library
    let items: [ShelfItem]
    @State private var shown: ShelfItem.ID?
    @State private var hovered: ShelfItem.ID?
    @State private var deleting: ShelfItem?

    private let rowHeight = SpineLook.tallest + 26
    private let inset = 22.0

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                let rows = Self.rows(of: items, width: proxy.size.width - inset * 2)
                let count = max(rows.count, Int(proxy.size.height / (rowHeight + Plank.thickness)))
                VStack(spacing: 0) {
                    ForEach(0..<count, id: \.self) { index in
                        VStack(spacing: 0) {
                            HStack(alignment: .bottom, spacing: 2) {
                                if index < rows.count {
                                    ForEach(rows[index]) { book(for: $0) }
                                }
                            }
                            .padding(.horizontal, inset)
                            .frame(maxWidth: .infinity, minHeight: rowHeight, alignment: .bottomLeading)
                            Plank()
                        }
                    }
                }
            }
            .background(Wood.back)
        }
        .confirmationDialog("Remove “\(deleting?.title ?? "")”?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }),
                            presenting: deleting) { item in
            Button("Remove", role: .destructive) { library.delete(item.id); deleting = nil }
            Button("Cancel", role: .cancel) { deleting = nil }
        }
    }

    private func book(for item: ShelfItem) -> some View {
        StandingItem(item: item, cover: library.covers[item.id])
            .offset(y: hovered == item.id || shown == item.id ? -6 : 0)
            .animation(.spring(duration: 0.25), value: hovered)
            .onHover { hovered = $0 ? item.id : (hovered == item.id ? nil : hovered) }
            .onTapGesture { shown = item.id }
            .popover(isPresented: Binding(get: { shown == item.id }, set: { if !$0 { shown = nil } }),
                     arrowEdge: .bottom) {
                DetailCard(id: item.id)
            }
            .contextMenu { menu(for: item) }
            .draggable(item.id.uuidString)
            .help("\(item.title), \(item.creator)")
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("\(item.title) by \(item.creator)")
            .accessibilityValue(item.status.label)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { shown = item.id }
    }

    @ViewBuilder
    private func menu(for item: ShelfItem) -> some View {
        Button("Show Details") { shown = item.id }
        Button(item.facesOut ? "Turn Spine Out" : "Turn Cover Out") {
            var turned = item
            turned.facesOut.toggle()
            library.update(turned)
        }
        Menu("Move To") {
            ForEach(library.shelves.filter { $0.id != item.shelfID }) { shelf in
                Button(shelf.name) { library.move(item.id, to: shelf.id) }
            }
        }
        .disabled(library.shelves.count < 2)
        Divider()
        Button("Remove from Shelves…", role: .destructive) { deleting = item }
    }

    /// Fills rows left to right, starting a new one when the next item wouldn't fit.
    static func rows(of items: [ShelfItem], width: Double) -> [[ShelfItem]] {
        var rows: [[ShelfItem]] = []
        var row: [ShelfItem] = []
        var used = 0.0
        for item in items {
            let size = (item.facesOut ? (item.look.height * 0.68).rounded() : item.look.width) + 2
            if used + size > width, !row.isEmpty {
                rows.append(row)
                row = []
                used = 0
            }
            row.append(item)
            used += size
        }
        if !row.isEmpty { rows.append(row) }
        return rows
    }
}

/// The colours of the bookcase, lighter oak in light mode and walnut in dark mode.
enum Wood {
    static let back = LinearGradient(colors: [dynamic(light: (0.89, 0.80, 0.68), dark: (0.17, 0.12, 0.09)),
                                              dynamic(light: (0.83, 0.72, 0.58), dark: (0.12, 0.08, 0.06))],
                                     startPoint: .top, endPoint: .bottom)
    static let top = dynamic(light: (0.80, 0.60, 0.38), dark: (0.50, 0.34, 0.21))
    static let front = dynamic(light: (0.62, 0.42, 0.24), dark: (0.36, 0.23, 0.13))

    private static func dynamic(light: (Double, Double, Double), dark: (Double, Double, Double)) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let (r, g, b) = appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: r, green: g, blue: b, alpha: 1)
        })
    }
}

/// One wooden plank: a lit top edge, a front with a little grain, and a shadow on the wall beneath it.
struct Plank: View {
    static let thickness = 16.0

    var body: some View {
        VStack(spacing: 0) {
            Wood.top.frame(height: 4)
            ZStack {
                LinearGradient(colors: [Wood.front, Wood.front.opacity(0.85)], startPoint: .top, endPoint: .bottom)
                Canvas { context, size in
                    // A few long, faint grain lines, the same on every plank.
                    for line in 0..<4 {
                        let y = size.height * (0.2 + Double(line) * 0.2)
                        var path = Path()
                        path.move(to: CGPoint(x: 0, y: y))
                        for x in stride(from: 0.0, through: Double(size.width), by: 40) {
                            let wave: Double = sin(x / 90 + Double(line)) * 1.2
                            path.addLine(to: CGPoint(x: x, y: y + wave))
                        }
                        context.stroke(path, with: .color(.black.opacity(0.08)), lineWidth: 0.8)
                    }
                }
            }
            .frame(height: Self.thickness - 4)
        }
        .shadow(color: .black.opacity(0.3), radius: 4, y: 4)
        .accessibilityHidden(true)
    }
}
