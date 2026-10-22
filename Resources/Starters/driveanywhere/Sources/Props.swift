import SwiftUI
import RealityKit

// MARK: - Mesh building

/// Collects flat-shaded triangles and makes one mesh of them. Faces turn to `outward` when given.
struct MeshKit {
    var pos: [SIMD3<Float>] = []
    var nor: [SIMD3<Float>] = []
    var uv: [SIMD2<Float>] = []
    var idx: [UInt32] = []

    var isEmpty: Bool { idx.isEmpty }

    mutating func tri(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>,
                      uv t: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = ([0, 0], [1, 0], [0, 1]),
                      outward: SIMD3<Float>? = nil) {
        var n = simd_cross(b - a, c - a)
        let len = simd_length(n)
        guard len > 1e-9 else { return }
        n /= len
        let base = UInt32(pos.count)
        if let o = outward, simd_dot(n, o) < 0 {
            pos += [a, c, b]; uv += [t.0, t.2, t.1]; n = -n
        } else {
            pos += [a, b, c]; uv += [t.0, t.1, t.2]
        }
        nor += [n, n, n]
        idx += [base, base + 1, base + 2]
    }

    mutating func quad(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ c: SIMD3<Float>, _ d: SIMD3<Float>,
                       uv t: (SIMD2<Float>, SIMD2<Float>, SIMD2<Float>, SIMD2<Float>) = ([0, 0], [1, 0], [1, 1], [0, 1]),
                       outward: SIMD3<Float>? = nil) {
        var n = simd_cross(c - a, d - b)
        let len = simd_length(n)
        guard len > 1e-9 else { return }
        n /= len
        let base = UInt32(pos.count)
        if let o = outward, simd_dot(n, o) < 0 {
            pos += [a, d, c, b]; uv += [t.0, t.3, t.2, t.1]; n = -n
        } else {
            pos += [a, b, c, d]; uv += [t.0, t.1, t.2, t.3]
        }
        nor += [n, n, n, n]
        idx += [base, base + 1, base + 2, base, base + 2, base + 3]
    }

