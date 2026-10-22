import RealityKit
import simd

/// Trees snapped off, and street signs and signal poles bent over, by a hard hit: each goes over the way the car
/// was going, slowly then fast, bounces once, lies there a while and then sinks away. A tree's stump stays.
@MainActor
final class TreeFall {
    private struct Faller {
        let pivot: Entity
        let axis: SIMD3<Float>
        let dir: SIMD3<Float>
        let scale: Float
        let rest: Float
        let reach: Float
        let metal: Bool
        var angle: Float
        var spin: Float
        var bounced = false
        var lying: Float = 0
    }
    private let root = Entity()
    private var fallers: [Faller] = []

    init(into parent: Entity) { parent.addChild(root) }

    func fell(at c: SIMD2<Float>, toward d: SIMD2<Float>, speed: Float, variant: Int, scale: Float) {
        if fallers.count >= 12 { fallers.removeFirst().pivot.removeFromParent() }
        // Snapped half a metre up, where the stump ends.
        let pivot = Entity()
        pivot.position = w3(c, Heights.ground + 0.5 * scale)
        let tree = TreeFactory.make(variant)
        tree.scale = [scale, scale, scale]
        tree.position = [0, -0.5 * scale, 0]
        tree.orientation = simd_quatf(angle: Float.random(in: 0..<6.28), axis: [0, 1, 0])
        pivot.addChild(tree)
        root.addChild(pivot)
        // Mostly the way the car went, a little to one side.
        let a = atan2(d.y, d.x) + Float.random(in: -0.3...0.3)
        let dir = SIMD3<Float>(cos(a), 0, -sin(a))
        let axis = simd_normalize(simd_cross([0, 1, 0], dir))
        // It lies about 1.25 over, its crown on the ground.
        fallers.append(Faller(pivot: pivot, axis: axis, dir: dir, scale: scale, rest: 1.25, reach: 4 * scale, metal: false,
                              angle: 0.04, spin: 0.3 + speed * 0.04))
    }

    /// A street sign or signal pole bent over at its foot, `height` metres tall.
    func topple(_ e: Entity, at c: SIMD2<Float>, toward d: SIMD2<Float>, speed: Float, height: Float) {
        if fallers.count >= 12 { fallers.removeFirst().pivot.removeFromParent() }
        let pivot = Entity()
        pivot.position = w3(c, Heights.sidewalk)
        root.addChild(pivot)
        e.setParent(pivot, preservingWorldTransform: true)
        let a = atan2(d.y, d.x) + Float.random(in: -0.25...0.25)
        let dir = SIMD3<Float>(cos(a), 0, -sin(a))
        let axis = simd_normalize(simd_cross([0, 1, 0], dir))
        // Height sets how quickly it goes; it lies flat.
        fallers.append(Faller(pivot: pivot, axis: axis, dir: dir, scale: height / 5, rest: 1.53, reach: height * 0.8, metal: true,
                              angle: 0.08, spin: 0.6 + speed * 0.06))
    }

    /// Moves the falling trees; returns where crowns hit the ground this frame, with how hard.
    func update(_ dt: Float) -> [(pos: SIMD2<Float>, strength: Float, metal: Bool)] {
        var landed: [(pos: SIMD2<Float>, strength: Float, metal: Bool)] = []
        for k in fallers.indices.reversed() {
            var f = fallers[k]
            if f.angle < f.rest || f.spin > 0 {
                // A falling pole: the further over, the faster it goes.
                f.spin += 2.8 / f.scale * sin(f.angle) * dt
                f.angle += f.spin * dt
                if f.angle >= f.rest {
                    f.angle = f.rest
                    if !f.bounced {
                        let crown = f.pivot.position + f.dir * f.reach
                        landed.append((SIMD2(crown.x, -crown.z), min(1, f.spin / 2.5), f.metal))
                        f.bounced = true
                        f.spin = -f.spin * 0.22
                    } else {
                        f.spin = 0
                    }
                }
            } else {
                f.lying += dt
                // After a while it sinks into the ground and is gone.
                if f.lying > 40 {
                    f.pivot.position.y -= dt * 0.9
                    if f.lying > 45 {
                        f.pivot.removeFromParent()
                        fallers.remove(at: k)
                        continue
                    }
                }
            }
            f.pivot.orientation = simd_quatf(angle: f.angle, axis: f.axis)
            fallers[k] = f
        }
        return landed
    }
}
