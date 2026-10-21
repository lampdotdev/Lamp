import XCTest
import AppKit
@testable import Lamp

/// Draws layered glass icons for starters and keeps every candidate, to look at them side by side while tuning
/// `GlassIcons`. `LAMP_GLASS_ICONS=focus,countdowns LAMP_GLASS_OUT=<folder> OPENROUTER_API_KEY=… (LAMP_GLASS_ROUNDS, LAMP_GLASS_MODEL) swift test
/// --filter GlassIconsExperimentTests`.
final class GlassIconsExperimentTests: XCTestCase {
    func testDrawCandidates() async throws {
        let env = ProcessInfo.processInfo.environment
        guard let names = env["LAMP_GLASS_ICONS"], let out = env["LAMP_GLASS_OUT"], let key = env["OPENROUTER_API_KEY"] else {
            throw XCTSkip("Set LAMP_GLASS_ICONS, LAMP_GLASS_OUT and OPENROUTER_API_KEY to draw glass icons.")
        }
        KeyStore.useForThisRun(key, for: "openrouter")
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let folder = URL(fileURLWithPath: out)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let variants = (env["LAMP_GLASS_VARIANTS"] ?? "0,1,2").split(separator: ",").compactMap { Int($0) }
        let rounds = env["LAMP_GLASS_ROUNDS"].flatMap(Int.init) ?? GlassIcons.rounds
        let model = env["LAMP_GLASS_MODEL"] ?? GlassIcons.drawModel
        await withTaskGroup(of: Void.self) { group in
            for name in names.split(separator: ",").map(String.init) {
                let starter = repo.appendingPathComponent("Resources/Starters/\(name)")
                guard let spec = try? JSONDecoder().decode(IconSpec.self, from: Data(contentsOf: starter.appendingPathComponent("icon.json")))
                else { continue }
                let about = (try? String(contentsOf: starter.appendingPathComponent("APP.md"), encoding: .utf8)) ?? ""
                for variant in variants {
                    group.addTask {
                        do {
                            let start = Date()
                            let (design, _, picture) = try await GlassIcons.drawCandidate(spec, appName: name, about: about,
                                                                                         variant: variant, canPaint: true,
                                                                                         rounds: rounds, model: model)
                            print("\(name)-\(variant): \(Int(Date().timeIntervalSince(start)))s")
                            let png = picture.tiffRepresentation.flatMap(NSBitmapImageRep.init(data:))?
                                .representation(using: .png, properties: [:])
                            try png?.write(to: folder.appendingPathComponent("\(name)-\(variant).png"))
                            let encoder = JSONEncoder()
                            encoder.outputFormatting = [.prettyPrinted]
                            try encoder.encode(design).write(to: folder.appendingPathComponent("\(name)-\(variant).json"))
                            print("\(name)-\(variant): drawn")
                        } catch {
                            print("\(name)-\(variant): \(error.localizedDescription)")
                        }
                    }
                }
            }
        }
    }
}
