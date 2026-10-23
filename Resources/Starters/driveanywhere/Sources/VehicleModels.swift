import SwiftUI
import RealityKit

/// How a vehicle drives: top speed and pull (m/s, m/s²), how hard its tyres hold sideways, how sharply it
/// steers, and its weight.
struct Handling {
    let top: Float
    let accel: Float
    let grip: Float
    let steer: Float
    let mass: Float

    static let standard = Handling(top: 44, accel: 9, grip: 9, steer: 1, mass: 1550)
}

extension CarStyle {
    var handling: Handling {
        switch self {
        case .sedan, .taxi: Handling(top: 42, accel: 8.5, grip: 9, steer: 1, mass: 1400)
        case .suv: Handling(top: 38, accel: 7, grip: 7.5, steer: 0.9, mass: 1900)
        case .hatch: Handling(top: 40, accel: 8.5, grip: 9.5, steer: 1.1, mass: 1200)
        case .sports: Handling(top: 64, accel: 15, grip: 11.5, steer: 1.15, mass: 1300)
        case .pickup: Handling(top: 40, accel: 7.5, grip: 7, steer: 0.85, mass: 2300)
        case .van: Handling(top: 38, accel: 6.5, grip: 7.5, steer: 0.85, mass: 2100)
        case .police: Handling(top: 54, accel: 11.5, grip: 10, steer: 1.05, mass: 1700)
        case .ambulance: Handling(top: 44, accel: 7, grip: 7, steer: 0.75, mass: 3800)
        case .boxTruck: Handling(top: 30, accel: 4.5, grip: 6, steer: 0.62, mass: 7000)
        case .bus: Handling(top: 26, accel: 3.5, grip: 6, steer: 0.5, mass: 13000)
        case .bulldozer: Handling(top: 9, accel: 2.5, grip: 14, steer: 1.4, mass: 18000)
        case .excavator: Handling(top: 6, accel: 2, grip: 14, steer: 1.3, mass: 22000)
        case .dumpTruck: Handling(top: 28, accel: 3.5, grip: 6, steer: 0.55, mass: 15000)
        case .cementMixer: Handling(top: 26, accel: 3.2, grip: 6, steer: 0.55, mass: 14000)
        case .fireTruck: Handling(top: 40, accel: 6, grip: 7, steer: 0.6, mass: 16000)
        case .garbageTruck: Handling(top: 28, accel: 3.8, grip: 6, steer: 0.55, mass: 13000)
        case .monsterTruck: Handling(top: 46, accel: 10, grip: 6.5, steer: 0.85, mass: 4500)
        case .limo: Handling(top: 40, accel: 6.5, grip: 8, steer: 0.6, mass: 2600)
        case .golfCart: Handling(top: 11, accel: 3.5, grip: 8, steer: 1.2, mass: 450)
        case .iceCream: Handling(top: 32, accel: 5.5, grip: 7, steer: 0.8, mass: 2400)
        case .supercar: Handling(top: 78, accel: 19, grip: 12.5, steer: 1.2, mass: 1350)
        }
    }

    var name: String {
        switch self {
        case .sedan: "Sedan"
        case .suv: "SUV"
        case .hatch: "Hatchback"
        case .sports: "Sports Car"
        case .pickup: "Pickup Truck"
        case .van: "Minivan"
        case .taxi: "Taxi"
        case .police: "Police Cruiser"
        case .ambulance: "Ambulance"
        case .boxTruck: "Box Truck"
        case .bus: CityConfig.current.busName
        case .bulldozer: "Bulldozer"
        case .excavator: "Excavator"
        case .dumpTruck: "Dump Truck"
        case .cementMixer: "Cement Mixer"
        case .fireTruck: "Fire Truck"
        case .garbageTruck: "Garbage Truck"
        case .monsterTruck: "Monster Truck"
        case .limo: "Stretch Limo"
        case .golfCart: "Golf Cart"
        case .iceCream: "Ice Cream Truck"
        case .supercar: "Supercar"
        }
    }

    /// Paint that comes with the job.
    var fixedColor: NSColor? {
        switch self {
        case .taxi: NSColor(red: 0.98, green: 0.78, blue: 0.08, alpha: 1)
        case .police: NSColor(white: 0.06, alpha: 1)
        case .ambulance: NSColor(white: 0.96, alpha: 1)
        case .bus: NSColor(red: 0.04, green: 0.2, blue: 0.45, alpha: 1)
        case .bulldozer, .excavator, .dumpTruck: NSColor(red: 0.98, green: 0.72, blue: 0.05, alpha: 1)
        case .fireTruck: NSColor(red: 0.8, green: 0.05, blue: 0.05, alpha: 1)
        case .garbageTruck: NSColor(red: 0.15, green: 0.45, blue: 0.2, alpha: 1)
        case .limo: NSColor(white: 0.04, alpha: 1)
        case .golfCart: NSColor(white: 0.95, alpha: 1)
        case .iceCream: NSColor(red: 1, green: 0.72, blue: 0.82, alpha: 1)
        default: nil
        }
    }

