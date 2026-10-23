import SwiftUI
import RealityKit

/// The city's looks, a 150 m square at a time, for LampScene's streaming. The city's data (road graph,
/// collisions, shops, parked cars) is loaded once and kept by the game; this only shares it out among squares
/// and draws one square when the scene asks, in two steps: `plan` works out its geometry off the main thread from
/// a copy of its data, `make` turns that into entities. Being named functions, a live change to how buildings,
/// roads or signs are drawn reaches the open game: the scene rebuilds its squares with the new code.
@MainActor
enum CityTiles {
    /// What `plan` reads off the main thread: each square's share of the data and a copy of the city's streets,
    /// handed over under a lock whenever they change.
    final class Store: @unchecked Sendable {
        private let lock = NSLock()
        private var parts: [SIMD2<Int32>: CityPart] = [:]
        private var snapshot: CitySnapshot?
        func set(_ parts: [SIMD2<Int32>: CityPart], _ snapshot: CitySnapshot?) {
            lock.lock(); defer { lock.unlock() }
            for (k, p) in parts { self.parts[k] = p }
            if let snapshot { self.snapshot = snapshot }
        }
        func clear() { lock.lock(); parts = [:]; snapshot = nil; lock.unlock() }
        func read(_ k: SIMD2<Int32>) -> (CityPart, CitySnapshot)? {
            lock.lock(); defer { lock.unlock() }
            guard let p = parts[k], let s = snapshot else { return nil }
            return (p, s)
        }
    }
    nonisolated static let store = Store()

    /// A fresh copy of what drawing needs from the city, for `plan`.
    private static func snapshot(_ city: City) -> CitySnapshot {
        CitySnapshot(edges: city.edges, nodes: city.nodes, roadGrid: city.roadGrid, fallen: city.fallen)
    }

    static let size: Float = 150
    static let radius: Float = 480

    struct Bucket {
        var part = CityPart()
        var shops: [Int] = []          // indices into Businesses.all
    }

    static var city: City?
    /// Each drawn square's small things, shown only near the car.
    private static var details: [SIMD2<Int32>: Entity] = [:]
    /// Where the car is, for which squares show their small things.
    static var viewer: SIMD2<Float> = .zero
    /// How far from the car a square's signs, storefronts, furniture and trees are drawn.
    static let detailReach: Float = 260

    private static func detailNear(_ k: SIMD2<Int32>) -> Bool {
        let c = SIMD2((Float(k.x) + 0.5) * size, -(Float(k.y) + 0.5) * size)
        return simd_distance(c, viewer) < detailReach + size * 0.7
    }

    /// Shows the small things on squares near `p` and hides them farther out.
    static func showDetail(around p: SIMD2<Float>) {
        viewer = p
        for (k, e) in details {
            guard e.parent != nil else { details[k] = nil; continue }
            let on = detailNear(k)
            if e.isEnabled != on { e.isEnabled = on }
        }
    }
    /// Squares made since the city was loaded: the loading screen waits for the first few.
    static var made = 0
    static var traffic: Traffic?
    static var shops: Businesses?
    private static var buckets: [SIMD2<Int32>: Bucket] = [:]
    /// Each drawn square's trees, so a knocked-down one can be swapped for a stump without redrawing the square.
    private static var treeHolders: [SIMD2<Int32>: Entity] = [:]
    private static var hydrantHolders: [SIMD2<Int32>: Entity] = [:]
    /// Street signs and signal poles standing in drawn squares, by spot.
    private static var pieces: [SIMD2<Int32>: Entity] = [:]

    /// Forgets everything shared out: a city loaded afresh starts with empty squares (and storefronts).
    static func reset() {
        made = 0
        details = [:]
        buckets = [:]
        store.clear()
        CityBuilder.forgetAtlases()
        CityBuilder.forgetMaterials()
        treeHolders = [:]
        hydrantHolders = [:]
        pieces = [:]
        ShopPieces.pieces = [:]
    }

    /// The square holding a point on the map (x east, y north).
    static func key(_ p: SIMD2<Float>) -> SIMD2<Int32> {
        SIMD2(Int32(floor(p.x / size)), Int32(floor(-p.y / size)))
    }

    static func key(_ tile: LampTile) -> SIMD2<Int32> { SIMD2(Int32(tile.x), Int32(tile.z)) }

    static func tile(_ k: SIMD2<Int32>) -> LampTile { LampTile(x: Int(k.x), z: Int(k.y), size: size) }

