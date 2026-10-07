#!/usr/bin/env python3
"""Extract the actual Store methods into an isolated harness with inert external services.
No Lamp instance, settings, credentials, phone or notification service is used.
"""
from pathlib import Path
import re
import sys

source = Path('Sources/Lamp/Store.swift').read_text()
def block(marker):
    start = source.index(marker)
    brace = source.index('{', start)
    depth = 1
    end = brace + 1
    while depth:
        depth += (source[end] == '{') - (source[end] == '}')
        end += 1
    return source[start:end]

methods = [block(marker) for marker in [
    '@MainActor final class Turn', 'func stop(_ project:',
    'private func notify(_ project:', 'private static func plain(',
    'func retryPhone(_ project:', 'private func clearPhoneRetry(',
    'private func installOnDevice(', 'enum TurnEnd', 'struct TurnResult',
]]
completion = re.search(r'        let failed = crash != nil.*\n        return TurnResult\(end: failed.*', source)
assert completion, 'Turn completion changed; update this extraction deliberately.'
text = r'''
import Foundation
struct LampProject {
    let id = "phone-review-replay"
    let name = "Pocket Timer"
    let device: String? = "TEST-PHONE"
    let dir = FileManager.default.temporaryDirectory
    func deviceBundleID(team: String) -> String { "dev.example.pockettimer" }
}
struct LogLine {
    enum Kind { case user, agent, status, error, detail }
    let kind: Kind
    let text: String
    var retryPhone: String?
}
struct Look {}
struct TurnProgress { var finished: Date?; var failed = false }
enum Experiments { static let devices = true }
enum Subprocess {
    @discardableResult static func terminateTree(_ process: Process) -> [pid_t] { [] }
}
@MainActor final class Notifier {
    static let shared = Notifier()
    var subtitles: [String] = []
    func post(for project: LampProject, subtitle: String, body: String) { subtitles.append(subtitle) }
}
enum Template { static func writeDeviceProject(for project: LampProject, team: String) throws {} }
enum Runtime {
    static func startLog(_ project: LampProject) {}
    static func logURL(_ project: LampProject) -> URL { project.dir.appendingPathComponent("unused-review-log") }
}
@MainActor enum Devices {
    struct Device { let udid = "TEST-PHONE"; let name = "Test iPhone" }
    static let team = "TESTTEAM01"
    static var checking = false
    static var launching = false
    static var builds = 0
    static var installs = 0
    static var launchDelay = false
    static func list() async -> [Device] {
        checking = true
        try? await Task.sleep(for: .milliseconds(100))
        checking = false
        return [Device()]
    }
    static func problem(_ device: Device?, team: String) -> String? { nil }
    static func build(_ project: LampProject, team: String, udid: String,
                      started: (Process) -> Void, onLine: (String) -> Void) async throws -> URL {
        builds += 1
        return project.dir.appendingPathComponent("unused-review-app")
    }
    static func install(_ app: URL, on udid: String) async throws { installs += 1 }
    static func launch(_ bundle: String, on udid: String, log: URL, started: (Process) -> Void,
                       cancelled: () -> Bool) async throws -> Process {
        launching = true
        if launchDelay { try await Task.sleep(for: .milliseconds(100)) }
        launching = false
        if cancelled() { throw CancellationError() }
        return Process()  // only a simulated successful launch; real waiter is covered in Replay.swift
    }
}
@MainActor final class Store {
    static let shared = Store()
    var projects: [LampProject] = []
    var turns: [String: Turn] = [:]
    var devices: [Devices.Device] = []
    var logs: [String: [LogLine]] = [:]
    var progress: [String: TurnProgress] = [:]
    var deviceApps: [String: Process] = [:]
    var approvalsEnded = 0
    var lastFinished: Turn?
    func begin(_ project: LampProject) -> Turn? {
        guard turns[project.id] == nil else { return nil }
        let turn = Turn(); turns[project.id] = turn; return turn
    }
    func finish(_ project: LampProject) { lastFinished = turns.removeValue(forKey: project.id) }
    func exists(_ project: LampProject) -> Bool { projects.contains { $0.id == project.id } }
    func endApprovals(for project: LampProject) { approvalsEnded += 1 }
    func saveChat(_ project: LampProject) {}
    func refreshOpenApps() {}
    func log(_ project: LampProject, _ kind: LogLine.Kind, _ text: String, retryPhone: String? = nil) {
        logs[project.id, default: []].append(LogLine(kind: kind, text: text, retryPhone: retryPhone))
    }
'''
text += '\n'.join(methods)
text += '''
    func completed(_ owner: Turn, crash: String? = nil, edited: Bool = true) -> TurnResult {
        let watched = false
''' + completion.group() + '\n    }\n'
text += r'''
    static func check(_ condition: Bool, _ label: String) {
        if !condition { fatalError("FAIL: \(label)") }
        print("PASS: \(label)")
    }
    static func runChecks() async {
        let project = LampProject()
        let store = Store(); store.projects = [project]
        let retry = Task { await store.retryPhone(project, udid: "TEST-PHONE") }
        while !Devices.checking { await Task.yield() }
        let owner = store.turns[project.id]!
        check(!owner.isWorking, "device lookup really has no tracked subprocess")
        store.stop(project)
        await retry.value
        check(owner.stopped, "production Stop cancels the owned retry during device lookup")
        check(Devices.builds == 0 && Devices.installs == 0, "stopped device lookup never reaches build or install")
        check(store.logs[project.id]?.contains { $0.kind == .error || $0.text.contains("ready") } != true,
              "stopped lookup adds no error or ready status")
        check(store.completed(owner).end == .failed, "stopped owned turn finishes as failed, not changed")

        Devices.launchDelay = true
        let second = Store(); second.projects = [project]
        let launch = Task { await second.retryPhone(project, udid: "TEST-PHONE") }
        while !Devices.launching { await Task.yield() }
        let launchingOwner = second.turns[project.id]!
        second.stop(project)
        await launch.value
        check(launchingOwner.stopped && launchingOwner.phoneReady == false, "cancelled production phone path preserves the failed outcome")
        check(second.completed(launchingOwner).end == .failed, "cancelled changed turn cannot finish as changed")
        check(second.logs[project.id]?.contains { $0.text.contains("is ready") } != true,
              "cancelled production phone path never logs ready")
        second.turns[project.id] = launchingOwner
        second.notify(project, after: .changed)
        check(Notifier.shared.subtitles.isEmpty, "production notifier suppresses cancelled ready notifications")
        second.logs[project.id] = [LogLine(kind: .error, text: "earlier error", retryPhone: nil)]
        second.notify(project, after: .failed)
        check(Notifier.shared.subtitles.isEmpty, "Stop also suppresses earlier error notifications")

        let normal = Store(); normal.projects = [project]
        let healthy = normal.begin(project)!
        check(normal.completed(healthy).end == .changed, "Mac or simulator completion is unchanged")
        healthy.phoneReady = false
        check(normal.completed(healthy).end == .failed, "phone failure is propagated without a crash-fixing loop")
        healthy.phoneReady = true
        check(normal.completed(healthy).end == .changed, "acknowledged phone completion remains changed")
        normal.notify(project, after: .changed)
        check(Notifier.shared.subtitles == ["Your change is ready"], "normal ready notification still works")
        print("All Store review replays passed. External devices and notifications were simulated.")
    }
}
@main struct StoreReviewReplay {
    @MainActor static func main() async { await Store.runChecks() }
}
'''
Path(sys.argv[1]).write_text(text)
