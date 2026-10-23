import Foundation
import simd

/// Shapes from map data, the same way the script that prepared the bundled downtown makes them: multipolygon
/// rings joined end to end, holes bridged into their outer ring for triangulating, and areas and lines cut along
/// the edges of the squares the city is drawn in (and of the map tiles and the bundled area), so each piece is
/// drawn by the square it's in.
enum MapShapes {
    static let square: Float = 150

    /// Ways (node id lists) joined end to end into closed rings (first == last).
    static func joinRings(_ segs: [[Int64]]) -> [[Int64]] {
        var rings: [[Int64]] = []
        var pending = segs.filter { $0.count >= 2 }
        while !pending.isEmpty {
            var cur = pending.removeFirst()
            var progress = true
            while cur.first != cur.last && progress {
                progress = false
                for (i, s) in pending.enumerated() {
                    if s.first == cur.last { cur += s.dropFirst() }
                    else if s.last == cur.last { cur += s.reversed().dropFirst() }
                    else if s.last == cur.first { cur = Array(s.dropLast()) + cur }
                    else if s.first == cur.first { cur = Array(s.reversed().dropLast()) + cur }
                    else { continue }
                    pending.remove(at: i)
                    progress = true
                    break
                }
            }
            if cur.first == cur.last && cur.count >= 4 { rings.append(cur) }
        }
        return rings
    }

    /// A ring cut to a rectangle (Sutherland-Hodgman); a concave ring may gain edges along the rectangle.
    static func clip(_ poly: [SIMD2<Float>], _ lo: SIMD2<Float>, _ hi: SIMD2<Float>) -> [SIMD2<Float>] {
        func pass(_ pts: [SIMD2<Float>], _ axis: Int, _ v: Float, _ keepAbove: Bool) -> [SIMD2<Float>] {
            var out: [SIMD2<Float>] = []
            guard !pts.isEmpty else { return out }
            func inside(_ p: SIMD2<Float>) -> Bool { keepAbove ? p[axis] >= v : p[axis] <= v }
            func cut(_ p: SIMD2<Float>, _ q: SIMD2<Float>) -> SIMD2<Float> {
                let t = (v - p[axis]) / (q[axis] - p[axis])
                return p + (q - p) * t
            }
            for i in 0..<pts.count {
                let p = pts[(i - 1 + pts.count) % pts.count], q = pts[i]
                let ip = inside(p), iq = inside(q)
                if iq {
                    if !ip { out.append(cut(p, q)) }
                    out.append(q)
                } else if ip { out.append(cut(p, q)) }
            }
            return out
        }
        var pts = poly
        pts = pass(pts, 0, lo.x, true)
        pts = pass(pts, 0, hi.x, false)
        pts = pass(pts, 1, lo.y, true)
        pts = pass(pts, 1, hi.y, false)
        return pts
    }

    /// Triangles over a ring, or over a ring with holes bridged in (`order` may visit a point twice).
    static func earclip(_ poly: [SIMD2<Float>], order: [Int]? = nil) -> [Int] {
        var idx = order ?? Array(poly.indices)
        var tris: [Int] = []
        func cr(_ o: SIMD2<Float>, _ a: SIMD2<Float>, _ b: SIMD2<Float>) -> Float { cross2(a - o, b - o) }
        var guardCount = 0
        while idx.count > 3 && guardCount < 20000 {
            guardCount += 1
            var found = false
            for k in 0..<idx.count {
                let i0 = idx[(k - 1 + idx.count) % idx.count], i1 = idx[k], i2 = idx[(k + 1) % idx.count]
                let a = poly[i0], b = poly[i1], c = poly[i2]
                if cr(a, b, c) <= 1e-9 { continue }
                var ok = true
                for j in idx where j != i0 && j != i1 && j != i2 {
                    let p = poly[j]
                    if p == a || p == b || p == c { continue }
                    if cr(a, b, p) >= 0 && cr(b, c, p) >= 0 && cr(c, a, p) >= 0 { ok = false; break }
                }
                if ok { tris += [i0, i1, i2]; idx.remove(at: k); found = true; break }
            }
            if !found { break }
        }
        if idx.count == 3 { tris += idx } else if idx.count > 3 { for k in 1..<(idx.count - 1) { tris += [idx[0], idx[k], idx[k + 1]] } }
        return tris
    }

