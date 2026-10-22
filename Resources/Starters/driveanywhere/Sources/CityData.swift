import Foundation
import simd

// The city as read from OpenStreetMap: the downtown built the first time a city is opened (cached), and the
// tiles streamed in round it. Positions are metres on a flat map: x east, y north, from the city's centre
// (CityConfig). In 3D, north is -z.

struct CityFile: Codable {
    let bounds: [Float]
    let nodes: [[Double]]         // x, y, signal, radius, map node id
    let edges: [EdgeData]
    let buildings: [BuildingData]
    let grass: [AreaData]
    let lots: [AreaData]
    let paths: [PathData]
    let shops: [ShopData]
    let parked: [[Float]]         // x, y, heading
    let trees: [[Float]]          // x, y, scale
    let rails: [RailData]?
    let xings: [XingData]?
    var hoods: [PlaceData]? = nil
    var furn: [[Float]]? = nil    // street furniture: kind, x, y, heading (see Furniture.Kind)
    var wires: [[Float]]? = nil   // overhead wires between utility poles: x1, y1, x2, y2
    var fuel: [FuelData]? = nil
}

/// A gas station's canopy: centre, long axis, half length and width, and the brand on it.
struct FuelData: Codable { let x: Float; let y: Float; let ax: Float; let ay: Float; let hl: Float; let hw: Float; let n: String }

/// A neighbourhood or suburb's name where OpenStreetMap puts it (s: 1 for a suburb, which reaches further).
/// Or a named area (a campus, a park, a district): `pg` its outline, flattened x, y pairs.
struct PlaceData: Codable { let n: String; let x: Float; let y: Float; var s: Int? = nil; var pg: [Float]? = nil }

/// A railway line: its name, kind (0 freight, 1 intercity, 2 regional passenger trains), the train's name, its points.
struct RailData: Codable { let n: String; let m: Int; let p: [Float]; var tn: String? = nil }
/// A level crossing: where, which line and how far along it, the road edge, the track's and road's directions.
struct XingData: Codable { let x: Float; let y: Float; let r: Int; let s: Float; let e: Int; let dx: Float; let dy: Float; let rx: Float; let ry: Float }

struct EdgeData: Codable {
    let a: Int, b: Int
    let p: [Float]
    let n: String, t: String
    let w: Float, dw: Float
    let l: Int, o: Int
    let pk: [Int]
    var sw: [Int]? = nil          // sidewalks left, right (both when absent)
    var st: [Int]? = nil          // stop signs at a, at b
}

struct BuildingData: Codable {
    let p: [Float]
    var h: Float                  // top of the walls
    let t: [Int]
    let g: [Float]?               // pitched roof frame: centre x, y, long axis x, y, half length, half width, roof height
    var c: Int
    var r: Int
    let n: String?
    var mh: Float? = nil          // walls start this high (a part held up over others, a skybridge)
    var rs: String? = nil         // roof shape: gabled, hipped, pyramidal, dome (flat when absent)
    var rh: Float? = nil          // roof height
    var x: Int? = nil             // 1: an outline drawn by its parts, kept only to drive into
    var pt: Int? = nil            // 1: a building:part
    var hn: String? = nil         // house number
    var ho: [[Float]]? = nil      // courtyards: inner rings (clockwise); `t` covers the outer ring then each of these
    var wc: [Float]? = nil        // wall colour as tagged (building:colour), 0–1 RGB
    var rc: [Float]? = nil        // roof colour as tagged (roof:colour)
    var sf: Int? = nil            // 1: shop windows on the ground floor (a retail or commercial building, or a shop inside)
    var gk: Int? = nil            // 1: a garage (garage doors, no windows); 2: a row of garages
    var wp: Int? = nil            // windows: 1 pairs, 2 a ribbon, 3 narrow and further apart (single when absent)
    var lk: String? = nil         // walls: "plain" (no windows), "stands" (seating from the courtyard up to the rim)
}

/// a: for a parking lot, the direction its rows of spaces run (radians from east), from the whole lot's shape.
/// o: for a pitch, its whole rectangle (centre x, y, long axis x, y, half length, half width), for its markings.
struct AreaData: Codable { let p: [Float]; let t: [Int]; let k: String; var a: Float? = nil; var o: [Float]? = nil }
struct PathData: Codable { let p: [Float]; let w: Float; var k: String? = nil }   // k "water": a river or stream
struct ShopData: Codable {
    let n: String; let x: Float; let y: Float; let dx: Float; let dy: Float; let z: Float
    // Kind, cuisine, address, opening hours, phone, website, outdoor seating.
    let k: String?; let c: String?; let a: String?; let h: String?; let ph: String?; let w: String?; let o: Int?
}

