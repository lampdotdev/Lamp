import SwiftUI
import RealityKit

// The city's businesses from OpenStreetMap: what kind each is, its hours, and how its storefront looks
// (awning, a projecting sign with its icon, patio tables, an OPEN sign that follows the real clock).

/// What kind of place, for icons and colours.
struct BusinessStyle {
    let symbol: String
    let color: NSColor

    static func of(_ kind: String) -> BusinessStyle {
        func s(_ sym: String, _ r: CGFloat, _ g: CGFloat, _ b: CGFloat) -> BusinessStyle {
            BusinessStyle(symbol: sym, color: NSColor(red: r, green: g, blue: b, alpha: 1))
        }
        switch kind {
        case "cafe", "coffee", "tea": return s("cup.and.saucer.fill", 0.45, 0.28, 0.16)
        case "restaurant": return s("fork.knife", 0.82, 0.25, 0.15)
        case "fast_food": return s("takeoutbag.and.cup.and.straw.fill", 0.95, 0.5, 0.1)
        case "bar", "nightclub": return s("wineglass.fill", 0.5, 0.2, 0.6)
        case "pub", "alcohol", "beverages": return s("mug.fill", 0.75, 0.55, 0.1)
        case "ice_cream", "confectionery": return s("snowflake", 0.95, 0.45, 0.65)
        case "bakery", "pastry": return s("birthday.cake.fill", 0.85, 0.6, 0.3)
        case "bank": return s("banknote.fill", 0.1, 0.5, 0.3)
        case "theatre", "cinema": return s("theatermasks.fill", 0.7, 0.1, 0.15)
        case "pharmacy": return s("cross.case.fill", 0.1, 0.6, 0.35)
        case "books": return s("book.fill", 0.1, 0.45, 0.5)
        case "library": return s("books.vertical.fill", 0.15, 0.35, 0.55)
        case "clothes", "shoes", "boutique", "fashion": return s("tshirt.fill", 0.85, 0.3, 0.5)
        case "hairdresser", "beauty", "cosmetics", "massage", "piercing", "tattoo": return s("scissors", 0.65, 0.25, 0.65)
        case "jewelry", "rock": return s("sparkles", 0.75, 0.6, 0.2)
        case "convenience", "supermarket", "greengrocer", "deli", "marketplace": return s("cart.fill", 0.2, 0.55, 0.2)
        case "music", "musical_instrument": return s("music.note", 0.3, 0.3, 0.7)
        case "bicycle", "scooter": return s("bicycle", 0.2, 0.5, 0.65)
        case "car_repair", "car_parts": return s("wrench.and.screwdriver.fill", 0.4, 0.4, 0.45)
        case "mobile_phone", "electronics_repair": return s("iphone", 0.3, 0.35, 0.45)
        case "museum": return s("building.columns.fill", 0.5, 0.45, 0.35)
        case "hotel": return s("bed.double.fill", 0.25, 0.3, 0.55)
        case "florist", "garden_centre": return s("leaf.fill", 0.3, 0.6, 0.25)
        case "gift", "antiques", "frame", "photo": return s("gift.fill", 0.75, 0.3, 0.3)
        case "optician": return s("eyeglasses", 0.2, 0.4, 0.6)
        case "cannabis", "tobacco": return s("leaf.circle.fill", 0.35, 0.5, 0.2)
        default: return s("bag.fill", 0.2, 0.4, 0.75)
        }
    }
}

/// Opening hours in OpenStreetMap's format ("Mo-Fr 07:00-19:00; Sa,Su 08:00-17:00"), the common parts of it.
struct OpeningHours {
    /// Minutes from midnight, Monday first; an interval can run past midnight (end over 1440).
    var week: [[ClosedRange<Int>]] = Array(repeating: [], count: 7)

