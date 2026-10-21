import Foundation
import Observation
@Observable final class Model { var n = 0 }
func probe(_ m: Model) -> String { "n only" }
