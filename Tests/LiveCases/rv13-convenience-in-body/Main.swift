import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", make().title)
    reload(1); print("after1 (want untitled, as with a convenience init in an extension):", make().title)
}}}