    /// What G does in this vehicle, worded for the moment (nil: nothing).
    func actionName(on: Bool) -> String? {
        switch self {
        case .dumpTruck: on ? "Lower the bed" : "Tip the bed"
        case .fireTruck: on ? "Lower the ladder" : "Raise the ladder"
        case .bulldozer: on ? "Lower the blade" : "Raise the blade"
        case .cementMixer: on ? "Stop pouring" : "Pour"
        case .iceCream: "Play the tune"
        case .taxi: on ? "Light on" : "Light off"
        default: nil
        }
    }

    /// How deep the engine sounds.
    var enginePitch: Double {
        switch self {
        case .sports: 1.35
        case .supercar: 1.6
        case .golfCart: 2.2
        case .monsterTruck: 0.8
        case .police: 1.15
        case .limo: 0.9
        case .bus, .boxTruck, .dumpTruck, .cementMixer, .fireTruck, .garbageTruck: 0.6
        case .bulldozer, .excavator: 0.5
        default: 1
        }
    }

    var flashes: Bool { self == .police || self == .ambulance || self == .fireTruck }

    static func pick(_ weights: [(CarStyle, Int)], _ roll: Int) -> CarStyle {
        let total = weights.reduce(0) { $0 + $1.1 }
        var r = abs(roll) % total
        for (s, w) in weights { if r < w { return s }; r -= w }
        return .sedan
    }

    /// Mostly ordinary cars; police, fire trucks, limos, monster trucks and construction machines are rare events.
    static func randomTraffic() -> CarStyle {
        pick([(.sedan, 240), (.suv, 180), (.hatch, 120), (.van, 80), (.pickup, 100), (.taxi, 40), (.sports, 50),
              (.boxTruck, 50), (.bus, 35), (.garbageTruck, 8), (.supercar, 5), (.police, 8), (.ambulance, 4),
              (.iceCream, 2), (.dumpTruck, 3), (.cementMixer, 3), (.fireTruck, 2), (.limo, 2), (.monsterTruck, 1), (.golfCart, 1),
              (.bulldozer, 1)],
             Int.random(in: 0..<10000))
    }

    /// Parked: ordinary cars and vans, with the odd sports car; no police, fire trucks, limos, monster trucks or machines.
    static func parked(_ seed: Int) -> CarStyle {
        pick([(.sedan, 260), (.suv, 180), (.hatch, 140), (.van, 80), (.pickup, 100), (.sports, 40), (.taxi, 15), (.boxTruck, 15),
              (.supercar, 4), (.iceCream, 2), (.golfCart, 2)], seed)
    }

    /// A colour for a new one.
    func paint(_ seed: Int) -> NSColor {
        if let c = fixedColor { return c }
        if self == .sports || self == .supercar || self == .monsterTruck {
            let bright = [NSColor(red: 0.85, green: 0.05, blue: 0.05, alpha: 1), NSColor(red: 1, green: 0.75, blue: 0, alpha: 1),
                          NSColor(red: 0.95, green: 0.4, blue: 0, alpha: 1), NSColor(red: 0.05, green: 0.35, blue: 0.85, alpha: 1),
                          NSColor(red: 0.15, green: 0.7, blue: 0.3, alpha: 1)]
            return bright[abs(seed) % bright.count]
        }
        return CarFactory.colors[abs(seed) % CarFactory.colors.count]
    }
}