    /// Shares out a newly loaded piece of the city among squares; returns the squares it touched.
    @discardableResult
    static func add(_ part: CityPart, shops shopIndices: [Int], of owner: City? = nil) -> Set<SIMD2<Int32>> {
        // Only for the city being drawn: a piece loaded for a city the game has since left (travel, or a build
        // started again) refers to that city's streets.
        guard let city, owner == nil || owner === city else { return [] }
        var touched = Set<SIMD2<Int32>>()
        func put(_ p: SIMD2<Float>, _ change: (inout Bucket) -> Void) {
            let k = key(p)
            change(&buckets[k, default: Bucket()])
            touched.insert(k)
        }
        for e in part.edges where e < city.edges.count { put(city.edges[e].pts[0]) { $0.part.edges.append(e) } }
        for n in part.nodes where n < city.nodes.count { put(city.nodes[n].pos) { $0.part.nodes.append(n) } }
        for b in part.buildings {
            let poly = points(b.p)
            guard !poly.isEmpty else { continue }
            put(poly.reduce(SIMD2<Float>(0, 0), +) / Float(poly.count)) { $0.part.buildings.append(b) }
        }
        // Areas come cut along the squares' edges: each piece goes to the square holding its first triangle's middle.
        func middle(_ a: AreaData) -> SIMD2<Float>? {
            guard a.t.count >= 3, let m = a.t.prefix(3).max(), 2 * m + 1 < a.p.count else { return a.p.count >= 2 ? SIMD2(a.p[0], a.p[1]) : nil }
            return a.t.prefix(3).reduce(SIMD2<Float>(0, 0)) { $0 + SIMD2(a.p[2 * $1], a.p[2 * $1 + 1]) } / 3
        }
        for g in part.grass { if let m = middle(g) { put(m) { $0.part.grass.append(g) } } }
        for l in part.lots { if let m = middle(l) { put(m) { $0.part.lots.append(l) } } }
        for p in part.paths where p.p.count >= 4 { put(SIMD2(p.p[0] + p.p[2], p.p[1] + p.p[3]) / 2) { $0.part.paths.append(p) } }
        for t in part.trees { put(SIMD2(t[0], t[1])) { $0.part.trees.append(t) } }
        for f in part.furniture where f.count >= 4 { put(SIMD2(f[1], f[2])) { $0.part.furniture.append(f) } }
        for w in part.wires where w.count >= 4 { put(SIMD2(w[0], w[1])) { $0.part.wires.append(w) } }
        for f in part.fuel { put(SIMD2(f.x, f.y)) { $0.part.fuel.append(f) } }
        if let all = shops?.all {
            for i in shopIndices where i < all.count {
                put(all[i].pos) { $0.shops.append(i); $0.part.shops.append(all[i].data) }
            }
        }
        var changed: [SIMD2<Int32>: CityPart] = [:]
        for k in touched { changed[k] = buckets[k]?.part }
        store.set(changed, snapshot(city))
        return touched
    }

    /// A tree knocked down at `c`: its square's trees redrawn with a stump there. Returns the tree's look and size.
    static func fell(_ c: SIMD2<Float>) -> (variant: Int, scale: Float)? {
        guard let city else { return nil }
        let k = key(c)
        guard let trees = buckets[k]?.part.trees,
              let o = trees.firstIndex(where: { $0.count > 2 && abs($0[0] - c.x) < 0.05 && abs($0[1] - c.y) < 0.05 }) else { return nil }
        store.set([:], snapshot(city))
        if let holder = treeHolders[k], holder.parent != nil {
            for child in Array(holder.children) { child.removeFromParent() }
            CityBuilder.fillTrees(holder, trees, fallen: city.fallen)
        }
        return (o % 2, trees[o][2])
    }

    /// The street sign or signal pole standing at `c`, taken out of its square to fall over.
    /// A hydrant knocked off at `c`: its square's hydrants redrawn with a broken pipe there.
    static func knockHydrant(_ c: SIMD2<Float>) {
        guard let city else { return }
        store.set([:], snapshot(city))
        let k = key(c)
        guard let furniture = buckets[k]?.part.furniture, let holder = hydrantHolders[k], holder.parent != nil else { return }
        for child in Array(holder.children) { child.removeFromParent() }
        CityBuilder.fillHydrants(holder, furniture, city: city)
    }

    /// A street lamp knocked over at `c`: taken out of its square, and a copy of it handed back to fall over.
    static func knockLamp(_ c: SIMD2<Float>) -> Entity? {
        knockHydrant(c)
        guard let f = buckets[key(c)]?.part.furniture.first(where: {
            Int($0[0]) == Furniture.Kind.lamp.rawValue && abs($0[1] - c.x) < 0.05 && abs($0[2] - c.y) < 0.05
        }), let city else { return nil }
        let e = Furniture.model(.lamp).clone(recursive: true)
        e.transform = Transform(rotation: simd_quatf(angle: -f[3], axis: [0, 1, 0]), translation: w3(c, city.surface(c)))
        return e
    }

    static func knockOver(_ c: SIMD2<Float>) -> Entity? {
        if let city { store.set([:], snapshot(city)) }
        guard let e = pieces.removeValue(forKey: City.spot(c)), e.parent != nil else { return nil }
        return e
    }

    /// Off the main thread: one square's geometry, from its share of the data and the copy of the city's streets.
    nonisolated static func plan(_ tile: LampTile) -> SquarePlan? {
        guard let (part, city) = store.read(SIMD2(Int32(tile.x), Int32(tile.z))) else { return nil }
        var plan = CityGeometry(city: city).plan(part, square: SIMD2(Int32(tile.x), Int32(tile.z)))
        plan.shops = part.shops.map { ShopPieces.plan($0) }
        return plan
    }

