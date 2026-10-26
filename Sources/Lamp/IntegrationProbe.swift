import AppKit
import Foundation

/// A test run of a device's integration on the person's own device, started by them from its setup window once it's
/// set up: what no documentation says (a Roku's installer hanging over a running channel) is found by Lamp rather than
/// by a person at the keyboard. It makes the integration's own scaffold into an app in a folder of Lamp's
/// (`Probes/`), and goes through Lamp's own ways with it, stage by stage, stopping at the first that fails: put it on
/// and open it, picture its screen, press the arrows and select (never every key: one may switch the TV off or change
/// its input), type, stop it, put it on again while it's open, and take it off. What happened goes back to the device's
/// setup conversation with its next request (`report`), for every engine alike, so the builder can fix the integration;
/// a run that passes marks the bridge as worked on that model (`Integration.Bridge.known`). Lamp's shipped integrations
/// are tried the same way but never written to.
@MainActor
enum IntegrationProbe {
    struct Stage: Identifiable, Equatable {
        enum State: Equatable { case waiting, running, passed, failed(String), skipped }
        let id: String
        var state: State
    }

    /// The last run's report on each device, by its id, for its setup conversation's next request.
    private static var reports: [String: String] = [:]

    static func report(for deviceID: String) -> String? { reports[deviceID] }

    /// The stages a run on this integration goes through, in order: the ones its bridge has.
    static func stages(for integration: Integration) -> [Stage] {
        let bridge = integration.bridge
        var names = ["Make a test app", "Put it on and open it"]
        if bridge?.look?.isEmpty == false { names.append("See its screen") }
        if !keys(of: integration).isEmpty { names.append("Press its keys") }
        if bridge?.type?.isEmpty == false { names.append("Type into it") }
        if bridge?.stop?.isEmpty == false { names.append("Stop it") }
        names.append("Put it on again while it's open")
        if bridge?.remove?.isEmpty == false { names.append("Take it off") }
        return names.map { Stage(id: $0, state: .waiting) }
    }

    /// The keys a run presses: the ones that only move and choose.
    private static func keys(of integration: Integration) -> [String] {
        guard integration.bridge?.use?.isEmpty == false else { return [] }
        let names = integration.bridge?.keys ?? [:]
        return ["up", "down", "left", "right", "select"].filter { names[$0] != nil }
    }

    /// Runs every stage on the device, `update` told as each starts and ends, and leaves nothing behind: the test app
    /// comes off the device (its last stage), and its folder and package off this Mac.
    static func run(_ integration: Integration, on device: Device, update: @escaping @MainActor ([Stage]) -> Void) async {
        var stages = stages(for: integration)
        update(stages)
        let folder = Edition.supportFolder.appendingPathComponent("Probes").appendingPathComponent(integration.id)
        var project = LampProject(id: "lamp-probe-" + integration.id, name: "Lamp Probe", exe: "LampProbe", dir: folder, platform: .device)
        project.integration = integration.id
        // One app at a time on a device: the run waits for an install under way, and holds it off until it's done.
        await DeviceApps.take(device.id)
        var run: DeviceApps.Run?
        defer {
            run?.end()
            DeviceApps.release(device.id)
            try? FileManager.default.removeItem(at: folder)
            try? FileManager.default.removeItem(at: DeviceApps.buildFolder(for: project))
        }
        for index in stages.indices {
            stages[index].state = .running
            update(stages)
            do {
                switch stages[index].id {
                case "Make a test app":
                    try? FileManager.default.removeItem(at: folder)
                    try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
                    try DeviceApps.fill(project)
                    try DeviceSupport.write(for: project)
                    try await DeviceApps.build(project)
                case "Put it on and open it":
                    run = try await DeviceApps.install(project, on: device, log: nil)
                case "See its screen":
                    _ = try await DeviceApps.picture(project, on: device)
                case "Press its keys":
                    for key in keys(of: integration) {
                        try await DeviceApps.press(key, in: project, on: device)
                        try await Task.sleep(for: .milliseconds(400))
                    }
                case "Type into it":
                    try await DeviceApps.type("lamp", in: project, on: device) { true }
                case "Stop it":
                    guard await DeviceApps.stop(project, on: device) else { throw DeviceApps.Failure(message: "The device refused to end the app.") }
                case "Put it on again while it's open":
                    // Opened, then put on again over the open copy, as every change the builder makes is.
                    run?.end()
                    run = try await DeviceApps.install(project, on: device, log: nil)
                    run?.end()
                    run = try await DeviceApps.install(project, on: device, log: nil)
                case "Take it off":
                    try await DeviceApps.remove(project, from: device)
                default: break
                }
                stages[index].state = .passed
            } catch {
                stages[index].state = .failed(DeviceApps.plain(error.localizedDescription))
                for later in stages.indices where later > index { stages[later].state = .skipped }
                update(stages)
                // The app may be on the device still: taken off, whatever else failed.
                if index > 0, stages.contains(where: { $0.id == "Take it off" }) { try? await DeviceApps.remove(project, from: device) }
                break
            }
            update(stages)
        }
        reports[device.id] = words(stages, integration: integration, device: device)
        if stages.allSatisfy({ $0.state == .passed }) { mark(integration, worked: device) }
    }

    /// What happened, for the builder: each stage, and the device's own words where one failed.
    private static func words(_ stages: [Stage], integration: Integration, device: Device) -> String {
        let model = [device.model, device.modelID.isEmpty ? nil : "(\(device.modelID))", device.os, device.osVersion].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " ")
        let lines = stages.map { stage -> String in
            switch stage.state {
            case .passed: return "- \(stage.id): worked"
            case .failed(let why): return "- \(stage.id): failed. \(why)"
            case .skipped, .waiting, .running: return "- \(stage.id): not tried"
            }
        }
        return "Lamp's test run of the \(integration.id) integration on \(device.name), \(model), with the person's say-so:\n" + lines.joined(separator: "\n")
    }

    /// A bridge that worked from start to end on a device, marked with its model and version. Not a shipped one, which
    /// is Lamp's and read-only.
    private static func mark(_ integration: Integration, worked device: Device) {
        guard !Integrations.isShipped(integration.id), var marked = Integrations.integration(integration.id), marked.bridge?.unmarked == integration.bridge?.unmarked else { return }
        marked.bridge?.known = Integration.Known(how: .lamp, model: device.modelID.isEmpty ? device.model : device.modelID, version: device.osVersion)
        Integrations.write(marked)
    }
}
