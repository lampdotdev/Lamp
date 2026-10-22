import SwiftUI
import RealityKit

/// Knocked-off fire hydrants: the hydrant flies off tumbling the way the car was going, and a column of water
/// shoots up from the broken pipe for a while, falling back in a spray.
@MainActor
final class Geysers {
    private struct Drop { let entity: ModelEntity; var vel: SIMD3<Float>; var life: Float }
    private struct Flying { let entity: Entity; var vel: SIMD3<Float>; var spin: SIMD3<Float>; var life: Float }
    private struct Spout { let at: SIMD3<Float>; var left: Float; var clock: Float = 0; let column: Entity; let puddle: Entity }

    private let root = Entity()
    private var drops: [Drop] = []
    private var spare: [ModelEntity] = []
    private var flying: [Flying] = []
    private var spouts: [Spout] = []

    /// A spray drop: a short streak, stretched along the way it's moving.
    private static let mesh: MeshResource = .generateBox(size: [0.07, 0.07, 0.45], cornerRadius: 0.03)
    /// Soft white water, a little see-through, unaffected by shading so it reads as spray rather than glass beads.
    private static let water: RealityKit.Material = {
        var m = UnlitMaterial(color: NSColor(red: 0.86, green: 0.93, blue: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        return m
    }()
    private static let jet: RealityKit.Material = {
        var m = UnlitMaterial(color: NSColor(red: 0.9, green: 0.96, blue: 1, alpha: 1))
        m.blending = .transparent(opacity: .init(floatLiteral: 0.6))
        return m
    }()
    /// The column of water: narrow at the pipe, opening out at the top.
    private static let columnMesh: MeshResource = {
        var k = MeshKit()
        let seg = 10
        let rows: [(Float, Float)] = [(0, 0.1), (2, 0.14), (4.5, 0.22), (6.5, 0.4), (7.2, 0.5)]
        for i in 0..<(rows.count - 1) {
            for j in 0..<seg {
                let a0 = Float(j) / Float(seg) * 2 * .pi, a1 = Float(j + 1) / Float(seg) * 2 * .pi
                let (y0, r0) = rows[i], (y1, r1) = rows[i + 1]
                let p00 = SIMD3(cos(a0) * r0, y0, sin(a0) * r0), p01 = SIMD3(cos(a1) * r0, y0, sin(a1) * r0)
                let p10 = SIMD3(cos(a0) * r1, y1, sin(a0) * r1), p11 = SIMD3(cos(a1) * r1, y1, sin(a1) * r1)
                kit_quad(&k, p00, p01, p11, p10, out: SIMD3(cos((a0 + a1) / 2), 0, sin((a0 + a1) / 2)))
            }
        }
        return k.mesh()!
    }()
    private static func kit_quad(_ k: inout MeshKit, _ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>, out: SIMD3<Float>) {
        k.quad(a, b, c, d, outward: out)
    }
    /// The wet patch spreading round the hydrant.
    private static let puddleMesh: MeshResource = {
        var k = MeshKit()
        k.post([0, 0, 0], radius: 1, height: 0.005, segments: 20)
        return k.mesh()!
    }()
    private static let wet: RealityKit.Material = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(red: 0.16, green: 0.2, blue: 0.24, alpha: 1))
        m.roughness = .init(floatLiteral: 0.05)
        m.blending = .transparent(opacity: .init(floatLiteral: 0.55))
        return m
    }()

    init(into parent: Entity) { parent.addChild(root) }

    func start(at p: SIMD2<Float>, toward d: SIMD2<Float>, speed: Float) {
        let base = w3(p, Heights.sidewalk)
        if spouts.count >= 3 {
            let old = spouts.removeFirst()
            old.column.removeFromParent(); old.puddle.removeFromParent()
        }
        let column = ModelEntity(mesh: Self.columnMesh, materials: [Self.jet])
        column.position = base
        root.addChild(column)
        let puddle = ModelEntity(mesh: Self.puddleMesh, materials: [Self.wet])
        puddle.position = base + [0, 0.02, 0]
        puddle.scale = [0.3, 1, 0.3]
        root.addChild(puddle)
        spouts.append(Spout(at: base, left: 25, column: column, puddle: puddle))
        // The hydrant itself, off on its own.
        let h = Furniture.model(.hydrant).clone(recursive: true)
        h.position = base
        root.addChild(h)
        let push = max(4, min(16, speed * 0.8))
        flying.append(Flying(entity: h, vel: SIMD3(d.x * push, 4 + speed * 0.2, -d.y * push),
                             spin: SIMD3(Float.random(in: -9...9), Float.random(in: -4...4), Float.random(in: -9...9)), life: 20))
    }

