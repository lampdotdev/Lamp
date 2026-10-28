import XCTest
@testable import Lamp

/// The starters as the tests read them: each one's tree is its repository at the commit its starter.md pins, fetched
/// into Resources/Starters/<folder>/tree by scripts/fetch-starters.sh (build.sh runs it) and never committed. A test
/// that needs a tree skips without it, saying so, rather than failing a checkout that hasn't fetched.
enum StarterTrees {
    static let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Resources/Starters")

    /// One starter, read as Lamp reads it (`Starters.read`).
    static func starter(_ name: String) throws -> Starters.Starter {
        guard let starter = Starters.read(folder.appendingPathComponent(name)) else {
            throw XCTSkip("\(name) has no tree: run scripts/fetch-starters.sh")
        }
        return starter
    }

    /// One starter's tree.
    static func tree(_ name: String) throws -> URL { try starter(name).tree }

    /// Every starter's folder, each with its tree.
    static func folders() throws -> [URL] {
        let folders = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter(\.hasDirectoryPath).sorted { $0.lastPathComponent < $1.lastPathComponent }
        let missing = folders.filter { Starters.read($0) == nil }.map(\.lastPathComponent)
        guard missing.isEmpty else { throw XCTSkip("\(missing.joined(separator: ", ")) have no tree: run scripts/fetch-starters.sh") }
        return folders
    }
}