    init?(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespaces)
        if t == "24/7" { week = Array(repeating: [0...1440], count: 7); return }
        let names = ["Mo", "Tu", "We", "Th", "Fr", "Sa", "Su"]
        var any = false
        for raw in t.replacingOccurrences(of: "||", with: ";").split(separator: ";") {
            var rule = raw.trimmingCharacters(in: .whitespaces)
            if rule.hasPrefix("PH") || rule.hasPrefix("SH") || rule.isEmpty { continue }
            var days = Array(0..<7)
            let first = rule.split(separator: " ", maxSplits: 1).first.map(String.init) ?? ""
            if let d = first.first, d.isLetter, first.count >= 2, names.contains(String(first.prefix(2))) {
                days = []
                for part in first.split(separator: ",") {
                    let ends = part.split(separator: "-").map(String.init)
                    guard let a = names.firstIndex(of: ends[0]) else { continue }
                    let b = ends.count > 1 ? (names.firstIndex(of: ends[1]) ?? a) : a
                    var k = a
                    while true { days.append(k); if k == b { break }; k = (k + 1) % 7 }
                }
                rule = String(rule.dropFirst(first.count)).trimmingCharacters(in: .whitespaces)
            } else if let d = first.first, d.isLetter, rule.lowercased() != "off", rule.lowercased() != "closed" {
                continue    // months, holidays, sunrise: not handled
            }
            if rule.isEmpty { continue }
            if rule == "off" || rule == "closed" { for d in days { week[d] = [] }; any = true; continue }
            var spans: [ClosedRange<Int>] = []
            for span in rule.split(separator: ",") {
                let ends = span.trimmingCharacters(in: .whitespaces).split(separator: "-")
                guard ends.count == 2, let a = Self.minutes(ends[0]), var b = Self.minutes(ends[1]) else { continue }
                if b <= a { b += 1440 }
                spans.append(a...b)
            }
            guard !spans.isEmpty else { continue }
            for d in days { week[d] = spans }
            any = true
        }
        if !any { return nil }
    }

    private static func minutes(_ s: Substring) -> Int? {
        let p = s.trimmingCharacters(in: CharacterSet(charactersIn: " +")).split(separator: ":")
        guard p.count == 2, let h = Int(p[0]), let m = Int(p[1]) else { return nil }
        return h * 60 + m
    }

    /// Open now, and a short line saying until when or when it opens.
    func status(at date: Date = Date()) -> (open: Bool, text: String) {
        let cal = Calendar.current
        let day = (cal.component(.weekday, from: date) + 5) % 7        // Monday 0
        let now = cal.component(.hour, from: date) * 60 + cal.component(.minute, from: date)
        for r in week[day] where r.contains(now) && now < r.upperBound {
            return (true, r.upperBound - r.lowerBound >= 1440 ? "Open 24 hours" : "Open until \(Self.clock(r.upperBound))")
        }
        for r in week[(day + 6) % 7] where r.upperBound > 1440 && now + 1440 < r.upperBound {
            return (true, "Open until \(Self.clock(r.upperBound))")
        }
        if let r = week[day].first(where: { $0.lowerBound > now }) { return (false, "Opens at \(Self.clock(r.lowerBound))") }
        let names = ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday", "Sunday"]
        for k in 1...7 {
            let d = (day + k) % 7
            if let r = week[d].first { return (false, "Opens \(k == 1 ? "tomorrow" : names[d]) at \(Self.clock(r.lowerBound))") }
        }
        return (false, "Closed")
    }

    static func clock(_ minutes: Int) -> String {
        let m = minutes % 1440
        if m == 0 { return "midnight" }
        if m == 720 { return "noon" }
        let h = m / 60, mm = m % 60
        let h12 = h % 12 == 0 ? 12 : h % 12
        return (mm == 0 ? "\(h12)" : String(format: "%d:%02d", h12, mm)) + (h < 12 ? " AM" : " PM")
    }
}

/// What the HUD's card shows about the place being passed.
struct BusinessInfo: Equatable {
    let name: String
    let label: String
    let address: String?
    let status: String?
    let open: Bool?
    let contact: String?
    let website: URL?
    let site: String?
    let symbol: String
    let color: Color
}

/// A place on the minimap.
struct BusinessMarker {
    let pos: SIMD2<Float>
    let symbol: String
    let color: Color
}

struct Business {
    let data: ShopData
    let pos: SIMD2<Float>
    let style: BusinessStyle
    let hours: OpeningHours?
    var openSign: Entity?

