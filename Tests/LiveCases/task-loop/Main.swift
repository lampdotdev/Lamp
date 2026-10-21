import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    let w = Worker()
    // A loop started before the change, as an agent's `Task { while true { await tick() } }` would be.
    Task { @MainActor in while w.running { w.step(); w.privateStep(); try? await Task.sleep(for: .milliseconds(20)) } }
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    print("before:", w.log.suffix(2))
    reload(1)
    w.log = []
    RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.2))
    print("after (want step-NEW, private stays old):", Set(w.log).sorted())
    w.running = false
}}}
