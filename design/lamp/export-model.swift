import SceneKit
import SceneKit.ModelIO
import ModelIO

// Export the production geometry, so the offline artwork starts with the same silhouette.
@main struct ExportLamp {
    static func main() throws {
        let stage = LampStage()
        let lamp = stage.scene.rootNode.childNodes[0]
        let url = URL(fileURLWithPath: CommandLine.arguments[1])
        FileManager.default.createFile(atPath: url.path, contents: nil)
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        var offset = 1
        var count = 0
        lamp.enumerateHierarchy { node, _ in
            guard let geometry = node.geometry else { return }
            // Model I/O tessellates SceneKit's primitives. Bake every node's transform
            // explicitly; exporting the hierarchy loses some primitive placements.
            let mesh = SCNGeometry(mdlMesh: MDLMesh(scnGeometry: geometry))
            guard let source = mesh.sources(for: .vertex).first else { return }
            var text = "o part\(count)\n"
            source.data.withUnsafeBytes { bytes in
                for i in 0..<source.vectorCount {
                    let p = source.dataOffset + i * source.dataStride
                    let v = SIMD3<Float>(bytes.loadUnaligned(fromByteOffset: p, as: Float.self),
                                         bytes.loadUnaligned(fromByteOffset: p + 4, as: Float.self),
                                         bytes.loadUnaligned(fromByteOffset: p + 8, as: Float.self))
                    let world = node.simdConvertPosition(v, to: nil)
                    text += "v \(world.x) \(world.y) \(world.z)\n"
                }
            }
            for element in mesh.elements where element.primitiveType == .triangles {
                element.data.withUnsafeBytes { bytes in
                    for triangle in 0..<element.primitiveCount {
                        var face = "f"
                        for corner in 0..<3 {
                            let p = (triangle * 3 + corner) * element.bytesPerIndex
                            let index: Int
                            switch element.bytesPerIndex {
                            case 2: index = Int(bytes.loadUnaligned(fromByteOffset: p, as: UInt16.self))
                            case 4: index = Int(bytes.loadUnaligned(fromByteOffset: p, as: UInt32.self))
                            default: index = Int(bytes.loadUnaligned(fromByteOffset: p, as: UInt8.self))
                            }
                            face += " \(offset + index)"
                        }
                        text += face + "\n"
                    }
                }
            }
            try! file.write(contentsOf: Data(text.utf8))
            offset += source.vectorCount
            count += 1
        }
        print("Exported \(count) parts, \(offset - 1) vertices")
    }
}