    /// Open now: by its hours, or ordinary shop hours when it has none.
    var isOpen: Bool {
        if let h = hours { return h.status().open }
        let hour = Calendar.current.component(.hour, from: Date())
        return hour >= 9 && hour < 21
    }

    var info: BusinessInfo {
        var label = data.k.map { $0.replacingOccurrences(of: "_", with: " ").capitalized } ?? "Shop"
        if let c = data.c {
            let cuisines = c.split(separator: ";").prefix(2).map { $0.replacingOccurrences(of: "_", with: " ").capitalized }
            label += " · " + cuisines.joined(separator: ", ")
        }
        let status = hours?.status()
        var contact: [String] = []
        if let p = data.ph { contact.append(p) }
        let url = data.w.flatMap { URL(string: $0.hasPrefix("http") ? $0 : "https://" + $0) }
        let site = url?.host?.replacingOccurrences(of: "www.", with: "")
        let address = data.a.map { $0.replacingOccurrences(of: " Street", with: " St").replacingOccurrences(of: " Avenue", with: " Ave") }
        return BusinessInfo(name: data.n, label: label, address: address, status: status?.text, open: status?.open,
                            contact: contact.isEmpty ? nil : contact.joined(separator: "  ·  "), website: url, site: site,
                            symbol: style.symbol, color: Color(nsColor: style.color))
    }
}

@MainActor
final class Businesses {
    var all: [Business] = []
    private var lastClock: Float = -100

    init(city: City) {
        all = city.file.shops.map { s in
            Business(data: s, pos: SIMD2(s.x, s.y), style: .of(s.k ?? ""), hours: s.h.flatMap { OpeningHours($0) })
        }
    }

    /// Businesses in a newly loaded piece of the city; their shopfronts are drawn with its squares.
    @discardableResult
    func add(_ shops: [ShopData]) -> [Int] {
        let start = all.count
        all += shops.map { s in Business(data: s, pos: SIMD2(s.x, s.y), style: .of(s.k ?? ""), hours: s.h.flatMap { OpeningHours($0) }) }
        return Array(start..<all.count)
    }

    var markers: [BusinessMarker] { all.map { BusinessMarker(pos: $0.pos, symbol: $0.style.symbol, color: Color(nsColor: $0.style.color)) } }

    /// The place beside the car, if any.
    func nearest(to p: SIMD2<Float>, within r: Float = 22) -> Business? {
        var best: Business?, bd = r
        for b in all {
            let d = simd_distance(b.pos, p)
            if d < bd { bd = d; best = b }
        }
        return best
    }

    /// OPEN signs on and off with the clock.
    func tick(time: Float) {
        guard time - lastClock > 30 else { return }
        lastClock = time
        for b in all { b.openSign?.isEnabled = b.isOpen }
    }

    // MARK: Storefronts

    private static func flat(_ c: NSColor, rough: Float = 0.6, metal: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        return m
    }

    /// Canvas stripes in a colour and white, for awnings and umbrellas.
    nonisolated private static func stripes(_ c: SIMD3<Float>) -> CGImage {
        LampTexture.draw(64, 8) { u, _ in Int(u * 4) % 2 == 0 ? SIMD4(c, 1) : SIMD4(0.95, 0.94, 0.9, 1) }
    }

    /// A square sign: the category's colour, a white border and its icon.
    nonisolated static func iconImage(_ style: BusinessStyle) -> CGImage {
        let size = 128
        let image = NSImage(size: NSSize(width: size, height: size), flipped: false) { r in
            style.color.setFill()
            NSBezierPath(rect: r).fill()
            NSColor.white.setStroke()
            let border = NSBezierPath(roundedRect: r.insetBy(dx: 8, dy: 8), xRadius: 14, yRadius: 14)
            border.lineWidth = 6
            border.stroke()
            let config = NSImage.SymbolConfiguration(pointSize: 60, weight: .bold).applying(.init(paletteColors: [.white]))
            if let sym = NSImage(systemSymbolName: style.symbol, accessibilityDescription: nil)?.withSymbolConfiguration(config) {
                let s = sym.size
                sym.draw(in: NSRect(x: (r.width - s.width) / 2, y: (r.height - s.height) / 2, width: s.width, height: s.height))
            }
            return true
        }
        var rect = NSRect(x: 0, y: 0, width: size, height: size)
        return image.cgImage(forProposedRect: &rect, context: nil, hints: nil)!
    }

