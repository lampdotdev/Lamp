import Foundation

/// What Lamp and the chat inside an app's window (the LampSidebar extension) say to each other: one JSON value
/// a line, over a connection on this Mac's own address. Lamp sends the chat as it should be shown;
/// the extension sends what the person did. Lamp draws nothing here and the extension decides nothing: it shows
/// the chat and passes on clicks and words, so all of what the chat does stays in Lamp.
public enum SidebarWire {
    /// What this side reads and writes; see `SidebarCommand.hello`. 3 added the cards and lines that ask
    /// something of the person, and the question card's own layout, words and progress.
    public static let version = 3

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
    /// What the agent is doing now, while it works, and since when.
    public var working: String?
    public var workingSince: Date?
    /// Nothing asked yet: the message box says so.
    public var empty: Bool
    /// The agent is at work, also while its questions wait: Stop shows.
    public var busy: Bool
    public var draft: String
    /// Goes up when the draft was changed somewhere else (Lamp's window, a picture pointed at), so the sidebar
    /// takes it up; the words the sidebar sent itself come back with the same number and are left alone.
    public var draftVersion: Int
    public var attachments: [SidebarAttachment]

    public init(app: String, lines: [SidebarLine], working: String?, workingSince: Date?, empty: Bool, busy: Bool,
                draft: String, draftVersion: Int, attachments: [SidebarAttachment]) {
        self.app = app
        self.lines = lines
        self.working = working
        self.workingSince = workingSince
        self.empty = empty
        self.busy = busy
        self.draft = draft
        self.draftVersion = draftVersion
        self.attachments = attachments
    }
}

public struct SidebarLine: Codable, Equatable, Identifiable {
    public enum Kind: String, Codable { case user, agent, status, error, ask, result, summary, setup, note, widget, action }
    public var id: UUID
    public var kind: Kind
    public var text: String
    /// The space above it, as Lamp's window has it.
    public var gap: Double
    /// A status step still going, with its spinner.
    public var running: Bool
    /// A request's pictures and files.
    public var attachments: [SidebarAttachment]?
    /// An agent's message that may still be growing.
    public var growing: Bool
    /// An open question card's questions.
    public var questions: [SidebarQuestion]?
    /// A result's step that wasn't tried, offered as Have Lamp Test It.
    public var untried: String?
    /// An open question card's layout: every question on one card rather than one at a time.
    public var together: Bool?
    /// How far the open card has been answered, and how many times that was changed in Lamp's window, so the
    /// sidebar takes up those changes and leaves alone the ones it sent itself.
    public var progress: AskProgress?
    public var progressVersion: Int?
    /// That version is this sidebar's own change coming back: it already shows it, and maybe more since.
    public var progressMine: Bool?
    public var setup: SetupContent?
    public var note: NoteContent?
    /// A widget's card: whether it's placed (its title is `text`, what to do `detail`).
    public var placed: Bool?
    public var detail: String?
    /// A line's one button, sent back as `SidebarCommand.act`: an icon to draw, iPhone setup, an error's Retry.
    public var symbol: String?
    public var button: String?
    public var enabled: Bool?

    public init(id: UUID, kind: Kind, text: String, gap: Double = 0, running: Bool = false, attachments: [SidebarAttachment]? = nil,
                growing: Bool = false, questions: [SidebarQuestion]? = nil, untried: String? = nil, together: Bool? = nil,
                progress: AskProgress? = nil, progressVersion: Int? = nil, setup: SetupContent? = nil, note: NoteContent? = nil,
                placed: Bool? = nil, detail: String? = nil, symbol: String? = nil, button: String? = nil, enabled: Bool? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.gap = gap
        self.running = running
        self.attachments = attachments
        self.growing = growing
        self.questions = questions
        self.untried = untried
        self.together = together
        self.progress = progress
        self.progressVersion = progressVersion
        self.setup = setup
        self.note = note
        self.placed = placed
        self.detail = detail
        self.symbol = symbol
        self.button = button
        self.enabled = enabled
    }
}

public struct SidebarQuestion: Codable, Equatable {
    public var question: String
    public var options: [String]
    public var symbols: [String?]
    /// Each answer's few words under its name.
    public var details: [String?]?

    public init(question: String, options: [String], symbols: [String?], details: [String?]? = nil) {
        self.question = question
        self.options = options
        self.symbols = symbols
        self.details = details
    }

    public init(_ question: CardQuestion) {
        self.init(question: question.question, options: question.options.map(\.title), symbols: question.options.map(\.symbol),
                  details: question.options.map(\.detail))
    }

    /// As the card draws it.
    public var card: CardQuestion {
        CardQuestion(question: question, options: options.indices.map { index in
            CardOption(title: options[index], detail: details.flatMap { $0.indices.contains(index) ? $0[index] : nil },
                       symbol: symbols.indices.contains(index) ? symbols[index] : nil)
        })
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
    /// The first thing a sidebar says: which shape of `SidebarState` it reads. One that says nothing is from
    /// before the summary line, which it can't read.
    case hello(Int)
    case send(String)
    case answer(UUID, [String])
    /// How far the person has got on a question card, so Lamp's window carries on from there.
    case progress(UUID, AskProgress)
    case setup(UUID, SetupAction)
    case undoNote(UUID)
    /// A line's one button (`SidebarLine.button`).
    case act(UUID)
    case tryIt(UUID)
    case draft(String)
    case removeAttachment(Int)
    /// Files pasted, dropped or chosen in the sidebar, which only it can read: their names and contents.
    case attach([SidebarFile])
    case stop
}

public struct SidebarFile: Codable, Equatable {
    public var name: String
    public var data: Data

    public init(name: String, data: Data) {
        self.name = name
        self.data = data
    }
}

/// Writes to a socket without ever waiting on it: what the other side hasn't taken yet stays here and goes as
/// it makes room. Both ends read on the main thread, so a blocking write while the other end is also writing
/// would leave each waiting for the other.
public final class SidebarOutbox {
    private let fd: Int32
    private var pending = Data()
    private var source: DispatchSourceWrite?
    /// Called when everything held has gone out.
    public var onDrain: (() -> Void)?

    public init(fd: Int32) {
        self.fd = fd
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    public var isHolding: Bool { !pending.isEmpty }

    public func send(_ data: Data) {
        pending.append(data)
        flush()
    }

    public func close() {
        source?.cancel()
        source = nil
        pending = Data()
    }

    private func flush() {
        while !pending.isEmpty {
            let written = pending.withUnsafeBytes { Darwin.write(fd, $0.baseAddress!, $0.count) }
            if written > 0 {
                pending.removeFirst(written)
            } else if written < 0, errno == EAGAIN || errno == EINTR {
                break
            } else {
                // The other end is gone: what's held won't go anywhere.
                pending = Data()
                break
            }
        }
        if pending.isEmpty {
            source?.cancel()
            source = nil
            onDrain?()
        } else if source == nil {
            let source = DispatchSource.makeWriteSource(fileDescriptor: fd, queue: .main)
            source.setEventHandler { [weak self] in self?.flush() }
            source.resume()
            self.source = source
        }
    }
}
