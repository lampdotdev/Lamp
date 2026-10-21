import Foundation
extension Engine { func describe() -> String { name }; convenience init(_ n: String) { self.init(); name = n } }
func make() -> Engine { Engine("f") }
