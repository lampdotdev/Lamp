import SwiftUI
import simd
import CoreLocation

/// One instruction along a route: where it happens (metres along the route), what to do, and which way.
struct RouteStep {
    enum Turn { case straight, slightLeft, left, sharpLeft, slightRight, right, sharpRight, uTurn, arrive }
    let at: Float
    let turn: Turn
    let text: String

    var symbol: String {
        switch turn {
        case .straight: "arrow.up"
        case .slightLeft: "arrow.up.left"
        case .left, .sharpLeft: "arrow.turn.up.left"
        case .slightRight: "arrow.up.right"
        case .right, .sharpRight: "arrow.turn.up.right"
        case .uTurn: "arrow.uturn.down"
        case .arrive: "flag.checkered"
        }
    }
}

/// A way through the streets: the line to follow and the turns along it.
struct Route {
    var pts: [SIMD2<Float>] = []
    var cum: [Float] = []
    var steps: [RouteStep] = []
    var length: Float { cum.last ?? 0 }
}

/// Finds the shortest drive along the street graph, keeping to one-way streets, and words the turns.
enum Router {
    static func route(_ city: City, from p: SIMD2<Float>, heading: Float, to dest: SIMD2<Float>, name: String) -> Route? {
        guard let start = city.nearestRoad(p, within: 120), let end = city.nearestRoad(dest, within: 250) else { return nil }
        let se = city.edges[start.edge], de = city.edges[end.edge]
        let s0 = project(p, se), s1 = project(dest, de)
        let facing = forwardOf(heading)

        // Straight along the same street.
        if start.edge == end.edge && (s1 >= s0 || !se.oneway) {
            let pts = piece(se, s0, s1)
            return finish(pts, legs: [], city: city, name: name)
        }

        // A* over the crossings. Starting: forward to the edge's end, or back to its start where two-way (a U-turn
        // costs extra if that's behind the car).
        let n = city.nodes.count
        var g = [Float](repeating: .infinity, count: n)
        var came = [(node: Int, edge: Int)](repeating: (-1, -1), count: n)
        var heap = Heap()
        func h(_ i: Int) -> Float { simd_distance(city.nodes[i].pos, dest) }
        func seed(_ node: Int, _ cost: Float) {
            guard node < n, cost < g[node] else { return }
            g[node] = cost; came[node] = (-1, start.edge)
            heap.push(cost + h(node), node)
        }
        let along = se.sample(s0).1
        let ahead = simd_dot(along, facing) >= 0
        seed(se.b, (se.length - s0) + (ahead ? 0 : 40))
        if !se.oneway { seed(se.a, s0 + (ahead ? 40 : 0)) }

        func goalCost(_ node: Int) -> Float? {
            if node == de.a { return s1 }
            if node == de.b && !de.oneway { return de.length - s1 }
            return nil
        }
        var best: (cost: Float, node: Int) = (.infinity, -1)
        var closed = Set<Int>()
        while let (f, u) = heap.pop() {
            if f >= best.cost { break }
            if closed.contains(u) { continue }
            closed.insert(u)
            if let gc = goalCost(u), g[u] + gc < best.cost { best = (g[u] + gc, u) }
            for ei in city.nodes[u].edges where ei < city.edges.count {
                let e = city.edges[ei]
                let v: Int
                if e.a == u { v = e.b } else if e.b == u && !e.oneway { v = e.a } else { continue }
                guard v < n else { continue }
                let cost = g[u] + e.length * weight(e)
                if cost < g[v] {
                    g[v] = cost
                    came[v] = (u, ei)
                    heap.push(cost + h(v), v)
                }
            }
        }
        guard best.node >= 0 else { return nil }

        // Back from the goal to the start: the edges taken, in order.
        var legs: [(edge: Int, from: Int, to: Int)] = []
        var node = best.node
        while came[node].node >= 0 {
            let c = came[node]
            legs.append((c.edge, c.node, node))
            node = c.node
        }
        legs.reverse()
        let firstNode = node

        var pts = piece(se, s0, firstNode == se.b ? se.length : 0)
        var junctions: [(at: Int, inEdge: Int, inNode: Int, outEdge: Int)] = []
        var prevEdge = start.edge
        for leg in legs {
            junctions.append((pts.count - 1, prevEdge, leg.from, leg.edge))
            let e = city.edges[leg.edge]
            pts += (leg.from == e.a ? e.pts : e.pts.reversed()).dropFirst()
            prevEdge = leg.edge
        }
        junctions.append((pts.count - 1, prevEdge, best.node, end.edge))
        pts += piece(de, best.node == de.a ? 0 : de.length, s1).dropFirst()
        return finish(pts, legs: junctions, city: city, name: name)
    }

