import SwiftUI
import RealityKit

/// Loads the city's data round the car: map tiles are fetched from OpenStreetMap (kept on disk after the first
/// time), turned into streets and buildings off the main thread, and joined to the road graph, collisions and
/// shops. Drawing them is CityTiles' job, through the scene's streaming.
@MainActor
final class TileStreamer {
    static let size: Float = 500
    let city: City
    private let onTile: (TileOutput, CityPart) -> Void

    private struct Tile { var loaded = false; var failedAt: Date? }
    private var tiles: [SIMD2<Int32>: Tile] = [:]
    private var inFlight = Set<SIMD2<Int32>>()
    private var lastCheck: Float = -10

    /// A trip being planned, from where it started to where it's going: the tiles along the way load too (after
    /// those round the car), so a route can be found through them.
    var trip: (from: SIMD2<Float>, to: SIMD2<Float>)?
    /// Whether tiles along the trip are still to come.
    private(set) var tripPending = false

    /// Loaded well beyond what's drawn (CityTiles.radius), so squares are drawn with their data already here.
    let loadRadius: Float = 1000

    init(city: City, onTile: @escaping (TileOutput, CityPart) -> Void) {
        self.city = city
        self.onTile = onTile
    }

    private func rect(_ k: SIMD2<Int32>) -> (SIMD2<Float>, SIMD2<Float>) {
        let lo = SIMD2(Float(k.x), Float(k.y)) * Self.size
        return (lo, lo + Self.size)
    }

    private func distance(_ p: SIMD2<Float>, to k: SIMD2<Int32>) -> Float {
        let (lo, hi) = rect(k)
        return simd_length(simd_max(simd_max(lo - p, p - hi), .zero))
    }

    /// Entirely inside downtown, which ships with the game.
    private func bundled(_ k: SIMD2<Int32>) -> Bool {
        let (lo, hi) = rect(k)
        return city.inBundled(lo) && city.inBundled(hi) && city.inBundled([lo.x, hi.y]) && city.inBundled([hi.x, lo.y])
    }

    /// The part of the map being looked at on the big map: its tiles load too (after those round the car and
    /// along a trip), a few at once, so zooming out shows more of the city.
    var lookArea: (lo: SIMD2<Float>, hi: SIMD2<Float>)?
    /// Whether tiles in the looked-at area are still to come.
    private(set) var lookPending = false

    private func wanted(_ k: SIMD2<Int32>) -> Bool {
        if bundled(k) || inFlight.contains(k) { return false }
        if let t = tiles[k], t.loaded || (t.failedAt.map { Date().timeIntervalSince($0) < 20 } ?? false) { return false }
        return true
    }

    func update(player p: SIMD2<Float>, heading v: SIMD2<Float> = .zero, time: Float) {
        guard time - lastCheck > 0.5 else { return }
        lastCheck = time
        // Two at a time: a tile can take half a minute when the map servers are busy, which a car outruns one at a
        // time. Two is what the main server lets one address run at once.
        while inFlight.count < 2, let k = next(player: p, heading: v) { load(k) }
        missingNearby = missing(near: p, within: 350)
    }

    /// Whether the map round the car isn't all here yet (still coming, or failed and waiting to be tried again):
    /// the HUD says the streets ahead are loading.
    private(set) var missingNearby = false

    private func missing(near p: SIMD2<Float>, within r: Float) -> Bool {
        let here = SIMD2(Int32(floor(p.x / Self.size)), Int32(floor(p.y / Self.size)))
        for x in Int32(-1)...1 {
            for y in Int32(-1)...1 {
                let k = here &+ SIMD2(x, y)
                if bundled(k) || tiles[k]?.loaded == true { continue }
                if distance(p, to: k) < r { return true }
            }
        }
        return false
    }

