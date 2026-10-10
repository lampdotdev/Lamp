import Foundation

/// Acceptance is a durable write, before any agent starts or a reply leaves the Mac. A lost reply
/// therefore only repeats a read, never a second wish. The UUID is also the generated app's instance.
struct PhoneWishLedger {
    struct Submission: Codable, Equatable {
        enum State: String, Codable { case queued, dispatched, posted }
        let id: UUID
        let text: String
        var state: State = .queued
    }
    struct Job: Codable {
        let id: UUID
        let pairID: UUID
        let wish: String
        var status: PhoneLink.Status
        var messages: [Submission]?
        var submissions: [Submission] {
            messages ?? [.init(id: id, text: wish, state: status.phase == .queued ? .queued : .posted)]
        }
    }
    private(set) var jobs: [Job]
    let file: URL

    init(file: URL) throws {
        self.file = file
        jobs = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode([Job].self, from: Data(contentsOf: file)) : []
    }

    mutating func accept(id: UUID, pairID: UUID, wish: String) throws -> Job {
        try validate(wish)
        if let job = jobs.first(where: { $0.id == id }) {
            guard job.pairID == pairID, job.wish == wish else { throw PhoneLink.Failure.invalid }
            return job
        }
        guard jobs.count < 256 else { throw PhoneLink.Failure.full }
        guard !jobs.contains(where: { !$0.status.phase.isFinished }) else { throw PhoneLink.Failure.busy }
        guard !jobs.contains(where: { $0.submissions.contains { $0.id == id } }) else { throw PhoneLink.Failure.invalid }
        let job = Job(id: id, pairID: pairID, wish: wish, status: .init(id: id, phase: .queued),
                      messages: [.init(id: id, text: wish)])
        try save(jobs + [job])
        return job
    }

    func job(_ id: UUID, for pair: UUID) -> Job? { jobs.first { $0.id == id && $0.pairID == pair } }

    mutating func reply(id: UUID, to chatID: UUID, pairID: UUID, text: String) throws -> Job {
        try validate(text)
        guard let index = jobs.firstIndex(where: { $0.id == chatID && $0.pairID == pairID }) else { throw PhoneLink.Failure.invalid }
        var job = jobs[index]
        if let message = job.submissions.first(where: { $0.id == id }) {
            guard message.text == text else { throw PhoneLink.Failure.invalid }
            return job
        }
        guard !jobs.contains(where: { $0.id != chatID && ($0.id == id || $0.submissions.contains { $0.id == id }) }) else {
            throw PhoneLink.Failure.invalid
        }
        guard !jobs.contains(where: { $0.id != chatID && !$0.status.phase.isFinished }) else { throw PhoneLink.Failure.busy }
        guard job.submissions.count < 256 else { throw PhoneLink.Failure.full }
        job.messages = job.submissions + [.init(id: id, text: text)]
        if job.status.phase.isFinished { job.status.phase = .queued }
        var next = jobs
        next[index] = job
        try save(next)
        return job
    }

    mutating func record(_ messageID: UUID, in chatID: UUID, as state: Submission.State) throws {
        guard let index = jobs.firstIndex(where: { $0.id == chatID }) else { throw PhoneLink.Failure.invalid }
        var next = jobs
        var messages = next[index].submissions
        guard let message = messages.firstIndex(where: { $0.id == messageID }) else { throw PhoneLink.Failure.invalid }
        messages[message].state = state
        next[index].messages = messages
        try save(next)
    }

    private func validate(_ text: String) throws {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 4000,
              text.unicodeScalars.allSatisfy({ $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }) else {
            throw PhoneLink.Failure.invalid
        }
    }

    mutating func update(_ status: PhoneLink.Status) throws {
        guard let index = jobs.firstIndex(where: { $0.id == status.id }) else { throw PhoneLink.Failure.invalid }
        var next = jobs
        next[index].status = status
        try save(next)
    }

    private mutating func save(_ next: [Job]) throws {
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: .atomic)
        jobs = next
    }
}
