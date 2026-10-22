import SwiftUI
import RealityKit

/// What flies off in a crash (bits of bumper, glass, sparks) and the smoke from damaged cars.
@MainActor
final class CrashFX {
    private struct Bit { let entity: Entity; var vel: SIMD3<Float>; let spin: SIMD3<Float>; var life: Float; let smoke: Bool; let start: Float }
    private var bits: [Bit] = []
    private let root = Entity()
    private var smokeClock: Float = 0

    private static let chunk = MeshResource.generateBox(size: [0.22, 0.06, 0.16])
    private static let shard = MeshResource.generateBox(size: [0.08, 0.02, 0.1])
    private static let spark = MeshResource.generateBox(size: [0.04, 0.04, 0.12])
    private static let puff: MeshResource = {
        var k = MeshKit()
        k.blob(.zero, radius: 0.5, segments: 7, rings: 4)
        return k.mesh()!
    }()
    private static let glass = LampMaterial.glass(NSColor(red: 0.8, green: 0.9, blue: 1, alpha: 1), clear: 0.5)
    private static let dark = LampMaterial.plastic(NSColor(white: 0.08, alpha: 1))
    private static let sparkGlow = LampMaterial.glow(NSColor(red: 1, green: 0.6, blue: 0.15, alpha: 1), strength: 6)
    private static let smokeGray = LampMaterial.plastic(NSColor(white: 0.35, alpha: 1), gloss: 0)
    private static let smokeBlack = LampMaterial.plastic(NSColor(white: 0.1, alpha: 1), gloss: 0)
    private static let fire = LampMaterial.glow(NSColor(red: 1, green: 0.42, blue: 0.05, alpha: 1), strength: 4)
    static let burnt = LampMaterial.paint(NSColor(red: 0.09, green: 0.08, blue: 0.07, alpha: 1))

    init(into parent: Entity) { parent.addChild(root) }

    /// A burst where something hit: harder hits throw more.
    func burst(at p: SIMD3<Float>, strength: Float, paint: RealityKit.Material?) {
        guard bits.count < 260 else { return }
        let n = min(18, Int(strength * 0.9))
        for k in 0..<n {
            let kind = k % 3
            let mesh = kind == 0 ? Self.chunk : (kind == 1 ? Self.shard : Self.spark)
            let mat: RealityKit.Material = kind == 0 ? (paint ?? Self.dark) : (kind == 1 ? Self.glass : Self.sparkGlow)
            let e = ModelEntity(mesh: mesh, materials: [mat])
            e.position = p + SIMD3(Float.random(in: -0.4...0.4), Float.random(in: 0.3...1.0), Float.random(in: -0.4...0.4))
            root.addChild(e)
            let speed = Float.random(in: 2...5) + strength * 0.25
            let dir = simd_normalize(SIMD3(Float.random(in: -1...1), Float.random(in: 0.4...1.4), Float.random(in: -1...1)))
            bits.append(Bit(entity: e, vel: dir * speed, spin: SIMD3(Float.random(in: -14...14), Float.random(in: -14...14), Float.random(in: -14...14)),
                            life: kind == 2 ? Float.random(in: 0.3...0.6) : Float.random(in: 2.5...4), smoke: false, start: 0))
        }
    }

    private static let leafGreen = LampMaterial.plastic(NSColor(red: 0.24, green: 0.42, blue: 0.16, alpha: 1), gloss: 0)
    private static let splinter = LampMaterial.wood(NSColor(red: 0.8, green: 0.68, blue: 0.48, alpha: 1))

    /// Leaves and splinters: off a tree as it snaps, and from its crown when it lands.
    func leaves(at p: SIMD3<Float>, count: Int, spread: Float) {
        guard bits.count < 260 else { return }
        for k in 0..<count {
            let wood = k % 4 == 0
            let e = ModelEntity(mesh: wood ? Self.spark : Self.shard, materials: [wood ? Self.splinter : Self.leafGreen])
            e.position = p + SIMD3(Float.random(in: -spread...spread), Float.random(in: -0.5...0.8), Float.random(in: -spread...spread))
            if !wood { e.scale = [2, 1, 2] }
            root.addChild(e)
            let dir = simd_normalize(SIMD3(Float.random(in: -1...1), Float.random(in: 0.2...1.2), Float.random(in: -1...1)))
            bits.append(Bit(entity: e, vel: dir * Float.random(in: 1.5...4.5), spin: SIMD3(Float.random(in: -9...9), Float.random(in: -9...9), Float.random(in: -9...9)),
                            life: Float.random(in: 2...4), smoke: false, start: 0))
        }
    }

    /// Smoke (and, when wrecked, fire) rising off a damaged car.
    func smoke(from p: SIMD3<Float>, damage: Float) {
        guard bits.count < 260 else { return }
        let wrecked = damage >= 1
        let e = ModelEntity(mesh: Self.puff, materials: [wrecked ? Self.smokeBlack : Self.smokeGray])
        e.position = p + SIMD3(Float.random(in: -0.3...0.3), 0, Float.random(in: -0.3...0.3))
        e.scale = [0.4, 0.4, 0.4]
        root.addChild(e)
        bits.append(Bit(entity: e, vel: [Float.random(in: -0.3...0.3), 1.6, Float.random(in: -0.3...0.3)], spin: .zero,
                        life: 2.2, smoke: true, start: 2.2))
        if wrecked && Bool.random() {
            let f = ModelEntity(mesh: Self.puff, materials: [Self.fire])
            f.position = p + [0, -0.2, 0]
            f.scale = [0.5, 0.6, 0.5]
            root.addChild(f)
            bits.append(Bit(entity: f, vel: [0, 1.2, 0], spin: .zero, life: 0.5, smoke: true, start: 0.5))
        }
    }

    /// Smoke puffs from damaged cars near `p`, a few times a second.
    func smokeFrom(_ bodies: [Body], near p: SIMD2<Float>, dt: Float) {
        smokeClock += dt
        guard smokeClock > 0.12 else { return }
        smokeClock = 0
        for b in bodies where b.damage > 0.5 && b.entity.isEnabled && simd_distance(b.pos, p) < 90 {
            // From under the bonnet: the front of the car.
            let front = b.pos + b.forward * (b.halfLength - 0.8)
            smoke(from: w3(front, Heights.road + b.lift + 1.1), damage: b.damage)
        }
    }

    func update(_ dt: Float) {
        var i = 0
        while i < bits.count {
            var b = bits[i]
            b.life -= dt
            if b.life <= 0 {
                b.entity.removeFromParent()
                bits.remove(at: i)
                continue
            }
            if b.smoke {
                b.entity.position += b.vel * dt
                let grown = 1 - b.life / b.start
                let s = 0.4 + grown * 2.0
                b.entity.scale = SIMD3(repeating: s * min(1, b.life * 2.5))
            } else {
                b.vel.y -= 9.8 * dt
                var p = b.entity.position + b.vel * dt
                let floor = Terrain.shared.height(SIMD2(p.x, -p.z)) + 0.2
                if p.y < floor {
                    p.y = floor
                    b.vel = SIMD3(b.vel.x * 0.5, abs(b.vel.y) * 0.3, b.vel.z * 0.5)
                }
                b.entity.position = p
                let a = simd_length(b.spin) * dt
                if a > 0 { b.entity.orientation = simd_quatf(angle: a * min(1, simd_length(b.vel) / 2), axis: simd_normalize(b.spin)) * b.entity.orientation }
            }
            bits[i] = b
            i += 1
        }
    }
}
