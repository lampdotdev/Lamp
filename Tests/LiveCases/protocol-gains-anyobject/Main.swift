import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let s = Store(); print("before:", total(s))
    reload(1); print("after1 (want reopen; a reload reads 40-byte existentials as 16-byte ones):", total(s)); add(s); print("after1 added:", total(s))
}}}
