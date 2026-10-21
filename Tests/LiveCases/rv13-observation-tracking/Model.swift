import Foundation
import Observation
@Observable final class Settings { var volume = 1; func louder() { volume += 1 } }
