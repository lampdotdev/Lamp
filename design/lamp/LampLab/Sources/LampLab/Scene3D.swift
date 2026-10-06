import SceneKit
import SwiftUI
import AppKit
import simd

/// One app's name, where to draw it over the 3D picture, and how strongly.
struct Label { var title: String; var point: CGPoint; var opacity: Double; var scale: CGFloat }

/// Everything on the welcome's stage in one 3D scene: the lamp, the smoke rising from it, and the apps coming
/// out of the smoke. Being in one scene is what lets the gold reflect the smoke and the apps.
@MainActor final class StageScene {
    static let interval = 1.7, life = 13.0, rise = 1.5
    static let puffs = 120, glints = 10
    static let page = NSColor(srgbRed: 0.992, green: 0.984, blue: 0.968, alpha: 1)

    let scene = SCNScene()
    let lamp = SCNNode()
    let model: SCNNode
    let camera = SCNNode()
    let studio = Lamp.environment()
    private var smoke: [SCNNode] = []
    private var sparkles: [SCNNode] = []
    private var icons: [Int: SCNNode] = [:]
    private let probe = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
    private let probes: [SCNNode]

    init() {
        scene.background.contents = Self.page
        scene.lightingEnvironment.contents = studio
        scene.lightingEnvironment.intensity = 1.6

        model = Lamp.node()
        model.position = SCNVector3(-0.36, 0, 0)
        model.scale = SCNVector3(1.2, 1.2, 1.2)
        lamp.addChildNode(model)
        scene.rootNode.addChildNode(lamp)

        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 700
        key.light!.color = NSColor(srgbRed: 1, green: 0.96, blue: 0.9, alpha: 1)
        key.eulerAngles = SCNVector3(-0.9, -0.5, 0)
        scene.rootNode.addChildNode(key)

        camera.camera = SCNCamera()
        camera.camera!.fieldOfView = 23.8
        camera.camera!.zFar = 200
        camera.position = SCNVector3(0, 3.2, 14)
        camera.look(at: SCNVector3(0, 2.55, 0))
        scene.rootNode.addChildNode(camera)

        // Six cameras at the lamp's heart, one per face of a cube, to photograph what it would reflect.
        let looks: [(SCNVector3, SCNVector3)] = [
            (SCNVector3(1, 0, 0), SCNVector3(0, 1, 0)), (SCNVector3(-1, 0, 0), SCNVector3(0, 1, 0)),
            (SCNVector3(0, 1, 0), SCNVector3(0, 0, -1)), (SCNVector3(0, -1, 0), SCNVector3(0, 0, 1)),
            (SCNVector3(0, 0, 1), SCNVector3(0, 1, 0)), (SCNVector3(0, 0, -1), SCNVector3(0, 1, 0)),
        ]
        probes = looks.map { look in
            let n = SCNNode()
            n.camera = SCNCamera()
            n.camera!.fieldOfView = 90
            n.camera!.zNear = 0.05
            n.camera!.zFar = 200
            n.simdPosition = Lamp.heart
            n.simdLook(at: Lamp.heart + SIMD3(Float(look.0.x), Float(look.0.y), Float(look.0.z)),
                       up: SIMD3(Float(look.1.x), Float(look.1.y), Float(look.1.z)), localFront: SIMD3(0, 0, -1))
            return n
        }
        probes.forEach(scene.rootNode.addChildNode)
        probe.scene = scene

        // A warm glow behind the lamp, and its soft shadow on the page.
        let glow = Self.billboard(Self.puffImage(), order: -2)
        glow.constraints = nil
        glow.geometry!.firstMaterial!.diffuse.contents = NSColor(srgbRed: 0.98, green: 0.82, blue: 0.5, alpha: 1)
        glow.opacity = 0.35
        glow.scale = SCNVector3(9, 5.5, 1)
        glow.position = SCNVector3(0, 1.3, -4)
        scene.rootNode.addChildNode(glow)
        let shadow = Self.billboard(Self.puffImage(), order: -1)
        shadow.constraints = nil
        shadow.geometry!.firstMaterial!.diffuse.contents = NSColor(srgbRed: 0.35, green: 0.28, blue: 0.2, alpha: 1)
        shadow.opacity = 0.32
        shadow.eulerAngles.x = -.pi / 2
        shadow.scale = SCNVector3(3.6, 1.4, 1)
        shadow.position = SCNVector3(-0.3, 0.005, 0)
        scene.rootNode.addChildNode(shadow)

        let puff = Self.puffImage()
        for _ in 0..<Self.puffs {
            let n = Self.billboard(puff, order: 10)
            smoke.append(n)
            scene.rootNode.addChildNode(n)
        }
        let star = Self.starImage()
        for _ in 0..<Self.glints {
            let n = Self.billboard(star, order: 11)
            n.geometry!.firstMaterial!.diffuse.contents = NSColor(srgbRed: 0.95, green: 0.72, blue: 0.25, alpha: 1)
            sparkles.append(n)
            scene.rootNode.addChildNode(n)
        }
    }

