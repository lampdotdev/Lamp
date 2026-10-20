import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let m = Model(); m.start()
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    print("before:", m.describe())
    reload(1)
    m.tab = .home
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.15))
    print("after (want about in cases, ticks growing):", m.describe())
    m.stop()
}}}
