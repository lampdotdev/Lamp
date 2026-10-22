import SwiftUI
import simd

/// The heads-up display: rotating minimap, area and street, speed and boost.
struct HUDView: View {
    @ObservedObject var model: HUDModel
    @ObservedObject var nav: NavModel
    @State private var showHelp = true

    var body: some View {
        ZStack {
            if model.loaded {
                VStack(alignment: .leading, spacing: 0) {
                    if showHelp { controls.transition(.opacity) }
                    Spacer()
                    HStack(alignment: .bottom) {
                        VStack(alignment: .leading, spacing: 6) {
                            Minimap(model: model, nav: nav).frame(width: 230, height: 230)
                            Text("© OpenStreetMap contributors · terrain: Mapzen, USGS")
                                .font(.system(size: 9)).foregroundStyle(.white.opacity(0.7)).shadow(radius: 2)
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(model.area)
                                .font(.system(size: 30, weight: .heavy, design: .default).italic())
                                .foregroundStyle(.white)
                            Text(model.street)
                                .font(.system(size: 17, weight: .semibold))
                                .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.02))
                            speedometer.padding(.top, 10)
                        }
                        .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                        .animation(.easeOut(duration: 0.25), value: model.street)
                    }
                }
                .padding(20)
                .allowsHitTesting(false)
                .overlay(alignment: .top) {
                    if let d = model.debug {
                        Text(d)
                            .font(.system(size: 11, design: .monospaced))
                            .foregroundStyle(.white)
                            .padding(8)
                            .background(.black.opacity(0.6), in: RoundedRectangle(cornerRadius: 6))
                            .padding(.top, 20)
                            .allowsHitTesting(false)
                    }
                }
                .overlay(alignment: .topTrailing) {
                    if let b = model.business {
                        BusinessCard(info: b)
                            .padding(20)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                            .id(b.name)
                    }
                }
                .animation(.spring(duration: 0.35), value: model.business)
                .overlay(alignment: .top) {
                    if let text = nav.instruction {
                        directions(text).padding(.top, 20).transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(.spring(duration: 0.35), value: nav.instruction)
                .overlay(alignment: .bottomLeading) {
                    // Clicking the minimap opens the big one.
                    Color.clear
                        .frame(width: 230, height: 230)
                        .contentShape(Circle())
                        .onTapGesture { nav.mapOpen = true }
                        .help("Open the map to set a destination (M)")
                        .padding(.leading, 20).padding(.bottom, 37)
                }
                .overlay(alignment: .bottom) {
                    if let toast = model.toast {
                        Text(toast)
                            .font(.system(size: 34, weight: .heavy).italic())
                            .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.02))
                            .shadow(color: .black.opacity(0.8), radius: 3, x: 0, y: 1)
                            .padding(.bottom, 100)
                            .transition(.opacity.combined(with: .scale(scale: 0.9)))
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.3), value: model.toast)
                .overlay(alignment: .bottom) {
                    if let prompt = model.prompt {
                        Text(prompt)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14).padding(.vertical, 8)
                            .background(.black.opacity(0.6), in: Capsule())
                            .padding(.bottom, 40)
                            .transition(.opacity)
                            .allowsHitTesting(false)
                    }
                }
                .animation(.easeOut(duration: 0.2), value: model.prompt)
                .task {
                    try? await Task.sleep(for: .seconds(14))
                    withAnimation(.easeOut(duration: 1)) { showHelp = false }
                }
                Color.red.opacity(Double(model.crash) * 0.18).allowsHitTesting(false).ignoresSafeArea()
            } else {
                loading
            }
        }
        .sheet(isPresented: $nav.mapOpen) { MapSheet(nav: nav) }
        .sheet(isPresented: $nav.travelOpen) { TravelSheet(nav: nav) }
    }

    /// The next turn: which way, how far, onto where.
    private func directions(_ text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: nav.instructionSymbol)
                .font(.system(size: 30, weight: .bold))
                .frame(width: 40)
            VStack(alignment: .leading, spacing: 1) {
                Text(nav.distanceText)
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(text).font(.system(size: 14, weight: .semibold)).lineLimit(1)
            }
            if !nav.remainingText.isEmpty {
                Divider().frame(height: 34).overlay(.white.opacity(0.4))
                VStack(alignment: .leading, spacing: 1) {
                    Text(nav.remainingText).font(.system(size: 15, weight: .bold, design: .rounded)).monospacedDigit()
                    Text("to go").font(.system(size: 11, weight: .semibold)).opacity(0.75)
                }
            }
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 16).padding(.vertical, 10)
        .background(MapSheet.routeColor.opacity(0.85), in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.4), radius: 6)
        .allowsHitTesting(false)
    }

    private var speedometer: some View {
        VStack(alignment: .trailing, spacing: 4) {
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text("\(Int(model.speed.rounded()))")
                    .font(.system(size: 56, weight: .heavy, design: .rounded))
                    .monospacedDigit()
                    .contentTransition(.numericText())
                Text(CityConfig.current.style.speedUnit).font(.system(size: 15, weight: .bold, design: .rounded)).opacity(0.85)
            }
            .foregroundStyle(.white)
            ZStack(alignment: .leading) {
                Capsule().fill(.black.opacity(0.45))
                Capsule().fill(model.boosting ? Color.orange : Color(red: 0.25, green: 0.65, blue: 1))
                    .frame(width: max(4, 150 * CGFloat(model.boost)))
            }
            .frame(width: 150, height: 7)
            if model.damage > 0.02 {
                ZStack(alignment: .leading) {
                    Capsule().fill(.black.opacity(0.45))
                    Capsule().fill(model.damage >= 1 ? Color(white: 0.3) : Color(red: 0.95, green: 0.25, blue: 0.2))
                        .frame(width: max(4, 150 * CGFloat(min(1, model.damage))))
                }
                .frame(width: 150, height: 7)
                .help("Damage")
            }
        }
    }

    private var controls: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("W A S D or arrows to drive")
            Text("Space handbrake  ·  Shift boost  ·  R back on the road  ·  F get out / in / ride  ·  Space jump on foot  ·  M map and directions  ·  T travel anywhere")
        }
        .font(.system(size: 12, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(.black.opacity(0.45), in: RoundedRectangle(cornerRadius: 8))
    }

    private var loading: some View {
        ZStack {
            LinearGradient(colors: [Color(red: 0, green: 0.15, blue: 0.3), .black], startPoint: .top, endPoint: .bottom)
            VStack(spacing: 14) {
                Text(CityConfig.current.name.uppercased())
                    .font(.system(size: 54, weight: .black).italic())
                    .foregroundStyle(Color(red: 1, green: 0.8, blue: 0.02))
                if model.failed {
                    Text(model.noStreets
                         ? "There are no streets to drive around \(CityConfig.current.name). Pick somewhere else."
                         : "The map of \(CityConfig.current.name) couldn't be downloaded. Check the internet connection and reopen, or go somewhere else.")
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                    Button("Travel Somewhere Else…") { nav.travelOpen = true }
                        .controlSize(.large)
                        .padding(.top, 6)
                } else {
                    ProgressView().controlSize(.large).tint(.white)
                    Text(model.status).foregroundStyle(.white.opacity(0.8))
                }
            }
        }
        .ignoresSafeArea()
    }
}

