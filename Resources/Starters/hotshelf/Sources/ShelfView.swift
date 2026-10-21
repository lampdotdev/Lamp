import SwiftUI

/// The whole app: a wooden pantry cabinet at night. The wall, the lamp, the planks and their lights are all one
/// thing that scrolls and resizes together; only the window's own edges stay put.
struct ShelfView: View {
    @EnvironmentObject var shelf: Shelf
    @ObservedObject private var labels = LabelFinder.shared

    private struct Plank: Identifiable {
        var id: String
        var title: String?
        var bottles: [Bottle]
        var retired = false
        var dim = false
    }

    /// Families in order, each wrapped onto as many planks as the window's width needs; retired bottles last.
    private func planks(perPlank: Int) -> [Plank] {
        var result: [Plank] = []
        let groups = Dictionary(grouping: shelf.active, by: \.flavor)
        for family in FlavorFamily.allCases {
            let bottles = (groups[family] ?? []).sorted { $0.heat < $1.heat }
            guard !bottles.isEmpty else { continue }
            let slots = bottles.count
            let count = max(1, Int((Double(slots) / Double(perPlank)).rounded(.up)))
            for i in 0..<count {
                let chunk = Array(bottles.dropFirst(i * perPlank).prefix(perPlank))
                result.append(Plank(id: "\(family.rawValue)-\(i)", title: i == 0 ? family.title : nil, bottles: chunk))
            }
        }
        let retired = shelf.retired
        // Retired bottles are shorter but just as wide, so they fit as many to a plank as the others.
        for i in stride(from: 0, to: retired.count, by: perPlank) {
            result.append(Plank(id: "retired-\(i)", title: i == 0 ? Look.current.finished : nil,
                                bottles: Array(retired.dropFirst(i).prefix(perPlank)), retired: true))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let perPlank = Studio.perPlank(width: geo.size.width)
            ZStack {
                StudioWall()
                ScrollView(.vertical) {
                    VStack(spacing: 0) {
                        titleHeader
                        if shelf.bottles.isEmpty {
                            emptyShelf
                        } else {
                            ForEach(planks(perPlank: perPlank)) { plank in
                                let height = plank.retired ? Look.current.finishedHeight : Look.current.bottleHeight
                                ShelfRow(title: plank.title, height: height, dim: plank.dim) {
                                    ForEach(plank.bottles) { b in
                                        column(BottleView(bottle: b, height: height), height: height) {
                                            if plank.retired { RailText(verdict: b.verdict) } else { RailText(heat: b.intensity, stars: b.score) }
                                        }
                                    }
                                }
                            }
                        }
                        Color.clear.frame(height: shelf.pick != nil ? 250 : 140)
                    }
                    .frame(width: geo.size.width)
                }
                .scrollContentBackground(.hidden)
                // The light over the whole set, bottles and shelves included, so they sit in one room.
                StudioLighting()
            }
        }
        .background(Look.current.shelfUnder)
        .overlay(alignment: .bottomTrailing) { TonightBar() }
        .overlay {
            if let id = shelf.openID {
                ZStack {
                    Color.black.opacity(0.45)
                        .ignoresSafeArea()
                        .onTapGesture { shelf.close() }
                        .transition(.opacity)
                    BottleDialog(id: id)
                        .transition(.modifier(active: FlyIn(amount: 1), identity: FlyIn(amount: 0)))
                }
            }
        }
        .confirmationDialog("Take \(shelf.confirmDeleteID.flatMap { shelf.bottle($0)?.name } ?? "it") off the shelf for good?",
                            isPresented: Binding(get: { shelf.confirmDeleteID != nil }, set: { if !$0 { shelf.confirmDeleteID = nil } })) {
            Button("Remove Bottle", role: .destructive) {
                if let id = shelf.confirmDeleteID { shelf.delete(id) }
            }
        } message: {
            Text("Its ratings go too. To keep its verdict, mark it finished instead.")
        }
        .overlay(alignment: .topLeading) {
            if labels.remaining > 0 {
                Label("Finding real labels… \(labels.remaining) to go", systemImage: "camera.viewfinder")
                    .font(Look.current.label(10.5))
                    .tracking(0.6)
                    .foregroundStyle(Look.current.ink.opacity(0.85))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(.black.opacity(0.28)))
                    .padding(.leading, 84).padding(.top, 10)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            shelf.seedIfNeeded()
            labels.findMissing()
        }
        .lampDropFiles { urls in
            AddBottle.dropped = urls
            shelf.showAdd = true
        }
        .sheet(isPresented: $shelf.showAdd) { AddBottleView().environmentObject(shelf) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { shelf.showAdd = true } label: { Label("Add Bottle", systemImage: "plus") }
                    .help("Photograph or scan a new bottle")
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .preferredColorScheme(Look.current.scheme)
        .tint(Look.current.accent)
        .frame(minWidth: 760, minHeight: 600)
    }

    /// A bottle standing on the shelf, with its line on the shelf's edge right under it.
    private func column(_ bottle: some View, height: CGFloat, @ViewBuilder rail: () -> some View) -> some View {
        VStack(spacing: 0) {
            bottle
            Color.clear.frame(height: Studio.top - Studio.sink)
            rail().frame(height: Studio.front)
        }
        .frame(width: Studio.columnWidth)
    }

    /// The shelf's name, big and white on the wall, with a line of what's on it.
    private var titleHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(Look.current.display.text(Look.current.title))
                .font(Look.current.display(Look.current.titleSize))
                .tracking(Look.current.display.tracking)
                .foregroundStyle(Look.current.ink)
                .shadow(color: .black.opacity(0.35 * Look.current.contrast), radius: 14, x: 8, y: 10)
            Text(summary)
                .font(Look.current.label(10.5))
                .tracking(Look.current.label.tracking)
                .foregroundStyle(Look.current.ink.opacity(0.72))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.leading, Studio.margin)
        .padding(.top, 78)
        .padding(.bottom, 18)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    private var summary: String {
        var parts = ["\(shelf.active.count) on the shelf"]
        if !shelf.retired.isEmpty { parts.append("\(shelf.retired.count) \(Look.current.finished.lowercased())") }
        if let line = Look.current.mostLine, let most = shelf.active.max(by: { $0.heat < $1.heat }) {
            parts.append("\(line): \(most.name)")
        }
        return Look.current.label.text(parts.joined(separator: "  ·  "))
    }

