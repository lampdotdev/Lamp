import Foundation
struct Allman
{
    var a = 1
}
struct Plain { var a = 1 }
func show() -> String { "\(Allman().a) \(Plain().a)" }
