import SwiftUI
import RealityKit

/// What drawing a square needs from the city, copied (cheaply: arrays are shared until changed) so it can be
/// read off the main thread while the game goes on changing the city.
struct CitySnapshot: @unchecked Sendable {
    let edges: [RoadEdge]
    let nodes: [RoadNode]
    let roadGrid: Grid<(Int, Int)>
    let fallen: Set<SIMD2<Int32>>
}

/// One square worked out off the main thread: its meshes as plain vertex data per material, the street signs
/// and signal poles standing in it (each its own small set of meshes), where its poles stand for collisions,
/// its sign lettering, and its trees.
struct SquarePlan: @unchecked Sendable {
    struct Batch { let material: String; let name: String; let mesh: LampMeshBuilder }
    struct Piece {
        let spot: SIMD2<Int32>
        let meshes: [(material: String, mesh: LampMeshBuilder)]
        let lamps: (node: Int, group: Int, meshes: [LampMeshBuilder])?
    }
    var batches: [Batch] = []
    var pieces: [Piece] = []
    var posts: [(c: SIMD2<Float>, r: Float, kind: UInt8)] = []
    var signalNodes: [Int] = []
    var atlasKey: UInt64?
    var atlasImage: CGImage?
    var trees: [[Float]] = []
    /// The square's storefronts, in the order of its shops.
    var shops: [ShopPieces.Plan] = []
    /// Street furniture (kind, x, y, heading), drawn as copies of one model per kind.
    var furniture: [[Float]] = []
}

extension MeshKit {
    /// The same triangles, as LampScene's builder, to be made into a mesh on the main thread.
    var builder: LampMeshBuilder { LampMeshBuilder(positions: pos, normals: nor, uvs: uv, indices: idx) }
}

/// Works out a square's geometry from a snapshot of the city: ground cover, streets and their markings, buildings,
/// signs, signals. Touches no entity, material or game state, so it runs on any thread.
final class CityGeometry {
    let city: CitySnapshot
    private var part = CityPart()
    private var batches: [String: MeshKit] = [:]
    let chunk: Float = 300

    static let plaques: [NSColor] = [
        NSColor(red: 0.05, green: 0.2, blue: 0.12, alpha: 1), NSColor(red: 0.06, green: 0.1, blue: 0.25, alpha: 1),
        NSColor(red: 0.4, green: 0.05, blue: 0.07, alpha: 1), NSColor(white: 0.06, alpha: 1), NSColor(red: 0.2, green: 0.12, blue: 0.08, alpha: 1),
    ]

    init(city: CitySnapshot) { self.city = city }

    /// Everything on one square.
    // MARK: The lie of the land

    /// While set, points stand on this height instead of the ground under each (a building sits level on the
    /// lowest ground under it, its walls running down into the slope).
    private var flatBase: Float?
    /// Off: drawn as if the land were flat (for comparing triangle counts).
    var follow = true
    private var hilly: Bool { follow && Terrain.shared.count > 0 }

    /// What a material is for, in the triangle census.
    static func censusGroup(_ m: String) -> String {
        let base = String(m.split(separator: "~").first ?? "")
        switch base {
        case "lawn": return "ground"
        case "park", "wood", "water", "paved", "woodchip", "court", "courtTan", "track", "lot": return "areas"
        case _ where base.hasPrefix("golf:"): return "areas"
        case "asphalt", "sidewalk", "verge", "walk", "path", "drive", "drivecon": return "roads"
        case "kerb": return "kerbs"
        case "white", "yellow": return "markings"
        default: return "other"
        }
    }

    /// A point `h` above the ground (or above the building's base) in 3D: the drawing's own version of `w3`.
    private func w3(_ p: SIMD2<Float>, _ h: Float) -> SIMD3<Float> { SIMD3(p.x, h + (flatBase ?? (follow ? Terrain.shared.height(p) : 0)), -p.y) }

    /// How closely drawn things follow the ground: a road or kerb strays at most this far from it between its
    /// points (markings sit 5 cm over the road), a lawn or park a little more (they sit apart further).
    static let lineTolerance: Float = 0.02
    static let areaTolerance: Float = 0.03
    static let groundTolerance: Float = 0.05

    /// A line with points added only where the ground under it bends (not where it only slopes evenly), so it
    /// follows the ground to within `lineTolerance`. `spread`: offsets to the right of the line whose own course
    /// must follow too (a strip's two edges).
    private func dense(_ line: [SIMD2<Float>], spread: [Float] = [0]) -> [SIMD2<Float>] {
        guard hilly, line.count >= 2 else { return line }
        let tol = Self.lineTolerance
        var out = [line[0]]
        func refine(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ depth: Int) {
            let len = simd_distance(a, b)
            guard len > 1.5, depth < 12 else { return }
            let n = perpRight((b - a) / len)
            var worst: Float = 0, at: Float = 0.5
            for o in spread {
                let r = Terrain.shared.bend(a + n * o, b + n * o)
                if r.dev > worst { worst = r.dev; at = r.at }
            }
            guard worst > tol else { return }
            let m = a + (b - a) * max(0.15, min(0.85, at))
            refine(a, m, depth + 1)
            out.append(m)
            refine(m, b, depth + 1)
        }
        for i in 1..<line.count {
            refine(line[i - 1], line[i], 0)
            out.append(line[i])
        }
        return out
    }

    /// The ground for one square: lawn following the land, in big pieces where it's even and down to the
    /// elevation grid's 10 m where it bends. A few centimetres under everything laid on it, so the two can stray
    /// from the ground a little each without one showing through the other.
    private func groundGrid(_ square: SIMD2<Int32>) {
        let size: Float = 150
        let x0 = Float(square.x) * size, y0 = -Float(square.y + 1) * size
        let h = Heights.ground - 0.07
        with("lawn", at: SIMD2(x0 + 1, y0 + 1)) { kit in
            func quad(_ a: SIMD2<Float>, _ c: SIMD2<Float>) {
                let b = SIMD2(c.x, a.y), d = SIMD2(a.x, c.y)
                kit.quad(w3(a, h), w3(b, h), w3(c, h), w3(d, h), uv: (a, b, c, d), outward: [0, 1, 0])
            }
            // Split in two along the longer side while the two triangles drawn stray from the ground.
            func piece(_ a: SIMD2<Float>, _ c: SIMD2<Float>) {
                let w = c.x - a.x, d = c.y - a.y
                guard hilly, max(w, d) > 10.5 else { quad(a, c); return }
                let b = SIMD2(c.x, a.y), e = SIMD2(a.x, c.y)
                let terrain = Terrain.shared
                if max(terrain.bend(a, b, c), terrain.bend(a, c, e)) <= Self.groundTolerance { quad(a, c); return }
                if w >= d {
                    let m = a.x + (w / 2 / terrain.cell).rounded(.down) * terrain.cell
                    let mx = m > a.x + 1 ? m : a.x + w / 2
                    piece(a, SIMD2(mx, c.y)); piece(SIMD2(mx, a.y), c)
                } else {
                    let m = a.y + (d / 2 / terrain.cell).rounded(.down) * terrain.cell
                    let my = m > a.y + 1 ? m : a.y + d / 2
                    piece(a, SIMD2(c.x, my)); piece(SIMD2(a.x, my), c)
                }
            }
            piece(SIMD2(x0, y0), SIMD2(x0 + size, y0 + size))
        }
    }

    func plan(_ part: CityPart, square: SIMD2<Int32>? = nil) -> SquarePlan {
        if let square { groundGrid(square) }
        // Only streets and crossings this city has (a square remembered from an earlier city is skipped).
        var part = part
        part.edges = part.edges.filter { $0 < city.edges.count }
        part.nodes = part.nodes.filter { $0 < city.nodes.count && city.nodes[$0].edges.allSatisfy { $0 < city.edges.count } }
        self.part = part
        atlas = TextAtlas()
        areas()
        roads()
        markings()
        buildings()
        streetSigns()
        shopSigns()
        houseNumbers()
        stopSigns()
        wires()
        fuelStations()
        lettering()
        trafficSignals()
        var out = SquarePlan()
        for (k, kit) in batches where !kit.isEmpty {
            let bits = k.split(separator: "|")
            out.batches.append(.init(material: String(bits[0]), name: "chunk|\(bits[1])|\(bits[2])", mesh: kit.builder))
        }
        for (spot, kits) in pieceKits {
            let meshes = kits.filter { !$0.value.isEmpty }.map { (material: $0.key, mesh: $0.value.builder) }
            let lamps = pieceLamps[spot].map { (node: $0.node, group: $0.group, meshes: $0.kits.map(\.builder)) }
            out.pieces.append(.init(spot: spot, meshes: meshes, lamps: lamps))
        }
        out.posts = posts
        out.signalNodes = signalNodes
        out.atlasKey = atlasKey
        out.atlasImage = atlasImage
        out.trees = part.trees
        out.furniture = part.furniture
        return out
    }

    // MARK: Batching

    private func key(_ mat: String, _ p: SIMD2<Float>) -> String {
        "\(mat)|\(Int(floor(p.x / chunk)))|\(Int(floor(p.y / chunk)))"
    }

    private func with(_ mat: String, at p: SIMD2<Float>, _ body: (inout MeshKit) -> Void) {
        if let piece {
            body(&pieceKits[piece, default: [:]][mat, default: MeshKit()])
            return
        }
        let k = key(mat, p)
        var kit = batches[k] ?? MeshKit()
        body(&kit)
        batches[k] = kit
    }

    // MARK: Things a car can knock down

    /// While set, `with` draws into this street sign's or signal pole's own meshes rather than the batches.
    private var piece: SIMD2<Int32>?
    private var pieceKits: [SIMD2<Int32>: [String: MeshKit]] = [:]
    private var pieceFaces: [SIMD2<Int32>: [(cell: Int, at: SIMD3<Float>, yaw: Float, w: Float, h: Float)]] = [:]
    /// Stop sign faces waiting for the atlas: their sign, cell, centre, facing.
    private var stopFaces: [(spot: SIMD2<Int32>, cell: Int, at: SIMD3<Float>, yaw: Float)] = []
    private var pieceLamps: [SIMD2<Int32>: (node: Int, group: Int, kits: [MeshKit])] = [:]
    /// Poles to drive into, added to the city on the main thread.
    private var posts: [(c: SIMD2<Float>, r: Float, kind: UInt8)] = []
    private var signalNodes: [Int] = []

    // MARK: Ground and areas

