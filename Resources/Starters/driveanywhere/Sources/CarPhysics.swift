import Foundation
import RealityKit
import QuartzCore
import simd

enum BodyKind { case player, traffic, parked, train }

/// A car on the flat map. Heading is a compass bearing (0 north, clockwise); spin is its rate of change.
struct Body {
    var pos: SIMD2<Float>
    var vel: SIMD2<Float> = .zero
    var heading: Float
    var spin: Float = 0
    var mass: Float = 1400
    var inertia: Float = 1400 * (4.6 * 4.6 + 1.85 * 1.85) / 12
    var halfLength: Float = 2.3
    var halfWidth: Float = 0.92
    var kind: BodyKind
    /// Moved by physics rather than by a driver.
    var dynamic: Bool
    var asleep = false
    var restTime: Float = 0
    var entity: Entity
    var rear: ModelEntity?
    var braking = false
    var bump: Float = 0          // a little jolt after a hit, for the picture
    var style: CarStyle? = nil   // what kind of vehicle
    // Off the flat map, for crashes: height and its speed, roll (about the length) and pitch (about the width)
    // and theirs, and damage from 0 (fine) to 1 (wrecked).
    var lift: Float = 0
    /// The height of what it stands on: the road, up a kerb onto the sidewalk, or down on the grass.
    var ground: Float = Heights.road
    var liftV: Float = 0
    var roll: Float = 0
    var rollV: Float = 0
    var pitch: Float = 0
    var pitchV: Float = 0
    var damage: Float = 0

    /// On its side or roof.
    var flipped: Bool { abs(roll) > 0.8 || abs(pitch) > 0.8 }
    /// Still moving off the ground or tipping.
    var tumbling: Bool { lift > 0 || liftV != 0 || roll != 0 || rollV != 0 || pitch != 0 || pitchV != 0 }

    var forward: SIMD2<Float> { forwardOf(heading) }
    var right: SIMD2<Float> { perpRight(forward) }

    func circles() -> [SIMD2<Float>] {
        let o = halfLength - halfWidth
        // Enough circles that a long railcar has no gaps between them.
        let n = max(3, Int(ceil(2 * o / halfWidth)) + 1)
        return (0..<n).map { pos + forward * (-o + 2 * o * Float($0) / Float(n - 1)) }
    }

    func velocity(at p: SIMD2<Float>) -> SIMD2<Float> {
        let r = p - pos
        return vel + spin * SIMD2(r.y, -r.x)
    }

    mutating func apply(_ j: SIMD2<Float>, at p: SIMD2<Float>) {
        vel += j / mass
        spin -= cross2(p - pos, j) / inertia
    }
}

/// Collisions among cars, and against buildings, trees and poles.
@MainActor
final class Physics {
    let city: City
    var bodies: [Body] = []
    /// Bodies standing still (parked, asleep), filed once and refiled only when one wakes, sleeps or is culled;
    /// and the few that move (the player, traffic, trains, anything knocked), refiled every substep.
    private var restGrid = Grid<Int>(cell: 8)
    private var moveGrid = Grid<Int>(cell: 8)
    private var moving: [Int] = []
    /// Each body's filing at the last refile: whether it's in, standing still, and where.
    private var filed: [SIMD4<Float>] = []
    /// The hardest hit the player took this frame, in metres a second.
    var playerImpact: Float = 0
    /// Hard hits this frame, for the debris, sparks and sound: where, how hard (m/s of change), which body.
    var crashes: [(pos: SIMD2<Float>, strength: Float, body: Int)] = []
    /// Trees snapped off since the game last looked: where, which way they go over, how fast the car was, the tree's size.
    var felled: [(pos: SIMD2<Float>, dir: SIMD2<Float>, speed: Float, scale: Float, kind: UInt8)] = []
    var onKnock: ((Int) -> Void)?

    init(city: City) { self.city = city }

    /// Set when a body wakes or falls asleep: the standing bodies are refiled next step (and anyway every
    /// quarter second, for those culled or changed from outside).
    private var restDirty = true
    private var lastRefile: CFTimeInterval = 0
    /// The bodies moving under physics this step.
    private var active: [Int] = []
    /// Bodies whose bump is still fading or that are still tipped.
    private var bumped: [Int] = []

    /// Files every body afresh (after bodies are added, removed or moved by hand).
    func rebuildGrid() {
        filed = []
        restDirty = true
        refile()
        fileMoving()
    }