    /// Slightly prefers big streets; avoids alleys.
    private static func weight(_ e: RoadEdge) -> Float {
        if e.isService { return 2 }
        switch e.rank { case 5: return 0.85; case 4: return 0.9; case 3: return 0.95; default: return 1 }
    }

    private static func finish(_ raw: [SIMD2<Float>], legs: [(at: Int, inEdge: Int, inNode: Int, outEdge: Int)],
                               city: City, name: String) -> Route {
        var route = Route()
        for p in raw where route.pts.last.map({ simd_distance($0, p) > 0.05 }) ?? true { route.pts.append(p) }
        var total: Float = 0
        route.cum = [0]
        for i in 1..<max(1, route.pts.count) {
            total += simd_distance(route.pts[i - 1], route.pts[i])
            route.cum.append(total)
        }
        if route.pts.count < 2 { route.pts = raw.isEmpty ? [] : [raw[0], raw[0]]; route.cum = [0, 0] }

        // A turn wherever the street changes or the road bends sharply at a crossing.
        var current = legs.first.map { city.edges[$0.inEdge].name } ?? ""
        for j in legs {
            let ein = city.edges[j.inEdge], eout = city.edges[j.outEdge]
            guard j.inNode < city.nodes.count, j.at < raw.count else { continue }
            let inDir = -ein.outward(from: j.inNode)
            let outDir = eout.outward(from: j.inNode)
            let angle = atan2(inDir.x * outDir.y - inDir.y * outDir.x, simd_dot(inDir, outDir))   // + left
            let deg = abs(angle) * 180 / .pi
            let renamed = eout.name != current && !eout.name.isEmpty
            let crossing = city.nodes[j.inNode].edges.count >= 3
            guard (renamed && deg > 0) || (deg > 40 && crossing) || deg > 70 else {
                if !eout.name.isEmpty { current = eout.name }
                continue
            }
            let turn: RouteStep.Turn
            switch deg {
            case ..<25: turn = .straight
            case ..<55: turn = angle > 0 ? .slightLeft : .slightRight
            case ..<135: turn = angle > 0 ? .left : .right
            case ..<165: turn = angle > 0 ? .sharpLeft : .sharpRight
            default: turn = .uTurn
            }
            let onto = eout.name.isEmpty ? (eout.isService ? "the alley" : "the road") : eout.name
            let verb: String
            switch turn {
            case .straight: verb = "Continue onto"
            case .slightLeft: verb = "Bear left onto"
            case .slightRight: verb = "Bear right onto"
            case .left: verb = "Turn left onto"
            case .right: verb = "Turn right onto"
            case .sharpLeft: verb = "Turn sharp left onto"
            case .sharpRight: verb = "Turn sharp right onto"
            case .uTurn: verb = "Make a U-turn onto"
            case .arrive: verb = ""
            }
            // Where along the route this crossing is.
            let at = distanceAlong(raw[j.at], route)
            route.steps.append(RouteStep(at: at, turn: turn, text: "\(verb) \(onto)"))
            if !eout.name.isEmpty { current = eout.name }
        }
        route.steps.append(RouteStep(at: route.length, turn: .arrive, text: "Arrive at \(name)"))
        return route
    }

