import AppKit
import Foundation

/// Apps for a device Lamp has no kit for (`Platform.device`), made and put on it entirely as the device's integration
/// declares: the scaffold is its declared files, the build is its declared package step, run in the app's sandbox like
/// every build, and putting the app on the device, opening it, looking at it and pressing the remote's keys are the
/// integration's bridge, run by `IntegrationRunner` with each primitive held to its guard. Nothing here knows any one
/// device: what's for a Roku is in the Roku's integration.
enum DeviceApps {
    /// Written with the scaffold, holding the integration's id: what tells a device app's folder from a draft's. It's
    /// kept with the code (not in .lamp/), so a version restored from before the app changed kind brings the kind
    /// and its device back with it (`Template.platform(fromPackageIn:)`).
    static let marker = ".lamp-device"

    /// The integration a folder's code was written for, read off its marker.
    static func integrationID(in dir: URL) -> String? {
        (try? String(contentsOf: dir.appendingPathComponent(marker), encoding: .utf8))?.trimmed.nilIfEmpty
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Whether the integration with this id declares the apps made for its device.
    static func makesApps(_ id: String) -> Bool { Integrations.integration(id)?.app?.declared != nil }

    /// The integrations that declare apps: the devices the naming call and `make_app_for` may name.
    static func kinds() -> [Integration] { Integrations.all().filter { $0.app?.declared != nil } }

    static func integration(for project: LampProject) -> Integration? { project.integration.flatMap(Integrations.integration) }

    static func isScaffolded(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }

    /// Writes the integration's scaffold, with Lamp's own names for the app put in (`{{NAME}}`), and the app's APP.md.
    static func fill(_ project: LampProject) throws {
        guard let integration = integration(for: project), let declared = integration.app?.declared else {
            throw Failure(message: "Lamp no longer has the integration this app is made for.")
        }
        for (path, contents) in declared.files.sorted(by: { $0.key < $1.key }) where IntegrationCheck.isAppPath(path) {
            try Template.write(contents, to: path, for: project)
        }
        let output = declared.output.split(separator: "/").first.map(String.init) ?? declared.output
        try Template.write(".lamp/\n\(output)\n", to: ".gitignore", for: project)
        try Template.write(appMd(integration), to: "APP.md", for: project)
        try Template.write(integration.id + "\n", to: marker, for: project)
    }

    static func appMd(_ integration: Integration) -> String {
        """
        # {{NAME}}

        An app for \(integration.name) (\(integration.kind ?? "a device")), built and changed with Lamp, which puts it on the \
        person's own \(integration.name) over the network.

        ## What it does
        Nothing yet: fresh scaffold.

        """
    }

    /// What the app is built from: everything in its folder but what the package step makes, Lamp's folder and the
    /// person's attachments.
    static func sourceRoots(_ project: LampProject) -> [URL] {
        let output = integration(for: project)?.app?.declared?.output.split(separator: "/").first.map(String.init)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: project.dir.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && $0 != output && $0 != Attachments.folder && $0 != "APP.md" }
            .sorted().map { project.dir.appendingPathComponent($0) }
    }

    // MARK: Building

    /// Where Lamp keeps the package it sends: its own folder, never the app's, which the agent's commands can change at
    /// any moment.
    static func buildFolder(for project: LampProject) -> URL {
        Edition.supportFolder.appendingPathComponent("Device Builds").appendingPathComponent(project.id)
    }

    static func packageURL(for project: LampProject) -> URL {
        let output = integration(for: project)?.app?.declared?.output ?? "package"
        let suffix = URL(fileURLWithPath: output).pathExtension
        return buildFolder(for: project).appendingPathComponent(suffix.isEmpty ? "package" : "package." + suffix)
    }