    /// The bodies near a point, standing or moving.
    func query(_ p: SIMD2<Float>, _ r: Float, _ body: (Int) -> Void) {
        restGrid.query(p, r, body)
        moveGrid.query(p, r, body)
    }

    private func still(_ b: Body) -> Bool {
        b.kind != .player && b.kind != .traffic && b.kind != .train && (!b.dynamic || b.asleep)
    }

    /// Refiles the standing bodies when any has changed since the last time, and lists the moving ones.
    private func refile() {
        let clock = CACurrentMediaTime()
        guard restDirty || clock - lastRefile > 0.25 || filed.count != bodies.count else { return }
        restDirty = false
        lastRefile = clock
        var now = [SIMD4<Float>](repeating: .zero, count: bodies.count)
        moving.removeAll(keepingCapacity: true)
        for i in bodies.indices {
            let b = bodies[i]
            // Parked cars far away and trains not running (waiting off the map) take no part.
            let included = b.entity.isEnabled || (b.kind != .parked && b.kind != .train)
            guard included else { continue }
            if still(b) { now[i] = SIMD4(1, b.pos.x, b.pos.y, b.halfLength) } else { now[i] = SIMD4(2, 0, 0, 0); moving.append(i) }
        }
        guard now != filed else { return }
        filed = now
        restGrid = Grid<Int>(cell: 8)
        for i in bodies.indices where now[i].x == 1 {
            let b = bodies[i]
            restGrid.insert(i, min: b.pos - (b.halfLength + 0.3), max: b.pos + (b.halfLength + 0.3))
        }
    }

    private func fileMoving() {
        // Made anew: only the cells the moving bodies are in now, however far they've travelled.
        moveGrid = Grid<Int>(cell: 8)
        for i in moving where i < bodies.count {
            let b = bodies[i]
            moveGrid.insert(i, min: b.pos - (b.halfLength + 0.3), max: b.pos + (b.halfLength + 0.3))
        }
    }

    /// For the F3 readout: milliseconds spent in each part of the last step, the substeps taken and how many
    /// bodies were moving under physics (with how many were trains).
    var profile: (integrate: Double, file: Double, statics: Double, pairs: Double, after: Double, substeps: Int, awake: Int, trains: Int) =
        (0, 0, 0, 0, 0, 0, 0, 0)

    func step(_ dt: Float) {
        var prof = profile
        prof = (0, 0, 0, 0, 0, 0, 0, 0)
        var t = CACurrentMediaTime()
        func lap(_ slot: WritableKeyPath<(integrate: Double, file: Double, statics: Double, pairs: Double, after: Double, substeps: Int, awake: Int, trains: Int), Double>) {
            let now = CACurrentMediaTime()
            prof[keyPath: slot] += (now - t) * 1000
            t = now
        }
        defer { profile = prof }
        playerImpact = 0
        crashes.removeAll(keepingCapacity: true)
        var fastest: Float = 0
        for b in bodies where b.dynamic && !b.asleep { fastest = max(fastest, simd_length(b.vel)) }
        let substeps = max(1, min(6, Int(ceil(fastest * dt / 0.35))))
        let h = dt / Float(substeps)
        prof.substeps = substeps
        // The bodies moving under physics, found once: most bodies are parked cars standing still.
        active.removeAll(keepingCapacity: true)
        for i in bodies.indices where bodies[i].dynamic && !bodies[i].asleep && (bodies[i].kind != .train || bodies[i].entity.isEnabled) {
            active.append(i)
        }
        prof.awake = active.count
        prof.trains = active.filter { bodies[$0].kind == .train }.count
        refile()
        lap(\.file)
        for _ in 0..<substeps {
            for i in active where bodies[i].kind != .train {
                if bodies[i].kind != .player { coast(i, h) }
                bodies[i].pos += bodies[i].vel * h
                bodies[i].heading += bodies[i].spin * h
            }
            lap(\.integrate)
            fileMoving()
            lap(\.file)
            for i in active {
                if bodies[i].kind != .train { collideStatic(i) }
                lap(\.statics)
                collideBodies(i)
                lap(\.pairs)
            }
        }
        for i in active where bodies[i].kind != .player && bodies[i].kind != .train && !bodies[i].asleep {
            if simd_length(bodies[i].vel) < 0.08 && abs(bodies[i].spin) < 0.05 && abs(bodies[i].rollV) < 0.05 && bodies[i].lift == 0 {
                bodies[i].restTime += dt
                if bodies[i].restTime > 0.5 { bodies[i].asleep = true; bodies[i].vel = .zero; bodies[i].spin = 0; restDirty = true }
            } else { bodies[i].restTime = 0 }
        }
        // Bumps fade and tipped bodies settle: only those still moving, or still bumped or tipped.
        bumped = bumped.filter { $0 < bodies.count && (bodies[$0].bump > 0.002 || bodies[$0].tumbling) }
        for i in active where !bumped.contains(i) && (bodies[i].bump > 0.002 || bodies[i].tumbling) { bumped.append(i) }
        for i in bumped {
            bodies[i].bump *= exp(-dt * 6)
            if bodies[i].tumbling { tumble(i, dt) }
        }
        surfaces(dt)
        lap(\.after)
    }

