import SwiftUI
import RealityKit

/// The ways people get about besides walking, bikes and scooters.
enum RideKind: CaseIterable {
    case bike, scooter, hoverboard, unicycle, skateboard, wheelboard, rollerblades

    /// Cruising speed, metres a second.
    var speeds: ClosedRange<Float> {
        switch self {
        case .bike: 4...6.5
        case .scooter: 3.5...5.5
        case .hoverboard: 2.5...3.8
        case .unicycle: 2.2...3.2
        case .skateboard: 3.2...4.8
        case .wheelboard: 4...6
        case .rollerblades: 3...4.5
        }
    }

    var title: String {
        switch self {
        case .bike: "bike"
        case .scooter: "scooter"
        case .hoverboard: "hoverboard"
        case .unicycle: "unicycle"
        case .skateboard: "skateboard"
        case .wheelboard: "One-wheel board"
        case .rollerblades: "rollerblades"
        }
    }

    /// Top speed and pull when you ride it, m/s and m/s².
    var playerTop: Float {
        switch self {
        case .bike: 12; case .scooter: 9; case .hoverboard: 5.5; case .unicycle: 4.5
        case .skateboard: 7.5; case .wheelboard: 9; case .rollerblades: 7
        }
    }
    var playerAccel: Float {
        switch self {
        case .bike: 3; case .scooter: 3.5; case .hoverboard: 2.5; case .unicycle: 1.8
        case .skateboard: 2.5; case .wheelboard: 3.2; case .rollerblades: 2.8
        }
    }

    /// How fast the legs go round for a given speed.
    var cadence: Float {
        switch self {
        case .bike: 2.4
        case .unicycle: 3.2
        case .rollerblades: 1.6
        case .skateboard: 0.9
        default: 1.2
        }
    }
}

@MainActor
enum RideModels {
    private static func mat(_ c: NSColor, rough: Float = 0.5, metal: Float = 0, glow: Float = 0) -> PhysicallyBasedMaterial {
        var m = PhysicallyBasedMaterial()
        m.baseColor = .init(tint: c)
        m.roughness = .init(floatLiteral: rough)
        m.metallic = .init(floatLiteral: metal)
        if glow > 0 { m.emissiveColor = .init(color: c); m.emissiveIntensity = glow }
        return m
    }

    private static func entity(_ parts: [(MeshKit, PhysicallyBasedMaterial)]) -> Entity {
        let root = Entity()
        for (kit, m) in parts { if let mesh = kit.mesh() { root.addChild(ModelEntity(mesh: mesh, materials: [m])) } }
        return root
    }

    private static let rubber = mat(NSColor(white: 0.06, alpha: 1), rough: 0.9)
    private static let bright: [NSColor] = [
        NSColor(red: 0.9, green: 0.15, blue: 0.2, alpha: 1), NSColor(red: 0.15, green: 0.5, blue: 0.95, alpha: 1),
        NSColor(red: 0.2, green: 0.8, blue: 0.5, alpha: 1), NSColor(red: 1, green: 0.75, blue: 0.1, alpha: 1),
        NSColor(red: 0.65, green: 0.3, blue: 0.9, alpha: 1), NSColor(white: 0.92, alpha: 1), NSColor(white: 0.12, alpha: 1),
    ]

