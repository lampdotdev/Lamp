import SceneKit
import SwiftUI
import AppKit
import simd

/// Lamp's app icon as an Icon Composer document: a warm white background, the porcelain lamp from the
/// welcome, and golden smoke rising from its spout, each its own layer so macOS 26 can give them depth.
@MainActor enum AppIcon {
    static let canvas: CGFloat = 1024

    /// Where the lamp sits in the icon: whole, a little low and left, so the smoke has room to rise.
    static let pose = Pose.framing(eye: SIMD3(1.2, 3.6, 9.4), subject: SIMD3(0.3, 0.95, 0),
                                   screen: SIMD2(-0.2, -0.36), fov: 30, aspect: 1)

    /// The lamp's pictures for one appearance: the lamp itself, and the ground under it (its shadow, and the
    /// smoke's glow pooled on the floor). Also where the spout is, in canvas points from the top left.
    struct Layers { var lamp: CGImage; var ground: CGImage; var spout: CGPoint }

    /// The lamp lit with a little more contrast than the welcome, so its shape still reads at Dock and Finder
    /// sizes, and with the smoke's warm light falling on it.
    static func layers(material: SCNMaterial, dark: Bool) -> Layers {
        let clay = ClayScene(material: material)
        clay.scene.background.contents = NSColor.clear
        clay.scene.lightingEnvironment.intensity = dark ? 0.65 : 0.5
        for node in clay.scene.rootNode.childNodes where node.light?.type == .directional {
            if node.light!.castsShadow {
                node.light!.intensity = 820
                node.light!.shadowColor = NSColor(white: 0, alpha: dark ? 0.55 : 0.32)
                node.light!.shadowRadius = 18
            } else {
                node.light!.intensity *= 0.7
            }
        }
        // The smoke's glow on the lamp: warm light just above the spout, where the smoke is thickest,
        // and a softer one high over the lid, where it sweeps back across. Each reaches only its own part.
        let tip = clay.lamp.simdConvertPosition(Lamp.spoutTip, to: nil)
        // White porcelain shows the same light more strongly than charcoal, so it gets less.
        let warmth = dark ? 130.0 : 70.0
        for (position, intensity, reach) in [(tip + SIMD3<Float>(-0.25, 0.8, 0.3), warmth, 1.45),
                                             (SIMD3<Float>(0.45, 2.55, 0.55), warmth, 1.75)] {
            let glow = SCNNode()
            glow.light = SCNLight()
            glow.light!.type = .omni
            glow.light!.color = NSColor(srgbRed: 1, green: 0.52, blue: 0.1, alpha: 1)
            glow.light!.intensity = CGFloat(intensity)
            glow.light!.attenuationStartDistance = 0
            glow.light!.attenuationEndDistance = CGFloat(reach)
            glow.light!.attenuationFalloffExponent = 2
            glow.simdPosition = position
            clay.scene.rootNode.addChildNode(glow)
        }
        clay.pose(pose)
        let r = SCNRenderer(device: MTLCreateSystemDefaultDevice(), options: nil)
        r.scene = clay.scene
        r.pointOfView = clay.camera
        func point(_ p: SIMD3<Float>) -> CGPoint {
            // projectPoint answers in the last render's pixels (twice the canvas), from the bottom left.
            let q = r.projectPoint(SCNVector3(p.x, p.y, p.z))
            return CGPoint(x: CGFloat(q.x) / 2, y: canvas - CGFloat(q.y) / 2)
        }

        // The pool of smoke-light on the floor bounces a little warmth back up onto the lamp's underside.
        let poolCentre = SIMD3<Float>(tip.x * 0.55, 0, tip.z * 0.55 + 0.35)
        let bounce = SCNNode()
        bounce.light = SCNLight()
        bounce.light!.type = .omni
        bounce.light!.color = NSColor(srgbRed: 1, green: 0.6, blue: 0.25, alpha: 1)
        bounce.light!.intensity = CGFloat(warmth * (dark ? 0.3 : 0.15))
        bounce.light!.attenuationEndDistance = 1.3
        bounce.light!.attenuationFalloffExponent = 2
        bounce.simdPosition = poolCentre + SIMD3(0, 0.08, 0)
        clay.scene.rootNode.addChildNode(bounce)

        // The lamp, with the floor taken away: its shadow goes in the ground layer behind it.
        let floor = clay.scene.rootNode.childNodes.filter { $0.geometry is SCNFloor }
        floor.forEach { $0.isHidden = true }
        let lamp = supersampled(r, pixels: CGSize(width: canvas, height: canvas))
        let spout = point(tip)
        // Measured now, while the last render is the full-size one that point() expects.
        let underSpout = point(poolCentre)
        let underLid = point(SIMD3(0.2, 0, 0.75))

        // The ground, lit the way a real room would: the key light as a large softbox (its shadow averaged
        // over many directions within a cone, so it's crisp where the foot meets the floor and softens with
        // distance) plus light from the whole sky (averaged over the hemisphere, so the floor darkens gently
        // under and around the lamp, as bounced light does). Each pass renders a plain white floor with the
        // lamp out of the camera's sight but still casting its shadow.
        let paper = SCNMaterial()
        paper.lightingModel = .lambert
        paper.diffuse.contents = NSColor.white
        floor.forEach { $0.isHidden = false; $0.categoryBitMask = 1 << 1; $0.geometry!.materials = [paper] }
        clay.camera.camera!.categoryBitMask = 1 << 1
        // Ambient occlusion would speckle the flat floor; the passes below do that job properly.
        clay.camera.camera!.screenSpaceAmbientOcclusionIntensity = 0
        let lights = clay.scene.rootNode.childNodes.filter { $0.light != nil }
        let key = lights.first { $0.light!.castsShadow }!
        lights.filter { $0 !== key }.forEach { $0.isHidden = true }
        key.light!.shadowRadius = 2
        key.light!.shadowSampleCount = 1
        let towardKey = -key.simdWorldFront
        let side = simd_normalize(simd_cross(towardKey, SIMD3(0, 1, 0))), up = simd_cross(side, towardKey)
        let golden: Float = 2.39996
        let softbox: [SIMD3<Float>] = (0..<32).map { i in
            let r = tan(0.22 * sqrt((Float(i) + 0.5) / 32)), a = Float(i) * golden
            return simd_normalize(towardKey + r * (cos(a) * side + sin(a) * up))
        }
        let sky: [SIMD3<Float>] = (0..<64).map { i in
            let y = max(sqrt(1 - (Float(i) + 0.5) / 64), 0.14), a = Float(i) * golden, h = sqrt(1 - y * y)
            return SIMD3(h * cos(a), y, h * sin(a))
        }
        func unlit(from directions: [SIMD3<Float>]) -> (dark: [Float], coverage: [Float]) {
            var sum = [Float](repeating: 0, count: Int(canvas * canvas)), coverage = sum
            for d in directions {
                key.simdPosition = d * 12
                key.simdLook(at: .zero, up: abs(d.y) > 0.95 ? SIMD3(0, 0, 1) : SIMD3(0, 1, 0), localFront: SIMD3(0, 0, -1))
                let pass = r.snapshot(atTime: 0, with: CGSize(width: canvas, height: canvas), antialiasingMode: .multisampling4X)
                let (lit, cover) = litFraction(pass.cgImage(forProposedRect: nil, context: nil, hints: nil)!)
                for i in sum.indices { sum[i] += 1 - lit[i] }
                coverage = cover
            }
            return (sum.map { $0 / Float(directions.count) }, coverage)
        }
        let keyShadow = unlit(from: softbox), skyShadow = unlit(from: sky)
        let shadow = shadowImage(key: keyShadow.dark, sky: skyShadow.dark, coverage: keyShadow.coverage,
                                 keyStrength: dark ? 0.75 : 0.6, skyStrength: dark ? 0.7 : 0.55)
        let ground = Canvas { ctx, size in
            ctx.draw(Image(decorative: shadow, scale: 1), in: CGRect(origin: .zero, size: size))
            // The smoke's light pooled on the floor, flattened by the angle we see the floor at.
            for (centre, width, strength) in [(underSpout, 520.0, 1.0), (underLid, 380.0, 0.5)] {
                ctx.drawLayer { l in
                    l.translateBy(x: centre.x, y: centre.y)
                    l.scaleBy(x: 1, y: 0.24)
                    let r = width / 2
                    l.fill(Path(ellipseIn: CGRect(x: -r, y: -r, width: 2 * r, height: 2 * r)), with: .radialGradient(
                        Gradient(colors: [Color(red: 1, green: 0.64, blue: 0.2).opacity((dark ? 0.5 : 0.45) * strength), .clear]),
                        center: .zero, startRadius: 0, endRadius: r))
                }
            }
        }
        .frame(width: canvas, height: canvas)
        let renderer = ImageRenderer(content: ground)
        renderer.scale = 1
        return Layers(lamp: lamp, ground: renderer.cgImage!, spout: spout)
    }

