import SceneKit
import simd

// Procedural geometry for Blender export. Lighting, materials, and cameras live in render-onboarding.py.

// MARK: - The model

/// A grid of points that wraps around in `cols`, turned into a smooth SceneKit surface.
private func gridGeometry(rows: Int, cols: Int, flip: Bool = false, _ point: (Int, Int) -> SIMD3<Float>) -> SCNGeometry {
    var p = [SIMD3<Float>](repeating: .zero, count: rows * cols)
    for i in 0..<rows { for j in 0..<cols { p[i * cols + j] = point(i, j) } }
    func at(_ i: Int, _ j: Int) -> SIMD3<Float> { p[min(max(i, 0), rows - 1) * cols + (j + cols) % cols] }
    var normals = [SIMD3<Float>]()
    for i in 0..<rows {
        for j in 0..<cols {
            let du = at(i, j + 1) - at(i, j - 1)
            var dv = at(i + 1, j) - at(i - 1, j)
            // At a pole the ring collapses; look one ring further in.
            if simd_length(du) < 1e-5 { dv = at(i + 1, j) - at(i - 1, j) }
            var n = flip ? simd_cross(du, dv) : simd_cross(dv, du)
            if simd_length(n) < 1e-9 { n = SIMD3(0, i == 0 ? -1 : 1, 0) }
            normals.append(simd_normalize(n))
        }
    }
    var idx = [UInt32]()
    for i in 0..<(rows - 1) {
        for j in 0..<cols {
            let a = UInt32(i * cols + j), b = UInt32(i * cols + (j + 1) % cols)
            let c = UInt32((i + 1) * cols + (j + 1) % cols), d = UInt32((i + 1) * cols + j)
            idx += [a, b, c, a, c, d]
        }
    }
    let vs = SCNGeometrySource(vertices: p.map { SCNVector3($0.x, $0.y, $0.z) })
    let ns = SCNGeometrySource(normals: normals.map { SCNVector3($0.x, $0.y, $0.z) })
    return SCNGeometry(sources: [vs, ns], elements: [SCNGeometryElement(indices: idx, primitiveType: .triangles)])
}

/// Catmull-Rom through the profile points, so a handful of numbers make a smooth silhouette.
private func smooth(_ pts: [SIMD2<Float>], steps: Int = 8) -> [SIMD2<Float>] {
    var out = [SIMD2<Float>]()
    for k in 0..<(pts.count - 1) {
        let p0 = pts[max(k - 1, 0)], p1 = pts[k], p2 = pts[k + 1], p3 = pts[min(k + 2, pts.count - 1)]
        for s in 0..<steps {
            let t = Float(s) / Float(steps), t2 = t * t, t3 = t2 * t
            let a: SIMD2<Float> = 2 * p1
            let b: SIMD2<Float> = p2 - p0
            var c: SIMD2<Float> = 2 * p0 - 5 * p1
            c += 4 * p2 - p3
            var d: SIMD2<Float> = 3 * p1 - p0
            d += p3 - 3 * p2
            let sum: SIMD2<Float> = a + b * t + c * t2 + d * t3
            out.append(0.5 * sum)
        }
    }
    out.append(pts.last!)
    return out
}

/// A surface of revolution from (radius, height) points, bottom to top. `relief` scales the radius by angle
/// and height (for fluting and petals); `warp` bends the result.
private func lathe(_ profile: [SIMD2<Float>], segments: Int = 120, steps: Int = 8,
           relief: (Float, Float) -> Float = { _, _ in 1 },
           warp: (SIMD3<Float>) -> SIMD3<Float> = { $0 }) -> SCNGeometry {
    let prof = smooth(profile, steps: steps)
    return gridGeometry(rows: prof.count, cols: segments, flip: true) { i, j in
        let a = Float(j) / Float(segments) * 2 * .pi
        let r = max(prof[i].x * relief(a, prof[i].y), 0.002)
        return warp(SIMD3(r * cos(a), prof[i].y, r * sin(a)))
    }
}

/// A tube along a cubic Bézier, its radius changing along the way.
private func tube(_ c: [SIMD3<Float>], radius: (Float) -> Float, rows: Int = 90, segments: Int = 48,
          squash: (Float) -> Float = { _ in 1 }) -> SCNGeometry {
    func at(_ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        let a: SIMD3<Float> = (u * u * u) * c[0] + (3 * u * u * t) * c[1]
        let b: SIMD3<Float> = (3 * u * t * t) * c[2] + (t * t * t) * c[3]
        return a + b
    }
    // The curves here lie in the xy plane, so z is a steady binormal: no twisting frames needed.
    let side = SIMD3<Float>(0, 0, 1)
    return gridGeometry(rows: rows, cols: segments, flip: true) { i, j in
        let t = Float(i) / Float(rows - 1)
        let tangent = simd_normalize(at(min(t + 0.001, 1)) - at(max(t - 0.001, 0)))
        let normal = simd_normalize(simd_cross(side, tangent))
        let a = Float(j) / Float(segments) * 2 * .pi
        let r = radius(t)
        return at(t) + r * squash(t) * cos(a) * normal + r * sin(a) * side
    }
}


