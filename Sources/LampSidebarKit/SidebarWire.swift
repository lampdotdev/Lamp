import Foundation

/// What Lamp and the chat inside an app's window (the LampSidebar extension) say to each other: one JSON value
/// a line, over a connection on this Mac's own address. Lamp sends the chat as it should be shown;
/// the extension sends what the person did. Lamp draws nothing here and the extension decides nothing: it shows
/// the chat and passes on clicks and words, so all of what the chat does stays in Lamp.
public enum SidebarWire {
    /// What this side reads and writes; see `SidebarCommand.hello`.
    public static let version = 6

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
    /// A request taken back into the message box to change and send again: Escape puts it back.
    public var replacing: Bool?
    /// Only the end of a long chat is here; more is sent when asked (`SidebarCommand.earlier`).
    public var hasEarlier: Bool?
    /// What the message box offers while it's empty, for Tab to take.
    public var suggestion: String?
    /// Lamp is listening to dictation for this chat, and whether this Mac can dictate at all.
    public var listening: Bool?
    public var canDictate: Bool?
    /// Why dictation didn't start or stopped, and the button to the System Settings page that fixes it, if any.
    public var dictationProblem: SidebarProblem?
    /// A message is on its way in (Lamp's window or this one sent it): nothing else is sent meanwhile.
    public var submitting: Bool?
    /// How many messages Lamp has taken from the sidebar's box, which a Send says back (`SidebarCommand.send`).
    /// Kept apart from `draftVersion`: taking the words doesn't change the box, which waits for the draft.
    public var sends: Int?
    /// What was pointed at in the app, on its own pill in the message box. Its picture counts as the attachment
    /// after the last of `attachments`, for `SidebarCommand.preview` and `removeAttachment`.
    public var pointed: SidebarPointed?
    /// The version the latest change made, when Undo Last Change is offered under it (`SidebarCommand.undoChange`).
    public var undoChange: String?
    /// The buttons above the chat, as Lamp's window has them in its toolbar.
    public var toolbar: SidebarToolbar?
    /// The panel open in place of the chat, as the sidebar asked for it (`SidebarCommand.panel`), with what it shows.
    public var panel: SidebarPanel?
    public var versions: [SidebarVersion]?
    public var info: [SidebarInfoSection]?
    /// The wish's file after Share…, for the sidebar's own share menu: sent once, since only the sidebar can show
    /// that menu where the button is, and it can't read Lamp's files.
    public var sharing: SidebarSharing?

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
    public enum Kind: String, Codable { case user, agent, status, error, ask, result, summary, note, offer, action, tools }
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
    /// The agent's questions as Lamp's window draws them, whether they still wait for an answer, and how far
    /// they've been answered (in either chat).
    public var ask: TalkCard.Ask?
    public var askOpen: Bool?
    public var progress: AskProgress?
    /// Goes up when the progress changed in Lamp's window, so the sidebar takes it up; its own edits come back
    /// with the same number and are left alone, so an echo of an older one never undoes a newer one.
    public var progressVersion: Int?
    /// What a request made as Lamp's window draws it.
    public var result: TalkCard.Result?
    /// A receipt for a save of Lamp's notes (its title is `text`): the lines added and removed, whether it was
    /// taken back, and what went wrong taking it back.
    public var added: [String]?
    public var removed: [String]?
    public var undone: Bool?
    public var problem: String?
    /// An offer's card (`offer`: a setup offer, the widget card) or line (`action`: Draw Icon, iPhone setup):
    /// its symbol, its status line (the title, or the line's words, is `text`), whether it's done, and its
    /// button, if any, with what the button does (`SidebarCommand.offer`).
    public var symbol: String?
    public var status: String?
    public var done: Bool?
    public var button: String?
    public var disabled: Bool?
    /// A request's buttons: going back to how the app was around it, and taking it back to change it.
    public var canGoBack: Bool?
    public var canSendAgain: Bool?
    public var isLatest: Bool?
    /// What a request pointed at in the app, its picture counting as the attachment after the last of `attachments`.
    public var pointed: SidebarPointed?
    /// The agent's steps, shown with Agent Details on (`tools`): what `text` sums up, one by one.
    public var calls: [SidebarToolCall]?

    public init(id: UUID, kind: Kind, text: String, gap: Double = 0, running: Bool = false, attachments: [SidebarAttachment]? = nil,
                growing: Bool = false, questions: [SidebarQuestion]? = nil) {
        self.id = id
        self.kind = kind
        self.text = text
        self.gap = gap
        self.running = running
        self.attachments = attachments
        self.growing = growing
        self.questions = questions
    }
}

/// One of the agent's steps as Agent Details shows it: its symbol, what it did, and to what.
public struct SidebarToolCall: Codable, Equatable {
    public var symbol: String
    public var verb: String
    public var argument: String

    public init(symbol: String, verb: String, argument: String) {
        self.symbol = symbol
        self.verb = verb
        self.argument = argument
    }
}

/// Which of Lamp's toolbar buttons can do something now, and what Agent Details is set to.
public struct SidebarToolbar: Codable, Equatable {
    /// There's a change to undo, and nothing running.
    public var canUndo: Bool
    /// The wish has been made: there's a file to share.
    public var canShare: Bool
    /// It has versions to look back at.
    public var hasVersions: Bool
    public var details: Bool
    /// What the app's AI has cost ("AI: 3 calls · $0.02"), when it has used any.
    public var usage: String?

    public init(canUndo: Bool, canShare: Bool, hasVersions: Bool, details: Bool, usage: String?) {
        self.canUndo = canUndo
        self.canShare = canShare
        self.hasVersions = hasVersions
        self.details = details
        self.usage = usage
    }
}

public enum SidebarPanel: String, Codable { case versions, info }

