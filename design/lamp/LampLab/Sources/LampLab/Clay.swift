import SceneKit
import AppKit
import simd

/// A camera framing: where it stands, what it looks at, how wide it sees.
struct Pose {
    var eye: SIMD3<Float>
    var target: SIMD3<Float>
    var fov: Float

    /// Looks from `eye` so that `subject` lands at `screen` (-1…1 across, -1…1 up) in a window of `aspect`.
    static func framing(eye: SIMD3<Float>, subject: SIMD3<Float>, screen: SIMD2<Float>, fov: Float,
                        aspect: Float = 1080.0 / 760) -> Pose {
        let d = subject - eye
        let yaw = atan2(d.x, -d.z), pitch = atan2(d.y, simd_length(SIMD2(d.x, d.z)))
        let half = fov / 2 * .pi / 180
        let h = atan(screen.x * tan(half) * aspect), v = atan(screen.y * tan(half))
        let y2 = yaw - h, p2 = pitch - v
        let forward = SIMD3(sin(y2) * cos(p2), sin(p2), -cos(y2) * cos(p2))
        return Pose(eye: eye, target: eye + forward * simd_length(d), fov: fov)
    }

    /// Glides from one framing to the next by circling the lamp, rather than cutting straight past it.
    static func mix(_ a: Pose, _ b: Pose, _ t: Float) -> Pose {
        let e = t * t * (3 - 2 * t)
        let centre = SIMD3<Float>(0, 1, 0)
        func polar(_ p: SIMD3<Float>) -> (az: Float, el: Float, r: Float) {
            let d = p - centre
            return (atan2(d.x, d.z), asin(d.y / simd_length(d)), simd_length(d))
        }
        let pa = polar(a.eye), pb = polar(b.eye)
        var daz = pb.az - pa.az
        if daz > .pi { daz -= 2 * .pi }
        if daz < -.pi { daz += 2 * .pi }
        let az = pa.az + daz * e, el = pa.el + (pb.el - pa.el) * e, r = pa.r + (pb.r - pa.r) * e
        let eye = centre + r * SIMD3(cos(el) * sin(az), sin(el), cos(el) * cos(az))
        return Pose(eye: eye, target: simd_mix(a.target, b.target, SIMD3(repeating: e)), fov: a.fov + (b.fov - a.fov) * e)
    }
}

/// The white lamp on a white page, lit softly so only its shading and shadows show its shape.
@MainActor final class ClayScene {
    static let page = NSColor(srgbRed: 0.98, green: 0.976, blue: 0.97, alpha: 1)

    /// One close, cropped framing per step of the welcome.
    static var poses: [Pose] = [
        // Hello: the lamp large and low, its foot cut off by the bottom of the window.
        Pose(eye: SIMD3(0.55, 1.5, 5.6), target: SIMD3(0.75, 2.05, 0), fov: 30),
        // The idea: the lid and its knob against the right edge, half out of the window.
        .framing(eye: SIMD3(2.6, 2.2, 3.0), subject: SIMD3(0, 1.5, 0), screen: SIMD2(0.93, 0.05), fov: 34),
        // Setup: seen from behind, the handle's loop against the left edge with the body beyond it.
        .framing(eye: SIMD3(-4.2, 1.7, -0.4), subject: SIMD3(-1.46, 1.25, -0.53), screen: SIMD2(-0.88, 0.05), fov: 34),
    ]

    let scene = SCNScene()
    let lamp: SCNNode
    let camera = SCNNode()

