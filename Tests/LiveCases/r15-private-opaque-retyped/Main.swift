import Foundation
import SwiftUI
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want 'a longer label than before' and HStack<Text>, the new code's own values):", show())
}}}
