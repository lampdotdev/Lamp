import Foundation

/// What a Lamp app file may hold: the shapes of keys a shared file never carries, the names a license goes by, and the
/// sizes another Lamp opens. Resources/share-rules.json is the one place they're written; lamp's command line reads the
/// same file (cli/lampapp.mjs), so a file either makes is held to the same rules.
struct ShareRules: Decodable {
    struct TokenShape: Decodable { let pattern: String }
    struct LicenseFiles: Decodable { let startsWith: [String]; let longestExtension: Int; let neverExtensions: [String] }
    struct Limits: Decodable { let files: Int; let unpackedBytes: Int; let archiveBytes: Int }
    let tokenShapes: [TokenShape]
    let licenseFiles: LicenseFiles
    let limits: Limits

    /// From the app, or from the repository a build or test runs from. Lamp can't make or check a shared file without
    /// them, so one that's missing is Lamp's own fault and stops it at once.
    static let shared: ShareRules = {
        let source = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Resources/share-rules.json")
        let places = [Bundle.main.resourceURL?.appendingPathComponent("share-rules.json"), source].compactMap { $0 }
        for place in places {
            if let data = try? Data(contentsOf: place), let rules = try? JSONDecoder().decode(ShareRules.self, from: data) { return rules }
        }
        fatalError("share-rules.json is missing from Lamp")
    }()
}
