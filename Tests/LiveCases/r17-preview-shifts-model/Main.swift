import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", Panel.caption)
    reload(1); print("after1 (want it in without reopening: a line added to a view whose file has a #Preview, in an app with a SwiftData model):", Panel.caption)
    reload(2); print("after2 (want it in: the same view changed within its lines, the #Preview where it was):", Panel.caption)
}}}