/// A point on the map, `h` metres above the ground there (the land's real height, from Terrain), in 3D.
@inline(__always) func w3(_ p: SIMD2<Float>, _ h: Float) -> SIMD3<Float> { SIMD3(p.x, h + Terrain.shared.height(p), -p.y) }
@inline(__always) func perpRight(_ d: SIMD2<Float>) -> SIMD2<Float> { SIMD2(d.y, -d.x) }
@inline(__always) func cross2(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { a.x * b.y - a.y * b.x }
@inline(__always) func forwardOf(_ heading: Float) -> SIMD2<Float> { SIMD2(sin(heading), cos(heading)) }

func points(_ flat: [Float]) -> [SIMD2<Float>] {
    stride(from: 0, to: flat.count - 1, by: 2).map { SIMD2(flat[$0], flat[$0 + 1]) }
}

enum Heights {
    // The lawn at 0; the road a little above it; the sidewalk a kerb (14 cm) above the road.
    static let ground: Float = 0
    static let grass: Float = 0.02
    static let lot: Float = 0.05
    static let path: Float = 0.06
    static let road: Float = 0.08
    static let marking: Float = 0.13
    static let sidewalk: Float = 0.22
    static let wood: Float = 0.015
    static let water: Float = 0.03
    static let paved: Float = 0.01
    /// Where a car settles in a lake or river: under the water, roof and all.
    static let underwater: Float = -1.9
}

struct RoadNode {
    var pos: SIMD2<Float>
    var signal: Bool
    var radius: Float
    var edges: [Int] = []
    /// An all-way stop (stop=all): everyone stops.
    var allStop = false
}

struct RoadEdge {
    let a: Int, b: Int
    let pts: [SIMD2<Float>]
    let cum: [Float]
    let length: Float
    let name: String
    let type: String
    let width: Float
    let driveWidth: Float
    let lanes: Int
    let oneway: Bool
    let parking: (Bool, Bool)
    /// Sidewalks on the left and right (of the way from `a` to `b`).
    var sidewalks: (Bool, Bool) = (true, true)
    /// Stop signs facing traffic arriving at `a`, and at `b`.
    var stops: (Bool, Bool) = (false, false)

    var isService: Bool { type == "service" }
    var isResidential: Bool { ["residential", "living_street", "unclassified"].contains(type) }
    /// The grass strip between the kerb and the sidewalk: on residential streets only.
    var verge: Float { isResidential ? 1.8 : 0 }
    /// How busy it is, for choosing where traffic drives: a primary road about six times a residential street.
    var trafficWeight: Float {
        switch type {
        case "primary", "trunk": 6
        case "secondary": 4
        case "tertiary": 2.5
        case "residential", "unclassified", "living_street": 1
        default: 0.3
        }
    }
    /// The middle of the sidewalk, from the street's middle line.
    var walkOffset: Float { width / 2 + verge + walkWidth / 2 }
    /// How wide the sidewalk itself is.
    var walkWidth: Float { isService ? 0 : (rank >= 3 ? 2.6 : 2.2) }
    var rank: Int {
        switch type {
        case "primary": 5
        case "secondary": 4
        case "tertiary": 3
        case "residential", "unclassified", "living_street": 2
        default: 1
        }
    }
    var speedLimit: Float {
        switch type {
        case "primary": 14
        case "secondary": 12.5
        case "tertiary": 11.5
        case "service": 5
        default: 10
        }
    }

    /// Where along the edge, from `a`, and the way it runs there.
    func sample(_ s: Float) -> (SIMD2<Float>, SIMD2<Float>) {
        let s = max(0, min(length, s))
        var lo = 0, hi = cum.count - 1
        while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= s { lo = m } else { hi = m } }
        let seg = cum[hi] - cum[lo]
        let u = seg > 0 ? (s - cum[lo]) / seg : 0
        let d = pts[hi] - pts[lo]
        let dir = simd_length(d) > 0 ? simd_normalize(d) : SIMD2(0, 1)
        return (pts[lo] + d * u, dir)
    }

    /// The way out of node `n` along this edge.
    func outward(from n: Int) -> SIMD2<Float> {
        let reach = min(6, length * 0.5)
        let start = n == a ? pts[0] : pts[pts.count - 1]
        let d = sample(n == a ? reach : length - reach).0 - start
        return simd_length(d) > 1e-4 ? simd_normalize(d) : SIMD2(0, 1)
    }
}

