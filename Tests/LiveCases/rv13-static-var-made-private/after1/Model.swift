import Foundation
enum Counter {
    private static var count = 0
    static func bump() { count += 1 }
    static func report() -> Int { count }
}