    private var emptyShelf: some View {
        VStack(alignment: .leading, spacing: 0) {
            ShelfRow(title: "Start here", height: 160) {
                ForEach(["fruity", "fermented", "smoky"], id: \.self) { f in
                    column(GhostBottle(line: "something \(f)?", height: 160), height: 160) { RailText(gap: "something \(f)?") }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(Look.current.display.text(Look.current.emptyTitle))
                    .font(Look.current.display(26))
                    .foregroundStyle(Look.current.ink)
                Text(Look.current.emptyLine)
                    .font(.system(size: 13))
                    .foregroundStyle(Look.current.ink.opacity(0.8))
                Button { shelf.showAdd = true } label: { Label("Add a Bottle", systemImage: "camera") }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(.white)
                    .foregroundStyle(Look.current.wall)
                    .padding(.top, 6)
            }
            .padding(.leading, Studio.margin)
            .padding(.top, 30)
        }
    }
}

/// Measurements of the set, shared so everything lines up at any width.
enum Studio {
    /// How deep the shelf's top looks, how tall its front edge is, and how far into the top a bottle stands.
    static let top: CGFloat = 16
    static let front: CGFloat = 26
    static let sink: CGFloat = 8
    static let margin: CGFloat = 56
    static let columnWidth: CGFloat = 104
    static let spacing: CGFloat = 14

    static func perPlank(width: CGFloat) -> Int {
        let usable = width - margin * 2 + 28
        return max(2, Int((usable + spacing) / (columnWidth + spacing)))
    }
}

/// The wall: one flat colour with a fine grain like painted board. The light is laid over the whole picture
/// afterwards (`StudioLighting`), so the wall, the shelves and the bottles are lit by the same light.
struct StudioWall: View {
    var body: some View {
        ZStack {
            Look.current.wall
            StudioGrain().opacity(Look.current.grain)
        }
        .ignoresSafeArea()
        .accessibilityHidden(true)
    }
}

/// A fine grain of light and dark specks, the same every time.
struct StudioGrain: View {
    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            var seed: UInt64 = 11
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            for _ in 0..<Int(size.width * size.height / 140) {
                let rect = CGRect(x: next() * size.width, y: next() * size.height, width: 1, height: 1)
                context.fill(Path(rect), with: .color(next() > 0.5 ? .white.opacity(0.035) : .black.opacity(0.06)))
            }
        }
    }
}