struct Wall { let a: SIMD2<Float>; let b: SIMD2<Float> }
/// tree: its size, 0 for anything else; kind: 0 fixed, 1 a street sign, 2 a signal pole (both knocked down by a hard
/// hit), 3 a fire hydrant (knocked off by any knock).
struct Post { let c: SIMD2<Float>; let r: Float; var tree: Float = 0; var kind: UInt8 = 0 }

/// A uniform grid of things for nearby lookups.
struct Grid<T> {
    let cell: Float
    var cells: [Int64: [T]] = [:]
    init(cell: Float) { self.cell = cell }
    func key(_ x: Int, _ y: Int) -> Int64 { Int64(x) << 32 | Int64(UInt32(bitPattern: Int32(y))) }
    func coord(_ v: Float) -> Int { Int(floor(v / cell)) }
    mutating func insert(_ item: T, min lo: SIMD2<Float>, max hi: SIMD2<Float>) {
        for x in coord(lo.x)...coord(hi.x) { for y in coord(lo.y)...coord(hi.y) { cells[key(x, y), default: []].append(item) } }
    }
    func query(_ p: SIMD2<Float>, _ r: Float, _ body: (T) -> Void) {
        for x in coord(p.x - r)...coord(p.x + r) { for y in coord(p.y - r)...coord(p.y + r) { cells[key(x, y)]?.forEach(body) } }
    }
}

final class City {
    let file: CityFile
    var nodes: [RoadNode] = []
    var edges: [RoadEdge] = []
    var walls = Grid<Wall>(cell: 12)
    var posts = Grid<Post>(cell: 12)
    var roadGrid = Grid<(Int, Int)>(cell: 30)      // edge, segment
    var buildingPolys: [[SIMD2<Float>]] = []
    let half: SIMD2<Float>

    var nodeByOSM: [Int64: Int] = [:]
    /// Parks, woods and water for the maps, as triangles (three points each), and rivers and streams as lines.
    var areas: [(kind: String, tris: [SIMD2<Float>])] = []
    var waterLines: [(pts: [SIMD2<Float>], width: Float)] = []

    func addArea(_ a: AreaData) {
        let p = points(a.p)
        var tris: [SIMD2<Float>] = []
        for i in stride(from: 0, to: a.t.count - 2, by: 3) where a.t[i + 2] < p.count { tris += [p[a.t[i]], p[a.t[i + 1]], p[a.t[i + 2]]] }
        if !tris.isEmpty { areas.append((a.k, tris)) }
        if a.k == "water" {
            for i in stride(from: 0, to: tris.count, by: 3) {
                let t = (tris[i], tris[i + 1], tris[i + 2])
                waterGrid.insert(.tri(t.0, t.1, t.2), min: simd_min(t.0, simd_min(t.1, t.2)), max: simd_max(t.0, simd_max(t.1, t.2)))
            }
        }
    }

    func addPath(_ p: PathData) {
        guard p.k == "water" else { return }
        let pts = points(p.p)
        waterLines.append((pts, p.w))
        for i in 0..<max(0, pts.count - 1) {
            let a = pts[i], b = pts[i + 1], r = p.w / 2
            waterGrid.insert(.line(a, b, r), min: simd_min(a, b) - r, max: simd_max(a, b) + r)
        }
    }

    /// Water by where it is: lakes and riverbanks as triangles, streams as lines with their half width.
    enum WaterPiece { case tri(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>), line(SIMD2<Float>, SIMD2<Float>, Float) }
    var waterGrid = Grid<WaterPiece>(cell: 25)

