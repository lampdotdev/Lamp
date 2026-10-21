import Foundation
enum Mood: Hashable { case calm, busy, away }
func dynamicEquals(_ a: Any, _ b: Any) -> Bool {
    guard let x = a as? any Equatable else { return false }
    func eq<T: Equatable>(_ x: T) -> Bool { (b as? T) == x }
    return eq(x)
}
func dynamicHash(_ a: Any) -> Int { (a as? AnyHashable)?.hashValue ?? -1 }
func probe() -> String {
    let values: [Any] = [Mood.calm, Mood.busy, Mood.away]
    let equal = values.map { dynamicEquals($0, $0) }
    let distinct = Set(values.map(dynamicHash)).count
    let awayVsCalm = dynamicEquals(Mood.away, Mood.calm)
    return "equal=\(equal) distinctHashes=\(distinct) awayEqualsCalm=\(awayVsCalm)"
}
