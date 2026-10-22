import SwiftUI
import RealityKit

/// The lamps of one traffic signal, grouped by which roads they face: one entity per colour per group.
struct SignalLamps {
    var lamps: [[[ModelEntity]]] = [[[], [], []], [[], [], []]]   // group, then red, yellow, green; one per pole
    var shown: [Int] = [-1, -1]
}

/// A piece of the city to build: indices into the road graph, and the things standing in it.
struct CityPart {
    var edges: [Int] = []
    var nodes: [Int] = []
    var buildings: [BuildingData] = []
    var grass: [AreaData] = []
    var lots: [AreaData] = []
    var paths: [PathData] = []
    var shops: [ShopData] = []
    var trees: [[Float]] = []
    var furniture: [[Float]] = []
    var wires: [[Float]] = []
    var fuel: [FuelData] = []
}

/// Turns a square's worked-out geometry (`CityGeometry`, done off the main thread) into entities with the
/// city's shared materials: buildings, roads, signs, signals and trees. Also the lawn under everything.
@MainActor
final class CityBuilder {
    let city: City
    /// Made once and shared by every square.
    private static var materials: [String: RealityKit.Material] = [:]
    /// Sign atlases' textures, kept by what's on them: a square drawn again reuses its texture.
    private static var atlasTextures: [UInt64: TextureResource] = [:]

    /// The street signs and signal poles drawn, each its own entity, by spot.
    var pieces: [SIMD2<Int32>: Entity] = [:]

    init(city: City) {
        self.city = city
        if Self.materials.isEmpty { Self.setupMaterials() }
    }

    /// Forgets the shared materials, made again for the next place (its signs' colours, its time of day).
    static func forgetMaterials() { materials = [:] }

    /// Forgets the textures made for sign lettering (a city loaded afresh starts over).
    static func forgetAtlases() {
        atlasTextures = [:]
        TextAtlas.forgetTextures()
    }

    /// The bundled downtown, as a part to share out among streamed squares.
    func downtown() -> CityPart {
        CityPart(edges: Array(city.edges.indices), nodes: Array(city.nodes.indices), buildings: city.file.buildings,
                 grass: city.file.grass, lots: city.file.lots, paths: city.file.paths, shops: city.file.shops, trees: city.file.trees,
                 furniture: city.file.furn ?? [], wires: city.file.wires ?? [], fuel: city.file.fuel ?? [])
    }

    /// The lawn under everything, made once.
    func buildGround(into root: Entity) {
        ground(root)
    }