    /// Cars ride up and down kerbs: a kerb taken at speed jolts the car and takes a little off its speed.
    private func surfaces(_ dt: Float) {
        for i in active where bodies[i].dynamic && !bodies[i].asleep && bodies[i].kind != .train && bodies[i].mass >= 300 {
            var b = bodies[i]
            let target = city.surface(b.pos)
            // In water: it slows hard and sinks.
            if target < -1 { b.vel *= exp(-dt * 2.2); b.spin *= exp(-dt * 2.2) }
            let step = target - b.ground
            if target < -1 && step < 0 {
                // Into water: a splash as it goes in, then it settles slowly to the bottom.
                if b.ground > -0.1 { b.bump = max(b.bump, 0.6); if b.kind == .player { playerImpact = max(playerImpact, 2) } }
                b.ground = max(target, b.ground - dt * 0.8)
                b.asleep = false
                bodies[i] = b
                continue
            }
            if abs(step) > 0.08 {
                let speed = simd_length(b.vel)
                if speed > 1 {
                    // Up a kerb: a knock and a little slower; down one: just the drop.
                    if step > 0 { b.vel *= max(0.82, 1 - 0.6 / speed) }
                    b.bump = max(b.bump, min(1, 0.25 + speed / 30))
                    if b.kind == .player { playerImpact = max(playerImpact, step > 0 ? 1.6 + speed * 0.05 : 1.3) }
                }
                b.asleep = false
            }
            b.ground += step * min(1, dt * 30)
            bodies[i] = b
        }
    }

    /// A car nobody drives: its tyres stop it sliding sideways and it rolls to a halt.
    private func coast(_ i: Int, _ h: Float) {
        var b = bodies[i]
        var vf = simd_dot(b.vel, b.forward), vl = simd_dot(b.vel, b.right)
        let roll: Float = b.flipped ? 11 : (b.kind == .parked ? 5 : 3)
        vf = vf > 0 ? max(0, vf - roll * h) : min(0, vf + roll * h)
        vl = vl > 0 ? max(0, vl - 8 * h) : min(0, vl + 8 * h)
        b.vel = b.forward * vf + b.right * vl
        b.spin *= exp(-h * 2.5)
        b.spin = b.spin > 0 ? max(0, b.spin - 1.2 * h) : min(0, b.spin + 1.2 * h)
        bodies[i] = b
    }

