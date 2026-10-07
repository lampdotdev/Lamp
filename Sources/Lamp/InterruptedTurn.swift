import Foundation

/// Kept outside the app's versions, so a crash or a restore can't erase the choice still owed to the user.
struct InterruptedTurn: Codable {
    var before: String
    let requests: [UUID]
    let label: String
    let attachments: [String]

    private static func url(in project: LampProject) -> URL {
        project.dir.appendingPathComponent(".lamp/interrupted-turn.json")
    }

    static func load(in project: LampProject) -> Self? {
        (try? Data(contentsOf: url(in: project))).flatMap { try? JSONDecoder().decode(Self.self, from: $0) }
    }

    func save(in project: LampProject) throws {
        try JSONEncoder().encode(self).write(to: Self.url(in: project), options: .atomic)
    }

    static func clear(in project: LampProject) throws {
        let file = url(in: project)
        if FileManager.default.fileExists(atPath: file.path) { try FileManager.default.removeItem(at: file) }
    }
}
