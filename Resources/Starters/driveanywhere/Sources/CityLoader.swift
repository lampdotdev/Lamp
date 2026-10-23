import Foundation
import simd

/// OpenStreetMap data from the Overpass API: everything in a box (nodes, ways, relations), with the ways and nodes
/// that multipolygons in it are made of, so parks, water and buildings come whole. Railway route relations come
/// without their members (which would be the whole line across the country).
enum Overpass {
    static let servers = ["https://overpass-api.de/api/interpreter",
                          "https://maps.mail.ru/osm/tools/overpass/api/interpreter",
                          "https://overpass.kumi.systems/api/interpreter"]

    /// When each server last failed (busy, timed out, refused): it's passed over for `restFor` seconds, so a
    /// mirror that's down doesn't hold up every request (one took 80 s to answer that it couldn't), and a busy
    /// server isn't asked again at once, as its usage policy asks.
    nonisolated(unsafe) private static var failedAt: [String: Date] = [:]
    private static let lock = NSLock()
    private static let restFor: TimeInterval = 120

    /// The servers to try, those that haven't failed lately first.
    private static var ordered: [String] {
        lock.lock(); defer { lock.unlock() }
        let now = Date()
        let resting = { (s: String) in failedAt[s].map { now.timeIntervalSince($0) < restFor } ?? false }
        let ready = servers.filter { !resting($0) }
        // All resting: try the main one again rather than give up.
        return ready.isEmpty ? [servers[0]] : ready
    }

    private static func noteFailed(_ server: String) {
        lock.lock(); failedAt[server] = Date(); lock.unlock()
    }

    static func query(lo: SIMD2<Float>, hi: SIMD2<Float>, timeout: Int = 90) -> String {
        let a = MapGeo.latLon(lo), b = MapGeo.latLon(hi)
        let bbox = String(format: "%.6f,%.6f,%.6f,%.6f", a.lat, a.lon, b.lat, b.lon)
        return """
        [out:xml][timeout:\(timeout)];nwr(\(bbox))->.all;rel.all[type=multipolygon]->.mp;way(r.mp)->.mpw;\
        (way.all;.mpw;)->.w;node(w.w)->.wn;(.all;.mpw;.wn;);out body;
        """
    }

    /// The box's data: from `cache` when it's there, else from each server in turn (saved to `cache`).
    static func fetch(lo: SIMD2<Float>, hi: SIMD2<Float>, cache: URL, timeout: Int = 90) async -> Data? {
        if let data = try? Data(contentsOf: cache), data.count > 200 { return data }
        let body = "data=" + (query(lo: lo, hi: hi, timeout: timeout).addingPercentEncoding(withAllowedCharacters: .alphanumerics) ?? "")
        for server in ordered {
            guard let url = URL(string: server) else { continue }
            var request = URLRequest(url: url, timeoutInterval: TimeInterval(timeout + 30))
            request.httpMethod = "POST"
            request.httpBody = body.data(using: .utf8)
            request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
            request.setValue("DriveAnywhere/1.0 (a driving game for macOS made with Lamp)", forHTTPHeaderField: "User-Agent")
            guard let (data, response) = try? await URLSession.shared.data(for: request),
                  (response as? HTTPURLResponse)?.statusCode == 200, data.count > 200,
                  String(decoding: data.suffix(64), as: UTF8.self).contains("</osm>") else { noteFailed(server); continue }
            try? FileManager.default.createDirectory(at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? data.write(to: cache)
            return data
        }
        return nil
    }
}

/// The city's downtown, made the first time the city is opened and kept in its cache: its map data fetched (or
/// read from the cache), read by the same rules as the streamed tiles, and saved as the game's own file.
enum CityLoader {
    /// Bumped when the rules change, so a downtown made by older rules is made again.
    static let version = 15

