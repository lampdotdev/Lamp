import SwiftUI

/// One thing a school email asks of the person: a form, money, something to bring, a day that's different, a task.
struct Todo: Codable, Identifiable, Hashable {
    var id = UUID().uuidString
    var title: String
    var kind: Kind
    var due: Date?
    /// Whether `due` carries a time of day ("8:15 AM pickup") or is just the day.
    var hasTime = false
    /// Which child it's for, when the email says.
    var child: String?
    /// The email it came from, as Mail shows it.
    var from: String
    var subject: String
    var received: Date
    /// The sentence in the email it comes from.
    var quote: String?
    var emailKey: String?
    var done: Date?
    var reminderID: String?
    var eventID: String?
    var isExample: Bool?

    var isDone: Bool { done != nil }

    enum Kind: String, Codable, CaseIterable {
        case form, pay, bring, event, task

        var symbol: String {
            switch self {
            case .form: "signature"
            case .pay: "dollarsign.circle"
            case .bring: "bag"
            case .event: "calendar"
            case .task: "checklist"
            }
        }

        var color: Color {
            switch self {
            case .form: .blue
            case .pay: .green
            case .bring: .orange
            case .event: .purple
            case .task: .gray
            }
        }

        var name: String {
            switch self {
            case .form: "Form"
            case .pay: "Payment"
            case .bring: "Bring or wear"
            case .event: "Event"
            case .task: "To do"
            }
        }
    }
}

/// An email Backpack has already looked at, so it's never read twice.
struct SeenEmail: Codable, Identifiable {
    var id: String
    var subject: String
    var from: String
    var received: Date
    var isSchool: Bool
    var found: Int
}

struct BackpackSettings: Codable, Equatable {
    /// The children's first names, so each thing says who it's for.
    var children: [String] = []
    /// Addresses ("teacher@school.org") or whole domains ("@school.org") always read as school. Senders the AI was
    /// sure about are added here, so the person can see them and take one out.
    var schoolSenders: [String] = []
    /// Never read as school, whatever the AI thinks.
    var otherSenders: [String] = []
    var lookBackDays = 60
    var notify = true
    /// Set once the person has asked Backpack to read their Mail; until then it only shows its examples.
    var readsMail = false
}

/// What a sender line from Mail ("Ms. Alvarez <alvarez@oakwood.org>") is made of.
enum Sender {
    static func address(_ sender: String) -> String {
        if let open = sender.lastIndex(of: "<"), let close = sender.lastIndex(of: ">"), open < close {
            return String(sender[sender.index(after: open)..<close]).lowercased()
        }
        return sender.trimmingCharacters(in: .whitespaces).lowercased()
    }

    static func name(_ sender: String) -> String {
        guard let open = sender.lastIndex(of: "<") else { return sender }
        let name = sender[..<open].trimmingCharacters(in: CharacterSet(charactersIn: " \""))
        return name.isEmpty ? address(sender) : name
    }

    /// Whether a sender matches one of the person's entries: an address, or a domain written "@school.org".
    static func matches(_ sender: String, any entries: [String]) -> Bool {
        let address = address(sender)
        return entries.contains { entry in
            let entry = entry.lowercased().trimmingCharacters(in: .whitespaces)
            if entry.hasPrefix("@") { return address.hasSuffix(entry) || address.hasSuffix("." + entry.dropFirst()) }
            return address == entry
        }
    }
}