    /// Awnings, projecting icon signs, patio tables and OPEN signs for every business.
    func decorate(_ root: Entity, indices: [Int], plans: [ShopPieces.Plan] = []) {
        for (k, i) in indices.enumerated() where i < all.count {
            let b = all[i]
            let piece = ShopPieces.piece(i, b, plan: k < plans.count ? plans[k] : nil)
            let n = SIMD2(b.data.dx, b.data.dy)
            // Built facing north at the origin; turned to face the street and moved to the shop.
            let holder = Entity()
            holder.transform = Transform(rotation: simd_quatf(angle: atan2(-n.x, n.y), axis: [0, 1, 0]), translation: w3(b.pos, 0))
            if let mesh = piece.mesh { holder.addChild(ModelEntity(mesh: mesh, materials: piece.materials)) }
            for e in piece.extras { holder.addChild(e.clone(recursive: true)) }
            // OPEN sign in the window, lit while it's open.
            let sign = ModelEntity(mesh: ShopPieces.openMesh, materials: [ShopPieces.openMaterial])
            sign.transform = piece.openSign
            sign.isEnabled = b.isOpen
            holder.addChild(sign)
            all[i].openSign = sign
            root.addChild(holder)
        }
    }

    /// Canvas stripes in a colour and white, for awnings and umbrellas.
    nonisolated static func stripeImage(_ c: SIMD3<Float>) -> CGImage { stripes(c) }
    static func icon(_ style: BusinessStyle) -> CGImage { iconImage(style) }
    static func flatMaterial(_ c: NSColor, rough: Float = 0.6, metal: Float = 0) -> PhysicallyBasedMaterial { flat(c, rough: rough, metal: metal) }
}

/// Each business's storefront, made once (meshes in its own frame: at the origin, facing north) and reused every
/// time its square is drawn. Kept in statics, so a live change to how storefronts are made starts afresh.
@MainActor
enum ShopPieces {
    struct Piece {
        var mesh: MeshResource?
        var materials: [RealityKit.Material] = []
        var extras: [Entity] = []
        var openSign = Transform()
    }

    /// A storefront worked out off the main thread: its triangles per material, the materials described, its
    /// lettering, and where its OPEN sign goes.
    struct Plan: @unchecked Sendable {
        var meshes: [(key: String, mesh: LampMeshBuilder)] = []
        var mats: [String: ShopMat] = [:]
        var texts: [ShopText] = []
        var style: BusinessStyle
        /// The awning stripes and icon sign pictures for this kind of place, drawn off the main thread.
        var stripes: CGImage?
        var icon: CGImage?
        var openSpot = SIMD3<Float>(0, 0, 0)
        var openYaw = simd_quatf(angle: 0, axis: [0, 1, 0])
    }

    /// Pictures drawn off the main thread, once per kind of place.
    final class Pictures: @unchecked Sendable {
        private let lock = NSLock()
        private var images: [String: CGImage] = [:]
        func get(_ key: String, _ draw: () -> CGImage) -> CGImage {
            lock.lock()
            if let i = images[key] { lock.unlock(); return i }
            lock.unlock()
            let i = draw()
            lock.lock(); images[key] = i; lock.unlock()
            return i
        }
    }
    nonisolated static let pictures = Pictures()

    static var pieces: [Int: Piece] = [:]
    static var materials: [String: RealityKit.Material] = [
        "metal": Businesses.flatMaterial(NSColor(white: 0.15, alpha: 1), rough: 0.4, metal: 0.6),
        "wood": Businesses.flatMaterial(NSColor(red: 0.45, green: 0.3, blue: 0.18, alpha: 1), rough: 0.8),
    ]
    static let openMesh = LampMesh.text("OPEN", size: 0.24, depth: 0.01, weight: .heavy)
    static let openMaterial = LampMaterial.glow(NSColor(red: 1, green: 0.15, blue: 0.3, alpha: 1), strength: 2.5)