    /// Points (the outer ring, counter-clockwise, then each hole, clockwise) and the triangles covering the outer
    /// ring less the holes.
    static func withHoles(_ outer: [SIMD2<Float>], _ holes: [[SIMD2<Float>]]) -> (pts: [SIMD2<Float>], tris: [Int]) {
        let o = TileProcessor.area(outer) < 0 ? Array(outer.reversed()) : outer
        let hs = holes.filter { $0.count >= 3 }.map { TileProcessor.area($0) > 0 ? Array($0.reversed()) : $0 }
        guard !hs.isEmpty else { return (o, earclip(o)) }
        var pts = o
        var order = Array(o.indices)
        for h in hs.sorted(by: { ($0.map(\.x).max() ?? 0) > ($1.map(\.x).max() ?? 0) }) {
            let base = pts.count
            pts += h
            let m = h.indices.max { h[$0].x < h[$1].x }!
            let hp = h[m]
            // The nearest ring point to the right to bridge to (good enough for map data).
            var best: Int?, bd = Float.infinity
            for (k, i) in order.enumerated() where pts[i].x >= hp.x {
                let d = simd_distance_squared(pts[i], hp)
                if d < bd { bd = d; best = k }
            }
            if best == nil { best = order.indices.min { simd_distance_squared(pts[order[$0]], hp) < simd_distance_squared(pts[order[$1]], hp) } }
            guard let b = best else { continue }
            let holeOrder = (0..<h.count).map { base + (m + $0) % h.count } + [base + m]
            order = Array(order[...b]) + holeOrder + [order[b]] + Array(order[(b + 1)...])
        }
        return (pts, earclip(pts, order: order))
    }

    /// Where to cut between `lo` and `hi`: the squares' edges, the map tiles' and any `extra` lines.
    static func cuts(_ lo: Float, _ hi: Float, _ extra: [Float]) -> [Float] {
        var vals = Set<Float>()
        for step: Float in [square, 500] {
            var k = floor(lo / step) + 1
            while k * step < hi { vals.insert(k * step); k += 1 }
        }
        for v in extra where v > lo && v < hi { vals.insert(v) }
        return [lo] + vals.sorted() + [hi]
    }

    /// The square holding a point (CityTiles' key: x east, rows southward).
    static func key(_ p: SIMD2<Float>) -> SIMD2<Int32> { SIMD2(Int32(floor(p.x / square)), Int32(floor(-p.y / square))) }

    /// Triangles cut along the squares' edges and `extra` lines, grouped by square, keeping only pieces whose
    /// middle is `owned`.
    static func cutTriangles(_ pts: [SIMD2<Float>], _ tris: [Int], owned: (SIMD2<Float>) -> Bool,
                             xExtra: [Float], yExtra: [Float]) -> [SIMD2<Int32>: (pts: [SIMD2<Float>], tris: [Int])] {
        var pieces: [SIMD2<Int32>: (pts: [SIMD2<Float>], tris: [Int])] = [:]
        for t in stride(from: 0, to: tris.count - 2, by: 3) {
            guard tris[t + 2] < pts.count else { continue }
            let tri = [pts[tris[t]], pts[tris[t + 1]], pts[tris[t + 2]]]
            guard abs(TileProcessor.area(tri)) > 1e-4 else { continue }
            let xs = tri.map(\.x), ys = tri.map(\.y)
            let xc = cuts(xs.min()!, xs.max()!, xExtra), yc = cuts(ys.min()!, ys.max()!, yExtra)
            for i in 0..<(xc.count - 1) {
                let slab = xc.count > 2 ? clip(tri, [xc[i], -1e9], [xc[i + 1], 1e9]) : tri
                guard slab.count >= 3 else { continue }
                for j in 0..<(yc.count - 1) {
                    let cell = yc.count > 2 ? clip(slab, [-1e9, yc[j]], [1e9, yc[j + 1]]) : slab
                    let a = TileProcessor.area(cell)
                    guard cell.count >= 3, abs(a) >= 0.05 else { continue }
                    let mid = cell.reduce(SIMD2<Float>(0, 0), +) / Float(cell.count)
                    guard owned(mid) else { continue }
                    let k = key(mid)
                    var piece = pieces[k] ?? ([], [])
                    let b = piece.pts.count
                    piece.pts += cell
                    for q in 1..<(cell.count - 1) { piece.tris += a > 0 ? [b, b + q, b + q + 1] : [b, b + q + 1, b + q] }
                    pieces[k] = piece
                }
            }
        }
        return pieces
    }

