import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", probe())
    reload(1); print("after1 (want shown shown, or a reopen: an optional holding a Dot is a Dot whatever its field holds):", probe())
    reload(2); print("after2 (want shown shown, or a reopen):", probe())
}}}
