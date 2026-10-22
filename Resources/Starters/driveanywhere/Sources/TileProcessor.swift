import Foundation
import simd

// Turning OpenStreetMap data into roads, buildings, parks, shops, parked cars and trees, off the main thread: for
// the downtown built when a city is first opened, and for every tile streamed in round it, by the same rules.

enum MapGeo {
    static var lat0: Double { CityConfig.current.lat }
    static var lon0: Double { CityConfig.current.lon }
    static var kx: Double { cos(lat0 * .pi / 180) * 111320.0 }
    static let ky = 110950.0
    static func local(lat: Double, lon: Double) -> SIMD2<Float> { SIMD2(Float((lon - lon0) * kx), Float((lat - lat0) * ky)) }
    static func latLon(_ p: SIMD2<Float>) -> (lat: Double, lon: Double) { (lat0 + Double(p.y) / ky, lon0 + Double(p.x) / kx) }
}

struct TileEdge: Sendable {
    let a: Int64, b: Int64
    let pts: [SIMD2<Float>]
    let name: String, type: String
    let width: Float, driveWidth: Float
    let lanes: Int, oneway: Bool
    let parking: (Bool, Bool)
    var sidewalks: (Bool, Bool) = (true, true)
    var stops: (Bool, Bool) = (false, false)
}

struct TileOutput: @unchecked Sendable {
    var edges: [TileEdge] = []
    var signals: [Int64] = []
    var buildings: [BuildingData] = []
    var grass: [AreaData] = []
    var lots: [AreaData] = []
    var paths: [PathData] = []
    var shops: [ShopData] = []
    var parked: [[Float]] = []
    var trees: [[Float]] = []
    /// Neighbourhood and suburb names, where OpenStreetMap puts them.
    var places: [PlaceData] = []
    /// Gas stations: where their canopy goes and whose they are.
    var fuel: [FuelData] = []
    /// Crossings that are all-way stops.
    var allStops: [Int64] = []
    /// Street furniture: kind, x, y, heading; and overhead wires: x1, y1, x2, y2.
    var furniture: [[Float]] = []
    var wires: [[Float]] = []
}

/// Reads the map API's XML: nodes with their tags, ways with their node lists and tags.
final class OSMReader: NSObject, XMLParserDelegate {
    var nodes: [Int64: SIMD2<Float>] = [:]
    var nodeTags: [Int64: [String: String]] = [:]
    var ways: [(id: Int64, nds: [Int64], tags: [String: String])] = []
    var wayIndex: [Int64: Int] = [:]
    /// Relations: their members (type, ref, role) and tags.
    var relations: [(members: [(type: String, ref: Int64, role: String)], tags: [String: String])] = []
    private var current: (kind: Int, id: Int64, nds: [Int64], tags: [String: String])?
    private var members: [(type: String, ref: Int64, role: String)] = []

    static func read(_ data: Data) -> OSMReader {
        let r = OSMReader()
        let p = XMLParser(data: data)
        p.delegate = r
        p.parse()
        for (i, w) in r.ways.enumerated() { r.wayIndex[w.id] = i }
        return r
    }

    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes a: [String: String] = [:]) {
        switch name {
        case "node":
            guard let id = a["id"].flatMap(Int64.init), let lat = a["lat"].flatMap(Double.init), let lon = a["lon"].flatMap(Double.init) else { return }
            nodes[id] = MapGeo.local(lat: lat, lon: lon)
            current = (0, id, [], [:])
        case "way":
            current = (1, a["id"].flatMap(Int64.init) ?? 0, [], [:])
        case "nd":
            if let r = a["ref"].flatMap(Int64.init) { current?.nds.append(r) }
        case "tag":
            if let k = a["k"], let v = a["v"] { current?.tags[k] = v }
        case "relation":
            current = (2, a["id"].flatMap(Int64.init) ?? 0, [], [:])
            members = []
        case "member":
            if let t = a["type"], let r = a["ref"].flatMap(Int64.init) { members.append((t, r, a["role"] ?? "")) }
        default: break
        }
    }

    func parser(_ parser: XMLParser, didEndElement name: String, namespaceURI: String?, qualifiedName: String?) {
        guard let c = current else { return }
        if name == "node" && c.kind == 0 {
            if !c.tags.isEmpty { nodeTags[c.id] = c.tags }
            current = nil
        } else if name == "way" && c.kind == 1 {
            ways.append((c.id, c.nds, c.tags))
            current = nil
        } else if name == "relation" && c.kind == 2 {
            relations.append((members, c.tags))
            current = nil
        }
    }
}

enum TileProcessor {
    static let drive: [String: Int] = ["motorway": 4, "trunk": 4, "primary": 4, "secondary": 2, "tertiary": 2, "unclassified": 2,
                                       "residential": 2, "living_street": 2, "service": 1, "primary_link": 1, "secondary_link": 1,
                                       "tertiary_link": 1, "trunk_link": 1, "motorway_link": 1]
    static let laneWidth: [String: Float] = ["primary": 3.4, "secondary": 3.3, "tertiary": 3.2, "residential": 3.0, "service": 3.0]
    static let houseKinds: Set<String> = ["house", "detached", "semidetached_house", "garage", "shed", "residential", "bungalow",
                                          "terrace", "carport", "garages", "hut"]

    static func number(_ s: String?) -> Float? {
        guard let s else { return nil }
        let scan = s.replacingOccurrences(of: ",", with: ".")
        var digits = ""
        for ch in scan.drop(while: { $0 == " " }) { if ch.isNumber || ch == "." { digits.append(ch) } else { break } }
        guard var v = Float(digits) else { return nil }
        if s.contains("'") || s.contains("ft") { v *= 0.3048 }
        return v
    }

    static func hash(_ a: Int, _ b: Int, _ c: Int = 0) -> Int {
        var h = UInt32(truncatingIfNeeded: a &* 73856093 ^ b &* 19349663 ^ c &* 83492791)
        h = (h ^ (h >> 13)) &* 1274126177
        return Int(h >> 1)
    }

    // MARK: Geometry

    static func area(_ p: [SIMD2<Float>]) -> Float {
        var a: Float = 0
        for i in 0..<p.count { let q = p[i], r = p[(i + 1) % p.count]; a += q.x * r.y - r.x * q.y }
        return a / 2
    }

    static func simplify(_ poly: [SIMD2<Float>], _ tol: Float = 0.25) -> [SIMD2<Float>] {
        var pts = poly
        var changed = true
        while changed && pts.count > 3 {
            changed = false
            for i in 0..<pts.count {
                let a = pts[(i - 1 + pts.count) % pts.count], b = pts[i], c = pts[(i + 1) % pts.count]
                let d = c - a
                let l = simd_length(d)
                let dev = l > 1e-6 ? abs(cross2(b - a, d)) / l : 0
                if dev < tol || simd_distance(a, b) < 0.15 { pts.remove(at: i); changed = true; break }
            }
        }
        return pts
    }

    static func pointIn(_ poly: [SIMD2<Float>], _ p: SIMD2<Float>) -> Bool {
        var c = false
        var j = poly.count - 1
        for i in 0..<poly.count {
            let a = poly[i], b = poly[j]
            if (a.y > p.y) != (b.y > p.y) && p.x < (b.x - a.x) * (p.y - a.y) / (b.y - a.y) + a.x { c.toggle() }
            j = i
        }
        return c
    }

    /// A multipolygon relation's outer rings, each with the inner rings inside it.
    static func multipolygon(_ osm: OSMReader, _ members: [(type: String, ref: Int64, role: String)]) -> [(outer: [SIMD2<Float>], holes: [[SIMD2<Float>]])] {
        func ways(_ inner: Bool) -> [[Int64]] {
            members.filter { $0.type == "way" && ($0.role == "inner") == inner }.compactMap { m in osm.wayIndex[m.ref].map { osm.ways[$0].nds } }
        }
        func coords(_ ring: [Int64]) -> [SIMD2<Float>] { ring.dropLast().compactMap { osm.nodes[$0] } }
        let outers = MapShapes.joinRings(ways(false)).map(coords).filter { $0.count >= 3 }
        let inners = MapShapes.joinRings(ways(true)).map(coords).filter { $0.count >= 3 }
        return outers.map { o in (o, inners.filter { pointIn(o, $0[0]) }) }
    }

