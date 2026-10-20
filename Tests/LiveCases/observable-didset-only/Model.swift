import Foundation
import Observation
@Observable final class Model { var saved = 0; func describe() -> String { "" } }
func poke(_ m: Model) {}
