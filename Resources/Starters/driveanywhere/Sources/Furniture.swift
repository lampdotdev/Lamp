import SwiftUI
import RealityKit

/// The time of day where the city is, from the real clock and the sun's height there: day, dusk or dawn
/// ("sunset"), or night. Read once when the game opens.
enum DayTime {
    enum Phase { case day, sunset, night }

    /// Set to force a time of day (for looking at the city by night); nil follows the clock.
    static let override: Phase? = nil

    /// Worked out once for each place the game is set in.
    nonisolated(unsafe) private static var known: (String, Phase)?
    static var phase: Phase {
        if let override { return override }
        let key = CityConfig.current.slug
        if let k = known, k.0 == key { return k.1 }
        let e = sunElevation(Date(), lat: CityConfig.current.lat, lon: CityConfig.current.lon)
        let p: Phase = e < -6 ? .night : (e < 6 ? .sunset : .day)
        known = (key, p)
        return p
    }

    /// Street lamps and windows lit.
    static var lightsOn: Bool { phase != .day }

    /// At night the sky alone leaves the city nearly black: moonlight from high up and a soft fill from the other
    /// side, so streets and walls stay readable. Nothing by day.
    @MainActor static func extraLight() -> Entity {
        let root = Entity()
        root.name = "nightLight"
        guard phase == .night else { return root }
        let moon = DirectionalLight()
        moon.light.intensity = 2600
        moon.light.color = NSColor(red: 0.75, green: 0.82, blue: 1, alpha: 1)
        moon.look(at: .zero, from: [0.3, 0.8, -0.5], relativeTo: nil)
        root.addChild(moon)
        let fill = DirectionalLight()
        fill.light.intensity = 1400
        fill.light.color = NSColor(red: 0.7, green: 0.75, blue: 0.9, alpha: 1)
        fill.look(at: .zero, from: [-0.5, 0.35, 0.6], relativeTo: nil)
        root.addChild(fill)
        return root
    }

    static var sky: LampSky {
        switch phase {
        case .day: .day
        case .sunset: .sunset
        case .night: .night
        }
    }

    /// The sun's height above the horizon, degrees (a close approximation).
    static func sunElevation(_ date: Date, lat: Double, lon: Double) -> Double {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        let day = Double(cal.ordinality(of: .day, in: .year, for: date) ?? 1)
        let c = cal.dateComponents([.hour, .minute, .second], from: date)
        let hours = Double(c.hour ?? 0) + Double(c.minute ?? 0) / 60 + Double(c.second ?? 0) / 3600
        let rad = Double.pi / 180
        let decl = 23.44 * sin(2 * .pi * (284 + day) / 365)
        let b = 2 * Double.pi * (day - 81) / 364
        let eot = 9.87 * sin(2 * b) - 7.53 * cos(b) - 1.5 * sin(b)
        let solar = hours * 60 + lon * 4 + eot
        let hourAngle = solar / 4 - 180
        let s = sin(lat * rad) * sin(decl * rad) + cos(lat * rad) * cos(decl * rad) * cos(hourAngle * rad)
        return asin(max(-1, min(1, s))) / rad
    }
}

/// Street furniture: one model per kind, drawn as copies (one batch per kind per square).
@MainActor
enum Furniture {
    enum Kind: Int, CaseIterable {
        case lamp, hydrant, bench, bin, bikeRack, shelter, busSign, meter, pole
        case picnic, swing, slide, climber, pavilion, fountain, hoop, net
        case flag
    }

    /// How big a post each is to drive into (0: nothing to hit).
    static func postRadius(_ k: Kind) -> Float {
        switch k {
        case .lamp: 0.12
        case .hydrant: 0.2
        case .bin: 0.25
        case .meter: 0.08
        case .busSign: 0.06
        case .pole: 0.16
        case .hoop: 0.12
        case .fountain: 0.2
        default: 0
        }
    }

    private static var models: [Kind: Entity] = [:]

    /// What's left when a hydrant is knocked off: a stub of pipe.
    static let brokenHydrant: Entity = {
        var a = MeshKit()
        a.post([0, 0, 0], radius: 0.09, height: 0.14, segments: 8)
        let root = Entity()
        if let m = a.mesh() { root.addChild(ModelEntity(mesh: m, materials: [LampMaterial.metal(NSColor(white: 0.35, alpha: 1), rough: 0.6)])) }
        return root
    }()

