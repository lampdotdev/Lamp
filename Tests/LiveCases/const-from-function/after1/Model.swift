import Foundation
enum K { static let table = build() }
func build() -> [Int] { [1, 2, 3] }
func table() -> [Int] { K.table }
