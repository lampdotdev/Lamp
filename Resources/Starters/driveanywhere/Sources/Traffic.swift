import SwiftUI
import RealityKit

/// A traffic car following the real streets, lane by lane, stopping for lights and for cars ahead.
struct Driver {
    var body: Int
    var edge: Int
    var forward: Bool
    var s: Float
    var speed: Float
    var lane: Int
    var next: Int?
    var nextForward = true
    var eagerness: Float
    var stuck: Float = 0
    var knockedTime: Float = 0
    /// At a stop sign: when it stopped at the line, and whether it's been let through.
    var stoppedAt: Float?
    var cleared = false
}

@MainActor
final class Traffic {
    let city: City
    let physics: Physics
    var drivers: [Driver] = []
    var signals: [Int: SignalLamps] = [:]
    /// Level crossings with a train coming: traffic waits short of them.
    var blockers: [SIMD2<Float>] = []
    /// A siren behind: where it is and which way it's going. Traffic ahead of it stops to let it by.
    var siren: (SIMD2<Float>, SIMD2<Float>)?
    private var lastCheck: Float = 0

    static let lampOff: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(white: 0.12, alpha: 1))
        m.roughness = 0.3
        return m
    }()
    static let lampOn: [PhysicallyBasedMaterial] = [
        LampMaterial.glow(NSColor(red: 1, green: 0.12, blue: 0.08, alpha: 1), strength: 6),
        LampMaterial.glow(NSColor(red: 1, green: 0.72, blue: 0.05, alpha: 1), strength: 6),
        LampMaterial.glow(NSColor(red: 0.2, green: 1, blue: 0.45, alpha: 1), strength: 6),
    ]

    init(city: City, physics: Physics) { self.city = city; self.physics = physics }

    // MARK: Signals

    /// The direction of the main road through a signalled crossing: roads along it share one phase.
    static func signalAxis(_ city: City, _ n: Int) -> SIMD2<Float> {
        let node = city.nodes[n]
        guard let main = node.edges.max(by: { city.edges[$0].rank < city.edges[$1].rank }) else { return [0, 1] }
        return city.edges[main].outward(from: n)
    }

    /// 0 green, 1 yellow, 2 red.
    /// Each crossing has its own cycle (26–40 s) and starting point, so the lights don't all change together.
    func light(_ node: Int, group: Int, time: Float) -> Int { Self.light(node, group: group, time: time) }

    nonisolated static func light(_ node: Int, group: Int, time: Float) -> Int {
        var h = UInt32(truncatingIfNeeded: node &* 2654435761 &+ 97)
        h = (h ^ (h >> 15)) &* 2246822519
        let cycle = 26 + Float(h % 15)
        let t = (time + Float((h >> 8) % 1000) / 1000 * cycle).truncatingRemainder(dividingBy: cycle)
        let local = group == 0 ? t : (t + cycle / 2).truncatingRemainder(dividingBy: cycle)
        return local < cycle * 0.375 ? 0 : (local < cycle * 0.47 ? 1 : 2)
    }

    func updateLamps(time: Float) {
        for (n, var lamps) in signals {
            var changed = false
            for g in 0..<2 {
                let state = light(n, group: g, time: time)
                if lamps.shown[g] == state { continue }
                lamps.shown[g] = state
                changed = true
                let colour = [2, 1, 0][state]      // red, yellow, green in the lamp order
                for c in 0..<3 {
                    for lamp in lamps.lamps[g][c] { lamp.model?.materials = [c == colour ? Self.lampOn[c] : Self.lampOff] }
                }
            }
            if changed { signals[n] = lamps }
        }
    }

    // MARK: Spawning

    func spawnAll(count: Int, around p: SIMD2<Float>) {
        for _ in 0..<count {
            let style = CarStyle.randomTraffic()
            let entity = CarFactory.make(style, color: style.paint(Int.random(in: 0..<1000)))
            entity.findEntity(named: "body")?.lampShadow()
            let size = CarFactory.size(style)
            let mass = style.handling.mass
            var body = Body(pos: p, heading: 0, mass: mass, inertia: mass * (size.x * size.x + size.y * size.y) / 12,
                            halfLength: size.x / 2, halfWidth: size.y / 2, kind: .traffic, dynamic: false, entity: entity,
                            rear: entity.findEntity(named: "rear") as? ModelEntity)
            body.style = style
            physics.bodies.append(body)
            // Heavy and slow machines dawdle, fast ones press on.
            var eager = style == .sports ? Float.random(in: 1.05...1.25) : Float.random(in: 0.85...1.1)
            if style.handling.mass > 6000 { eager = 0.75 }
            if style == .bulldozer { eager = 0.4 }
            if style == .golfCart { eager = 0.75 }
            if style == .supercar { eager = 1.3 }
            drivers.append(Driver(body: physics.bodies.count - 1, edge: 0, forward: true, s: 0, speed: 0, lane: 0, eagerness: eager))
            place(drivers.count - 1, around: p, from: 20, to: 420)
        }
    }

    /// Cars waiting at each stop-sign crossing, first come first served, and until when the last one let through
    /// has the crossing to itself.
    private var stopQueue: [Int: [Int]] = [:]
    private var crossingUntil: [Int: Float] = [:]

    private func endOf(_ d: Driver) -> Int {
        let e = city.edges[d.edge]
        return d.forward ? e.b : e.a
    }

    private func lanesPerDirection(_ e: RoadEdge) -> Int { e.oneway ? e.lanes : max(1, e.lanes / 2) }

    private func laneOffset(_ e: RoadEdge, _ lane: Int) -> Float {
        let per = Float(lanesPerDirection(e))
        if e.oneway { return -e.driveWidth / 2 + e.driveWidth / per * (Float(lane) + 0.5) }
        // Two-way: on the right of the way it's going where traffic keeps right, else on the left.
        return e.driveWidth / 2 * (Float(lane) + 0.5) / per * CityConfig.current.style.side
    }

    /// Puts a driver somewhere on the streets between two distances from a point, clear of other cars.
    func place(_ d: Int, around p: SIMD2<Float>, from: Float, to: Float) {
        for _ in 0..<120 {
            let ei = Int.random(in: 0..<city.edges.count)
            let e = city.edges[ei]
            if e.isService || e.length < 20 { continue }
            // Busy streets get more cars: chosen in proportion to their rank.
            if Float.random(in: 0..<6) > e.trafficWeight { continue }
            let s = Float.random(in: 5...(e.length - 5))
            let pt = e.sample(s).0
            let dist = simd_distance(pt, p)
            if dist < from || dist > to { continue }
            var clear = true
            physics.query(pt, 10) { j in if simd_distance(self.physics.bodies[j].pos, pt) < 9 { clear = false } }
            if !clear { continue }
            let forward = e.oneway ? true : Bool.random()
            var drv = drivers[d]
            drv.edge = ei; drv.forward = forward; drv.s = forward ? s : e.length - s
            drv.lane = Int.random(in: 0..<lanesPerDirection(e))
            drv.speed = e.speedLimit * 0.6
            drv.next = nil; drv.stuck = 0; drv.knockedTime = 0
            drv.stoppedAt = nil; drv.cleared = false
            drivers[d] = drv
            let (pos, dir) = target(drv)
            var b = physics.bodies[drv.body]
            b.pos = pos; b.heading = atan2(dir.x, dir.y); b.vel = dir * drv.speed; b.spin = 0
            b.dynamic = false; b.asleep = false
            physics.bodies[drv.body] = b
            physics.sync(drv.body)
            return
        }
        // Nowhere free this time: parked out of the way until the next look round.
        physics.bodies[drivers[d].body].pos = SIMD2(5000, 5000)
        physics.bodies[drivers[d].body].dynamic = false
        physics.sync(drivers[d].body)
    }

    private func target(_ d: Driver) -> (SIMD2<Float>, SIMD2<Float>) {
        let e = city.edges[d.edge]
        var (p, dir) = e.sample(d.forward ? d.s : e.length - d.s)
        if !d.forward { dir = -dir }
        return (p + perpRight(dir) * laneOffset(e, d.lane), dir)
    }

    private func chooseNext(_ d: inout Driver) {
        let e = city.edges[d.edge]
        let node = d.forward ? e.b : e.a
        var options: [(Int, Bool, Float)] = []
        for ci in city.nodes[node].edges where ci != d.edge {
            let c = city.edges[ci]
            if c.a == c.b { continue }
            let fwd = c.a == node
            if c.oneway && !fwd { continue }
            var w: Float = c.isService ? 0.05 : c.trafficWeight
            if c.name == e.name && !c.name.isEmpty { w *= 2.5 }
            options.append((ci, fwd, w))
        }
        if options.isEmpty {
            if !e.oneway { d.next = d.edge; d.nextForward = !d.forward } else { d.next = nil }
            return
        }
        var pick = Float.random(in: 0..<options.reduce(0) { $0 + $1.2 })
        for o in options {
            pick -= o.2
            if pick <= 0 { d.next = o.0; d.nextForward = o.1; return }
        }
        d.next = options.last!.0; d.nextForward = options.last!.1
    }

    // MARK: Driving

    func update(_ dt: Float, time: Float, player: SIMD2<Float>) {
        for i in drivers.indices {
            let bi = drivers[i].body
            if physics.bodies[bi].dynamic {
                drivers[i].knockedTime += dt
                continue
            }
            drive(i, dt, time: time)
        }
        // Keep the traffic around the player, and tidy away wrecks out of sight.
        if time - lastCheck > 1 {
            lastCheck = time
            for i in drivers.indices {
                let b = physics.bodies[drivers[i].body]
                let far = simd_distance(b.pos, player)
                if far > 480 || (b.dynamic && drivers[i].knockedTime > 12 && far > 70 && b.asleep) {
                    place(i, around: player, from: 180, to: 430)
                }
            }
        }
    }

    private func drive(_ i: Int, _ dt: Float, time: Float) {
        var d = drivers[i]
        let e = city.edges[d.edge]
        let remaining = e.length - d.s
        let endNode = d.forward ? e.b : e.a
        if d.next == nil && remaining < 45 { chooseNext(&d) }
        var want = e.speedLimit * d.eagerness
        let (_, dirNow) = target(d)

        // Slow for turns.
        if let n = d.next {
            let endDir = d.forward ? e.sample(e.length).1 : -e.sample(0).1
            let nextDir = city.edges[n].outward(from: endNode)
            let turn = simd_dot(endDir, nextDir)
            if turn < 0.8 {
                let corner: Float = turn < 0 ? 4 : 6.5
                want = min(want, corner + sqrt(max(0, 2 * 2.5 * (remaining - city.nodes[endNode].radius))))
            }
        } else if remaining < 30 {
            want = min(want, 2 + remaining * 0.3)
        }

        // Lights.
        var redAhead = false
        if city.nodes[endNode].signal {
            let approach = -(d.forward ? e.sample(e.length).1 : -e.sample(0).1)
            let group = abs(simd_dot(approach, Self.signalAxis(city, endNode))) > 0.707 ? 0 : 1
            let state = light(endNode, group: group, time: time)
            let stopAt = city.nodes[endNode].radius + 6.0
            let gap = remaining - stopAt
            if gap > -0.5 && (state == 2 || (state == 1 && gap > 9)) {
                redAhead = true
                want = min(want, sqrt(max(0, 2 * 4 * max(0, gap - 0.3))))
                if gap < 0.6 { want = 0 }
            }
        }

        // Stop signs: stop at the line, wait a second, and go in the order cars arrived, one at a time.
        if !city.nodes[endNode].signal && !d.cleared && (city.nodes[endNode].allStop || (d.forward ? e.stops.1 : e.stops.0)) {
            let stopAt = city.nodes[endNode].radius + 3.0
            let gap = remaining - stopAt
            if gap > -1 {
                redAhead = true
                want = min(want, sqrt(max(0, 2 * 4 * max(0, gap - 0.3))))
                if gap < 1.5 && d.speed < 0.6 {
                    if d.stoppedAt == nil { d.stoppedAt = time; stopQueue[endNode, default: []].append(i) }
                    // The queue keeps only cars still waiting at this crossing.
                    while let f = stopQueue[endNode]?.first, f != i,
                          !(drivers[f].stoppedAt != nil && !drivers[f].cleared && endOf(drivers[f]) == endNode) {
                        stopQueue[endNode]!.removeFirst()
                    }
                    let first = stopQueue[endNode]?.first == i
                    let clear = (crossingUntil[endNode] ?? 0) < time
                    if first && time - (d.stoppedAt ?? time) > 1 && clear {
                        d.cleared = true
                        stopQueue[endNode]!.removeFirst()
                        crossingUntil[endNode] = time + 2.2
                    }
                }
                if gap < 0.6 && !d.cleared { want = 0 }
            }
        }

        // Cars ahead.
        let me = physics.bodies[d.body]
        if d.stuck < 8 {
            physics.query(me.pos + dirNow * 12, 14) { j in
                if j == d.body { return }
                let o = self.physics.bodies[j]
                let rel = o.pos - me.pos
                let ahead = simd_dot(rel, dirNow)
                let side = abs(simd_dot(rel, perpRight(dirNow)))
                if ahead > 0 && ahead < 26 && side < 2.3 {
                    // Coming the other way in the same spot is a jam, not a queue.
                    let gap = ahead - (me.halfLength + o.halfLength + 1.8)
                    want = min(want, max(0, gap) * 0.9 + (simd_dot(o.vel, dirNow) > 1 ? simd_dot(o.vel, dirNow) * 0.5 : 0))
                }
            }
        }
        if let (sp, sf) = siren {
            let rel = me.pos - sp
            let ahead = simd_dot(rel, sf)
            if ahead > 3, ahead < 45, abs(simd_dot(rel, perpRight(sf))) < 7, simd_dot(dirNow, sf) > 0.3 { want = 0; redAhead = true }
        }
        for x in blockers {
            let rel = x - me.pos
            let ahead = simd_dot(rel, dirNow)
            if ahead > 6, ahead < 40, abs(simd_dot(rel, perpRight(dirNow))) < 6 {
                want = min(want, max(0, ahead - 9) * 0.8)
                redAhead = true
            }
        }
        if d.speed < 0.3 && !redAhead { d.stuck += dt } else if d.speed > 2 { d.stuck = 0 }
        if d.stuck > 10 { d.stuck = 0 }

        let accel = want > d.speed ? min(want - d.speed, 3.2 * dt) : max(want - d.speed, -9 * dt)
        d.speed = max(0, d.speed + accel)
        d.s += d.speed * dt
        while d.s >= city.edges[d.edge].length {
            d.s -= city.edges[d.edge].length
            if d.next == nil { chooseNext(&d) }
            guard let n = d.next else { drivers[i] = d; place(i, around: physics.bodies[d.body].pos, from: 150, to: 400); return }
            d.edge = n; d.forward = d.nextForward; d.next = nil
            d.stoppedAt = nil; d.cleared = false
            d.lane = min(d.lane, lanesPerDirection(city.edges[n]) - 1)
        }
        drivers[i] = d

        // The body follows its lane a little behind, so it takes corners in a curve.
        let (goal, _) = target(d)
        var b = physics.bodies[d.body]
        let old = b.pos
        b.pos += (goal - b.pos) * min(1, dt * 4)
        let moved = (b.pos - old) / max(dt, 1e-4)
        b.vel = moved
        if simd_length(moved) > 0.4 {
            let h = atan2(moved.x, moved.y)
            var dh = h - b.heading
            while dh > .pi { dh -= 2 * .pi }
            while dh < -.pi { dh += 2 * .pi }
            b.heading += dh * min(1, dt * 8)
        }
        let braking = accel < -0.5 * dt || d.speed < 0.5
        if braking != b.braking {
            b.braking = braking
            b.rear?.model?.materials = [braking ? CarFactory.brakeLight : CarFactory.taillight]
        }
        physics.bodies[d.body] = b
        physics.sync(d.body)
    }
}