    /// A box, its texture laid on in metres.
    mutating func box(_ center: SIMD3<Float>, _ size: SIMD3<Float>, rot: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])) {
        let h = size / 2
        func p(_ x: Float, _ y: Float, _ z: Float) -> SIMD3<Float> { center + rot.act(SIMD3(x * h.x, y * h.y, z * h.z)) }
        let faces: [(SIMD3<Float>, [SIMD3<Float>])] = [
            ([1, 0, 0], [[1, -1, -1], [1, -1, 1], [1, 1, 1], [1, 1, -1]]),
            ([-1, 0, 0], [[-1, -1, 1], [-1, -1, -1], [-1, 1, -1], [-1, 1, 1]]),
            ([0, 1, 0], [[-1, 1, -1], [1, 1, -1], [1, 1, 1], [-1, 1, 1]]),
            ([0, -1, 0], [[-1, -1, 1], [1, -1, 1], [1, -1, -1], [-1, -1, -1]]),
            ([0, 0, 1], [[-1, -1, 1], [1, -1, 1], [1, 1, 1], [-1, 1, 1]]),
            ([0, 0, -1], [[1, -1, -1], [-1, -1, -1], [-1, 1, -1], [1, 1, -1]]),
        ]
        for (n, c) in faces {
            let q = c.map { p($0.x, $0.y, $0.z) }
            let w = simd_distance(q[0], q[1]), hgt = simd_distance(q[1], q[2])
            quad(q[0], q[1], q[2], q[3], uv: ([0, 0], [w, 0], [w, hgt], [0, hgt]), outward: rot.act(n))
        }
    }

    /// A box narrower at the top than the bottom: a car's cabin. `bottom` and `top` are width and length.
    mutating func taper(_ center: SIMD3<Float>, bottom: SIMD2<Float>, top: SIMD2<Float>, height: Float, topShift: Float = 0) {
        let y0 = center.y, y1 = center.y + height
        let b = [SIMD3(-bottom.x / 2, y0, -bottom.y / 2), SIMD3(bottom.x / 2, y0, -bottom.y / 2),
                 SIMD3(bottom.x / 2, y0, bottom.y / 2), SIMD3(-bottom.x / 2, y0, bottom.y / 2)].map { $0 + SIMD3(center.x, 0, center.z) }
        let t = [SIMD3(-top.x / 2, y1, -top.y / 2 + topShift), SIMD3(top.x / 2, y1, -top.y / 2 + topShift),
                 SIMD3(top.x / 2, y1, top.y / 2 + topShift), SIMD3(-top.x / 2, y1, top.y / 2 + topShift)].map { $0 + SIMD3(center.x, 0, center.z) }
        let mid = SIMD3(center.x, y0 + height / 2, center.z)
        for k in 0..<4 {
            let a = b[k], c = b[(k + 1) % 4], d = t[(k + 1) % 4], e = t[k]
            quad(a, c, d, e, outward: (a + c + d + e) / 4 - mid)
        }
        quad(t[0], t[1], t[2], t[3], outward: [0, 1, 0])
    }

    /// A wheel: a cylinder along x.
    mutating func wheel(_ center: SIMD3<Float>, radius: Float, width: Float, segments: Int = 12) {
        var ring: [SIMD2<Float>] = []
        for i in 0..<segments { let a = Float(i) / Float(segments) * 2 * .pi; ring.append(SIMD2(cos(a), sin(a)) * radius) }
        let hx = width / 2
        for i in 0..<segments {
            let p = ring[i], q = ring[(i + 1) % segments]
            let a = center + SIMD3(-hx, p.x, p.y), b = center + SIMD3(hx, p.x, p.y)
            let c = center + SIMD3(hx, q.x, q.y), d = center + SIMD3(-hx, q.x, q.y)
            let mid = (p + q) / 2
            quad(a, b, c, d, outward: [0, mid.x, mid.y])
            tri(center + [hx, 0, 0], b, c, outward: [1, 0, 0])
            tri(center + [-hx, 0, 0], a, d, outward: [-1, 0, 0])
        }
    }

    /// A rounded lump: a sphere with few faces, squashed by `scale`.
    mutating func blob(_ center: SIMD3<Float>, radius: Float, scale: SIMD3<Float> = [1, 1, 1], segments: Int = 8, rings: Int = 5) {
        func p(_ i: Int, _ j: Int) -> SIMD3<Float> {
            let th = Float(j) / Float(rings) * .pi, ph = Float(i) / Float(segments) * 2 * .pi
            return SIMD3(sin(th) * cos(ph), cos(th), sin(th) * sin(ph)) * radius * scale
        }
        for j in 0..<rings {
            for i in 0..<segments {
                let a = p(i, j), b = p(i + 1, j), c = p(i + 1, j + 1), d = p(i, j + 1)
                let mid = (a + b + c + d) / 4
                if j == 0 { tri(center + a, center + c, center + d, outward: mid) }
                else if j == rings - 1 { tri(center + a, center + b, center + c, outward: mid) }
                else { quad(center + a, center + b, center + c, center + d, outward: mid) }
            }
        }
    }

    /// A vertical cylinder standing on `base`.
    mutating func post(_ base: SIMD3<Float>, radius: Float, height: Float, segments: Int = 8) {
        for i in 0..<segments {
            let a0 = Float(i) / Float(segments) * 2 * .pi, a1 = Float(i + 1) / Float(segments) * 2 * .pi
            let p = SIMD3(cos(a0) * radius, 0, sin(a0) * radius), q = SIMD3(cos(a1) * radius, 0, sin(a1) * radius)
            quad(base + p, base + q, base + q + [0, height, 0], base + p + [0, height, 0], outward: (p + q) / 2)
            tri(base + [0, height, 0], base + p + [0, height, 0], base + q + [0, height, 0], outward: [0, 1, 0])
        }
    }

    /// Another kit's triangles added to this one.
    mutating func append(_ other: MeshKit) {
        let base = UInt32(pos.count)
        pos += other.pos; nor += other.nor; uv += other.uv
        idx += other.idx.map { $0 + base }
    }

    func mesh() -> MeshResource? {
        guard !idx.isEmpty else { return nil }
        var d = MeshDescriptor()
        d.positions = MeshBuffers.Positions(pos)
        d.normals = MeshBuffers.Normals(nor)
        d.textureCoordinates = MeshBuffers.TextureCoordinates(uv)
        d.primitives = .triangles(idx)
        return try? MeshResource.generate(from: [d])
    }
}

