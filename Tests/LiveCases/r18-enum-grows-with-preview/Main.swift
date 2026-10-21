import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want it in: Tone gained a case, and no #Preview names it):", show())
    reload(2); print("after2 (want it in, like after1: Mood gained a case, and only a #Preview, which never runs in the app, names it):", show())
}}}