    /// The machine for a kind, facing -z on the ground. Rollerblades go on the rider's feet.
    static func make(_ kind: RideKind, legs: [Entity]) -> Entity {
        let colour = bright.randomElement()!
        switch kind {
        case .hoverboard:
            // Two wheels side by side, a deck between them with glowing strips.
            var body = MeshKit(), wheels = MeshKit(), lights = MeshKit()
            body.box([0, 0.15, 0], [0.62, 0.07, 0.2])
            for x: Float in [-0.33, 0.33] {
                wheels.wheel([x, 0.1, 0], radius: 0.1, width: 0.07, segments: 14)
                body.box([x, 0.17, 0], [0.12, 0.12, 0.24])               // fenders
            }
            lights.box([0, 0.15, -0.105], [0.5, 0.025, 0.01])
            lights.box([0, 0.15, 0.105], [0.5, 0.025, 0.01])
            return entity([(body, mat(colour, rough: 0.2, metal: 0.2)), (wheels, rubber),
                           (lights, mat(NSColor(red: 0.3, green: 0.8, blue: 1, alpha: 1), glow: 3))])
        case .unicycle:
            var frame = MeshKit(), wheel = MeshKit(), seat = MeshKit()
            wheel.wheel([0, 0.3, 0], radius: 0.3, width: 0.06, segments: 18)
            frame.box([0, 0.3, 0], [0.08, 0.06, 0.06])                   // hub
            for x: Float in [-0.06, 0.06] { frame.box([x, 0.6, 0], [0.025, 0.62, 0.025]) }
            frame.box([0, 0.86, 0], [0.04, 0.12, 0.04])
            seat.box([0, 0.94, 0.02], [0.12, 0.05, 0.28])
            for (x, z): (Float, Float) in [(-0.09, -0.1), (0.09, 0.1)] { frame.box([x, 0.3, z], [0.02, 0.02, 0.18]) }   // cranks
            return entity([(frame, mat(colour, rough: 0.3, metal: 0.6)), (wheel, rubber), (seat, mat(NSColor(white: 0.1, alpha: 1)))])
        case .skateboard:
            var deck = MeshKit(), trucks = MeshKit(), wheels = MeshKit()
            deck.box([0, 0.11, 0], [0.21, 0.025, 0.66])
            deck.box([0, 0.125, -0.36], [0.2, 0.02, 0.1], rot: simd_quatf(angle: -0.35, axis: [1, 0, 0]))   // kicktails
            deck.box([0, 0.125, 0.36], [0.2, 0.02, 0.1], rot: simd_quatf(angle: 0.35, axis: [1, 0, 0]))
            for z: Float in [-0.22, 0.22] {
                trucks.box([0, 0.075, z], [0.18, 0.04, 0.04])
                for x: Float in [-0.085, 0.085] { wheels.wheel([x, 0.03, z], radius: 0.03, width: 0.03, segments: 10) }
            }
            return entity([(deck, mat(colour, rough: 0.6)), (trucks, mat(NSColor(white: 0.7, alpha: 1), rough: 0.3, metal: 1)),
                           (wheels, mat(NSColor(white: 0.95, alpha: 1), rough: 0.4))])
        case .wheelboard:
            // One fat tyre through the middle of a long board, footpads either side.
            var deck = MeshKit(), tyre = MeshKit(), pads = MeshKit()
            tyre.wheel([0, 0.15, 0], radius: 0.15, width: 0.24, segments: 18)
            for z: Float in [-0.3, 0.3] {
                deck.box([0, 0.17, z], [0.24, 0.04, 0.32])
                pads.box([0, 0.195, z], [0.2, 0.012, 0.26])
            }
            for x: Float in [-0.13, 0.13] { deck.box([x, 0.17, 0], [0.025, 0.06, 0.95]) }   // rails
            deck.box([0, 0.17, -0.48], [0.22, 0.05, 0.03])
            pads.box([0, 0.17, -0.5], [0.16, 0.02, 0.01])
            return entity([(deck, mat(NSColor(white: 0.15, alpha: 1), rough: 0.4, metal: 0.5)), (tyre, rubber),
                           (pads, mat(colour, rough: 0.8))])
        case .rollerblades:
            // A boot with a row of wheels under each foot.
            for leg in legs {
                var boot = MeshKit(), wheels = MeshKit()
                boot.box([0, -0.8, -0.03], [0.15, 0.18, 0.28])
                boot.box([0, -0.9, -0.03], [0.05, 0.04, 0.3])
                for z: Float in [-0.14, -0.05, 0.04, 0.13] { wheels.wheel([0, -0.93, z - 0.03], radius: 0.035, width: 0.025, segments: 10) }
                leg.addChild(entity([(boot, mat(colour, rough: 0.4)), (wheels, mat(NSColor(red: 0.9, green: 0.9, blue: 0.3, alpha: 1), rough: 0.4))]))
            }
            return Entity()
        default:
            return Entity()
        }
    }