// MARK: - Cars

enum CarStyle: Int, CaseIterable {
    case sedan, suv, hatch, sports, pickup, van, taxi, police, ambulance, boxTruck, bus
    case bulldozer, excavator, dumpTruck, cementMixer, fireTruck, garbageTruck, monsterTruck, limo, golfCart, iceCream, supercar
}

@MainActor
enum CarFactory {
    static let colors: [NSColor] = [
        NSColor(red: 0.85, green: 0.86, blue: 0.88, alpha: 1), NSColor(white: 0.1, alpha: 1), NSColor(white: 0.5, alpha: 1),
        NSColor(red: 0.6, green: 0.08, blue: 0.08, alpha: 1), NSColor(red: 0.1, green: 0.2, blue: 0.45, alpha: 1),
        NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1), NSColor(red: 0.25, green: 0.3, blue: 0.25, alpha: 1),
        NSColor(red: 0.55, green: 0.5, blue: 0.42, alpha: 1), NSColor(red: 0.2, green: 0.45, blue: 0.7, alpha: 1),
        NSColor(red: 0.75, green: 0.35, blue: 0.1, alpha: 1), NSColor(white: 0.3, alpha: 1),
    ]
    static let blue = NSColor(red: 0, green: 0.15, blue: 0.3, alpha: 1)

    private static var meshes: [CarStyle: [MeshResource?]] = [:]
    private static var paints: [NSColor: PhysicallyBasedMaterial] = [:]
    static let glass: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(red: 0.08, green: 0.1, blue: 0.13, alpha: 1))
        m.roughness = .init(floatLiteral: 0.05); m.metallic = .init(floatLiteral: 0.4); m.specular = .init(floatLiteral: 1)
        return m
    }()
    static let dark = LampMaterial.rubber(NSColor(white: 0.07, alpha: 1))
    static let headlight = LampMaterial.glow(NSColor(red: 1, green: 0.97, blue: 0.85, alpha: 1), strength: 1.5)
    static let taillight = LampMaterial.glow(NSColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1), strength: 1.2)
    static let brakeLight = LampMaterial.glow(NSColor(red: 1, green: 0.1, blue: 0.05, alpha: 1), strength: 5)

    /// Length and width of each style, metres.
    static func size(_ style: CarStyle) -> SIMD2<Float> {
        switch style {
        case .sedan, .taxi, .police: [4.6, 1.85]
        case .suv: [4.8, 1.95]
        case .hatch: [4.1, 1.8]
        case .sports: [4.4, 1.95]
        case .pickup: [5.6, 2.0]
        case .van: [5.0, 2.0]
        case .ambulance: [6.6, 2.3]
        case .boxTruck: [7.5, 2.4]
        case .bus: [12, 2.55]
        case .bulldozer: [5.2, 3.0]
        case .excavator: [6.4, 2.8]
        case .dumpTruck: [8, 2.6]
        case .cementMixer: [8.2, 2.5]
        case .fireTruck: [9.6, 2.5]
        case .garbageTruck: [8.6, 2.5]
        case .monsterTruck: [5.4, 3.0]
        case .limo: [8, 1.95]
        case .golfCart: [2.5, 1.25]
        case .iceCream: [5.6, 2.1]
        case .supercar: [4.6, 2.05]
        }
    }

    private static func parts(_ style: CarStyle) -> [MeshResource?] {
        if let m = meshes[style] { return m }
        let s = size(style)
        let L = s.x, W = s.y
        let bodyTop: Float = style == .suv ? 1.15 : 0.95
        let cabH: Float = style == .suv ? 0.62 : 0.5
        var paint = MeshKit(), glass = MeshKit(), dark = MeshKit(), front = MeshKit(), rear = MeshKit()
        paint.box([0, (0.32 + bodyTop) / 2, 0], [W, bodyTop - 0.32, L - 0.3])
        // Rounded-off nose and tail.
        paint.box([0, (0.36 + bodyTop - 0.06) / 2, -(L / 2 - 0.2)], [W - 0.1, bodyTop - 0.42, 0.3])
        paint.box([0, (0.36 + bodyTop - 0.04) / 2, L / 2 - 0.2], [W - 0.1, bodyTop - 0.4, 0.3])
        let cabLen: Float = style == .sedan ? 2.5 : (style == .suv ? 3.1 : 2.4)
        let cabZ: Float = style == .sedan ? 0.25 : (style == .suv ? 0.45 : 0.45)
        glass.taper([0, bodyTop, cabZ], bottom: [W - 0.12, cabLen], top: [W - 0.32, cabLen - (style == .suv ? 0.5 : 0.9)],
                    height: cabH, topShift: style == .suv ? 0.15 : 0.1)
        paint.box([0, bodyTop + cabH + 0.03, cabZ + (style == .suv ? 0.15 : 0.1)], [W - 0.3, 0.06, cabLen - (style == .suv ? 0.55 : 0.95)])
        // Pillars between the windows.
        paint.box([W / 2 - 0.12, bodyTop + cabH / 2, cabZ + 0.05], [0.06, cabH, 0.12])
        paint.box([-(W / 2 - 0.12), bodyTop + cabH / 2, cabZ + 0.05], [0.06, cabH, 0.12])
        dark.box([0, 0.45, -L / 2 + 0.02], [W - 0.05, 0.22, 0.12])
        dark.box([0, 0.45, L / 2 - 0.02], [W - 0.05, 0.22, 0.12])
        dark.box([0, 0.3, 0], [W - 0.2, 0.1, L - 0.6])
        let r: Float = style == .suv ? 0.38 : 0.33
        let axle = L / 2 - (style == .hatch ? 0.75 : 0.95)
        for x in [-W / 2 + 0.1, W / 2 - 0.1] { for z in [-axle, axle] { dark.wheel([x, r, z], radius: r, width: 0.26) } }
        front.box([W / 2 - 0.3, bodyTop - 0.18, -L / 2 - 0.01], [0.38, 0.14, 0.04])
        front.box([-(W / 2 - 0.3), bodyTop - 0.18, -L / 2 - 0.01], [0.38, 0.14, 0.04])
        rear.box([W / 2 - 0.25, bodyTop - 0.16, L / 2 + 0.01], [0.32, 0.14, 0.04])
        rear.box([-(W / 2 - 0.25), bodyTop - 0.16, L / 2 + 0.01], [0.32, 0.14, 0.04])
        let m = [paint.mesh(), glass.mesh(), dark.mesh(), front.mesh(), rear.mesh()]
        meshes[style] = m
        return m
    }

    static func paint(_ color: NSColor) -> PhysicallyBasedMaterial {
        if let m = paints[color] { return m }
        let m = LampMaterial.paint(color)
        paints[color] = m
        return m
    }

    /// A car facing -z, standing at its origin. The rear lights are the child named "rear".
    static func make(_ style: CarStyle, color: NSColor, stripe: Bool = false) -> Entity {
        let base: CarStyle = style == .taxi || style == .police ? .sedan : style
        guard [.sedan, .suv, .hatch].contains(base) else { return VehicleModels.make(style, color: color) }
        let p = parts(base)
        let root = Entity()
        let mats: [RealityKit.Material] = [paint(color), glass, dark, headlight, taillight]
        let names = ["body", "glass", "dark", "front", "rear"]
        for (i, mesh) in p.enumerated() {
            guard let mesh else { continue }
            let e = ModelEntity(mesh: mesh, materials: [mats[i]])
            e.name = names[i]
            root.addChild(e)
        }
        if stripe {
            let L = size(style).x
            var s = MeshKit()
            s.box([0.18, 0.955, -0.6], [0.16, 0.012, L - 1.8])
            s.box([-0.18, 0.955, -0.6], [0.16, 0.012, L - 1.8])
            s.box([0.18, 1.483, 0.35], [0.16, 0.012, 1.5])
            s.box([-0.18, 1.483, 0.35], [0.16, 0.012, 1.5])
            if let m = s.mesh() { root.addChild(ModelEntity(mesh: m, materials: [paint(blue)])) }
        }
        VehicleModels.addExtras(style, to: root)
        return root
    }
}

