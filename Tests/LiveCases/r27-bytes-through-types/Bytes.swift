import Foundation
enum Bytes { static func count() -> Int { makeValues().withUnsafeBytes { $0.count } } }
