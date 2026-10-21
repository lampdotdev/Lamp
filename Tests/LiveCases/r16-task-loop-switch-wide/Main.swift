import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let engine = Engine.shared
    // The same loop as r16-thread-loop-switch-wide, as an async function in a task: Lamp sees it may still be running.
    Task.detached { await engine.run() }
    Thread.sleep(forTimeInterval: 0.2)
    print("before:", engine.seen())
    reload(1)
    pick(engine)
    // Long enough that a refused change's process is ended before it prints.
    Thread.sleep(forTimeInterval: 1.5)
    print("after1 (want the loop to see the new mode as itself, or a reopen: the loop is old code that switches over Mode):", engine.seen())
    engine.stop()
}}}