    static func load(_ city: CityConfig, status: @escaping @Sendable (String) -> Void) async -> CityFile? {
        let folder = city.cacheFolder
        let made = folder.appendingPathComponent("downtown-v\(version).json")
        if let data = try? Data(contentsOf: made), let file = try? JSONDecoder().decode(CityFile.self, from: data) { return file }
        let half = city.downtownHalf
        var data: Data?
        for attempt in 0..<8 {
            status(attempt == 0 ? "Downloading the map of \(city.name)…" : "The map servers are busy; trying again…")
            data = await Overpass.fetch(lo: -half, hi: half, cache: folder.appendingPathComponent("downtown.osm"), timeout: 180)
            if data != nil { break }
            try? await Task.sleep(for: .seconds(min(60, 5 << attempt)))
        }
        guard let data else { return nil }
        status("Building downtown \(city.name)…")
        let file = build(OSMReader.read(data), half: half)
        if let out = try? JSONEncoder().encode(file) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try? out.write(to: made)
        }
        return file
    }

    /// The downtown from its map data: roads joined into a graph of crossings, and everything else as the tiles have it.
    static func build(_ osm: OSMReader, half: SIMD2<Float>) -> CityFile {
        let out = TileProcessor.process(osm, rect: (-half, half), bundled: nil)
        // Crossings: every road end, with its widest road's half width and whether it has signals.
        var index: [Int64: Int] = [:]
        var nodes: [[Double]] = []
        func node(_ id: Int64, _ p: SIMD2<Float>) -> Int {
            if let i = index[id] { return i }
            index[id] = nodes.count
            nodes.append([Double(r2(p.x)), Double(r2(p.y)), 0, 0, Double(id)])
            return nodes.count - 1
        }
        var edges: [EdgeData] = []
        for e in out.edges {
            let a = node(e.a, e.pts[0]), b = node(e.b, e.pts[e.pts.count - 1])
            for i in [a, b] { nodes[i][3] = max(nodes[i][3], Double(e.width / 2)) }
            edges.append(EdgeData(a: a, b: b, p: TileProcessor.flat(e.pts), n: e.name, t: e.type, w: r2(e.width), dw: r2(e.driveWidth),
                                  l: e.lanes, o: e.oneway ? 1 : 0, pk: [e.parking.0 ? 1 : 0, e.parking.1 ? 1 : 0],
                                  sw: [e.sidewalks.0 ? 1 : 0, e.sidewalks.1 ? 1 : 0],
                                  st: e.stops.0 || e.stops.1 ? [e.stops.0 ? 1 : 0, e.stops.1 ? 1 : 0] : nil))
        }
        for id in out.signals { if let i = index[id] { nodes[i][2] = 1 } }
        for id in out.allStops { if let i = index[id], nodes[i][2] == 0 { nodes[i][2] = 2 } }
        for i in nodes.indices { nodes[i][3] = (nodes[i][3] * 100).rounded() / 100 }
        let (rails, xings) = railways(osm, half: half, edges: out.edges)
        return CityFile(bounds: [half.x, half.y], nodes: nodes, edges: edges, buildings: out.buildings, grass: out.grass, lots: out.lots,
                        paths: out.paths, shops: out.shops, parked: out.parked, trees: out.trees, rails: rails, xings: xings, hoods: out.places,
                        furn: out.furniture, wires: out.wires, fuel: out.fuel)
    }

    private static func r2(_ v: Float) -> Float { (v * 100).rounded() / 100 }