    /// One square's entities from its plan: a mesh per material and 300 m chunk, each sign and signal pole its own
    /// entity (with its lamps, for the signals), the poles' collisions, and the trees.
    func make(_ plan: SquarePlan, into root: Entity, signals: inout [Int: SignalLamps]) {
        var materials = Self.materials
        if let key = plan.atlasKey {
            var texture = Self.atlasTextures[key]
            if texture == nil, let image = plan.atlasImage {
                texture = try? TextureResource.generate(from: image, options: .init(semantic: .color))
                if let texture { Self.atlasTextures[key] = texture; TextAtlas.noteTexture(key) }
            }
            if let texture {
                var m = PhysicallyBasedMaterial()
                m.baseColor = .init(tint: .white, texture: .init(texture, sampler: LampTexture.sampler))
                m.roughness = .init(floatLiteral: 0.45)
                materials["atlas"] = m
            }
        }
        for b in plan.batches {
            guard let material = materials[b.material] ?? Self.tinted(b.material), let mesh = LampMesh.make([b.mesh]) else { continue }
            let e = ModelEntity(mesh: mesh, materials: [material])
            e.name = b.name
            root.addChild(e)
        }
        for n in plan.signalNodes { signals[n] = SignalLamps() }
        for p in plan.pieces {
            let e = Entity()
            for m in p.meshes {
                guard let material = materials[m.material] ?? Self.tinted(m.material), let mesh = LampMesh.make([m.mesh]) else { continue }
                e.addChild(ModelEntity(mesh: mesh, materials: [material]))
            }
            if let l = p.lamps {
                for c in 0..<min(3, l.meshes.count) {
                    guard let mesh = LampMesh.make([l.meshes[c]]) else { continue }
                    let lamp = ModelEntity(mesh: mesh, materials: [Traffic.lampOff])
                    e.addChild(lamp)
                    signals[l.node, default: SignalLamps()].lamps[l.group][c].append(lamp)
                }
            }
            root.addChild(e)
            pieces[p.spot] = e
        }
        for post in plan.posts { city.addPost(post.c, post.r, kind: post.kind) }
        // Street furniture: one batch of copies per kind, each standing on whatever is under it.
        var byKind: [Furniture.Kind: [Transform]] = [:]
        for f in plan.furniture {
            guard let k = Furniture.Kind(rawValue: Int(f[0])) else { continue }
            let p = SIMD2(f[1], f[2])
            byKind[k, default: []].append(Transform(rotation: simd_quatf(angle: -f[3], axis: [0, 1, 0]), translation: w3(p, city.surface(p))))
            let r = Furniture.postRadius(k)
            if r > 0 { city.addPost(p, r, kind: k == .hydrant ? 3 : (k == .lamp ? 4 : 0)) }
        }
        byKind[.hydrant] = nil
        byKind[.lamp] = nil
        for (k, ts) in byKind { root.addChild(LampScene.copies(of: Furniture.model(k), at: ts)) }
        // Hydrants and lamps on their own, so one knocked off or over can be taken out.
        let hydrants = Entity()
        hydrants.name = "hydrants"
        Self.fillHydrants(hydrants, plan.furniture, city: city)
        root.addChild(hydrants)
        let holder = Entity()
        holder.name = "trees"
        Self.fillTrees(holder, plan.trees, fallen: city.fallen)
        root.addChild(holder)
    }

    // MARK: Materials

    /// A material in a building's tagged colour ("f3~c84", see CityGeometry.tinted): the same surface as the
    /// untinted one, its wall colour taken out of the texture and the tagged colour put on. Made once per colour.
    private static func tinted(_ key: String) -> RealityKit.Material? {
        let bits = key.split(separator: "~")
        guard bits.count == 2, bits[1].count == 3 else { return nil }
        let rgb = bits[1].map { CGFloat(Int(String($0), radix: 16) ?? 8) / 15 }
        let colour = NSColor(red: rgb[0], green: rgb[1], blue: rgb[2], alpha: 1)
        let base = String(bits[0])
        var m: PhysicallyBasedMaterial
        if base.hasPrefix("f"), let c = Int(base.dropFirst().split(separator: "w").first ?? "") {
            let w = base.contains("w") ? Int(base.split(separator: "w").last ?? "") ?? 0 : 0
            m = facadeMaterial(c, neutral: true, pattern: w)
        } else if base.hasPrefix("p"), let c = Int(base.dropFirst()) {
            m = textured("plain-n-\(c)", rough: 0.88) { Self.facade(c, plain: true, neutral: true) }
        } else if base.hasPrefix("sh"), let r = Int(base.dropFirst(2)) {
            m = textured("shingle-n-\(r)", rough: 0.9) { Self.shingles(r, neutral: true) }
        } else if base == "roof" {
            m = LampMaterial.concrete(colour, repeat: 0.3)
            materials[key] = m
            return m
        } else if base == "paint" {
            m = flat(colour, rough: 0.35)
            materials[key] = m
            return m
        } else if base == "copper" {
            m = LampMaterial.metal(colour, rough: 0.6)
            materials[key] = m
            return m
        } else {
            return nil
        }
        m.baseColor.tint = colour
        materials[key] = m
        return m
    }

