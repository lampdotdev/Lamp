import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", moods())
    reload(1); print("after1 (same edit as private-enum-grows, in Moods.swift; want a b c):", moods())
}}}
