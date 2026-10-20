import Foundation
@main struct Main { static func main() { MainActor.assumeIsolated {
    let p = Person(); var seen: [Int] = []
    let obs = p.observe(\.age, options: [.new]) { _, c in seen.append(c.newValue ?? -1) }
    p.birthday(); print("before:", seen)
    reload(1); p.birthday(); print("after (want [1, 3]):", seen, NSStringFromClass(object_getClass(p)!)); _ = obs
}}}
