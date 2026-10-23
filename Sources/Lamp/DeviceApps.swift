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

    /// An app's kind as `LampProject.integration` keeps it: the integration's id, then ":" and one of its `kinds` when the
    /// app is that kind rather than its `app` ("xbox-one:game").
    static func split(_ kind: String) -> (integration: String, kind: String?) {
        guard let colon = kind.firstIndex(of: ":") else { return (kind, nil) }
        return (String(kind[..<colon]), String(kind[kind.index(after: colon)...]))
    }

    /// The kind of app this names: the integration's `app`, or one of its `kinds`.
    static func appKind(_ kind: String) -> Integration.AppKind? {
        let (id, name) = split(kind)
        guard let integration = Integrations.integration(id), integration.app?.declared != nil else { return nil }
        return name.map { integration.kinds?[$0] } ?? integration.app
    }

    /// Whether this names a kind of app Lamp makes for a device: "roku", "xbox-one", "xbox-one:game".
    static func makesApps(_ kind: String) -> Bool { appKind(kind) != nil }

    /// Every kind of app a device's integration offers, with what each is for: the names the naming call and
    /// `make_app_for` may give.
    static func kinds() -> [(id: String, integration: Integration, kind: Integration.AppKind)] {
        Integrations.all().filter { $0.app?.declared != nil }.flatMap { integration -> [(String, Integration, Integration.AppKind)] in
            [(integration.id, integration, integration.app!)]
                + (integration.kinds ?? [:]).sorted { $0.key < $1.key }.map { ("\(integration.id):\($0.key)", integration, $0.value) }
        }
    }

    static func integration(for project: LampProject) -> Integration? { project.deviceIntegration.flatMap(Integrations.integration) }

    static func appKind(for project: LampProject) -> Integration.AppKind? { project.integration.flatMap(appKind) }

    /// The folder a device app's kind previews on this Mac (`app.declared.preview`), checked; nil when it has none.
    static func previewFolder(for project: LampProject) -> String? {
        guard project.platform.hasDevice, let folder = appKind(for: project)?.declared?.preview,
              IntegrationCheck.isAppPath(folder) else { return nil }
        return folder
    }

    static func isScaffolded(_ dir: URL) -> Bool { FileManager.default.fileExists(atPath: dir.appendingPathComponent(marker).path) }

    /// Writes the integration's scaffold, with Lamp's own names for the app put in (`{{NAME}}`), and the app's APP.md.
    static func fill(_ project: LampProject) throws {
        if GameKit.isGame(project) {
            try GameKit.fill(project)
            try Template.write((project.integration ?? "") + "\n", to: marker, for: project)
            return
        }
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
        let output = GameKit.isGame(project) ? "build" : integration(for: project)?.app?.declared?.output.split(separator: "/").first.map(String.init)
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
        if integration(for: project)?.app?.declared?.wrap == "msix" { return buildFolder(for: project).appendingPathComponent("package.msix") }
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
        if GameKit.isGame(project) {
            // The game's own build for the console, then the package Lamp makes of what it left.
            let zip = project.dir.appendingPathComponent("build/xbox.zip")
            AppFolder.remove(zip, in: project.dir)
            try await GameKit.build(project, for: .xbox, started: started)
            guard let data = AppFile.read(zip, in: project), !data.isEmpty else { throw Failure(message: "The game's build left nothing to package.") }
            guard data.count <= DeviceHTTP.limit else { throw Failure(message: "The game is bigger than Lamp sends to a device.") }
            try FileManager.default.createDirectory(at: buildFolder(for: project), withIntermediateDirectories: true)
            try wrapMSIX(data, for: project, entry: .program("App.exe"))
            return
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
        if declared.wrap == "msix" {
            try wrapMSIX(data, for: project, entry: WebHost.isUsed(by: declared) ? .webHost : .page(declared.start ?? "index.html"))
        } else if !DeviceSupport.libraries(for: project).isEmpty, declared.output.lowercased().hasSuffix(".zip") {
            try await withFilledSupport(data, for: project).write(to: packageURL(for: project), options: .atomic)
        } else {
            try data.write(to: packageURL(for: project), options: .atomic)
        }
    }

    /// The package step's zip with Lamp's own files filled in with where Lamp is (`DeviceSupport.fill`), zipped again in
    /// Lamp's temporary folder; unchanged when none of them is in it.
    private static func withFilledSupport(_ zip: Data, for project: LampProject) async throws -> Data {
        let files = try MSIX.files(inZip: zip)
        let filled = DeviceSupport.fill(files, for: project)
        guard Swift.zip(filled, files).contains(where: { $0.0.data != $0.1.data }) else { return zip }
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-package-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: work) }
        let tree = work.appendingPathComponent("package")
        for (path, data) in filled {
            guard IntegrationCheck.isAppPath(path) else { throw Failure(message: "The package holds a file Lamp can't send: \(path).") }
            let url = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let out = work.appendingPathComponent("package.zip")
        let result = await Subprocess.run("/usr/bin/zip", ["-X", "-q", out.path] + filled.map(\.path), cwd: tree, timeout: 120)
        guard result.ok else { throw Failure(message: "Lamp couldn't put where it is into the package.") }
        return try Data(contentsOf: out)
    }


    /// The Windows package Lamp makes of the package step's zip: its own manifest, the app's icon as its logos, and
    /// Lamp's signature, beside the certificate the device installs with it and the identity the bridge launches by.
    private static func wrapMSIX(_ zip: Data, for project: LampProject, entry: MSIX.Start) throws {
        var files = DeviceSupport.fill(try MSIX.files(inZip: zip), for: project)
        if entry == .webHost { files = try WebHost.payload(files) }
        let folder = buildFolder(for: project)
        let previous = (try? Data(contentsOf: folder.appendingPathComponent("identity.json"))).flatMap { try? JSONDecoder().decode(MSIX.Identity.self, from: $0) }
        var identity = MSIX.Identity(name: MSIX.identityName(for: project.id), publisher: MSIX.publisher, version: MSIX.version(after: previous?.version))
        if case .page = entry {} else { identity.architecture = "x64" }
        let icon = AppFile.read(Icons.squareURL(project), in: project).flatMap(NSImage.init(data:))
        let package = try MSIX.package(payload: files, displayName: project.name, identity: identity, entry: entry, icon: icon)
        try package.write(to: packageURL(for: project), options: .atomic)
        try MSIX.certificate().write(to: folder.appendingPathComponent("certificate.cer"), options: .atomic)
        try JSONEncoder().encode(identity).write(to: folder.appendingPathComponent("identity.json"), options: .atomic)
    }

    /// The files a bridge's form may send: the package, and for a wrapped one Lamp's certificate.
    static func files(for project: LampProject) -> [String: URL] {
        var files = ["package": packageURL(for: project)]
        let certificate = buildFolder(for: project).appendingPathComponent("certificate.cer")
        if FileManager.default.fileExists(atPath: certificate.path) { files["certificate"] = certificate }
        return files
    }

    // MARK: On the device

    /// The device the app goes on: the one chosen under Try On, else the only one its integration found.
    @MainActor static func device(for project: LampProject, among devices: [Device]) -> Device? {
        let mine = devices.filter { $0.integration == project.deviceIntegration && $0.integration != nil }
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
        // The app opened by this install asks for its token, which isn't in its package.
        if !DeviceSupport.libraries(for: project).isEmpty, let address = device.address {
            DeviceSupport.Claims.shared.open(project.id, from: address)
        }
        if let logs = bridge.logs, !logs.isEmpty {
            // A device with nothing listening on its log's port still takes the app.
            run.streams = (try? await runner.run(logs).streams) ?? []
        }
        // A device busy closing the app it's replacing can drop a connection, the upload's or the launch's just after
        // it; a little later it's ready, so the pair is tried again a couple of times before Lamp gives up.
        // The copy on the device now is ended first: a device can fail to open a package installed over its running copy.
        if let stop = bridge.stop, !stop.isEmpty, let installed = installedValues(project, on: device) {
            _ = try? await runner.run(stop, extra: installed)
        }
        // A setting the install changes for itself (an Xbox's "treat apps as games") stays changed until the app has been
        // opened: the console settles the package's type then.
        let changed = IntegrationRunner.ChangedSettings()
        var tries = 0
        while true {
            do {
                guard await stillWanted() else { throw Failure(message: "Stopped.") }
                // Noted as on its way before the upload, and as the installed one only once the device took it: an install cut
                // short or deleted midway may still land on the device, and a removal then names both.
                remember(project, on: device, pending: true)
                let outcome = try await runner.run(install, extra: values(project), files: files(for: project), changed: changed)
                remember(project, on: device, pending: false)
                run.installAnswer = outcome.answers.last.map(plain)
                guard await stillWanted() else { throw Failure(message: "Stopped.") }
                if let launch = bridge.launch, !launch.isEmpty {
                    // A device that has only just taken an update can refuse to open it for a while (an Xbox answers
                    // 0x80073D00, 0x8D160120 or 0x80070002 to a launch right after an install over a copy it ended, for up
                    // to ten seconds or so while that copy's web view lets go): asked again a little later, a few times.
                    var refused = 0
                    while true {
                        do { _ = try await runner.run(launch, extra: values(project), changed: changed); break }
                        catch let failure as IntegrationRunner.Failure where refused < 4 {
                            refused += 1
                            try? await Task.sleep(for: .seconds(4))
                            guard await stillWanted() else { throw failure }
                        }
                    }
                }
                break
            } catch let error as URLError where error.code == .networkConnectionLost && tries < 2 {
                tries += 1
                try? await Task.sleep(for: .seconds(3))
            } catch {
                await runner.putBack(changed)
                run.end()
                throw error
            }
        }
        await runner.putBack(changed)
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

    /// What the app's own log on the device holds now, through the bridge's `log`; nil when the integration has none.
    static func log(_ project: LampProject, on device: Device) async throws -> String? {
        guard let integration = integration(for: project), let log = integration.bridge?.log, !log.isEmpty else { return nil }
        return try await IntegrationRunner(integration: integration, device: device).run(log, extra: values(project)).log
    }

    /// Notes which package is on which device once its install went through, for the next install to end it first.
    /// Notes the package just built for a device: as on its way (`pending`), or as the one the device has.
    private static func remember(_ project: LampProject, on device: Device, pending: Bool) {
        let identity = buildFolder(for: project).appendingPathComponent("identity.json")
        let record = installedRecord(project, device: device.id, pending: pending)
        try? FileManager.default.removeItem(at: record)
        try? FileManager.default.copyItem(at: identity, to: record)
        try? Data(device.id.utf8).write(to: installedRecord(project, device: device.id).deletingPathExtension().appendingPathExtension("device"))
        if !pending { try? FileManager.default.removeItem(at: installedRecord(project, device: device.id, pending: true)) }
    }

    /// Where Lamp notes which package of the app is on a device (the identity, with the device's id beside it), and
    /// which one is on its way there.
    private static func installedRecord(_ project: LampProject, device id: String, pending: Bool = false) -> URL {
        buildFolder(for: project).appendingPathComponent("installed-\(MSIX.publisherID(id))\(pending ? "-pending" : "").json")
    }

    /// The bridge's values for the copy last put on this device, when Lamp put one there.
    private static func installedValues(_ project: LampProject, on device: Device) -> [String: String]? {
        values(project, identity: installedRecord(project, device: device.id)).flatMap { $0["packageFullName"] == nil ? nil : $0 }
    }

    /// Takes the app off every device Lamp put it on, through the bridge's `remove`, as its wish is deleted: what's
    /// on a device the person can't reach (off, away) stays there, and nothing stops the delete.
    @MainActor static func removeEverywhere(_ project: LampProject, among devices: [Device]) async {
        guard let integration = integration(for: project), let remove = integration.bridge?.remove, !remove.isEmpty else { return }
        let folder = buildFolder(for: project)
        for name in (try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [] where name.hasPrefix("installed-") && name.hasSuffix(".device") {
            guard let id = try? String(contentsOf: folder.appendingPathComponent(name), encoding: .utf8),
                  let device = devices.first(where: { $0.id == id }) ?? Integrations.kept(id).map({ Integrations.device(from: $0, onNetwork: false) }) else { continue }
            let runner = IntegrationRunner(integration: integration, device: device)
            // The copy the device took, and one that was on its way and may have landed; the same package twice is asked once.
            var asked: Set<String> = []
            for pending in [false, true] {
                guard let package = values(project, identity: installedRecord(project, device: id, pending: pending)),
                      let fullName = package["packageFullName"], asked.insert(fullName).inserted else { continue }
                if let stop = integration.bridge?.stop { _ = try? await runner.run(stop, extra: package) }
                _ = try? await runner.run(remove, extra: package)
            }
        }
    }

    /// Lamp's values for the bridge: the app's id, whether it's a game, and for a wrapped package the names Windows
    /// gives it.
    private static func values(_ project: LampProject) -> [String: String] {
        var values = values(project, identity: buildFolder(for: project).appendingPathComponent("identity.json")) ?? ["appID": project.id]
        values["isGame"] = isGame(project) ? "true" : "false"
        return values
    }

    /// A game, to a device that gives games more than apps (an Xbox gives a game about five times the memory and the
    /// whole GPU): Lamp's native games always, and an app of another kind when its capabilities.json says it's one.
    static func isGame(_ project: LampProject) -> Bool {
        GameKit.isGame(project) || Template.Capabilities.load(project).game == true
    }

    private static func values(_ project: LampProject, identity file: URL) -> [String: String]? {
        var values = ["appID": project.id]
        if let data = try? Data(contentsOf: file),
           let identity = try? JSONDecoder().decode(MSIX.Identity.self, from: data) {
            values["packageFullName"] = identity.fullName
            values["appUserModelID"] = identity.appUserModelID
        }
        return values
    }

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
        if GameKit.isGame(project) { return gamePrompt(for: project) }
        let integration = DeviceApps.integration(for: project)
        let name = integration?.name ?? "the device"
        let rules = [Rules.deviceEdit, Rules.ask, Rules.shell, Rules.deviceKind(integration), Rules.deviceBlocks(project), Rules.icon, Rules.about,
                     Rules.deviceAttachments, Rules.deviceTry(project), Rules.appMd, Rules.audience, Rules.begin, Rules.finish]
        let previews = DeviceApps.previewFolder(for: project) != nil
        return (Rules.deviceHeader(integration, previews: previews) + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: name)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a " + name)
            .replacingOccurrences(of: "{{RELAUNCH}}", with: previews ? "opens it again in the \(name) preview on this Mac" : "puts it on the \(name) again and opens it")
    }
}