    /// How the rider stands or sits, moving with `phase`.
    static func pose(_ figure: Entity, _ legs: [Entity], _ arms: [Entity], kind: RideKind, phase: Float) {
        let sideways = simd_quatf(angle: .pi / 2, axis: [0, 1, 0])
        let reset = simd_quatf(angle: 0, axis: [1, 0, 0])
        switch kind {
        case .hoverboard:
            // Upright, feet apart on the pads, a gentle sway.
            figure.position = [0, 1.13, 0]
            figure.orientation = simd_quatf(angle: -0.06 + sin(phase) * 0.03, axis: [1, 0, 0])
            legs[0].orientation = simd_quatf(angle: -0.17, axis: [0, 0, 1])
            legs[1].orientation = simd_quatf(angle: 0.17, axis: [0, 0, 1])
            arms[0].orientation = simd_quatf(angle: -0.25, axis: [0, 0, 1])
            arms[1].orientation = simd_quatf(angle: 0.25, axis: [0, 0, 1])
        case .unicycle:
            // On the saddle, pedalling, arms out to balance and a wobble.
            figure.position = [0, 1.0, 0.02]
            figure.orientation = simd_quatf(angle: sin(phase * 0.7) * 0.06, axis: [0, 0, 1])
            legs[0].orientation = simd_quatf(angle: 0.1 + sin(phase) * 0.45, axis: [1, 0, 0])
            legs[1].orientation = simd_quatf(angle: 0.1 - sin(phase) * 0.45, axis: [1, 0, 0])
            arms[0].orientation = simd_quatf(angle: -1.2 + sin(phase * 0.7) * 0.2, axis: [0, 0, 1])
            arms[1].orientation = simd_quatf(angle: 1.2 + sin(phase * 0.7) * 0.2, axis: [0, 0, 1])
        case .skateboard:
            // Side-on, knees soft, now and then a push with the back foot.
            let push = max(0, sin(phase))
            figure.position = [0, 1.06 - push * 0.04, 0]
            figure.orientation = sideways * simd_quatf(angle: 0.05, axis: [1, 0, 0])
            legs[0].orientation = simd_quatf(angle: -0.22, axis: [0, 0, 1])
            legs[1].orientation = simd_quatf(angle: 0.22 + push * 0.35, axis: [0, 0, 1]) * simd_quatf(angle: -push * 0.4, axis: [1, 0, 0])
            arms[0].orientation = simd_quatf(angle: -0.5, axis: [0, 0, 1])
            arms[1].orientation = simd_quatf(angle: 0.4, axis: [0, 0, 1])
        case .wheelboard:
            // Side-on astride the tyre, carving gently.
            figure.position = [0, 1.16, 0]
            figure.orientation = sideways * simd_quatf(angle: sin(phase * 0.5) * 0.08, axis: [0, 0, 1])
            legs[0].orientation = simd_quatf(angle: -0.2, axis: [0, 0, 1])
            legs[1].orientation = simd_quatf(angle: 0.2, axis: [0, 0, 1])
            arms[0].orientation = simd_quatf(angle: -0.35, axis: [0, 0, 1])
            arms[1].orientation = simd_quatf(angle: 0.35, axis: [0, 0, 1])
        case .rollerblades:
            // Leaning in, striding out to each side in turn, arms swinging.
            let s = sin(phase)
            figure.position = [0, 1.0 - abs(s) * 0.03, 0]
            figure.orientation = simd_quatf(angle: -0.3, axis: [1, 0, 0])
            legs[0].orientation = simd_quatf(angle: -max(0, s) * 0.45, axis: [0, 0, 1]) * simd_quatf(angle: 0.25, axis: [1, 0, 0])
            legs[1].orientation = simd_quatf(angle: max(0, -s) * 0.45, axis: [0, 0, 1]) * simd_quatf(angle: 0.25, axis: [1, 0, 0])
            arms[0].orientation = simd_quatf(angle: s * 0.7, axis: [1, 0, 0])
            arms[1].orientation = simd_quatf(angle: -s * 0.7, axis: [1, 0, 0])
        default:
            figure.orientation = reset
        }
    }
}
