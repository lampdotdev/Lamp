import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    print("before:", show())
    reload(1); print("after1 (want \"accent=2 soft=true\" in place, or a reopen saying why: Look holds an object, a formatter):", show())
}}}