    /// Whether a point is in water (a road or bridge over it doesn't count).
    func inWater(_ p: SIMD2<Float>) -> Bool {
        var wet = false
        waterGrid.query(p, 0.1) { piece in
            guard !wet else { return }
            switch piece {
            case let .tri(a, b, c):
                let d1 = cross2(b - a, p - a), d2 = cross2(c - b, p - b), d3 = cross2(a - c, p - c)
                wet = !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
            case let .line(a, b, r):
                wet = simd_distance(closestOnSegment(p, a, b), p) < r
            }
        }
        return wet
    }

    init(file: CityFile) {
        self.file = file
        half = SIMD2(file.bounds[0], file.bounds[1])
        for n in file.nodes {
            _ = node(Int64(n.count > 4 ? n[4] : -Double(nodes.count) - 1), at: SIMD2(Float(n[0]), Float(n[1])),
                     signal: n[2] == 1, radius: Float(n[3]))
            if n[2] == 2 { nodes[nodes.count - 1].allStop = true }
        }
        for e in file.edges {
            addEdge(a: e.a, b: e.b, pts: points(e.p), name: e.n, type: e.t, width: e.w, driveWidth: e.dw,
                    lanes: e.l, oneway: e.o == 1, parking: (e.pk[0] == 1, e.pk[1] == 1),
                    sidewalks: e.sw.map { ($0[0] == 1, $0[1] == 1) } ?? (true, true),
                    stops: e.st.map { ($0[0] == 1, $0[1] == 1) } ?? (false, false))
        }
        for b in file.buildings where (b.mh ?? 0) < 1.5 { addBuilding(points(b.p), holes: (b.ho ?? []).map(points)) }
        for b in file.buildings { addAddress(b) }
        for g in file.grass { addArea(g) }
        for p in file.paths { addPath(p) }
        for t in file.trees { addPost(SIMD2(t[0], t[1]), 0.35, tree: t.count > 2 ? t[2] : 1) }
        addPlaces(file.hoods ?? [])
    }

    /// The road node for a map node, made the first time it's seen (roads in neighbouring tiles share them).
    func node(_ osm: Int64, at pos: SIMD2<Float>, signal: Bool = false, radius: Float = 0) -> Int {
        if let i = nodeByOSM[osm] {
            if signal { nodes[i].signal = true }
            nodes[i].radius = max(nodes[i].radius, radius)
            return i
        }
        nodes.append(RoadNode(pos: pos, signal: signal, radius: radius))
        nodeByOSM[osm] = nodes.count - 1
        return nodes.count - 1
    }

    @discardableResult
    func addEdge(a: Int, b: Int, pts: [SIMD2<Float>], name: String, type: String, width: Float, driveWidth: Float,
                 lanes: Int, oneway: Bool, parking: (Bool, Bool), sidewalks: (Bool, Bool) = (true, true),
                 stops: (Bool, Bool) = (false, false)) -> Int {
        var cum: [Float] = [0]
        for k in 1..<pts.count { cum.append(cum[k - 1] + simd_distance(pts[k], pts[k - 1])) }
        let i = edges.count
        edges.append(RoadEdge(a: a, b: b, pts: pts, cum: cum, length: cum.last ?? 0, name: name, type: type,
                              width: width, driveWidth: min(driveWidth, width), lanes: lanes, oneway: oneway, parking: parking,
                              sidewalks: sidewalks, stops: stops))
        nodes[a].edges.append(i)
        if b != a { nodes[b].edges.append(i) }
        nodes[a].radius = max(nodes[a].radius, width / 2)
        nodes[b].radius = max(nodes[b].radius, width / 2)
        for k in 0..<(pts.count - 1) {
            roadGrid.insert((i, k), min: simd_min(pts[k], pts[k + 1]), max: simd_max(pts[k], pts[k + 1]))
        }
        return i
    }

    func addBuilding(_ poly: [SIMD2<Float>], holes: [[SIMD2<Float>]] = []) {
        buildingPolys.append(poly)
        for ring in [poly] + holes {
            for k in 0..<ring.count {
                let a = ring[k], c = ring[(k + 1) % ring.count]
                // A wall standing across a street can't be there at street level: the street runs under the
                // building (a bus terminal over a street, an arcade, a passage), so there's no wall to hit.
                if overRoad(a, c) { continue }
                walls.insert(Wall(a: a, b: c), min: simd_min(a, c), max: simd_max(a, c))
            }
        }
    }