    private static func flat(_ color: NSColor, rough: Float = 0.8) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: color)
        m.roughness = .init(floatLiteral: rough)
        return m
    }

    private static func textured(_ name: String, rough: Float = 0.85, metal: Float = 0, _ image: () -> CGImage) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: .white, texture: .init(LampTexture.cached(name, image), sampler: LampTexture.sampler))
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    /// A facade with windows (at night, CityGeometry adds glowing panes over the lit ones).
    private static func facadeMaterial(_ c: Int, neutral: Bool, pattern: Int = 0) -> PhysicallyBasedMaterial {
        let glassy = c == 3
        let name = (neutral ? "facade-n-\(c)" : "facade-v2-\(c)") + (pattern > 0 ? "-w\(pattern)" : "")
        return textured(name, rough: glassy ? 0.25 : 0.88, metal: glassy ? 0.3 : 0) { Self.facade(c, neutral: neutral, pattern: pattern) }
    }

    private static func setupMaterials() {
        materials["asphalt"] = LampMaterial.asphalt(repeat: 0.25)
        materials["sidewalk"] = LampMaterial.concrete(NSColor(white: 0.74, alpha: 1), repeat: 0.4)
        materials["path"] = LampMaterial.concrete(NSColor(red: 0.72, green: 0.7, blue: 0.66, alpha: 1), repeat: 0.4)
        materials["lot"] = LampMaterial.concrete(NSColor(white: 0.38, alpha: 1), repeat: 0.3)
        var park = LampMaterial.grass(repeat: 0.15)
        park.baseColor.tint = NSColor(red: 0.3, green: 0.52, blue: 0.2, alpha: 1)
        materials["park"] = park
        // Golf: fairways mown in broad light and dark stripes, close-cut greens and tees, sand traps, longer rough.
        var fairway = textured("fairway", rough: 0.9) {
            LampTexture.draw(64, 8) { u, _ in u < 0.5 ? SIMD4(0.36, 0.6, 0.24, 1) : SIMD4(0.31, 0.53, 0.2, 1) }
        }
        fairway.textureCoordinateTransform = .init(scale: [1 / 16, 1 / 16], rotation: 0.6)
        materials["golf:fairway"] = fairway
        materials["golf:green"] = flat(NSColor(red: 0.33, green: 0.62, blue: 0.24, alpha: 1), rough: 0.75)
        materials["golf:bunker"] = LampMaterial.concrete(NSColor(red: 0.88, green: 0.8, blue: 0.6, alpha: 1), repeat: 0.5)
        var rough = LampMaterial.grass(repeat: 0.15)
        rough.baseColor.tint = NSColor(red: 0.24, green: 0.42, blue: 0.16, alpha: 1)
        materials["golf:rough"] = rough
        var lawn = LampMaterial.grass(repeat: 0.12)
        lawn.baseColor.tint = NSColor(red: 0.36, green: 0.5, blue: 0.24, alpha: 1)
        materials["lawn"] = lawn
        materials["white"] = flat(NSColor(white: 0.93, alpha: 1), rough: 0.6)
        materials["yellow"] = flat(NSColor(red: 0.98, green: 0.78, blue: 0.1, alpha: 1), rough: 0.6)
        materials["roof"] = LampMaterial.concrete(NSColor(white: 0.42, alpha: 1), repeat: 0.3)
        materials["pole"] = LampMaterial.metal(NSColor(white: 0.45, alpha: 1), rough: 0.5)
        materials["signal"] = flat(NSColor(red: 0.12, green: 0.12, blue: 0.1, alpha: 1), rough: 0.5)
        let sign = CityConfig.current.style.signColour
        materials["blade"] = flat(NSColor(red: CGFloat(sign.x), green: CGFloat(sign.y), blue: CGFloat(sign.z), alpha: 1), rough: 0.4)
        materials["text"] = flat(.white, rough: 0.4)
        materials["gold"] = LampMaterial.metal(NSColor(red: 0.95, green: 0.78, blue: 0.4, alpha: 1), rough: 0.3)
        for (i, c) in CityGeometry.plaques.enumerated() { materials["plaque\(i)"] = flat(c, rough: 0.45) }
        for c in 0...10 {
            materials["f\(c)"] = facadeMaterial(c, neutral: false)
            if !(4...8).contains(c) && c != 3 {
                for w in 1...3 { materials["f\(c)w\(w)"] = facadeMaterial(c, neutral: false, pattern: w) }
            }
            materials["p\(c)"] = textured("plain\(c)", rough: 0.88) { Self.facade(c, plain: true) }
        }
        for c in [0, 1, 2, 9, 10] {
            materials["s\(c)"] = textured("store\(c)", rough: 0.5) { Self.storefront(c) }
        }
        materials["copper"] = LampMaterial.metal(NSColor(red: 0.38, green: 0.6, blue: 0.5, alpha: 1), rough: 0.6)
        var wood = LampMaterial.grass(repeat: 0.1)
        wood.baseColor.tint = NSColor(red: 0.2, green: 0.36, blue: 0.16, alpha: 1)
        materials["wood"] = wood
        var water = PhysicallyBasedMaterial()
        water.baseColor = .init(tint: NSColor(red: 0.2, green: 0.36, blue: 0.48, alpha: 1))
        water.roughness = .init(floatLiteral: 0.12)
        water.metallic = .init(floatLiteral: 0.2)
        materials["water"] = water
        materials["kerb"] = LampMaterial.concrete(NSColor(white: 0.66, alpha: 1), repeat: 0.5)
        materials["paved"] = LampMaterial.concrete(NSColor(white: 0.6, alpha: 1), repeat: 0.3)
        materials["walk"] = LampMaterial.concrete(NSColor(white: 0.72, alpha: 1), repeat: 0.5)
        var verge = LampMaterial.grass(repeat: 0.3)
        verge.baseColor.tint = NSColor(red: 0.34, green: 0.5, blue: 0.22, alpha: 1)
        materials["verge"] = verge
        materials["door"] = LampMaterial.paint(NSColor(red: 0.32, green: 0.16, blue: 0.1, alpha: 1))
        materials["wire"] = LampMaterial.plastic(NSColor(white: 0.08, alpha: 1), gloss: 0.2)
        materials["canopy"] = DayTime.lightsOn ? LampMaterial.glow(NSColor(white: 0.95, alpha: 1), strength: 0.9) : flat(NSColor(white: 0.92, alpha: 1), rough: 0.5)
        materials["pump"] = flat(NSColor(white: 0.88, alpha: 1), rough: 0.4)
        materials["drive"] = LampMaterial.asphalt(repeat: 0.3)
        materials["court"] = flat(NSColor(red: 0.2, green: 0.45, blue: 0.32, alpha: 1), rough: 0.7)
        materials["courtTan"] = flat(NSColor(red: 0.62, green: 0.45, blue: 0.3, alpha: 1), rough: 0.7)
        materials["track"] = flat(NSColor(red: 0.62, green: 0.25, blue: 0.2, alpha: 1), rough: 0.85)
        materials["seats"] = textured("seats", rough: 0.6) {
            // Rows of benches on concrete steps: a bright bench, its shadowed riser, the tread.
            LampTexture.draw(8, 64) { _, v in
                let f = v
                let g: SIMD3<Float> = f < 0.3 ? [0.7, 0.72, 0.74] : (f < 0.45 ? [0.5, 0.51, 0.52] : [0.6, 0.59, 0.57])
                return SIMD4(g.x, g.y, g.z, 1)
            }
        }
        materials["woodchip"] = LampMaterial.concrete(NSColor(red: 0.55, green: 0.4, blue: 0.27, alpha: 1), repeat: 0.6)
        materials["drivecon"] = LampMaterial.concrete(NSColor(white: 0.66, alpha: 1), repeat: 0.4)
        materials["garagedoor"] = textured("garagedoor", rough: 0.5) {
            // Horizontal panels: four bands with dark joints between, faint panel lines across.
            LampTexture.draw(64, 64) { u, v in
                let joint = abs((v * 2).truncatingRemainder(dividingBy: 1)) < 0.05
                let seam = abs((u * 1.6).truncatingRemainder(dividingBy: 1)) < 0.02
                let g: Float = joint ? 0.62 : (seam ? 0.86 : 0.93)
                return SIMD4(g, g, g * 0.98, 1)
            }
        }
        materials["winglow"] = LampMaterial.glow(NSColor(red: 1, green: 0.78, blue: 0.48, alpha: 1), strength: 0.9)
        for r in 0...2 { materials["sh\(r)"] = textured("shingle\(r)", rough: 0.9) { Self.shingles(r) } }
    }

    // MARK: Textures

    nonisolated private static func noise(_ x: Int, _ y: Int, _ seed: Int) -> Float {
        var h = UInt32(truncatingIfNeeded: x &* 374761393 &+ y &* 668265263 &+ seed &* 1442695041)
        h = (h ^ (h >> 13)) &* 1274126177
        return Float(h & 0xffff) / 65535
    }

    /// One bay of a facade, one storey high, with its window.
    /// `neutral`: the wall left near white, to be tinted to a building's tagged colour.
    /// `night`: four bays by four storeys, a different set of windows lit in each (buildings start at different
    /// places in it, so no two look alike); `glow`: just the lit windows, for the night material's glow.
    nonisolated static func facade(_ c: Int, plain: Bool = false, neutral: Bool = false, night: Bool = false, glow: Bool = false, pattern: Int = 0) -> CGImage {
        let walls: [SIMD3<Float>] = [[0.55, 0.26, 0.19], [0.76, 0.64, 0.47], [0.78, 0.76, 0.7], [0.3, 0.4, 0.5],
                                     [0.92, 0.92, 0.89], [0.58, 0.68, 0.78], [0.9, 0.82, 0.52], [0.58, 0.66, 0.52],
                                     [0.6, 0.6, 0.62], [0.36, 0.22, 0.17], [0.87, 0.8, 0.68]]
        let wall = neutral ? SIMD3<Float>(0.92, 0.92, 0.92) : walls[c]
        let house = (4...8).contains(c)
        let brick = c == 0 || c == 1 || c == 9
        let n = 128
        let cells = night ? 4 : 1
        return LampTexture.draw(n * cells, n * cells) { u0, v0 in
            let cu = min(cells - 1, Int(u0 * Float(cells))), cv = min(cells - 1, Int(v0 * Float(cells)))
            let u = u0 * Float(cells) - Float(cu), v = v0 * Float(cells) - Float(cv)
            let litHere = night ? noise(cu * 7 + cv * 3, cv * 5 + cu, c + 40) > 0.62 : noise(c, 0, 5) > 0.7
            let px = Int(u * Float(n)), py = Int(v * Float(n))
            if glow {
                // Only the glass of the lit windows glows.
                let (x0, x1, y0, y1): (Float, Float, Float, Float) = c == 3 ? (0.03, 0.97, 0.04, 0.82) : ((4...8).contains(c) ? (0.37, 0.63, 0.24, 0.66) : (0.16, 0.84, 0.2, 0.74))
                if !plain && litHere && u > x0 && u < x1 && v > y0 && v < y1 { return SIMD4(1, 0.8, 0.5, 1) }
                return SIMD4(0, 0, 0, 1)
            }
            var col = wall * (0.94 + 0.08 * noise(px / 2, py / 2, c))
            if brick {
                let row = py / 5
                let off = row % 2 == 0 ? 0 : 6
                if py % 5 == 0 || (px + off) % 12 == 0 { col *= 0.8 }
                col *= 0.92 + 0.1 * noise(row, (px + off) / 12, c + 9)
            } else if house {
                if py % 10 == 0 { col *= 0.78 } else if py % 10 == 1 { col *= 1.03 }
            } else if c == 2 || c == 10 {
                if py % 32 == 0 || px % 64 == 0 { col *= 0.88 }
            }
            if c == 3 {
                // Curtain wall: glass with mullions and a spandrel band.
                let mull = px % 64 < 3 || py % 128 < 4
                let span = v > 0.82
                if mull { return SIMD4(0.7, 0.72, 0.75, 1) }
                if span { return SIMD4(0.22, 0.28, 0.34, 1) }
                if night && litHere { return SIMD4(0.75, 0.62, 0.42, 1) }
                let r = 0.25 + 0.25 * (1 - v) + 0.05 * noise(px / 32, 0, 3)
                return SIMD4(r * 0.7, r * 0.85, r, 1)
            }
            if plain { return SIMD4(col, 1) }
            // The window in this bay: one, a pair, a ribbon running bay to bay, or one narrow one.
            var (x0, x1, y0, y1): (Float, Float, Float, Float) = house ? (0.37, 0.63, 0.24, 0.66) : (0.16, 0.84, 0.2, 0.74)
            if !house {
                switch pattern {
                case 1: (x0, x1, y0, y1) = u < 0.5 ? (0.12, 0.42, 0.16, 0.78) : (0.58, 0.88, 0.16, 0.78)
                case 2: (x0, x1, y0, y1) = (-0.1, 1.1, 0.3, 0.68)
                    if v > y0 && v < y1 && (u < 0.012 || u > 0.988 || abs(u - 0.5) < 0.008) { return SIMD4(0.55, 0.56, 0.58, 1) }
                case 3: (x0, x1, y0, y1) = (0.36, 0.64, 0.14, 0.8)
                default: break
                }
            }
            let frame: Float = house ? 0.05 : 0.03
            if u > x0 - frame && u < x1 + frame && v > y0 - frame && v < y1 + frame + (house ? 0 : 0.03) {
                if u > x0 && u < x1 && v > y0 && v < y1 {
                    var g = SIMD3<Float>(0.13, 0.17, 0.22) + SIMD3(repeating: 0.2 * (1 - (v - y0) / (y1 - y0)))
                    if night { g = litHere ? SIMD3(0.85, 0.68, 0.45) : g * 0.5 }
                    else if litHere { g = g * 0.7 + SIMD3(0.25, 0.22, 0.15) }
                    if abs(u - (x0 + x1) / 2) < 0.012 || abs(v - (y0 + y1) / 2) < 0.012 && house { g = [0.9, 0.9, 0.88] }
                    return SIMD4(g, 1)
                }
                let trim: SIMD3<Float> = house ? [0.95, 0.95, 0.93] : (brick ? [0.75, 0.72, 0.66] : wall * 0.75)
                return SIMD4(trim, 1)
            }
            return SIMD4(col, 1)
        }
    }

    /// One shop window, the height of the ground floor: a sign band above, a low wall below.
    nonisolated static func storefront(_ c: Int) -> CGImage {
        let walls: [Int: SIMD3<Float>] = [0: [0.5, 0.24, 0.18], 1: [0.7, 0.6, 0.44], 2: [0.72, 0.7, 0.65], 9: [0.3, 0.2, 0.15], 10: [0.8, 0.74, 0.62]]
        let wall = walls[c] ?? [0.6, 0.6, 0.6]
        let n = 128
        return LampTexture.draw(n, n) { u, v in
            let px = Int(u * Float(n)), py = Int(v * Float(n))
            let col = wall * (0.94 + 0.08 * noise(px / 2, py / 2, c + 30))
            if v < 0.2 { return SIMD4(col * 0.55, 1) }                         // sign band
            if v > 0.88 { return SIMD4(col * 0.8, 1) }                         // low wall
            if u < 0.05 || u > 0.95 { return SIMD4(col, 1) }                   // piers
            if v < 0.23 || u < 0.075 || u > 0.925 || abs(u - 0.5) < 0.012 || abs(v - 0.34) < 0.01 {
                return SIMD4(0.12, 0.12, 0.12, 1)                              // frames
            }
            let shade = 0.16 + 0.22 * (1 - v) + 0.06 * noise(px / 16, py / 16, 4)
            return SIMD4(shade * 0.9, shade, shade * 1.05, 1)
        }
    }

    nonisolated static func shingles(_ r: Int, neutral: Bool = false) -> CGImage {
        let base: [SIMD3<Float>] = neutral ? [[0.85, 0.85, 0.85], [0.85, 0.85, 0.85], [0.85, 0.85, 0.85]] : [[0.24, 0.24, 0.26], [0.36, 0.27, 0.2], [0.3, 0.33, 0.38]]
        return LampTexture.draw(128, 128) { u, v in
            let px = Int(u * 128), py = Int(v * 128)
            let row = py / 16
            let off = row % 2 == 0 ? 0 : 10
            var c = base[r] * (0.85 + 0.25 * noise((px + off) / 20, row, r + 20))
            if py % 16 < 2 { c *= 0.6 }
            if (px + off) % 20 == 0 { c *= 0.75 }
            return SIMD4(c * (0.95 + 0.05 * noise(px, py, 2)), 1)
        }
    }

    // MARK: Ground and trees

    private func ground(_ root: Entity) {
        var kit = MeshKit()
        // One big lawn under everything, as far as the streamed city will ever reach.
        let h = SIMD2<Float>(12000, 12000)
        // Below the lowest land, for beyond the squares that are drawn.
        let y = Terrain.shared.lowest - 0.5
        let a = SIMD3<Float>(-h.x, y, h.y), b = SIMD3<Float>(h.x, y, h.y)
        let c = SIMD3<Float>(h.x, y, -h.y), d = SIMD3<Float>(-h.x, y, -h.y)
        kit.quad(a, b, c, d, uv: ([-h.x, -h.y], [h.x, -h.y], [h.x, h.y], [-h.x, h.y]), outward: [0, 1, 0])
        if let m = kit.mesh(), let mat = Self.materials["lawn"] { root.addChild(ModelEntity(mesh: m, materials: [mat])) }
    }

    /// A square's hydrants, with a broken pipe where one has been knocked off.
    static func fillHydrants(_ holder: Entity, _ furniture: [[Float]], city: City) {
        var standing: [Transform] = [], broken: [Transform] = [], lamps: [Transform] = []
        for f in furniture where Int(f[0]) == Furniture.Kind.hydrant.rawValue || Int(f[0]) == Furniture.Kind.lamp.rawValue {
            let p = SIMD2(f[1], f[2])
            let t = Transform(rotation: simd_quatf(angle: -f[3], axis: [0, 1, 0]), translation: w3(p, city.surface(p)))
            let down = city.fallen.contains(City.spot(p))
            if Int(f[0]) == Furniture.Kind.lamp.rawValue { if !down { lamps.append(t) }; continue }
            if down { broken.append(t) } else { standing.append(t) }
        }
        if !standing.isEmpty { holder.addChild(LampScene.copies(of: Furniture.model(.hydrant), at: standing)) }
        if !broken.isEmpty { holder.addChild(LampScene.copies(of: Furniture.brokenHydrant, at: broken)) }
        if !lamps.isEmpty { holder.addChild(LampScene.copies(of: Furniture.model(.lamp), at: lamps)) }
    }

    /// A square's trees, with a stump where one has been knocked down.
    static func fillTrees(_ holder: Entity, _ trees: [[Float]], fallen: Set<SIMD2<Int32>>) {
        var stumps: [Transform] = []
        for v in 0..<2 {
            var ts: [Transform] = []
            for (o, t) in trees.enumerated() where o % 2 == v && t.count > 2 {
                let s = t[2]
                let at = Transform(scale: [s, s, s], rotation: simd_quatf(angle: Float(o) * 1.7, axis: [0, 1, 0]),
                                   translation: w3(SIMD2(t[0], t[1]), Heights.ground))
                if fallen.contains(City.spot(SIMD2(t[0], t[1]))) { stumps.append(at) } else { ts.append(at) }
            }
            if !ts.isEmpty { holder.addChild(LampScene.copies(of: TreeFactory.model(v), at: ts)) }
        }
        if !stumps.isEmpty { holder.addChild(LampScene.copies(of: TreeFactory.model(-1), at: stumps)) }
    }
}
