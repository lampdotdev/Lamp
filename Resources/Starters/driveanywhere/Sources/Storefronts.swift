import SwiftUI
import RealityKit

/// The look of a shopfront, by what kind of business it is.
enum ShopLook {
    case cafe, restaurant, bar, pub, fastFood, bank, theatre, clothes, books, gifts, grocery, pharmacy, salon, garage, hotel, generic

    static func of(_ kind: String) -> ShopLook {
        switch kind {
        case "cafe", "coffee", "tea", "bakery", "pastry", "ice_cream", "confectionery", "deli": .cafe
        case "restaurant": .restaurant
        case "bar", "nightclub": .bar
        case "pub", "alcohol", "beverages": .pub
        case "fast_food": .fastFood
        case "bank", "library", "museum", "government": .bank
        case "theatre", "cinema": .theatre
        case "clothes", "shoes", "boutique", "fashion": .clothes
        case "books", "music", "musical_instrument", "antiques": .books
        case "jewelry", "rock", "optician", "cosmetics", "gift", "frame", "photo": .gifts
        case "convenience", "supermarket", "greengrocer", "marketplace", "florist", "garden_centre", "cannabis", "tobacco": .grocery
        case "pharmacy": .pharmacy
        case "hairdresser", "beauty", "massage", "piercing", "tattoo": .salon
        case "car_repair", "car_parts", "bicycle", "scooter": .garage
        case "hotel": .hotel
        default: .generic
        }
    }

    /// Whether it keeps the striped awning.
    var awning: Bool {
        switch self { case .cafe, .clothes, .books, .gifts, .grocery, .salon, .generic: true; default: false }
    }
}

/// A storefront material, described so a shopfront can be worked out off the main thread; made (once per
/// description, shared by every storefront) on the main thread.
struct ShopMat {
    let c: NSColor
    let rough: Float, metal: Float, glow: Float
    let clear: Float?

    @MainActor private static var made: [String: RealityKit.Material] = [:]

    @MainActor func material(_ key: String) -> RealityKit.Material {
        if let m = Self.made[key] { return m }
        let m: RealityKit.Material
        if let clear {
            m = LampMaterial.glass(c, clear: clear)
        } else {
            var pbr = PhysicallyBasedMaterial()
            pbr.baseColor = .init(tint: c)
            pbr.roughness = .init(floatLiteral: rough)
            pbr.metallic = .init(floatLiteral: metal)
            if glow > 0 { pbr.emissiveColor = .init(color: c); pbr.emissiveIntensity = glow }
            m = pbr
        }
        Self.made[key] = m
        return m
    }
}

/// Lettering on a storefront (a theatre's marquee), made into a mesh on the main thread and fitted to `maxWidth`.
struct ShopText {
    let text: String
    let maxWidth: Float
    let at: SIMD3<Float>
    let rot: simd_quatf

    @MainActor func entity() -> ModelEntity {
        let e = ModelEntity(mesh: LampMesh.text(text, size: 0.36, depth: 0.01, weight: .black),
                            materials: [LampMaterial.plastic(NSColor(red: 0.5, green: 0.0, blue: 0.05, alpha: 1))])
        let b = e.model!.mesh.bounds
        let s = min(1, maxWidth / max(0.1, b.extents.x))
        e.transform = Transform(scale: [s, s, 1], rotation: rot, translation: at + rot.act([-b.center.x * s, -b.center.y * s, 0]))
        return e
    }
}

/// Builds shopfronts in a business's own frame: u along the facade, y up from the ground, d out towards the street.
/// Plain geometry and material descriptions, so it runs on any thread.
struct ShopBuilder {
    var kits: [String: MeshKit] = [:]
    var mats: [String: ShopMat] = [:]
    var texts: [ShopText] = []
    private var o = SIMD2<Float>(0, 0), t = SIMD2<Float>(1, 0), n = SIMD2<Float>(0, 1)
    private var rot = simd_quatf(angle: 0, axis: [0, 1, 0])

