import SwiftUI

/// The person's own details for their invoices: who they are, where, and how to pay them.
struct SettingsView: View {
    @EnvironmentObject private var model: HoursModel

    var body: some View {
        Form {
            Section("Your Details") {
                TextField("Name", text: $model.profile.name)
                TextField("Business", text: $model.profile.business, prompt: Text("Optional"))
                TextField("Address", text: $model.profile.address, axis: .vertical)
                    .lineLimit(2...4)
                TextField("Email", text: $model.profile.email)
                TextField("Tax ID", text: $model.profile.taxID, prompt: Text("Optional"))
            }
            Section("Getting Paid") {
                TextField("Payment details", text: $model.profile.payment,
                          prompt: Text("Bank account, IBAN or PayPal"), axis: .vertical)
                    .lineLimit(2...4)
                Stepper("Due in \(model.profile.paymentTermsDays) days", value: $model.profile.paymentTermsDays,
                        in: 0...120, step: 7)
                Stepper("Next invoice: \(model.profile.invoiceNumber)", value: $model.profile.nextInvoiceNumber,
                        in: 1...99_999)
            }
        }
        .formStyle(.grouped)
        .frame(width: 460)
        .fixedSize(horizontal: false, vertical: true)
    }
}
