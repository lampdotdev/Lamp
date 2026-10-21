import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let read = Model(), unread = Model()
    print("before:", read.label)
    reload(1); print("after1 (want the same for both objects: \"b b\", or a reopen):", read.label, unread.label)
}}}
