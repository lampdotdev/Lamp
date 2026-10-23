import Foundation
import QuartzCore
import RealityKit
import simd

/// The F3 readout: frames a second, the slowest frame of the last few seconds, how long the last map square took
/// to make on the main thread, and what the game's own update and physics cost each frame. The first time it's
/// shown it also counts the triangles in the squares round the car (printed to the log).
@MainActor
final class Perf {
    static let shared = Perf()

    var shown = false
    private var held = false
    /// Milliseconds the last square took to make into entities.
    var lastSquare: Double = 0
    private var lastFrame: CFTimeInterval = 0
    /// Frame intervals of the last few seconds, with when each ended.
    private var frames: [(at: CFTimeInterval, ms: Double)] = []
    private var updateMs: Double = 0
    private var physicsMs: Double = 0
    private var shownAt: CFTimeInterval = 0
    private var counted = false

    private var parts = ""
    /// Time spent in each part of the game's update this frame, printed when a frame is slow.
    private var laps: [(String, Double)] = []
    private var lapAt: CFTimeInterval = 0
    private var lastSlowPrint: CFTimeInterval = 0
    func beginLaps(_ t: CFTimeInterval) { laps.removeAll(keepingCapacity: true); lapAt = t }
    func lap(_ name: String) {
        let t = CACurrentMediaTime()
        laps.append((name, (t - lapAt) * 1000))
        lapAt = t
    }
    /// What the scene draws: models and their material slots (roughly, draw calls), by what holds them.
    static func drawCensus(_ root: Entity) -> String {
        var groups: [String: (models: Int, parts: Int, enabled: Int)] = [:]
        var totalParts = 0, totalEnabled = 0, entities = 0
        func walk(_ e: Entity, _ group: String, _ on: Bool) {
            entities += 1
            let on = on && e.isEnabled
            if let m = e.components[ModelComponent.self] {
                let n = max(1, m.mesh.contents.models.map { $0.parts.count }.reduce(0, +))
                var g = groups[group] ?? (0, 0, 0)
                g.models += 1; g.parts += n; if on { g.enabled += n; totalEnabled += n }
                groups[group] = g
                totalParts += n
            }
            for c in e.children {
                let name = c.name.isEmpty ? group : String(c.name.split(separator: "|").first ?? "")
                walk(c, name.isEmpty ? "unnamed" : name, on)
            }
        }
        walk(root, "", true)
        var lines = ["Scene: \(entities) entities, \(totalParts) mesh parts (\(totalEnabled) shown)"]
        for (k, v) in groups.sorted(by: { $0.value.enabled > $1.value.enabled }).prefix(25) {
            lines.append("  \(k): \(v.models) models, \(v.parts) parts, \(v.enabled) shown")
        }
        return lines.joined(separator: "\n")
    }

    func physics(_ seconds: CFTimeInterval, _ p: (integrate: Double, file: Double, statics: Double, pairs: Double, after: Double, substeps: Int, awake: Int, trains: Int)) {
        physicsMs = physicsMs * 0.9 + seconds * 1000 * 0.1
        parts = String(format: "\nphysics: %d substeps · %d moving (%d train cars) · move %.2f · file %.2f · walls/posts %.2f · cars %.2f · after %.2f ms",
                       p.substeps, p.awake, p.trains, p.integrate, p.file, p.statics, p.pairs, p.after)
    }

    func frame(start: CFTimeInterval, game: Game, scene: LampScene) {
        let now = CACurrentMediaTime()
        updateMs = updateMs * 0.9 + (now - start) * 1000 * 0.1
        if shown && (now - start) * 1000 > 60 && now - lastSlowPrint > 2 {
            lastSlowPrint = now
            print(String(format: "Slow update %.0f ms: ", (now - start) * 1000) + laps.filter { $0.1 > 2 }.map { String(format: "%@ %.0f", $0.0, $0.1) }.joined(separator: ", ") + parts)
        }
        if lastFrame > 0 { frames.append((now, (start - lastFrame) * 1000)) }
        lastFrame = start
        while let f = frames.first, now - f.at > 3 { frames.removeFirst() }

        // F3 shows and hides it.
        let down = scene.isDown(LampKey(code: 99))
        if down && !held {
            shown.toggle()
            if !shown { game.hud.debug = nil }
        }
        held = down
        if shown && !counted && game.hud.loaded, let p = game.playerPos {
            counted = true
            print(Self.drawCensus(scene.root))
            Task.detached(priority: .utility) { print(CityTiles.census(around: p)) }
        }
        guard shown, now - shownAt > 0.25 else { return }
        shownAt = now
        let span = frames.map(\.ms).reduce(0, +)
        let fps = span > 0 ? Double(frames.count) * 1000 / span : 0
        let worst = frames.map(\.ms).max() ?? 0
        game.hud.debug = String(format: "%.0f fps · slowest %.0f ms (3 s)\nlast square %.1f ms · update %.1f ms · physics %.2f ms",
                                fps, worst, lastSquare, updateMs, physicsMs) + parts
    }
}
