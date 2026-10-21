import Foundation
struct Plain { var a = 1 }
func checksum(_ d: Data) -> Int { d.withUnsafeBytes { $0.reduce(0) { $0 &+ Int($1) } } }
func show() -> String { "\(Plain().a) \(checksum(Data([1,2])))" }