    private func polygon(_ mat: String, _ poly: [SIMD2<Float>], _ tris: [Int], h: Float, down: Bool = false) {
        guard let first = poly.first else { return }
        // Big triangles are split so they follow the ground (not on a building, which stands level).
        let split = flatBase == nil && hilly
        with(mat, at: first) { kit in
            func tri(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>, _ depth: Int) {
                // Split only while the flat triangle strays from the ground: across its longest side.
                let ab = simd_distance(a, b), bc = simd_distance(b, c), ca = simd_distance(c, a)
                let longest = max(ab, bc, ca)
                if split && longest > 3 && depth < 10 && Terrain.shared.bend(a, b, c) > Self.areaTolerance {
                    if longest == ab { let m = (a + b) / 2; tri(a, m, c, depth + 1); tri(m, b, c, depth + 1) }
                    else if longest == bc { let m = (b + c) / 2; tri(a, b, m, depth + 1); tri(a, m, c, depth + 1) }
                    else { let m = (c + a) / 2; tri(a, b, m, depth + 1); tri(m, b, c, depth + 1) }
                    return
                }
                kit.tri(w3(a, h), w3(b, h), w3(c, h), uv: (a, b, c), outward: [0, down ? -1 : 1, 0])
            }
            for t in stride(from: 0, to: tris.count - 2, by: 3) {
                guard tris[t + 2] < poly.count else { continue }
                tri(poly[tris[t]], poly[tris[t + 1]], poly[tris[t + 2]], 0)
            }
        }
    }

    private func areas() {
        for g in part.grass {
            switch g.k {
            case "paved": polygon("paved", points(g.p), g.t, h: Heights.paved)
            case "residential": continue
            case "water": polygon("water", points(g.p), g.t, h: Heights.water)
            case "wood": polygon("wood", points(g.p), g.t, h: Heights.wood)
            case _ where g.k.hasPrefix("pitch"):
                pitch(g)
            case "playground":
                polygon("woodchip", points(g.p), g.t, h: Heights.grass)
            case _ where g.k.hasPrefix("golf:"):
                // Each a few centimetres over the last, so they never show through one another on the slopes.
                let part = String(g.k.dropFirst(5))
                let h: Float = ["green": 0.12, "tee": 0.12, "bunker": 0.1, "fairway": 0.07, "rough": 0.045][part] ?? Heights.grass
                polygon(part == "tee" ? "golf:green" : "golf:" + part, points(g.p), g.t, h: h)
            default: polygon("park", points(g.p), g.t, h: Heights.grass)
            }
        }
        for l in part.lots {
            polygon("lot", points(l.p), l.t, h: Heights.lot)
            parkingSpaces(l)
        }
        for p in part.paths {
            if p.k == "water" { ribbon("water", points(p.p), half: p.w / 2, h: Heights.water) }
            else if p.k == "drive" { mappedDrive(points(p.p)) }
            else { ribbon("path", points(p.p), half: p.w / 2, h: Heights.path) }
        }
    }

    /// Painted spaces in a parking lot: double rows 5.5 m deep either side of a 7 m aisle, a line every 2.6 m,
    /// lined up with the lot. The pattern is laid from a fixed origin, so the pieces of a lot cut by squares match.
    private func parkingSpaces(_ l: AreaData) {
        guard let angle = l.a else { return }
        let pts = points(l.p)
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        for i in stride(from: 0, to: l.t.count - 2, by: 3) where l.t[i + 2] < pts.count { tris.append((pts[l.t[i]], pts[l.t[i + 1]], pts[l.t[i + 2]])) }
        guard !tris.isEmpty else { return }
        func inside(_ p: SIMD2<Float>) -> Bool {
            tris.contains { t in
                let d1 = cross2(t.1 - t.0, p - t.0), d2 = cross2(t.2 - t.1, p - t.1), d3 = cross2(t.0 - t.2, p - t.2)
                return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
            }
        }
        let u = SIMD2(cos(angle), sin(angle)), v = SIMD2(-u.y, u.x)
        // The piece's extent in the lot's own frame.
        let su = pts.map { simd_dot($0, u) }, sv = pts.map { simd_dot($0, v) }
        let (u0, u1, v0, v1) = (su.min()!, su.max()!, sv.min()!, sv.max()!)
        guard u1 - u0 > 4, v1 - v0 > 4 else { return }
        let stall: Float = 2.6, depth: Float = 5.5, module: Float = 18, line: Float = 0.06
        let h = Heights.lot + 0.012
        func mark(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ kit: inout MeshKit) {
            let d = simd_normalize(b - a), n = SIMD2(-d.y, d.x) * line
            kit.quad(w3(a - n, h), w3(b - n, h), w3(b + n, h), w3(a + n, h), outward: [0, 1, 0])
        }
        with("white", at: pts[0]) { kit in
            var m = floor(v0 / module) * module
            while m < v1 {
                for (r0, r1) in [(m, m + depth), (m + module - depth, m + module)] {
                    var s = floor(u0 / stall) * stall
                    while s <= u1 {
                        let a = u * s + v * (r0 + 0.3), b = u * s + v * (r1 - 0.3)
                        if inside(a) && inside(b) && inside(u * (s + stall) + v * r0) { mark(a, b, &kit) }
                        s += stall
                    }
                }
                m += module
            }
        }
    }