enum LampModel {
    static let spoutTip = SIMD3<Float>(2.5, 1.3, 0)

    /// A soft-edged band between two heights, 0 outside it and 1 in the middle.
    static func band(_ y: Float, _ from: Float, _ to: Float) -> Float {
        let edge: Float = 0.012
        let a = min(max((y - from) / edge, 0), 1), b = min(max((to - y) / edge, 0), 1)
        return a * b
    }

    static func bump(_ t: Float, _ at: Float, _ width: Float) -> Float { exp(-pow((t - at) / width, 2)) }

    static func bezier(_ c: [SIMD3<Float>], _ t: Float) -> SIMD3<Float> {
        let u = 1 - t
        let a: SIMD3<Float> = (u * u * u) * c[0] + (3 * u * u * t) * c[1]
        let b: SIMD3<Float> = (3 * u * t * t) * c[2] + (t * t * t) * c[3]
        return a + b
    }

    static func node(material: SCNMaterial) -> SCNNode {
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
                      // The decoration fades out towards the front, which is drawn out into the spout: stretched,
                      // it would turn into sharp ridges.
                      let back = 1 - min(max((cos(a) - 0.45) / 0.4, 0), 1)
                      let lobes = (pow(abs(cos(a * 13)), 0.45) - 0.6) * band(y, 0.45, 0.7) * min((y - 0.45) / 0.12, 1)
                      let belt = band(y, 0.755, 0.785)
                      let ribs = (cos(a * 90) * 0.5 + 0.5) * band(y, 0.92, 0.985)
                      return 1 + back * (0.045 * lobes + 0.018 * belt + 0.008 * ribs)
                  }) { p in
            // Towards the front it is drawn out and narrowed evenly all round, so it stays rounded where the
            // spout leaves it rather than flattening into a fin.
            var q = p
            if p.x > 0 {
                let f = min(p.x, 1), g = pow(f, 1.6)
                q.x = p.x * (1 + 0.5 * f)
                q.y = 0.84 + (p.y - 0.84) * (1 - 0.5 * g) + 0.02 * f * f
                q.z = p.z * (1 - 0.5 * g)
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
        let spout: [SIMD3<Float>] = [.init(0.35, 0.83, 0), .init(1.8, 0.78, 0), .init(2.25, 0.95, 0), spoutTip]
        let spoutRadius: (Float) -> Float = { t in 0.065 + 0.2 * pow(1 - t, 1.5) }
        let spoutSquash: (Float) -> Float = { t in 1 - 0.3 * (1 - t) }
        add(tube(spout, radius: { t in spoutRadius(t) + 0.016 * bump(t, 0.5, 0.01) + 0.012 * bump(t, 0.78, 0.008)
                     + 0.02 * bump(t, 1, 0.03) },
                 rows: 600, segments: 128, squash: spoutSquash))
        // A collar where the spout leaves the body, as on a cast lamp, so the two meet in a clean join:
        // a rounded band and a thin ring just ahead of it, following the spout's oval section.
        let leaves = stride(from: Float(0), through: 1, by: 0.005).min { abs(bezier(spout, $0).x - 1.44) < abs(bezier(spout, $1).x - 1.44) }!
        for (t, pipe) in [(leaves, Float(0.034)), (leaves + 0.035, Float(0.016))] {
            let centre = bezier(spout, t)
            let along = simd_normalize(bezier(spout, min(t + 0.002, 1)) - bezier(spout, max(t - 0.002, 0)))
            let across = simd_normalize(simd_cross(SIMD3(0, 0, 1), along))
            let collar = SCNTorus(ringRadius: CGFloat(spoutRadius(t) + pipe * 0.6), pipeRadius: CGFloat(pipe))
            collar.ringSegmentCount = 160
            collar.pipeSegmentCount = 32
            collar.materials = [mat]
            let node = SCNNode(geometry: collar)
            // The torus rings its own y axis: turn that along the spout, and squash it to the spout's oval.
            node.simdOrientation = simd_quatf(simd_float3x3(columns: (across, along, simd_cross(across, along))))
            node.simdScale = SIMD3(spoutSquash(t), 1, 1)
            node.simdPosition = centre
            lamp.addChildNode(node)
        }
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


}
