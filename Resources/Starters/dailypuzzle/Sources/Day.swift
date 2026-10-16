import Foundation

/// A calendar day on this Mac's clock, saved as "2026-10-15". A puzzle belongs to the day it was played on, so
/// days are compared by their date alone, never by a moment in time.
struct Day: Hashable, Comparable, Identifiable, Codable {
    let year: Int
    let month: Int
    let day: Int

    var id: String { key }
    var key: String { String(format: "%04d-%02d-%02d", year, month, day) }

    init(_ date: Date, calendar: Calendar = .current) {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        year = parts.year ?? 2000
        month = parts.month ?? 1
        day = parts.day ?? 1
    }

    init(year: Int, month: Int, day: Int) {
        self.year = year
        self.month = month
        self.day = day
    }

    static var today: Day { Day(Date()) }

    /// Noon of this day here, which is safely inside the day whatever daylight saving does.
    var date: Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12)) ?? Date()
    }

    func adding(days: Int) -> Day {
        Day(Calendar.current.date(byAdding: .day, value: days, to: date) ?? date)
    }

    /// Days since 1 January 2024, counted on a fixed calendar so the same date gives the same number on every
    /// Mac, whatever its time zone: this is what picks the day's puzzle.
    var number: Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let epoch = calendar.date(from: DateComponents(year: 2024, month: 1, day: 1))!
        let this = calendar.date(from: DateComponents(year: year, month: month, day: day))!
        return calendar.dateComponents([.day], from: epoch, to: this).day ?? 0
    }

    static func < (a: Day, b: Day) -> Bool { a.key < b.key }

    // Saved as its key, so the data reads plainly.
    init(from decoder: Decoder) throws {
        let key = try decoder.singleValueContainer().decode(String.self)
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Not a day: \(key)"))
        }
        self.init(year: parts[0], month: parts[1], day: parts[2])
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(key)
    }
}
