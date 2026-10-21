import Foundation
import Observation
// Saves the settings whenever they change, as an app does to keep them.
@MainActor final class Saver {
    var saves = 0
    let settings: Settings
    init(_ s: Settings) { settings = s; watch() }
    func watch() {
        withObservationTracking { _ = settings.volume } onChange: { [weak self] in
            DispatchQueue.main.async { MainActor.assumeIsolated { self?.saves += 1; self?.watch() } }
        }
    }
}
