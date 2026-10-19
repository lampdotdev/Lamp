import SwiftUI

/// The whole app: a wooden pantry cabinet at night. The wall, the lamp, the planks and their lights are all one
/// thing that scrolls and resizes together; only the window's own edges stay put.
struct ShelfView: View {
    @EnvironmentObject var shelf: Shelf
    @ObservedObject private var labels = LabelFinder.shared
    @ObservedObject private var artist = Illustrator.shared

    private struct Plank: Identifiable {
        var id: String
        var title: String?
        var bottles: [Bottle]
        var gap: Gap?
        var retired = false
        var dim = false
    }

    /// Families in order, each wrapped onto as many planks as the window's width needs; retired bottles last.
    private func planks(perPlank: Int) -> [Plank] {
        var result: [Plank] = []
        let groups = Dictionary(grouping: shelf.active, by: \.flavor)
        for family in FlavorFamily.allCases {
            let bottles = (groups[family] ?? []).sorted { $0.heat < $1.heat }
            let gap = shelf.taste.gaps.first { $0.family == family.rawValue }
            guard !bottles.isEmpty || gap != nil else { continue }
            // The ghost takes a spot on the family's last plank.
            let slots = bottles.count + (gap == nil ? 0 : 1)
            let count = max(1, Int((Double(slots) / Double(perPlank)).rounded(.up)))
            for i in 0..<count {
                let chunk = Array(bottles.dropFirst(i * perPlank).prefix(perPlank))
                result.append(Plank(id: "\(family.rawValue)-\(i)", title: i == 0 ? family.title : nil, bottles: chunk,
                                    gap: i == count - 1 ? gap : nil, dim: bottles.isEmpty))
            }
        }
        let retired = shelf.retired
        // Retired bottles are shorter but just as wide, so they fit as many to a plank as the others.
        for i in stride(from: 0, to: retired.count, by: perPlank) {
            result.append(Plank(id: "retired-\(i)", title: i == 0 ? "retired" : nil,
                                bottles: Array(retired.dropFirst(i).prefix(perPlank)), retired: true))
        }
        return result
    }

    var body: some View {
        GeometryReader { geo in
            let perPlank = Cabinet.perPlank(width: geo.size.width)
            ScrollView(.vertical) {
                VStack(spacing: 0) {
                    titleHeader
                    if shelf.bottles.isEmpty {
                        emptyShelf
                    } else {
                        ForEach(planks(perPlank: perPlank)) { plank in
                            PlankBay(title: plank.title, height: plank.retired ? 100 : 150, dim: plank.dim) {
                                ForEach(plank.bottles) { b in
                                    column(BottleView(bottle: b, height: plank.retired ? 100 : 150),
                                           tag: plank.retired ? (b.verdict?.isEmpty == false ? b.verdict! : "retired") : nil,
                                           seed: b.id, faded: plank.retired, peppers: plank.retired ? nil : b.intensity, stars: b.score)
                                }
                                if let gap = plank.gap {
                                    column(GhostBottle(gap: gap), tag: gap.line, seed: gap.id, ghost: true)
                                }
                            }
                        }
                    }
                    Color.clear.frame(height: shelf.pick != nil ? 250 : 140)
                }
                .frame(width: geo.size.width)
                .background(ZineWall())
            }
            .scrollContentBackground(.hidden)
            .background(Zine.pink)
        }
        .overlay(alignment: .bottom) { TonightBar() }
        .overlay {
            if let id = shelf.openID {
                ZStack {
                    Zine.navy.opacity(0.35)
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
            Text("Its tag and ratings go too. To keep its verdict, retire it instead.")
        }
        .overlay(alignment: .topLeading) {
            if labels.remaining > 0 || artist.remaining > 0 {
                Label(labels.remaining > 0 ? "Finding real labels… \(labels.remaining) to go" : "Drawing labels… \(artist.remaining) to go",
                      systemImage: labels.remaining > 0 ? "camera.viewfinder" : "paintbrush.pointed")
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .foregroundStyle(Zine.navy)
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(Capsule().fill(Zine.cream))
                    .overlay(Capsule().strokeBorder(Zine.navy, lineWidth: 1.2))
                    .padding(.leading, 84).padding(.top, 8)
                    .transition(.opacity)
            }
        }
        .ignoresSafeArea(edges: .top)
        .onAppear {
            shelf.seedIfNeeded()
            labels.findMissing()
            artist.illustrateMissing()
        }
        .lampDropFiles { urls in
            AddBottle.dropped = urls
            shelf.showAdd = true
        }
        .sheet(isPresented: $shelf.showAdd) { AddBottleView().environmentObject(shelf) }
        .sheet(isPresented: $shelf.showMap) { TasteMapView().environmentObject(shelf) }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button { shelf.showMap = true } label: { Label("Taste Map", systemImage: "map") }
                    .help("Your taste map and the gaps on your shelf")
                Button { shelf.showAdd = true } label: { Label("Add Bottle", systemImage: "plus") }
                    .help("Photograph or scan a new bottle")
            }
        }
        .toolbarBackground(.hidden, for: .windowToolbar)
        .navigationTitle("")
        .preferredColorScheme(.light)
        .tint(Zine.red)
        .frame(minWidth: 760, minHeight: 600)
    }