extension Agent.Rules {
    static func deviceHeader(_ integration: Integration?, previews: Bool = false) -> String {
        let name = integration?.name ?? "a device"
        let watching = previews
            ? "you try it in a preview of the \(name) on this Mac, and when the person presses Play Lamp makes its package with the package step its integration declares and puts it on the \(name)."
            : "Lamp makes its package with the package step its integration declares, puts it on the \(name) and opens it there: the person watches it on that device's screen."
        return """
        You are Lamp's builder agent. The current directory is an app for \(name) (\(integration?.kind ?? "a device") by \
        \(integration?.maker ?? "its maker")), the person's own, which Lamp reaches over their network: \(watching) \
        Read APP.md first for context.
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

    /// Lamp's building blocks the integration asks for, where they are, and how to use them.
    static func deviceBlocks(_ project: LampProject) -> String {
        let libraries = DeviceSupport.libraries(for: project)
        guard !libraries.isEmpty else {
            return "- Lamp has no building blocks for this device: the app has no AI of Lamp's and keeps its data its own way.\n"
        }
        var rule = "- Lamp's building blocks are in "
            + libraries.map { "\($0.path)" }.joined(separator: " and ")
            + ": Lamp writes them before every build, so never edit or delete them. "
        for entry in libraries {
            switch entry.library {
            case .web:
                rule += "Load \(entry.path) before the app's own scripts. It has `LampStore` (saved data: `load(key, fallback)`, "
                    + "`save(value, key)`, `collection(name)` with put, get, all, delete), `LampAssets` (the package's own files) and `LampAI`. "
                    + webAI.dropFirst(2).replacingOccurrences(of: "\n", with: "")
                    + " "
            case .brightscript:
                rule += "Include \(entry.path)/Lamp.brs in a component's XML (`<script type=\"text/brightscript\" uri=\"pkg:/\(entry.path)/Lamp.brs\" />`) "
                    + "to use `LampAI_ask`, `LampAI_makeImage`, `LampAI_isTrue`, `LampAI_choose`, `LampAI_rate`, `LampAI_decide`, `LampStore_load`, "
                    + "`LampStore_save`, `LampStore_collection` and `LampAssets_text`. Each LampAI call starts a Task node and gives it back: keep it in m, "
                    + "observe its `result` field, and show `result.error` when it's set. Lamp on the person's Mac answers while the device is on its Wi‑Fi "
                    + "with Lamp open. Text from outside the app goes in `options.data`, never into the prompt. Keep the package step zipping that folder. "
                    + "Read Lamp.brs's opening comment before using it; never call an AI service yourself. "
            case .three:
                let folder = "./" + DeviceSupport.pagePath(entry.path, page: DeviceApps.previewFolder(for: project)) + "/"
                rule += "\(entry.path) is three.js r\(DeviceSupport.threeRevision), the 3D library, with its addons (controls, loaders, "
                    + "geometries, postprocessing, utils): put the import map `<script type=\"importmap\">{ \"imports\": { \"three\": "
                    + "\"\(folder)three.module.js\", \"three/addons/\": \"\(folder)addons/\" } }</script>` in index.html before a "
                    + "`<script type=\"module\">`, then `import * as THREE from 'three'` and addons from 'three/addons/…'. Use it for "
                    + "anything 3D, never another engine or one from the network. "
            }
        }
        return rule + "Once something is saved, only ever add to it: a new field gets a default where it's read.\n"
    }

    static let deviceAttachments = """
    - Files the user attaches are saved in Attachments/, for you to look at; they stay on this Mac. When the app \
    should use one (a picture, a data file), copy it into the app's own folders where the package step takes it.
    """

    static func deviceTry(_ project: LampProject) -> String {
        let keys = DeviceApps.keys(for: project)
        let integration = DeviceApps.integration(for: project)
        let name = integration?.name ?? "device"
        if DeviceApps.previewFolder(for: project) != nil {
            return "- `look_at_app` opens the app in the \(name) preview on this Mac, a 1920x1080 window running it in this Mac's browser, "
                + "and shows you a picture of it with its screen as text and what its console printed; it's the preview, not the person's "
                + "\(name), so never say how it runs on the \(name) itself. `use_app` clicks, types and presses keys there: the arrows, enter, "
                + "back (Escape), space, a-z and 0-9, with `amount` in seconds to hold one (a game's move), then shows it again. Try a game by "
                + "playing it. Play puts the app on the \(name).\n"
        }
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