    /// A sports pitch: its surface by sport (courts hard and coloured, a running track red, fields grass) and its
    /// white lines, drawn by the piece holding the pitch's middle.
    private func pitch(_ g: AreaData) {
        let sport = String(g.k.dropFirst(6))
        let surface = sport.contains("tennis") ? "court" : (sport.contains("basketball") || sport.contains("volleyball") ? "courtTan"
            : (sport.contains("running") || sport.contains("athletics") ? "track" : "park"))
        let pts = points(g.p)
        polygon(surface, pts, g.t, h: Heights.grass + 0.004)
        guard let o = g.o, o.count >= 6 else { return }
        let c = SIMD2(o[0], o[1]), u = SIMD2(o[2], o[3]), v = SIMD2(-o[3], o[2]), hl = o[4] - 0.4, hw = o[5] - 0.4
        // Only once: the piece whose triangles hold the middle.
        var holds = false
        for i in stride(from: 0, to: g.t.count - 2, by: 3) where g.t[i + 2] < pts.count {
            let a = pts[g.t[i]], b = pts[g.t[i + 1]], d = pts[g.t[i + 2]]
            let d1 = cross2(b - a, c - a), d2 = cross2(d - b, c - b), d3 = cross2(a - d, c - d)
            if !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0)) { holds = true; break }
        }
        guard holds, hl > 2, hw > 2, surface != "track" else { return }
        let h = Heights.grass + 0.012
        let corners = [c - u * hl - v * hw, c + u * hl - v * hw, c + u * hl + v * hw, c - u * hl + v * hw]
        ribbon("white", corners + [corners[0], corners[1]], half: 0.05, h: h)
        ribbon("white", [c - v * hw, c + v * hw], half: 0.05, h: h)
        if sport.contains("american_football") || sport.contains("football") && !sport.contains("soccer") {
            // Yard lines every ten yards between the end zones.
            let zone = min(9.14, hl * 0.09)
            var x = -hl + zone
            while x <= hl - zone + 0.1 {
                ribbon("white", [c + u * x - v * hw, c + u * x + v * hw], half: 0.06, h: h)
                x += (hl - zone) * 2 / 10
            }
        } else if !sport.contains("tennis") {
            // The centre circle.
            let r = min(hw * 0.35, sport.contains("basketball") ? 1.8 : 9.15)
            ribbon("white", (0...24).map { c + u * cos(Float($0) / 24 * 2 * .pi) * r + v * sin(Float($0) / 24 * 2 * .pi) * r }, half: 0.05, h: h)
        }
    }

    /// A material tinted to a tagged colour: its name with the colour after a ~ (made on the main thread).
    static func tinted(_ mat: String, _ c: [Float]?) -> String {
        guard let c, c.count >= 3 else { return mat }
        let hex = c.prefix(3).map { String(Int(max(0, min(1, $0)) * 15 + 0.5), radix: 16) }.joined()
        return "\(mat)~\(hex)"
    }

    // MARK: Roads

    /// A strip along a line, `offset` to the right of it, `half` wide each side.
    private func ribbon(_ mat: String, _ line: [SIMD2<Float>], half: Float, offset: Float = 0, h: Float, uvScale: Float = 1) {
        var pts: [SIMD2<Float>] = []
        for p in dense(line, spread: [offset - half, offset + half]) where pts.last.map({ simd_distance($0, p) > 0.02 }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return }
        var normals: [SIMD2<Float>] = []
        for i in 0..<pts.count {
            let dPrev = i > 0 ? simd_normalize(pts[i] - pts[i - 1]) : simd_normalize(pts[1] - pts[0])
            let dNext = i < pts.count - 1 ? simd_normalize(pts[i + 1] - pts[i]) : dPrev
            let n0 = perpRight(dPrev)
            var n = perpRight(dPrev) + perpRight(dNext)
            n = simd_length(n) > 1e-4 ? simd_normalize(n) : n0
            normals.append(n / max(0.5, simd_dot(n, n0)))
        }
        with(mat, at: pts[0]) { kit in
            var along: Float = 0
            for i in 0..<(pts.count - 1) {
                let seg = simd_distance(pts[i], pts[i + 1])
                let r0 = pts[i] + normals[i] * (offset + half), l0 = pts[i] + normals[i] * (offset - half)
                let r1 = pts[i + 1] + normals[i + 1] * (offset + half), l1 = pts[i + 1] + normals[i + 1] * (offset - half)
                let u0 = along * uvScale, u1 = (along + seg) * uvScale
                kit.quad(w3(r0, h), w3(r1, h), w3(l1, h), w3(l0, h),
                         uv: ([half * 2, u0], [half * 2, u1], [0, u1], [0, u0]), outward: [0, 1, 0])
                along += seg
            }
        }
    }

    private func disc(_ mat: String, _ c: SIMD2<Float>, _ r: Float, h: Float) {
        with(mat, at: c) { kit in
            let n = 20
            for i in 0..<n {
                let a0 = Float(i) / Float(n) * 2 * .pi, a1 = Float(i + 1) / Float(n) * 2 * .pi
                let p = c + SIMD2(cos(a0), sin(a0)) * r, q = c + SIMD2(cos(a1), sin(a1)) * r
                kit.tri(w3(c, h), w3(p, h), w3(q, h), uv: (c, p, q), outward: [0, 1, 0])
            }
        }
    }

    /// How far from a crossing a street's sidewalks stop, where the corner pieces take over.
    private func sidewalkTrim(_ n: Int) -> Float {
        guard n < city.nodes.count, city.nodes[n].edges.count >= 3 else { return 0 }
        return city.nodes[n].radius + 0.5
    }

    /// A line moved sideways (right of its direction for positive `offset`), corners mitred.
    private func offsetLine(_ line: [SIMD2<Float>], _ offset: Float) -> [SIMD2<Float>] {
        var pts: [SIMD2<Float>] = []
        for p in line where pts.last.map({ simd_distance($0, p) > 0.02 }) ?? true { pts.append(p) }
        guard pts.count >= 2 else { return [] }
        return pts.indices.map { i in
            let dPrev = i > 0 ? simd_normalize(pts[i] - pts[i - 1]) : simd_normalize(pts[1] - pts[0])
            let dNext = i < pts.count - 1 ? simd_normalize(pts[i + 1] - pts[i]) : dPrev
            let n0 = perpRight(dPrev)
            var n = perpRight(dPrev) + perpRight(dNext)
            n = simd_length(n) > 1e-4 ? simd_normalize(n) : n0
            return pts[i] + n / max(0.5, simd_dot(n, n0)) * offset
        }
    }

    /// The kerb's face along a line, from `bottom` (the road) up to the sidewalk, facing right of the line's
    /// direction for `facing` +1, left for −1.
    private func kerb(_ rawLine: [SIMD2<Float>], facing toRoad: Float, bottom: Float = Heights.road - 0.02) {
        let line = dense(rawLine)
        guard line.count >= 2 else { return }
        with("kerb", at: line[0]) { kit in
            for i in 0..<(line.count - 1) {
                let a = line[i], b = line[i + 1]
                guard simd_distance(a, b) > 0.01 else { continue }
                let n = perpRight(simd_normalize(b - a)) * toRoad
                kit.quad(w3(a, bottom), w3(b, bottom), w3(b, Heights.sidewalk), w3(a, Heights.sidewalk),
                         uv: ([0, 0], [simd_distance(a, b), 0], [simd_distance(a, b), 0.15], [0, 0.15]), outward: SIMD3(n.x, 0, -n.y))
            }
        }
    }

    private func roads() {
        for ei in part.edges {
            let e = city.edges[ei]
            ribbon("asphalt", e.pts, half: e.width / 2, h: Heights.road)
            guard !e.isService else { continue }
            // Sidewalks a kerb above the road on the sides that have them, with a grass strip on residential streets;
            // they stop short of crossings, where the corner pieces join them up.
            let s0 = sidewalkTrim(e.a), s1 = e.length - sidewalkTrim(e.b)
            guard s1 - s0 > 0.5 else { continue }
            let line = slice(e, s0, s1)
            for (side, has) in [(Float(1), e.sidewalks.1), (Float(-1), e.sidewalks.0)] where has {
                if e.verge > 0 { ribbon("verge", line, half: e.verge / 2, offset: side * (e.width / 2 + e.verge / 2), h: Heights.sidewalk) }
                ribbon("sidewalk", line, half: e.walkWidth / 2, offset: side * (e.width / 2 + e.verge + e.walkWidth / 2), h: Heights.sidewalk)
                kerb(offsetLine(line, side * e.width / 2), facing: -side)
                // The back of the sidewalk, down to the ground.
                kerb(offsetLine(line, side * (e.width / 2 + e.verge + e.walkWidth)), facing: side, bottom: Heights.ground - 0.12)
            }
        }
        for i in part.nodes where city.nodes[i].edges.count >= 2 {
            let n = city.nodes[i]
            let widths = n.edges.map { city.edges[$0].width }
            let r = widths.max() ?? 6
            disc("asphalt", n.pos, n.edges.count == 2 ? (widths.min() ?? r) / 2 : r / 2 + 0.6, h: Heights.road)
            corners(i)
        }
    }

    /// The sidewalk round each corner of a crossing: between each street's left side and the next one's right
    /// (counter-clockwise), from kerb to the back of the sidewalk, with its kerb.
    private func corners(_ ni: Int) {
        let n = city.nodes[ni]
        guard n.edges.count >= 3 else { return }
        let t = sidewalkTrim(ni)
        struct End { let d: SIMD2<Float>; let e: RoadEdge; let left: Bool; let right: Bool }
        var ends: [End] = []
        for ei in n.edges where ei < city.edges.count {
            let e = city.edges[ei]
            guard !e.isService else { continue }
            let d = e.outward(from: ni)
            // Sides as seen looking out of the crossing along the street.
            let out = e.a == ni
            ends.append(End(d: d, e: e, left: out ? e.sidewalks.0 : e.sidewalks.1, right: out ? e.sidewalks.1 : e.sidewalks.0))
        }
        guard ends.count >= 2 else { return }
        ends.sort { atan2($0.d.y, $0.d.x) < atan2($1.d.y, $1.d.x) }
        for k in 0..<ends.count {
            let a = ends[k], b = ends[(k + 1) % ends.count]
            guard a.left && b.right else { continue }
            let la = SIMD2(-a.d.y, a.d.x), rb = perpRight(b.d)
            let reachA = a.e.width / 2 + a.e.verge + a.e.walkWidth, reachB = b.e.width / 2 + b.e.verge + b.e.walkWidth
            let aKerb = n.pos + a.d * t + la * a.e.width / 2, aOut = n.pos + a.d * t + la * reachA
            let bKerb = n.pos + b.d * t + rb * b.e.width / 2, bOut = n.pos + b.d * t + rb * reachB
            // Skip a corner that would fold over itself (streets nearly back to back).
            guard cross2(a.d, b.d) > -0.2 || simd_dot(a.d, b.d) < -0.9 else { continue }
            with("sidewalk", at: n.pos) { kit in
                kit.quad(w3(aKerb, Heights.sidewalk), w3(aOut, Heights.sidewalk), w3(bOut, Heights.sidewalk), w3(bKerb, Heights.sidewalk),
                         uv: (aKerb, aOut, bOut, bKerb), outward: [0, 1, 0])
            }
            // Its kerb faces into the crossing.
            let mid = (aKerb + bKerb) / 2
            kerb([bKerb, aKerb], facing: simd_dot(perpRight(aKerb - bKerb), n.pos - mid) >= 0 ? 1 : -1)
        }
    }

    // MARK: Markings

    func isCrossing(_ n: Int) -> Bool {
        guard n < city.nodes.count else { return false }
        let node = city.nodes[n]
        let roads = node.edges.filter { $0 < city.edges.count && !city.edges[$0].isService }
        return node.signal || (roads.count >= 3 && roads.map { city.edges[$0].rank }.max() ?? 0 >= 3)
    }

    private func trim(_ n: Int) -> Float {
        guard n < city.nodes.count else { return 0 }
        let node = city.nodes[n]
        let roads = node.edges.filter { $0 < city.edges.count && !city.edges[$0].isService }
        if roads.count < 3 && node.edges.count < 3 { return 0 }
        return node.radius + (isCrossing(n) ? 6 : 1.5)
    }

    private func slice(_ e: RoadEdge, _ s0: Float, _ s1: Float) -> [SIMD2<Float>] {
        var out = [e.sample(s0).0]
        for (k, c) in e.cum.enumerated() where c > s0 && c < s1 { out.append(e.pts[k]) }
        out.append(e.sample(s1).0)
        return out
    }

    private func markings() {
        for ei in part.edges where !city.edges[ei].isService {
            let e = city.edges[ei]
            let s0 = trim(e.a), s1 = e.length - trim(e.b)
            let h = Heights.marking
            if s1 - s0 > 2 {
                let laneW = e.driveWidth / Float(e.lanes)
                if !e.oneway && e.rank >= 3 {
                    let line = slice(e, s0, s1)
                    // The centre line: double yellow, or double white where the region marks it so.
                    let centre = CityConfig.current.style.yellowCentreLine ? "yellow" : "white"
                    ribbon(centre, line, half: 0.06, offset: -0.14, h: h)
                    ribbon(centre, line, half: 0.06, offset: 0.14, h: h)
                }
                var dividers: [Float] = []
                if e.oneway {
                    if e.lanes >= 2 { for k in 1..<e.lanes { dividers.append(-e.driveWidth / 2 + Float(k) * laneW) } }
                } else {
                    let perDir = e.lanes / 2
                    if perDir >= 2 { for k in 1..<perDir { dividers += [Float(k) * laneW, -Float(k) * laneW] } }
                }
                var s = s0 + 1
                while s + 3 < s1 {
                    let seg = slice(e, s, s + 3)
                    for o in dividers { ribbon("white", seg, half: 0.06, offset: o, h: h) }
                    s += 9
                }
                if e.rank >= 3 && e.driveWidth < e.width - 1 {
                    let line = slice(e, s0, s1)
                    if e.parking.1 { ribbon("white", line, half: 0.06, offset: e.driveWidth / 2, h: h) }
                    if e.parking.0 { ribbon("white", line, half: 0.06, offset: -e.driveWidth / 2, h: h) }
                }
            }
            for end in [e.a, e.b] where end < city.nodes.count && isCrossing(end) && e.length > city.nodes[end].radius + 9 {
                crosswalk(ei, at: end)
            }
        }
    }

    private func crosswalk(_ ei: Int, at n: Int) {
        let e = city.edges[ei]
        let node = city.nodes[n]
        let fromA = n == e.a
        let sMid = node.radius + 2.6
        let (p, dir) = e.sample(fromA ? sMid : e.length - sMid)
        let right = perpRight(dir)
        let h = Heights.marking + 0.005
        with("white", at: p) { kit in
            var o = -e.width / 2 + 0.6
            while o <= e.width / 2 - 0.5 {
                let c = p + right * o
                let a = c - dir * 1.5 - right * 0.28, b = c - dir * 1.5 + right * 0.28
                let cc = c + dir * 1.5 + right * 0.28, d = c + dir * 1.5 - right * 0.28
                kit.quad(w3(a, h), w3(b, h), w3(cc, h), w3(d, h), outward: [0, 1, 0])
                o += 1.1
            }
            // Stop line across the lanes coming in.
            let sStop = node.radius + 4.9
            let (q, _) = e.sample(fromA ? sStop : e.length - sStop)
            let incoming = fromA ? !e.oneway : true
            if incoming {
                let side: Float = (fromA ? -1 : 1) * CityConfig.current.style.side
                let lo: Float = e.oneway ? -e.driveWidth / 2 : 0.2 * side
                let hi: Float = e.oneway ? e.driveWidth / 2 : e.driveWidth / 2 * side
                let a0 = q + right * min(lo, hi) - dir * 0.22, a1 = q + right * max(lo, hi) - dir * 0.22
                let b1 = q + right * max(lo, hi) + dir * 0.22, b0 = q + right * min(lo, hi) + dir * 0.22
                kit.quad(w3(a0, h), w3(a1, h), w3(b1, h), w3(b0, h), outward: [0, 1, 0])
            }
        }
    }

    // MARK: Buildings

    private func buildings() {
        for b in part.buildings where b.x != 1 {
            let poly = points(b.p)
            guard let first = poly.first else { continue }
            // Level on the lowest ground under it.
            flatBase = hilly ? poly.map { Terrain.shared.height($0) }.min() : nil
            defer { flatBase = nil }
            let holes = (b.ho ?? []).map(points)
            if b.lk == "stands", !holes.isEmpty {
                flatBase = nil
                stands(b, poly: poly, holes: holes)
                continue
            }
            let house = (4...8).contains(b.c)
            // How its windows go (pairs, a ribbon, narrow ones, or single), chosen for its kind of building.
            let pattern = (house || b.c == 3) ? 0 : (b.wp ?? 0)
            let bay: Float = house ? 5.0 : [2.8, 3.2, 2.8, 3.6][pattern]
            let floor: Float = house ? 2.9 : (b.c == 3 ? 3.8 : 3.4)
            let base = b.mh ?? 0
            // Walls and roofs in their tagged colours, else the look chosen from the building's type.
            let wall = Self.tinted("f\(b.c)" + (pattern > 0 ? "w\(pattern)" : ""), b.wc), plainWall = Self.tinted("p\(b.c)", b.wc)
            let flatRoof = Self.tinted("roof", b.rc), shingle = Self.tinted("sh\(b.r)", b.rc), copper = Self.tinted("copper", b.rc)
            // Shops along the street get a tall ground floor of shop windows.
            // Shop windows only where there are shops: a retail or commercial building, or one with a shop mapped inside.
            let shopFront: Float = (b.sf == 1 && !house && b.c != 3 && b.h > 6.5 && base == 0) ? 4.2 : 0
            for ring in [poly] + holes {
                if shopFront > 0 {
                    band("s\(b.c)", ring, from: 0, to: shopFront, bay: 3.6, floor: shopFront, vStart: 0)
                }
                let hv = Int(abs(first.x * 13.7 + first.y * 7.3))
                if b.gk != nil || b.lk == "plain" {
                    // A garage, a works, a store: plain walls, no windows (a garage's doors are added facing the street).
                    band(plainWall, ring, from: base, to: b.h, bay: bay, floor: floor, vStart: base / floor)
                } else {
                    band(wall, ring, from: max(base, shopFront), to: b.h, bay: bay, floor: floor, vStart: max(base, shopFront) / floor,
                         plain: house ? plainWall : nil, shift: SIMD2(Float(hv % 4), Float((hv / 4) % 4)),
                         lit: nil, blank: house || b.c == 3 ? nil : plainWall)
                }
            }
            if b.gk != nil { garageDoors(b, poly: poly) }
            if shopFront > 0 && b.pt == nil { apron(poly) }
            let all = poly + holes.flatMap { $0 }
            if base > 0.5 { polygon(flatRoof, all, b.t, h: base, down: true) }
            // A pitched roof over a footprint that isn't a plain rectangle (an L, a wing, a bay) follows the outline
            // instead: sloping in from every wall to a smaller copy of the outline on top.
            var shape = b.rs
            if let g = b.g, shape == "gabled" || shape == "hipped" {
                let box = 4 * max(0.1, g[4] - 0.35) * max(0.1, g[5] - 0.45)
                if abs(TileProcessor.area(poly)) < box * 0.88 && outlineRoof(poly, eave: b.h, rise: g[6], half: g[5] - 0.45, mat: shingle) {
                    shape = "outline"
                }
            }
            switch shape {
            case "outline": break
            case "gabled" where b.g != nil:
                with(house ? plainWall : wall, at: first) { kit in gable(&kit, b.g!, eave: b.h, floor: floor) }
                roof(b.g!, eave: b.h, mat: shingle)
            case "hipped" where b.g != nil:
                hipped(b.g!, eave: b.h, mat: shingle)
            case "pyramidal", "dome":
                spire(poly, eave: b.h, height: b.rh ?? 3, mat: b.rs == "dome" ? copper : shingle)
            default:
                polygon(flatRoof, all, b.t, h: b.h)
                if b.pt == nil { for ring in [poly] + holes { parapet(ring, top: b.h, mat: wall) } }
            }
        }
    }

    /// A stadium's bowl: rows of seats stepping up from the edge of the field (the courtyard) to the rim, `b.h`
    /// above the lowest ground, with a blank outer wall down to the ground.
    private func stands(_ b: BuildingData, poly: [SIMD2<Float>], holes: [[SIMD2<Float>]]) {
        guard let first = poly.first else { return }
        let all = poly + holes.flatMap { $0 }
        let ground = all.map { Terrain.shared.height($0) }
        let field = holes.flatMap { $0 }.map { Terrain.shared.height($0) }.min() ?? 0
        // Each corner's height: the field's edge at the ground, the rim level all round (never under the ground).
        let rim = field + b.h
        func top(_ i: Int) -> SIMD3<Float> {
            let p = all[i]
            let y = i < poly.count ? max(rim, ground[i] + 1.2) : ground[i] + 0.25
            return SIMD3(p.x, y, -p.y)
        }
        // Rows across the slope: v counts rows from the field (0) to the rim.
        let rows = max(4, b.h / 0.45)
        with("seats", at: first) { kit in
            for t in stride(from: 0, to: b.t.count - 2, by: 3) {
                let i = b.t[t], j = b.t[t + 1], k = b.t[t + 2]
                guard k < all.count, i < all.count, j < all.count else { continue }
                func v(_ n: Int) -> SIMD2<Float> { SIMD2(0, n < poly.count ? rows : 0) }
                kit.tri(top(i), top(j), top(k), uv: (v(i), v(j), v(k)), outward: [0, 1, 0])
            }
        }
        // The outer wall, from below the ground to the rim, and a low wall round the field.
        let wall = Self.tinted("p\(b.c)", b.wc)
        with(wall, at: first) { kit in
            for n in 0..<poly.count {
                let a = poly[n], c = poly[(n + 1) % poly.count]
                let len = simd_distance(a, c)
                guard len > 0.01 else { continue }
                let o = perpRight(simd_normalize(c - a))
                let ta = top(n), tc = top((n + 1) % poly.count)
                let y0 = min(ground[n], ground[(n + 1) % poly.count]) - 1
                kit.quad(SIMD3(a.x, y0, -a.y), SIMD3(c.x, y0, -c.y), tc, ta,
                         uv: ([0, 0], [len / 2.8, 0], [len / 2.8, (tc.y - y0) / 3.4], [0, (ta.y - y0) / 3.4]), outward: SIMD3(o.x, 0, -o.y))
            }
            var base = poly.count
            for h in holes {
                for n in 0..<h.count {
                    let a = h[n], c = h[(n + 1) % h.count]
                    guard simd_distance(a, c) > 0.01 else { continue }
                    let ya = ground[base + n], yc = ground[base + (n + 1) % h.count]
                    kit.quad(SIMD3(a.x, ya - 0.2, -a.y), SIMD3(c.x, yc - 0.2, -c.y), SIMD3(c.x, yc + 1.1, -c.y), SIMD3(a.x, ya + 1.1, -a.y))
                    kit.quad(SIMD3(c.x, yc - 0.2, -c.y), SIMD3(a.x, ya - 0.2, -a.y), SIMD3(a.x, ya + 1.1, -a.y), SIMD3(c.x, yc + 1.1, -c.y))
                }
                base += h.count
            }
        }
    }

    /// House numbers by the door: on the wall facing the nearest street, white plates on houses, dark ones on
    /// everything else.
    /// A building's front: where a line from its middle to the nearest real street (not an alley) leaves the
    /// footprint, the wall's outward direction there, and that street point and street.
    private func front(_ b: BuildingData) -> (spot: SIMD2<Float>, n: SIMD2<Float>, q: SIMD2<Float>, e: Int)? {
        let poly = points(b.p)
        guard poly.count >= 3 else { return nil }
        let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
        var q = c, best = Float.infinity, edge = -1
        city.roadGrid.query(c, 70) { item in
            guard item.0 < self.city.edges.count else { return }
            let e = self.city.edges[item.0]
            guard !e.isService else { return }
            let p = closestOnSegment(c, e.pts[item.1], e.pts[item.1 + 1])
            let d = simd_distance(p, c)
            if d < best { best = d; q = p; edge = item.0 }
        }
        guard best < 70, best > 0.5 else { return nil }
        let dir = simd_normalize(q - c)
        var hit: (Float, SIMD2<Float>, SIMD2<Float>)?
        for k in 0..<poly.count {
            let a = poly[k], ed = poly[(k + 1) % poly.count] - a
            let den = cross2(dir, ed)
            if abs(den) < 1e-6 { continue }
            let t = cross2(a - c, ed) / den, u = cross2(a - c, dir) / den
            if t > 0 && u >= 0 && u <= 1 && (hit == nil || t < hit!.0) {
                var n = perpRight(simd_normalize(ed))
                if simd_dot(n, dir) < 0 { n = -n }
                hit = (t, c + dir * t, n)
            }
        }
        guard let (_, spot, n) = hit else { return nil }
        return (spot, n, q, edge)
    }

    /// House numbers by the door, and on houses the door itself and a front walk out to the sidewalk.
    private func houseNumbers() {
        for b in part.buildings where b.x != 1 && b.pt == nil && b.gk == nil {
            let house = (4...8).contains(b.c) || b.g != nil
            let number = b.hn ?? ""
            guard house || !number.isEmpty, let f = front(b) else { continue }
            let (spot, n) = (f.spot, f.n)
            let along = SIMD2(n.y, -n.x)
            let yaw = atan2(n.x, -n.y)
            // The door goes between two windows: on the front wall, at the bay edge nearest the middle.
            let door = house ? doorSpot(b, near: spot) : spot
            if house {
                with("door", at: door) { kit in
                    kit.box(w3(door + n * 0.04, Heights.ground + 1.07), [0.9, 2.1, 0.08], rot: simd_quatf(angle: yaw, axis: [0, 1, 0]))
                }
                // A driveway beside it, and a narrow walk from the door straight out to the sidewalk.
                let e = city.edges[f.e]
                _ = driveway(b, poly: points(b.p), spot: spot, q: f.q, edge: e)
                let reach = e.width / 2 + e.verge + e.walkWidth
                let toDoor = door - f.q
                let len = simd_length(toDoor)
                if len > reach + 1 {
                    let end = f.q + toDoor / len * (reach - 0.1)
                    ribbon("walk", [door + n * 0.1, end], half: 0.45, h: Heights.path)
                }
            }
            guard !number.isEmpty else { continue }
            let y = house ? min(2.3, max(1.6, b.h - 0.6)) : min(3.0, max(1.8, b.h - 0.6))
            let h: Float = house ? 0.32 : 0.38
            let cell = atlas.cell(number, background: house ? NSColor(white: 0.96, alpha: 1) : NSColor(red: 0.08, green: 0.12, blue: 0.22, alpha: 1),
                                  ink: house ? NSColor(white: 0.08, alpha: 1) : .white, maxAspect: 4)
            let w = min(4 * h, Float(TextAtlas.width(number) + 28) / 64 * h)
            // Beside the door (on a house, low, between it and the next window).
            let at = house ? w3(door + along * 0.85 + n * 0.08, 1.75) : w3(spot + along * 0.9 + n * 0.08, y)
            faces.append((cell, at, yaw, w, h))
        }
    }

    /// Where a house's front door goes: on the wall holding `spot`, at the edge between two window bays nearest
    /// it (the walls are drawn in whole bays from each corner, a window in the middle of each), or off to one side
    /// of a wall only one bay wide.
    private func doorSpot(_ b: BuildingData, near spot: SIMD2<Float>) -> SIMD2<Float> {
        let poly = points(b.p)
        guard poly.count >= 2 else { return spot }
        var best: (d: Float, k: Int) = (.infinity, 0)
        for k in 0..<poly.count {
            let d = simd_distance(closestOnSegment(spot, poly[k], poly[(k + 1) % poly.count]), spot)
            if d < best.d { best = (d, k) }
        }
        let a = poly[best.k], c = poly[(best.k + 1) % poly.count]
        let len = simd_distance(a, c)
        guard len > 1.5 else { return spot }
        let bay: Float = (4...8).contains(b.c) ? 5.0 : 2.8
        let bays = max(1, (len / bay).rounded())
        let t = simd_dot(spot - a, c - a) / (len * len)
        if bays < 2 {
            // One window in the middle: the door between it and a corner.
            return a + (c - a) * (t < 0.5 ? 0.17 : 0.83)
        }
        let i = max(1, min(bays - 1, (t * bays).rounded()))
        return a + (c - a) * (i / bays)
    }

    /// A driveway beside a house where none is mapped: from the kerb, across the sidewalk, to a little past the
    /// front of the house, on whichever side has room.
    /// The garage behind a house (beyond its front, within 35 m, to the side the driveway runs).
    private func garage(behind spot: SIMD2<Float>, toStreet: SIMD2<Float>, near a: SIMD2<Float>) -> (b: BuildingData, c: SIMD2<Float>)? {
        var best: (BuildingData, SIMD2<Float>, Float)?
        for g in part.buildings where g.gk != nil {
            let poly = points(g.p)
            guard !poly.isEmpty else { continue }
            let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
            let back = simd_dot(spot - c, toStreet)
            let d = simd_distance(c, a)
            if back > 2 && d < 35 && (best == nil || d < best!.2) { best = (g, c, d) }
        }
        return best.map { ($0.0, $0.1) }
    }

    /// Returns whether the house has a driveway (mapped or drawn here).
    private func driveway(_ b: BuildingData, poly: [SIMD2<Float>], spot: SIMD2<Float>, q: SIMD2<Float>, edge e: RoadEdge) -> Bool {
        let toStreet = simd_normalize(q - spot)
        let t = SIMD2(-toStreet.y, toStreet.x)
        // Not where a driveway is mapped already.
        for p in part.paths where p.k == "drive" {
            let pts = points(p.p)
            if pts.contains(where: { simd_distance($0, spot) < 18 }) { return true }
        }
        let reach = e.width / 2 + e.verge + e.walkWidth
        let extents = poly.map { simd_dot($0 - spot, t) }
        let seed = Int(abs(spot.x * 3.1 + spot.y * 1.7))
        for side in (seed % 2 == 0 ? [Float(1), -1] : [-1, 1]) {
            let o = side > 0 ? (extents.max() ?? 0) + 1.9 : (extents.min() ?? 0) - 1.9
            let a = spot + t * o
            let dist = simd_dot(q - a, toStreet)
            guard dist > reach + 2 else { continue }
            // Back past the rear of the house.
            let depth = poly.map { simd_dot($0 - spot, -toStreet) }.max() ?? 8
            let kerb = a + toStreet * (dist - e.width / 2), back = a + toStreet * (dist - reach), end = a - toStreet * (depth + 3)
            // Room for it: not through another building.
            let blocked = part.buildings.contains { other in
                guard other.x != 1, other.gk == nil else { return false }
                let op = points(other.p)
                guard let f = op.first, simd_distance(f, a) < 60 else { return false }
                return TileProcessor.pointIn(op, end) || TileProcessor.pointIn(op, (a + back) / 2) || TileProcessor.pointIn(op, a)
            }
            if blocked { continue }
            // Across the grass strip only: the sidewalk runs on unchanged.
            // On to a garage out behind the house, when there is one.
            var slab = [back, end]
            if let g = garage(behind: spot, toStreet: toStreet, near: a), let gf = front(g.b) {
                let door = gf.spot + gf.n * 3
                slab = [back, a - toStreet * max(1, simd_dot(spot - door, toStreet) - 0.5), door, gf.spot + gf.n * 0.1]
            }
            drawDrive(kerb: kerb, toStreet: toStreet, edge: e, slab: slab)
            return true
        }
        return false
    }

    /// Garage doors on the wall facing the street (or the one most like it): one 2.5 m door per 3 m of wall, a
    /// row of them for a block of garages.
    private func garageDoors(_ b: BuildingData, poly: [SIMD2<Float>]) {
        guard let f = front(b) else { return }
        // The wall the line to the street leaves through.
        var wall: (SIMD2<Float>, SIMD2<Float>)?
        var bestD = Float.infinity
        for k in 0..<poly.count {
            let a = poly[k], c = poly[(k + 1) % poly.count]
            let d = distanceToSegment(f.spot, a, c)
            if d < bestD { bestD = d; wall = (a, c) }
        }
        guard let (a, c) = wall else { return }
        let len = simd_distance(a, c)
        guard len > 2.6 else { return }
        let along = (c - a) / len
        let count = b.gk == 2 ? max(1, Int(len / 3.1)) : min(2, max(1, Int(len / 3.2)))
        let doorW: Float = min(2.6, len / Float(count) - 0.4)
        let yaw = atan2(f.n.x, -f.n.y)
        let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
        let h = min(2.2, b.h - 0.4)
        for i in 0..<count {
            let mid = a + along * (len * (Float(i) + 0.5) / Float(count)) + f.n * 0.03
            with("garagedoor", at: mid) { kit in
                kit.box(w3(mid, Heights.ground + h / 2), [doorW, h, 0.05], rot: rot)
            }
        }
    }

    /// A driveway as it is in real life: a dipped kerb where it meets the street, concrete across the grass strip,
    /// the sidewalk running on across it unchanged, then a concrete slab level with the sidewalk up beside the house.
    private func drawDrive(kerb k: SIMD2<Float>, toStreet d: SIMD2<Float>, edge e: RoadEdge, slab: [SIMD2<Float>]) {
        let side = SIMD2(-d.y, d.x) * 1.5
        with("drivecon", at: k) { kit in
            // The dipped kerb: a ramp up from the road, in front of the kerb's face.
            let low = k + d * 0.6
            kit.quad(w3(low - side, Heights.road + 0.004), w3(low + side, Heights.road + 0.004),
                     w3(k + side, Heights.sidewalk + 0.006), w3(k - side, Heights.sidewalk + 0.006), outward: [0, 1, 0])
        }
        if e.verge > 0 { ribbon("drivecon", [k, k - d * e.verge], half: 1.5, h: Heights.sidewalk + 0.006) }
        guard slab.count >= 2 else { return }
        ribbon("drivecon", slab, half: 1.5, h: Heights.sidewalk - 0.004)
        // Its edges down to the lawn, like the sidewalk's.
        for s: Float in [-1, 1] { kerb(offsetLine(slab, s * 1.5), facing: s, bottom: Heights.ground - 0.12) }
    }

    /// A driveway mapped as a line from the street: only the part beyond the sidewalk is a slab; where it meets the
    /// street it gets the dipped kerb.
    private func mappedDrive(_ pts: [SIMD2<Float>]) {
        guard pts.count >= 2 else { return }
        // The street it leaves: nearest to its first point.
        var best: (d: Float, e: Int)?
        city.roadGrid.query(pts[0], 25) { item in
            guard item.0 < self.city.edges.count else { return }
            let e = self.city.edges[item.0]
            guard !e.isService else { return }
            let d = distanceToSegment(pts[0], e.pts[item.1], e.pts[item.1 + 1])
            if best == nil || d < best!.d { best = (d, item.0) }
        }
        guard let b = best else {
            if !crossesRoadway(pts) { ribbon("drivecon", pts, half: 1.5, h: Heights.path) }
            return
        }
        let e = city.edges[b.e]
        let reach = e.width / 2 + e.verge + e.walkWidth
        func nearest(_ p: SIMD2<Float>) -> SIMD2<Float> {
            var q = p, bd = Float.infinity
            for j in 0..<(e.pts.count - 1) {
                let c = closestOnSegment(p, e.pts[j], e.pts[j + 1])
                let d = simd_distance(p, c)
                if d < bd { bd = d; q = c }
            }
            return q
        }
        guard let k = pts.firstIndex(where: { simd_distance($0, nearest($0)) > reach }) else { return }
        let q = nearest(pts[k])
        let away = simd_normalize(pts[k] - q)
        let back = q + away * reach
        // On past the back of the house it serves, where the mapped line stops short.
        var slab = [back] + pts[k...]
        if slab.count >= 2, let last = slab.last {
            let dir = simd_normalize(last - slab[slab.count - 2]), across = SIMD2(-dir.y, dir.x)
            var reachBack: Float = 0
            for b in part.buildings where b.x != 1 {
                let poly = points(b.p)
                guard let f = poly.first, simd_distance(f, last) < 40,
                      poly.contains(where: { abs(simd_dot($0 - last, across)) < 9 && simd_dot($0 - last, dir) > -3 }) else { continue }
                reachBack = max(reachBack, poly.map { simd_dot($0 - last, dir) }.max() ?? 0)
            }
            let end = last + dir * min(30, reachBack + 3)
            // Not through a building (a driveway that ends at a garage stops there).
            let through = part.buildings.contains { b in
                guard b.x != 1 else { return false }
                let poly = points(b.p)
                guard let f = poly.first, simd_distance(f, last) < 50 else { return false }
                return [Float(0.25), 0.5, 0.75, 1].contains { TileProcessor.pointIn(poly, last + (end - last) * $0) }
            }
            if reachBack > 0.5 && !through { slab.append(end) }
        }
        // A mapped driveway that runs along or across a street (a garage ramp mapped on the roadway, a line
        // joining both sides) would lay a slab over the road: left out.
        if crossesRoadway(Array(slab.dropFirst())) { return }
        drawDrive(kerb: q + away * (e.width / 2), toStreet: -away, edge: e, slab: slab)
    }

    /// Whether any part of a line lies on a street's roadway (not an alley's), checked every metre.
    private func crossesRoadway(_ line: [SIMD2<Float>]) -> Bool {
        guard line.count >= 1 else { return false }
        var samples: [SIMD2<Float>] = [line[0]]
        for i in 1..<max(1, line.count) where i < line.count {
            let a = line[i - 1], b = line[i]
            let n = max(1, Int(simd_distance(a, b)))
            for k in 1...n { samples.append(a + (b - a) * (Float(k) / Float(n))) }
        }
        for p in samples {
            var on = false
            city.roadGrid.query(p, 12) { item in
                guard !on, item.0 < self.city.edges.count else { return }
                let e = self.city.edges[item.0]
                guard !e.isService else { return }
                if distanceToSegment(p, e.pts[item.1], e.pts[item.1 + 1]) < e.width / 2 + 0.3 { on = true }
            }
            if on { return true }
        }
        return false
    }

    /// A low wall round a flat roof.
    private func parapet(_ poly: [SIMD2<Float>], top h: Float, mat: String) {
        guard let first = poly.first else { return }
        with(mat, at: first) { kit in
            for k in 0..<poly.count {
                let a = poly[k], c = poly[(k + 1) % poly.count]
                let inw = -perpRight(simd_normalize(c - a)) * 0.3
                kit.quad(w3(a + inw, h), w3(c + inw, h), w3(c + inw, h + 0.6), w3(a + inw, h + 0.6),
                         uv: ([0, 0], [1, 0], [1, 0.1], [0, 0.1]), outward: SIMD3(inw.x, 0, -inw.y))
                kit.quad(w3(a, h + 0.6), w3(c, h + 0.6), w3(c + inw, h + 0.6), w3(a + inw, h + 0.6),
                         uv: ([0, 0.95], [1, 0.95], [1, 1], [0, 1]), outward: [0, 1, 0])
                kit.quad(w3(a, h), w3(c, h), w3(c, h + 0.6), w3(a, h + 0.6),
                         uv: ([0, 0.95], [1, 0.95], [1, 1], [0, 1]), outward: SIMD3(-inw.x, 0, inw.y))
            }
        }
    }

    /// A hipped roof: sloping on all four sides up to a short ridge.
    private func hipped(_ g: [Float], eave: Float, mat: String) {
        let f = gableFrame(g)
        let top = eave + f.rh, low = eave - 0.15
        let ridge = max(0, f.ha - f.hb)
        let ra = f.c - f.u * ridge, rb = f.c + f.u * ridge
        let c00 = f.c - f.u * f.ha - f.v * f.hb, c10 = f.c + f.u * f.ha - f.v * f.hb
        let c11 = f.c + f.u * f.ha + f.v * f.hb, c01 = f.c - f.u * f.ha + f.v * f.hb
        with(mat, at: f.c) { kit in
            let up = SIMD3<Float>(0, 1, 0)
            func out(_ d: SIMD2<Float>) -> SIMD3<Float> { simd_normalize(SIMD3(d.x, 0, -d.y) + up) }
            kit.quad(w3(c00, low), w3(c10, low), w3(rb, top), w3(ra, top), uv: (c00 / 1.5, c10 / 1.5, rb / 1.5, ra / 1.5), outward: out(-f.v))
            kit.quad(w3(c11, low), w3(c01, low), w3(ra, top), w3(rb, top), uv: (c11 / 1.5, c01 / 1.5, ra / 1.5, rb / 1.5), outward: out(f.v))
            kit.tri(w3(c10, low), w3(c11, low), w3(rb, top), uv: (c10 / 1.5, c11 / 1.5, rb / 1.5), outward: out(f.u))
            kit.tri(w3(c01, low), w3(c00, low), w3(ra, top), uv: (c01 / 1.5, c00 / 1.5, ra / 1.5), outward: out(-f.u))
        }
    }

    /// A roof that follows a footprint: slopes from every wall up to the outline drawn in by `inset`, and a flat top
    /// on that. Returns false (drawing nothing) when the outline can't be drawn in cleanly, for a flat roof instead.
    private func outlineRoof(_ poly: [SIMD2<Float>], eave: Float, rise: Float, half: Float, mat: String) -> Bool {
        guard poly.count >= 4, let first = poly.first else { return false }
        let ccw = TileProcessor.area(poly) > 0
        func inward(_ d: SIMD2<Float>) -> SIMD2<Float> { ccw ? SIMD2(-d.y, d.x) : SIMD2(d.y, -d.x) }
        var inset = min(2.6, max(0.8, half * 0.8))
        var inner: [SIMD2<Float>] = []
        for _ in 0..<4 {
            inner = poly.indices.map { i in
                let a = poly[(i - 1 + poly.count) % poly.count], p = poly[i], c = poly[(i + 1) % poly.count]
                let n0 = inward(simd_normalize(p - a)), n1 = inward(simd_normalize(c - p))
                var m = n0 + n1
                m = simd_length(m) > 1e-4 ? simd_normalize(m) : n0
                return p + m * inset / max(0.35, simd_dot(m, n0))
            }
            // Clean when every edge still runs the same way and the top keeps the outline's turn.
            let ok = poly.indices.allSatisfy { i in
                let j = (i + 1) % poly.count
                return simd_dot(inner[j] - inner[i], poly[j] - poly[i]) > 0
            } && (TileProcessor.area(inner) > 0) == ccw && abs(TileProcessor.area(inner)) > 2
            if ok { break }
            inset *= 0.6
            inner = []
        }
        guard !inner.isEmpty else { return false }
        let low = eave - 0.15, top = eave + max(0.6, min(rise, inset * 1.0))
        with(mat, at: first) { kit in
            for i in poly.indices {
                let j = (i + 1) % poly.count
                let a = poly[i], b = poly[j], ia = inner[i], ib = inner[j]
                let n = -inward(simd_normalize(b - a))
                let out = simd_normalize(SIMD3(n.x * (top - low), inset, -n.y * (top - low)))
                kit.quad(w3(a, low), w3(b, low), w3(ib, top), w3(ia, top), uv: (a / 1.5, b / 1.5, ib / 1.5, ia / 1.5), outward: out)
            }
            let tris = TileProcessor.earclip(ccw ? inner : inner.reversed())
            let pts = ccw ? inner : inner.reversed()
            for t in stride(from: 0, to: tris.count - 2, by: 3) {
                kit.tri(w3(pts[tris[t]], top), w3(pts[tris[t + 1]], top), w3(pts[tris[t + 2]], top),
                        uv: (pts[tris[t]] / 1.5, pts[tris[t + 1]] / 1.5, pts[tris[t + 2]] / 1.5), outward: [0, 1, 0])
            }
        }
        return true
    }

    /// A pyramid or a dome over the whole footprint.
    private func spire(_ poly: [SIMD2<Float>], eave: Float, height: Float, mat: String) {
        guard let first = poly.first else { return }
        let dome = mat.hasPrefix("copper")
        let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
        let steps = dome ? 4 : 1
        with(mat, at: first) { kit in
            for s in 0..<steps {
                let t0 = Float(s) / Float(steps) * .pi / 2, t1 = Float(s + 1) / Float(steps) * .pi / 2
                let k0 = dome ? cos(t0) : 1, k1 = dome ? cos(t1) : 0
                let y0 = eave + (dome ? sin(t0) : 0) * height, y1 = eave + (dome ? sin(t1) : 1) * height
                for i in 0..<poly.count {
                    let a = poly[i], b = poly[(i + 1) % poly.count]
                    let a0 = c + (a - c) * k0, b0 = c + (b - c) * k0, a1 = c + (a - c) * k1, b1 = c + (b - c) * k1
                    let mid = (a + b) / 2 - c
                    let o = simd_normalize(SIMD3(mid.x, 0, -mid.y) + [0, 1, 0])
                    if k1 < 0.001 {
                        kit.tri(w3(a0, y0), w3(b0, y0), w3(c, y1), uv: (a0 / 1.5, b0 / 1.5, c / 1.5), outward: o)
                    } else {
                        kit.quad(w3(a0, y0), w3(b0, y0), w3(b1, y1), w3(a1, y1), uv: (a0 / 1.5, b0 / 1.5, b1 / 1.5, a1 / 1.5), outward: o)
                    }
                }
            }
        }
    }

    /// Walls all round a footprint between two heights, the texture's bays and storeys laid on whole.
    /// Walls too short for a window (a house's bump-outs and corners) take `plain` when given.
    private func band(_ mat: String, _ poly: [SIMD2<Float>], from y0: Float, to y1: Float, bay: Float, floor: Float, vStart vFrom: Float,
                      plain: String? = nil, shift: SIMD2<Float> = .zero, lit: (look: Int, seed: Int)? = nil, blank: String? = nil) {
        // Long walls aren't windows from end to end: every so often a stretch of blank wall (a stairwell, a
        // service core), drawn in `blank`, breaks them into groups.
        var blanks: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, Float)] = []
        // Whole bays and storeys of shift: the same by day, a different set of lit windows at night.
        let vStart = vFrom + shift.y
        guard y1 > y0 + 0.01, let first = poly.first else { return }
        if let plain {
            let short = (0..<poly.count).filter { simd_distance(poly[$0], poly[($0 + 1) % poly.count]) < 3 }
            with(plain, at: first) { kit in
                for k in short {
                    let a = poly[k], c = poly[(k + 1) % poly.count]
                    guard simd_distance(a, c) > 0.01 else { continue }
                    let out2 = perpRight(simd_normalize(c - a))
                    let len = simd_distance(a, c)
                    kit.quad(w3(a, y0), w3(c, y0), w3(c, y1), w3(a, y1),
                             uv: ([0, vStart], [len / bay, vStart], [len / bay, vStart + (y1 - y0) / floor], [0, vStart + (y1 - y0) / floor]),
                             outward: SIMD3(out2.x, 0, -out2.y))
                }
            }
        }
        with(mat, at: first) { kit in
            var along: Float = 0
            for k in 0..<poly.count {
                let a = poly[k], c = poly[(k + 1) % poly.count]
                let len = simd_distance(a, c)
                guard len > 0.01 else { continue }
                if plain != nil && len < 3 { continue }
                let out2 = perpRight(simd_normalize(c - a))
                // Whole bays only, so windows aren't cut at corners.
                let bays = max(1, (len / bay).rounded())
                let u0 = along + shift.x, u1 = along + shift.x + bays
                let v0 = vStart, v1 = vStart + (y1 - y0) / floor
                if blank != nil && bays >= 10 {
                    // Groups of windows (6 to 8 bays, by the wall) with two blank bays between.
                    let group = 6 + k % 3, cycle = group + 2, n = Int(bays)
                    let start = (n % cycle) / 2
                    var j = 0
                    while j < n {
                        let inBlank = (j - start + cycle * 4) % cycle >= group
                        var r = j + 1
                        while r < n && ((r - start + cycle * 4) % cycle >= group) == inBlank { r += 1 }
                        let p0 = a + (c - a) * (Float(j) / bays), p1 = a + (c - a) * (Float(r) / bays)
                        if inBlank { blanks.append((p0, p1, out2, Float(r - j))) }
                        else {
                            kit.quad(w3(p0, y0), w3(p1, y0), w3(p1, y1), w3(p0, y1),
                                     uv: ([u0 + Float(j), v0], [u0 + Float(r), v0], [u0 + Float(r), v1], [u0 + Float(j), v1]), outward: SIMD3(out2.x, 0, -out2.y))
                        }
                        j = r
                    }
                } else {
                    kit.quad(w3(a, y0), w3(c, y0), w3(c, y1), w3(a, y1),
                             uv: ([u0, v0], [u1, v0], [u1, v1], [u0, v1]), outward: SIMD3(out2.x, 0, -out2.y))
                }
                if let lit { litWindows(a, c, out2, bays: Int(bays), y0: y0, y1: y1, storey: floor, vStart: vStart, look: lit.look, seed: lit.seed &+ Int(along)) }
                along += bays
            }
        }
        if let blank, !blanks.isEmpty {
            with(blank, at: first) { kit in
                for (p0, p1, o, n) in blanks {
                    kit.quad(w3(p0, y0), w3(p1, y0), w3(p1, y1), w3(p0, y1),
                             uv: ([0, vStart], [n, vStart], [n, vStart + (y1 - y0) / floor], [0, vStart + (y1 - y0) / floor]), outward: SIMD3(o.x, 0, -o.y))
                }
            }
        }
    }

    /// At night, glowing panes over a different set of windows on every wall: about a third of them lit.
    private func litWindows(_ a: SIMD2<Float>, _ c: SIMD2<Float>, _ out: SIMD2<Float>, bays: Int, y0: Float, y1: Float, storey: Float,
                            vStart: Float, look: Int, seed: Int) {
        let (x0, x1, wy0, wy1): (Float, Float, Float, Float) = look == 3 ? (0.03, 0.97, 0.04, 0.82)
            : ((4...8).contains(look) ? (0.37, 0.63, 0.24, 0.66) : (0.16, 0.84, 0.2, 0.74))
        let firstFloor = Int(ceil(vStart - 0.001)), lastFloor = Int(floor(vStart + (y1 - y0) / storey + 0.001))
        guard bays > 0, lastFloor > firstFloor else { return }
        let push = out * 0.03
        with("winglow", at: a) { kit in
            for k in 0..<bays {
                for f in firstFloor..<lastFloor {
                    var h = UInt32(truncatingIfNeeded: seed &* 73856093 ^ k &* 19349663 ^ f &* 83492791)
                    h = (h ^ (h >> 13)) &* 1274126177
                    guard h % 100 < 34 else { continue }
                    let pa = a + (c - a) * ((Float(k) + x0) / Float(bays)) + push
                    let pb = a + (c - a) * ((Float(k) + x1) / Float(bays)) + push
                    let ya = y0 + (Float(f) + wy0 - vStart) * storey, yb = y0 + (Float(f) + wy1 - vStart) * storey
                    kit.quad(w3(pa, ya), w3(pb, ya), w3(pb, yb), w3(pa, yb), outward: SIMD3(out.x, 0, -out.y))
                }
            }
        }
    }

    /// Pavement in front of a shop or office, out to the sidewalk.
    private func apron(_ poly: [SIMD2<Float>]) {
        guard poly.count >= 3 else { return }
        ribbon("sidewalk", poly + [poly[0], poly[1]], half: 3.5, offset: 3.4, h: Heights.sidewalk - 0.01)
    }

    private func gableFrame(_ g: [Float]) -> (c: SIMD2<Float>, u: SIMD2<Float>, v: SIMD2<Float>, ha: Float, hb: Float, rh: Float) {
        let c = SIMD2(g[0], g[1]), u = SIMD2(g[2], g[3])
        return (c, u, SIMD2(-u.y, u.x), g[4], g[5], g[6])
    }

    /// The triangular wall ends under a pitched roof.
    private func gable(_ kit: inout MeshKit, _ g: [Float], eave: Float, floor: Float) {
        let f = gableFrame(g)
        let ha = f.ha - 0.35, hb = f.hb - 0.45
        for s: Float in [-1, 1] {
            let e = f.c + f.u * ha * s
            let a = e - f.v * hb, b = e + f.v * hb
            let top = w3(e, eave + f.rh * (hb / f.hb))
            let out2 = f.u * s
            kit.tri(w3(a, eave), w3(b, eave), top, uv: ([0, eave / floor], [2 * hb / 3, eave / floor], [hb / 3, (eave + f.rh) / floor]),
                    outward: SIMD3(out2.x, 0, -out2.y))
        }
    }

    private func roof(_ g: [Float], eave: Float, mat: String) {
        let f = gableFrame(g)
        let ridgeA = f.c - f.u * f.ha, ridgeB = f.c + f.u * f.ha
        let top = eave + f.rh
        let low = eave - 0.15
        with(mat, at: f.c) { kit in
            for s: Float in [-1, 1] {
                let ea = ridgeA + f.v * f.hb * s, eb = ridgeB + f.v * f.hb * s
                let slope = sqrt(f.hb * f.hb + f.rh * f.rh)
                let out2 = f.v * s
                kit.quad(w3(ea, low), w3(eb, low), w3(ridgeB, top), w3(ridgeA, top),
                         uv: ([0, 0], [f.ha * 2 / 1.5, 0], [f.ha * 2 / 1.5, slope / 1.5], [0, slope / 1.5]),
                         outward: simd_normalize(SIMD3(out2.x * f.rh, f.hb, -out2.y * f.rh)))
                // Underside, seen from the street below the eaves.
                kit.quad(w3(ea, low - 0.05), w3(eb, low - 0.05), w3(ridgeB, top - 0.05), w3(ridgeA, top - 0.05),
                         uv: ([0, 0], [0.1, 0], [0.1, 0.1], [0, 0.1]), outward: [0, -1, 0])
            }
        }
    }

    // MARK: Signs

    /// Sign faces waiting for the atlas: cell, centre, yaw, size.
    private var faces: [(cell: Int, at: SIMD3<Float>, yaw: Float, w: Float, h: Float)] = []
    private var atlas = TextAtlas()
    private var atlasKey: UInt64?
    private var atlasImage: CGImage?

    /// Lays out every sign's lettering in the atlas (drawing or loading its picture unless the main thread already
    /// has it) and lays the sign faces in the batches.
    private func lettering() {
        guard !atlas.cells.isEmpty else { return }
        let key = atlas.layout()
        atlasKey = key
        if !TextAtlas.hasTexture(key) { atlasImage = atlas.image(key) }
        for f in faces {
            with("atlas", at: SIMD2(f.at.x, -f.at.z)) { kit in
                atlas.quad(f.cell, into: &kit, center: f.at, yaw: f.yaw, width: f.w, height: f.h, back: false)
            }
        }
        faces = []
        for (spot, fs) in pieceFaces {
            for f in fs {
                atlas.quad(f.cell, into: &pieceKits[spot, default: [:]]["atlas", default: MeshKit()], center: f.at, yaw: f.yaw, width: f.w, height: f.h, back: false)
            }
        }
        pieceFaces = [:]
        // Stop signs: a red octagon showing the STOP cell.
        for f in stopFaces {
            let (lo, hi) = atlas.uv(f.cell)
            let rot = simd_quatf(angle: f.yaw, axis: [0, 1, 0])
            let r: Float = 0.36
            var kit = pieceKits[f.spot, default: [:]]["atlas", default: MeshKit()]
            func corner(_ k: Int) -> (SIMD3<Float>, SIMD2<Float>) {
                let a = Float.pi / 8 + Float(k) * .pi / 4
                let x = cos(a) * r, y = sin(a) * r
                return (f.at + rot.act([x, y, 0]), [lo.x + (hi.x - lo.x) * (x / (2 * r) + 0.5), lo.y + (hi.y - lo.y) * (y / (2 * r) + 0.5)])
            }
            let mid = SIMD2((lo.x + hi.x) / 2, (lo.y + hi.y) / 2)
            for k in 0..<8 {
                let (p0, t0) = corner(k), (p1, t1) = corner(k + 1)
                kit.tri(f.at, p0, p1, uv: (mid, t0, t1), outward: rot.act([0, 0, 1]))
            }
            pieceKits[f.spot, default: [:]]["atlas"] = kit
        }
        stopFaces = []
    }

    /// A flat octagon (corners at 22.5° and every 45°), facing +z of `rot`, or −z for its back.
    static func octagon(_ kit: inout MeshKit, _ c: SIMD3<Float>, _ rot: simd_quatf, r: Float, back: Bool) {
        let n = rot.act([0, 0, back ? -1 : 1])
        for k in 0..<8 {
            let a0 = Float.pi / 8 + Float(k) * .pi / 4, a1 = a0 + .pi / 4
            kit.tri(c, c + rot.act([cos(a0) * r, sin(a0) * r, 0]), c + rot.act([cos(a1) * r, sin(a1) * r, 0]), outward: n)
        }
    }

    /// Stop signs at the crossings where traffic stops: on the right of each street arriving, before the crossing.
    private func stopSigns() {
        for ei in part.edges {
            let e = city.edges[ei]
            guard !e.isService else { continue }
            for (end, flagged) in [(e.a, e.stops.0), (e.b, e.stops.1)] {
                guard end < city.nodes.count else { continue }
                let node = city.nodes[end]
                guard !node.signal, flagged || node.allStop, node.edges.count >= 3 else { continue }
                if e.oneway && e.a == end { continue }     // nobody arrives this way
                let out = e.outward(from: end)
                let right = perpRight(-out) * CityConfig.current.style.side
                let pole = node.pos + out * (node.radius + 3.5) + right * (e.width / 2 + 0.7)
                posts.append((pole, 0.1, 1))
                let spot = City.spot(pole)
                if city.fallen.contains(spot) { continue }
                piece = spot
                defer { piece = nil }
                let yaw = atan2(out.x, -out.y)        // facing the traffic coming in
                let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
                let center = w3(pole, Heights.sidewalk + 2.2)
                with("pole", at: pole) { kit in
                    kit.post(w3(pole, Heights.sidewalk), radius: 0.035, height: 2.0, segments: 6)
                }
                // The sign's white rim in front, its plain grey back behind.
                with("white", at: pole) { kit in Self.octagon(&kit, center + rot.act([0, 0, -0.022]), rot, r: 0.4, back: false) }
                with("pole", at: pole) { kit in Self.octagon(&kit, center + rot.act([0, 0, -0.03]), rot, r: 0.4, back: true) }
                let cell = atlas.cell("STOP", background: NSColor(red: 0.78, green: 0.06, blue: 0.08, alpha: 1), ink: .white, maxAspect: 1)
                stopFaces.append((spot, cell, center + rot.act([0, 0, -0.015]), yaw))
            }
        }
    }

    /// A brand's colours: the canopy's band and sign, and the lettering on them.
    static func brandColours(_ name: String) -> (band: SIMD3<Float>, ink: SIMD3<Float>) {
        // One of a few strong colours, picked by the station's name, so each brand keeps its own look everywhere.
        let palette: [(SIMD3<Float>, SIMD3<Float>)] = [
            ([0.75, 0.1, 0.12], [1, 1, 1]), ([0.0, 0.5, 0.28], [1, 1, 1]), ([0.1, 0.24, 0.6], [1, 1, 1]),
            ([0.98, 0.78, 0.08], [0.1, 0.1, 0.12]), ([0.95, 0.45, 0.05], [1, 1, 1]), ([0.12, 0.12, 0.14], [1, 0.85, 0.1]),
        ]
        var h: UInt32 = 2166136261
        for b in name.lowercased().utf8 { h = (h ^ UInt32(b)) &* 16777619 }
        return palette[Int(h % UInt32(palette.count))]
    }

    /// Gas stations: a flat canopy on columns, lit underneath, a band in the brand's colours with its name on both
    /// long sides, pump islands under it, and a tall sign by the street.
    private func fuelStations() {
        for f in part.fuel {
            let c = SIMD2(f.x, f.y), u = simd_normalize(SIMD2(f.ax, f.ay)), v = SIMD2(-u.y, u.x)
            let colours = Self.brandColours(f.n)
            let band = Self.tinted("paint", [colours.band.x, colours.band.y, colours.band.z])
            let yaw = atan2(u.y, u.x)
            let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
            let top: Float = Heights.ground + 5.4
            with("canopy", at: c) { kit in kit.box(w3(c, top - 0.25), [2 * f.hl, 0.06, 2 * f.hw], rot: rot) }
            with(band, at: c) { kit in kit.box(w3(c, top + 0.1), [2 * f.hl + 0.1, 0.7, 2 * f.hw + 0.1], rot: rot) }
            // Islands across the canopy, a column and two pumps each.
            let islands = max(2, Int(f.hl * 2 / 6.5))
            let rows: [Float] = f.hw > 6 ? [-f.hw / 2, f.hw / 2] : [0]
            for i in 0..<islands {
                let along = -f.hl + (Float(i) + 0.5) * (2 * f.hl / Float(islands))
                for r in rows {
                    let p = c + u * along + v * r
                    with("kerb", at: p) { kit in kit.box(w3(p, Heights.ground + 0.1), [1.1, 0.2, 4.2], rot: rot) }
                    with("pole", at: p) { kit in kit.post(w3(p, Heights.ground + 0.2), radius: 0.16, height: top - 0.45, segments: 8) }
                    for s: Float in [-1.3, 1.3] {
                        let q = p + v * s
                        with("pump", at: q) { kit in kit.box(w3(q, Heights.ground + 0.2 + 0.85), [0.75, 1.7, 0.5], rot: rot) }
                        with("signal", at: q) { kit in kit.box(w3(q, Heights.ground + 1.55), [0.77, 0.35, 0.3], rot: rot) }
                    }
                    posts.append((p, 0.7, 0))
                    posts.append((p + v * 1.3, 0.45, 0))
                    posts.append((p - v * 1.3, 0.45, 0))
                }
            }
            // The name on the band, both long sides.
            let cell = atlas.cell(f.n.uppercased(), background: NSColor(red: CGFloat(colours.band.x), green: CGFloat(colours.band.y), blue: CGFloat(colours.band.z), alpha: 1),
                                  ink: NSColor(red: CGFloat(colours.ink.x), green: CGFloat(colours.ink.y), blue: CGFloat(colours.ink.z), alpha: 1), maxAspect: 8)
            let h: Float = 0.6
            let w = min(2 * f.hl - 1, Float(TextAtlas.width(f.n.uppercased()) + 28) / 64 * h)
            for side: Float in [-1, 1] {
                let n = v * side
                let faceYaw = atan2(n.x, -n.y)
                faces.append((cell, w3(c + n * (f.hw + 0.07), top + 0.1), faceYaw, w, h))
            }
            // The sign by the street: a tall post with the brand panel and a price panel under it.
            let sp = c + u * (f.hl + 4) + v * (f.hw + 2)
            with("pole", at: sp) { kit in kit.post(w3(sp, Heights.ground), radius: 0.18, height: 6.5, segments: 8) }
            with(band, at: sp) { kit in kit.box(w3(sp, Heights.ground + 6.6), [2.4, 1.4, 0.35], rot: rot) }
            with("pump", at: sp) { kit in kit.box(w3(sp, Heights.ground + 5.4), [2.2, 1.0, 0.3], rot: rot) }
            for side: Float in [-1, 1] {
                let n = v * side
                faces.append((cell, w3(sp + n * 0.19, Heights.ground + 6.6), atan2(n.x, -n.y), 2.1, 0.5))
            }
            posts.append((sp, 0.25, 0))
        }
    }

    /// Overhead wires between utility poles, sagging a little.
    private func wires() {
        for w in part.wires where w.count >= 4 {
            let a = SIMD2(w[0], w[1]), b = SIMD2(w[2], w[3])
            let d = b - a
            guard simd_length(d) > 1 else { continue }
            let side = simd_normalize(perpRight(d))
            with("wire", at: a) { kit in
                for off: Float in [-0.9, 0.9] {
                    var prev = w3(a + side * off, 9.06 + Heights.sidewalk)
                    for k in 1...6 {
                        let t = Float(k) / 6
                        let p = w3(a + d * t + side * off, 9.06 + Heights.sidewalk - 0.7 * 4 * t * (1 - t))
                        let mid = (prev + p) / 2, dir = p - prev
                        let yaw = atan2(dir.x, dir.z), pitch = atan2(dir.y, simd_length(SIMD2(dir.x, dir.z)))
                        kit.box(mid, [0.03, 0.03, simd_length(dir)], rot: simd_quatf(angle: yaw, axis: [0, 1, 0]) * simd_quatf(angle: -pitch, axis: [1, 0, 0]))
                        prev = p
                    }
                }
            }
        }
    }

    private func streetSigns() {
        for ni in part.nodes {
            let n = city.nodes[ni]
            let roads = n.edges.filter { !city.edges[$0].isService && !city.edges[$0].name.isEmpty }
            guard roads.count >= 2, n.edges.count >= 3 || Set(roads.map { city.edges[$0].name }).count >= 2 else { continue }
            let names = Set(roads.map { signName(city.edges[$0].name) })
            guard names.count >= 2 else { continue }
            let dirs = roads.map { (e: $0, d: city.edges[$0].outward(from: ni)) }
                .sorted { atan2($0.d.y, $0.d.x) < atan2($1.d.y, $1.d.x) }
            var pick: (Int, Int)?
            for i in 0..<dirs.count {
                let a = dirs[i], b = dirs[(i + 1) % dirs.count]
                if signName(city.edges[a.e].name) != signName(city.edges[b.e].name) { pick = (a.e, b.e); break }
            }
            guard let (ea, eb) = pick else { continue }
            let da = city.edges[ea].outward(from: ni), db = city.edges[eb].outward(from: ni)
            var bis = da + db
            bis = simd_length(bis) > 0.1 ? simd_normalize(bis) : perpRight(da)
            let half = acos(max(-1, min(1, simd_dot(da, db)))) / 2
            let need = max(city.edges[ea].width, city.edges[eb].width) / 2 + 2.0
            let dist = min(28, need / max(0.35, sin(half)))
            let p = n.pos + bis * dist
            posts.append((p, 0.15, 1))
            let spot = City.spot(p)
            if city.fallen.contains(spot) { continue }
            piece = spot
            defer { piece = nil }
            with("pole", at: p) { kit in kit.post(w3(p, Heights.sidewalk), radius: 0.06, height: 3.5) }
            for (k, e) in [ea, eb].enumerated() {
                let d = city.edges[e].outward(from: ni)
                let yaw = atan2(d.y, d.x)
                let y = Heights.sidewalk + 3.0 + Float(k) * 0.32
                let label = signName(city.edges[e].name)
                let style = CityConfig.current.style
                let cell = atlas.cell(label, background: NSColor(red: CGFloat(style.signColour.x), green: CGFloat(style.signColour.y), blue: CGFloat(style.signColour.z), alpha: 1),
                                      ink: NSColor(red: CGFloat(style.signInk.x), green: CGFloat(style.signInk.y), blue: CGFloat(style.signInk.z), alpha: 1), maxAspect: 9.6)
                let h: Float = 0.27
                let at = w3(p, y)
                // Width follows the lettering; laid out once the atlas is built, so measure here the same way.
                let w = min(2.6, Float(TextAtlas.width(label) + 28) / 64 * h)
                with("blade", at: p) { kit in
                    kit.box(at, [w, h, 0.025], rot: simd_quatf(angle: yaw, axis: [0, 1, 0]))
                }
                for side: Float in [0, .pi] {
                    let r = simd_quatf(angle: yaw + side, axis: [0, 1, 0])
                    pieceFaces[spot, default: []].append((cell, at + r.act([0, 0, 0.014]), yaw + side, w, h))
                }
            }
        }
    }

    private func shopSigns() {
        for (i, s) in part.shops.enumerated() {
            let p = SIMD2(s.x, s.y)
            let yaw = atan2(s.dx, -s.dy)
            let at = w3(p, s.z)
            let h: Float = 0.62
            let w = min(6.6, Float(TextAtlas.width(s.n) + 28) / 64 * h)
            let style = s.n.unicodeScalars.reduce(0) { $0 &+ Int($1.value) } % Self.plaques.count
            let gold = i % 4 == 0
            let push = SIMD3(s.dx, 0, -s.dy) * 0.06
            with("plaque\(style)", at: p) { kit in
                kit.box(at + push, [w, h, 0.1], rot: simd_quatf(angle: yaw, axis: [0, 1, 0]))
            }
            let ink = gold ? NSColor(red: 0.95, green: 0.8, blue: 0.45, alpha: 1) : NSColor.white
            let cell = atlas.cell(s.n, background: Self.plaques[style], ink: ink, maxAspect: CGFloat(w / h))
            let r = simd_quatf(angle: yaw, axis: [0, 1, 0])
            faces.append((cell, at + push + r.act([0, 0, 0.056]), yaw, w, h))
        }
    }

    // MARK: Traffic signals

    /// The way the crossing's biggest street runs (Traffic.signalAxis, from the snapshot).
    private func signalAxis(_ n: Int) -> SIMD2<Float> {
        let node = city.nodes[n]
        guard let main = node.edges.max(by: { city.edges[$0].rank < city.edges[$1].rank }) else { return [0, 1] }
        return city.edges[main].outward(from: n)
    }

    private func trafficSignals() {
        for ni in part.nodes where city.nodes[ni].signal {
            let n = city.nodes[ni]
            let axis = signalAxis(ni)
            for ei in n.edges {
                let e = city.edges[ei]
                if e.isService { continue }
                let out2 = e.outward(from: ni)
                // Traffic comes in along this edge towards the node unless it's one way out of it.
                if e.oneway && e.a == ni { continue }
                let heading = -out2
                let right = perpRight(heading)
                let group = abs(simd_dot(out2, axis)) > 0.707 ? 0 : 1
                let pole = n.pos + out2 * (n.radius + 6.5) + right * (e.width / 2 + 1.0)
                posts.append((pole, 0.2, 2))
                let spot = City.spot(pole)
                if city.fallen.contains(spot) { continue }
                piece = spot
                defer { piece = nil }
                var lampKits = [MeshKit(), MeshKit(), MeshKit()]
                let armLen = max(2.5, e.width / 2 + 1.0 - (e.oneway ? 0 : e.driveWidth / 4) + 0.2)
                let yaw = atan2(out2.x, -out2.y)    // lamp faces back along the edge, towards the traffic
                let base = w3(pole, Heights.sidewalk)
                with("pole", at: pole) { kit in
                    kit.post(base, radius: 0.13, height: 6.2)
                    let armEnd = pole - right * armLen
                    let mid = (pole + armEnd) / 2
                    kit.box(w3(mid, Heights.sidewalk + 6.0), [armLen, 0.12, 0.12], rot: simd_quatf(angle: atan2(right.y, right.x), axis: [0, 1, 0]))
                }
                let heads = [pole - right * armLen, pole - right * (armLen * 0.45)]
                for hp in heads {
                    let top: Float = Heights.sidewalk + 5.95
                    let center = w3(hp, top - 0.55)
                    let rot = simd_quatf(angle: yaw, axis: [0, 1, 0])
                    with("signal", at: hp) { kit in
                        kit.box(center, [0.36, 1.05, 0.28], rot: rot)
                        kit.box(center + rot.act([0, 0, -0.16]), [0.5, 1.2, 0.03], rot: rot)
                    }
                    for c in 0..<3 {
                        let lp = center + rot.act(SIMD3(0, 0.32 - Float(c) * 0.32, 0.15))
                        lampKits[c].blob(lp, radius: 0.12, scale: [1, 1, 0.4], segments: 10, rings: 4)
                    }
                }
                pieceLamps[spot] = (ni, group, lampKits)
            }
            signalNodes.append(ni)
        }
    }
}
