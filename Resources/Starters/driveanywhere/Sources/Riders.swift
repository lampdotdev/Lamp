import SwiftUI
import RealityKit

/// Someone on a bike (at the curb, in the road), or on an e-scooter, hoverboard, unicycle, skateboard, one-wheel board or
/// rollerblades (on the sidewalk), following the real streets.
/// Hit, rider and machine go flying together, lie there a while, then carry on.
struct Rider {
    enum State { case riding, flying, down }
    var root: Entity
    var tumbler: Entity
    var figure: Entity
    var legs: [Entity]
    var arms: [Entity]
    var kind: RideKind
    var bike: Bool { kind == .bike }
    var edge = 0
    var forward = true
    var s: Float = 0
    var speed: Float
    var phase: Float = 0
    var pos: SIMD2<Float> = .zero
    var heading: Float = 0
    var state: State = .riding
    var vel: SIMD3<Float> = .zero
    var height: Float = 0
    var tumble = simd_quatf(angle: 0, axis: [0, 1, 0])
    var spin: SIMD3<Float> = .zero
    var timer: Float = 0
    var paused: Float = 0        // stopped by a horn, seconds left
}

@MainActor
final class Riders {
    let city: City
    let physics: Physics
    var riders: [Rider] = []
    /// Where people were hit this frame, for the sound.
    var hits: [SIMD2<Float>] = []
    /// You on a bike, scooter or board: light, but you still knock people over.
    var playerRiding = false
    private var lastCheck: Float = 0

    init(city: City, physics: Physics) { self.city = city; self.physics = physics }

    // MARK: Machines