    /// The model, front towards −z (the street), standing on its base at the origin.
    static func model(_ k: Kind) -> Entity {
        if let m = models[k] { return m }
        let m = make(k)
        models[k] = m
        return m
    }

    static let dark = LampMaterial.metal(NSColor(white: 0.18, alpha: 1), rough: 0.5)
    static let lampHead: RealityKit.Material = DayTime.lightsOn
        ? LampMaterial.glow(NSColor(red: 1, green: 0.85, blue: 0.6, alpha: 1), strength: 3)
        : LampMaterial.plastic(NSColor(white: 0.85, alpha: 1), gloss: 0.6)

    private static func make(_ k: Kind) -> Entity {
        var parts: [(MeshKit, RealityKit.Material)] = []
        var a = MeshKit(), b = MeshKit(), c = MeshKit()
        switch k {
        case .lamp:
            a.post([0, 0, 0], radius: 0.08, height: 7.2, segments: 8)
            a.box([0, 7.15, -0.8], [0.07, 0.07, 1.6])
            b.box([0, 7.05, -1.6], [0.32, 0.12, 0.62])
            parts = [(a, dark), (b, lampHead)]
        case .hydrant:
            a.post([0, 0, 0], radius: 0.13, height: 0.62, segments: 8)
            a.blob([0, 0.66, 0], radius: 0.14, scale: [1, 0.7, 1], segments: 8, rings: 3)
            a.box([0, 0.42, 0], [0.42, 0.1, 0.1])
            b.box([0, 0.42, -0.14], [0.1, 0.1, 0.1])
            parts = [(a, LampMaterial.paint(NSColor(red: 0.8, green: 0.1, blue: 0.08, alpha: 1))), (b, LampMaterial.metal(NSColor(white: 0.7, alpha: 1)))]
        case .bench:
            a.box([0, 0.45, 0], [1.7, 0.06, 0.45])
            a.box([0, 0.78, 0.22], [1.7, 0.36, 0.05])
            for x: Float in [-0.7, 0.7] { b.box([x, 0.22, 0], [0.06, 0.44, 0.4]); b.box([x, 0.6, 0.22], [0.06, 0.4, 0.05]) }
            parts = [(a, LampMaterial.wood(NSColor(red: 0.5, green: 0.33, blue: 0.2, alpha: 1))), (b, dark)]
        case .bin:
            a.post([0, 0, 0], radius: 0.26, height: 0.95, segments: 10)
            b.post([0, 0.95, 0], radius: 0.28, height: 0.06, segments: 10)
            parts = [(a, LampMaterial.paint(NSColor(red: 0.12, green: 0.26, blue: 0.16, alpha: 1))), (b, dark)]
        case .bikeRack:
            for x: Float in [-0.9, 0, 0.9] {
                for z: Float in [-0.35, 0.35] { a.box([x, 0.42, z], [0.05, 0.84, 0.05]) }
                a.box([x, 0.84, 0], [0.05, 0.05, 0.75])
            }
            parts = [(a, LampMaterial.metal(NSColor(white: 0.75, alpha: 1), rough: 0.3))]
        case .shelter:
            a.box([0, 2.5, 0], [3.4, 0.08, 1.6])
            for x: Float in [-1.65, 1.65] { for z: Float in [-0.7, 0.7] { a.box([x, 1.25, z], [0.08, 2.5, 0.08]) } }
            b.box([0, 1.3, 0.72], [3.3, 2.1, 0.03])
            for x: Float in [-1.66, 1.66] { b.box([x, 1.3, 0.2], [0.03, 2.1, 1.0]) }
            c.box([0, 0.45, 0.45], [2.4, 0.06, 0.4])
            parts = [(a, dark), (b, LampMaterial.glass(NSColor(red: 0.8, green: 0.9, blue: 1, alpha: 1), clear: 0.6)),
                     (c, LampMaterial.metal(NSColor(white: 0.6, alpha: 1)))]
        case .busSign:
            a.post([0, 0, 0], radius: 0.04, height: 2.9, segments: 6)
            b.box([0, 2.55, -0.04], [0.45, 0.6, 0.03])
            parts = [(a, LampMaterial.metal(NSColor(white: 0.6, alpha: 1))), (b, LampMaterial.paint(NSColor(red: 0.1, green: 0.3, blue: 0.65, alpha: 1)))]
        case .meter:
            a.post([0, 0, 0], radius: 0.04, height: 1.15, segments: 6)
            b.box([0, 1.3, 0], [0.22, 0.32, 0.16])
            parts = [(a, dark), (b, LampMaterial.metal(NSColor(white: 0.55, alpha: 1), rough: 0.4))]
        case .pole:
            a.post([0, 0, 0], radius: 0.14, height: 9.6, segments: 8)
            a.box([0, 9.0, 0], [2.2, 0.12, 0.12])
            b.post([-0.9, 9.06, 0], radius: 0.05, height: 0.16, segments: 6)
            b.post([0.9, 9.06, 0], radius: 0.05, height: 0.16, segments: 6)
            parts = [(a, LampMaterial.wood(NSColor(red: 0.38, green: 0.29, blue: 0.2, alpha: 1))), (b, LampMaterial.ceramic(NSColor(white: 0.85, alpha: 1)))]
        case .picnic:
            // Table and its two benches, on A-frame legs.
            a.box([0, 0.75, 0], [1.8, 0.05, 0.8])
            for z: Float in [-0.65, 0.65] { a.box([0, 0.45, z], [1.8, 0.05, 0.3]) }
            for x: Float in [-0.7, 0.7] {
                for s: Float in [-1, 1] {
                    a.box([x, 0.37, s * 0.4], [0.06, 0.8, 0.07], rot: simd_quatf(angle: s * 0.55, axis: [1, 0, 0]))
                }
                a.box([x, 0.42, 0], [0.06, 0.05, 1.6])
            }
            parts = [(a, LampMaterial.wood(NSColor(red: 0.55, green: 0.38, blue: 0.24, alpha: 1)))]
        case .swing:
            // Two A-frames, a top bar, two seats on chains.
            for x: Float in [-1.7, 1.7] {
                for s: Float in [-1, 1] { a.box([x, 1.2, s * 0.45], [0.08, 2.5, 0.08], rot: simd_quatf(angle: s * 0.36, axis: [1, 0, 0])) }
            }
            a.box([0, 2.38, 0], [3.5, 0.09, 0.09])
            for x: Float in [-0.7, 0.7] {
                for s: Float in [-0.22, 0.22] { b.box([x + s, 1.45, 0], [0.02, 1.85, 0.02]) }
                c.box([x, 0.5, 0], [0.5, 0.05, 0.2])
            }
            parts = [(a, LampMaterial.paint(NSColor(red: 0.12, green: 0.45, blue: 0.75, alpha: 1))), (b, dark),
                     (c, LampMaterial.rubber(NSColor(red: 0.1, green: 0.1, blue: 0.1, alpha: 1)))]
        case .slide:
            // A platform up a ladder, and the slide down from it.
            for x: Float in [-0.6, 0.6] { for z: Float in [-0.6, 0.6] { a.box([x, 0.9, z], [0.1, 1.8, 0.1]) } }
            a.box([0, 1.5, 0], [1.3, 0.08, 1.3])
            for k in 0..<5 { a.box([0, 0.3 + Float(k) * 0.3, 0.75], [0.6, 0.05, 0.08]) }
            b.box([0, 0.8, -1.9], [0.6, 0.06, 2.9], rot: simd_quatf(angle: -0.55, axis: [1, 0, 0]))
            for x: Float in [-0.3, 0.3] { b.box([x, 0.92, -1.9], [0.04, 0.2, 2.9], rot: simd_quatf(angle: -0.55, axis: [1, 0, 0])) }
            c.box([0, 1.85, 0], [1.4, 0.06, 1.4])
            parts = [(a, LampMaterial.paint(NSColor(red: 0.95, green: 0.75, blue: 0.1, alpha: 1))), (b, LampMaterial.plastic(NSColor(red: 0.85, green: 0.15, blue: 0.1, alpha: 1))),
                     (c, LampMaterial.plastic(NSColor(red: 0.1, green: 0.55, blue: 0.3, alpha: 1)))]
        case .climber:
            // A frame of bars to climb, a cube with a cross bar on each side.
            for x: Float in [-1, 1] { for z: Float in [-1, 1] { a.box([x, 1, z], [0.07, 2, 0.07]) } }
            for y: Float in [0.7, 1.4, 2] {
                for s: Float in [-1, 1] { a.box([0, y, s], [2, 0.06, 0.06]); a.box([s, y, 0], [0.06, 0.06, 2]) }
            }
            b.box([0, 2.02, 0], [2, 0.04, 2])
            parts = [(a, LampMaterial.paint(NSColor(red: 0.85, green: 0.2, blue: 0.15, alpha: 1))), (b, LampMaterial.plastic(NSColor(red: 0.15, green: 0.4, blue: 0.75, alpha: 1)))]
        case .pavilion:
            // A picnic shelter: posts, a pitched roof.
            for x: Float in [-3.5, 0, 3.5] { for z: Float in [-2.3, 2.3] { a.post([x, 0, z], radius: 0.12, height: 2.7, segments: 8) } }
            b.taper([0, 2.7, 0], bottom: [8.4, 5.8], top: [8.4, 0.2], height: 1.4)
            parts = [(a, LampMaterial.wood(NSColor(red: 0.5, green: 0.35, blue: 0.22, alpha: 1))), (b, LampMaterial.metal(NSColor(red: 0.3, green: 0.38, blue: 0.3, alpha: 1), rough: 0.6))]
        case .fountain:
            a.post([0, 0, 0], radius: 0.18, height: 0.85, segments: 10)
            b.blob([0, 0.9, 0], radius: 0.25, scale: [1, 0.35, 1], segments: 10, rings: 3)
            parts = [(a, LampMaterial.metal(NSColor(white: 0.45, alpha: 1), rough: 0.4)), (b, LampMaterial.metal(NSColor(white: 0.75, alpha: 1), rough: 0.2))]
        case .hoop:
            // A basketball hoop facing −z: pole, arm, backboard, orange rim.
            a.post([0, 0, 0.9], radius: 0.07, height: 3.3, segments: 8)
            a.box([0, 3.25, 0.45], [0.08, 0.08, 0.9])
            b.box([0, 3.35, 0], [1.8, 1.05, 0.04])
            c.box([0, 3.05, -0.35], [0.46, 0.03, 0.46])
            parts = [(a, dark), (b, LampMaterial.plastic(NSColor(white: 0.95, alpha: 1))), (c, LampMaterial.paint(NSColor(red: 0.95, green: 0.4, blue: 0.05, alpha: 1)))]
        case .net:
            // A tennis net across the court (along x), on posts.
            for x: Float in [-6.4, 6.4] { a.post([x, 0, 0], radius: 0.04, height: 1.07, segments: 6) }
            b.box([0, 0.5, 0], [12.8, 0.9, 0.02])
            c.box([0, 0.97, 0], [12.8, 0.07, 0.03])
            parts = [(a, dark), (b, LampMaterial.plastic(NSColor(white: 0.12, alpha: 0.9))), (c, LampMaterial.plastic(NSColor(white: 0.95, alpha: 1)))]
        case .flag:
            // The pin on a green: a white pole with a red flag, and the dark cup round its foot.
            // (It stands on the green, which lies 12 cm over the ground.)
            a.post([0, 0, 0], radius: 0.015, height: 2.42, segments: 6)
            b.box([0.26, 2.2, 0], [0.5, 0.34, 0.01])
            c.post([0, 0.122, 0], radius: 0.06, height: 0.01, segments: 10)
            parts = [(a, LampMaterial.plastic(NSColor(white: 0.95, alpha: 1))), (b, LampMaterial.plastic(NSColor(red: 0.85, green: 0.1, blue: 0.1, alpha: 1))),
                     (c, LampMaterial.plastic(NSColor(white: 0.05, alpha: 1)))]
        }
        let root = Entity()
        for (kit, mat) in parts { if let m = kit.mesh() { root.addChild(ModelEntity(mesh: m, materials: [mat])) } }
        return root
    }
}