    private func collideStatic(_ i: Int) {
        let r = bodies[i].halfWidth
        for c in bodies[i].circles() {
            var center = c
            city.walls.query(center, r + 0.5) { w in
                let q = closestOnSegment(center, w.a, w.b)
                let d = simd_distance(center, q)
                if d < r && d > 1e-5 {
                    let n = (center - q) / d
                    bodies[i].pos += n * (r - d)
                    center += n * (r - d)
                    resolveStatic(i, contact: q, normal: n)
                }
            }
            city.posts.query(center, r + 0.6) { p in
                let d = simd_distance(center, p.c)
                if d < r + p.r && d > 1e-5 {
                    let n = (center - p.c) / d
                    if p.tree > 0 || p.kind > 0 {
                        let spot = City.spot(p.c)
                        if city.fallen.contains(spot) { return }
                        // Hit hard enough, a tree snaps, a sign or signal pole bends over at its foot, and the
                        // car ploughs on, a little slower.
                        let b = bodies[i]
                        let speed = -simd_dot(b.velocity(at: p.c), n)
                        let needs: Float = p.tree > 0 ? 8 + 4 * p.tree : (p.kind == 3 ? 1.5 : (p.kind == 1 ? 4.5 : (p.kind == 4 ? 5 : 7)))
                        if b.mass >= 300 && b.kind != .train && speed > needs {
                            if p.kind == 3 {
                                // A hydrant pops off its pipe: the car hardly notices.
                                city.fallen.insert(spot)
                                let v = simd_length(b.vel)
                                felled.append((p.c, v > 0.1 ? b.vel / v : -n, speed, 0, 3))
                                bodies[i].vel *= 0.96
                                bodies[i].bump = max(bodies[i].bump, 0.3)
                                if b.kind == .player { playerImpact = max(playerImpact, 1.5) }
                                return
                            }
                            city.fallen.insert(spot)
                            let v = simd_length(b.vel)
                            let dir = v > 0.1 ? b.vel / v : -n
                            felled.append((p.c, dir, speed, p.tree, p.kind))
                            // What it takes to break it pushes back at the point of contact: a tree takes a big
                            // bite out of the car's speed and, hit off-centre, slews it round; a signal pole less, a sign a little.
                            let loss: Float = p.tree > 0 ? max(5 + 4 * p.tree, speed * 0.65) : (p.kind == 1 ? 2 : (p.kind == 4 ? 3 : 4.5))
                            let contact = p.c + n * p.r
                            let r = contact - b.pos
                            let rn = cross2(r, n)
                            let j = min(speed * 0.85, loss) / (1 / b.mass + rn * rn / b.inertia)
                            bodies[i].apply(n * j, at: contact)
                            let jolt = j / b.mass
                            if b.kind == .player { playerImpact = max(playerImpact, 2 + jolt * 1.5) }
                            bodies[i].bump = max(bodies[i].bump, min(1, jolt / 8))
                            knock(i, dv: p.tree > 0 ? min(10, 3.5 + jolt) : (p.kind == 1 ? 3 + jolt : 3.5 + jolt), tilt: -n, at: p.c)
                            return
                        }
                    }
                    bodies[i].pos += n * (r + p.r - d)
                    center += n * (r + p.r - d)
                    resolveStatic(i, contact: p.c + n * p.r, normal: n)
                }
            }
        }
    }

    /// Something giving way (a person, a rider) pushes back on body `i` where it was hit: up to `loss` m/s off
    /// its speed there, so an off-centre hit also turns it.
    func pushBack(_ i: Int, at contact: SIMD2<Float>, loss: Float) {
        var b = bodies[i]
        let v = b.velocity(at: contact)
        let speed = simd_length(v)
        guard speed > 0.1, loss > 0 else { return }
        let n = -v / speed
        let rn = cross2(contact - b.pos, n)
        let j = min(speed * 0.85, loss) / (1 / b.mass + rn * rn / b.inertia)
        b.apply(n * j, at: contact)
        b.bump = max(b.bump, min(1, 0.3 + j / b.mass / 6))
        b.asleep = false
        bodies[i] = b
    }

    private func resolveStatic(_ i: Int, contact: SIMD2<Float>, normal n: SIMD2<Float>) {
        var b = bodies[i]
        let v = b.velocity(at: contact)
        let vn = simd_dot(v, n)
        guard vn < 0 else { return }
        let r = contact - b.pos
        let rn = cross2(r, n)
        let j = -(1 + 0.1) * vn / (1 / b.mass + rn * rn / b.inertia)
        b.apply(n * j, at: contact)
        // Scraping along the wall.
        let t = SIMD2(-n.y, n.x)
        let vt = simd_dot(b.velocity(at: contact), t)
        let rt = cross2(r, t)
        var jt = -vt / (1 / b.mass + rt * rt / b.inertia)
        jt = max(-0.3 * j, min(0.3 * j, jt))
        b.apply(t * jt, at: contact)
        if b.kind == .player { playerImpact = max(playerImpact, -vn) }
        b.bump = max(b.bump, min(1, -vn / 12))
        bodies[i] = b
        // Into a wall: the top keeps going.
        knock(i, dv: j / b.mass, tilt: -n, at: contact)
    }