    /// The storefront for a business: made once, from a plan worked out off the main thread when there is one.
    static func piece(_ index: Int, _ b: Business, plan: Plan? = nil) -> Piece {
        if let p = pieces[index] { return p }
        let p = finish(plan ?? Self.plan(b.data))
        pieces[index] = p
        return p
    }

    /// Off the main thread: the storefront's geometry, in its own frame (at the origin, facing north).
    nonisolated static func plan(_ data: ShopData) -> Plan {
        let style = BusinessStyle.of(data.k ?? "")
        var kits: [String: MeshKit] = [:]
        let n = SIMD2<Float>(0, 1), t = SIMD2<Float>(1, 0), o = SIMD2<Float>(0, 0)
        let key = style.symbol
        let width = min(Float(data.n.count) * 0.21 + 0.6, 6.6) + 0.6
        let base = Heights.sidewalk

        // The shopfront itself, built for the kind of place it is.
        let look = ShopLook.of(data.k ?? "")
        let seed = data.n.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }
        var shop = ShopBuilder()
        shop.at(o, out: n)
        let frontD = shop.build(look, name: data.n, width: width, height: max(2.9, min(3.7, data.z - 0.45)), style: style, seed: seed)
        let ahead = n * max(0, frontD - 0.12)

        // Awning under the name plaque, sloping out over the sidewalk.
        let topY = data.z - 0.42, dropY = topY - 0.55, out: Float = 1.3
        let l = o - t * width / 2 + ahead, r = o + t * width / 2 + ahead
        if look.awning {
            kits["awn" + key, default: MeshKit()].quad(w3(l, topY), w3(r, topY), w3(r + n * out, dropY), w3(l + n * out, dropY),
                                                       uv: ([0, 0], [width / 0.5, 0], [width / 0.5, 1], [0, 1]), outward: [0, 1, 0])
            kits["awn" + key, default: MeshKit()].quad(w3(l + n * out, dropY), w3(r + n * out, dropY), w3(r + n * out, dropY - 0.25), w3(l + n * out, dropY - 0.25),
                                                       uv: ([0, 0], [width / 0.5, 0], [width / 0.5, 1], [0, 1]), outward: SIMD3(n.x, 0, -n.y))
        }

        // A projecting sign with the icon, at one end of the shopfront, readable from both ways along the street.
        let at = o + t * (width / 2 + 0.45)
        let c = at + n * 0.62, y = data.z - 0.1
        let h: Float = 0.3
        let p0 = c - n * h, p1 = c + n * h
        kits["icon" + key, default: MeshKit()].quad(w3(p0, y - h), w3(p1, y - h), w3(p1, y + h), w3(p0, y + h),
                                                    uv: ([0, 0], [1, 0], [1, 1], [0, 1]), outward: SIMD3(t.x, 0, -t.y))
        kits["icon" + key, default: MeshKit()].quad(w3(p1, y - h), w3(p0, y - h), w3(p0, y + h), w3(p1, y + h),
                                                    uv: ([0, 0], [1, 0], [1, 1], [0, 1]), outward: SIMD3(-t.x, 0, t.y))
        kits["metal", default: MeshKit()].box(w3(at + n * 0.45, y + h + 0.05), [0.04, 0.04, 0.9],
                                               rot: simd_quatf(angle: atan2(n.x, -n.y), axis: [0, 1, 0]))