    mutating func at(_ pos: SIMD2<Float>, out: SIMD2<Float>) {
        o = pos - out * 0.12        // back onto the wall
        n = out
        t = SIMD2(out.y, -out.x)
        rot = simd_quatf(angle: atan2(out.x, -out.y), axis: [0, 1, 0])
    }

    func p(_ u: Float, _ y: Float, _ d: Float) -> SIMD3<Float> { w3(o - t * u + n * d, y) }

    /// A material by name: described here, made once on the main thread.
    @discardableResult
    mutating func color(_ c: NSColor, rough: Float = 0.6, metal: Float = 0, glow: Float = 0, clear: Float? = nil) -> String {
        let rgb = c.usingColorSpace(.sRGB) ?? c
        let key = String(format: "c%.2f,%.2f,%.2f|%.2f|%.2f|%.2f|%@", rgb.redComponent, rgb.greenComponent, rgb.blueComponent,
                         rough, metal, glow, clear.map { String($0) } ?? "-")
        if mats[key] == nil { mats[key] = ShopMat(c: c, rough: rough, metal: metal, glow: glow, clear: clear) }
        return key
    }

    /// A box standing on `y`, centred on u, its front face at d + depth/2.
    mutating func box(_ m: String, _ u: Float, _ y: Float, _ d: Float, _ w: Float, _ h: Float, _ depth: Float, tilt: Float = 0) {
        let r = tilt == 0 ? rot : rot * simd_quatf(angle: tilt, axis: [1, 0, 0])
        kits[m, default: MeshKit()].box(p(u, y + h / 2, d), [w, h, depth], rot: r)
    }

    mutating func post(_ m: String, _ u: Float, _ d: Float, _ y: Float, _ r: Float, _ h: Float, segments: Int = 10) {
        kits[m, default: MeshKit()].post(p(u, y, d), radius: r, height: h, segments: segments)
    }

    mutating func blob(_ m: String, _ u: Float, _ y: Float, _ d: Float, _ r: Float, scale: SIMD3<Float> = [1, 1, 1]) {
        kits[m, default: MeshKit()].blob(p(u, y, d), radius: r, scale: scale, segments: 7, rings: 4)
    }

    /// The common shopfront: plinth, pilasters, fascia, glass with mullions, a door near one end.
    mutating func front(_ W: Float, _ H: Float, frame: String, glass: String, door: String, mullion: Float, transom: Bool,
                        d0: Float = 0, depth: Float = 0.16, plinth: Float = 0.45) -> Float {
        box(frame, 0, 0, d0, W, plinth, depth)
        for s: Float in [-1, 1] { box(frame, s * (W / 2 - 0.15), 0, d0, 0.3, H, depth) }
        box(frame, 0, H - 0.55, d0, W, 0.55, depth)
        box(glass, 0, plinth, d0 - 0.02, W - 0.6, H - 0.55 - plinth, 0.04)
        var x = -W / 2 + 0.3 + mullion
        while x < W / 2 - 0.4 { box(frame, x, plinth, d0, 0.06, H - 0.55 - plinth, depth * 0.7); x += mullion }
        if transom { box(frame, 0, H - 1.2, d0, W - 0.6, 0.07, depth * 0.7) }
        let ud = W > 3.2 ? -W / 2 + 1.05 : 0
        box(door, ud, 0, d0 + 0.01, 1.0, 2.35, depth + 0.02)
        box(glass, ud, 0.95, d0 + 0.03, 0.6, 1.15, depth)
        box(color(NSColor(white: 0.8, alpha: 1), rough: 0.2, metal: 1), ud + 0.35, 1.0, d0 + 0.05, 0.04, 0.3, depth + 0.04)
        if d0 > 0.2 {
            // The bay's sides and top, back to the wall.
            for s: Float in [-1, 1] { box(frame, s * (W / 2 - 0.15), 0, d0 / 2, 0.3, H, d0) }
            box(frame, 0, H - 0.1, d0 / 2, W, 0.1, d0 + 0.1)
            box(color(NSColor(red: 0.9, green: 0.85, blue: 0.75, alpha: 1), glow: 0.35), 0, plinth, 0.02, W - 0.6, H - 0.55 - plinth, 0.02)
        }
        return d0 + depth / 2
    }

