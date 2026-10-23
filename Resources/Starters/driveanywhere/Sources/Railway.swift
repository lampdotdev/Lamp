import SwiftUI
import RealityKit

/// The city's railways from the map (railway=rail): long-distance lines get an intercity train, other passenger
/// lines a regional train, the rest freight. Tracks, level crossings with flashing lights and gates, and trains that run
/// end to end, stop traffic at the crossings and knock over anything in their way.
@MainActor
final class Railway {
    struct Line {
        let name: String
        /// 0 freight, 1 intercity, 2 regional passenger train.
        let kind: Int
        /// What the train is called (its route's name, or "<line> Freight").
        let trainName: String
        /// Fast: any passenger train.
        var fast: Bool { kind != 0 }
        let pts: [SIMD2<Float>]
        let cum: [Float]
        var length: Float { cum.last ?? 0 }

        func sample(_ s: Float) -> (SIMD2<Float>, SIMD2<Float>) {
            if s <= 0 || s >= length {
                // Off the end: carry on straight, so trains come in from and leave into the distance.
                let end = s <= 0 ? 0 : pts.count - 1
                let dir = simd_normalize(s <= 0 ? pts[1] - pts[0] : pts[end] - pts[end - 1])
                return (pts[end] + dir * (s <= 0 ? s : s - length), dir)
            }
            var lo = 0, hi = cum.count - 1
            while hi - lo > 1 { let m = (lo + hi) / 2; if cum[m] <= s { lo = m } else { hi = m } }
            let seg = cum[hi] - cum[lo]
            let u = seg > 0 ? (s - cum[lo]) / seg : 0
            let d = pts[hi] - pts[lo]
            return (pts[lo] + d * u, simd_length(d) > 0 ? simd_normalize(d) : SIMD2(0, 1))
        }
    }

    struct Car { let entity: Entity; let body: Int; let length: Float; let offset: Float }

    struct Train {
        var line: Int
        var cars: [Car] = []
        var running = false
        var head: Float = 0
        var dir: Float = 1
        var speed: Float
        var wait: Float
        var driven = false          // you're at the controls
        var total: Float { (cars.last.map { $0.offset + $0.length } ?? 0) }
    }

    struct Crossing {
        let data: XingData
        var gates: [Entity] = []
        var lamps: [[ModelEntity]] = []     // per pole, left and right
        var gate: Float = 1.45              // arm angle: up
        var active = false
    }

    let city: City
    let physics: Physics
    var lines: [Line] = []
    var trains: [Train] = []
    var crossings: [Crossing] = []
    private var flash: Float = 0
    private static let lampOff = Traffic.lampOff
    private static let lampOn = LampMaterial.glow(NSColor(red: 1, green: 0.1, blue: 0.05, alpha: 1), strength: 7)

    init(city: City, physics: Physics) {
        self.city = city
        self.physics = physics
        for r in city.file.rails ?? [] {
            let pts = points(r.p)
            var cum: [Float] = [0]
            for k in 1..<pts.count { cum.append(cum[k - 1] + simd_distance(pts[k], pts[k - 1])) }
            lines.append(Line(name: r.n, kind: r.m, trainName: r.tn ?? (r.m == 0 ? "\(r.n) Freight" : r.n), pts: pts, cum: cum))
        }
    }

    // MARK: Building

