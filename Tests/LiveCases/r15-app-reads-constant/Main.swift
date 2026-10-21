import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", title())
    reload(1); print("after1 (want a reopen: the App read the title once, at launch, for its window, which keeps it):", title())
}}}
