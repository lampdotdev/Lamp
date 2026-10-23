import SwiftUI
import simd

/// The big map (M): north up, drag to look around, zoom, click anywhere to drive there, or search for a place.
struct MapSheet: View {
    @ObservedObject var nav: NavModel
    @State private var center: SIMD2<Float> = .zero
    @State private var scale: Float = 0.9          // points per metre
    @State private var dragStart: SIMD2<Float>?
    @State private var pinchStart: Float?
    @State private var query = ""
    @FocusState private var searching: Bool
    /// An address found by Apple's geocoder, for one the loaded map doesn't know.
    @State private var looked: Place?

    private func results() -> [Place] {
        let local = nav.search(query)
        if local.contains(where: { $0.detail == "Address" }) { return local }
        return (looked.map { [$0] } ?? []) + local
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                TextField("Search for a place, street or address", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .focused($searching)
                    .frame(maxWidth: 360)
                    .onSubmit { if let first = results().first { go(first) } }
                    .task(id: query) {
                        looked = nil
                        guard query.contains(where: \.isNumber), !nav.search(query).contains(where: { $0.detail == "Address" }) else { return }
                        try? await Task.sleep(for: .milliseconds(450))
                        guard !Task.isCancelled else { return }
                        looked = await nav.lookUp(query)
                    }
                Spacer()
                if let name = nav.destinationName {
                    Text("To \(name)").font(.callout.weight(.semibold)).lineLimit(1)
                    if !nav.remainingText.isEmpty { Text(nav.remainingText).font(.callout).foregroundStyle(.secondary) }
                    Button("Clear Route") { nav.clear() }
                }
                Button("Travel…") {
                    nav.mapOpen = false
                    Task { @MainActor in try? await Task.sleep(for: .milliseconds(350)); nav.travelOpen = true }
                }
                .help("Go somewhere else in the world")
                Button("Done") { nav.mapOpen = false }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.borderedProminent)
            }
            .padding(12)
            ZStack(alignment: .topLeading) {
                map
                if searching || !query.isEmpty {
                    let found = results()
                    if !found.isEmpty {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(found) { p in
                                Button { go(p) } label: {
                                    VStack(alignment: .leading, spacing: 1) {
                                        Text(p.name).font(.body.weight(.medium))
                                        Text(p.detail).font(.caption).foregroundStyle(.secondary)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                Divider()
                            }
                        }
                        .frame(width: 360)
                        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
                        .padding(.leading, 12).padding(.top, 4)
                    }
                }
                VStack(spacing: 6) {
                    Button { zoom(1.5) } label: { Image(systemName: "plus").frame(width: 18, height: 18) }
                        .help("Zoom In").keyboardShortcut("=", modifiers: .command)
                    Button { zoom(1 / 1.5) } label: { Image(systemName: "minus").frame(width: 18, height: 18) }
                        .help("Zoom Out").keyboardShortcut("-", modifiers: .command)
                    Button { center = nav.playerPos } label: { Image(systemName: "location.fill").frame(width: 18, height: 18) }
                        .help("Show Where You Are")
                }
                .padding(12)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
                Text((nav.loadingMap ? "Loading more of the map…  ·  " : "") + "Click the map to set a destination  ·  © OpenStreetMap contributors")
                    .font(.caption).foregroundStyle(.white.opacity(0.8))
                    .padding(8)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
            }
        }
        .frame(minWidth: 820, idealWidth: 1000, minHeight: 600, idealHeight: 720)
        .onAppear { center = nav.destination.map { ($0 + nav.playerPos) / 2 } ?? nav.playerPos }
    }

    private func zoom(_ k: Float) { scale = max(0.12, min(6, scale * k)) }

    /// Zooms keeping the map under `q` (a point in the map) where it is.
    private func zoom(_ k: Float, at q: CGPoint, _ size: CGSize) {
        let anchor = world(q, size)
        scale = max(0.12, min(6, scale * k))
        center = anchor - SIMD2(Float(q.x - size.width / 2), Float(size.height / 2 - q.y)) / scale
    }

    private func go(_ p: Place) {
        nav.setDestination(p.pos, name: p.name)
        query = ""
        searching = false
        center = (p.pos + nav.playerPos) / 2
        fit(p.pos)
    }

    /// Zooms out enough to show both you and the destination.
    private func fit(_ p: SIMD2<Float>) {
        let span = max(abs(p.x - nav.playerPos.x), abs(p.y - nav.playerPos.y))
        scale = max(0.12, min(1.5, 280 / max(span, 1)))
    }

    private var map: some View {
        GeometryReader { geo in
            let size = geo.size
            let version = nav.mapVersion
            Canvas { ctx, size in _ = version; draw(ctx, size) }
                .onAppear { look(size) }
                .onChange(of: center) { look(size) }
                .onChange(of: scale) { look(size) }
                .onChange(of: size) { look(size) }
                .onDisappear { nav.onLook?(nil) }
                .background(Color(red: 0.16, green: 0.19, blue: 0.2))
                // Two fingers on the trackpad move the map; a mouse wheel, or ⌘ with two fingers, zooms where the pointer is.
                .background(ScrollWatcher { dx, dy, precise, command, at in
                    if precise && !command {
                        center += SIMD2(Float(-dx), Float(dy)) / scale
                    } else {
                        zoom(Float(exp(dy * (precise ? 0.01 : 0.1))), at: at, size)
                    }
                })
                .gesture(
                    DragGesture(minimumDistance: 4)
                        .onChanged { v in
                            let start = dragStart ?? center
                            if dragStart == nil { dragStart = center }
                            center = start + SIMD2(Float(-v.translation.width), Float(v.translation.height)) / scale
                        }
                        .onEnded { _ in dragStart = nil }
                )
                .simultaneousGesture(
                    MagnifyGesture()
                        .onChanged { v in
                            // Pinching zooms about the point between the fingers, which stays put.
                            let q = CGPoint(x: v.startAnchor.x * size.width, y: v.startAnchor.y * size.height)
                            let s = pinchStart ?? scale
                            if pinchStart == nil { pinchStart = scale }
                            let anchor = world(q, size)
                            scale = max(0.12, min(6, s * Float(v.magnification)))
                            center = anchor - SIMD2(Float(q.x - size.width / 2), Float(size.height / 2 - q.y)) / scale
                        }
                        .onEnded { _ in pinchStart = nil }
                )
                .onTapGesture(coordinateSpace: .local) { loc in
                    searching = false
                    nav.setDestination(world(loc, size))
                }
        }
        .clipped()
    }

    /// Tells the game what's in view, so it loads that part of the map.
    private func look(_ size: CGSize) {
        let half = SIMD2(Float(size.width), Float(size.height)) / (2 * scale)
        nav.onLook?((center - half, center + half))
    }

    private func world(_ q: CGPoint, _ size: CGSize) -> SIMD2<Float> {
        center + SIMD2(Float(q.x - size.width / 2), Float(size.height / 2 - q.y)) / scale
    }

    private func draw(_ ctx: GraphicsContext, _ size: CGSize) {
        guard let city = nav.city else { return }
        let half = SIMD2(Float(size.width), Float(size.height)) / (2 * scale)
        let lo = center - half - 80, hi = center + half + 80
        func inView(_ p: SIMD2<Float>, pad: Float = 0) -> Bool {
            p.x > lo.x - pad && p.x < hi.x + pad && p.y > lo.y - pad && p.y < hi.y + pad
        }
        func map(_ q: SIMD2<Float>) -> CGPoint {
            CGPoint(x: size.width / 2 + CGFloat((q.x - center.x) * scale), y: size.height / 2 - CGFloat((q.y - center.y) * scale))
        }
        for a in city.areas where a.kind != "parking" && a.kind != "paved" {
            guard let first = a.tris.first, inView(first, pad: 220) else { continue }
            ctx.fill(Minimap.triangles(a.tris, map), with: .color(Minimap.colour(a.kind)))
        }
        for w in city.waterLines {
            guard let first = w.pts.first, inView(first, pad: 220) else { continue }
            var path = Path(); path.addLines(w.pts.map(map))
            ctx.stroke(path, with: .color(Minimap.colour("water")), style: StrokeStyle(lineWidth: CGFloat(max(1.5, w.width * scale)), lineCap: .round, lineJoin: .round))
        }
        if scale > 0.3 {
            for b in city.buildingPolys {
                guard let first = b.first, inView(first) else { continue }
                var path = Path(); path.addLines(b.map(map)); path.closeSubpath()
                ctx.fill(path, with: .color(Color(white: 0.34)))
            }
        }
        for e in city.edges {
            guard inView(e.pts[0], pad: e.length) else { continue }
            if e.isService && scale < 0.5 { continue }
            var path = Path(); path.addLines(e.pts.map(map))
            let w = CGFloat(max(e.isService ? 1 : 1.6, e.width * scale))
            ctx.stroke(path, with: .color(e.isService ? Color(white: 0.6) : Color(white: 0.88)),
                       style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
        }
        // Street names, a few, on the longest stretches in view.
        if scale > 0.45 {
            var labels: [String: (SIMD2<Float>, SIMD2<Float>, Float)] = [:]
            for e in city.edges where !e.name.isEmpty && !e.isService && e.length > 40 {
                let (mid, dir) = e.sample(e.length / 2)
                guard inView(mid, pad: -60) else { continue }
                if let have = labels[e.name], have.2 >= e.length { continue }
                labels[e.name] = (mid, dir, e.length)
            }
            var placed: [CGPoint] = []
            for (name, l) in labels.sorted(by: { $0.value.2 > $1.value.2 }).prefix(40) {
                let q = map(l.0)
                if placed.contains(where: { hypot($0.x - q.x, $0.y - q.y) < 70 }) { continue }
                placed.append(q)
                var ang = atan2(-Double(l.1.y), Double(l.1.x))
                if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
                var layer = ctx
                layer.translateBy(x: q.x, y: q.y)
                layer.rotate(by: .radians(ang))
                layer.draw(Text(signName(name).uppercased()).font(.system(size: 10, weight: .heavy)).foregroundColor(Color(white: 0.12)), at: .zero)
            }
        }
        // The route.
        if let route = nav.route, route.pts.count > 1 {
            var path = Path(); path.addLines(route.pts.map(map))
            ctx.stroke(path, with: .color(.black.opacity(0.5)), style: StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round))
            ctx.stroke(path, with: .color(Self.routeColor), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
        }
        if let d = nav.destination { Self.drawPin(ctx, at: map(d)) }
        // You.
        let c = map(nav.playerPos)
        var layer = ctx
        layer.translateBy(x: c.x, y: c.y)
        layer.rotate(by: .radians(Double(nav.playerHeading)))
        layer.fill(Self.arrow, with: .color(Color(red: 1, green: 0.8, blue: 0.02)))
        layer.stroke(Self.arrow, with: .color(.black), lineWidth: 1.2)
    }

    static let routeColor = Color(red: 0.75, green: 0.3, blue: 1)

    static var arrow: Path {
        var a = Path()
        a.move(to: CGPoint(x: 0, y: -10))
        a.addLine(to: CGPoint(x: 7, y: 8))
        a.addLine(to: CGPoint(x: 0, y: 4))
        a.addLine(to: CGPoint(x: -7, y: 8))
        a.closeSubpath()
        return a
    }

    /// A pin standing on the destination.
    static func drawPin(_ ctx: GraphicsContext, at q: CGPoint) {
        var stem = Path()
        stem.move(to: q)
        stem.addLine(to: CGPoint(x: q.x, y: q.y - 14))
        ctx.stroke(stem, with: .color(.black), lineWidth: 2)
        let head = Path(ellipseIn: CGRect(x: q.x - 7, y: q.y - 26, width: 14, height: 14))
        ctx.fill(head, with: .color(routeColor))
        ctx.stroke(head, with: .color(.white), lineWidth: 2)
    }
}