    init(material: SCNMaterial = Lamp.clay()) {
        scene.background.contents = Self.page
        scene.lightingEnvironment.contents = Self.studio()
        scene.lightingEnvironment.intensity = 0.8

        lamp = Lamp.node(material: material)
        lamp.eulerAngles.y = -0.35
        lamp.enumerateHierarchy { n, _ in n.castsShadow = true }
        scene.rootNode.addChildNode(lamp)

        // The page the lamp stands on: invisible but for the shadows on it.
        let floor = SCNFloor()
        floor.reflectivity = 0
        let fm = SCNMaterial()
        fm.lightingModel = .shadowOnly
        floor.materials = [fm]
        scene.rootNode.addChildNode(SCNNode(geometry: floor))

        // One big soft light from the upper left, for the shading and the long shadow.
        let key = SCNNode()
        key.light = SCNLight()
        key.light!.type = .directional
        key.light!.intensity = 800
        key.light!.castsShadow = true
        key.light!.shadowMode = .deferred
        key.light!.shadowRadius = 14
        key.light!.shadowSampleCount = 32
        key.light!.shadowMapSize = CGSize(width: 4096, height: 4096)
        key.light!.shadowColor = NSColor(white: 0, alpha: 0.26)
        key.light!.orthographicScale = 4
        key.light!.automaticallyAdjustsShadowProjection = true
        key.eulerAngles = SCNVector3(-0.55, -1.15, 0)
        scene.rootNode.addChildNode(key)

        // Soft fills from the right, from behind and bounced up from the page, so no crease or underside
        // falls too dark while the key light still shows the shape.
        for (angles, intensity) in [(SCNVector3(-0.35, 1.2, 0), 380.0), (SCNVector3(-0.4, 2.8, 0), 260.0),
                                    (SCNVector3(1.2, 0.3, 0), 220.0)] {
            let fill = SCNNode()
            fill.light = SCNLight()
            fill.light!.type = .directional
            fill.light!.intensity = CGFloat(intensity)
            fill.light!.color = NSColor(srgbRed: 1, green: 0.985, blue: 0.96, alpha: 1)
            fill.eulerAngles = angles
            scene.rootNode.addChildNode(fill)
        }

        camera.camera = SCNCamera()
        camera.camera!.zNear = 0.05
        camera.camera!.screenSpaceAmbientOcclusionIntensity = 0.7
        camera.camera!.screenSpaceAmbientOcclusionRadius = 0.1
        camera.camera!.screenSpaceAmbientOcclusionBias = 0.02
        scene.rootNode.addChildNode(camera)
        pose(Self.poses[0])
    }

    func pose(_ p: Pose) {
        camera.camera!.fieldOfView = CGFloat(p.fov)
        camera.simdPosition = p.eye
        camera.simdLook(at: p.target)
    }

    /// While a step is showing, the camera eases slowly back and a little round, slowing to a stop, so the
    /// picture is never quite still. `elapsed` is the time spent on that step.
    static func drift(_ p: Pose, _ elapsed: Double) -> Pose {
        let d = Float(1 - exp(-elapsed / 6))
        let centre = SIMD3<Float>(0, 1, 0)
        let away = p.eye - centre
        let turn = 0.05 * d
        let turned = SIMD3(away.x * cos(turn) + away.z * sin(turn), away.y, -away.x * sin(turn) + away.z * cos(turn))
        return Pose(eye: centre + turned * (1 + 0.1 * d), target: p.target, fov: p.fov)
    }

    /// Where the camera is `t` seconds into a tour that rests on each framing, then glides to the next.
    static func tour(_ t: Double, rest: Double, glide: Double) -> Pose {
        let leg = rest + glide
        let i = min(Int(t / leg), poses.count - 1)
        let into = t - Double(i) * leg
        guard i < poses.count - 1, into > rest else { return drift(poses[i], into) }
        return Pose.mix(drift(poses[i], rest), poses[i + 1], Float((into - rest) / glide))
    }

    /// Bright from above, a little darker from below: soft light from everywhere for the matte white.
    static func studio() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 256), flipped: false) { rect in
            NSGradient(colors: [NSColor(white: 0.62, alpha: 1), NSColor(white: 0.82, alpha: 1), NSColor(white: 1, alpha: 1)],
                       atLocations: [0, 0.5, 1], colorSpace: .sRGB)!.draw(in: rect, angle: 90)
            return true
        }
    }
}
