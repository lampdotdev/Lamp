import Foundation
enum K { static let size = 10 }
enum Board {
    static var area = K.size * K.size
    static func show() -> String { "\(K.size) \(area)" }
}