    /// A line cut along the squares' edges and `extra` lines: the owned pieces.
    static func cutLine(_ pts: [SIMD2<Float>], owned: (SIMD2<Float>) -> Bool, xExtra: [Float], yExtra: [Float]) -> [[SIMD2<Float>]] {
        var out: [[SIMD2<Float>]] = []
        var cur: (key: SIMD2<Int32>?, pts: [SIMD2<Float>])?
        func flush() { if let c = cur, c.key != nil, c.pts.count >= 2 { out.append(c.pts) } }
        for i in 0..<max(0, pts.count - 1) {
            let a = pts[i], b = pts[i + 1]
            var ts: [Float] = [0, 1]
            for axis in 0..<2 {
                let lo = min(a[axis], b[axis]), hi = max(a[axis], b[axis])
                guard hi - lo > 1e-6 else { continue }
                for v in cuts(lo, hi, axis == 0 ? xExtra : yExtra).dropFirst().dropLast() { ts.append((v - a[axis]) / (b[axis] - a[axis])) }
            }
            ts = Array(Set(ts)).sorted()
            for j in 0..<(ts.count - 1) {
                let p = a + (b - a) * ts[j], q = a + (b - a) * ts[j + 1]
                let mid = (p + q) / 2
                let k: SIMD2<Int32>? = owned(mid) ? key(mid) : nil
                if let c = cur, c.key == k { cur!.pts.append(q) } else { flush(); cur = (k, [p, q]) }
            }
        }
        flush()
        return out
    }

    /// A tagged colour (a name or #rrggbb) as 0–1 RGB.
    static func colour(_ value: String?) -> [Float]? {
        guard var v = value?.lowercased() else { return nil }
        v = v.replacingOccurrences(of: " ", with: "").replacingOccurrences(of: "_", with: "")
        if v.hasPrefix("#") {
            var h = String(v.dropFirst())
            if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
            guard h.count == 6, let n = UInt32(h, radix: 16) else { return nil }
            return [Float((n >> 16) & 255) / 255, Float((n >> 8) & 255) / 255, Float(n & 255) / 255].map { ($0 * 1000).rounded() / 1000 }
        }
        return colours[v]
    }

    static let colours: [String: [Float]] = [
        "white": [0.94, 0.94, 0.92], "black": [0.12, 0.12, 0.12], "grey": [0.55, 0.55, 0.55], "gray": [0.55, 0.55, 0.55],
        "lightgrey": [0.78, 0.78, 0.76], "lightgray": [0.78, 0.78, 0.76], "darkgrey": [0.35, 0.35, 0.35], "darkgray": [0.35, 0.35, 0.35],
        "silver": [0.75, 0.75, 0.75], "red": [0.62, 0.2, 0.16], "darkred": [0.45, 0.12, 0.1], "maroon": [0.45, 0.13, 0.12],
        "brown": [0.5, 0.33, 0.22], "tan": [0.82, 0.71, 0.55], "beige": [0.88, 0.82, 0.68], "cream": [0.95, 0.91, 0.78],
        "ivory": [0.96, 0.94, 0.85], "yellow": [0.92, 0.82, 0.4], "orange": [0.85, 0.5, 0.2], "gold": [0.85, 0.7, 0.3],
        "green": [0.3, 0.5, 0.3], "darkgreen": [0.15, 0.3, 0.15], "olive": [0.45, 0.45, 0.25], "blue": [0.3, 0.4, 0.6],
        "lightblue": [0.6, 0.72, 0.85], "navy": [0.12, 0.16, 0.35], "teal": [0.2, 0.45, 0.45], "purple": [0.4, 0.25, 0.45],
        "pink": [0.88, 0.65, 0.68], "sandybrown": [0.85, 0.65, 0.45], "peru": [0.8, 0.52, 0.25], "sienna": [0.55, 0.3, 0.18],
        "khaki": [0.85, 0.8, 0.55], "wheat": [0.92, 0.85, 0.7], "salmon": [0.9, 0.55, 0.45], "terracotta": [0.75, 0.4, 0.3],
        "brick": [0.6, 0.28, 0.2], "copper": [0.45, 0.65, 0.55],
    ]

