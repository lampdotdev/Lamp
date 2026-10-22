import Foundation
import CoreGraphics
import ImageIO
import simd

/// The lie of the land: real elevation round the city, from the open Terrain Tiles (Mapzen's, on AWS; SRTM and
/// USGS data), fetched once and cached. Heights are metres above the city's centre, on a 10 m grid out to 5 km;
/// everything placed with `w3` stands on it. Flat (0) until loaded, or if it can't be fetched.
final class Terrain: @unchecked Sendable {
    static let shared = Terrain()

    let cell: Float = 10
    let reach: Float = 5000
    /// Heights, row by row from the south-west corner; empty while flat.
    private(set) var grid: [Float] = []
    private(set) var count = 0
    /// The lowest point, for the lawn under everything.
    private(set) var lowest: Float = 0

    /// Height above the centre at a point (x east, y north), smoothly between grid points.
    @inline(__always) func height(_ p: SIMD2<Float>) -> Float {
        let n = count
        guard n > 1 else { return 0 }
        let gx = max(0, min(Float(n - 1) - 0.001, (p.x + reach) / cell))
        let gy = max(0, min(Float(n - 1) - 0.001, (p.y + reach) / cell))
        let ix = Int(gx), iy = Int(gy)
        let fx = gx - Float(ix), fy = gy - Float(iy)
        return grid.withUnsafeBufferPointer { g in
            let a = g[iy * n + ix], b = g[iy * n + ix + 1], c = g[(iy + 1) * n + ix], d = g[(iy + 1) * n + ix + 1]
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        }
    }

    /// How far the ground strays from a straight line between `a` and `b`, and where along it (0–1) the most:
    /// checked where the line crosses the grid's lines (where the slope can change) and halfway between them.
    /// Nothing on ground that only slopes evenly, however steep.
    func bend(_ a: SIMD2<Float>, _ b: SIMD2<Float>) -> (dev: Float, at: Float) {
        guard count > 1 else { return (0, 0.5) }
        let d = b - a
        var ts: [Float] = [0, 1]
        for axis in 0..<2 where abs(d[axis]) > 1e-4 {
            let lo = min(a[axis], b[axis]), hi = max(a[axis], b[axis])
            var k = ceil((lo + reach) / cell)
            while k * cell - reach < hi {
                let t = (k * cell - reach - a[axis]) / d[axis]
                if t > 0 && t < 1 { ts.append(t) }
                k += 1
            }
        }
        ts.sort()
        let ha = height(a), hb = height(b)
        var worst: Float = 0, at: Float = 0.5
        func check(_ t: Float) {
            let e = abs(height(a + d * t) - (ha + (hb - ha) * t))
            if e > worst { worst = e; at = t }
        }
        for i in 0..<(ts.count - 1) {
            if i > 0 { check(ts[i]) }
            check((ts[i] + ts[i + 1]) / 2)
        }
        return (worst, at)
    }

    /// How far the ground strays from the flat triangle through its height at `a`, `b` and `c`: along its edges
    /// and at every grid point inside it.
    func bend(_ a: SIMD2<Float>, _ b: SIMD2<Float>, _ c: SIMD2<Float>) -> Float {
        guard count > 1 else { return 0 }
        var worst = max(bend(a, b).dev, bend(b, c).dev, bend(c, a).dev)
        let ha = height(a), hb = height(b), hc = height(c)
        let den = cross2(b - a, c - a)
        guard abs(den) > 1e-4 else { return worst }
        let lo = simd_min(a, simd_min(b, c)), hi = simd_max(a, simd_max(b, c))
        var x = ceil((lo.x + reach) / cell) * cell - reach
        while x < hi.x {
            var y = ceil((lo.y + reach) / cell) * cell - reach
            while y < hi.y {
                let p = SIMD2(x, y)
                let u = cross2(p - a, c - a) / den, v = cross2(b - a, p - a) / den
                if u >= 0 && v >= 0 && u + v <= 1 {
                    worst = max(worst, abs(height(p) - (ha + (hb - ha) * u + (hc - ha) * v)))
                }
                y += cell
            }
            x += cell
        }
        return worst
    }

    /// Which way is up at a point, in 3D (y up, north −z).
    func normal(_ p: SIMD2<Float>) -> SIMD3<Float> {
        let e: Float = 2
        let dx = (height(p + [e, 0]) - height(p - [e, 0])) / (2 * e)
        let dy = (height(p + [0, e]) - height(p - [0, e])) / (2 * e)
        return simd_normalize(SIMD3(-dx, 1, dy))
    }

    // MARK: Loading

    static let zoom = 14