/// Scroll-wheel and trackpad scrolling over a view (SwiftUI has no modifier for it on the Mac): the deltas, whether
/// they're a trackpad's precise ones, whether ⌘ is held, and where the pointer is in the view (from its top left).
struct ScrollWatcher: NSViewRepresentable {
    let onScroll: (CGFloat, CGFloat, Bool, Bool, CGPoint) -> Void

    final class Watcher: NSView {
        var onScroll: ((CGFloat, CGFloat, Bool, Bool, CGPoint) -> Void)?
        private var monitor: Any?
        override var isFlipped: Bool { true }
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            if let monitor { NSEvent.removeMonitor(monitor); self.monitor = nil }
            guard window != nil else { return }
            monitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
                guard let self, let window = self.window, event.window === window else { return event }
                let p = self.convert(event.locationInWindow, from: nil)
                guard self.bounds.contains(p) else { return event }
                self.onScroll?(event.scrollingDeltaX, event.scrollingDeltaY, event.hasPreciseScrollingDeltas,
                               event.modifierFlags.contains(.command), p)
                return nil
            }
        }
        deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
    }

    func makeNSView(context: Context) -> Watcher {
        let v = Watcher()
        v.onScroll = onScroll
        return v
    }

    func updateNSView(_ v: Watcher, context: Context) { v.onScroll = onScroll }
}