    /// The next tile to fetch: round the car, those where it's heading first, then along a trip, then in the area
    /// the big map shows.
    private func next(player p: SIMD2<Float>, heading v: SIMD2<Float> = .zero) -> SIMD2<Int32>? {
        // Where the car will be in about fifteen seconds, at most 400 m on: the tile it's in comes first, then
        // those nearest that point, so the streets ahead arrive before those behind.
        var ahead = p + v * 15
        if simd_distance(ahead, p) > 400 { ahead = p + simd_normalize(v) * 400 }
        let here = SIMD2(Int32(floor(p.x / Self.size)), Int32(floor(p.y / Self.size)))
        var best: (SIMD2<Int32>, Float)?
        let reach = Int32(ceil(loadRadius / Self.size)) + 1
        for x in -reach...reach {
            for y in -reach...reach {
                let k = here &+ SIMD2(x, y)
                guard wanted(k) else { continue }
                let d = distance(p, to: k)
                guard d < loadRadius else { continue }
                // The car's own tile below every other, even one holding the point ahead (which scores 0 too).
                let score = d == 0 ? -1 : distance(ahead, to: k)
                if best == nil || score < best!.1 { best = (k, score) }
            }
        }
        if best == nil, let trip {
            // Along the trip: tiles within 600 m of the straight line there, nearest the car first.
            let lo = simd_min(trip.from, trip.to) - 700, hi = simd_max(trip.from, trip.to) + 700
            let a = SIMD2(Int32(floor(lo.x / Self.size)), Int32(floor(lo.y / Self.size)))
            let b = SIMD2(Int32(floor(hi.x / Self.size)), Int32(floor(hi.y / Self.size)))
            for x in a.x...b.x {
                for y in a.y...b.y {
                    let k = SIMD2(x, y)
                    guard wanted(k) else { continue }
                    let (tlo, thi) = rect(k)
                    let mid = (tlo + thi) / 2
                    guard distanceToSegment(mid, trip.from, trip.to) < 600 else { continue }
                    let d = distance(p, to: k)
                    if best == nil || d < best!.1 { best = (k, d) }
                }
            }
            tripPending = best != nil
        }
        if best == nil, let look = lookArea {
            // What the big map shows, middle first, within 6 km of downtown.
            let mid = (look.lo + look.hi) / 2
            let a = SIMD2(Int32(floor(look.lo.x / Self.size)), Int32(floor(look.lo.y / Self.size)))
            let b = SIMD2(Int32(floor(look.hi.x / Self.size)), Int32(floor(look.hi.y / Self.size)))
            if b.x - a.x <= 24 && b.y - a.y <= 24 {
                for x in a.x...b.x {
                    for y in a.y...b.y {
                        let k = SIMD2(x, y)
                        guard wanted(k) else { continue }
                        let (tlo, thi) = rect(k)
                        let c = (tlo + thi) / 2
                        guard simd_length(c) < 6000 else { continue }
                        let d = simd_distance(c, mid)
                        if best == nil || d < best!.1 { best = (k, d) }
                    }
                }
            }
            lookPending = best != nil || !inFlight.isEmpty
        } else {
            lookPending = false
        }
        return best?.0
    }

    private func load(_ k: SIMD2<Int32>) {
        inFlight.insert(k)
        let (lo, hi) = rect(k)
        let bundledHalf = city.half
        Task {
            let output: TileOutput? = await Task.detached(priority: .userInitiated) {
                guard let data = await Self.fetch(k, lo: lo, hi: hi) else { return nil }
                let osm = OSMReader.read(data)
                return TileProcessor.process(osm, rect: (lo, hi), bundled: bundledHalf)
            }.value
            self.inFlight.remove(k)
            guard let output else {
                self.tiles[k] = Tile(loaded: false, failedAt: Date())
                return
            }
            self.install(k, output)
        }
    }

    /// The tile's map data: from the city's cache, or from the Overpass API.
    nonisolated private static func fetch(_ k: SIMD2<Int32>, lo: SIMD2<Float>, hi: SIMD2<Float>) async -> Data? {
        let file = CityConfig.current.cacheFolder.appendingPathComponent("tiles/\(k.x)_\(k.y).osm")
        if let data = await Overpass.fetch(lo: lo, hi: hi, cache: file) { return data }
        print("Map tile \(k.x),\(k.y) couldn't be fetched (the map servers are busy); trying again shortly")
        return nil
    }

    /// Adds the tile's streets to the road graph and builds it into the scene.
    private func install(_ k: SIMD2<Int32>, _ out: TileOutput) {
        let firstNode = city.nodes.count
        var part = CityPart()
        for e in out.edges where e.pts.count >= 2 {
            let a = city.node(e.a, at: e.pts[0]), b = city.node(e.b, at: e.pts[e.pts.count - 1])
            part.edges.append(city.addEdge(a: a, b: b, pts: e.pts, name: e.name, type: e.type, width: e.width,
                                           driveWidth: e.driveWidth, lanes: e.lanes, oneway: e.oneway, parking: e.parking,
                                           sidewalks: e.sidewalks, stops: e.stops))
        }
        for id in out.signals { if let i = city.nodeByOSM[id], i >= firstNode { city.nodes[i].signal = true } }
        for id in out.allStops { if let i = city.nodeByOSM[id], !city.nodes[i].signal { city.nodes[i].allStop = true } }
        part.nodes = Array(firstNode..<city.nodes.count)
        for b in out.buildings where (b.mh ?? 0) < 1.5 { city.addBuilding(points(b.p), holes: (b.ho ?? []).map(points)) }
        for b in out.buildings { city.addAddress(b) }
        for g in out.grass { city.addArea(g) }
        city.addPlaces(out.places)
        for p in out.paths { city.addPath(p) }
        for t in out.trees { city.addPost(SIMD2(t[0], t[1]), 0.35, tree: t.count > 2 ? t[2] : 1) }
        part.buildings = out.buildings
        part.grass = out.grass
        part.lots = out.lots
        part.paths = out.paths
        part.furniture = out.furniture
        part.wires = out.wires
        part.fuel = out.fuel
        part.shops = out.shops
        part.trees = out.trees

        let started = Date()
        onTile(out, part)
        tiles[k] = Tile(loaded: true)
        print(String(format: "Map data %d,%d: %d streets, %d buildings, %d shops, in %.2f s", k.x, k.y,
                     out.edges.count, out.buildings.count, out.shops.count, Date().timeIntervalSince(started)))
    }
}