@MainActor
enum VehicleModels {
    private static var meshes: [CarStyle: [(MeshResource, Int, String)]] = [:]     // mesh, material slot, name
    static let lightOff: PhysicallyBasedMaterial = {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: NSColor(white: 0.2, alpha: 1))
        m.roughness = .init(floatLiteral: 0.3)
        return m
    }()
    static let red = LampMaterial.glow(NSColor(red: 1, green: 0.05, blue: 0.05, alpha: 1), strength: 8)
    static let blue = LampMaterial.glow(NSColor(red: 0.1, green: 0.3, blue: 1, alpha: 1), strength: 8)
    static let white = LampMaterial.plastic(NSColor(white: 0.96, alpha: 1))
    static let crossRed = LampMaterial.plastic(NSColor(red: 0.85, green: 0.08, blue: 0.08, alpha: 1))
    static let lightBlue = LampMaterial.paint(NSColor(red: 0.35, green: 0.7, blue: 0.95, alpha: 1))

    static let steel = LampMaterial.metal(NSColor(white: 0.6, alpha: 1), rough: 0.35)
    static let orange = LampMaterial.paint(NSColor(red: 1, green: 0.45, blue: 0.05, alpha: 1))

    /// Material slots: 0 paint, 1 glass, 2 dark, 3 headlights, 4 tail lights, 5 white, 6 red, 7 light blue, 8 steel, 9 orange.
    private static func material(_ slot: Int, paint: NSColor) -> RealityKit.Material {
        switch slot {
        case 0: CarFactory.paint(paint)
        case 1: CarFactory.glass
        case 2: CarFactory.dark
        case 3: CarFactory.headlight
        case 4: CarFactory.taillight
        case 5: white
        case 6: crossRed
        case 7: lightBlue
        case 8: steel
        default: orange
        }
    }

    static func make(_ style: CarStyle, color: NSColor) -> Entity {
        let root = Entity()
        for (mesh, slot, name) in parts(style) {
            let e = ModelEntity(mesh: mesh, materials: [material(slot, paint: color)])
            e.name = name
            if name == "moving", let hinge = Self.hinge(style) {
                // On a hinge, so it can tip, rise or lift (see `move`).
                let pivot = Entity()
                pivot.name = "hinge"
                pivot.position = hinge
                e.position = -hinge
                pivot.addChild(e)
                root.addChild(pivot)
                continue
            }
            if name == "drum" {
                // The mixer's drum turns on a tilted axle (see `spin`).
                let pivot = Entity()
                pivot.name = "drumPivot"
                pivot.position = [0, 2.35, 1.3]
                pivot.orientation = simd_quatf(angle: .pi / 2, axis: [0, 1, 0]) * simd_quatf(angle: -0.22, axis: [0, 0, 1])
                pivot.addChild(e)
                root.addChild(pivot)
                continue
            }
            root.addChild(e)
        }
        addExtras(style, to: root)
        return root
    }

    /// Light bars and roof signs, on a sedan body or one of the bigger ones.
    static func addExtras(_ style: CarStyle, to root: Entity) {
        switch style {
        case .police:
            var base = MeshKit(), doors = MeshKit(), a = MeshKit(), b = MeshKit()
            base.box([0, 1.53, 0.35], [1.2, 0.08, 0.3])
            a.box([-0.32, 1.62, 0.35], [0.5, 0.12, 0.26])
            b.box([0.32, 1.62, 0.35], [0.5, 0.12, 0.26])
            for x: Float in [-0.93, 0.93] { doors.box([x, 0.66, 0.1], [0.02, 0.5, 1.9]) }
            add(root, base, CarFactory.dark, "lightbar")
            add(root, doors, white, "doors")
            add(root, a, red, "lightA")
            add(root, b, blue, "lightB")
        case .taxi:
            var sign = MeshKit()
            sign.box([0, 1.6, 0.4], [0.7, 0.2, 0.25])
            add(root, sign, LampMaterial.glow(NSColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), strength: 1.5), "sign")
            var checks = MeshKit()
            for x: Float in [-0.93, 0.93] { for k in 0..<8 where k % 2 == 0 { checks.box([x, 0.85, -1.4 + Float(k) * 0.4], [0.02, 0.1, 0.4]) } }
            add(root, checks, CarFactory.paint(NSColor(white: 0.05, alpha: 1)), "checks")
        default: break
        }
    }

    private static func add(_ root: Entity, _ kit: MeshKit, _ m: RealityKit.Material, _ name: String) {
        guard let mesh = kit.mesh() else { return }
        let e = ModelEntity(mesh: mesh, materials: [m])
        e.name = name
        root.addChild(e)
    }

    /// Where a vehicle's moving part turns: the dump truck's bed and the fire truck's ladder at their back ends,
    /// the bulldozer's blade on its arms.
    static func hinge(_ style: CarStyle) -> SIMD3<Float>? {
        let L = CarFactory.size(style).x
        switch style {
        case .dumpTruck: return [0, 1.25, L / 2 - 0.1]
        case .fireTruck: return [0, 3.05, L / 2 - 0.8]
        case .bulldozer: return [0, 0.9, -L / 2 + 1.3]
        default: return nil
        }
    }

    /// Tips the bed, raises the ladder or lifts the blade: `amount` from 0 (down) to 1 (all the way).
    static func move(_ root: Entity, style: CarStyle, amount: Float) {
        guard let hinge = root.findEntity(named: "hinge") else { return }
        let angle: Float = style == .dumpTruck ? 0.95 : (style == .fireTruck ? 0.75 : 0.35)
        hinge.orientation = simd_quatf(angle: angle * amount, axis: [1, 0, 0])
    }

    /// The taxi's roof light on or off.
    static func sign(_ root: Entity, on: Bool) {
        (root.findEntity(named: "sign") as? ModelEntity)?.model?.materials = [on ? LampMaterial.glow(NSColor(red: 1, green: 0.95, blue: 0.7, alpha: 1), strength: 1.5) : lightOff]
    }

    /// The cement mixer's drum, turning.
    static func spin(_ root: Entity, by angle: Float) {
        guard let drum = root.findEntity(named: "drum") else { return }
        drum.orientation = simd_quatf(angle: angle, axis: [1, 0, 0]) * drum.orientation
    }

    /// Lights on emergency vehicles take turns.
    static func flash(_ root: Entity, phase: Bool) {
        (root.findEntity(named: "lightA") as? ModelEntity)?.model?.materials = [phase ? red : lightOff]
        (root.findEntity(named: "lightB") as? ModelEntity)?.model?.materials = [phase ? lightOff : (root.findEntity(named: "doors") != nil ? blue : red)]
    }


    private static func parts(_ style: CarStyle) -> [(MeshResource, Int, String)] {
        if let m = meshes[style] { return m }
        let s = CarFactory.size(style)
        let L = s.x, W = s.y
        var k = [MeshKit](repeating: MeshKit(), count: 10)
        var drum = MeshKit(), moving = MeshKit()       // `moving`: a bed, ladder or blade on a hinge
        func tracks(_ len: Float, _ h: Float) {
            for x in [-W / 2 + 0.35, W / 2 - 0.35] {
                k[2].box([x, h / 2, 0], [0.7, h, len])
                for z in stride(from: -len / 2 + 0.4, through: len / 2 - 0.4, by: 0.8) { k[2].wheel([x, 0.32, z], radius: 0.3, width: 0.72, segments: 10) }
            }
        }
        var lightA = MeshKit(), lightB = MeshKit()
        func wheels(_ r: Float, _ axles: [Float], width: Float = 0.28) {
            for z in axles { for x in [-W / 2 + 0.12, W / 2 - 0.12] { k[2].wheel([x, r, z], radius: r, width: width) } }
        }
        func lights(front fy: Float, rear ry: Float, inset: Float = 0.3) {
            for x in [-W / 2 + inset, W / 2 - inset] {
                k[3].box([x, fy, -L / 2 - 0.01], [0.36, 0.14, 0.04])
                k[4].box([x, ry, L / 2 + 0.01], [0.3, 0.16, 0.04])
            }
        }
        switch style {
        case .sports:
            // Low and wide, a long nose, a fastback cabin, a wing.
            k[0].box([0, 0.5, 0.1], [W, 0.5, L - 0.6])
            k[0].box([0, 0.45, -L / 2 + 0.35], [W - 0.1, 0.36, 0.7])
            k[0].box([0, 0.5, L / 2 - 0.2], [W - 0.06, 0.5, 0.4])
            k[1].taper([0, 0.75, 0.35], bottom: [W - 0.2, 2.1], top: [W - 0.6, 1.0], height: 0.36, topShift: 0.25)
            k[0].box([0, 1.12, 0.6], [W - 0.62, 0.04, 0.95])
            k[2].box([0, 1.0, L / 2 - 0.25], [W - 0.2, 0.05, 0.3])
            for x: Float in [-0.65, 0.65] { k[2].box([x, 0.87, L / 2 - 0.25], [0.05, 0.22, 0.08]) }
            k[2].box([0, 0.28, 0], [W - 0.2, 0.1, L - 0.6])
            wheels(0.34, [-1.35, 1.35], width: 0.32)
            lights(front: 0.6, rear: 0.66)
        case .pickup:
            // A cab up front, an open bed behind.
            k[0].box([0, 0.78, 0], [W, 0.6, L - 0.3])
            k[0].box([0, 1.2, -1.1], [W, 0.25, 2.6])
            k[1].taper([0, 1.32, -0.9], bottom: [W - 0.1, 1.9], top: [W - 0.3, 1.4], height: 0.58, topShift: 0.15)
            k[0].box([0, 1.93, -0.82], [W - 0.32, 0.06, 1.42])
            for x in [-W / 2 + 0.05, W / 2 - 0.05] { k[0].box([x, 1.2, 1.3], [0.1, 0.25, 2.5]) }
            k[0].box([0, 1.2, L / 2 - 0.08], [W, 0.25, 0.1])
            k[2].box([0, 1.09, 1.3], [W - 0.2, 0.02, 2.5])
            k[2].box([0, 0.5, -L / 2], [W, 0.25, 0.14])
            k[2].box([0, 0.5, L / 2], [W, 0.25, 0.14])
            wheels(0.42, [-1.75, 1.7])
            lights(front: 1.05, rear: 1.15, inset: 0.15)
        case .van:
            k[0].box([0, 0.85, 0.1], [W, 0.9, L - 0.6])
            k[0].box([0, 0.75, -L / 2 + 0.3], [W - 0.1, 0.7, 0.6])
            k[1].taper([0, 1.3, 0.25], bottom: [W - 0.04, L - 1.5], top: [W - 0.2, L - 2.0], height: 0.55, topShift: 0.25)
            k[0].box([0, 1.88, 0.5], [W - 0.2, 0.06, L - 2.1])
            k[2].box([0, 0.3, 0], [W - 0.2, 0.1, L - 0.6])
            wheels(0.36, [-1.6, 1.55])
            lights(front: 0.95, rear: 1.15)
        case .ambulance:
            // A van cab and a tall white box, a red stripe and crosses, lights all round.
            k[0].box([0, 1.05, -L / 2 + 1.05], [W - 0.1, 1.1, 2.1])
            k[1].taper([0, 1.6, -L / 2 + 1.3], bottom: [W - 0.15, 1.4], top: [W - 0.3, 1.0], height: 0.55, topShift: 0.2)
            k[0].box([0, 2.18, -L / 2 + 1.4], [W - 0.3, 0.06, 1.0])
            k[0].box([0, 1.9, 1.05], [W, 2.2, L - 2.2])
            k[6].box([0, 1.25, 1.05], [W + 0.02, 0.22, L - 2.2])
            k[6].box([0, 1.25, -L / 2 + 1.05], [W - 0.08, 0.22, 2.1])
            for x: Float in [-1, 1] {
                k[6].box([x * (W / 2 + 0.015), 2.2, 1.3], [0.02, 0.8, 0.25])
                k[6].box([x * (W / 2 + 0.015), 2.2, 1.3], [0.02, 0.25, 0.8])
            }
            k[2].box([0, 0.45, 0], [W - 0.2, 0.2, L - 0.4])
            wheels(0.42, [-L / 2 + 1.1, L / 2 - 1.3])
            lights(front: 0.95, rear: 1.2, inset: 0.25)
            lightA.box([-0.5, 3.04, -L / 2 + 2.2], [0.5, 0.1, 0.2])
            lightA.box([0.9, 3.04, L / 2 - 0.15], [0.2, 0.1, 0.2])
            lightB.box([0.5, 3.04, -L / 2 + 2.2], [0.5, 0.1, 0.2])
            lightB.box([-0.9, 3.04, L / 2 - 0.15], [0.2, 0.1, 0.2])
        case .boxTruck:
            // A cab and a big white cargo box on a long chassis.
            k[0].box([0, 1.3, -L / 2 + 1.1], [W - 0.1, 1.5, 2.2])
            k[1].box([0, 1.75, -L / 2 - 0.01], [W - 0.4, 0.6, 0.04])
            for x: Float in [-1, 1] { k[1].box([x * (W / 2 - 0.04), 1.75, -L / 2 + 0.8], [0.04, 0.55, 0.9]) }
            k[5].box([0, 2.2, 1.15], [W, 2.6, L - 2.3])
            k[2].box([0, 0.65, 0.3], [W - 0.4, 0.3, L - 0.6])
            k[2].box([0, 0.75, L / 2], [W, 0.2, 0.12])
            wheels(0.5, [-L / 2 + 1.2, L / 2 - 2.0, L / 2 - 0.9], width: 0.34)
            lights(front: 1.0, rear: 0.85, inset: 0.3)
        case .bus:
            // A city bus: a long navy body, a band of windows, a light-blue sweep.
            k[0].box([0, 1.75, 0], [W, 2.7, L - 0.1])
            for x: Float in [-1, 1] { k[1].box([x * (W / 2 + 0.01), 2.15, 0.3], [0.03, 1.05, L - 1.6]) }
            k[1].box([0, 2.1, -L / 2 - 0.01], [W - 0.2, 1.3, 0.04])
            k[7].box([0, 1.2, 0], [W + 0.03, 0.35, L - 0.4])
            k[2].box([0, 0.5, 0], [W + 0.02, 0.18, L - 0.2])
            k[2].box([0, 3.2, 2], [1.4, 0.2, 3])                 // roof unit
            wheels(0.5, [-L / 2 + 2.6, L / 2 - 3.2], width: 0.34)
            lights(front: 0.9, rear: 1.2, inset: 0.3)
            k[3].box([0, 2.95, -L / 2 - 0.02], [1.4, 0.18, 0.04])  // destination sign
        case .bulldozer:
            tracks(L - 0.6, 0.85)
            k[0].box([0, 1.35, 0.6], [W - 0.6, 1.0, L - 2.0])               // engine body
            k[1].box([0, 2.4, 1.0], [1.6, 1.1, 1.6])                        // cab
            k[0].box([0, 3.0, 1.0], [1.8, 0.08, 1.8])
            k[2].post([0.6, 1.85, -0.3], radius: 0.08, height: 1.0)         // exhaust
            moving.box([0, 0.75, -L / 2 - 0.15], [W + 0.4, 1.3, 0.25])      // blade
            for x: Float in [-0.9, 0.9] { moving.box([x, 0.9, -L / 2 + 0.6], [0.15, 0.2, 1.4]) }
            lights(front: 1.7, rear: 1.5, inset: 0.6)
        case .excavator:
            tracks(L - 1.6, 0.9)
            k[2].box([0, 1.05, 0], [2.2, 0.3, 2.2])                         // turntable
            k[0].box([0, 1.7, 0.6], [W - 0.2, 1.1, 3.0])                    // house
            k[1].box([-0.75, 2.2, -0.6], [1.0, 1.6, 1.2])                   // cab
            k[0].box([0.35, 2.6, -1.6], [0.45, 0.45, 3.0], rot: simd_quatf(angle: 0.55, axis: [1, 0, 0]))   // boom
            k[0].box([0.35, 2.9, -3.4], [0.35, 0.35, 2.2], rot: simd_quatf(angle: -0.9, axis: [1, 0, 0]))   // stick
            k[2].box([0.35, 1.2, -3.9], [1.0, 0.7, 0.6])                    // bucket
            lights(front: 1.9, rear: 1.6, inset: 0.6)
        case .dumpTruck:
            k[0].box([0, 1.6, -L / 2 + 1.2], [W - 0.1, 1.8, 2.4])           // cab
            k[1].box([0, 2.0, -L / 2 - 0.01], [W - 0.4, 0.7, 0.04])
            k[2].box([0, 0.9, 0.5], [W - 0.5, 0.4, L - 1])                  // chassis
            moving.box([0, 1.25, 1.3], [W, 0.15, L - 2.8])                  // bed floor
            for x in [-W / 2 + 0.06, W / 2 - 0.06] { moving.box([x, 2.05, 1.3], [0.12, 1.5, L - 2.8]) }
            moving.box([0, 2.05, L / 2 - 0.06], [W, 1.5, 0.12])
            moving.box([0, 2.3, -L / 2 + 2.7], [W, 2.0, 0.12])
            wheels(0.6, [-L / 2 + 1.3, L / 2 - 2.3, L / 2 - 1.0], width: 0.45)
            lights(front: 1.2, rear: 1.2, inset: 0.3)
        case .cementMixer:
            k[0].box([0, 1.5, -L / 2 + 1.1], [W - 0.1, 1.7, 2.2])
            k[1].box([0, 1.9, -L / 2 - 0.01], [W - 0.4, 0.7, 0.04])
            k[2].box([0, 0.9, 0.5], [W - 0.5, 0.4, L - 1])
            for z: Float in [-0.4, 3.0] { k[8].box([0, 1.6, z], [W - 0.6, 1.1, 0.2]) }   // drum cradle
            k[9].box([0, 3.0, L / 2 - 0.3], [0.5, 0.15, 0.8], rot: simd_quatf(angle: 0.6, axis: [1, 0, 0]))      // chute
            // The drum, round its own axle along x (turned to lie along the truck by its pivot).
            drum.wheel([0, 0, 0], radius: 1.15, width: 3.0, segments: 18)
            drum.wheel([1.9, 0, 0], radius: 0.7, width: 0.9, segments: 14)
            drum.box([-0.2, 1.16, 0], [2.6, 0.06, 0.3])                      // a stripe to see it turn
            wheels(0.55, [-L / 2 + 1.2, L / 2 - 2.0, L / 2 - 0.9], width: 0.42)
            lights(front: 1.2, rear: 1.1, inset: 0.3)
        case .fireTruck:
            k[0].box([0, 1.6, -L / 2 + 1.3], [W, 1.9, 2.6])                 // cab
            k[1].box([0, 2.0, -L / 2 - 0.01], [W - 0.3, 0.75, 0.04])
            for x: Float in [-1, 1] { k[1].box([x * (W / 2 + 0.01), 2.0, -L / 2 + 1.0], [0.03, 0.7, 1.6]) }
            k[0].box([0, 1.7, 1.2], [W, 2.2, L - 2.6])                      // body with lockers
            for x: Float in [-1, 1] { for z in stride(from: Float(-1.2), through: 3.6, by: 1.2) { k[8].box([x * (W / 2 + 0.01), 1.6, z], [0.02, 1.4, 1.0]) } }
            k[5].box([0, 1.0, 1.2], [W + 0.03, 0.12, L - 2.6])              // white band
            for x: Float in [-0.45, 0.45] { moving.box([x, 3.05, 0.8], [0.12, 0.12, L - 1.6]) }   // ladder rails
            for z in stride(from: -L / 2 + 1.2, through: L / 2 - 0.6, by: 0.5) { moving.box([0, 3.05, z], [0.9, 0.06, 0.06]) }
            k[2].box([0, 0.55, 0], [W - 0.2, 0.25, L - 0.4])
            wheels(0.55, [-L / 2 + 1.4, L / 2 - 2.2, L / 2 - 1.0], width: 0.4)
            lights(front: 1.1, rear: 1.2, inset: 0.3)
            lightA.box([-0.6, 2.62, -L / 2 + 1.3], [0.7, 0.14, 0.25])
            lightB.box([0.6, 2.62, -L / 2 + 1.3], [0.7, 0.14, 0.25])
        case .garbageTruck:
            k[5].box([0, 1.5, -L / 2 + 1.1], [W, 1.8, 2.2])                 // white cab
            k[1].box([0, 1.95, -L / 2 - 0.01], [W - 0.3, 0.7, 0.04])
            k[0].box([0, 1.95, 1.0], [W, 2.6, L - 2.4])                     // packer body
            k[0].box([0, 1.8, L / 2 - 0.5], [W - 0.1, 2.4, 1.0])            // hopper
            k[2].box([0, 1.0, L / 2 + 0.02], [W - 0.4, 0.6, 0.06])
            k[2].box([0, 0.6, 0], [W - 0.4, 0.3, L - 0.6])
            wheels(0.55, [-L / 2 + 1.2, L / 2 - 2.4, L / 2 - 1.2], width: 0.42)
            lights(front: 1.2, rear: 2.6, inset: 0.3)
        case .monsterTruck:
            // A pickup up on huge tyres.
            let lift: Float = 1.3
            k[0].box([0, 0.78 + lift, 0], [W - 0.8, 0.6, L - 0.4])
            k[0].box([0, 1.2 + lift, -0.9], [W - 0.8, 0.25, 2.4])
            k[1].taper([0, 1.32 + lift, -0.8], bottom: [W - 0.9, 1.8], top: [W - 1.1, 1.3], height: 0.55, topShift: 0.15)
            k[0].box([0, 1.9 + lift, -0.72], [W - 1.1, 0.06, 1.3])
            k[2].box([0, 1.3, 0], [0.4, 0.4, L - 0.8])                      // chassis
            for x: Float in [-0.9, 0.9] { k[8].box([x, 1.4, 0], [0.1, 0.8, 0.1]) }
            for x in [-W / 2 + 0.38, W / 2 - 0.38] { for z: Float in [-1.6, 1.6] {
                k[2].wheel([x, 0.95, z], radius: 0.95, width: 0.72, segments: 18)
                k[8].wheel([x + (x > 0 ? 0.37 : -0.37), 0.95, z], radius: 0.4, width: 0.02, segments: 12)
            } }
            for x in [-(W - 0.8) / 2 + 0.25, (W - 0.8) / 2 - 0.25] {
                k[3].box([x, 1.1 + lift - 0.1, -L / 2 + 0.19], [0.32, 0.14, 0.04])
                k[4].box([x, 1.15 + lift, L / 2 - 0.19], [0.28, 0.14, 0.04])
            }
        case .limo:
            k[0].box([0, 0.65, 0], [W, 0.65, L - 0.3])
            k[1].box([0, 1.2, 0.3], [W - 0.12, 0.45, L - 2.4])
            k[0].box([0, 1.45, 0.3], [W - 0.2, 0.06, L - 2.6])
            k[1].taper([0, 0.98, -L / 2 + 1.6], bottom: [W - 0.12, 0.8], top: [W - 0.2, 0.1], height: 0.45, topShift: 0.35)
            k[8].box([0, 0.5, 0], [W + 0.02, 0.06, L - 0.6])
            k[2].box([0, 0.3, 0], [W - 0.2, 0.1, L - 0.6])
            wheels(0.34, [-L / 2 + 1.0, L / 2 - 1.0])
            lights(front: 0.8, rear: 0.82)
        case .golfCart:
            k[0].box([0, 0.45, 0], [W, 0.35, L - 0.2])
            k[2].box([0, 0.8, 0.3], [W - 0.1, 0.12, 0.6])                   // seat
            k[2].box([0, 1.1, 0.6], [W - 0.1, 0.5, 0.1])
            for x in [-W / 2 + 0.08, W / 2 - 0.08] { for z: Float in [-0.55, 0.85] { k[8].box([x, 1.3, z], [0.05, 1.3, 0.05]) } }
            k[0].box([0, 1.98, 0.15], [W + 0.1, 0.06, 1.8])                 // roof
            k[1].box([0, 1.4, -0.6], [W - 0.1, 0.65, 0.03])
            wheels(0.22, [-0.8, 0.8], width: 0.18)
            lights(front: 0.55, rear: 0.55, inset: 0.2)
        case .iceCream:
            k[0].box([0, 1.25, 0.1], [W, 1.9, L - 0.4])
            k[5].box([0, 0.75, 0.1], [W + 0.02, 0.5, L - 0.4])
            k[1].taper([0, 1.45, -L / 2 + 0.8], bottom: [W - 0.1, 1.2], top: [W - 0.2, 0.8], height: 0.6, topShift: 0.2)
            k[1].box([W / 2 + 0.01, 1.6, 0.7], [0.03, 0.8, 1.8])            // serving window
            k[7].box([W / 2 + 0.25, 1.15, 0.7], [0.5, 0.06, 1.9])           // counter
            // The cone on the roof.
            k[9].taper([0, 2.25, 0.6], bottom: [0.12, 0.12], top: [0.6, 0.6], height: 0.8)
            k[5].blob([0, 3.2, 0.6], radius: 0.38)
            k[6].blob([0, 3.6, 0.6], radius: 0.12)
            k[2].box([0, 0.3, 0], [W - 0.2, 0.1, L - 0.6])
            wheels(0.38, [-1.7, 1.6])
            lights(front: 1.0, rear: 1.1)
        case .supercar:
            // Wedge-low, a glass canopy, side intakes, a tall wing.
            k[0].box([0, 0.45, 0.2], [W, 0.45, L - 0.8])
            k[0].taper([0, 0.22, -L / 2 + 0.55], bottom: [W - 0.1, 1.1], top: [W - 0.3, 0.9], height: 0.32, topShift: 0.1)
            k[1].taper([0, 0.67, 0.2], bottom: [W - 0.35, 1.9], top: [W - 0.85, 0.7], height: 0.36, topShift: 0.45)
            for x: Float in [-1, 1] { k[2].box([x * (W / 2 + 0.005), 0.55, 0.9], [0.02, 0.22, 0.7]) }
            k[2].box([0, 1.12, L / 2 - 0.25], [W - 0.1, 0.05, 0.38])
            for x: Float in [-0.7, 0.7] { k[2].box([x, 0.88, L / 2 - 0.25], [0.05, 0.42, 0.1]) }
            k[2].box([0, 0.22, 0], [W - 0.2, 0.08, L - 0.6])
            wheels(0.34, [-1.4, 1.45], width: 0.34)
            lights(front: 0.5, rear: 0.58)
        default: break
        }
        var out: [(MeshResource, Int, String)] = []
        let names = ["body", "glass", "dark", "front", "rear", "white", "red", "trim", "steel", "orange"]
        for (i, kit) in k.enumerated() { if let m = kit.mesh() { out.append((m, i, names[i])) } }
        meshes[style] = out
        if let a = lightA.mesh(), let b = lightB.mesh() { out += [(a, 6, "lightA"), (b, 6, "lightB")] }
        if let d = drum.mesh() { out.append((d, 8, "drum")) }
        if let m = moving.mesh() { out.append((m, style == .fireTruck ? 8 : 0, "moving")) }
        meshes[style] = out
        return out
    }
}
