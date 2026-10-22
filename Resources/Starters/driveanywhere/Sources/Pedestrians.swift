import SwiftUI
import RealityKit

/// Someone on foot: walks the sidewalks along the real streets, jumps out of the way, or goes flying.
struct Walker {
    enum State { case walking, dodging, flying, down }
    var root: Entity
    var figure: Entity
    var legs: [Entity]
    var arms: [Entity]
    var edge = 0
    var forward = true
    var s: Float = 0
    var side: Float = 1
    var speed: Float = 1.3
    var phase: Float = 0
    var pos: SIMD2<Float> = .zero
    var heading: Float = 0
    var state: State = .walking
    var vel: SIMD3<Float> = .zero
    var height: Float = 0
    var tumble: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    var spin: SIMD3<Float> = .zero
    var timer: Float = 0
    var paused: Float = 0        // stopped by a horn, seconds left
    /// The street it'll take at the corner it's waiting at (for the light to change).
    var held: Int?
}

@MainActor
final class Crowd {
    let city: City
    let physics: Physics
    var walkers: [Walker] = []
    /// Where people were hit this frame, for the sound.
    var hits: [SIMD2<Float>] = []
    /// You on a bike, scooter or board: light, but you still knock people over.
    var playerRiding = false
    private var lastCheck: Float = 0

    init(city: City, physics: Physics) { self.city = city; self.physics = physics }

    // MARK: People

    private static var meshes: (torso: MeshResource, head: MeshResource, hair: MeshResource, leg: MeshResource, arm: MeshResource)?

    private static func parts() -> (torso: MeshResource, head: MeshResource, hair: MeshResource, leg: MeshResource, arm: MeshResource) {
        if let m = meshes { return m }
        var torso = MeshKit(), head = MeshKit(), hair = MeshKit(), leg = MeshKit(), arm = MeshKit()
        torso.box([0, 0.3, 0], [0.4, 0.6, 0.22])
        torso.box([0, 0.02, 0], [0.36, 0.12, 0.2])               // hips
        head.blob([0, 0.74, 0], radius: 0.115, scale: [0.9, 1.1, 1], segments: 8, rings: 5)
        head.box([0, 0.63, 0], [0.09, 0.08, 0.09])               // neck
        hair.blob([0, 0.79, 0.015], radius: 0.122, scale: [0.95, 0.75, 1.05], segments: 8, rings: 4)
        leg.box([0, -0.43, 0], [0.15, 0.86, 0.17])
        leg.box([0, -0.86, -0.05], [0.14, 0.08, 0.27])           // shoe
        arm.box([0, -0.29, 0], [0.1, 0.6, 0.11])
        let m = (torso.mesh()!, head.mesh()!, hair.mesh()!, leg.mesh()!, arm.mesh()!)
        meshes = m
        return m
    }