/// A round map that turns with the car, with street names along the streets.
struct Minimap: View {
    /// Ground colours on the maps: water, woods, everything green.
    static func colour(_ kind: String) -> Color {
        switch kind {
        case "water": Color(red: 0.24, green: 0.42, blue: 0.6)
        case "wood": Color(red: 0.15, green: 0.3, blue: 0.15)
        case "golf:fairway", "golf:green", "golf:tee": Color(red: 0.3, green: 0.5, blue: 0.24)
        case "golf:bunker": Color(red: 0.7, green: 0.64, blue: 0.48)
        default: Color(red: 0.2, green: 0.36, blue: 0.2)
        }
    }

    /// Triangles (three points each) as one path.
    static func triangles(_ tris: [SIMD2<Float>], _ map: (SIMD2<Float>) -> CGPoint) -> Path {
        var path = Path()
        for i in stride(from: 0, to: tris.count - 2, by: 3) {
            path.move(to: map(tris[i])); path.addLine(to: map(tris[i + 1])); path.addLine(to: map(tris[i + 2])); path.closeSubpath()
        }
        return path
    }

    @ObservedObject var model: HUDModel
    let nav: NavModel
    let range: Float = 230      // metres from the middle to the rim

    var body: some View {
        Canvas { ctx, size in
            guard let city = model.city else { return }
            let r = Float(min(size.width, size.height) / 2)
            let k = r / range
            let c = CGPoint(x: CGFloat(r), y: CGFloat(r))
            let p = model.pos, h = model.heading
            let f = forwardOf(h), rt = perpRight(f)
            func map(_ q: SIMD2<Float>) -> CGPoint {
                let rel = q - p
                return CGPoint(x: c.x + CGFloat(simd_dot(rel, rt) * k), y: c.y - CGFloat(simd_dot(rel, f) * k))
            }
            let reach = range * 1.45
            let circle = Path(ellipseIn: CGRect(origin: .zero, size: size))
            ctx.fill(circle, with: .color(Color(red: 0.16, green: 0.19, blue: 0.2).opacity(0.88)))
            ctx.clip(to: circle)

            for a in city.areas where a.kind != "parking" && a.kind != "paved" {
                guard let first = a.tris.first, simd_distance(first, p) < reach + 220 else { continue }
                ctx.fill(Minimap.triangles(a.tris, map), with: .color(Minimap.colour(a.kind)))
            }
            for w in city.waterLines {
                guard let first = w.pts.first, simd_distance(first, p) < reach + 220 else { continue }
                var path = Path()
                path.addLines(w.pts.map(map))
                ctx.stroke(path, with: .color(Minimap.colour("water")), style: StrokeStyle(lineWidth: CGFloat(max(1.5, w.width * k)), lineCap: .round, lineJoin: .round))
            }
            for b in city.buildingPolys {
                guard let first = b.first, simd_distance(first, p) < reach else { continue }
                var path = Path()
                path.addLines(b.map(map))
                path.closeSubpath()
                ctx.fill(path, with: .color(Color(white: 0.34)))
            }
            for e in city.edges {
                guard simd_distance(e.pts[0], p) < reach + e.length else { continue }
                var path = Path()
                path.addLines(e.pts.map(map))
                let w = CGFloat(max(e.isService ? 1.5 : 2.5, e.width * k * 1.3))
                ctx.stroke(path, with: .color(e.isService ? Color(white: 0.6) : Color(white: 0.88)),
                           style: StrokeStyle(lineWidth: w, lineCap: .round, lineJoin: .round))
            }
            // Railways: a dark line with ties, trains as orange bars.
            for line in model.rails {
                var path = Path()
                path.addLines(line.map(map))
                ctx.stroke(path, with: .color(Color(white: 0.15)), lineWidth: 2.5)
                ctx.stroke(path, with: .color(Color(white: 0.55)), style: StrokeStyle(lineWidth: 4.5, dash: [1.2, 3]))
            }
            for t in model.trains where simd_distance(t, p) < reach {
                let q = map(t)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 4, y: q.y - 4, width: 8, height: 8)), with: .color(.orange))
            }
            for t in model.traffic where simd_distance(t, p) < reach {
                let q = map(t)
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 2.5, y: q.y - 2.5, width: 5, height: 5)), with: .color(Color(red: 0.4, green: 0.7, blue: 1)))
            }

            // The route to follow, and the destination (on the rim when it's further off).
            if let route = nav.route, route.pts.count > 1 {
                var path = Path()
                path.addLines(route.pts.map(map))
                ctx.stroke(path, with: .color(.black.opacity(0.45)), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                ctx.stroke(path, with: .color(MapSheet.routeColor), style: StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round))
            }

            // One label per street: on the stretch nearest the car.
            var labels: [String: (SIMD2<Float>, SIMD2<Float>, Float)] = [:]
            for e in city.edges where !e.name.isEmpty && !e.isService && e.length > 30 {
                let (mid, dir) = e.sample(e.length / 2)
                let d = simd_distance(mid, p)
                guard d < range * 0.85 else { continue }
                if let have = labels[e.name], have.2 <= d { continue }
                labels[e.name] = (mid, dir, d)
            }
            var placed: [CGPoint] = []
            for (name, l) in labels.sorted(by: { $0.value.2 < $1.value.2 }).prefix(12) {
                let q = map(l.0)
                if placed.contains(where: { hypot($0.x - q.x, $0.y - q.y) < 45 }) { continue }
                placed.append(q)
                let ahead = map(l.0 + l.1)
                var ang = atan2(Double(ahead.y - q.y), Double(ahead.x - q.x))
                if ang > .pi / 2 { ang -= .pi } else if ang < -.pi / 2 { ang += .pi }
                var layer = ctx
                layer.translateBy(x: q.x, y: q.y)
                layer.rotate(by: .radians(ang))
                let text = Text(signName(name).uppercased())
                    .font(.system(size: 8.5, weight: .heavy))
                    .foregroundColor(Color(white: 0.12))
                layer.draw(text, at: .zero)
            }

            // Businesses nearby, as coloured icons.
            let near = model.businesses.filter { simd_distance($0.pos, p) < range * 0.95 }
                .sorted { simd_distance($0.pos, p) < simd_distance($1.pos, p) }.prefix(28)
            var drawn: [CGPoint] = [c]
            var shown: [(BusinessMarker, CGPoint)] = []
            for m in near {
                let q = map(m.pos)
                if drawn.contains(where: { hypot($0.x - q.x, $0.y - q.y) < 15 }) { continue }
                drawn.append(q)
                shown.append((m, q))
            }
            for (m, q) in shown.reversed() {
                ctx.fill(Path(ellipseIn: CGRect(x: q.x - 7.5, y: q.y - 7.5, width: 15, height: 15)), with: .color(m.color))
                ctx.stroke(Path(ellipseIn: CGRect(x: q.x - 7.5, y: q.y - 7.5, width: 15, height: 15)), with: .color(.white), lineWidth: 1.2)
                var icon = ctx.resolve(Image(systemName: m.symbol))
                icon.shading = .color(.white)
                ctx.draw(icon, in: CGRect(x: q.x - 4.5, y: q.y - 4.5, width: 9, height: 9))
            }

            if let d = nav.destination {
                let rel = d - p
                let local = SIMD2<Float>(simd_dot(rel, rt), simd_dot(rel, f))
                let len = simd_length(local) * k
                if len < r - 14 {
                    MapSheet.drawPin(ctx, at: map(d))
                } else {
                    let dir = simd_normalize(local)
                    let q = CGPoint(x: c.x + CGFloat(dir.x * (r - 10)), y: c.y - CGFloat(dir.y * (r - 10)))
                    let dot = Path(ellipseIn: CGRect(x: q.x - 7, y: q.y - 7, width: 14, height: 14))
                    ctx.fill(dot, with: .color(MapSheet.routeColor))
                    ctx.stroke(dot, with: .color(.white), lineWidth: 2)
                }
            }

            // North on the rim.
            let north = SIMD2<Float>(simd_dot([0, 1], rt), -simd_dot([0, 1], f))
            let np = CGPoint(x: c.x + CGFloat(north.x * (r - 12)), y: c.y + CGFloat(north.y * (r - 12)))
            ctx.fill(Path(ellipseIn: CGRect(x: np.x - 8, y: np.y - 8, width: 16, height: 16)), with: .color(.black.opacity(0.7)))
            ctx.draw(Text("N").font(.system(size: 10, weight: .heavy)).foregroundColor(.white), at: np)

            // The player.
            var arrow = Path()
            arrow.move(to: CGPoint(x: c.x, y: c.y - 9))
            arrow.addLine(to: CGPoint(x: c.x + 6.5, y: c.y + 7))
            arrow.addLine(to: CGPoint(x: c.x, y: c.y + 3.5))
            arrow.addLine(to: CGPoint(x: c.x - 6.5, y: c.y + 7))
            arrow.closeSubpath()
            ctx.fill(arrow, with: .color(Color(red: 1, green: 0.8, blue: 0.02)))
            ctx.stroke(arrow, with: .color(.black), lineWidth: 1.2)
        }
        .overlay(Circle().stroke(.black.opacity(0.7), lineWidth: 3))
        .overlay(Circle().inset(by: 3).stroke(.white.opacity(0.25), lineWidth: 1))
        .shadow(color: .black.opacity(0.5), radius: 6)
    }
}
