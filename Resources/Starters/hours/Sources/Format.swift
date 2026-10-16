import Foundation

/// How times and money are written everywhere in the app, so the list, the menu bar and the invoice agree.
enum Format {
    /// "1:05" for the menu bar, or "1:05:09" with seconds.
    static func clock(_ seconds: TimeInterval, withSeconds: Bool = false) -> String {
        let total = Int(seconds)
        let h = total / 3600, m = (total % 3600) / 60, s = total % 60
        return withSeconds ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", h, m)
    }

    /// "2h 15m", for a single entry.
    static func duration(_ seconds: TimeInterval) -> String {
        let minutes = Int((seconds / 60).rounded())
        let h = minutes / 60, m = minutes % 60
        if h == 0 { return "\(m)m" }
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }

    /// "12.5 h", for totals.
    static func hours(_ seconds: TimeInterval) -> String {
        (seconds / 3600).formatted(.number.precision(.fractionLength(0...1))) + " h"
    }

    /// "1.50", the hours column of an invoice.
    static func invoiceHours(_ hours: Double) -> String {
        hours.formatted(.number.precision(.fractionLength(2)))
    }

    static func money(_ amount: Double, _ currency: String) -> String {
        amount.formatted(.currency(code: currency))
    }

    static func month(_ interval: DateInterval) -> String {
        interval.start.formatted(.dateTime.month(.wide).year())
    }
}

extension Calendar {
    func week(containing date: Date) -> DateInterval {
        dateInterval(of: .weekOfYear, for: date) ?? DateInterval(start: startOfDay(for: date), duration: 7 * 86400)
    }

    func month(containing date: Date) -> DateInterval {
        dateInterval(of: .month, for: date) ?? DateInterval(start: startOfDay(for: date), duration: 30 * 86400)
    }
}