/// The one light, over everything on the set: dodged bright where it falls, with a beam coming down from it, and
/// burned dark where it doesn't reach. It stays put while the shelves scroll under it, as a studio light would.
struct StudioLighting: View {
    var body: some View {
        GeometryReader { geo in
            let size = geo.size
            let reach = max(size.width, size.height) * Look.current.reach
            let k = Look.current.lightStrength
            ZStack {
                // Burn: the far side of the room falls into shadow.
                RadialGradient(stops: [.init(color: .white, location: 0),
                                       .init(color: .white, location: 0.3),
                                       .init(color: Color(white: 1 - 0.3 * k), location: 0.7),
                                       .init(color: Color(white: 1 - 0.5 * k), location: 1)],
                               center: Look.current.light, startRadius: 0, endRadius: reach * 1.6)
                    .blendMode(.colorBurn)
                // Dodge: a hot spot under the light, in the light's colour...
                RadialGradient(stops: [.init(color: Look.current.glow(0.36 * k), location: 0),
                                       .init(color: Look.current.glow(0.1 * k), location: 0.4),
                                       .init(color: .black, location: 1)],
                               center: Look.current.light, startRadius: 0, endRadius: reach)
                    .blendMode(.colorDodge)
                // ...and the beam it throws down across the wall, when it throws one.
                if Look.current.beam > 0 {
                    LinearGradient(stops: [.init(color: .black, location: 0),
                                           .init(color: Look.current.glow(0.36 * k * Look.current.beam), location: 0.5),
                                           .init(color: .black, location: 1)],
                                   startPoint: .leading, endPoint: .trailing)
                        .frame(width: size.width * 0.34, height: reach * 2.4)
                        .rotationEffect(.degrees(-36))
                        .offset(x: -size.width * 0.14, y: -size.height * 0.08)
                        .blur(radius: 18)
                        .blendMode(.colorDodge)
                }
            }
            .frame(width: size.width, height: size.height)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

/// One shelf running the width of the wall, its bottles standing on it and its name on its front edge.
struct ShelfRow<Content: View>: View {
    var title: String?
    var height: CGFloat = 160
    var dim = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let title { name(title) }
            StudioShelf()
                .padding(.top, top + height - Studio.sink)
                .opacity(dim ? 0.7 : 1)
            HStack(alignment: .top, spacing: Studio.spacing) { content }
                .padding(.leading, Studio.margin - 14)
                .padding(.top, top)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 4)
    }
}

extension ShelfRow {
    /// Room over the bottles: a caption needs a line of its own.
    private var top: CGFloat {
        if case .caption = Look.current.shelfNames, title != nil { return 40 }
        return 14
    }

    /// The shelf's name: painted big on the wall behind it, standing on the shelf with the bottles in front, or a
    /// small caption over its left end.
    @ViewBuilder private func name(_ title: String) -> some View {
        let look = Look.current
        switch look.shelfNames {
        case .painted(let size, let color, let opacity):
            Text(look.display.text(title))
                .font(look.display(size))
                .tracking(look.display.tracking - 0.5)
                .lineLimit(1)
                .minimumScaleFactor(0.4)
                .foregroundStyle(color.opacity(dim ? opacity * 0.6 : opacity))
                .frame(height: top + height - Studio.sink + 6, alignment: .bottomLeading)
                .padding(.leading, Studio.margin - 4)
                .padding(.trailing, Studio.margin)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        case .caption:
            Text(look.label.text(title))
                .font(look.label(11))
                .tracking(look.label.tracking)
                .lineLimit(1)
                .foregroundStyle(look.ink.opacity(dim ? 0.45 : 0.75))
                .padding(.leading, Studio.margin)
                .padding(.top, 12)
                .allowsHitTesting(false)
                .accessibilityAddTraits(.isHeader)
        }
    }
}

/// The shelf: a top lit from above that darkens towards the wall, a bright edge where the light catches it, a
/// front in shade, and its shadow on the wall underneath.
struct StudioShelf: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [Look.current.shelfBack, Look.current.shelfTop], startPoint: .top, endPoint: .bottom)
                .frame(height: Studio.top)
            Rectangle().fill(.white.opacity(0.28 * Look.current.contrast)).frame(height: 1)
            LinearGradient(colors: [Look.current.shelfFront, Look.current.shelfUnder],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: Studio.front - 1)
            LinearGradient(colors: [.black.opacity(0.36 * Look.current.contrast), .black.opacity(0.08 * Look.current.contrast), .clear],
                           startPoint: .top, endPoint: .bottom)
                .frame(height: 60)
        }
        .accessibilityHidden(true)
    }
}

/// What's on the shelf's edge under a bottle: its heat and stars, a finished bottle's verdict, or a gap's line.
struct RailText: View {
    var heat: Int? = nil
    var stars: Int? = nil
    var verdict: String? = nil
    var gap: String? = nil

    var body: some View {
        Group {
            if let heat {
                HStack(spacing: 10) {
                    HStack(spacing: 3) { Image(systemName: Look.current.measureSymbol).foregroundStyle(Look.current.accent); Text("\(heat)") }
                    if let stars { HStack(spacing: 3) { Image(systemName: "star.fill").foregroundStyle(Look.current.ink.opacity(0.7)); Text("\(stars)") } }
                }
                .font(Look.current.label(10.5, weight: .bold))
                .foregroundStyle(Look.current.ink.opacity(0.92))
            } else {
                Text(Look.current.label.text(verdict?.isEmpty == false ? verdict! : gap ?? Look.current.finished))
                    .font(Look.current.label(8.5))
                    .tracking(0.8)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .foregroundStyle(Look.current.ink.opacity(gap == nil ? 0.6 : 0.5))
                    .padding(.horizontal, 2)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