    private static func distanceAlong(_ p: SIMD2<Float>, _ r: Route) -> Float {
        var best: (Float, Float) = (.infinity, 0)
        for i in 0..<(r.pts.count - 1) {
            let q = closestOnSegment(p, r.pts[i], r.pts[i + 1])
            let d = simd_distance(p, q)
            if d < best.0 { best = (d, r.cum[i] + simd_distance(r.pts[i], q)) }
        }
        return best.1
    }

    /// How far along an edge a point lies.
    static func project(_ p: SIMD2<Float>, _ e: RoadEdge) -> Float {
        var best: (Float, Float) = (.infinity, 0)
        for i in 0..<(e.pts.count - 1) {
            let q = closestOnSegment(p, e.pts[i], e.pts[i + 1])
            let d = simd_distance(p, q)
            if d < best.0 { best = (d, e.cum[i] + simd_distance(e.pts[i], q)) }
        }
        return best.1
    }

    /// The stretch of an edge between two distances along it, in the order given.
    static func piece(_ e: RoadEdge, _ a: Float, _ b: Float) -> [SIMD2<Float>] {
        var out = [e.sample(a).0]
        if a <= b {
            for i in e.cum.indices where e.cum[i] > a && e.cum[i] < b { out.append(e.pts[i]) }
        } else {
            for i in e.cum.indices.reversed() where e.cum[i] < a && e.cum[i] > b { out.append(e.pts[i]) }
        }
        out.append(e.sample(b).0)
        return out
    }

    /// A small binary heap of (priority, node), lowest first.
    struct Heap {
        private var items: [(Float, Int)] = []
        mutating func push(_ f: Float, _ v: Int) {
            items.append((f, v))
            var i = items.count - 1
            while i > 0 {
                let parent = (i - 1) / 2
                if items[parent].0 <= items[i].0 { break }
                items.swapAt(parent, i); i = parent
            }
        }
        mutating func pop() -> (Float, Int)? {
            guard let top = items.first else { return nil }
            let last = items.removeLast()
            if !items.isEmpty {
                items[0] = last
                var i = 0
                while true {
                    let l = 2 * i + 1, r = l + 1
                    var m = i
                    if l < items.count && items[l].0 < items[m].0 { m = l }
                    if r < items.count && items[r].0 < items[m].0 { m = r }
                    if m == i { break }
                    items.swapAt(i, m); i = m
                }
            }
            return top
        }
    }
}

/// A place to search for on the big map.
struct Place: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let pos: SIMD2<Float>
}

/// Directions: where you're going, the route there, and the next turn, for the HUD and the big map.
@MainActor
final class NavModel: ObservableObject {
    @Published var mapOpen = false
    /// The travel sheet (T, or Travel on the big map): go anywhere in the world.
    @Published var travelOpen = false
    /// Set by the game: builds it afresh at the place chosen.
    var onTravel: ((TravelPlace) -> Void)?
    @Published var destinationName: String?
    @Published var destination: SIMD2<Float>?
    @Published var instruction: String?
    @Published var instructionSymbol = "arrow.up"
    @Published var distanceText = ""
    @Published var remainingText = ""
    @Published private(set) var route: Route?
    var city: City?
    var places: [Place] = []
    /// Where the player is, kept up to date by the game, for routing from.
    var playerPos: SIMD2<Float> = .zero
    var playerHeading: Float = 0
    /// Set when you get there, for the game to show.
    var arrived = false
    private var lastIndex = 0
    private var offSince: Date?
    private var lastReroute = Date.distantPast

    /// Bumped as more of the map arrives, so the big map draws it.
    @Published var mapVersion = 0
    /// Whether the big map's area is still loading.
    @Published var loadingMap = false
    /// Told what the big map shows (nil when it closes), so that area can be loaded.
    var onLook: (((lo: SIMD2<Float>, hi: SIMD2<Float>)?) -> Void)?

