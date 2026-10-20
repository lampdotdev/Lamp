import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", String(describing: Settings.self), Item(name: "a").name)
    reload(1); print("after1:", Item(name: "a").name)
    reload(2); print("after2:", Item(name: "a").name)
}}}