// MARK: - Trees

@MainActor
enum TreeFactory {
    /// Each tree's model and the stump, made once and shared by every square's copies.
    private static var models: [Int: Entity] = [:]
    static func model(_ variant: Int) -> Entity {
        if let m = models[variant] { return m }
        let m = variant < 0 ? stump() : make(variant)
        models[variant] = m
        return m
    }

    /// What's left when a tree is knocked down: a short trunk with a pale, splintered top.
    static func stump() -> Entity {
        var trunk = MeshKit(), top = MeshKit()
        trunk.post([0, 0, 0], radius: 0.21, height: 0.5, segments: 6)
        top.post([0, 0.5, 0], radius: 0.17, height: 0.04, segments: 6)
        top.post([0.06, 0.5, 0.02], radius: 0.06, height: 0.22, segments: 4)
        let root = Entity()
        if let m = trunk.mesh() { root.addChild(ModelEntity(mesh: m, materials: [LampMaterial.wood(NSColor(red: 0.35, green: 0.25, blue: 0.17, alpha: 1))])) }
        if let m = top.mesh() { root.addChild(ModelEntity(mesh: m, materials: [LampMaterial.wood(NSColor(red: 0.82, green: 0.7, blue: 0.5, alpha: 1))])) }
        return root
    }

    static func make(_ variant: Int) -> Entity {
        var trunk = MeshKit(), leaves = MeshKit()
        trunk.post([0, 0, 0], radius: 0.2, height: 3.2, segments: 6)
        if variant == 0 {
            leaves.blob([0, 4.4, 0], radius: 2.3, scale: [1, 0.85, 1])
            leaves.blob([0.7, 5.6, 0.3], radius: 1.5)
            leaves.blob([-0.8, 4.9, -0.4], radius: 1.6)
        } else {
            leaves.blob([0, 4.0, 0], radius: 2.0, scale: [1, 1.1, 1])
            leaves.blob([0, 5.6, 0], radius: 1.4)
        }
        let root = Entity()
        if let m = trunk.mesh() { root.addChild(ModelEntity(mesh: m, materials: [LampMaterial.wood(NSColor(red: 0.35, green: 0.25, blue: 0.17, alpha: 1))])) }
        let green = variant == 0 ? NSColor(red: 0.24, green: 0.42, blue: 0.16, alpha: 1) : NSColor(red: 0.18, green: 0.36, blue: 0.14, alpha: 1)
        var leaf = PhysicallyBasedMaterial()
        leaf.baseColor = .init(tint: green, texture: .init(LampTexture.cached(LampTexture.speckle) { LampTexture.named(LampTexture.speckle) }, sampler: LampTexture.sampler))
        leaf.roughness = .init(floatLiteral: 0.9)
        if let m = leaves.mesh() { root.addChild(ModelEntity(mesh: m, materials: [leaf])) }
        return root
    }
}