    /// Railway lines (railway=rail) through the downtown, joined end to end by name, and their level crossings with
    /// the streets. A line used by a long-distance route gets an intercity train, one used by another passenger
    /// route a regional train, and the rest freight.
    static func railways(_ osm: OSMReader, half: SIMD2<Float>, edges: [TileEdge]) -> ([RailData], [XingData]) {
        func inside(_ p: SIMD2<Float>, _ m: Float = 0) -> Bool { abs(p.x) <= half.x + m && abs(p.y) <= half.y + m }
        // Which ways carry passenger trains, and whether they go far.
        var routeOf: [Int64: (intercity: Bool, name: String)] = [:]
        for r in osm.relations where r.tags["route"] == "train" {
            let intercity = ["long_distance", "high_speed", "national", "international"].contains(r.tags["service"] ?? "")
            var name = r.tags["name"] ?? r.tags["ref"] ?? "Passenger"
            if let cut = name.firstIndex(where: { $0 == ":" || $0 == "(" }) { name = String(name[..<cut]).trimmingCharacters(in: .whitespaces) }
            for m in r.members where m.type == "way" {
                if let have = routeOf[m.ref], have.intercity && !intercity { continue }
                routeOf[m.ref] = (intercity, name)
            }
        }
        var byName: [String: [(nds: [Int64], id: Int64, tags: [String: String])]] = [:]
        // Main lines in the open: not tunnels, nor yard tracks, sidings and spurs.
        for w in osm.ways where w.tags["railway"] == "rail" && w.tags["tunnel"] == nil && !(w.tags["layer"] ?? "0").hasPrefix("-")
                && w.tags["service"] == nil {
            let nds = w.nds.filter { osm.nodes[$0] != nil }
            if nds.count >= 2 { byName[w.tags["name"] ?? "", default: []].append((nds, w.id, w.tags)) }
        }
        var rails: [RailData] = []
        var chains: [[Int64]] = []
        for (name, parts) in byName.sorted(by: { $0.key < $1.key }) {
            var pending = parts.map(\.nds)
            // The kind of train: from the routes using any of these ways, else whoever operates the line.
            var kind = 0, train = "\(name.isEmpty ? "Freight" : name) Freight"
            let routes = parts.compactMap { routeOf[$0.id] }
            if let r = routes.first(where: \.intercity) ?? routes.first { kind = r.intercity ? 1 : 2; train = r.name }
            while !pending.isEmpty {
                var chain = pending.removeFirst()
                var grown = true
                while grown {
                    grown = false
                    for (i, q) in pending.enumerated() {
                        if q.first == chain.last { chain += q.dropFirst() }
                        else if q.last == chain.last { chain += q.reversed().dropFirst() }
                        else if q.last == chain.first { chain = Array(q.dropLast()) + chain }
                        else if q.first == chain.first { chain = Array(q.reversed().dropLast()) + chain }
                        else { continue }
                        pending.remove(at: i)
                        grown = true
                        break
                    }
                }
                chain = chain.filter { osm.nodes[$0].map { inside($0, 320) } ?? false }
                guard chain.count >= 2 else { continue }
                let pts = chain.map { osm.nodes[$0]! }
                var length: Float = 0
                for k in 1..<pts.count { length += simd_distance(pts[k], pts[k - 1]) }
                guard length >= 200 else { continue }
                rails.append(RailData(n: name, m: kind, p: TileProcessor.flat(pts), tn: train))
                chains.append(chain)
            }
        }
        // Level crossings: where a line meets a street inside the downtown.
        var xings: [XingData] = []
        for (ri, chain) in chains.enumerated() {
            var s: Float = 0
            for (k, id) in chain.enumerated() {
                let p = osm.nodes[id]!
                if k > 0 { s += simd_distance(p, osm.nodes[chain[k - 1]]!) }
                guard osm.nodeTags[id]?["railway"] == "level_crossing", inside(p) else { continue }
                var best: (d: Float, e: Int, dir: SIMD2<Float>)?
                for (ei, e) in edges.enumerated() where e.type != "service" {
                    for j in 0..<(e.pts.count - 1) {
                        let d = distanceToSegment(p, e.pts[j], e.pts[j + 1])
                        if best == nil || d < best!.d { best = (d, ei, e.pts[j + 1] - e.pts[j]) }
                    }
                }
                guard let b = best, b.d <= 6 else { continue }
                let next = osm.nodes[chain[min(k + 1, chain.count - 1)]]!, prev = osm.nodes[chain[max(k - 1, 0)]]!
                let d = simd_length(next - prev) > 0 ? simd_normalize(next - prev) : SIMD2<Float>(0, 1)
                let rd = simd_length(b.dir) > 0 ? simd_normalize(b.dir) : SIMD2<Float>(1, 0)
                func r3(_ v: Float) -> Float { (v * 1000).rounded() / 1000 }
                xings.append(XingData(x: r2(p.x), y: r2(p.y), r: ri, s: r2(s), e: b.e, dx: r3(d.x), dy: r3(d.y), rx: r3(rd.x), ry: r3(rd.y)))
            }
        }
        return (rails, xings)
    }
}
