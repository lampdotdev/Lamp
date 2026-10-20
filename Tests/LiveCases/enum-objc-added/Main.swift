import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", show(s))
    reload(1); print("after1 (want reopen; a reload reads 1-byte values as 8-byte ones):", show(s))
}}}