    static let shirts: [NSColor] = [
        NSColor(red: 0, green: 0.15, blue: 0.3, alpha: 1), NSColor(red: 1, green: 0.8, blue: 0.02, alpha: 1), .white,
        NSColor(white: 0.15, alpha: 1), NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1), NSColor(red: 0.3, green: 0.5, blue: 0.3, alpha: 1),
        NSColor(red: 0.5, green: 0.6, blue: 0.75, alpha: 1), NSColor(red: 0.85, green: 0.5, blue: 0.2, alpha: 1), NSColor(white: 0.55, alpha: 1),
        NSColor(red: 0.45, green: 0.2, blue: 0.45, alpha: 1),
    ]
    static let pants: [NSColor] = [
        NSColor(red: 0.15, green: 0.2, blue: 0.35, alpha: 1), NSColor(white: 0.12, alpha: 1), NSColor(red: 0.55, green: 0.48, blue: 0.36, alpha: 1),
        NSColor(white: 0.35, alpha: 1), NSColor(red: 0.25, green: 0.3, blue: 0.45, alpha: 1),
    ]
    static let skins: [NSColor] = [
        NSColor(red: 0.95, green: 0.78, blue: 0.65, alpha: 1), NSColor(red: 0.8, green: 0.6, blue: 0.45, alpha: 1),
        NSColor(red: 0.55, green: 0.38, blue: 0.26, alpha: 1), NSColor(red: 0.36, green: 0.24, blue: 0.16, alpha: 1),
    ]
    static let hairs: [NSColor] = [
        NSColor(white: 0.08, alpha: 1), NSColor(red: 0.3, green: 0.18, blue: 0.1, alpha: 1),
        NSColor(red: 0.75, green: 0.6, blue: 0.35, alpha: 1), NSColor(white: 0.6, alpha: 1),
    ]

    private static var cloth: [NSColor: PhysicallyBasedMaterial] = [:]
    private static func cloth(_ c: NSColor) -> PhysicallyBasedMaterial {
        if let m = cloth[c] { return m }
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: 0.85)
        cloth[c] = m
        return m
    }

    /// A person facing -z with their feet at the origin.
    /// What someone wears and looks like, so the same person can be made again (you, getting on a bike).
    struct Look {
        var shirt = Crowd.shirts.randomElement()!, trousers = Crowd.pants.randomElement()!
        var skin = Crowd.skins.randomElement()!, hair = Crowd.hairs.randomElement()!
    }

    static func makePerson(_ look: Look = Look()) -> (Entity, Entity, [Entity], [Entity]) {
        let p = parts()
        let shirt = cloth(look.shirt), trousers = cloth(look.trousers)
        let skin = cloth(look.skin), hair = cloth(look.hair)
        let root = Entity()
        let figure = Entity()
        figure.position = [0, 0.9, 0]
        root.addChild(figure)
        figure.addChild(ModelEntity(mesh: p.torso, materials: [shirt]))
        figure.addChild(ModelEntity(mesh: p.head, materials: [skin]))
        figure.addChild(ModelEntity(mesh: p.hair, materials: [hair]))
        var legs: [Entity] = [], arms: [Entity] = []
        for x: Float in [-0.1, 0.1] {
            let leg = ModelEntity(mesh: p.leg, materials: [trousers])
            leg.position = [x, 0, 0]
            figure.addChild(leg)
            legs.append(leg)
            let arm = ModelEntity(mesh: p.arm, materials: [shirt])
            arm.position = [x * 2.6, 0.56, 0]
            figure.addChild(arm)
            arms.append(arm)
        }
        return (root, figure, legs, arms)
    }

    // MARK: Spawning

    func spawn(count: Int, around p: SIMD2<Float>, into parent: Entity) {
        for _ in 0..<count {
            let (root, figure, legs, arms) = Self.makePerson()
            root.name = "person"
            parent.addChild(root)
            walkers.append(Walker(root: root, figure: figure, legs: legs, arms: arms,
                                  speed: Float.random(in: 1.1...1.6), phase: Float.random(in: 0...6)))
            place(walkers.count - 1, around: p, from: 0, to: 220)
        }
    }

    /// A horn: people just ahead of it jump aside.
    func scare(from p: SIMD2<Float>, toward f: SIMD2<Float>) {
        // Everyone near stops and turns to look.
        for i in walkers.indices where walkers[i].state == .walking && simd_distance(walkers[i].pos, p) < 28 {
            walkers[i].paused = 2.5
            let d = p - walkers[i].pos
            walkers[i].heading = atan2(d.x, d.y)
        }
        for i in walkers.indices where walkers[i].state == .walking {
            let rel = walkers[i].pos - p
            let ahead = simd_dot(rel, f), side = simd_dot(rel, perpRight(f))
            guard ahead > 0, ahead < 16, abs(side) < 3.5 else { continue }
            let away = perpRight(f) * (side >= 0 ? 1 : -1)
            walkers[i].state = .dodging
            walkers[i].vel = SIMD3(away.x, 0, away.y) * 4.5
            walkers[i].timer = 0.5
        }
    }

    /// Someone pulled out of a car you've taken: they appear beside it and hurry off along the nearest street.
    func addDriver(at p: SIMD2<Float>, heading: Float, into parent: Entity) {
        let (root, figure, legs, arms) = Self.makePerson()
        parent.addChild(root)
        var w = Walker(root: root, figure: figure, legs: legs, arms: arms, speed: 3.2, phase: 0)
        w.pos = p
        w.heading = heading + .pi / 2
        // A stumble out of the door, then off.
        w.state = .dodging
        w.vel = SIMD3(-cos(heading), 0, sin(heading)) * 2.5
        w.timer = 0.6
        walkers.append(w)
        standUp(walkers.count - 1)
        walkers[walkers.count - 1].pos = p
        walkers[walkers.count - 1].state = .dodging
        walkers[walkers.count - 1].timer = 0.6
        show(walkers.count - 1)
    }

    private func place(_ i: Int, around p: SIMD2<Float>, from: Float, to: Float) {
        for _ in 0..<160 {
            let ei = Int.random(in: 0..<city.edges.count)
            let e = city.edges[ei]
            if e.isService || e.length < 15 { continue }
            var side: Float = Bool.random() ? 1 : -1
            if !(side > 0 ? e.sidewalks.1 : e.sidewalks.0) { side = -side }
            guard side > 0 ? e.sidewalks.1 : e.sidewalks.0 else { continue }
            let s = Float.random(in: 2...(e.length - 2))
            let (q, dir) = e.sample(s)
            // People where the shops are: a street lined with them is many times busier than a quiet one.
            let weight = 1 + 2 * Float(min(6, city.shopsNear(q)))
            if Float.random(in: 0..<13) > weight { continue }
            let pt = q + perpRight(dir) * side * e.walkOffset
            let d = simd_distance(pt, p)
            if d < from || d > to { continue }
            var w = walkers[i]
            w.edge = ei; w.forward = Bool.random(); w.s = w.forward ? s : e.length - s; w.side = side
            w.pos = pt; w.state = .walking; w.height = 0; w.timer = 0
            w.tumble = simd_quatf(angle: 0, axis: [0, 1, 0])
            w.heading = atan2(dir.x, dir.y) + (w.forward ? 0 : .pi)
            walkers[i] = w
            show(i)
            return
        }
    }

    /// How far from a crossing's middle people walk to: the corner, outside the road.
    private func cornerTrim(_ n: Int) -> Float {
        city.nodes[n].edges.count >= 3 ? city.nodes[n].radius + 1.2 : 0
    }

    private func target(_ w: Walker) -> (SIMD2<Float>, SIMD2<Float>) {
        let e = city.edges[w.edge]
        // Along the street between its corners, so crossings are made at the corners.
        let t0 = cornerTrim(w.forward ? e.a : e.b), t1 = cornerTrim(w.forward ? e.b : e.a)
        let span = e.length - t0 - t1
        let along = span > 1 ? t0 + w.s / e.length * span : w.s
        let (q, dir) = e.sample(w.forward ? along : e.length - along)
        return (q + perpRight(dir) * w.side * e.walkOffset, w.forward ? dir : -dir)
    }

    /// The street to take at the corner ahead.
    private func choose(_ w: Walker) -> Int? {
        let e = city.edges[w.edge]
        let node = w.forward ? e.b : e.a
        return city.nodes[node].edges.filter { $0 != w.edge && !city.edges[$0].isService && city.edges[$0].a != city.edges[$0].b }.randomElement()
    }

    /// Whether going on into street `n` means crossing a road while its light is against walking.
    private func mustWait(_ w: Walker, into n: Int, time: Float) -> Bool {
        let e = city.edges[w.edge]
        let node = w.forward ? e.b : e.a
        guard city.nodes[node].signal else { return false }
        let inDir = -e.outward(from: node), outDir = city.edges[n].outward(from: node)
        let walkingSide = w.side * (w.forward ? 1 : -1)          // +1: on the right of the way it's walking
        let turn = cross2(inDir, outDir)                          // > 0: turning left
        let straight = simd_dot(inDir, outDir) > 0.5
        let axis = Traffic.signalAxis(city, node)
        func green(_ along: SIMD2<Float>) -> Bool {
            Traffic.light(node, group: abs(simd_dot(along, axis)) > 0.707 ? 0 : 1, time: time) == 0
        }
        if straight { return !green(inDir) }                     // across the side street: with the traffic beside it
        let aroundCorner = (turn < 0 && walkingSide > 0) || (turn > 0 && walkingSide < 0)
        return aroundCorner ? false : !green(outDir)             // across its own street: with the cross traffic
    }

    private func next(_ w: inout Walker, into chosen: Int? = nil) {
        let e = city.edges[w.edge]
        let node = w.forward ? e.b : e.a
        guard let n = chosen ?? choose(w) else { w.forward.toggle(); w.side = -w.side; return }
        // Keep to the same side of the street as seen walking.
        let walkingSide = w.side * (w.forward ? 1 : -1)
        w.forward = city.edges[n].a == node
        w.edge = n
        w.side = walkingSide * (w.forward ? 1 : -1)
    }

    // MARK: Every frame

    func update(_ dt: Float, time: Float, player: Int) {
        let car = physics.bodies[player]
        for i in walkers.indices {
            switch walkers[i].state {
            case .walking, .dodging: walk(i, dt, car: car, time: time)
            case .flying: fly(i, dt)
            case .down:
                walkers[i].timer -= dt
                if walkers[i].timer <= 0 { standUp(i) }
            }
            show(i)
        }
        if time - lastCheck > 1 {
            lastCheck = time
            for i in walkers.indices where simd_distance(walkers[i].pos, car.pos) > 260 {
                place(i, around: car.pos, from: 90, to: 230)
            }
        }
    }

    private func walk(_ i: Int, _ dt: Float, car: Body, time: Float) {
        var w = walkers[i]
        let e = city.edges[w.edge]
        if w.paused > 0 { w.paused -= dt } else { w.s += w.speed * dt }
        if w.s >= e.length {
            // At the corner: cross with the light where there is one.
            let n = w.held ?? choose(w)
            if let n, mustWait(w, into: n, time: time) {
                w.held = n
                w.s = e.length
            } else {
                w.held = nil
                w.s -= e.length
                next(&w, into: n)
            }
        }
        let (goal, _) = target(w)
        let old = w.pos
        if w.state == .dodging {
            w.pos += SIMD2(w.vel.x, w.vel.z) * dt
            w.timer -= dt
            if w.timer <= 0 { w.state = .walking }
        } else {
            w.pos += (goal - w.pos) * min(1, dt * 2.5)
        }
        let moved = (w.pos - old) / max(dt, 1e-4)
        if simd_length(moved) > 0.3 { w.heading = turn(w.heading, toward: atan2(moved.x, moved.y), dt * 8) }
        w.phase += simd_length(moved) * dt * 5.5
        walkers[i] = w

        // Hit by something moving fast: checked where the car is and half a frame back, so speed can't skip it.
        var hitBy: Body?
        physics.query(w.pos, 4) { j in
            let b = self.physics.bodies[j]
            guard b.dynamic, b.mass > 300 || (self.playerRiding && b.kind == .player), simd_length(b.vel) > 2.5 else { return }
            let back = b.vel * dt * 0.5
            let reach = b.halfWidth + 0.45
            if b.circles().contains(where: { simd_distance($0, w.pos) < reach || simd_distance($0 - back, w.pos) < reach }) { hitBy = b }
        }
        if let b = hitBy { launch(i, by: b); return }

        // About one in three see the car coming at the last moment and jump; not always far enough.
        if w.state == .walking && i % 3 == 0 {
            let rel = w.pos - car.pos
            let speed = simd_length(car.vel)
            if speed > 6 {
                let along = simd_normalize(car.vel)
                let ahead = simd_dot(rel, along)
                let lateral = simd_dot(rel, perpRight(along))
                if ahead > 2, ahead / speed < 0.6, abs(lateral) < 1.8, Float.random(in: 0...1) < dt * 4 {
                    let away = perpRight(along) * (lateral >= 0 ? 1 : -1)
                    walkers[i].state = .dodging
                    walkers[i].vel = SIMD3(away.x, 0, away.y) * 4
                    walkers[i].timer = 0.4
                }
            }
        }
    }

    private func launch(_ i: Int, by b: Body) {
        hits.append(b.pos)
        var w = walkers[i]
        let speed = simd_length(b.vel)
        let push = b.vel * 1.05 + simd_normalize(w.pos - b.pos + SIMD2(0.01, 0)) * 2
        w.state = .flying
        w.vel = SIMD3(push.x, min(9, 2 + speed * 0.35), push.y)
        w.spin = SIMD3(Float.random(in: -9...9), Float.random(in: -6...6), Float.random(in: -9...9))
        walkers[i] = w
        // The car feels it: slowed and jolted where it hit them, more for a lighter car.
        if let j = physics.bodies.firstIndex(where: { $0.entity === b.entity }) {
            physics.pushBack(j, at: w.pos, loss: min(speed * 0.3, 3) * min(1.5, 1500 / b.mass))
        }
    }

    private func fly(_ i: Int, _ dt: Float) {
        var w = walkers[i]
        w.vel.y -= 9.8 * dt
        var step = SIMD2(w.vel.x, w.vel.z) * dt
        // Off walls.
        let next = w.pos + step
        city.walls.query(next, 1) { wall in
            let q = closestOnSegment(next, wall.a, wall.b)
            let d = simd_distance(next, q)
            if d < 0.3 && d > 1e-5 {
                let n = (next - q) / d
                let v = SIMD2(w.vel.x, w.vel.z)
                let r = v - 1.5 * simd_dot(v, n) * n
                w.vel.x = r.x * 0.5; w.vel.z = r.y * 0.5
                step = .zero
            }
        }
        w.pos += step
        w.height += w.vel.y * dt
        let ang = simd_length(w.spin)
        if ang > 0 { w.tumble = simd_quatf(angle: ang * dt, axis: w.spin / ang) * w.tumble }
        if w.height <= 0 && w.vel.y < 0 {
            w.height = 0
            let horiz = simd_length(SIMD2(w.vel.x, w.vel.z))
            if horiz > 3 || w.vel.y < -4 {
                w.vel = SIMD3(w.vel.x * 0.45, -w.vel.y * 0.3, w.vel.z * 0.45)
                w.spin *= 0.5
            } else {
                w.state = .down
                w.timer = Float.random(in: 4...7)
                w.tumble = simd_quatf(angle: -.pi / 2, axis: [1, 0, 0])
            }
        }
        walkers[i] = w
    }

    private func standUp(_ i: Int) {
        var w = walkers[i]
        w.state = .walking
        w.tumble = simd_quatf(angle: 0, axis: [0, 1, 0])
        w.height = 0
        // Pick up again on the nearest sidewalk.
        if let road = city.nearestRoad(w.pos, within: 40) {
            let e = city.edges[road.edge]
            var best: Float = 0, bd = Float.infinity
            for s in stride(from: Float(0), through: e.length, by: 2) {
                let d = simd_distance(e.sample(s).0, w.pos)
                if d < bd { bd = d; best = s }
            }
            w.edge = road.edge
            w.forward = Bool.random()
            w.s = w.forward ? best : e.length - best
        }
        walkers[i] = w
    }

    private func show(_ i: Int) {
        let w = walkers[i]
        w.root.transform = Transform(rotation: simd_quatf(angle: -w.heading, axis: [0, 1, 0]),
                                     translation: w3(w.pos, Heights.sidewalk))
        switch w.state {
        case .walking, .dodging:
            let swing = sin(w.phase) * (w.state == .dodging ? 0.9 : 0.5)
            w.legs[0].orientation = simd_quatf(angle: swing, axis: [1, 0, 0])
            w.legs[1].orientation = simd_quatf(angle: -swing, axis: [1, 0, 0])
            w.arms[0].orientation = simd_quatf(angle: -swing * 0.8, axis: [1, 0, 0])
            w.arms[1].orientation = simd_quatf(angle: swing * 0.8, axis: [1, 0, 0])
            w.figure.position = [0, 0.9 + abs(cos(w.phase)) * 0.03, 0]
            w.figure.orientation = simd_quatf(angle: 0, axis: [0, 1, 0])
        case .flying:
            w.figure.position = [0, 0.9 + w.height, 0]
            w.figure.orientation = w.tumble
            w.legs[0].orientation = simd_quatf(angle: 0.6, axis: [1, 0, 0])
            w.arms[0].orientation = simd_quatf(angle: -2.4, axis: [1, 0, 0])
            w.arms[1].orientation = simd_quatf(angle: 2.0, axis: [0, 0, 1])
        case .down:
            w.figure.position = [0, 0.13, 0]
            w.figure.orientation = w.tumble
            w.arms[0].orientation = simd_quatf(angle: -0.5, axis: [0, 0, 1])
            w.arms[1].orientation = simd_quatf(angle: 0.6, axis: [0, 0, 1])
            w.legs[0].orientation = simd_quatf(angle: 0.2, axis: [0, 0, 1])
            w.legs[1].orientation = simd_quatf(angle: -0.1, axis: [0, 0, 1])
        }
    }

    private func turn(_ a: Float, toward b: Float, _ k: Float) -> Float {
        var d = b - a
        while d > .pi { d -= 2 * .pi }
        while d < -.pi { d += 2 * .pi }
        return a + d * min(1, k)
    }
}
