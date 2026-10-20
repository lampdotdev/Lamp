import Foundation
import Observation
@Observable final class Model { var saved = 0 }
final class Plain { var saved = 0 }
func poke(_ m: Model, _ p: Plain) {}
