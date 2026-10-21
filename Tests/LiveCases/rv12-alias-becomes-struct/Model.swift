import Foundation
typealias Money = Int
final class Wallet { var amount: Money = 5; var label = "cash" }
func show(_ w: Wallet) -> String { "amount=\(w.amount) label=\(w.label)" }
