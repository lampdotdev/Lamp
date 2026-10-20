import Foundation
enum Mood: Hashable { case happy, sad, angry }
func check(_ x: Any) -> String {
    if let m = x as? Mood { return "\(m)" }
    if let a = x as? [Mood] { return "\(a.map { "\($0)" })" }
    if let h = x as? AnyHashable, h == AnyHashable(Mood.sad) { return "sad (hashable)" }
    return "not a Mood"
}
