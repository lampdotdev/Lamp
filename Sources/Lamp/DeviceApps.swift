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

    /// The most Lamp packages and sends to a device as one app: a game with its models, textures and sounds. It's its
    /// own limit, not the cap on a device's answers (`DeviceHTTP.limit`), and is held in memory as it's wrapped and sent.
    static let packageLimit = 1 << 30

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
    /// `make_app_for` may give. A game isn't one: it's a kind of its own (`Platform.game`), which the Xbox's game kind
    /// is only the package of when it's played there.
    static func kinds() -> [(id: String, integration: Integration, kind: Integration.AppKind)] {
        Integrations.all().filter { $0.app?.declared != nil }.flatMap { integration -> [(String, Integration, Integration.AppKind)] in
            [(integration.id, integration, integration.app!)]
                + (integration.kinds ?? [:]).filter { $0.value.lamp != GameKit.kind }.sorted { $0.key < $1.key }
                    .map { ("\(integration.id):\($0.key)", integration, $0.value) }
        }
    }

    static func integration(for project: LampProject) -> Integration? { project.deviceIntegration.flatMap(Integrations.integration) }

    // MARK: As one of a wish's apps

    /// The folder a device's app is in among its wish's other apps: its device's name, in letters and digits ("Roku",
    /// "Xbox"), which is also its name to the others (`WishRooms.peer`). Never one of the other kinds' folders, and nil
    /// for an integration Lamp doesn't have or that declares no apps.
    static func folder(for integration: String) -> String? {
        guard let found = Integrations.integration(split(integration).integration), found.app?.declared != nil else { return nil }
        let name = String(found.name.unicodeScalars.filter { CharacterSet.alphanumerics.contains($0) && $0.isASCII }.map(Character.init))
        let base = name.isEmpty ? "Device" : name.prefix(1).uppercased() + name.dropFirst()
        // The other kinds' folders, and what a wish's folder keeps of its own.
        let taken = Set(Targets.all.compactMap { $0.part?.folder } + [Attachments.folder, "Lamp"])
        return taken.contains(base) ? base + "App" : base
    }

    /// Every folder a device's app may be in: one per integration that declares apps.
    static func folders() -> [String] {
        Integrations.all().filter { $0.app?.declared != nil }.compactMap { folder(for: $0.id) }
    }

    /// The integration whose app lives in this folder of a wish.
    static func integration(inFolder folder: String) -> Integration? {
        Integrations.all().first { $0.app?.declared != nil && self.folder(for: $0.id) == folder }
    }

    /// The folders of a wish holding a device's app, by their marker, whatever they're called: a folder made for an
    /// integration whose name has changed since is still found. Lamp's other kinds' folders and what's the wish's own
    /// are never one.
    static func markedFolders(in wish: URL) -> [String] {
        let others = Set(Targets.all.compactMap { $0.part?.folderFor == nil ? $0.part?.folder : nil } + [Attachments.folder, "Lamp"])
        let names = (try? FileManager.default.contentsOfDirectory(atPath: wish.path)) ?? []
        return names.filter { !$0.hasPrefix(".") && !others.contains($0) && isMade(wish.appendingPathComponent($0), wish: wish) }.sorted()
    }

    /// Whether a part's folder holds a device's app, read without following a link: its marker, naming an integration.
    static func isMade(_ dir: URL, wish: URL) -> Bool {
        AppFile.read(dir.appendingPathComponent(marker), inFolder: wish, last: 1) != nil
    }

    static func appKind(for project: LampProject) -> Integration.AppKind? { project.integration.flatMap(appKind) }

    /// The folder a device app's kind previews on this Mac (`app.declared.preview`), checked; nil when it has none.
    static func previewFolder(for project: LampProject) -> String? {
        // A game is looked at in its own preview, which plays it from a script, whatever its engine.
        guard project.hasDevice, !GameKit.isGame(project), let folder = appKind(for: project)?.declared?.preview,
              IntegrationCheck.isAppPath(folder) else { return nil }
        return folder
    }

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
        if GameKit.isGame(project), GameKit.engine(project) == .native {
            // The game's own build for the console, then the package Lamp makes of what it left.
            let zip = project.dir.appendingPathComponent("build/xbox.zip")
            AppFolder.remove(zip, in: project.dir)
            try await GameKit.build(project, for: .xbox, started: started)
            guard let data = AppFile.read(zip, in: project), !data.isEmpty else { throw Failure(message: "The game's build left nothing to package.") }
            guard data.count <= packageLimit else { throw Failure(message: "The game is bigger than Lamp sends to a device (\(packageLimit >> 30) GB).") }
            try FileManager.default.createDirectory(at: buildFolder(for: project), withIntermediateDirectories: true)
            try wrapMSIX(data, for: project, entry: .program("App.exe"))
            return
        }
        // The package step runs on Lamp's copy of the app, where a game's page is told the device it's on (`GamePage`).
        // That copy is checked for it after the step, and so is the package where Lamp can read it (a ZIP): a package
        // in any other form is the integration's own, which Lamp doesn't look inside.
        let source = try await packageSource(project)
        let page = GameKit.isGame(project) ? try GamePage.place(for: project) : nil
        if let page { try GamePage.stage(source.appendingPathComponent(GameKit.webFolder), in: source, for: page) }
        let output = freshOutput(declared.output, in: source)
        var printed: [String] = []
        let status = await Sandbox.run(declared.package, for: project, cwd: source, opening: [source.path], started: started) { printed.append($0) }
        guard status == 0 else {
            throw Failure(message: (["The package step failed:"] + printed.suffix(30)).joined(separator: "\n"))
        }
        if let page { try GamePage.check(source, for: page) }
        guard let data = AppFile.read(output, inFolder: source), !data.isEmpty else {
            throw Failure(message: "The package step ran but left nothing at \(declared.output).")
        }
        guard data.count <= packageLimit else { throw Failure(message: "The package is bigger than Lamp sends to a device (\(packageLimit >> 30) GB).") }
        if let page, declared.output.lowercased().hasSuffix(".zip") { try GamePage.check(payload: try MSIX.files(inZip: data), for: page) }
        try FileManager.default.createDirectory(at: buildFolder(for: project), withIntermediateDirectories: true)
        if declared.wrap == "msix" {
            try wrapMSIX(data, for: project, entry: WebHost.isUsed(by: declared) ? .webHost : .page(declared.start ?? "index.html"))
        } else if !DeviceSupport.libraries(for: project).isEmpty, declared.output.lowercased().hasSuffix(".zip") {
            try await withFilledSupport(data, for: project).write(to: packageURL(for: project), options: .atomic)
        } else {
            try data.write(to: packageURL(for: project), options: .atomic)
        }
    }

    /// Where the package step leaves its package in the copy, with what an earlier package left in the app's folder
    /// (and so came along in the copy) taken away: a step that makes nothing mustn't pass on an old one.
    static func freshOutput(_ path: String, in source: URL) -> URL {
        let output = source.appendingPathComponent(path)
        AppFolder.remove(output, in: source)
        return output
    }

    /// The app's folder as its package step takes it: a copy in Lamp's own folder (`buildFolder`), never the app's, so
    /// what Lamp adds for this device goes into the package alone, and nothing in the app's folder changes while the
    /// package is made. What builds leave there (.build, build) and its history (.git) stay behind; the copy is made
    /// under the app's sandbox, as the preview's page is (`GameKit.stageWeb`).
    static func packageSource(_ project: LampProject, in folder: URL? = nil) async throws -> URL {
        let fm = FileManager.default
        let source = (folder ?? buildFolder(for: project)).appendingPathComponent("source")
        try? fm.removeItem(at: source)
        try fm.createDirectory(at: source, withIntermediateDirectories: true)
        let copy = "cd \"$LAMP_FROM\" && /usr/bin/rsync -a --exclude=/.build --exclude=/build --exclude=/.git ./ \"$LAMP_TO/\""
        guard let confined = Sandbox.wrapEngine(copy, for: project, opening: [source.path]) else {
            throw Failure(message: "Lamp couldn't copy the app's files to package it.")
        }
        var output: [String] = []
        let status = await Shell.run(confined, cwd: source, env: ["LAMP_FROM": project.dir.path, "LAMP_TO": source.path], login: false) { output.append($0) }
        guard status == 0 else { throw Failure(message: "Lamp couldn't copy the app's files to package it.\n\n" + output.suffix(4).joined(separator: "\n")) }
        // Links stay links in the copy, and Lamp writes in it: one anywhere in it refuses the package, as it refuses the
        // page for the preview or a phone (`GameKit.stageWeb`, `Devices.checkUnlinked`).
        let linked = (fm.enumerator(at: source, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? [])
            .first { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
        if let linked {
            try? fm.removeItem(at: source)
            throw Failure(message: "\(linked.path.dropFirst(source.path.count + 1)) is a shortcut to another file. Put the file itself in its place.")
        }
        return source
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

    /// The device the app goes on: the one chosen under Try On, else the only one of its integration's that's set up.
    /// One only found is never taken for the person's on its own: it may be a neighbor's, and is set up when chosen.
    /// A chosen one since forgotten is still the choice while it's on the network (Play sets it up again first); gone
    /// from both, the choice falls to the only one set up, as if none had been made.
    @MainActor static func device(for project: LampProject, among devices: [Device]) -> Device? {
        let mine = devices.filter { $0.integration == project.deviceIntegration && $0.integration != nil }
        if let id = project.device, let chosen = mine.first(where: { $0.id == id }) ?? Integrations.kept(id).map({ Integrations.device(from: $0, onNetwork: false) }) {
            return chosen
        }
        let setUp = mine.filter(\.isSetUp)
        return setUp.count == 1 ? setUp.first : nil
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
    /// `waiting` is told when Lamp waits on the device to finish installing it.
    static func install(_ project: LampProject, on device: Device, log: FileHandle?,
                        stillWanted: @escaping @MainActor () -> Bool = { true },
                        waiting: @escaping @MainActor () -> Void = {}) async throws -> Run {
        guard let integration = integration(for: project), let bridge = integration.bridge, let install = bridge.install else {
            throw Failure(message: "\(device.name)'s integration doesn't say how an app goes on it.")
        }
        var runner = IntegrationRunner(integration: integration, device: device, onLog: { line in
            log?.write(Data((line + "\n").utf8))
        })
        runner.onWaiting = { Task { @MainActor in waiting() } }
        let run = Run(device: device)
        // The app opened by this install asks for its token, which isn't in its package, over the network: Lamp listens
        // there from now on, and after, for as long as the app is on a device (`wentOnADevice`).
        if !DeviceSupport.libraries(for: project).isEmpty, let address = device.address {
            await MainActor.run { Store.shared.puttingOnDevice(project.id, true) }
            DeviceSupport.Claims.shared.open(project.id, from: address)
        }
        defer { Task { @MainActor in Store.shared.puttingOnDevice(project.id, false) } }
        // A game's or a screen's page of a wish asks for its wish's key too, as a TV app's does: open from minutes before
        // the upload, and again once it's open, since an Xbox's install can take longer than that.
        let claimsKey = (GameKit.isGame(project) || ScreenKit.isScreen(project)) && Template.carriesWish(project) ? device.address : nil
        if let claimsKey { WishClaims.shared.open(project.id, from: claimsKey) }
        if let logs = bridge.logs, !logs.isEmpty {
            // A device with nothing listening on its log's port still takes the app.
            run.streams = (try? await runner.run(logs).streams) ?? []
        }
        // A device busy closing the app it's replacing can drop a connection, the upload's or the launch's just after
        // it; a little later it's ready, so the pair is tried again a couple of times before Lamp gives up.
        // The copy on the device now is ended first: a device can fail to open a package installed over its running copy.
        // A Roku's installer waits on a developer channel that's still running until the upload times out, so a package
        // that isn't wrapped (one copy on the device, whichever app it is) is always ended first.
        let running = integration.app?.declared?.wrap == nil ? values(project) : installedValues(project, on: device)
        if let stop = bridge.stop, !stop.isEmpty, let running {
            _ = try? await runner.run(stop, extra: running)
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
                    // A device only just done installing can refuse the launch, or take it and not open the app yet:
                    // launched again until it's seen running (`IntegrationRunner.open`).
                    do {
                        try await runner.open(launch, running: bridge.running, extra: values(project), changed: changed, stillWanted: stillWanted)
                    } catch let notOpened as IntegrationRunner.NotOpened {
                        if let refused = notOpened.refused { log?.write(Data((refused + "\n").utf8)) }
                        throw Failure(message: notOpened.launched
                            ? "The \(integration.name) is still finishing installing \(project.name), or it closed as it opened. Try again in a moment."
                            : stillInstalling(project, on: integration))
                    }
                }
                break
            } catch let error as URLError where error.code == .networkConnectionLost && tries < 2 {
                tries += 1
                try? await Task.sleep(for: .seconds(3))
            } catch {
                await runner.putBack(changed)
                run.end()
                // Lamp stopped waiting while the device was still installing it: that, plainly, for a moment later.
                if (error as? IntegrationRunner.Failure)?.stillWorking == true { throw Failure(message: stillInstalling(project, on: integration)) }
                throw error
            }
        }
        await runner.putBack(changed)
        if let claimsKey { WishClaims.shared.renew(project.id, from: claimsKey) }
        return run
    }

    private static func stillInstalling(_ project: LampProject, on integration: Integration) -> String {
        "The \(integration.name) is still finishing installing \(project.name). Try again in a moment."
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

    /// The app's screen as text, through the bridge's `screen`; nil when the integration has none.
    static func screen(_ project: LampProject, on device: Device) async throws -> String? {
        guard let integration = integration(for: project), let screen = integration.bridge?.screen, !screen.isEmpty else { return nil }
        return try await IntegrationRunner(integration: integration, device: device).run(screen, extra: values(project)).screen
    }

    /// Presses one of the remote's keys by Lamp's name for it, through the bridge's use.
    static func press(_ key: String, in project: LampProject, on device: Device) async throws {
        guard let integration = integration(for: project), let use = integration.bridge?.use, let name = integration.bridge?.keys?[key] else {
            throw Failure(message: "\(device.name) has no key called \"\(key)\". Its keys are \(keys(for: project).joined(separator: ", ")).")
        }
        _ = try await IntegrationRunner(integration: integration, device: device).run(use, extra: values(project).merging(["key": name]) { $1 })
    }

    /// Types text on the device's screen through the bridge's `type`, a character at a time, while `stillWanted` says
    /// the app is still the one there and the turn still running.
    static func type(_ text: String, in project: LampProject, on device: Device, stillWanted: @MainActor () -> Bool) async throws {
        guard let integration = integration(for: project), let type = integration.bridge?.type, !type.isEmpty else {
            throw Failure(message: "Lamp can't type on the \(device.name): its integration doesn't say how.")
        }
        let runner = IntegrationRunner(integration: integration, device: device)
        for character in text {
            guard await stillWanted() else { throw Failure(message: "Stopped.") }
            _ = try await runner.run(type, extra: values(project).merging(["text": String(character)]) { $1 })
        }
    }

    /// Ends the app on the device as the person stops it, through the bridge's `stop`; false when the integration has
    /// none or the device refused, for the caller to take the device back another way (Home).
    static func stop(_ project: LampProject, on device: Device) async -> Bool {
        guard let integration = integration(for: project), let stop = integration.bridge?.stop, !stop.isEmpty else { return false }
        // A wrapped package is ended by its names, so only the copy Lamp knows is there.
        let extra = integration.app?.declared?.wrap == nil ? values(project) : installedValues(project, on: device)
        guard let extra else { return false }
        return (try? await IntegrationRunner(integration: integration, device: device).run(stop, extra: extra)) != nil
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
        // Which app the device last took, for a device that keeps only one copy of anything Lamp puts there.
        if !pending { try? Data(project.id.utf8).write(to: lastOnDevice(device.id), options: .atomic) }
    }

    /// The devices an app is going on or coming off now: one at a time on each, since an install replaces what's there.
    @MainActor private static var busy: Set<String> = []

    @MainActor static func take(_ id: String) async {
        while busy.contains(id) { try? await Task.sleep(for: .milliseconds(300)) }
        busy.insert(id)
    }

    @MainActor static func release(_ id: String) { busy.remove(id) }

    /// Where Lamp notes which app it last put on a device: a Roku has one developer channel, which each install replaces.
    private static func lastOnDevice(_ id: String) -> URL {
        Edition.supportFolder.appendingPathComponent("Device Builds").appendingPathComponent("last-\(MSIX.publisherID(id)).txt")
    }

    /// Whether Lamp has put the app on a device, by the record each install leaves: an app made for a device but never
    /// put on one doesn't need Lamp listening on the network for it.
    static func wentOnADevice(_ project: LampProject) -> Bool {
        let names = (try? FileManager.default.contentsOfDirectory(atPath: buildFolder(for: project).path)) ?? []
        return names.contains { $0.hasPrefix("installed-") && $0.hasSuffix(".device") }
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
            // Never while an install is putting another app there: its ownership is checked and the copy removed in one go.
            await take(id)
            defer { release(id) }
            let runner = IntegrationRunner(integration: integration, device: device)
            // A package that isn't wrapped has no names of its own: the device keeps one copy (a Roku's developer channel).
            guard integration.app?.declared?.wrap != nil else {
                // Only while it's still this app's: another wish put on the device since has replaced it.
                guard (try? String(contentsOf: lastOnDevice(id), encoding: .utf8)) == project.id else { continue }
                if let stop = integration.bridge?.stop { _ = try? await runner.run(stop, extra: values(project)) }
                _ = try? await runner.run(remove, extra: values(project))
                continue
            }
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

    /// Takes the copy just put on one device off it, saying what the device answered when it refused: the test run's
    /// last stage (`IntegrationProbe`), where a removal that fails is the finding rather than something to pass over.
    static func remove(_ project: LampProject, from device: Device) async throws {
        guard let integration = integration(for: project), let remove = integration.bridge?.remove, !remove.isEmpty else { return }
        let extra = integration.app?.declared?.wrap == nil ? values(project) : (installedValues(project, on: device) ?? values(project))
        let runner = IntegrationRunner(integration: integration, device: device)
        if let stop = integration.bridge?.stop { _ = try? await runner.run(stop, extra: extra) }
        _ = try await runner.run(remove, extra: extra)
    }

    /// Lamp's values for the bridge: the app's id, whether it's a game, and for a wrapped package the names Windows
    /// gives it.
    static func values(_ project: LampProject) -> [String: String] {
        var values = values(project, identity: buildFolder(for: project).appendingPathComponent("identity.json")) ?? ["appID": project.id]
        values["isGame"] = isGame(project) ? "true" : "false"
        return values
    }

    /// A game, to a device that gives games more than apps (an Xbox gives a game about five times the memory and the
    /// whole GPU): Lamp's native games always, and an app of another kind when its capabilities.json says it's one or
    /// its icon is a game's. The icon's `game` is the same word from the agent, written for every game it has made, so
    /// a game made before capabilities.json asked is installed as one without changing it.
    static func isGame(_ project: LampProject) -> Bool {
        GameKit.isGame(project) || Template.Capabilities.load(project).game == true || Icons.load(project)?.game == true
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
        let integration = DeviceApps.integration(for: project)
        let name = integration?.name ?? "the device"
        let rules = [Rules.deviceEdit, Rules.ask, Rules.shell, Rules.deviceKind(integration), Rules.deviceBlocks(project), Rules.icon, Rules.about,
                     Rules.deviceAttachments, Rules.deviceTry(project), Rules.appMd, Rules.audience, Skills.index(Skills.offered(.device)),
                     Rules.begin, Rules.finish]
        let previews = DeviceApps.previewFolder(for: project) != nil
        return (Rules.deviceHeader(integration, previews: previews) + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: name)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a " + name)
            .replacingOccurrences(of: "{{RELAUNCH}}", with: previews ? "opens it again in the \(name) preview on this Mac" : "puts it on the \(name) again and opens it")
    }
}

extension Agent {
    /// The rules for a device's app as one of a wish's apps, in its folder (Roku/, whose name says which integration):
    /// the device's own rules for the files there, then how it stands beside the others.
    /// `integration`: the app's own (its folder's marker), which the folder's name may no longer say.
    static func devicePrompt(part folder: String, alone: Bool = false, integration id: String? = nil) -> String {
        let integration = id.flatMap { Integrations.integration(DeviceApps.split($0).integration) } ?? DeviceApps.integration(inFolder: folder)
        let app = LampProject(id: "", name: "", exe: "", dir: URL(fileURLWithPath: "/"), platform: .device, integration: integration?.id)
        let name = integration?.name ?? "the device"
        let rules = [Rules.deviceEdit, Rules.deviceKind(integration), Rules.deviceBlocks(app), Rules.deviceAttachments, Rules.deviceTry(app),
                     alone ? "" : Rules.deviceAmongApps]
        let what = "an app for the person's \(name)\(integration?.kind.map { " (\($0))" } ?? ""), made, packaged and put on it as its integration declares"
        return (Rules.partHeader(what, folder: folder) + "\n\nRules:\n" + rules.joined())
            .replacingOccurrences(of: "{{DEVICE}}", with: name)
            .replacingOccurrences(of: "{{A_DEVICE}}", with: "a " + name)
            .replacingOccurrences(of: "{{RELAUNCH}}", with: "puts it on the \(name) again and opens it")
    }
}

extension Agent.Rules {
    /// For a wish with a device's app beside its other apps: it can't reach them yet, so nothing of the wish leans on that,
    /// and what does work today.
    static let deviceAmongApps = """

    - The {{DEVICE}} app is one of this wish's apps, in its own folder, but it can't reach the wish's other apps yet and \
    they can't reach it: the link between a wish's apps doesn't run on {{A_DEVICE}} yet. Its `LampWish` (in its building \
    blocks, beside LampAI) always says it's away, with that reason. So write each app to stand on its own: the \
    {{DEVICE}} app keeps its own data with LampStore and gets what's new from the web or with LampAI, not from the other \
    apps. Another app of the wish on the Mac or an iPhone can still drive it as a remote from the same network where Lamp \
    has a block for the device (`LampRoku` for a Roku: its keys, and opening the app by launching "dev"), which needs no \
    link. Tell the person in a sentence, once, that the two don't share data yet, and what each does meanwhile.
    """

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
                    + " " + webSound.dropFirst(2).replacingOccurrences(of: "\n", with: "")
                    + " "
            case .brightscript:
                rule += "Include \(entry.path)/Lamp.brs in a component's XML (`<script type=\"text/brightscript\" uri=\"pkg:/\(entry.path)/Lamp.brs\" />`) "
                    + "to use `LampAI_ask`, `LampAI_makeImage`, `LampAI_isTrue`, `LampAI_choose`, `LampAI_rate`, `LampAI_decide`, `LampStore_load`, "
                    + "`LampStore_save`, `LampStore_collection` and `LampAssets_text`. Each LampAI call starts a Task node and gives it back: keep it in m, "
                    + "observe its `result` field, and show `result.error` when it's set. Lamp on the person's Mac answers while the device is on its Wi‑Fi "
                    + "with Lamp open. Text from outside the app goes in `options.data`, never into the prompt. Keep the package step zipping that folder. "
                    + "Read Lamp.brs's opening comment before using it; never call an AI service yourself. "
                if let wish = DeviceSupport.wishFile(for: project) {
                    rule += "\(wish) is `LampWish`, the wish's other apps: on this device it always says it's away, so show its reason "
                        + "where the app would show them, and keep the app whole without them. "
                }
            case .three:
                let folder = "./" + DeviceSupport.pagePath(entry.path, page: DeviceApps.previewFolder(for: project)) + "/"
                rule += "\(entry.path) is three.js r\(DeviceSupport.threeRevision) with its addons (controls, loaders, geometries, "
                    + "postprocessing, utils), which this page reaches at `\(folder)`; this page has no game runtime, Phaser bridge or Rapier. "
                    + "For anything 3D, read the 3d-game skill with `read_skill` before writing it, and load the library from that folder. "
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
            if integration?.bridge?.type?.isEmpty == false { rule += "`type` with `text` types into a keyboard on its screen once one has focus. " }
        }
        if integration?.bridge?.look == nil { rule += "Its integration has no way to picture its screen, so ask the person what they see. " }
        if integration?.bridge?.screen != nil {
            return rule + "Both also give you the screen as text, as the \(name) describes it: the tree of the app's nodes, with what each "
                + "shows, where it is and which one has focus. Read it to check text and focus the picture is too small for. There is no "
                + "pointer: try the app the way the person will, with the keys.\n"
        }
        return rule + "There is no screen as text and no pointer: try the app the way the person will, with the keys.\n"
    }
}
