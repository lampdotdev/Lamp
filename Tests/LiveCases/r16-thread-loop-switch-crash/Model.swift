import Foundation
enum Mode { case idle, playing, paused, won, lost, menu, intro, outro, credits, shop, map, quiz }
final class Engine: @unchecked Sendable {
    static let shared = Engine()
    private let lock = NSLock()
    private var mode: Mode = .idle
    private var running = true
    private var last = ""
    func set(_ m: Mode) { lock.lock(); mode = m; lock.unlock() }
    func seen() -> String { lock.lock(); defer { lock.unlock() }; return last }
    func stop() { lock.lock(); running = false; lock.unlock() }
    // The loop: started once, never returns while the app runs.
    func run() {
        while true {
            lock.lock()
            if !running { lock.unlock(); return }
            switch mode {
            case .idle: last = "idle"
            case .playing: last = "playing"
            case .paused: last = "paused"
            case .won: last = "won"
            case .lost: last = "lost"
            case .menu: last = "menu"
            case .intro: last = "intro"
            case .outro: last = "outro"
            case .credits: last = "credits"
            case .shop: last = "shop"
            case .map: last = "map"
            case .quiz: last = "quiz"
            }
            lock.unlock()
            Thread.sleep(forTimeInterval: 0.01)
        }
    }
}
func pick(_ e: Engine) { e.set(.playing) }
