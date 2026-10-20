import Foundation
struct A: Hashable { var volume = 1; var score = 0 }
struct B: Hashable { var volume = 1; var score = 0 }
func bump(_ a: inout A, _ b: inout B) { a.score = 7; b.score = 9 }
func show(_ a: A, _ b: B, _ b2: B) -> String { "aEqual=\(a == A()) bEqual=\(b == b2) bScore=\(scoreOf(b))" }
func scoreOf(_ b: B) -> Int { b.score }