    private func collideBodies(_ i: Int) {
        var others: [Int] = []
        query(bodies[i].pos, bodies[i].halfLength + 1) { j in if j != i && !others.contains(j) { others.append(j) } }
        for j in others {
            let a = bodies[i], b = bodies[j]
            // Both moving under physics: handle each pair once.
            if b.dynamic && !b.asleep && j < i { continue }
            if a.kind == .traffic && !a.dynamic { continue }
            // Train cars run on their rails, coupled: they never push one another about.
            if a.kind == .train && b.kind == .train { continue }
            if b.kind == .train && !b.entity.isEnabled { continue }
            if simd_distance(a.pos, b.pos) > a.halfLength + b.halfLength + 0.2 { continue }
            var best: (pen: Float, n: SIMD2<Float>, p: SIMD2<Float>)?
            for ca in a.circles() {
                for cb in b.circles() {
                    let d = simd_distance(ca, cb)
                    let pen = a.halfWidth + b.halfWidth - d
                    if pen > 0 && d > 1e-5 && (best == nil || pen > best!.pen) {
                        let n = (ca - cb) / d
                        best = (pen, n, cb + n * b.halfWidth)
                    }
                }
            }
            guard let hit = best else { continue }
            // Someone on foot walks round traffic rather than knocking it loose.
            if bodies[j].kind == .traffic && !bodies[j].dynamic && bodies[i].mass < 300 { continue }
            if bodies[j].kind == .traffic && !bodies[j].dynamic {
                bodies[j].dynamic = true
                onKnock?(j)
            }
            if bodies[j].asleep { restDirty = true }
            bodies[j].asleep = false
            bodies[j].restTime = 0
            // Knocked awake: it moves under physics from the next substep.
            if bodies[j].dynamic && !active.contains(j) { active.append(j) }
            let ma = bodies[i].mass, mb = bodies[j].mass
            bodies[i].pos += hit.n * hit.pen * mb / (ma + mb)
            bodies[j].pos -= hit.n * hit.pen * ma / (ma + mb)
            let vrel = bodies[i].velocity(at: hit.p) - bodies[j].velocity(at: hit.p)
            let vn = simd_dot(vrel, hit.n)
            guard vn < 0 else { continue }
            let ra = cross2(hit.p - bodies[i].pos, hit.n), rb = cross2(hit.p - bodies[j].pos, hit.n)
            let jm = -(1 + 0.15) * vn / (1 / ma + 1 / mb + ra * ra / bodies[i].inertia + rb * rb / bodies[j].inertia)
            bodies[i].apply(hit.n * jm, at: hit.p)
            bodies[j].apply(-hit.n * jm, at: hit.p)
            let jolt = min(1, -vn / 10)
            bodies[i].bump = max(bodies[i].bump, jolt)
            bodies[j].bump = max(bodies[j].bump, jolt)
            if bodies[i].kind == .player || bodies[j].kind == .player { playerImpact = max(playerImpact, -vn) }
            // Shoved by another car: each is tripped over away from the other.
            knock(i, dv: jm / ma, tilt: hit.n, at: hit.p)
            knock(j, dv: jm / mb, tilt: -hit.n, at: hit.p)
        }
    }

    /// A hard hit lifts a car, tips it and dents it; big enough, it rolls or flips. `tilt` is the way its top goes.
    private func knock(_ i: Int, dv: Float, tilt: SIMD2<Float>, at p: SIMD2<Float>) {
        guard dv > 3, bodies[i].kind != .train, bodies[i].mass >= 300 else { return }
        var b = bodies[i]
        // Toned down: a hard hit lifts and tips a car, only the hardest send it rolling.
        let k = max(0, dv - 5) * min(1, 2500 / b.mass)
        b.liftV = min(4.5, b.liftV + k * 0.14)
        b.rollV -= simd_dot(tilt, b.right) * k * 0.3
        b.pitchV -= simd_dot(tilt, b.forward) * k * 0.17
        b.asleep = false
        b.restTime = 0
        bodies[i] = b
        if dv > 4 { crashes.append((p, dv, i)) }
    }

