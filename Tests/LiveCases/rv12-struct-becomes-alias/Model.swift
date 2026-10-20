import Foundation
struct Money { var cents: Int; var currency: String }
final class Wallet { var amount: Money = Money(cents: 5, currency: "EUR"); var label = "cash" }
func show(_ w: Wallet) -> String { "amount=\(w.amount.cents) \(w.amount.currency) label=\(w.label)" }