    // MARK: Each kind

    /// Builds the shopfront and returns how far out its glass is, for the OPEN sign.
    mutating func build(_ look: ShopLook, name: String, width: Float, height: Float, style: BusinessStyle, seed: Int) -> Float {
        let W = max(3, width), H = height
        func pick(_ list: [NSColor]) -> NSColor { list[seed % list.count] }
        let darkGlass = color(NSColor(red: 0.1, green: 0.13, blue: 0.17, alpha: 1), rough: 0.05, metal: 0.5)
        let warmGlass = color(NSColor(red: 0.95, green: 0.62, blue: 0.3, alpha: 1), rough: 0.1, glow: 0.7)
        let coolGlass = color(NSColor(red: 0.85, green: 0.92, blue: 1, alpha: 1), rough: 0.1, glow: 0.6)
        let clearGlass = color(NSColor(red: 0.85, green: 0.92, blue: 0.95, alpha: 1), clear: 0.85)
        let wood = color(NSColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 1), rough: 0.8)
        let metal = color(NSColor(white: 0.18, alpha: 1), rough: 0.35, metal: 0.8)
        let brass = color(NSColor(red: 0.8, green: 0.65, blue: 0.3, alpha: 1), rough: 0.25, metal: 1)
        let leaf = color(NSColor(red: 0.2, green: 0.45, blue: 0.18, alpha: 1), rough: 0.9)
        let ud: Float = W > 3.2 ? -W / 2 + 1.05 : 0
        let accent = color(style.color, rough: 0.4)

