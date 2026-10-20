import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    setvbuf(stdout, nil, _IONBF, 0)
    Thread.detachNewThread { Thread.sleep(forTimeInterval: 8); print("HANG"); exit(99) }
    let h = Holder()
    print("before:", describe(h))
    reload(1)
    print("after (want the same):", describe(h))
}}}
