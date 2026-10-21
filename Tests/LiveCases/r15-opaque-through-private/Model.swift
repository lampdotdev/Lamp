import Foundation
// An internal helper whose type is a private helper's: callers in other files learn it at run time.
struct Badge {
    func label() -> some CustomStringConvertible { text() }
    private func text() -> some CustomStringConvertible { 42 }
}
