import Foundation
enum Bytes {
    static func stride() -> Int { MemoryLayout<Vertex>.stride }
    static func count(_ v: [Vertex]) -> Int { v.withUnsafeBytes { $0.count } }
}
