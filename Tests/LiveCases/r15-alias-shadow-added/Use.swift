import Foundation
// Unchanged by either change: what `Item` means here is decided by what Shop declares.
extension Shop { func count() -> Int { Item().value } }
func show() -> String { "count=\(Shop().count())" }