    private func column(_ bottle: some View, tag: String?, seed: String, faded: Bool = false, ghost: Bool = false,
                        peppers: Int? = nil, stars: Int? = nil) -> some View {
        VStack(spacing: 0) {
            bottle
            Color.clear.frame(height: Cabinet.plankHeight)
            HangingTag(text: tag, seed: seed, faded: faded, ghost: ghost, peppers: peppers, stars: stars)
        }
        .frame(width: Cabinet.columnWidth)
    }

    /// The shelf's name, lettered on the wall like the top of a print.
    private var titleHeader: some View {
        HStack(spacing: 10) {
            chili(rotation: -30)
            Text("the hot shelf")
                .font(Hand.font(40))
                .foregroundStyle(Zine.red)
                .shadow(color: Zine.navy.opacity(0.9), radius: 0, x: 2, y: 2)
            chili(rotation: 150)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 130)
        .padding(.top, 14)
        .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private func chili(rotation: Double) -> some View {
        if let image = LampAssets.image("chili.png") {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit).frame(width: 34)
                .rotationEffect(.degrees(rotation))
                .accessibilityHidden(true)
        }
    }

    private var emptyShelf: some View {
        VStack(spacing: 0) {
            PlankBay(title: "start here") {
                ForEach(["fruity", "fermented", "smoky"], id: \.self) { f in
                    column(GhostBottle(gap: Gap(family: f, line: f)), tag: "something \(f)?", seed: f, ghost: true)
                }
            }
            VStack(spacing: 10) {
                Text("An empty shelf. Tragic.")
                    .font(Hand.font(26))
                    .foregroundStyle(Zine.red)
                Text("Snap a bottle or drop a photo here, and I'll read the label and find it a spot.")
                    .foregroundStyle(Zine.navy)
                Button { shelf.showAdd = true } label: { Label("Add a Bottle", systemImage: "camera") }
                    .controlSize(.large)
                    .buttonStyle(.borderedProminent)
                    .tint(Zine.red)
                    .padding(.top, 6)
            }
            .padding(.top, 40)
        }
    }
}

/// Measurements of the cabinet, shared so everything lines up at any width.
enum Cabinet {
    static let plankHeight: CGFloat = 26
    static let stileWidth: CGFloat = 26
    static let gutter: CGFloat = 150
    static let columnWidth: CGFloat = 100
    static let spacing: CGFloat = 14

    static func perPlank(width: CGFloat) -> Int {
        let usable = width - stileWidth * 2 - gutter - 30
        return max(2, Int((usable + spacing) / (columnWidth + spacing)))
    }
}

/// The wall: flat pink with a soft crayon grain and chili peppers tumbling across it, drawn at fixed sizes so
/// resizing shows more wall instead of stretching it, and scrolling moves it with the shelves.
struct ZineWall: View {
    private static let chili = LampAssets.image("chili.png")

