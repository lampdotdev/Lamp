import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let doc = Doc(); print("before:", doc.describe())
    reload(1); print("after1 (want bold=true italic=true, or a reopen: the open app's value was made with the old bits):", doc.describe())
}}}
