import Foundation

/// What Lamp and the chat inside an app's window (the LampSidebar extension) say to each other: one JSON value
/// a line, over a connection on this Mac's own address. Lamp sends the chat as it should be shown;
/// the extension sends what the person did. Lamp draws nothing here and the extension decides nothing: it shows
/// the chat and passes on clicks and words, so all of what the chat does stays in Lamp.
public enum SidebarWire {
    public static func encode<T: Encodable>(_ value: T) -> Data? {
        guard var data = try? JSONEncoder().encode(value) else { return nil }
        data.append(0x0A)
        return data
    }

    /// Whole lines from `buffer`, taken out of it; a line still arriving stays.
    public static func lines(from buffer: inout Data) -> [Data] {
        var out: [Data] = []
        while let end = buffer.firstIndex(of: 0x0A) {
            out.append(buffer[buffer.startIndex..<end])
            buffer = Data(buffer[(end + 1)...])
        }
        return out
    }
}

/// The chat, as the sidebar shows it.
public struct SidebarState: Codable, Equatable {
    public var app: String
    public var lines: [SidebarLine]
    /// What the agent is doing now, while it works.
    public var working: String?
    public var draft: String
    /// Goes up when the draft was changed somewhere else (Lamp's window, a picture pointed at), so the sidebar
    /// takes it up; the words the sidebar sent itself come back with the same number and are left alone.
    public var draftVersion: Int
    public var attachments: [SidebarAttachment]

    public init(app: String, lines: [SidebarLine], working: String?, draft: String, draftVersion: Int, attachments: [SidebarAttachment]) {
        self.app = app
        self.lines = lines
        self.working = working
        self.draft = draft
        self.draftVersion = draftVersion
        self.attachments = attachments
    }
}

public struct SidebarLine: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case user, agent, status, error, ask, result }
    public var id: UUID
    public var kind: Kind
    public var text: String
    /// An open question card's questions.
    public var questions: [SidebarQuestion]?
    /// A result's step that wasn't tried, offered as Try It.
    public var untried: String?

    public init(id: UUID, kind: Kind, text: String, questions: [SidebarQuestion]? = nil, untried: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.questions = questions
        self.untried = untried
    }
}

public struct SidebarQuestion: Codable, Equatable {
    public var question: String
    public var options: [String]
    public var symbols: [String?]

    public init(question: String, options: [String], symbols: [String?]) {
        self.question = question
        self.options = options
        self.symbols = symbols
    }
}

public struct SidebarAttachment: Codable, Equatable {
    public var name: String
    public var thumbnail: Data?

    public init(name: String, thumbnail: Data?) {
        self.name = name
        self.thumbnail = thumbnail
    }
}

/// What the person did in the sidebar.
public enum SidebarCommand: Codable, Equatable {
    case send(String)
    case answer(UUID, [String])
    case tryIt(UUID)
    case draft(String)
    case removeAttachment(Int)
    case stop
}
