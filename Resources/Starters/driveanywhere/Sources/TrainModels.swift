import SwiftUI
import RealityKit

/// Locomotives and cars, built facing -z with the rail tops at their origin.
@MainActor
enum RollingStock {
    private static func entity(_ parts: [(MeshKit, RealityKit.Material)]) -> Entity {
        let root = Entity()
        for (kit, m) in parts { if let mesh = kit.mesh() { root.addChild(ModelEntity(mesh: mesh, materials: [m])) } }
        return root
    }

    private static let dark = LampMaterial.metal(NSColor(white: 0.1, alpha: 1), rough: 0.6)
    private static let steel = LampMaterial.metal(NSColor(white: 0.35, alpha: 1), rough: 0.4)
    private static let glass: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(red: 0.12, green: 0.15, blue: 0.2, alpha: 1))
        m.roughness = .init(floatLiteral: 0.05)
        m.metallic = .init(floatLiteral: 0.6)
        return m
    }()

    /// Two bogies with their wheels, and the frame between them.
    private static func running(_ kit: inout MeshKit, length: Float, centers: Float, frameTop: Float = 1.5) {
        for z in [-centers, centers] {
            kit.box([0, 0.75, z], [2.5, 0.6, 3.4])
            for zz in [z - 1.1, z + 1.1] {
                for x: Float in [-0.72, 0.72] { kit.wheel([x, 0.46, zz], radius: 0.46, width: 0.14, segments: 14) }
            }
        }
        kit.box([0, frameTop - 0.25, 0], [2.9, 0.5, length - 0.4])
        kit.box([0, frameTop - 0.4, -length / 2], [0.4, 0.3, 0.6])       // couplers
        kit.box([0, frameTop - 0.4, length / 2], [0.4, 0.3, 0.6])
    }

    // MARK: Freight

    static func freightLoco() -> (Entity, Float, Float) {
        let L: Float = 19, W: Float = 3.1
        var paint = MeshKit(), under = MeshKit(), stripe = MeshKit(), win = MeshKit(), rail = MeshKit(), light = MeshKit()
        running(&under, length: L, centers: 6.3, frameTop: 1.6)
        under.box([0, 1.1, 0], [2.4, 1.0, 5.0])                            // fuel tank
        under.box([0, 1.62, 0], [W, 0.08, L])                              // walkway
        paint.box([0, 3.05, -6.1], [3.0, 2.9, 3.0])                        // cab
        paint.box([0, 2.4, -8.5], [2.4, 1.6, 1.8])                         // short nose
        paint.box([0, 2.85, 2.3], [2.3, 2.5, 13.8])                        // long hood
        paint.box([0, 4.55, -6.1], [2.6, 0.12, 2.8])                       // cab roof
        for z: Float in [0, 3, 6] { under.blob([0, 4.15, z], radius: 0.7, scale: [1, 0.25, 1]) }   // fans
        stripe.box([0, 2.2, 2.3], [2.32, 0.18, 13.82])
        stripe.box([0, 2.2, -6.1], [3.02, 0.18, 3.02])
        stripe.box([0, 1.95, -8.5], [2.42, 0.18, 1.82])
        win.box([0.65, 3.9, -7.62], [0.9, 0.6, 0.04])
        win.box([-0.65, 3.9, -7.62], [0.9, 0.6, 0.04])
        for x: Float in [-1.51, 1.51] {
            win.box([x, 3.85, -6.3], [0.04, 0.6, 1.6])
            rail.box([x, 2.6, 2.3], [0.04, 0.04, 13.8])
            for z in stride(from: Float(-4.5), through: 9, by: 2.25) { rail.box([x, 2.1, z], [0.04, 1.0, 0.04]) }
        }
        light.box([0, 3.0, -9.42], [0.5, 0.2, 0.04])
        let blue = NSColor(red: 0.08, green: 0.15, blue: 0.4, alpha: 1)
        let e = entity([(paint, LampMaterial.paint(blue)), (under, dark), (stripe, LampMaterial.paint(NSColor(red: 1, green: 0.8, blue: 0.05, alpha: 1))),
                        (win, glass), (rail, LampMaterial.paint(NSColor(red: 1, green: 0.8, blue: 0.05, alpha: 1))),
                        (light, LampMaterial.glow(NSColor(red: 1, green: 0.95, blue: 0.8, alpha: 1), strength: 4))])
        return (e, L, W)
    }

    static func boxcar(_ color: NSColor) -> (Entity, Float, Float) {
        let L: Float = 17, W: Float = 3.0
        var body = MeshKit(), under = MeshKit(), door = MeshKit()
        running(&under, length: L, centers: 6.0)
        body.box([0, 3.0, 0], [W, 3.0, L - 0.4])
        for z in stride(from: Float(-7.5), through: 7.5, by: 1.0) { body.box([0, 3.0, z], [W + 0.06, 2.9, 0.06]) }   // ribs
        for x: Float in [-1, 1] { door.box([x * (W / 2 + 0.05), 2.9, 0], [0.06, 2.6, 3.0]) }
        body.box([0, 4.55, 0], [W - 0.2, 0.1, L - 0.4])
        let darker = color.blended(withFraction: 0.35, of: .black) ?? color
        return (entity([(body, LampMaterial.paint(color)), (under, dark), (door, LampMaterial.paint(darker))]), L, W)
    }

    static func hopper(_ color: NSColor) -> (Entity, Float, Float) {
        let L: Float = 16, W: Float = 3.1
        var body = MeshKit(), under = MeshKit()
        running(&under, length: L, centers: 5.6)
        body.box([0, 3.2, 0], [W, 2.4, L - 0.6])
        body.taper([0, 1.5, -3.5], bottom: [1.2, 1.4], top: [W, 6.6], height: 0.5)
        body.taper([0, 1.5, 3.5], bottom: [1.2, 1.4], top: [W, 6.6], height: 0.5)
        body.box([0, 4.45, 0], [2.6, 0.1, L - 1.2])
        return (entity([(body, LampMaterial.paint(color)), (under, dark)]), L, W)
    }

    static func tankCar() -> (Entity, Float, Float) {
        let L: Float = 17, W: Float = 3.0
        var under = MeshKit()
        running(&under, length: L, centers: 6.2)
        let e = entity([(under, dark)])
        // The tank lying along the car, and the dome on top.
        var barrel = MeshKit(), dome = MeshKit()
        barrel.post([0, -(L - 1.4) / 2, 0], radius: 1.45, height: L - 1.4, segments: 20)
        for i in 0..<20 {
            // Its other end closed too.
            let a0 = Float(i) / 20 * 2 * .pi, a1 = Float(i + 1) / 20 * 2 * .pi, y = -(L - 1.4) / 2
            barrel.tri([0, y, 0], [cos(a1) * 1.45, y, sin(a1) * 1.45], [cos(a0) * 1.45, y, sin(a0) * 1.45], outward: [0, -1, 0])
        }
        dome.post([0, 4.25, 0], radius: 0.5, height: 0.4, segments: 12)
        let black = LampMaterial.paint(NSColor(white: 0.08, alpha: 1))
        let tank = entity([(barrel, black)])
        tank.orientation = simd_quatf(angle: .pi / 2, axis: [1, 0, 0])
        tank.position = [0, 2.9, 0]
        e.addChild(tank)
        e.addChild(entity([(dome, black)]))
        return (e, L, W)
    }

    static func freight() -> [(Entity, Float, Float)] {
        let colors = [NSColor(red: 0.5, green: 0.15, blue: 0.1, alpha: 1), NSColor(red: 0.15, green: 0.3, blue: 0.5, alpha: 1),
                      NSColor(red: 0.2, green: 0.35, blue: 0.2, alpha: 1), NSColor(red: 0.75, green: 0.6, blue: 0.2, alpha: 1)]
        var cars = [freightLoco()]
        for k in 0..<7 {
            switch k % 3 {
            case 0: cars.append(boxcar(colors[k % colors.count]))
            case 1: cars.append(hopper(NSColor(white: k % 2 == 0 ? 0.75 : 0.5, alpha: 1)))
            default: cars.append(tankCar())
            }
        }
        return cars
    }

    // MARK: Passenger trains

    /// A passenger locomotive, silver with a band in its `livery` (accent colour).
    static func locomotive(livery: NSColor = NSColor(red: 0.62, green: 0.08, blue: 0.1, alpha: 1)) -> (Entity, Float, Float) {
        let L: Float = 21, W: Float = 3.05
        var silver = MeshKit(), black = MeshKit(), blue = MeshKit(), win = MeshKit(), under = MeshKit(), light = MeshKit()
        running(&under, length: L, centers: 7.0, frameTop: 1.4)
        silver.box([0, 2.85, 1.2], [W, 2.9, L - 2.6])
        black.box([0, 2.3, -9.6], [W - 0.1, 1.8, 1.6])                       // nose
        black.box([0, 4.1, -8.6], [W - 0.2, 0.4, 0.4])
        win.quad([-1.4, 3.2, -10.3], [1.4, 3.2, -10.3], [1.4, 4.25, -9.0], [-1.4, 4.25, -9.0], outward: [0, 0.6, -1])
        for x: Float in [-1, 1] { black.quad([x * 1.5, 3.2, -10.3], [x * 1.5, 4.25, -9.0], [x * 1.5, 4.25, -8.8], [x * 1.5, 3.2, -8.8], outward: [x, 0, 0]) }
        silver.box([0, 4.33, 1.2], [W - 0.3, 0.1, L - 2.6])
        blue.box([0, 2.0, 0], [W + 0.04, 0.35, L - 0.8])
        blue.box([0, 3.5, 4], [W + 0.04, 0.6, 6])
        light.box([0.9, 2.6, -10.42], [0.4, 0.16, 0.04])
        light.box([-0.9, 2.6, -10.42], [0.4, 0.16, 0.04])
        let e = entity([(silver, LampMaterial.metal(NSColor(white: 0.78, alpha: 1), rough: 0.3)), (black, LampMaterial.paint(NSColor(white: 0.06, alpha: 1))),
                        (blue, LampMaterial.paint(livery)), (win, glass), (under, dark),
                        (light, LampMaterial.glow(NSColor(red: 1, green: 0.95, blue: 0.85, alpha: 1), strength: 5))])
        return (e, L, W)
    }

    static func coach(livery: NSColor = NSColor(red: 0.62, green: 0.08, blue: 0.1, alpha: 1),
                      trim: NSColor = NSColor(white: 0.25, alpha: 1)) -> (Entity, Float, Float) {
        let L: Float = 25, W: Float = 3.05
        var silver = MeshKit(), win = MeshKit(), stripes = MeshKit(), red = MeshKit(), under = MeshKit()
        running(&under, length: L, centers: 8.6, frameTop: 1.4)
        silver.box([0, 2.85, 0], [W, 2.9, L - 0.6])
        silver.taper([0, 4.3, 0], bottom: [W, L - 0.6], top: [W - 1.0, L - 0.8], height: 0.3)
        for x: Float in [-1, 1] {
            win.box([x * (W / 2 + 0.01), 3.25, 0], [0.04, 0.75, L - 3])
            stripes.box([x * (W / 2 + 0.01), 2.25, 0], [0.04, 0.12, L - 1])
            red.box([x * (W / 2 + 0.01), 2.05, 0], [0.04, 0.1, L - 1])
        }
        let e = entity([(silver, LampMaterial.metal(NSColor(white: 0.8, alpha: 1), rough: 0.3)), (win, glass),
                        (stripes, LampMaterial.paint(livery)),
                        (red, LampMaterial.paint(trim)), (under, dark)])
        return (e, L, W)
    }

    /// A long-distance train: a locomotive and four coaches.
    static func intercity() -> [(Entity, Float, Float)] {
        [locomotive(), coach(), coach(), coach(), coach()]
    }

    /// A regional passenger train: green and yellow, three coaches.
    static func passenger() -> [(Entity, Float, Float)] {
        let green = NSColor(red: 0.08, green: 0.4, blue: 0.22, alpha: 1), yellow = NSColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1)
        return [locomotive(livery: green), coach(livery: green, trim: yellow), coach(livery: green, trim: yellow), coach(livery: green, trim: yellow)]
    }

    /// A short train on its own, for looking at.
    static func sample(_ cars: [(Entity, Float, Float)]) -> Entity {
        let root = Entity()
        var z: Float = 0
        for (e, l, _) in cars.prefix(3) {
            e.position = [0, 0, z + l / 2]
            root.addChild(e)
            z += l + 1.2
        }
        return root
    }
}