        switch look {
        case .cafe:
            let frame = color(pick([NSColor(red: 0.1, green: 0.3, blue: 0.2, alpha: 1), NSColor(red: 0.1, green: 0.15, blue: 0.32, alpha: 1),
                                    NSColor(red: 0.9, green: 0.86, blue: 0.74, alpha: 1), NSColor(white: 0.1, alpha: 1)]), rough: 0.5)
            let f = front(W, H, frame: frame, glass: warmGlass, door: frame, mullion: 0.55, transom: true)
            // Window box with flowers, and a chalkboard on the sidewalk.
            box(wood, ud + 1.0 + (W - 2.6) / 2 - 0.6, 0.5, 0.3, max(1, W - 2.8), 0.25, 0.3)
            let flowers = [color(NSColor(red: 0.9, green: 0.2, blue: 0.3, alpha: 1)), color(NSColor(red: 1, green: 0.85, blue: 0.2, alpha: 1)),
                           color(NSColor(red: 0.95, green: 0.95, blue: 0.95, alpha: 1))]
            var u = ud + 0.9
            var k = 0
            while u < W / 2 - 0.5 { blob(k % 2 == 0 ? leaf : flowers[k % 3], u, 0.8, 0.3, 0.13); u += 0.28; k += 1 }
            let slate = color(NSColor(white: 0.12, alpha: 1), rough: 0.9)
            box(slate, ud, 0.12, 1.25, 0.6, 0.9, 0.04, tilt: 0.22)
            box(slate, ud, 0.12, 1.55, 0.6, 0.9, 0.04, tilt: -0.22)
            box(color(.white, rough: 0.9), ud, 0.55, 1.22, 0.4, 0.04, 0.05, tilt: 0.22)
            return f
        case .restaurant:
            let frame = color(pick([NSColor(red: 0.25, green: 0.15, blue: 0.1, alpha: 1), NSColor(red: 0.4, green: 0.08, blue: 0.08, alpha: 1),
                                    NSColor(red: 0.12, green: 0.12, blue: 0.14, alpha: 1)]), rough: 0.5)
            let f = front(W, H, frame: frame, glass: warmGlass, door: frame, mullion: 1.2, transom: false)
            // Lamps by the door, planters, and a flat canopy.
            let lamp = color(NSColor(red: 1, green: 0.8, blue: 0.5, alpha: 1), glow: 3)
            for s: Float in [-1, 1] {
                box(lamp, ud + s * 0.75, 2.25, 0.2, 0.14, 0.26, 0.14)
                box(color(NSColor(white: 0.25, alpha: 1), rough: 0.7), ud + s * 1.0, 0.12, 0.55, 0.5, 0.55, 0.5)
                blob(leaf, ud + s * 1.0, 0.95, 0.55, 0.32, scale: [1, 1.3, 1])
            }
            box(frame, 0, H - 0.5, 0.75, W, 0.12, 1.5)
            return f
        case .bar:
            let frame = color(NSColor(white: 0.05, alpha: 1), rough: 0.2, metal: 0.3)
            let f = front(W, H, frame: frame, glass: darkGlass, door: frame, mullion: 1.6, transom: false, plinth: 1.3)
            // Neon round the windows.
            let neon = color(style.color, glow: 5)
            let y0: Float = 1.3, y1 = H - 0.55, x0 = ud + 0.6, x1 = W / 2 - 0.3
            box(neon, (x0 + x1) / 2, y0, 0.12, x1 - x0, 0.05, 0.04)
            box(neon, (x0 + x1) / 2, y1 - 0.05, 0.12, x1 - x0, 0.05, 0.04)
            box(neon, x0, y0, 0.12, 0.05, y1 - y0, 0.04)
            box(neon, x1, y0, 0.12, 0.05, y1 - y0, 0.04)
            box(neon, ud, 2.45, 0.12, 1.1, 0.05, 0.04)
            return f
        case .pub:
            let frame = color(pick([NSColor(red: 0.1, green: 0.25, blue: 0.15, alpha: 1), NSColor(red: 0.35, green: 0.08, blue: 0.08, alpha: 1)]), rough: 0.4)
            let f = front(W, H, frame: frame, glass: warmGlass, door: frame, mullion: 0.4, transom: true, plinth: 0.9)
            // Barrels by the door, a lantern over it.
            let hoop = color(NSColor(white: 0.15, alpha: 1), rough: 0.5, metal: 0.6)
            for s: Float in [-1, 1] {
                post(wood, ud + s * 0.95, 0.5, 0.12, 0.3, 0.85)
                post(hoop, ud + s * 0.95, 0.5, 0.25, 0.31, 0.05)
                post(hoop, ud + s * 0.95, 0.5, 0.75, 0.31, 0.05)
            }
            box(metal, ud, 2.6, 0.35, 0.04, 0.04, 0.5)
            box(color(NSColor(red: 1, green: 0.75, blue: 0.4, alpha: 1), glow: 3), ud, 2.3, 0.55, 0.22, 0.3, 0.22)
            return f
        case .fastFood:
            let bright = pick([NSColor(red: 0.85, green: 0.12, blue: 0.1, alpha: 1), NSColor(red: 0.95, green: 0.5, blue: 0.05, alpha: 1),
                               NSColor(red: 0.1, green: 0.45, blue: 0.25, alpha: 1)])
            let frame = color(bright, rough: 0.25)
            let f = front(W, H, frame: frame, glass: coolGlass, door: color(NSColor(white: 0.85, alpha: 1), rough: 0.3), mullion: 1.6, transom: false, plinth: 0.35)
            let band = color(NSColor(red: 1, green: 0.85, blue: 0.1, alpha: 1), rough: 0.3, glow: 0.4)
            box(band, 0, H - 0.75, 0.3, W + 0.4, 0.7, 0.6)
            box(frame, 0, H - 0.05, 0.3, W + 0.4, 0.12, 0.6)
            return f
        case .bank:
            let stone = color(NSColor(red: 0.84, green: 0.81, blue: 0.74, alpha: 1), rough: 0.85)
            let f = front(W, H, frame: stone, glass: darkGlass, door: color(NSColor(red: 0.6, green: 0.5, blue: 0.3, alpha: 1), rough: 0.3, metal: 0.8),
                          mullion: 1.0, transom: true)
            // Columns, a cornice, steps and an ATM.
            let count = max(2, Int(W / 1.6))
            for k in 0..<count {
                let u = -W / 2 + 0.35 + Float(k) * (W - 0.7) / Float(count - 1)
                post(stone, u, 0.55, 0.12, 0.2, H - 0.2, segments: 12)
                box(stone, u, 0, 0.55, 0.5, 0.2, 0.5)
            }
            box(stone, 0, H - 0.2, 0.4, W + 0.3, 0.35, 0.95)
            box(stone, 0, 0, 0.9, W * 0.7, 0.14, 0.6)
            box(metal, W / 2 - 0.9, 0.9, 0.12, 0.6, 0.9, 0.15)
            box(color(NSColor(red: 0.3, green: 0.7, blue: 1, alpha: 1), glow: 2), W / 2 - 0.9, 1.35, 0.2, 0.36, 0.25, 0.02)
            return f
        case .theatre:
            let frame = color(NSColor(red: 0.45, green: 0.05, blue: 0.08, alpha: 1), rough: 0.4)
            let f = front(W, H, frame: frame, glass: warmGlass, door: brass, mullion: 1.1, transom: false)
            // A marquee with bulbs round it and the name across the front.
            let marquee = color(NSColor(red: 0.3, green: 0.04, blue: 0.06, alpha: 1), rough: 0.4)
            let bulbs = color(NSColor(red: 1, green: 0.9, blue: 0.6, alpha: 1), glow: 4)
            let mw = W + 0.6, my = H - 0.55
            box(marquee, 0, my, 1.6, mw, 1.0, 2.6)
            for y in [my, my + 0.95] {
                box(bulbs, 0, y, 2.92, mw, 0.06, 0.04)
                for s: Float in [-1, 1] { box(bulbs, s * (mw / 2 + 0.02), y, 1.6, 0.04, 0.06, 2.6) }
            }
            let panel = color(NSColor(white: 0.95, alpha: 1), glow: 0.9)
            box(panel, 0, my + 0.18, 2.91, mw - 0.6, 0.62, 0.02)
            texts.append(ShopText(text: name.uppercased(), maxWidth: mw - 0.9, at: p(0, my + 0.49, 2.93), rot: rot))
            return f
        case .clothes, .books, .gifts:
            let frame = color(pick([NSColor(white: 0.08, alpha: 1), NSColor(white: 0.95, alpha: 1), style.color.blended(withFraction: 0.4, of: .black) ?? style.color]), rough: 0.35)
            let d0: Float = 0.55
            let f = front(W, H, frame: frame, glass: clearGlass, door: frame, mullion: 2.0, transom: false, d0: d0)
            let x0 = ud + 0.7, x1 = W / 2 - 0.4
            if look == .clothes {
                // Mannequins in the window.
                var u = x0 + 0.3
                var k = seed
                while u < x1 {
                    let shirt = color(Crowd.shirts[k % Crowd.shirts.count], rough: 0.85)
                    post(metal, u, 0.3, 0.45, 0.02, 0.5, segments: 6)
                    box(shirt, u, 0.95, 0.3, 0.38, 0.6, 0.2)
                    box(color(Crowd.pants[k % Crowd.pants.count], rough: 0.85), u, 0.6, 0.3, 0.3, 0.35, 0.18)
                    blob(color(NSColor(white: 0.92, alpha: 1), rough: 0.4), u, 1.68, 0.3, 0.11)
                    u += 1.0; k += 3
                }
            } else if look == .books {
                // Shelves of books.
                let colours = [NSColor(red: 0.6, green: 0.1, blue: 0.1, alpha: 1), NSColor(red: 0.1, green: 0.25, blue: 0.5, alpha: 1),
                               NSColor(red: 0.15, green: 0.4, blue: 0.2, alpha: 1), NSColor(red: 0.85, green: 0.7, blue: 0.3, alpha: 1),
                               NSColor(white: 0.9, alpha: 1), NSColor(red: 0.4, green: 0.25, blue: 0.5, alpha: 1)]
                for shelf: Float in [0.6, 1.25, 1.9] where shelf + 0.4 < H - 0.6 {
                    box(wood, (x0 + x1) / 2, shelf - 0.04, 0.2, x1 - x0, 0.04, 0.3)
                    var u = x0 + 0.05
                    var k = seed + Int(shelf * 10)
                    while u < x1 - 0.05 {
                        let w = 0.04 + Float(k % 3) * 0.015, h = 0.22 + Float(k % 4) * 0.03
                        box(color(colours[k % colours.count], rough: 0.7), u + w / 2, shelf, 0.2, w, h, 0.18)
                        u += w + 0.008; k += 7
                    }
                }
            } else {
                // Pedestals with things that catch the light.
                var u = x0 + 0.3
                var k = seed
                while u < x1 {
                    let h = 0.7 + Float(k % 3) * 0.2
                    box(color(NSColor(white: 0.95, alpha: 1), rough: 0.5), u, 0.45, 0.25, 0.35, h, 0.35)
                    box(color(pick([NSColor(red: 1, green: 0.85, blue: 0.4, alpha: 1), NSColor(red: 0.7, green: 0.85, blue: 1, alpha: 1)]), glow: 2),
                        u, 0.45 + h, 0.25, 0.12, 0.12, 0.12)
                    u += 0.8; k += 1
                }
            }
            return f
        case .grocery:
            let frame = color(pick([NSColor(red: 0.15, green: 0.4, blue: 0.2, alpha: 1), NSColor(red: 0.6, green: 0.12, blue: 0.1, alpha: 1)]), rough: 0.5)
            let f = front(W, H, frame: frame, glass: coolGlass, door: color(NSColor(white: 0.75, alpha: 1), rough: 0.3, metal: 0.6), mullion: 1.4, transom: false, plinth: 0.3)
            // Crates of fruit and flowers out front.
            let fruit = [NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1), NSColor(red: 1, green: 0.55, blue: 0.05, alpha: 1),
                         NSColor(red: 1, green: 0.88, blue: 0.2, alpha: 1), NSColor(red: 0.4, green: 0.7, blue: 0.15, alpha: 1)]
            var u = ud + 1.2
            var k = seed
            while u < W / 2 - 0.5 {
                box(wood, u, 0.12, 0.75, 0.7, 0.55, 0.5, tilt: -0.15)
                let c = color(fruit[k % fruit.count], rough: 0.5)
                for a in 0..<3 { for b in 0..<2 { blob(c, u - 0.2 + Float(a) * 0.2, 0.72 + Float(b) * 0.06, 0.65 + Float(b) * 0.18, 0.09) } }
                u += 0.85; k += 1
            }
            return f
        case .pharmacy:
            let frame = color(NSColor(white: 0.95, alpha: 1), rough: 0.4)
            let f = front(W, H, frame: frame, glass: coolGlass, door: frame, mullion: 1.5, transom: false)
            let cross = color(NSColor(red: 0.1, green: 0.85, blue: 0.35, alpha: 1), glow: 4)
            box(metal, W / 2 - 0.3, H - 0.4, 0.4, 0.04, 0.04, 0.7)
            box(cross, W / 2 - 0.3, H - 1.1, 0.75, 0.12, 0.6, 0.2)
            box(cross, W / 2 - 0.3, H - 0.9, 0.75, 0.12, 0.2, 0.6)
            return f
        case .salon:
            let frame = color(pick([NSColor(red: 0.95, green: 0.75, blue: 0.8, alpha: 1), NSColor(white: 0.08, alpha: 1), NSColor(white: 0.95, alpha: 1)]), rough: 0.35)
            let f = front(W, H, frame: frame, glass: darkGlass, door: frame, mullion: 1.8, transom: false)
            // A barber's pole by the door.
            let stripes = [color(NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1), rough: 0.2), color(.white, rough: 0.2),
                           color(NSColor(red: 0.1, green: 0.2, blue: 0.7, alpha: 1), rough: 0.2)]
            box(metal, ud + 0.85, 2.35, 0.2, 0.06, 0.06, 0.3)
            for k in 0..<8 { post(stripes[k % 3], ud + 0.85, 0.32, 1.55 + Float(k) * 0.1, 0.08, 0.1, segments: 10) }
            blob(color(NSColor(white: 0.9, alpha: 1), rough: 0.1, metal: 0.8), ud + 0.85, 2.38, 0.32, 0.1)
            return f
        case .garage:
            let frame = color(NSColor(white: 0.45, alpha: 1), rough: 0.7)
            box(frame, 0, 0, 0, W, H, 0.12)
            // A roll-up door and a stack of tyres.
            let steel = color(NSColor(white: 0.68, alpha: 1), rough: 0.4, metal: 0.6)
            let dw = max(2, W - 2.0)
            var y: Float = 0
            while y < 2.9 { box(steel, -W / 2 + 0.3 + dw / 2, y, 0.08, dw, 0.12, 0.06); y += 0.15 }
            box(color(NSColor(white: 0.1, alpha: 1), rough: 0.9), W / 2 - 0.85, 0, 0.1, 1.1, 2.3, 0.06)
            let rubber = color(NSColor(white: 0.06, alpha: 1), rough: 0.9)
            for k in 0..<4 { post(rubber, W / 2 - 0.5, 0.9, 0.12 + Float(k) * 0.24, 0.33, 0.22, segments: 12) }
            return 0.14
        case .hotel:
            let frame = color(NSColor(red: 0.12, green: 0.16, blue: 0.3, alpha: 1), rough: 0.4)
            let f = front(W, H, frame: frame, glass: warmGlass, door: brass, mullion: 1.3, transom: true)
            // A canopy out to the curb over a red carpet.
            box(frame, ud, 2.9, 1.9, 2.4, 0.2, 3.8)
            for s: Float in [-1, 1] { post(brass, ud + s * 1.1, 3.7, 0.12, 0.05, 2.8) }
            box(color(NSColor(red: 0.6, green: 0.05, blue: 0.08, alpha: 1), rough: 0.95), ud, 0.12, 1.9, 1.4, 0.02, 3.8)
            return f
        case .generic:
            let frame = color(pick([NSColor(white: 0.15, alpha: 1), NSColor(red: 0.2, green: 0.25, blue: 0.35, alpha: 1),
                                    NSColor(red: 0.85, green: 0.82, blue: 0.75, alpha: 1), style.color.blended(withFraction: 0.5, of: .black) ?? .gray]), rough: 0.45)
            _ = accent
            return front(W, H, frame: frame, glass: darkGlass, door: frame, mullion: 1.0, transom: true)
        }
    }
}

extension ShopBuilder {
    /// Four shopfronts side by side on a plain wall, for looking at them on their own.
    @MainActor static func sample(_ looks: [ShopLook]) -> Entity {
        var b = ShopBuilder()
        let root = Entity()
        for (i, look) in looks.enumerated() {
            let x = (Float(i) - Float(looks.count - 1) / 2) * 6.5
            b.at(SIMD2(x, 0.12), out: SIMD2(0, -1))
            _ = b.build(look, name: "\(look)", width: 5.5, height: 3.6, style: .of(""), seed: i * 3)
        }
        var wall = MeshKit()
        wall.box([0, 3, -0.5], [Float(looks.count) * 6.5, 6, 1])
        if let m = wall.mesh() { root.addChild(ModelEntity(mesh: m, materials: [LampMaterial.brick(repeat: 1)])) }
        for (k, kit) in b.kits {
            guard let mesh = kit.mesh(), let m = b.mats[k] else { continue }
            root.addChild(ModelEntity(mesh: mesh, materials: [m.material(k)]))
        }
        for t in b.texts { root.addChild(t.entity()) }
        return root
    }
}