    /// Runs the declared package step in the app's sandbox, then copies what it made into Lamp's folder, read the way
    /// Lamp reads anything there (`AppFile`: no link followed, only a plain file).
    static func build(_ project: LampProject, started: (@MainActor (Process) -> Void)? = nil) async throws {
        guard let declared = integration(for: project)?.app?.declared else {
            throw Failure(message: "Lamp no longer has the integration this app is made for, so it can't make its package.")
        }
        let output = project.dir.appendingPathComponent(declared.output)
        AppFolder.remove(output, in: project.dir)
        var printed: [String] = []
        let status = await Sandbox.run(declared.package, for: project, started: started) { printed.append($0) }
        guard status == 0 else {
            throw Failure(message: (["The package step failed:"] + printed.suffix(30)).joined(separator: "\n"))
        }
        guard let data = AppFile.read(output, in: project), !data.isEmpty else {
            throw Failure(message: "The package step ran but left nothing at \(declared.output).")
        }
        guard data.count <= DeviceHTTP.limit else { throw Failure(message: "The package is bigger than Lamp sends to a device.") }
        try FileManager.default.createDirectory(at: buildFolder(for: project), withIntermediateDirectories: true)
        try data.write(to: packageURL(for: project), options: .atomic)
    }

    // MARK: On the device

    /// The device the app goes on: the one chosen under Try On, else the only one its integration found.
    @MainActor static func device(for project: LampProject, among devices: [Device]) -> Device? {
        let mine = devices.filter { $0.integration == project.integration && $0.integration != nil }
        if let id = project.device { return mine.first { $0.id == id } ?? Integrations.kept(id).map { Integrations.device(from: $0, onNetwork: false) } }
        return mine.count == 1 ? mine.first : nil
    }

    /// The remote's keys the integration names, Lamp's names first.
    static func keys(for project: LampProject) -> [String] {
        (integration(for: project)?.bridge?.keys ?? [:]).keys.sorted()
    }

    /// One app as put on a device: which device, and the log read from it while it's open.
    final class Run {
        let device: Device
        var streams: [DeviceStream] = []
        /// What the device answered the install with, as text: where a device that has no log says what it refused.
        var installAnswer: String?
        init(device: Device) { self.device = device }
        func end() { streams.forEach { $0.stop() }; streams = [] }
    }

    /// Puts the package on the device and opens it: the bridge's install, then its launch, with its log read into the
    /// app's from the moment before the install, so what the device says of the package is in it.
    /// `stillWanted` is asked before each thing that changes the device, so a Stop meanwhile leaves it as it was.
    static func install(_ project: LampProject, on device: Device, log: FileHandle?,
                        stillWanted: @escaping @MainActor () -> Bool = { true }) async throws -> Run {
        guard let integration = integration(for: project), let bridge = integration.bridge, let install = bridge.install else {
            throw Failure(message: "\(device.name)'s integration doesn't say how an app goes on it.")
        }
        let runner = IntegrationRunner(integration: integration, device: device, onLog: { line in
            log?.write(Data((line + "\n").utf8))
        })
        let run = Run(device: device)
        if let logs = bridge.logs, !logs.isEmpty {
            // A device with nothing listening on its log's port still takes the app.
            run.streams = (try? await runner.run(logs).streams) ?? []
        }
        // A device busy closing the app it's replacing can drop a connection, the upload's or the launch's just after
        // it; a little later it's ready, so the pair is tried again a couple of times before Lamp gives up.
        var tries = 0
        while true {
            do {
                guard await stillWanted() else { throw Failure(message: "Stopped.") }
                let outcome = try await runner.run(install, extra: values(project), files: ["package": packageURL(for: project)])
                run.installAnswer = outcome.answers.last.map(plain)
                guard await stillWanted() else { throw Failure(message: "Stopped.") }
                if let launch = bridge.launch, !launch.isEmpty { _ = try await runner.run(launch, extra: values(project)) }
                break
            } catch let error as URLError where error.code == .networkConnectionLost && tries < 2 {
                tries += 1
                try? await Task.sleep(for: .seconds(3))
            } catch {
                run.end()
                throw error
            }
        }
        return run
    }

    /// The device's screen, from the bridge's look.
    static func picture(_ project: LampProject, on device: Device) async throws -> Data {
        guard let integration = integration(for: project), let look = integration.bridge?.look else {
            throw Failure(message: "\(device.name)'s integration doesn't say how to see its screen.")
        }
        let outcome = try await IntegrationRunner(integration: integration, device: device).run(look, extra: values(project))
        guard let picture = outcome.picture, NSImage(data: picture) != nil else { throw Failure(message: "\(device.name) sent no picture of its screen.") }
        return picture
    }

