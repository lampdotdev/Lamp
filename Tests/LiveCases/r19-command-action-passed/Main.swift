import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let store = Store()
    store.refresh(); print("before:", Log.last)
    reload(1); store.refresh(); print("after1 (want v2 in place: the store's refresh runs when its menu item is chosen, passed to the button as a function, not at launch):", Log.last)
}}}