    /// Whether a building's wall from `a` to `c` crosses a street's middle line, or stands in the roadway of a
    /// street (not an alley, whose mapping may run along a wall).
    private func overRoad(_ a: SIMD2<Float>, _ c: SIMD2<Float>) -> Bool {
        let mid = (a + c) / 2
        var over = false
        roadGrid.query(mid, simd_distance(a, c) / 2 + 2) { item in
            guard !over, item.0 < self.edges.count else { return }
            let e = self.edges[item.0]
            let p = e.pts[item.1], q = e.pts[item.1 + 1]
            let d1 = cross2(c - a, p - a), d2 = cross2(c - a, q - a), d3 = cross2(q - p, a - p), d4 = cross2(q - p, c - p)
            if d1 * d2 < 0 && d3 * d4 < 0 { over = true; return }
            if !e.isService && distanceToSegment(mid, p, q) < e.width / 2 - 0.5 { over = true }
        }
        return over
    }

    /// Numbered buildings: where they stand, their number, and (worked out when first asked) their street.
    struct Address { let pos: SIMD2<Float>; let number: String; var street: String?? = nil }
    var addresses: [Address] = []
    var addressGrid = Grid<Int>(cell: 30)

    func addAddress(_ b: BuildingData) {
        guard let n = b.hn, !n.isEmpty else { return }
        let poly = points(b.p)
        guard !poly.isEmpty else { return }
        let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
        addresses.append(Address(pos: c, number: n))
        addressGrid.insert(addresses.count - 1, min: c, max: c)
    }

    /// The nearest real street to a point (alleys and parking aisles left out), by name.
    func streetName(near p: SIMD2<Float>, within r: Float = 60) -> String? {
        var best: (String, Float)?
        roadGrid.query(p, r) { item in
            let e = self.edges[item.0]
            guard !e.isService, !e.name.isEmpty else { return }
            let d = distanceToSegment(p, e.pts[item.1], e.pts[item.1 + 1])
            if best == nil || d < best!.1 { best = (e.name, d) }
        }
        return best?.0
    }

    /// The number of the building beside `p` on `street`, if it has one.
    func houseNumber(near p: SIMD2<Float>, on street: String, within r: Float = 35) -> String? {
        var found: [(Int, Float)] = []
        addressGrid.query(p, r) { i in
            let d = simd_distance(self.addresses[i].pos, p)
            if d < r && !found.contains(where: { $0.0 == i }) { found.append((i, d)) }
        }
        for (i, _) in found.sorted(by: { $0.1 < $1.1 }) {
            if addresses[i].street == nil { addresses[i].street = .some(streetName(near: addresses[i].pos)) }
            if addresses[i].street! == street { return addresses[i].number }
        }
        return nil
    }

    /// Whether a point is in the area that ships with the game (the rest streams in).
    func inBundled(_ p: SIMD2<Float>) -> Bool { abs(p.x) <= half.x && abs(p.y) <= half.y }

    private var postSpots = Set<SIMD2<Int32>>()

    /// A pole or trunk to drive into; one per spot, however often the square it stands on is drawn.
    func addPost(_ c: SIMD2<Float>, _ r: Float, tree: Float = 0, kind: UInt8 = 0) {
        guard postSpots.insert(City.spot(c)).inserted else { return }
        posts.insert(Post(c: c, r: r, tree: tree, kind: kind), min: c - r, max: c + r)
    }

    /// Trees, street signs and signal poles knocked down by a hard hit, by spot: no longer in the way, and drawn as stumps.
    var fallen = Set<SIMD2<Int32>>()

    static func spot(_ c: SIMD2<Float>) -> SIMD2<Int32> { SIMD2(Int32((c.x * 10).rounded()), Int32((c.y * 10).rounded())) }

