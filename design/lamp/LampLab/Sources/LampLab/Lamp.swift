import SceneKit
import AppKit
import simd

enum Lamp {
    /// Where the smoke comes out, in the lamp's own coordinates.
    static let spoutTip = SIMD3<Float>(2.5, 1.3, 0)
    /// The middle of the body, where the lamp "sees" its surroundings from.
    static let heart = SIMD3<Float>(0.15, 0.85, 0)

    static func gold() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 1.0, green: 0.77, blue: 0.4, alpha: 1)
        m.metalness.contents = 1.0
        m.roughness.contents = 0.1
        m.isDoubleSided = true
        return m
    }

    /// A soft-edged band between two heights, 0 outside it and 1 in the middle.
    static func band(_ y: Float, _ from: Float, _ to: Float) -> Float {
        let edge: Float = 0.012
        let a = min(max((y - from) / edge, 0), 1), b = min(max((to - y) / edge, 0), 1)
        return a * b
    }

    /// Matte white, like an unglazed porcelain model: only light and shadow show its shape.
    static func clay() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.9, green: 0.885, blue: 0.86, alpha: 1)
        m.metalness.contents = 0.0
        m.roughness.contents = 0.72
        m.isDoubleSided = true
        return m
    }

    /// Charcoal porcelain, for the icon in dark mode: a deep warm grey with only a faint glaze.
    static func charcoal() -> SCNMaterial {
        let m = SCNMaterial()
        m.lightingModel = .physicallyBased
        m.diffuse.contents = NSColor(srgbRed: 0.2, green: 0.195, blue: 0.19, alpha: 1)
        m.metalness.contents = 0.0
        m.roughness.contents = 0.6
        m.clearCoat.contents = 0.15
        m.clearCoatRoughness.contents = 0.35
        m.isDoubleSided = true
        return m
    }

    static func bump(_ t: Float, _ at: Float, _ width: Float) -> Float { exp(-pow((t - at) / width, 2)) }

    static func bezier(_ c: [SIMD3<Float>], _ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        let a: SIMD3<Float> = (u * u * u) * c[0] + (3 * u * u * t) * c[1]
        let b: SIMD3<Float> = (3 * u * t * t) * c[2] + (t * t * t) * c[3]
        return a + b
    }

    static func node(material: SCNMaterial = gold()) -> SCNNode {
        let lamp = SCNNode()
        let mat = material
        func add(_ g: SCNGeometry) { g.materials = [mat]; lamp.addChildNode(SCNNode(geometry: g)) }
        func ring(_ radius: CGFloat, _ pipe: CGFloat, y: CGFloat) {
            let t = SCNTorus(ringRadius: radius, pipeRadius: pipe)
            t.ringSegmentCount = 360
            t.pipeSegmentCount = 48
            t.materials = [mat]
            let n = SCNNode(geometry: t)
            n.position.y = y
            lamp.addChildNode(n)
        }
        func ball(_ r: CGFloat, at p: SIMD3<Float>) {
            let s = SCNSphere(radius: r)
            s.segmentCount = 64
            s.materials = [mat]
            let n = SCNNode(geometry: s)
            n.simdPosition = p
            lamp.addChildNode(n)
        }
        /// A string of small beads around the lamp's axis.
        func beads(_ count: Int, radius: Float, size: CGFloat, y: Float) {
            for i in 0..<count {
                let a = Float(i) / Float(count) * 2 * .pi
                ball(size, at: SIMD3(radius * cos(a), y, radius * sin(a)))
            }
        }

        // The foot: a stepped base with beading and a ring of petals, narrowing to a stem.
        add(lathe([.init(0, 0), .init(0.62, 0), .init(0.68, 0.015), .init(0.69, 0.045), .init(0.66, 0.07),
                   .init(0.62, 0.085), .init(0.56, 0.14), .init(0.48, 0.18), .init(0.4, 0.2), .init(0.3, 0.24),
                   .init(0.22, 0.29), .init(0.19, 0.34), .init(0.2, 0.38), .init(0.17, 0.42)],
                  segments: 720, steps: 24,
                  relief: { a, y in
                      // Rounded petals around the slope of the foot, fading out towards the stem.
                      let petal = pow(abs(cos(a * 12)), 0.6)
                      return 1 + 0.05 * petal * band(y, 0.085, 0.2) * (1 - (y - 0.085) / 0.2)
                  }))
        ring(0.2, 0.03, y: 0.36)
        beads(56, radius: 0.645, size: 0.017, y: 0.088)
        beads(20, radius: 0.215, size: 0.024, y: 0.41)

        // The body: round at the back, drawn out, flattened and narrowed at the front so it flows into the spout.
        // Lobes swell round its lower half, with a raised belt at its widest and fine ribs on the shoulder.
        add(lathe([.init(0, 0.4), .init(0.3, 0.42), .init(0.62, 0.49), .init(0.88, 0.62), .init(0.99, 0.77),
                   .init(0.96, 0.9), .init(0.84, 0.99), .init(0.66, 1.04), .init(0.4, 1.065), .init(0, 1.075)],
                  segments: 720, steps: 28,
                  relief: { a, y in
                      let lobes = (pow(abs(cos(a * 13)), 0.45) - 0.6) * band(y, 0.45, 0.7) * min((y - 0.45) / 0.12, 1)
                      let belt = band(y, 0.755, 0.785)
                      let ribs = (cos(a * 90) * 0.5 + 0.5) * band(y, 0.92, 0.985)
                      return 1 + 0.045 * lobes + 0.018 * belt + 0.008 * ribs
                  }) { p in
            // Towards the front it is drawn out and pinched to a narrow wedge that the spout's base swallows.
            var q = p
            if p.x > 0 {
                let f = min(p.x, 1), g = pow(f, 1.6)
                q.x = p.x * (1 + 0.65 * f)
                q.y = 0.84 + (p.y - 0.84) * (1 - 0.62 * g) + 0.02 * f * f
                q.z = p.z * (1 - 0.58 * g)
            }
            return q
        })
        beads(52, radius: 0.6, size: 0.026, y: 1.05)

        // The lid: a notched collar, a fluted dome, a bead and a faceted flame-shaped knob.
        add(lathe([.init(0.56, 1.04), .init(0.6, 1.06), .init(0.61, 1.09), .init(0.61, 1.13), .init(0.57, 1.16),
                   .init(0.47, 1.18), .init(0.42, 1.21), .init(0.33, 1.27), .init(0.21, 1.33), .init(0.12, 1.37),
                   .init(0.085, 1.4), .init(0.1, 1.43), .init(0.07, 1.46), .init(0.1, 1.5), .init(0.145, 1.56),
                   .init(0.14, 1.63), .init(0.095, 1.71), .init(0.035, 1.78), .init(0, 1.8)],
                  segments: 720, steps: 28,
                  relief: { a, y in
                      let tooth = 0.5 + 0.5 * tanh(3 * cos(a * 28))
                      let flutes = pow(abs(cos(a * 12)), 0.5) * band(y, 1.2, 1.36) * (1.36 - y) / 0.16
                      let facets = abs(cos(a * 4)) * band(y, 1.5, 1.79)
                      return 1 + 0.03 * tooth * band(y, 1.075, 1.14) + 0.05 * flutes + 0.07 * facets
                  }))
        ring(0.47, 0.02, y: 1.18)
        ring(0.1, 0.018, y: 1.47)

        // The spout: wide where it leaves the body, with two raised rings, sweeping up to a flared lip.
        add(tube([.init(0.35, 0.83, 0), .init(1.8, 0.78, 0), .init(2.25, 0.95, 0), spoutTip],
                 radius: { t in 0.065 + 0.2 * pow(1 - t, 1.5) + 0.016 * bump(t, 0.5, 0.01) + 0.012 * bump(t, 0.78, 0.008)
                     + 0.02 * bump(t, 1, 0.03) },
                 rows: 600, segments: 128, squash: { t in 1 - 0.3 * (1 - t) }))
        let lip = SCNTorus(ringRadius: 0.085, pipeRadius: 0.018)
        lip.ringSegmentCount = 96
        lip.pipeSegmentCount = 32
        lip.materials = [mat]
        let lipNode = SCNNode(geometry: lip)
        lipNode.position = SCNVector3(spoutTip.x, spoutTip.y, spoutTip.z)
        lipNode.eulerAngles.z = -0.95
        lamp.addChildNode(lipNode)

        // The handle rises from the back of the body, loops over and comes back in, ending in a ball, with
        // a little curl on top for the thumb.
        let handle: [SIMD3<Float>] = [.init(-0.66, 1.0, 0), .init(-1.2, 1.62, 0), .init(-2.0, 1.25, 0), .init(-1.12, 0.66, 0)]
        add(tube(handle, radius: { t in 0.07 + 0.028 * sin(.pi * t) + 0.012 * bump(t, 0.06, 0.02) }, rows: 400, segments: 128,
                 squash: { _ in 0.75 }))
        ball(0.115, at: handle[3])
        let top = bezier(handle, 0.36)
        add(tube([top, top + SIMD3(0.05, 0.25, 0), top + SIMD3(0.32, 0.3, 0), top + SIMD3(0.3, 0.16, 0)],
                 radius: { t in 0.05 * (1 - 0.6 * t) }, rows: 160, segments: 64))
        ball(0.035, at: top + SIMD3(0.3, 0.16, 0))

        return lamp
    }

    /// An imaginary warm studio for the gold to reflect: a pale ceiling, a dark floor, dark panels and bright
    /// softboxes, so the metal has strong light and shade to show its shape against a pale page.
    static func environment() -> NSImage {
        let w = 1024, h = 512
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: w, pixelsHigh: h, bitsPerSample: 8,
                                   samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                   bytesPerRow: 0, bitsPerPixel: 0)!
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        let sky = NSGradient(colors: [NSColor(srgbRed: 0.08, green: 0.06, blue: 0.05, alpha: 1),
                                      NSColor(srgbRed: 0.3, green: 0.24, blue: 0.2, alpha: 1),
                                      NSColor(srgbRed: 0.98, green: 0.95, blue: 0.9, alpha: 1),
                                      NSColor(srgbRed: 0.45, green: 0.4, blue: 0.36, alpha: 1),
                                      NSColor(srgbRed: 0.97, green: 0.95, blue: 0.92, alpha: 1)],
                               atLocations: [0, 0.4, 0.5, 0.62, 1], colorSpace: .sRGB)!
        sky.draw(in: NSRect(x: 0, y: 0, width: w, height: h), angle: 90)
        // Dark panels between the lights give the reflections crisp edges.
        NSColor(srgbRed: 0.12, green: 0.1, blue: 0.09, alpha: 1).setFill()
        NSRect(x: 380, y: 270, width: 140, height: 200).fill()
        NSRect(x: 900, y: 260, width: 90, height: 220).fill()
        NSColor(white: 1, alpha: 1).setFill()
        NSBezierPath(roundedRect: NSRect(x: 150, y: 330, width: 200, height: 120), xRadius: 24, yRadius: 24).fill()
        NSBezierPath(roundedRect: NSRect(x: 620, y: 290, width: 90, height: 180), xRadius: 24, yRadius: 24).fill()
        NSRect(x: 0, y: 478, width: w, height: 18).fill()
        NSGraphicsContext.restoreGraphicsState()
        let image = NSImage(size: NSSize(width: w, height: h))
        image.addRepresentation(rep)
        return image
    }
}