    func build(_ root: Entity) {
        var ballast = MeshKit(), ties = MeshKit(), steel = MeshKit(), pads = MeshKit(), white = MeshKit(), dark = MeshKit()
        for line in lines {
            // Ballast bed, then sleepers every 60 cm, then the two rails.
            var s: Float = 0
            while s < line.length {
                let (p, d) = line.sample(s)
                let (q, _) = line.sample(min(line.length, s + 4))
                let r = perpRight(d)
                ballast.quad(w3(p - r * 1.6, 0.07), w3(q - r * 1.6, 0.07), w3(q + r * 1.6, 0.07), w3(p + r * 1.6, 0.07),
                             uv: (p * 0.5, q * 0.5, q * 0.5, p * 0.5), outward: [0, 1, 0])
                for k in 0..<7 {
                    let (tp, td) = line.sample(s + Float(k) * 0.6)
                    if s + Float(k) * 0.6 > line.length { break }
                    ties.box(w3(tp, 0.18), [2.6, 0.12, 0.22], rot: simd_quatf(angle: atan2(td.y, td.x) + .pi / 2, axis: [0, 1, 0]))
                }
                for side: Float in [-0.72, 0.72] {
                    let a = p + r * side, b = q + r * side
                    let mid = (a + b) / 2
                    steel.box(w3(mid, 0.3), [0.08, 0.12, simd_distance(a, b) + 0.02], rot: simd_quatf(angle: atan2(d.x, -d.y), axis: [0, 1, 0]))
                }
                s += 4
            }
        }
        // Level crossings: a rubber pad over the road, crossbucks and lights on poles, gates.
        for x in city.file.xings ?? [] {
            var c = Crossing(data: x)
            let at = SIMD2(x.x, x.y)
            let rd = SIMD2(x.rx, x.ry), td = SIMD2(x.dx, x.dy)
            let e = city.edges[x.e]
            pads.box(w3(at, 0.2), [e.width + 1.5, 0.08, 3.2], rot: simd_quatf(angle: atan2(td.x, -td.y), axis: [0, 1, 0]))
            for side: Float in [-1, 1] {
                // A pole on the right of traffic coming from each side, back from the tracks.
                let heading = rd * side
                let right = perpRight(heading)
                let pole = at - heading * 4.5 + right * (e.width / 2 + 0.9)
                city.addPost(pole, 0.18)
                dark.post(w3(pole, Heights.sidewalk), radius: 0.09, height: 4.2, segments: 8)
                let facing = simd_quatf(angle: atan2(-heading.x, heading.y), axis: [0, 1, 0])   // faces oncoming traffic
                // Crossbuck: two white boards in an X.
                for a: Float in [0.6, -0.6] {
                    white.box(w3(pole, Heights.sidewalk + 3.8) + facing.act([0, 0, 0.12]), [1.3, 0.22, 0.03],
                              rot: facing * simd_quatf(angle: a, axis: [0, 0, 1]))
                }
                // Light bar with two red lamps.
                dark.box(w3(pole, Heights.sidewalk + 2.9) + facing.act([0, 0, 0.1]), [1.1, 0.08, 0.08], rot: facing)
                var pair: [ModelEntity] = []
                for k: Float in [-1, 1] {
                    var hood = MeshKit()
                    hood.blob(.zero, radius: 0.15, scale: [1, 1, 0.4], segments: 10, rings: 4)
                    dark.box(w3(pole, Heights.sidewalk + 2.9) + facing.act([k * 0.45, 0, 0.12]), [0.42, 0.42, 0.06], rot: facing)
                    let lamp = ModelEntity(mesh: hood.mesh()!, materials: [Self.lampOff])
                    lamp.position = w3(pole, Heights.sidewalk + 2.9) + facing.act([k * 0.45, 0, 0.18])
                    lamp.orientation = facing
                    root.addChild(lamp)
                    pair.append(lamp)
                }
                c.lamps.append(pair)
                // Gate arm across the lanes coming this way, hinged at the pole.
                let armDir = -right
                let length = e.width / 2 + 0.4
                var arm = MeshKit()
                var stripes = MeshKit()
                var u: Float = 0.3
                var k = 0
                while u < length {
                    let seg = min(0.6, length - u)
                    if k % 2 == 0 { arm.box([u + seg / 2, 0, 0], [seg, 0.12, 0.08]) } else { stripes.box([u + seg / 2, 0, 0], [seg, 0.12, 0.08]) }
                    u += 0.6; k += 1
                }
                arm.box([-0.4, 0, 0], [0.8, 0.2, 0.2])          // counterweight
                let pivot = Entity()
                pivot.position = w3(pole, Heights.sidewalk + 1.1) + SIMD3(armDir.x, 0, -armDir.y) * 0.15
                let yaw = simd_quatf(angle: atan2(armDir.y, armDir.x), axis: [0, 1, 0])
                pivot.orientation = yaw * simd_quatf(angle: c.gate, axis: [0, 0, 1])
                if let m = arm.mesh() { pivot.addChild(ModelEntity(mesh: m, materials: [LampMaterial.plastic(.white)])) }
                if let m = stripes.mesh() { pivot.addChild(ModelEntity(mesh: m, materials: [LampMaterial.plastic(NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))])) }
                root.addChild(pivot)
                c.gates.append(pivot)
            }
            crossings.append(c)
        }
        let parts: [(MeshKit, RealityKit.Material)] = [
            (ballast, LampMaterial.concrete(NSColor(red: 0.42, green: 0.39, blue: 0.36, alpha: 1), repeat: 1)),
            (ties, LampMaterial.wood(NSColor(red: 0.3, green: 0.22, blue: 0.16, alpha: 1))),
            (steel, LampMaterial.metal(NSColor(white: 0.55, alpha: 1), rough: 0.35)),
            (pads, LampMaterial.rubber(NSColor(white: 0.12, alpha: 1))),
            (white, LampMaterial.plastic(.white)),
            (dark, LampMaterial.metal(NSColor(white: 0.15, alpha: 1), rough: 0.5)),
        ]
        for (kit, m) in parts { if let mesh = kit.mesh() { root.addChild(ModelEntity(mesh: mesh, materials: [m])) } }

