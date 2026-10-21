import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    bump(); otherBump()
    print("before:", show(), "| other file reads:", otherShow())
    reload(1); bump(); otherBump()
    print("after1 (want one total, 7.0 in both files, and size 200.0 in both; or a reopen):", show(), "| other file reads:", otherShow())
}}}
