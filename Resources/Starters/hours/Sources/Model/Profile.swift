import Foundation

/// The person's own details, printed at the top and foot of every invoice. Edited in Settings.
struct Profile: Codable, Equatable {
    var name = ""
    var business = ""
    var address = ""
    var email = ""
    var taxID = ""
    /// Bank account, PayPal or whatever the client should pay into.
    var payment = ""
    var paymentTermsDays = 14
    var nextInvoiceNumber = 1

    var isEmpty: Bool { name.isEmpty && business.isEmpty && payment.isEmpty }
    var invoiceNumber: String { String(format: "INV-%04d", nextInvoiceNumber) }
}