    /// What kind of ground an area is: water, wood, a kind of park, a parking lot, or nothing drawn.
    static func areaKind(_ t: [String: String]) -> String? {
        // A golf course's parts: fairways, greens, tees, sand traps and rough.
        if let g = t["golf"], ["fairway", "green", "tee", "bunker", "rough", "driving_range"].contains(g) {
            return "golf:" + (g == "driving_range" ? "fairway" : g)
        }
        if t["natural"] == "water" || t["waterway"] == "riverbank" || ["reservoir", "basin"].contains(t["landuse"] ?? "") { return "water" }
        if ["wood", "scrub"].contains(t["natural"] ?? "") || t["landuse"] == "forest" { return "wood" }
        if ["park", "pitch", "garden", "playground", "golf_course", "nature_reserve", "dog_park"].contains(t["leisure"] ?? "") ||
            ["grass", "recreation_ground", "cemetery", "village_green", "meadow", "flowerbed"].contains(t["landuse"] ?? "") ||
            t["natural"] == "grassland" {
            // A pitch carries its sport, for its surface and markings.
            if t["leisure"] == "pitch" { return "pitch:" + (t["sport"] ?? "") }
            return t["leisure"] ?? t["landuse"] ?? "park"
        }
        if t["amenity"] == "parking" && (t["parking"] ?? "surface") == "surface" && t["building"] == nil { return "parking" }
        // Land use: paving where it's commercial, retail or industrial (downtown); residential stays lawn.
        if ["retail", "commercial", "industrial"].contains(t["landuse"] ?? "") || t["amenity"] == "fuel" { return "paved" }
        return nil
    }

    /// A parking lot piece's spaces, laid as CityGeometry paints them (double rows 5.5 m deep either side of a 7 m
    /// aisle, 2.6 m wide, from a fixed origin along `angle`): each space's middle and the way a car parks in it,
    /// nose in.
    static func stalls(_ pts: [SIMD2<Float>], _ t: [Int], angle: Float) -> [(center: SIMD2<Float>, facing: SIMD2<Float>)] {
        var tris: [(SIMD2<Float>, SIMD2<Float>, SIMD2<Float>)] = []
        for i in stride(from: 0, to: t.count - 2, by: 3) where t[i + 2] < pts.count { tris.append((pts[t[i]], pts[t[i + 1]], pts[t[i + 2]])) }
        guard !tris.isEmpty, !pts.isEmpty else { return [] }
        func inside(_ p: SIMD2<Float>) -> Bool {
            tris.contains { t in
                let d1 = cross2(t.1 - t.0, p - t.0), d2 = cross2(t.2 - t.1, p - t.1), d3 = cross2(t.0 - t.2, p - t.2)
                return !((d1 < 0 || d2 < 0 || d3 < 0) && (d1 > 0 || d2 > 0 || d3 > 0))
            }
        }
        let u = SIMD2(cos(angle), sin(angle)), v = SIMD2(-u.y, u.x)
        let su = pts.map { simd_dot($0, u) }, sv = pts.map { simd_dot($0, v) }
        let (u0, u1, v0, v1) = (su.min()!, su.max()!, sv.min()!, sv.max()!)
        let stall: Float = 2.6, depth: Float = 5.5, module: Float = 18
        var out: [(SIMD2<Float>, SIMD2<Float>)] = []
        var m = (v0 / module).rounded(.down) * module
        while m < v1 {
            for (r0, r1, nose) in [(m, m + depth, -v), (m + module - depth, m + module, v)] {
                var s = (u0 / stall).rounded(.down) * stall
                while s + stall <= u1 + stall {
                    let c = u * (s + stall / 2) + v * ((r0 + r1) / 2)
                    if inside(u * s + v * (r0 + 0.3)) && inside(u * (s + stall) + v * (r0 + 0.3)) && inside(u * s + v * (r1 - 0.3)) && inside(u * (s + stall) + v * (r1 - 0.3)) {
                        out.append((c, nose))
                    }
                    s += stall
                }
            }
            m += module
        }
        return out.map { (center: $0.0, facing: $0.1) }
    }

    static let waterwayWidth: [String: Float] = ["river": 22, "canal": 8, "stream": 3]
}