        // One train on each of the longest lines (at most six).
        let busiest = Set(lines.indices.sorted { lines[$0].length > lines[$1].length }.prefix(6))
        for (li, line) in lines.enumerated() where busiest.contains(li) {
            var train = Train(line: li, speed: line.fast ? 22 : 9, wait: line.fast ? 25 : 6)
            let consist: [(Entity, Float, Float)] = line.kind == 1 ? RollingStock.intercity() : (line.kind == 2 ? RollingStock.passenger() : RollingStock.freight())
            var offset: Float = 0
            for (entity, length, width) in consist {
                entity.isEnabled = false
                root.addChild(entity)
                let mass: Float = 90000
                physics.bodies.append(Body(pos: SIMD2(9000, 9000), heading: 0, mass: mass, inertia: mass * length * length / 12,
                                           halfLength: length / 2, halfWidth: width / 2, kind: .train, dynamic: true, entity: entity))
                train.cars.append(Car(entity: entity, body: physics.bodies.count - 1, length: length, offset: offset))
                offset += length + 1.2
            }
            trains.append(train)
        }
    }

    // MARK: Running

    func update(_ dt: Float, traffic: Traffic) {
        for i in trains.indices {
            var t = trains[i]
            let line = lines[t.line]
            if !t.running {
                t.wait -= dt
                if t.wait <= 0 {
                    t.running = true
                    t.dir = t.dir > 0 ? -1 : 1
                    t.head = t.dir > 0 ? -60 : line.length + 60
                    for c in t.cars { c.entity.isEnabled = true }
                }
            } else if t.driven {
                // Your hand on the throttle: forwards or back, stopping at the ends of the line.
                t.head += t.dir * t.speed * dt
                let lo: Float = t.dir > 0 ? t.total - 40 : -40, hi: Float = t.dir > 0 ? line.length + 40 : line.length + 40 - t.total
                if t.head < lo || t.head > hi { t.head = max(lo, min(hi, t.head)); t.speed = 0 }
            } else {
                t.head += t.dir * t.speed * dt
                let tail = t.head - t.dir * t.total
                if (t.dir > 0 && tail > line.length + 60) || (t.dir < 0 && tail < -60) {
                    t.running = false
                    t.wait = Float.random(in: line.fast ? 40...80 : 20...45)
                    for c in t.cars {
                        c.entity.isEnabled = false
                        physics.bodies[c.body].pos = SIMD2(9000, 9000)
                        physics.bodies[c.body].vel = .zero
                    }
                }
            }
            if t.running {
                for c in t.cars {
                    // Each car sits between where its front and back are on the track.
                    let mid = t.head - t.dir * (c.offset + c.length / 2)
                    let (f, _) = line.sample(mid + t.dir * c.length * 0.35)
                    let (b, _) = line.sample(mid - t.dir * c.length * 0.35)
                    let d = simd_normalize(f - b)
                    let pos = (f + b) / 2
                    let heading = atan2(d.x, d.y)
                    physics.bodies[c.body].pos = pos
                    physics.bodies[c.body].heading = heading
                    physics.bodies[c.body].vel = d * t.speed
                    physics.bodies[c.body].spin = 0
                    physics.bodies[c.body].asleep = false
                    c.entity.transform = Transform(rotation: simd_quatf(angle: -heading, axis: [0, 1, 0]), translation: w3(pos, 0.36))
                }
            }
            trains[i] = t
        }

        // Crossings: lights and gates come on well before the train, stay down until it's past.
        flash += dt
        var blockers: [SIMD2<Float>] = []
        for i in crossings.indices {
            var c = crossings[i]
            var active = false
            for t in trains where t.running && t.line == c.data.r {
                let toFront = (c.data.s - t.head) * t.dir             // ahead of the locomotive
                let pastTail = (t.head - t.dir * t.total - c.data.s) * t.dir
                if (toFront > -1 && toFront < max(abs(t.speed), 6) * 18) || (toFront <= 0 && pastTail < 8) { active = true }
            }
            if active != c.active || active {
                let on = active && Int(flash * 2) % 2 == 0
                for pair in c.lamps {
                    pair[0].model?.materials = [active && on ? Self.lampOn : Self.lampOff]
                    pair[1].model?.materials = [active && !on ? Self.lampOn : Self.lampOff]
                }
            }
            c.active = active
            let goal: Float = active ? 0 : 1.45
            if abs(c.gate - goal) > 0.001 {
                c.gate += max(-dt * 0.6, min(dt * 0.6, goal - c.gate))
                for (k, g) in c.gates.enumerated() {
                    let heading = SIMD2(c.data.rx, c.data.ry) * (k == 0 ? -1 : 1)
                    let armDir = -perpRight(heading)
                    g.orientation = simd_quatf(angle: atan2(armDir.y, armDir.x), axis: [0, 1, 0]) * simd_quatf(angle: c.gate, axis: [0, 0, 1])
                }
            }
            if active { blockers.append(SIMD2(c.data.x, c.data.y)) }
            crossings[i] = c
        }
        traffic.blockers = blockers
    }

    /// The train whose locomotive is within reach of `p`.
    func locomotive(near p: SIMD2<Float>, within r: Float) -> Int? {
        trains.indices.first { i in
            trains[i].running && !trains[i].cars.isEmpty && simd_distance(physics.bodies[trains[i].cars[0].body].pos, p) < r
        }
    }

    /// The body of a train's locomotive.
    func locomotiveBody(_ i: Int) -> Int { trains[i].cars[0].body }

    /// Driving: throttle from -1 (brake, then back) to 1.
    func throttle(_ i: Int, _ input: Float, _ dt: Float) {
        var t = trains[i]
        let top: Float = lines[t.line].fast ? 38 : 22
        if input > 0 { t.speed = min(top, t.speed + 1.4 * input * dt) }
        else if input < 0 { t.speed = max(-6, t.speed - 3.5 * dt) }
        else { t.speed *= exp(-0.03 * dt) }
        trains[i] = t
    }

    func setDriven(_ i: Int, _ on: Bool) {
        trains[i].driven = on
        // Left to itself again, it carries on at its usual pace.
        if !on { trains[i].speed = max(trains[i].speed, lines[trains[i].line].fast ? 22 : 9) }
    }

    func speed(_ i: Int) -> Float { trains[i].speed }

    /// Where trains are, for the minimap.
    var positions: [SIMD2<Float>] {
        trains.filter(\.running).flatMap { t in t.cars.map { physics.bodies[$0.body].pos } }
    }
}
