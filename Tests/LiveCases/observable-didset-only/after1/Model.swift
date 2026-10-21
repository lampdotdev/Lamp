import Foundation
import Observation
@Observable final class Model {
    var saved = 0
    var dirty = false { didSet { saved += 1000 } }
    func describe() -> String { "dirty=\(dirty)" }
}
func poke(_ m: Model) { m.dirty = true }
