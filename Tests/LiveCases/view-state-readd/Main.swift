import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1:", describe())
    reload(2); print("after2:", describe())
    reload(3); print("after3:", describe())
}}}