    /// Moves the water and the flying hydrants; returns how loud the spray is from `listener` (0 to 1).
    func update(_ dt: Float, near listener: SIMD2<Float>) -> Float {
        var loud: Float = 0
        for k in spouts.indices.reversed() {
            spouts[k].left -= dt
            if spouts[k].left <= 0 {
                spouts[k].column.removeFromParent()
                // The wet patch stays a while longer, then dries.
                let puddle = spouts[k].puddle
                Task { @MainActor in try? await Task.sleep(for: .seconds(20)); puddle.removeFromParent() }
                spouts.remove(at: k)
                continue
            }
            let fade = min(1, spouts[k].left / 4)
            let at = spouts[k].at
            // The column surges a little and dies down at the end.
            let surge = 0.9 + 0.1 * sin(spouts[k].left * 23) + 0.05 * sin(spouts[k].left * 61)
            spouts[k].column.scale = [1 + 0.15 * sin(spouts[k].left * 37), fade * surge, 1 + 0.15 * cos(spouts[k].left * 29)]
            let wetR = min(4.5, 0.3 + (25 - spouts[k].left) * 0.35)
            spouts[k].puddle.scale = [wetR, 1, wetR]
            loud = max(loud, fade * max(0, 1 - simd_distance(SIMD2(at.x, -at.z), listener) / 60))
            // About 40 drops a second, up 7–10 m, spreading a little.
            spouts[k].clock += dt
            while spouts[k].clock > 0.025 {
                spouts[k].clock -= 0.025
                guard drops.count < 220 else { break }
                let e = spare.popLast() ?? ModelEntity(mesh: Self.mesh, materials: [Self.water])
                e.position = at + [Float.random(in: -0.05...0.05), 0.15, Float.random(in: -0.05...0.05)]
                e.scale = .one * Float.random(in: 0.6...1.3)
                if e.parent == nil { root.addChild(e) }
                e.isEnabled = true
                // From the top of the column, spreading out and falling back.
                let up = Float.random(in: 1...3.5) * fade
                e.position = at + [Float.random(in: -0.3...0.3), 7 * fade * surge, Float.random(in: -0.3...0.3)]
                drops.append(Drop(entity: e, vel: [Float.random(in: -2.6...2.6), up, Float.random(in: -2.6...2.6)], life: 3))
            }
        }
        var i = 0
        while i < drops.count {
            var d = drops[i]
            d.life -= dt
            d.vel.y -= 9.8 * dt
            d.entity.position += d.vel * dt
            if simd_length(d.vel) > 0.1 { d.entity.orientation = simd_quatf(from: [0, 0, 1], to: simd_normalize(d.vel)) }
            if d.entity.position.y < Heights.road + Terrain.shared.height(SIMD2(d.entity.position.x, -d.entity.position.z)) || d.life <= 0 {
                d.entity.isEnabled = false
                spare.append(d.entity)
                drops.swapAt(i, drops.count - 1)
                drops.removeLast()
                continue
            }
            drops[i] = d
            i += 1
        }
        for k in flying.indices.reversed() {
            var f = flying[k]
            f.life -= dt
            if f.life <= 0 { f.entity.removeFromParent(); flying.remove(at: k); continue }
            f.vel.y -= 9.8 * dt
            var p = f.entity.position + f.vel * dt
            let floor = Heights.road + Terrain.shared.height(SIMD2(p.x, -p.z))
            if p.y < floor {
                p.y = floor
                f.vel = SIMD3(f.vel.x * 0.5, abs(f.vel.y) * 0.3, f.vel.z * 0.5)
                f.spin *= 0.5
            }
            f.entity.position = p
            let a = simd_length(f.spin) * dt
            if a > 0.0001 { f.entity.orientation = simd_quatf(angle: a, axis: simd_normalize(f.spin)) * f.entity.orientation }
            flying[k] = f
        }
        return loud
    }
}
