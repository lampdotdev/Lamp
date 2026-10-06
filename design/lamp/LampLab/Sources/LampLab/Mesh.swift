import SceneKit
import AppKit
import simd

/// A grid of points that wraps around in `cols`, turned into a smooth SceneKit surface.
func gridGeometry(rows: Int, cols: Int, flip: Bool = false, _ point: (Int, Int) -> SIMD3<Float>) -> SCNGeometry {
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
func smooth(_ pts: [SIMD2<Float>], steps: Int = 8) -> [SIMD2<Float>] {
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
func lathe(_ profile: [SIMD2<Float>], segments: Int = 120, steps: Int = 8,
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
func tube(_ c: [SIMD3<Float>], radius: (Float) -> Float, rows: Int = 90, segments: Int = 48,
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

