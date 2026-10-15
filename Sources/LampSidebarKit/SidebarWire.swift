import Foundation

/// What Lamp and the chat inside an app's window (the LampSidebar extension) say to each other: one JSON value
/// a line, over a connection on this Mac's own address. Lamp sends the chat as it should be shown;
/// the extension sends what the person did. Lamp draws nothing here and the extension decides nothing: it shows
/// the chat and passes on clicks and words, so all of what the chat does stays in Lamp.
public enum SidebarWire {
    /// What this side reads and writes; see `SidebarCommand.hello`.
    public static let version = 2

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
    // Optional, like everything added since the first sidebar: a sidebar talking to a Lamp from before these
    // were sent still reads its chat.
    /// Messages waiting for the current change to finish.
    public var queued: [SidebarQueued]?
    /// The first request is waiting for Apple's tools to install, not for a turn.
    public var waitingForSetup: Bool?
    /// A command or file the agent is asking to use, waiting for an answer.
    public var approval: SidebarApproval?
    /// The app was asked to quit and isn't responding: what the notice says.
    public var notResponding: String?

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
    public enum Kind: String, Codable { case user, agent, status, error, ask, result, summary }
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
    /// The agent's questions as Lamp's window draws them, whether they still wait for an answer, and how far
    /// they've been answered (in either chat).
    public var ask: TalkCard.Ask?
    public var askOpen: Bool?
    public var progress: AskProgress?
    /// What a request made as Lamp's window draws it, whether its Try It still applies, and its picture.
    public var result: TalkCard.Result?
    public var resultCurrent: Bool?
    public var picture: Data?

    public init(id: UUID, kind: Kind, text: String, gap: Double = 0, running: Bool = false, attachments: [SidebarAttachment]? = nil,
                growing: Bool = false, questions: [SidebarQuestion]? = nil, untried: String? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.gap = gap
        self.running = running
        self.attachments = attachments
        self.growing = growing
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

public struct SidebarQueued: Codable, Equatable, Identifiable {
    public var id: UUID
    public var text: String
    public var attachments: [SidebarAttachment]

    public init(id: UUID, text: String, attachments: [SidebarAttachment]) {
        self.id = id
        self.text = text
        self.attachments = attachments
    }
}

public struct SidebarApproval: Codable, Equatable {
    public var id: UUID
    public var title: String
    public var command: String
    public var explanation: ChatLook.Explanation?

    public init(id: UUID, title: String, command: String, explanation: ChatLook.Explanation?) {
        self.id = id
        self.title = title
        self.command = command
        self.explanation = explanation
    }
}

public struct SidebarAttachment: Codable, Equatable {
    public var name: String
    /// A small picture: of the picture itself, or the file's icon.
    public var thumbnail: Data?
    /// A picture, shown as itself in a request; any other file is a chip.
    public var isImage: Bool?

    public init(name: String, thumbnail: Data?, isImage: Bool? = nil) {
        self.name = name
        self.thumbnail = thumbnail
        self.isImage = isImage
    }
}

/// What the person did in the sidebar.
public enum SidebarCommand: Codable, Equatable {
    /// The first thing a sidebar says: which shape of `SidebarState` it reads. One that says nothing is from
    /// before the summary line, which it can't read.
    case hello(Int)
    case send(String)
    case answer(UUID, [String])
    case tryIt(UUID)
    case draft(String)
    case removeAttachment(Int)
    /// How far an open card has been answered, as it changes, so the other chat carries on from there.
    case askProgress(UUID, AskProgress)
    /// Files pasted, dropped or chosen in the sidebar, which only it can read: their names and contents.
    case attach([SidebarFile])
    case stop
    case unqueue(UUID)
    /// The answer to the approval with this id.
    case approve(UUID, allow: Bool, allowAll: Bool)
    case forceQuit
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

/// What the app hosting the sidebar tells it over their own connection: where the sidebar's lower left corner is on
/// screen, so its message box reports its caret where it really is (`Composer.hostOrigin`). The only thing the app
/// can say to it, and nothing that reaches Lamp. LampSupport.swift declares the same.
@objc(LampSidebarPlacement) public protocol SidebarPlacement {
    func place(x: Double, y: Double)
}