    static func earclip(_ poly: [SIMD2<Float>]) -> [Int] {
        var idx = Array(poly.indices)
        var tris: [Int] = []
        func cr(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { cross2(a - o, b - o) }
        var guardCount = 0
        while idx.count > 3 && guardCount < 10000 {
            guardCount += 1
            var found = false
            for k in 0..<idx.count {
                let i0 = idx[(k - 1 + idx.count) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = poly[i0], b = poly[i1], c = poly[i2]
                if cr(a, b, c) <= 1e-9 { continue }
                var ok = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    let p = poly[j]
                    if cr(a, b, p) >= 0 && cr(b, c, p) >= 0 && cr(c, a, p) >= 0 { ok = false; break }
                }
                if ok { tris += [i0, i1, i2]; idx.remove(at: k); found = true; break }
            }
            if !found { break }
        }
        if idx.count == 3 { tris += idx } else if idx.count > 3 { for k in 1..<(idx.count - 1) { tris += [idx[0], idx[k], idx[k + 1]] } }
        return tris
    }

    /// Smallest rectangle round a footprint: centre, long axis, half length, half width.
    static func obb(_ poly: [SIMD2<Float>]) -> (SIMD2<Float>, SIMD2<Float>, Float, Float) {
        var best: (Float, SIMD2<Float>, SIMD2<Float>, Float, Float)?
        for i in 0..<poly.count {
            let d = poly[(i + 1) % poly.count] - poly[i]
            let l = simd_length(d)
            if l < 1e-4 { continue }
            let u = d / l, v = SIMD2(-u.y, u.x)
            let a = poly.map { simd_dot($0, u) }, b = poly.map { simd_dot($0, v) }
            let ar = (a.max()! - a.min()!) * (b.max()! - b.min()!)
            if best == nil || ar < best!.0 {
                let ca = (a.max()! + a.min()!) / 2, cb = (b.max()! + b.min()!) / 2
                best = (ar, u * ca + v * cb, u, (a.max()! - a.min()!) / 2, (b.max()! - b.min()!) / 2)
            }
        }
        guard var b = best else { return (poly[0], [1, 0], 1, 1) }
        if b.4 > b.3 { b.2 = SIMD2(-b.2.y, b.2.x); swap(&b.3, &b.4) }
        return (b.1, b.2, b.3, b.4)
    }

    static func flat(_ p: [SIMD2<Float>]) -> [Float] { p.flatMap { [($0.x * 100).rounded() / 100, ($0.y * 100).rounded() / 100] } }

    // MARK: The tile

    /// Everything in the tile `rect` (min, max) that isn't in the bundled area `bundled` (half extents).
    /// `bundled`: the downtown's half size, left out of a streamed tile; nil when building the downtown itself.
    static func process(_ osm: OSMReader, rect: (SIMD2<Float>, SIMD2<Float>), bundled: SIMD2<Float>?) -> TileOutput {
        var out = TileOutput()
        let downtown = bundled == nil
        func owned(_ p: SIMD2<Float>) -> Bool {
            guard p.x >= rect.0.x && p.x < rect.1.x && p.y >= rect.0.y && p.y < rect.1.y else { return false }
            if let b = bundled, abs(p.x) <= b.x && abs(p.y) <= b.y { return false }
            return true
        }
        let nodes = osm.nodes

        // Roads.
        var usage: [Int64: Int] = [:]
        var runs: [(ids: [Int64], tags: [String: String], oneway: Bool)] = []
        for w in osm.ways {
            guard let hw = w.tags["highway"], drive[hw] != nil, w.tags["area"] != "yes" else { continue }
            if hw == "service" && ["parking_aisle", "driveway", "drive-through", "emergency_access"].contains(w.tags["service"] ?? "") { continue }
            if hw == "service" && ["private", "no"].contains(w.tags["access"] ?? "") { continue }
            if ["yes", "building_passage"].contains(w.tags["tunnel"] ?? "") { continue }
            let ids = w.nds.filter { nodes[$0] != nil }
            for i in ids { usage[i, default: 0] += 1 }
            var ow = ["yes", "1", "true"].contains(w.tags["oneway"] ?? "") || w.tags["junction"] == "roundabout" || hw == "motorway"
            let rev = w.tags["oneway"] == "-1"
            var cur: [Int64] = []
            var mine: [[Int64]] = []
            for k in 0..<max(0, ids.count - 1) {
                if owned(nodes[ids[k]]!) {
                    if cur.isEmpty { cur = [ids[k]] }
                    cur.append(ids[k + 1])
                } else {
                    if cur.count > 1 { mine.append(cur) }
                    cur = []
                }
            }
            if cur.count > 1 { mine.append(cur) }
            for var run in mine {
                if rev { run.reverse(); ow = true }
                runs.append((run, w.tags, ow))
                usage[run[0], default: 0] += 1
                usage[run[run.count - 1], default: 0] += 1
            }
        }
        for (run, t, ow) in runs {
            let hw = t["highway"]!
            let base = hw.replacingOccurrences(of: "_link", with: "")
            var lanes = Int(number(t["lanes"]) ?? 0)
            if lanes == 0 {
                lanes = (ow && ["residential", "service", "tertiary", "unclassified"].contains(base)) || hw.hasSuffix("_link") ? 1 : (drive[hw] ?? 2)
            }
            if hw == "service" { lanes = ow ? 1 : 2 }
            lanes = max(1, lanes)
            var (pl, pr) = parking(t, base)
            if hw == "service" { pl = false; pr = false }
            let lw: Float = hw == "service" ? 2.8 : (laneWidth[base] ?? 3.2)
            let dw = Float(lanes) * lw
            var total = dw + 2.3 * Float((pl ? 1 : 0) + (pr ? 1 : 0))
            if let w = number(t["width"]), w > 3, w < 40 { total = max(w, dw) }
            if hw == "service" { total = min(total, 6) }
            var start = 0
            for k in 1..<run.count where usage[run[k], default: 0] >= 2 || k == run.count - 1 {
                let seg = Array(run[start...k])
                let pts = seg.map { nodes[$0]! }
                var length: Float = 0
                for j in 1..<pts.count { length += simd_distance(pts[j], pts[j - 1]) }
                if length > 0.5 {
                    out.edges.append(TileEdge(a: seg[0], b: seg[seg.count - 1], pts: pts, name: t["name"] ?? "",
                                              type: hw == "service" ? "service" : base, width: total, driveWidth: dw,
                                              lanes: lanes, oneway: ow, parking: (pl, pr), sidewalks: sidewalks(t)))
                }
                start = k
            }
        }

        // Signals at the crossings they control.
        var degree: [Int64: Int] = [:]
        var endPos: [Int64: SIMD2<Float>] = [:]
        for e in out.edges { degree[e.a, default: 0] += 1; degree[e.b, default: 0] += 1; endPos[e.a] = e.pts[0]; endPos[e.b] = e.pts[e.pts.count - 1] }
        for (id, t) in osm.nodeTags where t["highway"] == "traffic_signals" {
            guard let p = nodes[id], owned(p) else { continue }
            var best: (Int64, Float)?
            for (n, q) in endPos where degree[n, default: 0] >= 3 {
                let d = simd_distance(p, q)
                if d < 30 && (best == nil || d < best!.1) { best = (n, d) }
            }
            if let b = best { out.signals.append(b.0) }
        }

        // Stop signs: on the street arriving at the crossing they stand by (all of them for a four-way stop).
        for (id, t) in osm.nodeTags where t["highway"] == "stop" {
            guard let p = nodes[id], owned(p) else { continue }
            var best: (Int64, Float)?
            for (n, q) in endPos where degree[n, default: 0] >= 3 {
                let d = simd_distance(p, q)
                if d < 25 && (best == nil || d < best!.1) { best = (n, d) }
            }
            guard let (n, d) = best else { continue }
            if t["stop"] == "all" { out.allStops.append(n); continue }
            let ends = out.edges.indices.filter { out.edges[$0].a == n || out.edges[$0].b == n }
            func dist(_ k: Int) -> Float {
                let e = out.edges[k]
                return (0..<(e.pts.count - 1)).map { distanceToSegment(p, e.pts[$0], e.pts[$0 + 1]) }.min() ?? .infinity
            }
            var chosen: [Int]
            if d < 1.5 {
                // Mapped on the crossing itself: the smaller streets stop.
                let lowest = ends.map { out.edges[$0].type == "residential" || out.edges[$0].type == "unclassified" ? 0 : 1 }.min() ?? 0
                chosen = ends.filter { (out.edges[$0].type == "residential" || out.edges[$0].type == "unclassified" ? 0 : 1) == lowest }
                if chosen.count == ends.count { out.allStops.append(n); continue }
            } else {
                chosen = ends.min(by: { dist($0) < dist($1) }).map { [$0] } ?? []
            }
            for k in chosen {
                if out.edges[k].a == n { out.edges[k].stops.0 = true }
                if out.edges[k].b == n { out.edges[k].stops.1 = true }
            }
        }

        // Road grid for nearby checks.
        let cell: Float = 25
        func key(_ p: SIMD2<Float>) -> SIMD2<Int32> { SIMD2(Int32(floor(p.x / cell)), Int32(floor(p.y / cell))) }
        var roadGrid: [SIMD2<Int32>: [(SIMD2<Float>, SIMD2<Float>, Float, Int)]] = [:]
        for (ei, e) in out.edges.enumerated() {
            for k in 0..<(e.pts.count - 1) {
                let a = e.pts[k], b = e.pts[k + 1]
                let lo = key(simd_min(a, b) - cell), hi = key(simd_max(a, b) + cell)
                for x in lo.x...hi.x { for y in lo.y...hi.y { roadGrid[SIMD2(x, y), default: []].append((a, b, e.width, ei)) } }
            }
        }
        func roadClear(_ p: SIMD2<Float>, _ margin: Float, skip: Int = -1) -> Bool {
            for (a, b, w, ei) in roadGrid[key(p)] ?? [] where ei != skip {
                if distanceToSegment(p, a, b) < w / 2 + margin { return false }
            }
            return true
        }

        // Buildings: every footprint in the download for "is this inside a building", the owned ones built.
        var allPolys: [[SIMD2<Float>]] = []
        var bgrid: [SIMD2<Int32>: [Int]] = [:]
        for w in osm.ways where w.tags["building"] != nil && w.tags["building"] != "no" && w.nds.count >= 4 && w.nds.first == w.nds.last {
            var poly = w.nds.dropLast().compactMap { nodes[$0] }
            guard poly.count >= 3 else { continue }
            if area(poly) < 0 { poly.reverse() }
            let pi = allPolys.count
            allPolys.append(poly)
            let lo = key(poly.reduce(poly[0]) { simd_min($0, $1) }), hi = key(poly.reduce(poly[0]) { simd_max($0, $1) })
            for x in lo.x...hi.x { for y in lo.y...hi.y { bgrid[SIMD2(x, y), default: []].append(pi) } }
        }
        out.buildings = buildings(osm, owned: owned)
        func inBuilding(_ p: SIMD2<Float>, pad: Float = 0) -> Int? {
            for i in bgrid[key(p)] ?? [] {
                if pointIn(allPolys[i], p) { return i }
                if pad > 0 {
                    let poly = allPolys[i]
                    for k in 0..<poly.count where distanceToSegment(p, poly[k], poly[(k + 1) % poly.count]) < pad { return i }
                }
            }
            return nil
        }

        // Parks, woods, water and lots: ways and multipolygon relations, cut to the tile and then along the squares'
        // edges so each piece is drawn by the square it's in.
        var areaSources: [(kind: String, outer: [SIMD2<Float>], holes: [[SIMD2<Float>]])] = []
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last {
            guard let k = MapShapes.areaKind(w.tags) else { continue }
            areaSources.append((k, w.nds.dropLast().compactMap { nodes[$0] }, []))
        }
        for r in osm.relations where r.tags["type"] == "multipolygon" {
            guard let k = MapShapes.areaKind(r.tags) else { continue }
            for (o, hs) in multipolygon(osm, r.members) { areaSources.append((k, o, hs)) }
        }
        let edgeX = bundled?.x ?? -rect.0.x, edgeY = bundled?.y ?? -rect.0.y
        let xExtra = [-edgeX, edgeX], yExtra = [-edgeY, edgeY]
        let margin = SIMD2<Float>(2, 2)
        for src in areaSources {
            var o = MapShapes.clip(src.outer, rect.0 - margin, rect.1 + margin)
            guard o.count >= 3, abs(area(o)) >= 20 else { continue }
            if area(o) < 0 { o.reverse() }
            o = simplify(o, 0.4)
            let hs = src.holes.map { simplify(MapShapes.clip($0, rect.0 - margin, rect.1 + margin), 0.4) }.filter { $0.count >= 3 && abs(area($0)) >= 4 }
            let (pts, tris) = MapShapes.withHoles(o, hs)
            for (_, piece) in MapShapes.cutTriangles(pts, tris, owned: owned, xExtra: xExtra, yExtra: yExtra) {
                var a = AreaData(p: flat(piece.pts), t: piece.tris, k: src.kind)
                if src.kind == "parking" {
                    let axis = obb(o).1
                    a.a = (atan2(axis.y, axis.x) * 1000).rounded() / 1000
                }
                if src.kind.hasPrefix("pitch") {
                    let f = obb(src.outer)
                    a.o = [f.0.x, f.0.y, f.1.x, f.1.y, f.2, f.3]
                }
                if src.kind == "parking" { out.lots.append(a) } else { out.grass.append(a) }
            }
        }
        // Commercial and retail ground, for how full its parking lanes are.
        let paved: [[SIMD2<Float>]] = areaSources.filter { $0.kind == "paved" }.map(\.outer)
        func inPaved(_ p: SIMD2<Float>) -> Bool {
            paved.contains { poly in
                let lo = poly.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }, hi = poly.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
                return p.x >= lo.x && p.x <= hi.x && p.y >= lo.y && p.y <= hi.y && pointIn(poly, p)
            }
        }
        // Rivers and streams as lines, as wide as tagged.
        for w in osm.ways {
            guard let ww = w.tags["waterway"], let width = MapShapes.waterwayWidth[ww] else { continue }
            if ["yes", "culvert"].contains(w.tags["tunnel"] ?? "") || (w.tags["layer"] ?? "0").hasPrefix("-") { continue }
            let pts = w.nds.compactMap { nodes[$0] }
            guard pts.count >= 2 else { continue }
            let wd = number(w.tags["width"]) ?? width
            for piece in MapShapes.cutLine(pts, owned: owned, xExtra: xExtra, yExtra: yExtra) {
                out.paths.append(PathData(p: flat(piece), w: (wd * 10).rounded() / 10, k: "water"))
            }
        }
        // Driveways, as paths up to the house.
        for w in osm.ways where w.tags["highway"] == "service" && w.tags["service"] == "driveway" && w.tags["tunnel"] == nil {
            let pts = w.nds.compactMap { nodes[$0] }
            guard pts.count >= 2, owned(pts[0]) else { continue }
            out.paths.append(PathData(p: flat(pts), w: 2.8, k: "drive"))
        }
        for w in osm.ways {
            let t = w.tags
            guard let hw = t["highway"], ["footway", "pedestrian", "path", "cycleway"].contains(hw) else { continue }
            if ["sidewalk", "crossing"].contains(t["footway"] ?? "") || t["area"] == "yes" || t["tunnel"] == "yes" || t["indoor"] == "yes" { continue }
            if let l = t["level"], l != "0" { continue }
            let pts = w.nds.compactMap { nodes[$0] }
            guard pts.count >= 2, owned(pts[0]) else { continue }
            out.paths.append(PathData(p: flat(pts), w: hw == "pedestrian" ? 4 : 2.4))
        }

        // Shops: a name plaque on the facade facing the nearest street.
        let amenities: Set<String> = ["restaurant", "cafe", "bar", "pub", "fast_food", "bank", "cinema", "theatre", "ice_cream",
                                      "pharmacy", "nightclub", "library"]
        var sources: [(SIMD2<Float>, [String: String])] = []
        for (id, t) in osm.nodeTags where t["name"] != nil {
            guard let p = nodes[id], owned(p) else { continue }
            if t["shop"] != nil || amenities.contains(t["amenity"] ?? "") || t["craft"] != nil || ["hotel", "museum"].contains(t["tourism"] ?? "") {
                sources.append((p, t))
            }
        }
        func shopTags(_ t: [String: String]) -> Bool {
            t["name"] != nil && (t["shop"] != nil || amenities.contains(t["amenity"] ?? "") || t["craft"] != nil || ["hotel", "museum"].contains(t["tourism"] ?? ""))
        }
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last && shopTags(w.tags) {
            let poly = w.nds.dropLast().compactMap { nodes[$0] }
            guard !poly.isEmpty else { continue }
            let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
            if owned(c) { sources.append((c, w.tags)) }
        }
        for r in osm.relations where r.tags["type"] == "multipolygon" && shopTags(r.tags) {
            guard let o = multipolygon(osm, r.members).first?.outer, !o.isEmpty else { continue }
            let c = o.reduce(SIMD2<Float>(0, 0), +) / Float(o.count)
            if owned(c) { sources.append((c, r.tags)) }
        }
        // A building with a shop mapped inside gets shop windows (unless it's a kind that never has them).
        for (p, _) in sources {
            if let k = out.buildings.firstIndex(where: { $0.x != 1 && $0.sf == nil && pointIn(points($0.p), p) }) { out.buildings[k].sf = 1 }
        }
        var placed: [SIMD2<Float>] = []
        var shopFronts: [(SIMD2<Float>, SIMD2<Float>)] = []
        for (p, t) in sources {
            guard let bi = inBuilding(p) else { continue }
            var best: (Float, SIMD2<Float>)?
            for x in -2...2 {
                for y in -2...2 {
                    let k = key(p) &+ SIMD2(Int32(x), Int32(y))
                    for (a, b, _, ei) in roadGrid[k] ?? [] where out.edges[ei].type != "service" {
                        let q = closestOnSegment(p, a, b)
                        let d = simd_distance(p, q)
                        if best == nil || d < best!.0 { best = (d, q) }
                    }
                }
            }
            guard let (dist, q) = best, dist < 60, dist > 0.5 else { continue }
            let dir = simd_normalize(q - p)
            let poly = allPolys[bi]
            var hit: (Float, SIMD2<Float>, SIMD2<Float>)?
            for k in 0..<poly.count {
                let a = poly[k], b = poly[(k + 1) % poly.count], e = b - a
                let den = cross2(dir, e)
                if abs(den) < 1e-9 { continue }
                let tt = cross2(a - p, e) / den, uu = cross2(a - p, dir) / den
                if tt > 0 && uu >= 0 && uu <= 1 && (hit == nil || tt < hit!.0) {
                    var n = perpRight(simd_normalize(e))
                    if simd_dot(n, dir) < 0 { n = -n }
                    hit = (tt, p + dir * tt, n)
                }
            }
            guard var (_, h, n) = hit else { continue }
            if placed.contains(where: { simd_distance($0, h) < 3.5 }) {
                h += SIMD2(-n.y, n.x) * 4
                if placed.contains(where: { simd_distance($0, h) < 3.5 }) { continue }
            }
            placed.append(h)
            shopFronts.append((h, n))
            let height = out.buildings.first(where: { $0.x != 1 && pointIn(points($0.p), p) })?.h ?? 8
            let kind = t["amenity"] ?? t["shop"] ?? t["craft"] ?? t["tourism"] ?? ""
            let addr = [t["addr:housenumber"], t["addr:street"]].compactMap { $0 }.joined(separator: " ")
            out.shops.append(ShopData(n: t["name"]!, x: h.x + n.x * 0.12, y: h.y + n.y * 0.12, dx: n.x, dy: n.y, z: min(4, height - 0.6),
                                      k: kind == "yes" ? "shop" : kind, c: t["cuisine"], a: addr.isEmpty ? nil : addr,
                                      h: t["opening_hours"], ph: t["phone"] ?? t["contact:phone"], w: t["website"] ?? t["contact:website"],
                                      o: t["outdoor_seating"] == "yes" ? 1 : nil))
        }

        // Parked cars and street trees along the tile's streets; trees in its parks.
        var rng = SystemRandomNumberGenerator()
        for (ei, e) in out.edges.enumerated() where e.type != "service" {
            // Parking lanes: about 70% full downtown and in commercial areas, sparse on residential streets.
            let busy = inPaved(e.pts[e.pts.count / 2])
            let fill: Float = busy ? 0.7 : (["residential", "living_street", "unclassified"].contains(e.type) ? 0.12 : 0.3)
            var s: Float = 12
            var cum: [Float] = [0]
            for k in 1..<e.pts.count { cum.append(cum[k - 1] + simd_distance(e.pts[k], e.pts[k - 1])) }
            let length = cum.last ?? 0
            func at(_ s: Float) -> (SIMD2<Float>, SIMD2<Float>) {
                var k = 0
                while k < cum.count - 2 && cum[k + 1] < s { k += 1 }
                let seg = cum[k + 1] - cum[k]
                let d = e.pts[k + 1] - e.pts[k]
                return (e.pts[k] + d * (seg > 0 ? (s - cum[k]) / seg : 0), simd_length(d) > 0 ? simd_normalize(d) : [0, 1])
            }
            while s < length - 12 {
                let (p, d) = at(s)
                for (side, on) in [(Float(1), e.parking.1), (Float(-1), e.parking.0)] where on && Float.random(in: 0...1, using: &rng) < fill {
                    let q = p + perpRight(d) * side * (e.width / 2 - 1.15)
                    if inBuilding(q, pad: 1.5) == nil && roadClear(q, 0.5, skip: ei) {
                        // Facing the way traffic goes on that side of the street.
                        let hd = side == CityConfig.current.style.side || e.oneway ? atan2(d.x, d.y) : atan2(-d.x, -d.y)
                        out.parked.append([q.x, q.y, hd])
                    }
                }
                s += 6.4
            }
            if ["residential", "tertiary", "secondary", "unclassified", "primary"].contains(e.type) {
                var s: Float = 12
                while s < length - 12 {
                    let (p, d) = at(s)
                    for side: Float in [1, -1] where Float.random(in: 0...1, using: &rng) < 0.55 {
                        // In the grass strip between kerb and sidewalk on residential streets, else behind the sidewalk.
                        let residential = ["residential", "living_street", "unclassified"].contains(e.type)
                        let q = p + perpRight(d) * side * (e.width / 2 + (residential ? 0.9 : 3.2))
                        if inBuilding(q, pad: 2.5) == nil && roadClear(q, 2) { out.trees.append([q.x, q.y, Float.random(in: 0.8...1.3, using: &rng)]) }
                    }
                    s += 11
                }
            }
        }
        // Trees mapped one by one.
        for (id, t) in osm.nodeTags where t["natural"] == "tree" {
            guard let p = nodes[id], owned(p), inBuilding(p) == nil else { continue }
            out.trees.append([p.x, p.y, Float.random(in: 0.9...1.35, using: &rng)])
        }
        // Scattered through parks, thick in woods (none in water or on fields of play).
        for g in out.grass where !["water", "golf_course", "paved", "residential"].contains(g.k) && !g.k.hasPrefix("pitch") && !g.k.hasPrefix("golf") && g.k != "playground" {
            let pts = points(g.p)
            var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
            var sizes: [Float] = []
            for i in stride(from: 0, to: g.t.count - 2, by: 3) where g.t[i + 2] < pts.count {
                let tri = (pts[g.t[i]], pts[g.t[i + 1]], pts[g.t[i + 2]])
                tris.append(tri)
                sizes.append(abs(area([tri.0, tri.1, tri.2])))
            }
            let total = sizes.reduce(0, +)
            guard total > 0 else { continue }
            let wood = g.k == "wood"
            let n = min(wood ? 150 : 120, Int(total / (wood ? 70 : 260)))
            for _ in 0..<n {
                var pick = Float.random(in: 0..<total, using: &rng), k = 0
                while k < sizes.count - 1 && pick > sizes[k] { pick -= sizes[k]; k += 1 }
                var a = Float.random(in: 0...1, using: &rng), b = Float.random(in: 0...1, using: &rng)
                if a + b > 1 { a = 1 - a; b = 1 - b }
                let tri = tris[k]
                let q = tri.0 + (tri.1 - tri.0) * a + (tri.2 - tri.0) * b
                if owned(q) && inBuilding(q, pad: 3) == nil && roadClear(q, 2.5) { out.trees.append([q.x, q.y, Float.random(in: 0.9...1.5, using: &rng)]) }
            }
        }
        // Cars in parking lots: about half the spaces taken, nose in.
        var lotCars: [[Float]] = []
        for l in out.lots {
            guard let angle = l.a else { continue }
            let pts = points(l.p)
            for st in MapShapes.stalls(pts, l.t, angle: angle) where Float.random(in: 0...1, using: &rng) < 0.5 {
                if inBuilding(st.center, pad: 1.5) == nil && roadClear(st.center, 1) {
                    lotCars.append([st.center.x, st.center.y, atan2(st.facing.x, st.facing.y)])
                }
            }
        }
        if downtown && out.parked.count > 900 { out.parked.shuffle(using: &rng); out.parked = Array(out.parked.prefix(900)) }
        out.parked += downtown ? Array(lotCars.shuffled(using: &rng).prefix(400)) : lotCars
        furniture(osm, owned: owned, shopFronts: shopFronts, into: &out)
        fuelStations(osm, owned: owned, into: &out)

        // Named areas the car can be inside: campuses, parks, districts.
        func namedArea(_ t: [String: String]) -> Bool {
            guard t["name"] != nil, t["building"] == nil, t["highway"] == nil else { return false }
            return ["university", "college", "hospital", "school"].contains(t["amenity"] ?? "") || ["park", "nature_reserve"].contains(t["leisure"] ?? "")
                || ["neighbourhood", "suburb", "quarter", "district"].contains(t["place"] ?? "") || t["landuse"] != nil
        }
        var areaNames: [(String, [SIMD2<Float>])] = []
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last && namedArea(w.tags) {
            areaNames.append((w.tags["name"]!, w.nds.dropLast().compactMap { nodes[$0] }))
        }
        for r in osm.relations where r.tags["type"] == "multipolygon" && namedArea(r.tags) {
            for (o, _) in multipolygon(osm, r.members) { areaNames.append((r.tags["name"]!, o)) }
        }
        for (name, poly) in areaNames where poly.count >= 3 && abs(area(poly)) > 2000 {
            let c = poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)
            guard owned(c) else { continue }
            let outline = simplify(area(poly) < 0 ? Array(poly.reversed()) : poly, 3)
            out.places.append(PlaceData(n: name, x: (c.x * 10).rounded() / 10, y: (c.y * 10).rounded() / 10, s: 2, pg: flat(outline)))
        }
        // Neighbourhoods and suburbs by name.
        for (id, t) in osm.nodeTags {
            guard let kind = t["place"], ["neighbourhood", "suburb", "quarter"].contains(kind), let name = t["name"], let p = nodes[id], owned(p) else { continue }
            out.places.append(PlaceData(n: name, x: (p.x * 10).rounded() / 10, y: (p.y * 10).rounded() / 10, s: kind == "neighbourhood" ? nil : 1))
        }
        var taken = Set<SIMD2<Int32>>()
        out.trees = out.trees.filter { t in
            let k = SIMD2(Int32(floor(t[0] / 4)), Int32(floor(t[1] / 4)))
            for x in -1...1 { for y in -1...1 where taken.contains(k &+ SIMD2(Int32(x), Int32(y))) { return false } }
            taken.insert(k)
            return true
        }
        return out
    }

    /// Which sides have a sidewalk: as tagged (sidewalk=both/left/right/no, or per side); "separate" (mapped as
    /// its own footway, which isn't drawn) counts as a sidewalk; untagged streets have both.
    static func sidewalks(_ t: [String: String]) -> (Bool, Bool) {
        func has(_ v: String?) -> Bool? { v.map { !["no", "none"].contains($0) } }
        var l = true, r = true
        switch t["sidewalk"] {
        case "no", "none": l = false; r = false
        case "left": r = false
        case "right": l = false
        default: break
        }
        if let b = has(t["sidewalk:both"]) { l = b; r = b }
        if let v = has(t["sidewalk:left"]) { l = v }
        if let v = has(t["sidewalk:right"]) { r = v }
        if t["highway"] == "service" { return (false, false) }
        return (l, r)
    }

    static func parking(_ t: [String: String], _ hw: String) -> (Bool, Bool) {
        func v(_ side: String) -> String? { t["parking:\(side)"] ?? t["parking:lane:\(side)"] }
        let both = v("both")
        let l = v("left") ?? both, r = v("right") ?? both
        func yes(_ s: String?) -> Bool { s != nil && !["no", "no_parking", "no_stopping", "separate", "none"].contains(s!) }
        if l == nil && r == nil {
            let d = ["residential", "unclassified", "tertiary", "secondary", "living_street"].contains(hw)
            return (d, d)
        }
        return (yes(l), yes(r))
    }

    // MARK: Buildings

    static let smallKinds: Set<String> = ["garage", "shed", "garages", "carport", "hut", "roof", "park", "service", "transformer_tower"]
    /// Buildings with blank walls: works, stores, farm buildings, sheds, a park's restrooms.
    static let plainKinds: Set<String> = ["industrial", "warehouse", "manufacture", "storage_tank", "silo", "hangar", "service",
                                          "transformer_tower", "barn", "farm_auxiliary", "stable", "cowshed", "sports_hall",
                                          "riding_hall", "bunker", "shed", "hut", "park", "water_tower", "digester", "works"]
    /// Seating round a field.
    static let standKinds: Set<String> = ["stadium", "grandstand"]

    /// What kind of ground an area is, for the buildings standing in it.
    static func groundKind(_ t: [String: String]) -> String? {
        switch t["amenity"] ?? "" {
        case "university", "college": return "university"
        case "school", "kindergarten": return "school"
        case "hospital": return "hospital"
        case "place_of_worship": return "church"
        default: break
        }
        if ["park", "recreation_ground", "garden", "nature_reserve", "golf_course", "dog_park", "playground", "pitch",
            "sports_centre", "stadium"].contains(t["leisure"] ?? "") { return "park" }
        switch t["landuse"] ?? "" {
        case "residential": return "residential"
        case "retail": return "retail"
        case "commercial": return "office"
        case "industrial", "railway", "port", "quarry": return "industrial"
        case "education": return "university"
        case "religious": return "church"
        case "cemetery", "recreation_ground", "grass", "village_green": return "park"
        case "farmyard", "farmland": return "farm_auxiliary"
        default: return nil
        }
    }

    static func levelHeight(_ kind: String) -> Float {
        if houseKinds.contains(kind) { return 2.9 }
        if ["apartments", "dormitory", "hotel"].contains(kind) { return 3.1 }
        if ["university", "college", "school", "hospital", "museum", "church", "government", "public", "civic"].contains(kind) { return 4 }
        return 3.6
    }

    static func defaultLevels(_ kind: String, _ a: Float) -> Float {
        switch kind {
        case "house", "detached", "semidetached_house", "terrace", "bungalow": return 2
        case _ where smallKinds.contains(kind): return 1
        case "apartments", "residential": return a < 400 ? 3 : (a < 1500 ? 4 : 6)
        case "dormitory", "hotel": return 8
        case "office": return 5
        case "university", "college": return a < 1500 ? 3 : (a < 5000 ? 4 : 5)
        case "school": return 2
        case "hospital": return 6
        case "parking": return 4
        case "government", "public", "civic", "museum", "church": return 3
        case "retail", "commercial": return a < 600 ? 2 : 3
        default: return a < 60 ? 1 : (a < 600 ? 2 : (a < 2000 ? 3 : 4))
        }
    }

    static let roofAlias = ["skillion": "gabled", "gambrel": "gabled", "saltbox": "gabled", "half-hipped": "hipped",
                            "mansard": "hipped", "round": "dome", "onion": "dome", "cone": "pyramidal"]
    static let materials: [String: [Int]] = ["brick": [0, 9], "stone": [2, 10], "sandstone": [10], "limestone": [2],
                                             "concrete": [2], "glass": [3], "metal": [2],
                                             "plaster": [2, 10], "cement_block": [2], "wood": [5, 6, 7], "timber_framing": [10]]

    /// Outlines and building:parts, the same way the bundled downtown was prepared: outlines with parts inside are
    /// kept only to drive into, parts carry their own heights and roofs, and missing heights come from the kind of
    /// building, its size and its neighbours.
    static func buildings(_ osm: OSMReader, owned: (SIMD2<Float>) -> Bool) -> [BuildingData] {
        struct Item { var poly: [SIMD2<Float>]; var holes: [[SIMD2<Float>]]; var tags: [String: String]; var part: Bool; var c: SIMD2<Float>
                      var parent: Int? = nil; var hasParts = false; var kind = "yes" }
        var items: [Item] = []
        func add(_ outer: [SIMD2<Float>], _ holes: [[SIMD2<Float>]], _ tags: [String: String], part isPart: Bool) {
            // Nothing below ground: a subway station or an underground garage under the streets isn't a wall.
            if (tags["layer"] ?? "0").hasPrefix("-") || ["underground", "indoor"].contains(tags["location"] ?? "")
                || tags["building"] == "underground" || tags["indoor"] != nil { return }
            var poly = outer
            guard poly.count >= 3 else { return }
            if area(poly) < 0 { poly.reverse() }
            poly = simplify(poly)
            guard poly.count >= 3, area(poly) >= 6 else { return }
            let hs = holes.map { h -> [SIMD2<Float>] in simplify(area(h) > 0 ? Array(h.reversed()) : h) }.filter { $0.count >= 3 && abs(area($0)) >= 4 }
            items.append(Item(poly: poly, holes: hs, tags: tags, part: isPart, c: poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)))
        }
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last {
            let isPart = w.tags["building:part"] != nil && w.tags["building:part"] != "no"
            let isOutline = !isPart && w.tags["building"] != nil && w.tags["building"] != "no"
            guard isPart || isOutline else { continue }
            add(w.nds.dropLast().compactMap { osm.nodes[$0] }, [], w.tags, part: isPart)
        }
        // Multipolygon buildings: outer rings joined end to end, courtyards cut out; tags from the outer ways too.
        for r in osm.relations where r.tags["type"] == "multipolygon" {
            let isPart = r.tags["building:part"] != nil && r.tags["building:part"] != "no" && r.tags["building"] == nil
            guard isPart || (r.tags["building"] != nil && r.tags["building"] != "no") else { continue }
            var tags = r.tags
            for m in r.members where m.type == "way" && m.role == "outer" {
                if let i = osm.wayIndex[m.ref] { for (k, v) in osm.ways[i].tags where tags[k] == nil { tags[k] = v } }
            }
            for (o, hs) in multipolygon(osm, r.members) { add(o, hs, tags, part: isPart) }
        }
        let partCenters = items.filter(\.part).map(\.c)
        for i in items.indices {
            if items[i].part {
                items[i].parent = items.indices.first { !items[$0].part && pointIn(items[$0].poly, items[i].c) }
            } else {
                items[i].hasParts = partCenters.contains { pointIn(items[i].poly, $0) }
            }
        }
        // What the land round a building is (homes, shops, a campus, a park, a works), from the smallest mapped
        // area it stands in: a building tagged only "yes" takes its kind from there.
        var grounds: [(poly: [SIMD2<Float>], lo: SIMD2<Float>, hi: SIMD2<Float>, area: Float, kind: String)] = []
        func ground(_ poly: [SIMD2<Float>], _ t: [String: String]) {
            guard t["building"] == nil, poly.count >= 3, let k = groundKind(t) else { return }
            let lo = poly.reduce(SIMD2<Float>(repeating: .infinity)) { simd_min($0, $1) }
            let hi = poly.reduce(SIMD2<Float>(repeating: -.infinity)) { simd_max($0, $1) }
            grounds.append((poly, lo, hi, abs(area(poly)), k))
        }
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last { ground(w.nds.dropLast().compactMap { osm.nodes[$0] }, w.tags) }
        for r in osm.relations where r.tags["type"] == "multipolygon" {
            guard groundKind(r.tags) != nil else { continue }
            for (o, _) in multipolygon(osm, r.members) { ground(o, r.tags) }
        }
        grounds.sort { $0.area < $1.area }
        func groundAt(_ p: SIMD2<Float>) -> String? {
            grounds.first { p.x >= $0.lo.x && p.y >= $0.lo.y && p.x <= $0.hi.x && p.y <= $0.hi.y && pointIn($0.poly, p) }?.kind
        }
        var setting: [String?] = Array(repeating: nil, count: items.count)
        for i in items.indices {
            let k = items[i].part ? (items[i].parent.flatMap { items[$0].tags["building"] } ?? "yes") : (items[i].tags["building"] ?? "yes")
            items[i].kind = k == "construction" ? "yes" : k
            setting[i] = groundAt(items[i].c)
            if items[i].kind == "yes", let g = setting[i], g != "residential" { items[i].kind = g }
        }
        // Heights already known nearby.
        var known: [SIMD2<Int32>: [(SIMD2<Float>, Float)]] = [:]
        for it in items where !houseKinds.contains(it.kind) {
            var h = number(it.tags["height"])
            if h == nil, let l = number(it.tags["building:levels"]) { h = l * levelHeight(it.kind) + 0.6 }
            if let h { known[SIMD2(Int32(floor(it.c.x / 70)), Int32(floor(it.c.y / 70))), default: []].append((it.c, h)) }
        }
        func neighbours(_ c: SIMD2<Float>) -> Float? {
            var hs: [Float] = []
            let k = SIMD2(Int32(floor(c.x / 70)), Int32(floor(c.y / 70)))
            for x in -1...1 { for y in -1...1 { for (q, h) in known[k &+ SIMD2(Int32(x), Int32(y))] ?? [] where simd_distance(q, c) < 70 { hs.append(h) } } }
            guard hs.count >= 2 else { return nil }
            return hs.sorted()[hs.count / 2]
        }

        var out: [BuildingData] = []
        for (idx, it) in items.enumerated() where owned(it.c) {
            let poly = it.poly, t = it.tags, kind = it.kind
            // Houses only where people live: among homes, or where the map doesn't say.
            let homely = setting[idx] == nil || setting[idx] == "residential"
            let a = area(poly)
            if ["roof", "carport"].contains(kind) && t["height"] == nil && !it.part { continue }
            let flatPoly = flat(poly)
            let tris = it.holes.isEmpty ? earclip(poly) : MapShapes.withHoles(poly, it.holes).tris
            let holes: [[Float]]? = it.holes.isEmpty ? nil : it.holes.map(flat)
            let name = t["name"] ?? it.parent.flatMap { items[$0].tags["name"] }
            if !it.part && it.hasParts {
                var b = BuildingData(p: flatPoly, h: 0, t: tris, g: nil, c: 0, r: 0, n: name)
                b.x = 1
                b.ho = holes
                b.hn = t["addr:housenumber"].map { String($0.prefix(8)) }
                out.append(b)
                continue
            }
            let lh = levelHeight(kind)
            let levels = number(t["building:levels"]), height = number(t["height"])
            var mh = number(t["min_height"]) ?? number(t["building:min_level"]).map { $0 * lh } ?? 0
            mh = max(0, mh)
            var shape = t["roof:shape"] ?? ""
            shape = roofAlias[shape] ?? shape
            var houseish = !it.part && (houseKinds.contains(kind) || (kind == "yes" && homely && a < 180 && (levels ?? 2) <= 2 && height == nil))
            if ["apartments", "residential"].contains(kind) && a > 450 { houseish = false }
            if shape.isEmpty { shape = houseish ? "gabled" : "flat" }
            if !["flat", "gabled", "hipped", "pyramidal", "dome"].contains(shape) { shape = "flat" }
            var frame: (SIMD2<Float>, SIMD2<Float>, Float, Float)?
            if shape == "gabled" || shape == "hipped" {
                let f = obb(poly)
                if f.3 > 14 || f.2 > 45 { shape = "flat" } else { frame = f }
            }
            var rh: Float
            switch shape {
            case "gabled": rh = min((frame?.3 ?? 0) * 0.75, 4.5)
            case "hipped": rh = min((frame?.3 ?? 0) * 0.7, 4.5)
            case "pyramidal": rh = min(sqrt(a) * 0.35, 8)
            case "dome": rh = min(sqrt(a) * 0.45, 14)
            default: rh = 0
            }
            if let r = number(t["roof:height"]) { rh = r } else if let l = number(t["roof:levels"]), shape != "flat" { rh = l * 2.8 }
            var eave: Float
            if let h = height {
                eave = shape != "flat" && h - rh > mh + 2 ? h - rh : h
            } else if let l = levels {
                eave = l * lh + (houseish ? 0 : 0.6)
            } else {
                var guess = defaultLevels(kind, a) * lh + (houseish ? 0 : 0.6)
                if !houseish && !smallKinds.contains(kind), let n = neighbours(it.c) { guess = max(3, min(0.6 * n + 0.4 * guess, guess * 2.5)) }
                if kind == "church" { guess = 13 }
                eave = guess
            }
            eave = max(min(eave, 150), mh + 2.2)
            let base = it.parent.map { items[$0] } ?? it
            let hv = hash(Int(base.c.x.rounded()), Int(base.c.y.rounded()), 7)
            let material = t["building:material"] ?? base.tags["building:material"]
            let colour: Int
            if houseish { colour = 4 + hv % 5 }
            else if let m = material, let list = materials[m] { colour = list[hv % list.count] }
            else if eave > 32 { colour = 3 }
            else if ["university", "college", "school", "church", "government", "museum", "public"].contains(kind) { colour = [0, 1, 2, 2, 9][hv % 5] }
            else if kind == "parking" { colour = 2 }
            else if plainKinds.contains(kind) || standKinds.contains(kind) { colour = [2, 10, 2][hv % 3] }
            else { colour = [0, 0, 1, 9, 2, 10][hv % 6] }
            var g: [Float]?
            if let f = frame { g = [f.0.x, f.0.y, f.1.x, f.1.y, f.2 + 0.35, f.3 + 0.45, max(0.5, rh)] }
            var b = BuildingData(p: flatPoly, h: eave, t: tris, g: g, c: colour, r: hash(Int(it.c.x.rounded()), Int(it.c.y.rounded())) % 3, n: name)
            // A roof on its own (a canopy, a shelter) is a slab up top, not a solid block.
            if kind == "roof" { mh = max(mh, eave - 0.7) }
            if mh > 0 { b.mh = mh }
            if it.part { b.pt = 1 } else { b.hn = t["addr:housenumber"].map { String($0.prefix(8)) } }
            if shape != "flat" { b.rs = shape; b.rh = max(0.5, rh) }
            b.ho = holes
            // How its walls look, from what it is: seating stepping up from a field for a stadium's bowl (a ring round
            // an open middle), a tall glass box for its press box or club seats, blank walls where nobody looks out.
            if standKinds.contains(kind) || t["leisure"] == "stadium" || t["leisure"] == "grandstand" {
                if !it.holes.isEmpty {
                    b.lk = "stands"
                    // Without a tagged height, the stands rise about one in two from the field to the rim.
                    if height == nil {
                        let outerR = sqrt(a / .pi), innerR = sqrt(it.holes.map { abs(area($0)) }.reduce(0, +) / .pi)
                        b.h = max(5, min(35, (outerR - innerR) * 0.5))
                    }
                } else if eave >= 15 { b.c = 3 } else { b.lk = "plain" }
            } else if plainKinds.contains(kind) && material != "glass" { b.lk = "plain" }
            // Windows to suit the kind of building, varied from one building to the next.
            let wpChoices: [Int]
            switch kind {
            case "school", "university", "college", "kindergarten", "hospital", "civic", "public", "government": wpChoices = [2, 1, 3, 2]
            case "office", "commercial": wpChoices = [2, 0, 1]
            case "apartments", "dormitory", "residential", "hotel": wpChoices = [0, 1, 3]
            case "church", "chapel", "cathedral", "museum", "library": wpChoices = [3]
            default: wpChoices = [0, 1, 3, 2, 0]
            }
            let wp = wpChoices[hv % wpChoices.count]
            if wp > 0 { b.wp = wp }
            if ["garage", "carport"].contains(kind) { b.gk = 1 } else if kind == "garages" { b.gk = 2 }
            // Most garages aren't tagged as such: a small building with no address of its own, no name and no tagged
            // height, out on its own, is a garage (a tiny one a shed, left plain).
            else if !it.part && homely && ["yes", "shed", "detached"].contains(kind) && a >= 16 && a <= 60 && t["addr:housenumber"] == nil
                        && t["name"] == nil && levels == nil && height == nil { b.gk = 1 }
            // Shop windows: on retail and commercial buildings; never on kinds that don't have them.
            if ["retail", "commercial", "supermarket", "kiosk", "shop"].contains(kind) { b.sf = 1 }
            else if houseish || ["church", "cathedral", "chapel", "apartments", "dormitory", "university", "college", "school", "hospital",
                                 "parking", "residential", "house", "detached", "garage", "garages", "shed", "government", "civic",
                                 "public", "museum", "library", "train_station", "transportation", "industrial", "warehouse"].contains(kind) { b.sf = 0 }
            // Colours as tagged, on the part or else its building.
            b.wc = MapShapes.colour(t["building:colour"]) ?? MapShapes.colour(base.tags["building:colour"])
            b.rc = MapShapes.colour(t["roof:colour"]) ?? MapShapes.colour(base.tags["roof:colour"])
            out.append(b)
        }
        // A garage matches the house it belongs to: the nearest house within 30 m takes it over in colour and roof.
        let centres = out.map { b -> SIMD2<Float> in let p = points(b.p); return p.reduce(SIMD2<Float>(0, 0), +) / Float(max(1, p.count)) }
        for i in out.indices where out[i].gk != nil {
            var best: (Int, Float)?
            for j in out.indices where j != i && out[j].gk == nil && out[j].x != 1 && out[j].pt == nil && (out[j].g != nil || (4...8).contains(out[j].c)) {
                let d = simd_distance(centres[i], centres[j])
                if d < 30 && (best == nil || d < best!.1) { best = (j, d) }
            }
            guard let (h, _) = best else { continue }
            out[i].c = out[h].c
            out[i].r = out[h].r
            if out[i].wc == nil { out[i].wc = out[h].wc }
            if out[i].rc == nil { out[i].rc = out[h].rc }
        }
        // Address points inside a building number it, when it has no number of its own.
        for (id, t) in osm.nodeTags where t["addr:housenumber"] != nil && t["building"] == nil {
            guard let p = osm.nodes[id], owned(p) else { continue }
            if let i = out.firstIndex(where: { $0.hn == nil && $0.pt == nil && pointIn(points($0.p), p) }) {
                out[i].hn = String(t["addr:housenumber"]!.prefix(8))
            }
        }
        return out
    }

    // MARK: Street furniture

    /// Lamps, hydrants, benches, bins, bike racks, bus stops, parking meters and utility poles (with their wires)
    /// as mapped; where none are mapped, a lamp every 35 m along bigger streets, a hydrant every 100 m and bike
    /// racks in front of shops.
    static func furniture(_ osm: OSMReader, owned: (SIMD2<Float>) -> Bool, shopFronts: [(SIMD2<Float>, SIMD2<Float>)], into out: inout TileOutput) {
        func facing(_ p: SIMD2<Float>) -> Float {
            var best: (Float, SIMD2<Float>)?
            for e in out.edges where e.type != "service" {
                for j in 0..<(e.pts.count - 1) {
                    let a = e.pts[j], b = e.pts[j + 1]
                    if simd_distance(p, a) > 60 && simd_distance(p, b) > 60 { continue }
                    let q = closestOnSegment(p, a, b)
                    let d = simd_distance(p, q)
                    if best == nil || d < best!.0 { best = (d, q) }
                }
            }
            guard let q = best?.1, simd_distance(q, p) > 0.1 else { return 0 }
            let d = simd_normalize(q - p)
            return atan2(d.x, d.y)
        }
        var mapped: [Furniture.Kind: [SIMD2<Float>]] = [:]
        var poles: [Int64: SIMD2<Float>] = [:]
        for (id, t) in osm.nodeTags {
            guard let p = osm.nodes[id] else { continue }
            var kind: Furniture.Kind?
            if t["highway"] == "street_lamp" { kind = .lamp }
            else if t["emergency"] == "fire_hydrant" { kind = .hydrant }
            else if t["amenity"] == "bench" { kind = .bench }
            else if t["amenity"] == "waste_basket" || t["amenity"] == "recycling" && t["recycling_type"] == "container" { kind = .bin }
            else if t["amenity"] == "bicycle_parking" { kind = .bikeRack }
            else if t["highway"] == "bus_stop" || (t["public_transport"] == "platform" && t["bus"] == "yes") { kind = t["shelter"] == "yes" ? .shelter : .busSign }
            else if t["amenity"] == "parking_meter" || (t["amenity"] == "vending_machine" && (t["vending"] ?? "").contains("parking")) { kind = .meter }
            else if t["power"] == "pole" { kind = .pole; poles[id] = p }
            guard let k = kind else { continue }
            mapped[k, default: []].append(p)
            if owned(p) { out.furniture.append([Float(k.rawValue), p.x, p.y, facing(p)]) }
        }
        // Parks: picnic tables, shelters, drinking fountains and playground equipment as mapped; a playground with
        // nothing mapped in it gets a climbing frame, a slide and swings; basketball courts get hoops, tennis courts nets.
        var equipment: [SIMD2<Float>] = []
        var pins: [SIMD2<Float>] = []
        for (id, t) in osm.nodeTags where t["golf"] == "pin" {
            guard let p = osm.nodes[id] else { continue }
            pins.append(p)
            if owned(p) { out.furniture.append([Float(Furniture.Kind.flag.rawValue), p.x, p.y, 0]) }
        }
        for (id, t) in osm.nodeTags {
            guard let p = osm.nodes[id] else { continue }
            var kind: Furniture.Kind?
            if t["leisure"] == "picnic_table" { kind = .picnic }
            else if t["amenity"] == "drinking_water" { kind = .fountain }
            else if t["amenity"] == "shelter" && t["shelter_type"] != "public_transport" && t["highway"] == nil && t["bus"] == nil { kind = .pavilion }
            else if let play = t["playground"] {
                kind = play.contains("swing") ? .swing : (play.contains("slide") ? .slide : .climber)
                equipment.append(p)
            }
            if let k = kind, owned(p) { out.furniture.append([Float(k.rawValue), p.x, p.y, facing(p)]) }
        }
        for w in osm.ways where w.nds.count >= 4 && w.nds.first == w.nds.last {
            let poly = w.nds.dropLast().compactMap { osm.nodes[$0] }
            guard poly.count >= 3 else { continue }
            let f = obb(poly)
            let c = f.0, u = f.1, v = SIMD2(-u.y, u.x)
            let yaw = atan2(v.x, v.y)
            if w.tags["golf"] == "green", !pins.contains(where: { pointIn(poly, $0) }) {
                // The pin somewhere off the middle of the green.
                var p = c + u * f.2 * 0.25
                if !pointIn(poly, p) { p = c }
                if owned(p) { out.furniture.append([Float(Furniture.Kind.flag.rawValue), p.x, p.y, 0]) }
            } else if w.tags["amenity"] == "shelter" && w.tags["building"] == nil && w.tags["shelter_type"] != "public_transport", owned(c) {
                out.furniture.append([Float(Furniture.Kind.pavilion.rawValue), c.x, c.y, atan2(u.x, u.y)])
            } else if w.tags["leisure"] == "playground", owned(c), !equipment.contains(where: { pointIn(poly, $0) }) {
                let r = min(f.2, f.3)
                guard r > 3 else { continue }
                out.furniture.append([Float(Furniture.Kind.climber.rawValue), c.x, c.y, yaw])
                let s = c + u * min(f.2 * 0.5, 5), w2 = c - u * min(f.2 * 0.5, 5)
                if pointIn(poly, s) { out.furniture.append([Float(Furniture.Kind.slide.rawValue), s.x, s.y, yaw]) }
                if pointIn(poly, w2) { out.furniture.append([Float(Furniture.Kind.swing.rawValue), w2.x, w2.y, atan2(u.x, u.y)]) }
            } else if w.tags["leisure"] == "pitch", owned(c) {
                let sport = w.tags["sport"] ?? ""
                if sport.contains("basketball") && f.2 > 8 {
                    // Hoops at both ends, facing in.
                    for s: Float in [-1, 1] {
                        let p = c + u * s * (f.2 - 1.2)
                        let inward = -u * s
                        out.furniture.append([Float(Furniture.Kind.hoop.rawValue), p.x, p.y, atan2(inward.x, inward.y)])
                    }
                } else if sport.contains("tennis") && f.2 > 8 {
                    out.furniture.append([Float(Furniture.Kind.net.rawValue), c.x, c.y, atan2(v.x, v.y) + .pi / 2])
                }
            }
        }

        // Wires between neighbouring poles of a power line.
        for w in osm.ways where ["line", "minor_line", "cable"].contains(w.tags["power"] ?? "") && w.tags["location"] != "underground" {
            let ids = w.nds.filter { poles[$0] != nil }
            for k in 0..<max(0, ids.count - 1) {
                let a = poles[ids[k]]!, b = poles[ids[k + 1]]!
                if owned(a) && simd_distance(a, b) < 80 { out.wires.append([a.x, a.y, b.x, b.y]) }
            }
        }
        func near(_ k: Furniture.Kind, _ p: SIMD2<Float>, _ r: Float) -> Bool { (mapped[k] ?? []).contains { simd_distance($0, p) < r } }
        // Where nothing is mapped: lamps along bigger streets, hydrants along every street.
        for e in out.edges where e.type != "service" {
            var cum: [Float] = [0]
            for k in 1..<e.pts.count { cum.append(cum[k - 1] + simd_distance(e.pts[k], e.pts[k - 1])) }
            let length = cum.last ?? 0
            func at(_ s: Float) -> (SIMD2<Float>, SIMD2<Float>) {
                var k = 0
                while k < cum.count - 2 && cum[k + 1] < s { k += 1 }
                let seg = cum[k + 1] - cum[k], d = e.pts[k + 1] - e.pts[k]
                return (e.pts[k] + d * (seg > 0 ? (s - cum[k]) / seg : 0), simd_length(d) > 0 ? simd_normalize(d) : [0, 1])
            }
            let big = ["primary", "secondary", "tertiary", "trunk"].contains(e.type)
            if big {
                var s: Float = 12, side: Float = 1
                while s < length - 12 {
                    let (p, d) = at(s)
                    let q = p + perpRight(d) * side * (e.width / 2 + 0.6)
                    if owned(q) && !near(.lamp, q, 30) {
                        out.furniture.append([Float(Furniture.Kind.lamp.rawValue), q.x, q.y, atan2(-perpRight(d).x * side, -perpRight(d).y * side)])
                    }
                    s += 35; side = -side
                }
            }
            var s: Float = 20
            while s < length - 10 {
                let (p, d) = at(s)
                let q = p + perpRight(d) * (e.width / 2 + 0.5)
                if owned(q) && !near(.hydrant, q, 80) { out.furniture.append([Float(Furniture.Kind.hydrant.rawValue), q.x, q.y, 0]) }
                s += 100
            }
        }
        // Bike racks in front of every other shop.
        for (k, (h, n)) in shopFronts.enumerated() where k % 2 == 0 {
            let q = h + n * 1.6 + SIMD2(-n.y, n.x) * 2.5
            if owned(q) && !near(.bikeRack, q, 20) { out.furniture.append([Float(Furniture.Kind.bikeRack.rawValue), q.x, q.y, atan2(n.x, n.y)]) }
        }
    }

    // MARK: Gas stations

    /// Each gas station (amenity=fuel, a point or an area): its canopy over the pumps, from a mapped canopy roof
    /// (building=roof) when there is one, else the forecourt's shape, else a standard size beside the street.
    static func fuelStations(_ osm: OSMReader, owned: (SIMD2<Float>) -> Bool, into out: inout TileOutput) {
        var sites: [(c: SIMD2<Float>, area: [SIMD2<Float>]?, tags: [String: String])] = []
        for (id, t) in osm.nodeTags where t["amenity"] == "fuel" {
            if let p = osm.nodes[id] { sites.append((p, nil, t)) }
        }
        for w in osm.ways where w.tags["amenity"] == "fuel" && w.nds.count >= 4 && w.nds.first == w.nds.last {
            let poly = w.nds.dropLast().compactMap { osm.nodes[$0] }
            if poly.count >= 3 { sites.append((poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count), poly, w.tags)) }
        }
        let roofs: [[SIMD2<Float>]] = osm.ways.filter { $0.tags["building"] == "roof" && $0.nds.count >= 4 && $0.nds.first == $0.nds.last }
            .map { $0.nds.dropLast().compactMap { osm.nodes[$0] } }.filter { $0.count >= 3 }
        var done: [SIMD2<Float>] = []
        for site in sites {
            // A point inside an area mapped as the same station is the same station.
            if done.contains(where: { simd_distance($0, site.c) < 35 }) { continue }
            let canopyRoof = roofs.filter { r in
                let c = r.reduce(SIMD2<Float>(0, 0), +) / Float(r.count)
                return site.area.map { pointIn($0, c) } ?? (simd_distance(c, site.c) < 45)
            }.max { abs(area($0)) < abs(area($1)) }
            var centre: SIMD2<Float>, axis: SIMD2<Float>, hl: Float, hw: Float
            if let r = canopyRoof {
                (centre, axis, hl, hw) = obb(r)
            } else if let a = site.area {
                let f = obb(a)
                (centre, axis, hl, hw) = (f.0, f.1, min(11, f.2 * 0.6), min(6, f.3 * 0.5))
            } else {
                // Along the nearest street, a little back from it.
                var best: (Float, SIMD2<Float>, SIMD2<Float>)?
                for e in out.edges where e.type != "service" {
                    for j in 0..<(e.pts.count - 1) {
                        let q = closestOnSegment(site.c, e.pts[j], e.pts[j + 1])
                        let d = simd_distance(q, site.c)
                        if best == nil || d < best!.0 { best = (d, q, simd_normalize(e.pts[j + 1] - e.pts[j])) }
                    }
                }
                axis = best?.2 ?? [1, 0]
                centre = site.c
                if let b = best, b.0 < 40 { centre = b.1 + simd_normalize(site.c - b.1 + SIMD2(0.001, 0)) * min(b.0, 16) }
                (hl, hw) = (9, 5)
            }
            guard owned(centre) else { continue }
            done.append(site.c)
            let name = site.tags["brand"] ?? site.tags["name"] ?? site.tags["operator"] ?? "Gas"
            out.fuel.append(FuelData(x: centre.x, y: centre.y, ax: axis.x, ay: axis.y, hl: max(5, hl), hw: max(3.5, hw), n: name))
        }
    }
}