        // Patio: two tables with umbrellas out front.
        if data.o == 1 {
            for side: Float in [-1, 1] {
                let tp = o + n * 2.6 + t * side * 1.6
                kits["metal", default: MeshKit()].post(w3(tp, base), radius: 0.03, height: 0.74, segments: 6)
                kits["wood", default: MeshKit()].post(w3(tp, base + 0.72), radius: 0.42, height: 0.04, segments: 10)
                kits["metal", default: MeshKit()].post(w3(tp, base + 0.76), radius: 0.025, height: 1.5, segments: 6)
                kits["awn" + key, default: MeshKit()].blob(w3(tp, base + 2.25), radius: 1.15, scale: [1, 0.28, 1], segments: 10, rings: 3)
                for k in 0..<2 {
                    let cp = tp + t * (k == 0 ? -0.75 : 0.75)
                    kits["wood", default: MeshKit()].box(w3(cp, base + 0.45), [0.42, 0.05, 0.42])
                    kits["wood", default: MeshKit()].box(w3(cp + t * (k == 0 ? -0.2 : 0.2), base + 0.7), [0.42, 0.5, 0.05],
                                                        rot: simd_quatf(angle: atan2(t.x, -t.y), axis: [0, 1, 0]))
                }
            }
        }

        for (k, kit) in shop.kits { kits[k] = kits[k].map { var m = $0; m.append(kit); return m } ?? kit }
        var plan = Plan(style: style)
        var rgb = SIMD3<Float>(0, 0, 0)
        if let c = style.color.usingColorSpace(.sRGB) { rgb = [Float(c.redComponent), Float(c.greenComponent), Float(c.blueComponent)] }
        plan.stripes = pictures.get("stripes-" + key) { Businesses.stripeImage(rgb) }
        plan.icon = pictures.get("icon-" + key) { Businesses.iconImage(style) }
        plan.meshes = kits.sorted(by: { $0.key < $1.key }).filter { !$0.value.isEmpty }.map { (key: $0.key, mesh: $0.value.builder) }
        plan.mats = shop.mats
        plan.texts = shop.texts
        plan.openYaw = simd_quatf(angle: atan2(n.x, -n.y), axis: [0, 1, 0])
        let spot = o - t * (width / 2 - 0.9) + ahead + n * 0.03
        plan.openSpot = w3(spot, base + 2.0)
        return plan
    }

    /// On the main thread: the storefront's one mesh (a part per material) and its lettering.
    private static func finish(_ plan: Plan) -> Piece {
        let key = plan.style.symbol
        if materials["awn" + key] == nil {
            var c = SIMD3<Float>(0, 0, 0)
            if let rgb = plan.style.color.usingColorSpace(.sRGB) { c = [Float(rgb.redComponent), Float(rgb.greenComponent), Float(rgb.blueComponent)] }
            var m = PhysicallyBasedMaterial()
            m.baseColor = .init(tint: .white, texture: .init(LampTexture.cached("stripes-" + key) { plan.stripes ?? Businesses.stripeImage(c) }, sampler: LampTexture.sampler))
            m.roughness = .init(floatLiteral: 0.9)
            m.faceCulling = .none
            materials["awn" + key] = m
            var icon = PhysicallyBasedMaterial()
            let tex = LampTexture.cached("icon-" + key) { plan.icon ?? Businesses.icon(plan.style) }
            icon.baseColor = .init(tint: .white, texture: .init(tex, sampler: LampTexture.sampler))
            icon.emissiveColor = .init(color: NSColor(white: 0.25, alpha: 1), texture: .init(tex))
            icon.emissiveIntensity = 0.6
            icon.roughness = .init(floatLiteral: 0.5)
            materials["icon" + key] = icon
        }
        var piece = Piece()
        // One mesh for the whole storefront, a part per material: one mesh to make, one entity to draw.
        var descriptors: [MeshDescriptor] = []
        for m in plan.meshes {
            let material: RealityKit.Material
            if let shared = materials[m.key] { material = shared } else if let spec = plan.mats[m.key] { material = spec.material(m.key) } else { continue }
            guard var d = m.mesh.descriptor() else { continue }
            d.materials = .allFaces(UInt32(piece.materials.count))
            descriptors.append(d)
            piece.materials.append(material)
        }
        piece.mesh = descriptors.isEmpty ? nil : try? MeshResource.generate(from: descriptors)
        piece.extras = plan.texts.map { $0.entity() }
        let ob = openMesh.bounds
        piece.openSign = Transform(rotation: plan.openYaw, translation: plan.openSpot + plan.openYaw.act([-ob.center.x, -ob.center.y, 0]))
        return piece
    }
}