/// A saved version, as the Versions panel lists it: newest first, with a small picture of how the app looked.
public struct SidebarVersion: Codable, Equatable, Identifiable {
    public var id: String
    public var label: String
    public var named: Bool
    public var date: Date
    public var current: Bool
    public var picture: Data?

    public init(id: String, label: String, named: Bool, date: Date, current: Bool, picture: Data?) {
        self.id = id
        self.label = label
        self.named = named
        self.date = date
        self.current = current
        self.picture = picture
    }
}

/// A part of the app's info panel: its rows, and the buttons under them (`SidebarCommand.infoAction`).
public struct SidebarInfoSection: Codable, Equatable, Identifiable {
    public var id: String { title ?? "" }
    public var title: String?
    public var rows: [SidebarInfoRow]
    public var buttons: [SidebarInfoButton]

    public init(title: String?, rows: [SidebarInfoRow], buttons: [SidebarInfoButton] = []) {
        self.title = title
        self.rows = rows
        self.buttons = buttons
    }
}

/// A fact: its label and its value, or Not Ready when nothing answers.
public struct SidebarInfoRow: Codable, Equatable {
    public var label: String
    public var value: String?

    public init(label: String, value: String?) {
        self.label = label
        self.value = value
    }
}

public struct SidebarInfoButton: Codable, Equatable {
    public var title: String
    /// What it does, Lamp's to know.
    public var action: String

    public init(title: String, action: String) {
        self.title = title
        self.action = action
    }
}

public struct SidebarSharing: Codable, Equatable {
    public var id: UUID
    public var file: SidebarFile

    public init(id: UUID, file: SidebarFile) {
        self.id = id
        self.file = file
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
    public var pointed: SidebarPointed?
    /// Send Now, for every waiting message, is offered under it (the latest of them, `Store.canSendNow`); or it was
    /// sent now and is on its way.
    public var canSendNow: Bool?
    public var sendingNow: Bool?

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

/// What was pointed at in the app: what it is, what it's part of, and whether it can be pointed at again now
/// (the app is open on this Mac). Its picture stays in Lamp and is shown from there (`SidebarCommand.preview`).
public struct SidebarPointed: Codable, Equatable {
    public var title: String
    public var detail: String?
    public var canChooseAgain: Bool?

    public init(title: String, detail: String?, canChooseAgain: Bool? = nil) {
        self.title = title
        self.detail = detail
        self.canChooseAgain = canChooseAgain
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
    /// before the summary line, which it can't read; one before 3, from before the notes receipt; one before 4, from before offers;
    /// one before 5, from before what was pointed at had a pill of its own; one before 6, from before the agent's
    /// steps (`SidebarLine.Kind.tools`) could be shown.
    case hello(Int)
    /// The message box's words, and how many of the box's messages Lamp had taken when it last said
    /// (`SidebarState.sends`): a Return pressed again before the sidebar hears that they were sent is for words Lamp
    /// has already sent, and does nothing. A sidebar from before the count sends none.
    case send(String, sends: Int? = nil)
    case answer(UUID, [String])
    case draft(String)
    case removeAttachment(Int)
    /// Point at something else in the app for the message box's card.
    case pointAgain
    /// How far an open card has been answered, as it changes, so the other chat carries on from there.
    case askProgress(UUID, AskProgress)
    /// Takes back the save of Lamp's notes this receipt is for.
    case undoNote(UUID)
    /// Undo Last Change, under the change that made this version.
    case undoChange(String)
    /// The button on an offer's card or line: what it does is Lamp's to know, by the line.
    case offer(UUID)
    /// Back to how the app was after the request with this id, or before it.
    case goBack(UUID, before: Bool)
    /// The request with this id into the message box, to change and send again; and back out of it.
    case takeBack(UUID)
    case putBack
    /// Shows an attachment in Quick Look: of the request with this id, or (nil) of the message box, by its place.
    case preview(UUID?, Int)
    /// More of the chat, from before what's shown.
    case earlier
    case dismissSuggestion
    /// Starts or stops dictating into the message box, in Lamp.
    case dictate(Bool)
    /// The dictation problem was seen: closed, or (true) its System Settings page asked for.
    case dictationProblem(openSettings: Bool)
    /// Files pasted, dropped or chosen in the sidebar, which only it can read: their names and contents.
    case attach([SidebarFile])
    /// Point at part of the app for the message (`MagicPanel.point`).
    case point
    case stop
    case unqueue(UUID)
    /// Send Now under the latest waiting message, named by its id: every waiting message goes to the agent in the turn
    /// that's running, if that is still the latest.
    case sendNow(UUID)
    /// The answer to the approval with this id.
    case approve(UUID, allow: Bool, allowAll: Bool)
    case forceQuit
    // The toolbar's, as in Lamp's window.
    /// Undo Last Change: back to the version before this one.
    case undo
    /// Delete the wish, which the sidebar has already confirmed.
    case delete
    case copyWishFile
    /// Share…: Lamp makes the file and sends it back (`SidebarState.sharing`).
    case share
    case export
    case details(Bool)
    /// The panel shown in place of the chat, or (nil) the chat.
    case panel(SidebarPanel?)
    case goBackToVersion(String)
    /// A version's name, or (empty) none.
    case nameVersion(String, String)
    /// A button in the info panel.
    case infoAction(String)
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

/// Something the person needs to know before a thing can work, as an alert: its title, what to do, and the
/// button that opens the fix, when there is one.
public struct SidebarProblem: Codable, Equatable {
    public var title: String
    public var message: String
    public var settingsButton: String?

    public init(title: String, message: String, settingsButton: String?) {
        self.title = title
        self.message = message
        self.settingsButton = settingsButton
    }
}
