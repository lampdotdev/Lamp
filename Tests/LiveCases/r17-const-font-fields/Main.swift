import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want amber in place: the typeface's font design, width and weight are plain values the app says hold no object):", show())
    reload(2); print("after2 (want brighter amber in place, the typeface kept):", show())
}}}
