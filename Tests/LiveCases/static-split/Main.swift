import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    bump(); bump(); bump()
    print("before:", report())
    reload(1)
    bump()
    print("after (want count=4 total=4 tag=t1 name=n1 flag=true, every value kept):", report())
    print("old code reads:", oldRead())
}}}
