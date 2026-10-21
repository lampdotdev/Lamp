import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Settings(), saver = Saver(s)
    s.louder(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    print("before:", saver.saves, s.volume)
    reload(1)
    s.louder(); RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.05))
    print("after1 (want 2 saves: the tracking set up before the change still hears volume change):", saver.saves, s.volume)
}}}