    private static func mat(_ c: NSColor, rough: Float = 0.5, metal: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    static let bikeColors: [NSColor] = [
        NSColor(red: 0.7, green: 0.1, blue: 0.1, alpha: 1), NSColor(red: 0.1, green: 0.3, blue: 0.6, alpha: 1),
        NSColor(white: 0.85, alpha: 1), NSColor(red: 0.2, green: 0.5, blue: 0.3, alpha: 1), NSColor(white: 0.15, alpha: 1),
        NSColor(red: 1, green: 0.8, blue: 0.02, alpha: 1),
    ]

    /// A bicycle facing -z on the ground: two thin wheels, a diamond frame, saddle and bars.
    static func makeBike(_ color: NSColor) -> Entity {
        var frame = MeshKit(), tyres = MeshKit(), dark = MeshKit()
        for z: Float in [-0.52, 0.52] {
            tyres.wheel([0, 0.34, z], radius: 0.34, width: 0.04, segments: 16)
        }
        func tube(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ t: Float = 0.04) {
            let d = b - a
            let len = simd_length(d)
            let rot = simd_quatf(from: [0, 1, 0], to: d / len)
            frame.box((a + b) / 2, [t, len, t], rot: rot)
        }
        let bb = SIMD3<Float>(0, 0.32, 0.02), seat = SIMD3<Float>(0, 0.88, 0.12), head = SIMD3<Float>(0, 0.9, -0.38)
        tube(bb, seat)
        tube(bb, head)
        tube(seat, head)
        tube(bb, [0, 0.34, 0.52])
        tube(seat, [0, 0.34, 0.52])
        tube(head, [0, 0.34, -0.52])
        tube(head, head + [0, 0.12, 0.02])
        dark.box(seat + [0, 0.04, 0.02], [0.13, 0.05, 0.24])                 // saddle
        dark.box(head + [0, 0.13, 0], [0.5, 0.03, 0.03])                       // bars
        dark.box(bb, [0.05, 0.12, 0.12])                                       // cranks
        // Hubs, so the wheels read as wheels.
        for z: Float in [-0.52, 0.52] { dark.box([0, 0.34, z], [0.06, 0.08, 0.08]) }
        let root = Entity()
        if let m = frame.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat(color, rough: 0.35, metal: 0.4)])) }
        if let m = tyres.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat(NSColor(white: 0.06, alpha: 1), rough: 0.9)])) }
        if let m = dark.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat(NSColor(white: 0.1, alpha: 1), rough: 0.6)])) }
        return root
    }

    /// A rental e-scooter: low deck, small wheels, tall stem with bars.
    static func makeScooter() -> Entity {
        var body = MeshKit(), dark = MeshKit()
        body.box([0, 0.11, 0.02], [0.17, 0.05, 0.74])
        body.box([0, 0.6, -0.37], [0.05, 0.98, 0.05], rot: simd_quatf(angle: -0.12, axis: [1, 0, 0]))
        body.box([0, 0.14, 0.42], [0.1, 0.04, 0.16])                          // rear mudguard
        dark.box([0, 1.08, -0.43], [0.48, 0.035, 0.035])
        dark.wheel([0, 0.1, -0.4], radius: 0.1, width: 0.05, segments: 12)
        dark.wheel([0, 0.1, 0.38], radius: 0.1, width: 0.05, segments: 12)
        dark.box([0, 0.14, 0.02], [0.15, 0.012, 0.6])                         // grip tape
        let root = Entity()
        let green = NSColor(red: 0.35, green: 0.85, blue: 0.2, alpha: 1)
        if let m = body.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat(Bool.random() ? green : NSColor(white: 0.12, alpha: 1), rough: 0.4)])) }
        if let m = dark.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat(NSColor(white: 0.07, alpha: 1), rough: 0.8)])) }
        return root
    }

    static func pose(_ figure: Entity, _ legs: [Entity], _ arms: [Entity], kind: RideKind, phase: Float) {
        switch kind {
        case .bike:
            // Sitting on the saddle, leaning to the bars, pedalling.
            figure.position = [0, 0.98, 0.1]
            figure.orientation = simd_quatf(angle: -0.35, axis: [1, 0, 0])
            legs[0].orientation = simd_quatf(angle: 0.25 + sin(phase) * 0.4, axis: [1, 0, 0])
            legs[1].orientation = simd_quatf(angle: 0.25 - sin(phase) * 0.4, axis: [1, 0, 0])
            for a in arms { a.orientation = simd_quatf(angle: 0.95, axis: [1, 0, 0]) }
        case .scooter:
            // Standing on the deck, one foot behind the other, hands on the bars.
            figure.position = [0, 1.02, 0.05]
            figure.orientation = simd_quatf(angle: -0.05, axis: [1, 0, 0])
            legs[0].orientation = simd_quatf(angle: 0.12, axis: [1, 0, 0])
            legs[1].orientation = simd_quatf(angle: -0.18, axis: [1, 0, 0])
            for a in arms { a.orientation = simd_quatf(angle: 0.8, axis: [1, 0, 0]) }
        default:
            RideModels.pose(figure, legs, arms, kind: kind, phase: phase)
        }
    }

    static func makeRider(_ kind: RideKind, look: Crowd.Look = Crowd.Look()) -> (Entity, Entity, Entity, [Entity], [Entity]) {
        let root = Entity()
        let tumbler = Entity()
        root.addChild(tumbler)
        let (person, figure, legs, arms) = Crowd.makePerson(look)
        switch kind {
        case .bike: tumbler.addChild(makeBike(bikeColors.randomElement()!))
        case .scooter: tumbler.addChild(makeScooter())
        default: tumbler.addChild(RideModels.make(kind, legs: legs))
        }
        tumbler.addChild(person)
        pose(figure, legs, arms, kind: kind, phase: 0)
        return (root, tumbler, figure, legs, arms)
    }

    /// A horn: riders near it pull up for a moment.
    func honk(from p: SIMD2<Float>) {
        for i in riders.indices where riders[i].state == .riding && simd_distance(riders[i].pos, p) < 28 { riders[i].paused = 2.5 }
    }

    /// The nearest rider on the move, for taking their ride.
    func nearest(to p: SIMD2<Float>, within r: Float) -> (index: Int, kind: RideKind, distance: Float)? {
        var best: (Int, RideKind, Float)?
        for (i, rider) in riders.enumerated() where rider.state == .riding {
            let d = simd_distance(rider.pos, p)
            if d < r && (best == nil || d < best!.2) { best = (i, rider.kind, d) }
        }
        return best.map { (index: $0.0, kind: $0.1, distance: $0.2) }
    }

    /// Takes a rider out of the world (their ride is about to be yours).
    func take(_ i: Int) -> (kind: RideKind, pos: SIMD2<Float>, heading: Float)? {
        guard riders.indices.contains(i) else { return nil }
        let r = riders.remove(at: i)
        r.root.removeFromParent()
        return (r.kind, r.pos, r.heading)
    }

    // MARK: Spawning

    func spawn(_ counts: [(RideKind, Int)], around p: SIMD2<Float>, into parent: Entity) {
        for (kind, count) in counts {
            for _ in 0..<count {
                let (root, tumbler, figure, legs, arms) = Self.makeRider(kind)
                parent.addChild(root)
                riders.append(Rider(root: root, tumbler: tumbler, figure: figure, legs: legs, arms: arms, kind: kind,
                                    speed: Float.random(in: kind.speeds), phase: Float.random(in: 0...6)))
                place(riders.count - 1, around: p, from: 10, to: 260)
            }
        }
    }

    private func offset(_ r: Rider, _ e: RoadEdge) -> Float {
        (r.bike ? max(0.6, e.driveWidth / 2 - 0.7) : e.walkOffset) * CityConfig.current.style.side
    }

    private func place(_ i: Int, around p: SIMD2<Float>, from: Float, to: Float) {
        for _ in 0..<100 {
            let ei = Int.random(in: 0..<city.edges.count)
            let e = city.edges[ei]
            if e.isService || e.length < 20 { continue }
            if Float.random(in: 0..<6) > max(1.5, e.trafficWeight) { continue }
            let s = Float.random(in: 3...(e.length - 3))
            let fwd = e.oneway ? true : Bool.random()
            var r = riders[i]
            r.edge = ei; r.forward = fwd; r.s = fwd ? s : e.length - s
            let (pt, dir) = target(r)
            let d = simd_distance(pt, p)
            if d < from || d > to { continue }
            r.pos = pt; r.heading = atan2(dir.x, dir.y)
            r.state = .riding; r.height = 0; r.tumble = simd_quatf(angle: 0, axis: [0, 1, 0])
            riders[i] = r
            show(i)
            return
        }
    }

    private func target(_ r: Rider) -> (SIMD2<Float>, SIMD2<Float>) {
        let e = city.edges[r.edge]
        var (q, dir) = e.sample(r.forward ? r.s : e.length - r.s)
        if !r.forward { dir = -dir }
        return (q + perpRight(dir) * offset(r, e), dir)
    }

    private func next(_ r: inout Rider) {
        let e = city.edges[r.edge]
        let node = r.forward ? e.b : e.a
        let options = city.nodes[node].edges.filter { ci in
            let c = city.edges[ci]
            return ci != r.edge && !c.isService && c.a != c.b && !(c.oneway && c.a != node && r.bike)
        }
        guard let n = options.randomElement() else {
            if !e.oneway || !r.bike { r.forward.toggle() }
            return
        }
        r.forward = city.edges[n].a == node
        r.edge = n
    }

    // MARK: Every frame

    func update(_ dt: Float, time: Float, player: Int) {
        let car = physics.bodies[player]
        for i in riders.indices {
            switch riders[i].state {
            case .riding: ride(i, dt)
            case .flying: fly(i, dt)
            case .down:
                riders[i].timer -= dt
                if riders[i].timer <= 0 { getBackOn(i) }
            }
            show(i)
        }
        if time - lastCheck > 1 {
            lastCheck = time
            for i in riders.indices where simd_distance(riders[i].pos, car.pos) > 300 {
                place(i, around: car.pos, from: 120, to: 280)
            }
        }
    }

    private func ride(_ i: Int, _ dt: Float) {
        var r = riders[i]
        if r.paused > 0 { r.paused -= dt } else { r.s += r.speed * dt }
        while r.s >= city.edges[r.edge].length {
            r.s -= city.edges[r.edge].length
            next(&r)
        }
        let (goal, _) = target(r)
        let old = r.pos
        r.pos += (goal - r.pos) * min(1, dt * 3)
        let moved = (r.pos - old) / max(dt, 1e-4)
        if simd_length(moved) > 0.5 {
            var d = atan2(moved.x, moved.y) - r.heading
            while d > .pi { d -= 2 * .pi }
            while d < -.pi { d += 2 * .pi }
            r.heading += d * min(1, dt * 6)
        }
        r.phase += simd_length(moved) * dt * r.kind.cadence
        riders[i] = r

        var hitBy: Body?
        physics.query(r.pos, 4) { j in
            let b = self.physics.bodies[j]
            guard b.dynamic, b.mass > 300 || (self.playerRiding && b.kind == .player), simd_length(b.vel) > 2.5 else { return }
            let back = b.vel * dt * 0.5
            let reach = b.halfWidth + (r.bike ? 0.6 : 0.45)
            if b.circles().contains(where: { simd_distance($0, r.pos) < reach || simd_distance($0 - back, r.pos) < reach }) { hitBy = b }
        }
        if let b = hitBy { launch(i, by: b) }
    }

    private func launch(_ i: Int, by b: Body) {
        hits.append(b.pos)
        var r = riders[i]
        let speed = simd_length(b.vel)
        let push = b.vel * 1.05 + simd_normalize(r.pos - b.pos + SIMD2(0.01, 0)) * 2 + forwardOf(r.heading) * r.speed * 0.5
        r.state = .flying
        r.vel = SIMD3(push.x, min(9, 2.5 + speed * 0.3), push.y)
        r.spin = SIMD3(Float.random(in: -8...8), Float.random(in: -6...6), Float.random(in: -8...8))
        riders[i] = r
        // Rider and machine together push back a bit harder than someone on foot.
        if let j = physics.bodies.firstIndex(where: { $0.entity === b.entity }) {
            physics.pushBack(j, at: r.pos, loss: min(speed * 0.35, 3.5) * min(1.5, 1500 / b.mass))
        }
    }

    private func fly(_ i: Int, _ dt: Float) {
        var r = riders[i]
        r.vel.y -= 9.8 * dt
        var step = SIMD2(r.vel.x, r.vel.z) * dt
        let next = r.pos + step
        city.walls.query(next, 1) { wall in
            let q = closestOnSegment(next, wall.a, wall.b)
            let d = simd_distance(next, q)
            if d < 0.4 && d > 1e-5 {
                let n = (next - q) / d
                let v = SIMD2(r.vel.x, r.vel.z)
                let o = v - 1.5 * simd_dot(v, n) * n
                r.vel.x = o.x * 0.5; r.vel.z = o.y * 0.5
                step = .zero
            }
        }
        r.pos += step
        r.height += r.vel.y * dt
        let ang = simd_length(r.spin)
        if ang > 0 { r.tumble = simd_quatf(angle: ang * dt, axis: r.spin / ang) * r.tumble }
        if r.height <= 0 && r.vel.y < 0 {
            r.height = 0
            let horiz = simd_length(SIMD2(r.vel.x, r.vel.z))
            if horiz > 3 || r.vel.y < -4 {
                r.vel = SIMD3(r.vel.x * 0.45, -r.vel.y * 0.3, r.vel.z * 0.45)
                r.spin *= 0.5
            } else {
                r.state = .down
                r.timer = Float.random(in: 4...7)
                r.tumble = simd_quatf(angle: .pi / 2 * (Bool.random() ? 1 : -1), axis: [0, 0, 1])
            }
        }
        riders[i] = r
    }

    private func getBackOn(_ i: Int) {
        var r = riders[i]
        r.state = .riding
        r.tumble = simd_quatf(angle: 0, axis: [0, 1, 0])
        r.height = 0
        if let road = city.nearestRoad(r.pos, within: 40) {
            let e = city.edges[road.edge]
            var best: Float = 0, bd = Float.infinity
            for s in stride(from: Float(0), through: e.length, by: 2) {
                let d = simd_distance(e.sample(s).0, r.pos)
                if d < bd { bd = d; best = s }
            }
            r.edge = road.edge
            r.forward = e.oneway ? true : Bool.random()
            r.s = r.forward ? best : e.length - best
        }
        riders[i] = r
    }

    private func show(_ i: Int) {
        let r = riders[i]
        let ground = r.bike ? Heights.road : (city.edges[r.edge].isService ? Heights.road : Heights.sidewalk)
        r.root.transform = Transform(rotation: simd_quatf(angle: -r.heading, axis: [0, 1, 0]), translation: w3(r.pos, ground))
        switch r.state {
        case .riding, .down:
            r.tumbler.position = r.state == .down ? [0, 0.3, 0] : .zero
            r.tumbler.orientation = r.tumble
        case .flying:
            r.tumbler.position = [0, 0.4 + r.height, 0]
            r.tumbler.orientation = r.tumble
        }
        Self.pose(r.figure, r.legs, r.arms, kind: r.kind, phase: r.phase)
    }
}