    /// Up in the air and over: gravity brings it down, and on the ground it rocks back onto its wheels, or settles
    /// on its side or roof when it's gone too far over.
    private func tumble(_ i: Int, _ dt: Float) {
        var b = bodies[i]
        if b.lift > 0 || b.liftV != 0 {
            b.liftV -= 9.8 * dt
            b.lift += b.liftV * dt
            if b.lift <= 0 {
                b.lift = 0
                if b.liftV < -3 {
                    b.liftV = -b.liftV * 0.3
                    b.rollV *= 0.6
                    b.pitchV *= 0.6
                    crashes.append((b.pos, 4.5, i))
                } else { b.liftV = 0 }
            }
        }
        b.roll += b.rollV * dt
        b.pitch += b.pitchV * dt
        if b.lift == 0 {
            // Always back onto its wheels: whatever way over it went, it rocks (or rolls on round) upright.
            func wrap(_ a: inout Float) { while a > .pi { a -= 2 * .pi }; while a < -.pi { a += 2 * .pi } }
            wrap(&b.roll)
            wrap(&b.pitch)
            func settle(_ a: Float, _ v: inout Float) {
                v += -a * 26 * dt
                v *= exp(-5 * dt)
            }
            settle(b.roll, &b.rollV)
            settle(b.pitch, &b.pitchV)
            if abs(b.rollV) < 0.02 && abs(b.roll) < 0.01 { b.rollV = 0 }
            if abs(b.pitchV) < 0.02 && abs(b.pitch) < 0.01 { b.pitchV = 0 }
            if abs(b.roll) < 0.002 && b.rollV == 0 { b.roll = 0 }
            if abs(b.pitch) < 0.002 && b.pitchV == 0 { b.pitch = 0 }
        } else {
            b.rollV *= exp(-0.5 * dt)
            b.pitchV *= exp(-0.5 * dt)
        }
        bodies[i] = b
    }

    /// Back on its wheels, where it is.
    func rightSideUp(_ i: Int) {
        bodies[i].roll = 0; bodies[i].rollV = 0
        bodies[i].pitch = 0; bodies[i].pitchV = 0
        bodies[i].lift = 0; bodies[i].liftV = 0
    }

    /// Puts each car's picture where its body is: turned to its heading, then rolled and pitched about its middle.
    func sync(_ i: Int, roll: Float = 0, pitch: Float = 0) {
        let b = bodies[i]
        let wobble = b.bump * 0.12 * sin(Float(i) + b.pos.x)
        // Tilted to lie along the slope it's on.
        let slope = simd_quatf(from: [0, 1, 0], to: Terrain.shared.normal(b.pos))
        let turn = slope * simd_quatf(angle: -b.heading, axis: [0, 1, 0]) * simd_quatf(angle: roll + wobble + b.roll, axis: [0, 0, 1])
            * simd_quatf(angle: pitch + b.pitch, axis: [1, 0, 0])
        var at = w3(b.pos, b.ground + b.lift)
        if b.roll != 0 || b.pitch != 0 {
            let mid = SIMD3<Float>(0, 0.8, 0)
            at += mid - turn.act(mid)
            // Never through the road: whichever corner of the body is lowest rests on it at most.
            let h = b.style.map { Self.height($0) } ?? 1.75
            var lowest = Float.infinity
            for x in [-b.halfWidth, b.halfWidth] { for y in [Float(0), h] { for z in [-b.halfLength, b.halfLength] {
                lowest = min(lowest, (at + turn.act(SIMD3(x, y, z))).y)
            } } }
            let floor = b.ground + Terrain.shared.height(b.pos)
            if lowest < floor { at.y += floor - lowest }
        }
        b.entity.transform = Transform(rotation: turn, translation: at)
    }

    /// Roughly how tall each kind of vehicle is, metres.
    static func height(_ style: CarStyle) -> Float {
        switch style {
        case .sports, .supercar: 1.2
        case .golfCart: 2.0
        case .suv, .pickup, .van, .limo: 1.8
        case .monsterTruck: 3.3
        case .ambulance, .boxTruck, .dumpTruck, .cementMixer, .garbageTruck, .bus, .fireTruck: 3.3
        case .bulldozer, .excavator: 3.0
        default: 1.5
        }
    }

    /// The first wall between two points, as a fraction of the way.
    func firstWall(from a: SIMD2<Float>, to b: SIMD2<Float>) -> Float {
        var best: Float = 1
        let d = b - a
        let mid = (a + b) / 2
        city.walls.query(mid, simd_length(d) / 2 + 1) { w in
            let e = w.b - w.a
            let den = cross2(d, e)
            if abs(den) < 1e-6 { return }
            let t = cross2(w.a - a, e) / den
            let u = cross2(w.a - a, d) / den
            if t >= 0 && t < best && u >= 0 && u <= 1 { best = t }
        }
        return best
    }
}