    /// Told about each new trip, so the streets on the way can be loaded.
    var onTrip: ((SIMD2<Float>) -> Void)?

    func setDestination(_ p: SIMD2<Float>, name: String? = nil) {
        let label = name ?? describe(p)
        destination = p
        destinationName = label
        onTrip?(p)
        reroute()
    }

    /// Works the route out again from where the player is (also as more of the map loads).
    func reroute() {
        guard let city, let p = destination else { return }
        lastIndex = 0
        route = Router.route(city, from: playerPos, heading: playerHeading, to: p, name: destinationName ?? "your destination")
        refresh()
    }

    /// Finds an address anywhere in the city with Apple's geocoder, for one the loaded map doesn't know yet.
    func lookUp(_ text: String) async -> Place? {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 4 else { return nil }
        let city = CityConfig.current
        let full = q.localizedCaseInsensitiveContains(city.name) ? q : "\(q), \(city.name), \(city.region)"
        guard let mark = try? await CLGeocoder().geocodeAddressString(full).first, let loc = mark.location else { return nil }
        let p = MapGeo.local(lat: loc.coordinate.latitude, lon: loc.coordinate.longitude)
        guard simd_length(p) < 15000 else { return nil }
        let street = [mark.subThoroughfare, mark.thoroughfare].compactMap { $0 }.joined(separator: " ")
        return Place(name: street.isEmpty ? (mark.name ?? q) : street, detail: "Address", pos: p)
    }

    func clear() {
        destination = nil
        destinationName = nil
        route = nil
        instruction = nil
    }

    /// A dropped pin's name: the house number and street, or the street.
    func describe(_ p: SIMD2<Float>) -> String {
        guard let city, let road = city.nearestRoad(p, within: 120) else { return "Dropped pin" }
        let name = city.edges[road.edge].name
        if name.isEmpty { return "Dropped pin" }
        if let n = city.houseNumber(near: p, on: name, within: 40) { return "\(n) \(name)" }
        return name
    }

    /// Follows the player along the route: next turn, distances, rerouting when off it, arriving.
    func track(_ p: SIMD2<Float>, heading: Float) {
        playerPos = p
        playerHeading = heading
        guard let route, let dest = destination, route.pts.count >= 2 else { return }
        if simd_distance(p, dest) < 18 {
            arrived = true
            clear()
            return
        }
        // Nearest point on the route, looking near where we were last.
        let lo = max(0, lastIndex - 3), hi = min(route.pts.count - 1, lastIndex + 60)
        var best: (d: Float, along: Float, i: Int) = (.infinity, 0, lastIndex)
        for i in lo..<hi {
            let q = closestOnSegment(p, route.pts[i], route.pts[i + 1])
            let d = simd_distance(p, q)
            if d < best.d { best = (d, route.cum[i] + simd_distance(route.pts[i], q), i) }
        }
        lastIndex = best.i
        if best.d > 28 {
            if offSince == nil { offSince = Date() }
            if let since = offSince, Date().timeIntervalSince(since) > 1.2, Date().timeIntervalSince(lastReroute) > 2 {
                lastReroute = Date()
                offSince = nil
                _ = dest
                reroute()
                return
            }
        } else {
            offSince = nil
        }
        refresh(along: best.along)
    }

    private func refresh(along: Float = 0) {
        guard let route else {
            instruction = destination == nil ? nil : "Loading the streets on the way…"
            distanceText = ""
            remainingText = ""
            return
        }
        let next = route.steps.first { $0.at > along + 3 } ?? route.steps.last
        let text = next?.text ?? ""
        if instruction != text { instruction = text }
        let sym = next?.symbol ?? "arrow.up"
        if instructionSymbol != sym { instructionSymbol = sym }
        let d = Self.distance(max(0, (next?.at ?? route.length) - along))
        if distanceText != d { distanceText = d }
        let r = Self.distance(max(0, route.length - along))
        if remainingText != r { remainingText = r }
    }