    /// Fetches (or reads from the cache) the elevation tiles round the city and builds the grid.
    func load(_ city: CityConfig, status: @escaping @Sendable (String) -> Void) async {
        guard count == 0 else { return }
        status("Shaping the land round \(city.name)…")
        let n = Double(1 << Self.zoom)
        func tileXY(lat: Double, lon: Double) -> (Double, Double) {
            let x = (lon + 180) / 360 * n
            let r = lat * .pi / 180
            let y = (1 - log(tan(r) + 1 / cos(r)) / .pi) / 2 * n
            return (x, y)
        }
        let a = MapGeo.latLon([-reach, -reach]), b = MapGeo.latLon([reach, reach])
        let (x0, y1) = tileXY(lat: a.lat, lon: a.lon), (x1, y0) = tileXY(lat: b.lat, lon: b.lon)
        var tiles: [SIMD2<Int32>: [Float]] = [:]
        let folder = city.cacheFolder.appendingPathComponent("terrain", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for tx in Int(floor(x0))...Int(floor(x1)) {
            for ty in Int(floor(y0))...Int(floor(y1)) {
                let file = folder.appendingPathComponent("\(Self.zoom)_\(tx)_\(ty).png")
                var data = try? Data(contentsOf: file)
                if data == nil, let url = URL(string: "https://s3.amazonaws.com/elevation-tiles-prod/terrarium/\(Self.zoom)/\(tx)/\(ty).png"),
                   let (d, r) = try? await URLSession.shared.data(from: url), (r as? HTTPURLResponse)?.statusCode == 200 {
                    try? d.write(to: file)
                    data = d
                }
                if let data, let h = Self.decode(data) { tiles[SIMD2(Int32(tx), Int32(ty))] = h }
            }
        }
        guard !tiles.isEmpty else { return }
        // Resample onto the local grid.
        let cells = Int(2 * reach / cell) + 1
        var out = [Float](repeating: 0, count: cells * cells)
        func elevation(_ gx: Double, _ gy: Double) -> Float? {
            // gx, gy: global pixel coordinates at this zoom.
            let px = gx - 0.5, py = gy - 0.5
            let ix = Int(floor(px)), iy = Int(floor(py))
            let fx = Float(px - Double(ix)), fy = Float(py - Double(iy))
            func at(_ x: Int, _ y: Int) -> Float? {
                let t = SIMD2(Int32(x >> 8), Int32(y >> 8))
                guard let h = tiles[t] else { return nil }
                return h[(y & 255) * 256 + (x & 255)]
            }
            guard let a = at(ix, iy), let b = at(ix + 1, iy), let c = at(ix, iy + 1), let d = at(ix + 1, iy + 1) else { return at(ix, iy) }
            return (a * (1 - fx) + b * fx) * (1 - fy) + (c * (1 - fx) + d * fx) * fy
        }
        let base: Float = {
            let (cx, cy) = tileXY(lat: city.lat, lon: city.lon)
            return elevation(cx * 256, cy * 256) ?? 0
        }()
        for j in 0..<cells {
            for i in 0..<cells {
                let p = SIMD2(Float(i) * cell - reach, Float(j) * cell - reach)
                let ll = MapGeo.latLon(p)
                let (tx, ty) = tileXY(lat: ll.lat, lon: ll.lon)
                out[j * cells + i] = (elevation(tx * 256, ty * 256) ?? base) - base
            }
        }
        out = Self.smoothed(out, cells, radius: Self.smoothing)
        grid = out
        lowest = out.min() ?? 0
        count = cells
    }

    /// The elevation data is noisy at the scale of a street (bumps of 5–10 cm every few metres, and the odd
    /// spike); real streets and lawns aren't. Two passes of a box blur this many cells each side (spread over about
    /// 50 m) leave the hills and valleys and take out the noise, so the ground only bends where the land does.
    static let smoothing = 1

    static func smoothed(_ h: [Float], _ n: Int, radius r: Int) -> [Float] {
        guard r > 0, n > 2 * r else { return h }
        var a = h, b = h
        for _ in 0..<2 {
            // Along rows, then along columns.
            for j in 0..<n {
                for i in 0..<n {
                    var s: Float = 0, k: Float = 0
                    for d in -r...r where i + d >= 0 && i + d < n { s += a[j * n + i + d]; k += 1 }
                    b[j * n + i] = s / k
                }
            }
            for j in 0..<n {
                for i in 0..<n {
                    var s: Float = 0, k: Float = 0
                    for d in -r...r where j + d >= 0 && j + d < n { s += b[(j + d) * n + i]; k += 1 }
                    a[j * n + i] = s / k
                }
            }
        }
        return a
    }

    /// Terrarium tiles keep the height in the colour: (red × 256 + green + blue / 256) − 32768 metres.
    private static func decode(_ data: Data) -> [Float]? {
        guard let src = CGImageSourceCreateWithData(data as CFData, nil), let img = CGImageSourceCreateImageAtIndex(src, 0, nil),
              img.width == 256, img.height == 256, img.bitsPerComponent == 8, let raw = img.dataProvider?.data else { return nil }
        // The bytes as stored, untouched by colour management (which would change the heights).
        let bytes = CFDataGetBytePtr(raw)!
        let step = img.bitsPerPixel / 8, row = img.bytesPerRow
        guard step >= 3 else { return nil }
        var out = [Float](repeating: 0, count: 256 * 256)
        for y in 0..<256 {
            for x in 0..<256 {
                let o = y * row + x * step
                out[y * 256 + x] = Float(bytes[o]) * 256 + Float(bytes[o + 1]) + Float(bytes[o + 2]) / 256 - 32768
            }
        }
        return out
    }
}
