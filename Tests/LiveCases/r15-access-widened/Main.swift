import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want total=2: Shop's own price is visible to Use.swift now, and a member is found before a global):", show())
}}}
