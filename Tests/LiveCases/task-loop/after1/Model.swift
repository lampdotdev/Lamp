import Foundation
@MainActor final class Worker {
    var running = true
    var log: [String] = []
    func step() { log.append("step-NEW") }
    func privateStep() { secret() }
    private func secret() { log.append("private-NEW") }
}