    /// Feet when close, miles further off.
    static func distance(_ m: Float) -> String {
        if !CityConfig.current.style.imperial {
            if m < 1000 { return "\(max(10, Int((m / 10).rounded()) * 10)) m" }
            return String(format: "%.1f km", m / 1000)
        }
        let feet = m * 3.281
        if feet < 1000 { return "\(max(50, Int((feet / 50).rounded()) * 50)) ft" }
        return String(format: "%.1f mi", m / 1609.34)
    }

    /// Places matching a search: businesses by name or kind, and streets.
    func search(_ text: String) -> [Place] {
        let q = text.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { return [] }
        let found = addresses(q)
        if !found.isEmpty { return found }
        var out = places.filter { $0.name.localizedCaseInsensitiveContains(q) }
        out.sort { a, b in
            let pa = a.name.lowercased().hasPrefix(q.lowercased()), pb = b.name.lowercased().hasPrefix(q.lowercased())
            if pa != pb { return pa }
            return simd_distance(a.pos, playerPos) < simd_distance(b.pos, playerPos)
        }
        if out.count < 8 {
            out += places.filter { !$0.name.localizedCaseInsensitiveContains(q) && $0.detail.localizedCaseInsensitiveContains(q) }
                .sorted { simd_distance($0.pos, playerPos) < simd_distance($1.pos, playerPos) }
        }
        return Array(out.prefix(8))
    }

    /// An address typed as "221 Baker": that building, or failing that the nearest number on that street.
    private func addresses(_ q: String) -> [Place] {
        guard let city else { return [] }
        let words = q.split(separator: " ", maxSplits: 1).map(String.init)
        guard words.count == 2, let wanted = Int(words[0].filter(\.isNumber)), words[0].first?.isNumber == true else { return [] }
        let rest = words[1].lowercased().replacingOccurrences(of: ",", with: "")
        // Streets the rest of the text names.
        let streets = Set(places.filter { $0.detail == "Street" }.map(\.name).filter { name in
            let full = name.lowercased(), short = signName(name).lowercased()
            return full.hasPrefix(rest) || short.hasPrefix(rest) || rest.hasPrefix(full) || rest.hasPrefix(short)
                || full.split(separator: " ").first.map { rest.hasPrefix($0.lowercased()) && $0.count >= 3 } == true
        })
        guard !streets.isEmpty else { return [] }
        var exact: [Place] = [], near: [(Int, Place)] = []
        for i in city.addresses.indices {
            let digits = Int(city.addresses[i].number.prefix { $0.isNumber }) ?? -1
            guard digits >= 0, abs(digits - wanted) < 400 else { continue }
            if city.addresses[i].street == nil { city.addresses[i].street = .some(city.streetName(near: city.addresses[i].pos)) }
            guard let street = city.addresses[i].street ?? nil, streets.contains(street) else { continue }
            let place = Place(name: "\(city.addresses[i].number) \(street)", detail: "Address", pos: city.addresses[i].pos)
            if digits == wanted { exact.append(place) } else { near.append((abs(digits - wanted), place)) }
        }
        if !exact.isEmpty { return Array(exact.prefix(8)) }
        return near.sorted { $0.0 < $1.0 }.prefix(3).map { Place(name: $0.1.name, detail: "Nearest number found", pos: $0.1.pos) }
    }

    /// Streets, once each, at the middle of their longest stretch.
    static func streets(_ city: City) -> [Place] {
        var best: [String: RoadEdge] = [:]
        for e in city.edges where !e.name.isEmpty && !e.isService {
            if let have = best[e.name], have.length >= e.length { continue }
            best[e.name] = e
        }
        return best.map { Place(name: $0.key, detail: "Street", pos: $0.value.sample($0.value.length / 2).0) }
    }
}
