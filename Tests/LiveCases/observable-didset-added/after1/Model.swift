import Foundation
import Observation
@Observable final class Model { var saved = 0; var dirty = false { didSet { saved += 1000 } } }
final class Plain { var saved = 0; var dirty = false { didSet { saved += 1000 } } }
func poke(_ m: Model, _ p: Plain) { m.dirty = true; p.dirty = true }
