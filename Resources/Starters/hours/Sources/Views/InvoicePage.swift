import SwiftUI

/// The invoice as a printed page: US Letter width, black on white whatever the Mac's appearance, since it is
/// paper (or a PDF) in the end. The same view is shown in the app, saved as a PDF and printed.
struct InvoicePage: View {
    let invoice: Invoice

    static let width: CGFloat = 612

    private var profile: Profile { invoice.profile }
    private var currency: String { invoice.client.currency }
    private let ink = Color.black
    private let muted = Color(white: 0.42)
    private let rule = Color(white: 0.85)

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            header
            billTo
            table
            footer
        }
        .padding(48)
        .frame(width: Self.width, alignment: .topLeading)
        .frame(minHeight: 792, alignment: .top)
        .background(Color.white)
        .foregroundStyle(ink)
        .environment(\.colorScheme, .light)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(profile.business.isEmpty ? profile.name : profile.business)
                    .font(.system(size: 18, weight: .semibold))
                if !profile.business.isEmpty, !profile.name.isEmpty { small(profile.name) }
                if !profile.address.isEmpty { small(profile.address) }
                if !profile.email.isEmpty { small(profile.email) }
                if !profile.taxID.isEmpty { small("Tax ID: \(profile.taxID)") }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 3) {
                Text("Invoice").font(.system(size: 26, weight: .light)).textCase(.uppercase).tracking(2)
                small(invoice.number)
                small("Issued \(invoice.issued.formatted(date: .long, time: .omitted))")
                small("Due \(invoice.due.formatted(date: .long, time: .omitted))")
            }
        }
    }

    private var billTo: some View {
        VStack(alignment: .leading, spacing: 3) {
            label("Bill to")
            Text(invoice.client.name).font(.system(size: 13, weight: .medium))
            small("Work in \(Format.month(invoice.month)), at \(Format.money(invoice.client.rate, currency)) an hour")
        }
    }

    private var table: some View {
        let showsDate = invoice.lines.contains { $0.date != nil }
        return Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 8) {
            GridRow {
                if showsDate { label("Date") }
                label("Description")
                label("Hours").gridColumnAlignment(.trailing)
                label("Amount").gridColumnAlignment(.trailing)
            }
            Divider().overlay(rule)
            if invoice.lines.isEmpty {
                Text("No time tracked this month.").font(.system(size: 11)).foregroundStyle(muted)
            }
            ForEach(invoice.lines) { line in
                GridRow(alignment: .firstTextBaseline) {
                    if showsDate {
                        Text(line.date?.formatted(.dateTime.day().month(.abbreviated)) ?? "")
                            .fixedSize()
                    }
                    Text(line.description).frame(maxWidth: .infinity, alignment: .leading)
                    Text(Format.invoiceHours(line.hours))
                    Text(Format.money(line.amount, currency))
                }
                .font(.system(size: 11))
                .monospacedDigit()
            }
            Divider().overlay(rule)
            GridRow {
                if showsDate { Color.clear.gridCellUnsizedAxes([.horizontal, .vertical]) }
                Text("Total").font(.system(size: 12, weight: .semibold))
                Text(Format.invoiceHours(invoice.totalHours)).font(.system(size: 11))
                Text(Format.money(invoice.total, currency)).font(.system(size: 14, weight: .semibold))
            }
            .monospacedDigit()
        }
    }

    private var footer: some View {
        VStack(alignment: .leading, spacing: 3) {
            if !profile.payment.isEmpty {
                label("Payment")
                small(profile.payment)
            }
            small("Please pay within \(profile.paymentTermsDays) days. Thank you!")
                .padding(.top, 6)
        }
    }

    private func label(_ text: String) -> some View {
        Text(text).font(.system(size: 9, weight: .semibold)).textCase(.uppercase).tracking(0.8).foregroundStyle(muted)
    }

    private func small(_ text: String) -> some View {
        Text(text).font(.system(size: 11)).foregroundStyle(muted).fixedSize(horizontal: false, vertical: true)
    }
}
