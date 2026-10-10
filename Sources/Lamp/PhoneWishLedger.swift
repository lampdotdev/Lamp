import Foundation

/// Acceptance is a durable write, before any agent starts or a reply leaves the Mac. A lost reply
/// therefore only repeats a read, never a second wish. The UUID is also the generated app's instance.
struct PhoneWishLedger {
    struct Job: Codable {
        let id: UUID
        let pairID: UUID
        let wish: String
        var status: PhoneLink.Status
    }
    private(set) var jobs: [Job]
    let file: URL

    init(file: URL) throws {
        self.file = file
        jobs = FileManager.default.fileExists(atPath: file.path)
            ? try JSONDecoder().decode([Job].self, from: Data(contentsOf: file)) : []
    }

    mutating func accept(id: UUID, pairID: UUID, wish: String) throws -> Job {
        guard !wish.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, wish.count <= 4000,
              wish.unicodeScalars.allSatisfy({ $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }) else {
            throw PhoneLink.Failure.invalid
        }
        if let job = jobs.first(where: { $0.id == id }) {
            guard job.pairID == pairID, job.wish == wish else { throw PhoneLink.Failure.invalid }
            return job
        }
        guard jobs.count < 256 else { throw PhoneLink.Failure.full }
        guard !jobs.contains(where: { ![.ready, .needsMac].contains($0.status.phase) }) else { throw PhoneLink.Failure.busy }
        let job = Job(id: id, pairID: pairID, wish: wish, status: .init(id: id, phase: .queued))
        try save(jobs + [job])
        return job
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