    /// Off the main thread, for the F3 readout: triangles in the squares round `p`, by what they're for, drawn
    /// flat (as before the land had any shape) and following the ground.
    nonisolated static func census(around p: SIMD2<Float>, reach: Int = 2) -> String {
        let k = SIMD2(Int32(floor(p.x / 150)), Int32(floor(-p.y / 150)))
        var flat: [String: Int] = [:], hilly: [String: Int] = [:]
        var squares = 0
        var times: (Double, Double) = (0, 0)
        for dx in -reach...reach {
            for dy in -reach...reach {
                let s = SIMD2(k.x + Int32(dx), k.y + Int32(dy))
                guard let (part, city) = store.read(s) else { continue }
                squares += 1
                for follow in [false, true] {
                    let g = CityGeometry(city: city)
                    g.follow = follow
                    let t0 = CACurrentMediaTime()
                    let plan = g.plan(part, square: s)
                    if follow { times.1 += CACurrentMediaTime() - t0 } else { times.0 += CACurrentMediaTime() - t0 }
                    for b in plan.batches {
                        let group = CityGeometry.censusGroup(b.material)
                        let n = b.mesh.indices.count / 3
                        if follow { hilly[group, default: 0] += n } else { flat[group, default: 0] += n }
                    }
                }
            }
        }
        // How much the ground bends: the second difference of heights along grid rows within 1 km.
        var second: [Float] = []
        let t = Terrain.shared
        var y = p.y - 1000
        while y < p.y + 1000 {
            var x = p.x - 1000
            while x < p.x + 1000 {
                let c = SIMD2(x, y)
                second.append(abs(t.height(c - [10, 0]) - 2 * t.height(c) + t.height(c + [10, 0])))
                second.append(abs(t.height(c - [0, 10]) - 2 * t.height(c) + t.height(c + [0, 10])))
                x += 10
            }
            y += 10
        }
        second.sort()
        if !second.isEmpty {
            func pct(_ q: Double) -> String { String(format: "%.3f", second[min(second.count - 1, Int(Double(second.count) * q))]) }
            print("Ground bend (m, second difference over 10 m): median \(pct(0.5)), 75% \(pct(0.75)), 90% \(pct(0.9)), 99% \(pct(0.99))")
        }
        let groups = ["ground", "areas", "roads", "kerbs", "markings", "other"]
        var lines = ["Triangles in \(squares) squares round the car (flat → following the ground), plan time \(Int(times.0 * 1000)) → \(Int(times.1 * 1000)) ms:"]
        for g in groups {
            let a = flat[g] ?? 0, b = hilly[g] ?? 0
            lines.append("  \(g): \(a) → \(b) (×\(a > 0 ? String(format: "%.1f", Double(b) / Double(a)) : "–"))")
        }
        let ta = flat.values.reduce(0, +), tb = hilly.values.reduce(0, +)
        lines.append("  total: \(ta) → \(tb), \(tb / max(1, squares)) per square")
        return lines.joined(separator: "\n")
    }

    /// On the main thread: the square's entities from its plan, and what touches the game (its trees and signs
    /// for knocking down, its signal lamps for the traffic lights, its shopfronts).
    static func make(_ tile: LampTile, _ plan: SquarePlan) -> Entity? {
        guard let city else { return nil }
        made += 1
        let started = CACurrentMediaTime()
        defer { Perf.shared.lastSquare = (CACurrentMediaTime() - started) * 1000 }
        let root = Entity()
        let builder = CityBuilder(city: city)
        var lamps: [Int: SignalLamps] = [:]
        builder.make(plan, into: root, signals: &lamps)
        if let t = root.findEntity(named: "trees") { treeHolders[key(tile)] = t }
        if let h = root.findEntity(named: "hydrants") { hydrantHolders[key(tile)] = h }
        pieces.merge(builder.pieces) { $1 }
        // Fresh lamps for the crossings drawn here: the signals light them from their next change.
        for (n, l) in lamps { traffic?.signals[n] = l }
        shops?.decorate(root, indices: buckets[key(tile)]?.shops ?? [], plans: plan.shops)
        // Everything but the square's big merged meshes (streets, ground, buildings) and its trees goes in one
        // holder: signs, signal poles, storefronts, furniture. Each is a few small things to draw, hundreds a
        // square, so they're shown only on squares near the car (`showDetail`). Trees are drawn as one batch a
        // square and stay in view.
        let detail = Entity()
        detail.name = "detail"
        for child in Array(root.children) where !child.name.hasPrefix("chunk") && child.name != "trees" {
            detail.addChild(child, preservingWorldTransform: true)
        }
        root.addChild(detail)
        details[key(tile)] = detail
        detail.isEnabled = detailNear(key(tile))
        return root
    }
}