    /// The nearest named road to a point, and how far it is.
    func nearestRoad(_ p: SIMD2<Float>, within r: Float = 40) -> (edge: Int, distance: Float)? {
        var best: (Int, Float)?
        roadGrid.query(p, r) { item in
            let e = edges[item.0]
            let a = e.pts[item.1], b = e.pts[item.1 + 1]
            let d = distanceToSegment(p, a, b) - (e.isService ? 3 : 0)
            if best == nil || d < best!.1 { best = (item.0, d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// What's underfoot at a point: the road, a sidewalk (a kerb above it) where the street has one on that side,
    /// or the ground beside the street.
    func surface(_ p: SIMD2<Float>) -> Float {
        var best: (d: Float, e: Int, right: Bool)?
        roadGrid.query(p, 12) { item in
            let e = self.edges[item.0]
            let a = e.pts[item.1], b = e.pts[item.1 + 1]
            let q = closestOnSegment(p, a, b)
            let d = simd_distance(p, q)
            if best == nil || d < best!.d { best = (d, item.0, cross2(b - a, p - a) < 0) }
        }
        guard let b = best else { return inWater(p) ? Heights.underwater : Heights.ground }
        let e = edges[b.e]
        if b.d <= e.width / 2 { return Heights.road }
        // In a crossing's middle it's all road.
        for n in [e.a, e.b] where nodes[n].edges.count >= 3 && simd_distance(nodes[n].pos, p) < nodes[n].radius + 0.5 { return Heights.road }
        let has = b.right ? e.sidewalks.1 : e.sidewalks.0
        if has && b.d <= e.width / 2 + e.verge + e.walkWidth { return Heights.sidewalk }
        if e.isService { return Heights.road }
        return inWater(p) ? Heights.underwater : Heights.ground
    }

    /// Where shops are, for putting people where it's busy.
    var shopGrid = Grid<SIMD2<Float>>(cell: 50)
    func addShops(_ ps: [SIMD2<Float>]) { for p in ps { shopGrid.insert(p, min: p, max: p) } }
    func shopsNear(_ p: SIMD2<Float>, _ r: Float = 50) -> Int {
        var n = 0
        shopGrid.query(p, r) { q in if simd_distance(q, p) < r { n += 1 } }
        return n
    }

    /// Neighbourhood and suburb names from the map, as they load.
    var places: [PlaceData] = []
    private var placeSpots = Set<String>()

    /// Named areas (campuses, parks, districts): outline, bounds and size.
    var namedAreas: [(name: String, poly: [SIMD2<Float>], lo: SIMD2<Float>, hi: SIMD2<Float>, size: Float)] = []

    func addPlaces(_ list: [PlaceData]) {
        for p in list where placeSpots.insert("\(p.n)|\(Int(p.x / 50))|\(Int(p.y / 50))").inserted {
            if let pg = p.pg {
                let poly = points(pg)
                guard poly.count >= 3 else { continue }
                let lo = poly.reduce(poly[0]) { simd_min($0, $1) }, hi = poly.reduce(poly[0]) { simd_max($0, $1) }
                namedAreas.append((p.n, poly, lo, hi, abs(TileProcessor.area(poly))))
            } else {
                places.append(p)
            }
        }
    }

    /// What to call where a point is: a neighbourhood or suburb close by, else the smallest named area it's inside
    /// (a campus, a park, a district), else the street it's on, else the city.
    func neighbourhood(_ p: SIMD2<Float>) -> String {
        var best: String?, bd: Float = 150
        for n in places {
            let d = simd_distance(SIMD2(n.x, n.y), p) / (n.s == 1 ? 2 : 1)
            if d < bd { bd = d; best = n.n }
        }
        if let best { return best }
        var inside: (String, Float)?
        for a in namedAreas where p.x >= a.lo.x && p.x <= a.hi.x && p.y >= a.lo.y && p.y <= a.hi.y && (inside == nil || a.size < inside!.1) {
            if TileProcessor.pointIn(a.poly, p) { inside = (a.name, a.size) }
        }
        if let inside { return inside.0 }
        if let street = streetName(near: p, within: 40) { return street }
        return CityConfig.current.name
    }
}

func distanceToSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float {
    simd_distance(p, closestOnSegment(p, a, b))
}

func closestOnSegment(_ p: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> SIMD2<Float> {
    let d = b - a
    let l2 = simd_length_squared(d)
    if l2 < 1e-8 { return a }
    let t = max(0, min(1, simd_dot(p - a, d) / l2))
    return a + d * t
}

/// "East Liberty Street" as a street sign writes it: "E Liberty St".
func signName(_ name: String) -> String {
    let words = ["North": "N", "South": "S", "East": "E", "West": "W", "Street": "St", "Avenue": "Ave",
                 "Place": "Pl", "Court": "Ct", "Drive": "Dr", "Boulevard": "Blvd", "Road": "Rd", "Lane": "Ln"]
    return name.split(separator: " ").map { words[String($0)] ?? String($0) }.joined(separator: " ")
}
