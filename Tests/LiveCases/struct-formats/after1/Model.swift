import Foundation
struct Allman
{
    var a = 1
    var b = 2
}
struct Plain { var a = 1; var b = 2 }
func show() -> String { "\(Allman().a) \(Allman().b) \(Plain().a) \(Plain().b)" }