    var body: some View {
        Canvas(rendersAsynchronously: true) { context, size in
            context.fill(Path(CGRect(origin: .zero, size: size)), with: .color(Zine.pink))
            // Crayon grain: short soft strokes, the same every time.
            var seed: UInt64 = 7
            func next() -> Double {
                seed = seed &* 6364136223846793005 &+ 1442695040888963407
                return Double(seed >> 33) / Double(UInt64(1) << 31)
            }
            let strokes = Int(size.width * size.height / 900)
            for _ in 0..<strokes {
                let x = next() * size.width, y = next() * size.height
                let len = 4 + next() * 9, angle = next() * .pi
                var p = Path()
                p.move(to: CGPoint(x: x, y: y))
                p.addLine(to: CGPoint(x: x + cos(angle) * len, y: y + sin(angle) * len))
                let light = next() > 0.5
                context.stroke(p, with: .color(light ? .white.opacity(0.12) : Zine.pinkShadow.opacity(0.18)), lineWidth: 1.2)
            }
            // Chilies scattered on a loose grid, mostly in the open wall to the right.
            guard let chili = Self.chili else { return }
            let image = context.resolve(Image(nsImage: chili))
            let cell: CGFloat = 230
            let tints: [Double] = [0, 18, -14, 26]
            var row = 0
            var y: CGFloat = 170
            while y < size.height {
                var x: CGFloat = Cabinet.stileWidth + Cabinet.gutter + CGFloat(row % 2) * cell / 2
                while x < size.width - 40 {
                    let jx = (next() - 0.5) * cell * 0.6, jy = (next() - 0.5) * cell * 0.5
                    if next() < 0.38 {
                        var c = context
                        c.translateBy(x: x + jx, y: y + jy)
                        c.rotate(by: .degrees(next() * 360))
                        c.addFilter(.hueRotation(.degrees(tints[Int(next() * 4) % 4])))
                        c.opacity = 0.9
                        let w: CGFloat = 34 + next() * 22
                        c.draw(image, in: CGRect(x: -w / 2, y: -w / 2, width: w, height: w * 0.96))
                    }
                    x += cell
                }
                y += cell * 0.8
                row += 1
            }
        }
    }
}

/// One plank with bottles standing on it, tags hanging off its front edge, and a warm strip light underneath
/// that lights the plank below.
struct PlankBay<Content: View>: View {
    var title: String?
    var height: CGFloat = 150
    var dim = false
    @ViewBuilder var content: Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            plank
                .padding(.top, 30 + height)
                .padding(.horizontal, Cabinet.stileWidth)
            HStack(alignment: .top, spacing: Cabinet.spacing) { content }
                .padding(.leading, Cabinet.stileWidth + Cabinet.gutter)
                .padding(.top, 30)
            if let title {
                Text(title)
                    .font(Hand.font(14))
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Zine.cream.opacity(dim ? 0.6 : 1))
                    .frame(width: Cabinet.gutter - 24, alignment: .trailing)
                    .padding(.leading, Cabinet.stileWidth + 8)
                    .padding(.top, 30 + height + 9)
                    .allowsHitTesting(false)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 26)
    }

    /// A chunky flat plank with a navy pencil edge, a white highlight streak and a flat shadow on the wall.
    private var plank: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Zine.woodDark)
            RoundedRectangle(cornerRadius: 4)
                .fill(Zine.wood)
                .frame(height: 9)
            Capsule().fill(.white.opacity(0.55))
                .frame(width: 120, height: 2.5)
                .offset(x: 40, y: 3)
            Capsule().fill(.white.opacity(0.35))
                .frame(width: 40, height: 2)
                .offset(x: 175, y: 3.5)
        }
        .frame(height: Cabinet.plankHeight)
        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(Zine.navy, lineWidth: 1.6))
        .background(
            RoundedRectangle(cornerRadius: 4).fill(Zine.pinkShadow.opacity(0.8)).offset(x: 4, y: 7)
        )
        .opacity(dim ? 0.55 : 1)
    }
}
