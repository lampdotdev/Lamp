import Foundation
// Summing a Data's bytes, as hashing or audio code does: nothing of the app's is laid out by hand.
func checksum(_ data: Data) -> Int { data.withUnsafeBytes { raw in raw.reduce(0) { $0 + Int($1) } } }
