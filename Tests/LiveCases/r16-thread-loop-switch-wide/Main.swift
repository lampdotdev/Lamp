import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let engine = Engine.shared
    // A worker started before the change, as a game or audio loop on its own thread would be.
    Thread.detachNewThread { engine.run() }
    Thread.sleep(forTimeInterval: 0.2)
    print("before:", engine.seen())
    reload(1)
    pick(engine)
    // Briefly: after a refused change the harness ends this copy, and the line has to come before that.
    Thread.sleep(forTimeInterval: 0.05)
    print("after1 (want the loop to see the new mode as itself, or a reopen: the loop is old code that switches over Mode):", engine.seen())
    engine.stop()
}}}
