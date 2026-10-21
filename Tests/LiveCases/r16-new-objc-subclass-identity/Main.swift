import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe(make()))
    reload(1)
    print("after1 (want boss kind=true size=1: a node subclass written beside its superclass is one of its, to Swift and to Objective-C):", describe(make()))
}}}