    var spout: SIMD3<Float> { model.simdConvertPosition(Lamp.spoutTip, to: nil) }

    /// The smoke's path, `s` from the spout (0) to where it thins out (1), in the scene's units.
    func plume(_ s: Float, _ t: Double) -> SIMD3<Float> {
        let tt = Float(t)
        let sway = 0.55 * sin(s * 3.2 - tt * 0.55) * s + 0.18 * sin(s * 7.5 - tt * 1.1) * s * s
        return spout + SIMD3(1.4 * s - 1.1 * s * s + sway, 4.0 * s, 0.3 * s)
    }

    func update(_ t: Double) {
        // A slow sway, never far enough to hide the spout, and a breath of a bob.
        lamp.eulerAngles.y = CGFloat(-0.3 + 0.16 * sin(t * 0.42))
        lamp.position.y = CGFloat(0.025 * sin(t * 0.9))

        let violet = SIMD3<Float>(0.55, 0.42, 0.92), mist = SIMD3<Float>(0.72, 0.78, 0.98)
        for (k, n) in smoke.enumerated() {
            // Each puff has its own drift, size and strength, so the plume billows rather than forming a cone.
            let r1 = Self.noise(k, 1), r2 = Self.noise(k, 2), r3 = Self.noise(k, 3)
            let a = (t / (4 + 1.5 * Double(r3)) + Double(k) / Double(Self.puffs)).truncatingRemainder(dividingBy: 1)
            let s = Float(a) * 0.95
            let tt = Float(t)
            let drift = SIMD3<Float>(0.9 * (r1 - 0.5) + 0.25 * sin(tt * 0.7 + Float(k)),
                                     0.3 * (r2 - 0.5), 0.6 * (r2 - 0.5)) * s
            n.simdPosition = plume(s, t) + drift
            n.simdScale = SIMD3(repeating: (0.15 + 1.5 * s) * (0.6 + 0.8 * r2))
            n.eulerAngles.z = CGFloat(r1 * 6 + tt * 0.2 * (r3 - 0.5))
            n.opacity = CGFloat(0.2 * pow(sin(.pi * min(a * 1.3, 1)), 1.1) * Double(1 - 0.7 * s) * Double(0.5 + r3))
            let c = simd_mix(violet, mist, SIMD3(repeating: min(s * 1.1, 1) * 0.7))
            n.geometry!.firstMaterial!.diffuse.contents = NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y),
                                                                   blue: CGFloat(c.z), alpha: 1)
        }
        for (k, n) in sparkles.enumerated() {
            let cycle = 2.6 + Double(k % 3) * 0.5
            let a = (t / cycle + Double(k) * 0.37).truncatingRemainder(dividingBy: 1)
            let s = 0.1 + Float((k * 37) % 70) / 100
            n.simdPosition = plume(s, t) + SIMD3(Float((k * 53) % 60 - 30) / 60, 0, 0.3)
            n.simdScale = SIMD3(repeating: 0.12 + 0.14 * Float(sin(.pi * a)))
            n.opacity = CGFloat(pow(sin(.pi * a), 2))
        }

        // The apps on screen now: each appears `interval` after the last and stays for `life`.
        let first = max(Int(((t - Self.life) / Self.interval).rounded(.down)) + 1, 0)
        let last = max(Int((t / Self.interval).rounded(.down)), 0)
        for (k, n) in icons where k < first || k > last { n.removeFromParentNode(); icons[k] = nil }
        for k in first...last {
            let n = icons[k] ?? {
                let n = Self.cube(ideas[k % ideas.count])
                scene.rootNode.addChildNode(n)
                icons[k] = n
                return n
            }()
            place(n, k: k, t: t)
        }
    }

    private func place(_ n: SCNNode, k: Int, t: Double) {
        let age = t - Double(k) * Self.interval
        let side: Float = k % 2 == 0 ? -1 : 1
        let lane = Float((k / 2) % 3)
        let top = plume(0.5, t)
        if age < Self.rise {
            // Out of the spout in a steady climb, growing and turning to face us as it goes.
            let u = Float(age / Self.rise)
            let e = 1 - pow(1 - u, 2.4)
            n.simdPosition = plume(0.5 * u, t)
            n.simdScale = SIMD3(repeating: 0.1 + 0.9 * e)
            n.simdEulerAngles = SIMD3(0.25 * (1 - e), side * 2.4 * (1 - e), 0.15 * (1 - e))
            n.opacity = CGFloat(min(u * 2.5, 1))
            return
        }
        // Then off along an arc to one side, drifting back as it goes, like the face of a drum.
        let u = Float((age - Self.rise) / (Self.life - Self.rise))
        let e = 1 - pow(1 - u, 1.35)
        let end = SIMD3<Float>(side < 0 ? -10 : 12.5, top.y + 0.45 - lane * 1.25, -2.5)
        let control = SIMD3<Float>(top.x + side * 3.2, top.y + 0.9 + (2 - lane) * 0.37, 1.2)
        let v = 1 - e
        let a = v * v * top
        let b = 2 * v * e * control
        n.simdPosition = a + b + e * e * end
        n.simdScale = SIMD3(repeating: 1)
        let bob = 0.06 * sin(Float(t) * 1.3 + Float(k))
        n.simdEulerAngles = SIMD3(bob, atan(n.simdPosition.x / 12) * 0.8, 0)
        n.opacity = CGFloat(min((1 - u) / 0.15, 1))
    }

    /// Photographs the scene around the lamp, without the lamp, and has the gold reflect that.
    func reflect(_ t: Double, size: CGFloat = 256) {
        lamp.isHidden = true
        scene.background.contents = studio
        scene.lightingEnvironment.contents = studio
        let images = probes.map { cam -> NSImage in
            cam.simdPosition = lamp.simdConvertPosition(model.simdConvertPosition(Lamp.heart, to: lamp), to: nil)
            probe.pointOfView = cam
            return probe.snapshot(atTime: t, with: CGSize(width: size, height: size), antialiasingMode: .none)
        }
        scene.background.contents = Self.page
        lamp.isHidden = false
        scene.lightingEnvironment.contents = images
    }

    /// Where to write each app's name: just below its cube, as the main camera sees it.
    func labels(_ renderer: SCNRenderer, t: Double, height: CGFloat, scale: CGFloat) -> [Label] {
        icons.sorted { $0.key < $1.key }.map { k, n in
            let below = n.simdPosition - SIMD3(0, 0.62 * n.simdScale.x, 0)
            let p = renderer.projectPoint(SCNVector3(below.x, below.y, below.z))
            let age = t - Double(k) * Self.interval
            let shown = min(max((age - Self.rise * 0.6) / (Self.rise * 0.4), 0), 1)
            let depth = 14 / max(14 - CGFloat(n.simdPosition.z), 1)
            return Label(title: ideas[k % ideas.count].0, point: CGPoint(x: CGFloat(p.x) / scale, y: height - CGFloat(p.y) / scale),
                         opacity: shown * Double(n.opacity), scale: depth)
        }
    }

    /// A steady pseudo-random number in 0..<1 for each puff, so every frame agrees.
    static func noise(_ k: Int, _ salt: Int) -> Float {
        var x = UInt32(truncatingIfNeeded: k &* 73856093 ^ salt &* 19349663)
        x ^= x >> 13; x = x &* 0x5bd1e995; x ^= x >> 15
        return Float(x % 10000) / 10000
    }

    // MARK: Pieces

    /// An app as a small glossy block with rounded edges: its icon on the front, its colour all round.
    static func cube(_ idea: (String, String, Double)) -> SCNNode {
        let box = SCNBox(width: 0.8, height: 0.8, length: 0.36, chamferRadius: 0.19)
        box.chamferSegmentCount = 12
        let hue = idea.2
        let side = NSColor(hue: hue, saturation: 0.7, brightness: 0.86, alpha: 1)
        func material(_ contents: Any) -> SCNMaterial {
            let m = SCNMaterial()
            m.lightingModel = .physicallyBased
            m.diffuse.contents = contents
            m.metalness.contents = 0.0
            m.roughness.contents = 0.28
            m.clearCoat.contents = 1.0
            m.clearCoatRoughness.contents = 0.05
            return m
        }
        let front = material(faceImage(idea))
        let rest = material(side)
        box.materials = [front, rest, rest, rest, rest, rest]
        let n = SCNNode(geometry: box)
        return n
    }

    static func faceImage(_ idea: (String, String, Double)) -> CGImage {
        let view = ZStack {
            LinearGradient(colors: [Color(hue: idea.2, saturation: 0.42, brightness: 1),
                                    Color(hue: idea.2, saturation: 0.75, brightness: 0.86)],
                           startPoint: .top, endPoint: .bottom)
            Image(systemName: idea.1)
                .font(.system(size: 112, weight: .semibold))
                .foregroundStyle(.white)
        }
        .frame(width: 256, height: 256)
        let r = ImageRenderer(content: view)
        r.scale = 2
        return r.cgImage!
    }

    static func billboard(_ image: NSImage, order: Int) -> SCNNode {
        let plane = SCNPlane(width: 1, height: 1)
        let m = SCNMaterial()
        m.lightingModel = .constant
        // The image is only the shape; the colour is set per puff.
        m.diffuse.contents = NSColor.white
        m.transparent.contents = image
        m.transparencyMode = .aOne
        m.blendMode = .alpha
        m.writesToDepthBuffer = false
        m.isDoubleSided = true
        plane.firstMaterial = m
        let n = SCNNode(geometry: plane)
        n.renderingOrder = order
        n.constraints = [SCNBillboardConstraint()]
        return n
    }

    /// A soft round puff of white that fades to nothing at its edge.
    static func puffImage() -> NSImage {
        NSImage(size: NSSize(width: 128, height: 128), flipped: false) { rect in
            let g = NSGradient(colors: [NSColor(white: 1, alpha: 1), NSColor(white: 1, alpha: 0.3), NSColor(white: 1, alpha: 0)],
                               atLocations: [0, 0.35, 1], colorSpace: .sRGB)!
            g.draw(in: NSBezierPath(ovalIn: rect), relativeCenterPosition: .zero)
            return true
        }
    }

    /// A four-pointed glint.
    static func starImage() -> NSImage {
        NSImage(size: NSSize(width: 64, height: 64), flipped: false) { _ in
            let c = NSPoint(x: 32, y: 32), r: CGFloat = 30
            let p = NSBezierPath()
            p.move(to: NSPoint(x: c.x, y: c.y + r))
            p.curve(to: NSPoint(x: c.x + r, y: c.y), controlPoint1: c, controlPoint2: c)
            p.curve(to: NSPoint(x: c.x, y: c.y - r), controlPoint1: c, controlPoint2: c)
            p.curve(to: NSPoint(x: c.x - r, y: c.y), controlPoint1: c, controlPoint2: c)
            p.curve(to: NSPoint(x: c.x, y: c.y + r), controlPoint1: c, controlPoint2: c)
            NSColor.white.setFill()
            p.fill()
            return true
        }
    }
}
