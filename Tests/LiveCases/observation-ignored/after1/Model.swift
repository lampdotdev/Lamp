import Foundation
import Observation
@Observable final class Model { var n = 0; @ObservationIgnored var cache = 0 }
func probe(_ m: Model) -> String {
    var fired = false
    withObservationTracking({ _ = m.cache }, onChange: { fired = true })
    m.cache += 1
    return "ignored: fired=\(fired) cache=\(m.cache)"
}