    /// How lit each pixel of a white-floor render is, from 0 (in full shadow) to 1 (open floor), and how much
    /// of it is floor at all (beyond the horizon the render is transparent).
    static func litFraction(_ image: CGImage) -> (lit: [Float], coverage: [Float]) {
        let w = image.width, h = image.height
        var px = [UInt8](repeating: 0, count: w * h * 4)
        let ctx = CGContext(data: &px, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image, in: CGRect(x: 0, y: 0, width: w, height: h))
        // Open floor is the floor's most common brightness, since most of it is unshadowed.
        var counts = [Int](repeating: 0, count: 256)
        for i in stride(from: 0, to: px.count, by: 4) where px[i + 3] == 255 { counts[Int(px[i + 1])] += 1 }
        let open = Float(max(counts.indices.max { counts[$0] < counts[$1] } ?? 255, 1))
        var lit = [Float](repeating: 1, count: w * h), coverage = [Float](repeating: 0, count: w * h)
        for p in 0..<(w * h) {
            let c = Float(px[p * 4 + 3]) / 255
            coverage[p] = c
            if c > 0 { lit[p] = min(Float(px[p * 4 + 1]) / c / open, 1) }
        }
        return (lit, coverage)
    }

    /// The two kinds of shadow, combined into black on transparency.
    static func shadowImage(key: [Float], sky: [Float], coverage: [Float], keyStrength: Float, skyStrength: Float) -> CGImage {
        let n = Int(canvas)
        var px = [UInt8](repeating: 0, count: n * n * 4)
        for p in 0..<(n * n) {
            let a = coverage[p] * (1 - (1 - keyStrength * key[p]) * (1 - skyStrength * sky[p]))
            px[p * 4 + 3] = UInt8(max(0, min(1, a)) * 255)
        }
        return CGContext(data: &px, width: n, height: n, bitsPerComponent: 8, bytesPerRow: n * 4,
                         space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!.makeImage()!
    }

    /// Golden smoke: a ribbon that leaves the spout thin, swells as it rises and curls back over the lamp,
    /// with a fainter second wisp and a few glints.
    static func smokeLayer(from spout: CGPoint) -> CGImage {
        let view = Canvas { ctx, _ in
            func ribbon(_ points: [CGPoint], width: (Double) -> Double) -> Path {
                var left: [CGPoint] = [], right: [CGPoint] = []
                for (i, p) in points.enumerated() {
                    let a = points[max(i - 1, 0)], b = points[min(i + 1, points.count - 1)]
                    let dx = b.x - a.x, dy = b.y - a.y, len = max(hypot(dx, dy), 0.001)
                    let w = width(Double(i) / Double(points.count - 1)) / 2
                    left.append(CGPoint(x: p.x - dy / len * w, y: p.y + dx / len * w))
                    right.append(CGPoint(x: p.x + dy / len * w, y: p.y - dx / len * w))
                }
                var path = Path()
                path.addLines(left + right.reversed())
                path.closeSubpath()
                return path
            }
            func curve(_ c: [CGPoint], steps: Int = 120) -> [CGPoint] {
                (0...steps).map { i in
                    let t = CGFloat(i) / CGFloat(steps), u = 1 - t
                    let x = u * u * u * c[0].x + 3 * u * u * t * c[1].x + 3 * u * t * t * c[2].x + t * t * t * c[3].x
                    let y = u * u * u * c[0].y + 3 * u * u * t * c[1].y + 3 * u * t * t * c[2].y + t * t * t * c[3].y
                    return CGPoint(x: x, y: y)
                }
            }
            let s = spout
            // Up from the spout, leaning right, then back over the lamp and curling in at the top.
            let main = curve([s, CGPoint(x: s.x + 110, y: s.y - 150), CGPoint(x: s.x - 10, y: s.y - 320),
                              CGPoint(x: s.x - 210, y: s.y - 360)])
                + curve([CGPoint(x: s.x - 210, y: s.y - 360), CGPoint(x: s.x - 400, y: s.y - 400),
                         CGPoint(x: s.x - 400, y: s.y - 560), CGPoint(x: s.x - 260, y: s.y - 545)], steps: 70).dropFirst()
            let gold = Gradient(stops: [.init(color: Color(red: 0.98, green: 0.86, blue: 0.55), location: 0),
                                        .init(color: Color(red: 0.93, green: 0.7, blue: 0.27), location: 0.5),
                                        .init(color: Color(red: 0.84, green: 0.56, blue: 0.16), location: 1)])
            let bounds = CGRect(x: s.x - 420, y: s.y - 580, width: 540, height: 600)
            // A soft glow around it, then the ribbon, then a bright thread down its middle.
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 26))
                l.fill(ribbon(main) { t in 10 + 120 * sin(.pi * min(t * 1.1, 1)) }, with: .color(Color(red: 1, green: 0.8, blue: 0.4).opacity(0.45)))
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 5))
                l.fill(ribbon(main) { t in 8 + 78 * sin(.pi * min(t * 1.08, 1)) },
                       with: .linearGradient(gold, startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                             endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
            }
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 3))
                l.fill(ribbon(main) { t in 3 + 20 * sin(.pi * min(t * 1.08, 1)) }, with: .color(Color(red: 1, green: 0.95, blue: 0.8).opacity(0.85)))
            }
            // A thinner wisp peeling off upwards.
            let wisp = curve([CGPoint(x: s.x + 30, y: s.y - 200), CGPoint(x: s.x + 110, y: s.y - 300),
                              CGPoint(x: s.x - 20, y: s.y - 420), CGPoint(x: s.x + 50, y: s.y - 500)])
            ctx.drawLayer { l in
                l.addFilter(.blur(radius: 4))
                l.fill(ribbon(wisp) { t in 4 + 24 * sin(.pi * t) },
                       with: .linearGradient(gold, startPoint: CGPoint(x: bounds.minX, y: bounds.minY),
                                             endPoint: CGPoint(x: bounds.maxX, y: bounds.maxY)))
            }
            // Glints.
            for (x, y, r) in [(s.x - 120.0, s.y - 500.0, 24.0), (s.x - 460, s.y - 330, 16), (s.x + 120, s.y - 420, 13)] {
                let c = CGPoint(x: x, y: y)
                var star = Path()
                star.move(to: CGPoint(x: x, y: y - r))
                star.addQuadCurve(to: CGPoint(x: x + r, y: y), control: c)
                star.addQuadCurve(to: CGPoint(x: x, y: y + r), control: c)
                star.addQuadCurve(to: CGPoint(x: x - r, y: y), control: c)
                star.addQuadCurve(to: CGPoint(x: x, y: y - r), control: c)
                ctx.fill(star, with: .color(Color(red: 0.95, green: 0.72, blue: 0.28)))
            }
        }
        .frame(width: canvas, height: canvas)
        let r = ImageRenderer(content: view)
        r.scale = 1
        return r.cgImage!
    }

    /// Everything the app ships: the compiled document for macOS 26 (Assets.car), and for older macOS an
    /// .icns of the same picture drawn on Apple's grid (824 points inside 1024, with a shadow), plus a PNG.
    static func export(_ doc: URL, to resources: URL, scratch: URL) throws {
        let developer = "/Applications/Xcode.app/Contents/Developer"
        func run(_ tool: String, _ args: [String]) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: tool)
            p.arguments = args
            p.environment = ["DEVELOPER_DIR": developer]
            try! p.run()
            p.waitUntilExit()
        }
        let car = scratch.appendingPathComponent("car")
        try? FileManager.default.removeItem(at: car)
        try FileManager.default.createDirectory(at: car, withIntermediateDirectories: true)
        run(developer + "/usr/bin/actool", [doc.path, "--compile", car.path, "--platform", "macosx",
                                            "--minimum-deployment-target", "14.0", "--app-icon", "AppIcon",
                                            "--output-partial-info-plist", car.appendingPathComponent("partial.plist").path])
        try? FileManager.default.removeItem(at: resources.appendingPathComponent("Assets.car"))
        try FileManager.default.copyItem(at: car.appendingPathComponent("Assets.car"), to: resources.appendingPathComponent("Assets.car"))

        let full = scratch.appendingPathComponent("full.png")
        run(developer + "/../Applications/Icon Composer.app/Contents/Executables/ictool",
            [doc.path, "--export-preview", "macOS", "Light", "1024", "1024", "1", full.path])
        let tile = NSImage(contentsOf: full)!
        func onGrid(_ pixels: Int) -> NSBitmapImageRep {
            let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                                       samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                       bytesPerRow: 0, bitsPerPixel: 0)!
            NSGraphicsContext.saveGraphicsState()
            NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
            NSGraphicsContext.current!.imageInterpolation = .high
            let k = CGFloat(pixels) / 1024
            let shadow = NSShadow()
            shadow.shadowColor = NSColor(white: 0, alpha: 0.3)
            shadow.shadowBlurRadius = 20 * k
            shadow.shadowOffset = NSSize(width: 0, height: -10 * k)
            shadow.set()
            tile.draw(in: NSRect(x: 100 * k, y: 100 * k, width: 824 * k, height: 824 * k))
            NSGraphicsContext.restoreGraphicsState()
            return rep
        }
        let iconset = scratch.appendingPathComponent("AppIcon.iconset")
        try? FileManager.default.removeItem(at: iconset)
        try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
        for (name, pixels) in [("16x16", 16), ("16x16@2x", 32), ("32x32", 32), ("32x32@2x", 64), ("128x128", 128),
                               ("128x128@2x", 256), ("256x256", 256), ("256x256@2x", 512), ("512x512", 512), ("512x512@2x", 1024)] {
            try onGrid(pixels).representation(using: .png, properties: [:])!.write(to: iconset.appendingPathComponent("icon_\(name).png"))
        }
        run("/usr/bin/iconutil", ["-c", "icns", iconset.path, "-o", resources.appendingPathComponent("AppIcon.icns").path])
        try onGrid(1024).representation(using: .png, properties: [:])!.write(to: resources.appendingPathComponent("AppIcon.png"))
    }

    /// Writes the document (icon.json plus its layer images) and returns its URL.
    static func write(to folder: URL) throws -> URL {
        let doc = folder.appendingPathComponent("AppIcon.icon")
        try? FileManager.default.removeItem(at: doc)
        try FileManager.default.createDirectory(at: doc.appendingPathComponent("Assets"), withIntermediateDirectories: true)
        let light = layers(material: Lamp.clay(), dark: false)
        let dark = layers(material: Lamp.charcoal(), dark: true)
        writePNG(light.lamp, doc.appendingPathComponent("Assets/lamp.png"))
        writePNG(dark.lamp, doc.appendingPathComponent("Assets/lamp-dark.png"))
        writePNG(light.ground, doc.appendingPathComponent("Assets/ground.png"))
        writePNG(dark.ground, doc.appendingPathComponent("Assets/ground-dark.png"))
        writePNG(smokeLayer(from: light.spout), doc.appendingPathComponent("Assets/smoke.png"))
        // The first group is the front one: the smoke over the lamp. The lamp keeps its own shading;
        // the smoke gets Liquid Glass's highlights, so it reads as something luminous rather than painted.
        let json: [String: Any] = [
            "fill": ["linear-gradient": ["srgb:1.00000,1.00000,1.00000,1.00000", "srgb:0.91765,0.89804,0.86667,1.00000"]],
            "groups": [
                ["layers": [["image-name": "smoke.png", "name": "smoke", "glass": true]],
                 "shadow": ["kind": "neutral", "opacity": 0.25],
                 "translucency": ["enabled": false, "value": 0.4]],
                // In dark mode the lamp is charcoal instead of white. A plain "image-name" beside the
                // specializations would win over them, so there's none. The ground carries the real shadow,
                // so the system's own shadow under the lamp is kept faint.
                ["layers": [["name": "lamp", "glass": false,
                             "image-name-specializations": [["value": "lamp.png"],
                                                            ["appearance": "dark", "value": "lamp-dark.png"]]]],
                 "shadow": ["kind": "neutral", "opacity": 0.12],
                 "translucency": ["enabled": false, "value": 0.4]],
                ["layers": [["name": "ground", "glass": false,
                             "image-name-specializations": [["value": "ground.png"],
                                                            ["appearance": "dark", "value": "ground-dark.png"]]]],
                 "shadow": ["kind": "none", "opacity": 0],
                 "translucency": ["enabled": false, "value": 0.4]],
            ],
            "supported-platforms": ["squares": ["macOS"]],
        ]
        try JSONSerialization.data(withJSONObject: json, options: [.prettyPrinted, .sortedKeys])
            .write(to: doc.appendingPathComponent("icon.json"))
        return doc
    }
}