    /// Presses one of the remote's keys by Lamp's name for it, through the bridge's use.
    static func press(_ key: String, in project: LampProject, on device: Device) async throws {
        guard let integration = integration(for: project), let use = integration.bridge?.use, let name = integration.bridge?.keys?[key] else {
            throw Failure(message: "\(device.name) has no key called \"\(key)\". Its keys are \(keys(for: project).joined(separator: ", ")).")
        }
        _ = try await IntegrationRunner(integration: integration, device: device).run(use, extra: values(project).merging(["key": name]) { $1 })
    }

    private static func values(_ project: LampProject) -> [String: String] { ["appID": project.id] }

    /// A device's answer as plain words: an HTML page's text without its tags and scripts, cut to a few lines.
    static func plain(_ answer: String) -> String {
        var text = answer.replacingOccurrences(of: #"(?s)<(script|style)[^>]*>.*?</\1>"#, with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: "\n", options: .regularExpression)
        let lines = text.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        return String(lines.joined(separator: "\n").prefix(1500))
    }

    /// The picture as PNG, the way the other looks keep theirs, with its size in pixels.
    static func png(_ data: Data) -> (data: Data, width: Int, height: Int)? {
        guard let image = NSBitmapImageRep(data: data), let png = image.representation(using: .png, properties: [:]) else { return nil }
        return (png, image.pixelsWide, image.pixelsHigh)
    }
}

// MARK: - What the builder is told

extension Agent {
    /// The rules for a device app: the integration's own words on writing for its device, in the shape of the others'.
    static func devicePrompt(for project: LampProject) -> String {
        let integration = DeviceApps.integration(for: project)
        let name = integration?.name ?? "the device"
        let rules = [Rules.deviceEdit, Rules.ask, Rules.shell, Rules.deviceKind(integration), Rules.icon, Rules.about,
                     Rules.deviceAttachments, Rules.deviceTry(project), Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        return (Rules.deviceHeader(integration) + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: name)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a " + name)
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "puts it on the \(name) again and opens it")
    }
}

extension Agent.Rules {
    static func deviceHeader(_ integration: Integration?) -> String {
        let name = integration?.name ?? "a device"
        return """
        You are Lamp's builder agent. The current directory is an app for \(name) (\(integration?.kind ?? "a device") by \
        \(integration?.maker ?? "its maker")), the person's own, which Lamp reaches over their network. Lamp makes its \
        package with the package step its integration declares, puts it on the \(name) and opens it there: the person \
        watches it on that device's screen. Read APP.md first for context.
        """
    }

    static let deviceEdit = """
    - Make the change the user asks for by editing the app's files here, in the layout the scaffold has. Lamp makes \
    the package from them by itself when you look, so don't run the package step or put anything on the device \
    yourself, and leave .lamp/ alone.
    """

    /// What the integration says about writing for its device, as one rule.
    static func deviceKind(_ integration: Integration?) -> String {
        guard let rules = integration?.app?.declared?.rules.trimmed, !rules.isEmpty else { return "" }
        return "- Writing for \(integration?.name ?? "the device"): " + rules + "\n"
    }

    static let deviceAttachments = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. When the app \
    should use one (a picture, a data file), copy it into the app's own folders where the package step takes it.
    """

    static func deviceTry(_ project: LampProject) -> String {
        let keys = DeviceApps.keys(for: project)
        let integration = DeviceApps.integration(for: project)
        let name = integration?.name ?? "device"
        var rule = "- `look_at_app` makes the package, puts it on the person's \(name), opens it there and shows you a picture of its screen, "
            + "with what the device answered to the install and what the app printed when the device has a log. "
        if keys.isEmpty || integration?.bridge?.use == nil {
            rule += "Lamp can't press the \(name)'s keys, so `use_app` doesn't work for it. "
        } else {
            rule += "`use_app` presses the remote's keys there, with `key` actions (\(keys.joined(separator: ", "))) and `wait`, then shows the screen again. "
        }
        if integration?.bridge?.look == nil { rule += "Its integration has no way to picture its screen, so ask the person what they see. " }
        return rule + "There is no screen as text and no pointer: try the app the way the person will, with the keys.\n"
    }
}
