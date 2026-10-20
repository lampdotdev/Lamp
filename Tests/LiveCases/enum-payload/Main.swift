import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", describe())
    reload(1); print("after1 (want v1):", describe())
    reload(2); print("after2 (want reopen, v1):", describe())
}}}
