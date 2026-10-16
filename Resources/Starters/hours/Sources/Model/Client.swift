import SwiftUI

/// Someone the person works for. Time is tracked against a client and billed at its rate, in its currency.
struct Client: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    /// Per hour, in `currency`.
    var rate: Double
    /// An ISO 4217 code, such as "USD" or "EUR".
    var currency: String
    /// A `ClientColor` name, stored as text so a color added later never breaks saved clients.
    var color: String
    /// Set on the sample clients, so Clear Examples removes exactly those.
    var isExample: Bool? = nil

    var tint: Color { (ClientColor(rawValue: color) ?? .gray).color }
    var nsTint: NSColor { (ClientColor(rawValue: color) ?? .gray).nsColor }
}

/// The colors a client can have: system colors, so they suit light and dark mode.
enum ClientColor: String, CaseIterable, Identifiable {
    case red, orange, yellow, green, mint, teal, blue, indigo, purple, pink, brown, gray

    var id: String { rawValue }
    var color: Color { Color(nsColor: nsColor) }

    var nsColor: NSColor {
        switch self {
        case .red: .systemRed
        case .orange: .systemOrange
        case .yellow: .systemYellow
        case .green: .systemGreen
        case .mint: .systemMint
        case .teal: .systemTeal
        case .blue: .systemBlue
        case .indigo: .systemIndigo
        case .purple: .systemPurple
        case .pink: .systemPink
        case .brown: .systemBrown
        case .gray: .systemGray
        }
    }
}

/// Currencies offered when adding a client. The person's own currency comes first.
enum Currencies {
    static let common: [String] = {
        let usual = ["USD", "EUR", "GBP", "CAD", "AUD", "NZD", "CHF", "SEK", "NOK", "DKK", "JPY", "BRL", "MXN", "INR"]
        let local = Locale.current.currency?.identifier ?? "USD"
        return [local] + usual.filter { $0 != local }
    }()
}
