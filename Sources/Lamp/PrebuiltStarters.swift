import Foundation

/// The starters Lamp comes with, built when Lamp is released, so one opens at once instead of after its first
/// build, and before Apple's build tools are even on the Mac. A release runs `Lamp --prebuild-starters <folder>`
/// (build.sh, `PREBUILD_STARTERS=1`), which builds each starter of the checkout as this Mac would, as a live build
/// (`LiveReload`), and leaves it in `<folder>/<starter>/Prebuilt`: the app, the live copy of its sources (so a change
/// can go into it from the first one), and what it was built from. build.sh signs the app and zips it as an asset of
/// the release on GitHub, pinning its size and hash in the bundle's listing (`Starters.Listed.prebuilt`); it's
/// fetched with the starter's tree when the starter is first opened (`StarterDownloads`), and its signature is checked
/// as Lamp's own before it's used (`install`).
///
/// A prebuilt app holds nothing of the Mac it's put on: what an app is told about itself and Lamp is written into
/// its Info.plist when it's installed (`Template.installValues`). It's used only when it's exactly what a build here
/// would make: by this Lamp (`BuildStamp`), under the program name it was built with, from the starter's files as
/// they still are in the app. Anything else is built as before.
enum PrebuiltStarters {
    static let folderName = "Prebuilt"
    static let commandLineFlag = "--prebuild-starters"
    static let restampFlag = "--restamp-starters"

    struct Manifest: Codable {
        var exe: String
        var support: String
    }

    /// The parts of the live copy that go with the app (not its build folder, which is the size of the app many
    /// times over and only speeds up the next whole build).
    private static let liveParts = ["Package.swift", "Sources", "built", "live.pl"]

    /// The starter's prebuilt app on this Mac, once it's been fetched.
    static func archive(of starter: Starters.Starter) -> URL? { StarterDownloads.prebuiltArchive(of: starter) }

    /// The starter as Lamp ships it, found by the name in the app's starter.md (`Starters.starter(of:)` reads it
    /// from the app's own folder).
    private static func shipped(_ project: LampProject) -> Starters.Starter? {
        guard let name = Starters.starter(of: project)?.name else { return nil }
        return Starters.bundled.first { $0.name == name }
    }

    /// Whether this starter's prebuilt app from this Lamp is on this Mac.
    static func has(_ project: LampProject) -> Bool {
        shipped(project).flatMap(archive(of:)) != nil
    }

    /// Whether this Lamp pins a prebuilt app for the starter that isn't on this Mac (it couldn't be fetched).
    static func unavailable(_ project: LampProject) -> Bool {
        guard let starter = shipped(project) else { return false }
        return StarterDownloads.prebuilt(of: starter) != nil && archive(of: starter) == nil
    }

    /// Where `--prebuild-starters` and `--restamp-starters` leave the starters they build: the folder after the flag.
    private static func output(after flag: String) -> URL {
        let arguments = CommandLine.arguments
        guard let index = arguments.firstIndex(of: flag), index + 1 < arguments.count else {
            FileHandle.standardError.write(Data("Usage: Lamp \(flag) <folder>\n".utf8))
            exit(2)
        }
        return URL(fileURLWithPath: arguments[index + 1], isDirectory: true)
    }

    // MARK: - Building, when Lamp is released

    /// `Lamp --prebuild-starters <folder>`: builds every starter (the checkout's, `Starters.folder`) into the folder,
    /// then quits. Run by build.sh before Lamp is signed; a starter that doesn't build stops the release.
    static func runFromCommandLine() -> Never {
        let fm = FileManager.default
        let out = output(after: commandLineFlag)
        let root = fm.temporaryDirectory.appendingPathComponent("lamp-prebuild-\(UUID().uuidString)")
        var failed = false
        for starter in Starters.bundled {
            do {
                try fm.createDirectory(at: root, withIntermediateDirectories: true)
                try build(starter, in: root, to: out.appendingPathComponent(starter.folder.lastPathComponent))
                print("Prebuilt \(starter.name)")
            } catch {
                FileHandle.standardError.write(Data("Couldn't prebuild \(starter.name): \(error.localizedDescription)\n".utf8))
                failed = true
            }
            // Each starter's project and build folder go as soon as it's done: together they run to gigabytes.
            remove(root)
        }
        // exit doesn't unwind: nothing of the work folder is left behind.
        remove(root)
        exit(failed ? 1 : 0)
    }

    /// Removes the work folder, falling back to `rm -rf` when FileManager stops at something it can't remove (a
    /// build folder's odd entries), and says so when even that leaves it: a folder left behind is gigabytes in the
    /// temporary folder, silently.
    private static func remove(_ folder: URL) {
        let fm = FileManager.default
        guard fm.fileExists(atPath: folder.path) else { return }
        if (try? fm.removeItem(at: folder)) != nil { return }
        let rm = Process()
        rm.executableURL = URL(fileURLWithPath: "/bin/rm")
        rm.arguments = ["-rf", folder.path]
        try? rm.run()
        rm.waitUntilExit()
        if fm.fileExists(atPath: folder.path) {
            FileHandle.standardError.write(Data("Couldn't remove the prebuild folder \(folder.path)\n".utf8))
        }
    }

    /// `Lamp --restamp-starters`: a development build that kept its prebuilt starters from an earlier one (build.sh)
    /// stamps them as its own. They're the same apps: what they're made from is unchanged, but the stamp also covers
    /// the chat sidebar, which every build signs again.
    static func restampFromCommandLine() -> Never {
        let built = output(after: restampFlag)
        for starter in Starters.bundled {
            let out = built.appendingPathComponent(starter.folder.lastPathComponent).appendingPathComponent(folderName)
            let manifestURL = out.appendingPathComponent("manifest.json")
            guard let data = try? Data(contentsOf: manifestURL),
                  var manifest = try? JSONDecoder().decode(Manifest.self, from: data) else { continue }
            BuildStamp.stamp(out.appendingPathComponent("\(manifest.exe).app"))
            manifest.support = BuildStamp.current.support ?? ""
            try? JSONEncoder().encode(manifest).write(to: manifestURL)
        }
        exit(0)
    }

    private struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// One starter made into an app the way the desk makes it (`Store.add(starter:)`), built live, and left in
    /// `<folder>/Prebuilt`.
    private static func build(_ starter: Starters.Starter, in root: URL, to folder: URL) throws {
        let fm = FileManager.default
        let project = try Template.draft(name: starter.name, platform: starter.kind, in: root)
        try Template.fill(project)
        try Starters.copy(starter, into: project)
        try Template.writeOwnedFiles(for: project)
        let build = Process()
        build.executableURL = URL(fileURLWithPath: "/bin/zsh")
        build.arguments = ["-c", "./build.sh"]
        build.currentDirectoryURL = project.dir
        build.environment = ProcessInfo.processInfo.environment.merging(["LAMP_LIVE": "1"]) { $1 }
            .merging(try GamePage.buildEnvironment(for: project)) { $1 }
            // A game or a screen with no Swift of its own is a copy of Lamp's player, as it is on the person's Mac.
            .merging(GameKit.playerEnvironment(for: project)) { $1 }
        let output = Pipe()
        build.standardOutput = output
        build.standardError = output
        try build.run()
        let log = output.fileHandleForReading.readDataToEndOfFile()
        build.waitUntilExit()
        guard build.terminationStatus == 0 else {
            throw Failure(message: "its build failed:\n" + String(decoding: log.suffix(4000), as: UTF8.self))
        }
        BuildStamp.write(for: project)

        let out = folder.appendingPathComponent(folderName)
        try? fm.removeItem(at: out)
        try fm.createDirectory(at: out.appendingPathComponent("live"), withIntermediateDirectories: true)
        try fm.copyItem(at: project.builtURL, to: out.appendingPathComponent("\(project.exe).app"))
        for part in liveParts {
            let from = LiveReload.folder(project).appendingPathComponent(part)
            if fm.fileExists(atPath: from.path) { try fm.copyItem(at: from, to: out.appendingPathComponent("live").appendingPathComponent(part)) }
        }
        let manifest = Manifest(exe: project.exe, support: BuildStamp.current.support ?? "")
        try JSONEncoder().encode(manifest).write(to: out.appendingPathComponent("manifest.json"))
    }

    // MARK: - Using one, on the person's Mac

    /// Puts the starter's prebuilt app where its build would be, with the live copy it was built from, when it's
    /// what a build here would make. False, with nothing changed, when it isn't: the starter is then built.
    static func install(into project: LampProject) -> Bool {
        let fm = FileManager.default
        guard let starter = shipped(project), let archive = archive(of: starter),
              unchanged(starter, in: project) else { return false }
        let work = fm.temporaryDirectory.appendingPathComponent("lamp-starter-\(UUID().uuidString)")
        defer { try? fm.removeItem(at: work) }
        guard (try? fm.createDirectory(at: work, withIntermediateDirectories: true)) != nil else { return false }
        let unzip = Process()
        unzip.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        unzip.arguments = ["-x", "-k", archive.path, work.path]
        guard (try? unzip.run()) != nil else { return false }
        unzip.waitUntilExit()
        let unpacked = work.appendingPathComponent(folderName)
        guard unzip.terminationStatus == 0,
              let data = try? Data(contentsOf: unpacked.appendingPathComponent("manifest.json")),
              let manifest = try? JSONDecoder().decode(Manifest.self, from: data),
              manifest.exe == project.exe, manifest.support == BuildStamp.current.support else { return false }
        let app = unpacked.appendingPathComponent("\(project.exe).app")
        guard fm.fileExists(atPath: app.appendingPathComponent("Contents/MacOS/\(project.exe)").path) else { return false }
        // Downloaded: it runs only as what this Lamp's own build signed, checked before anything of it is changed.
        guard Downloads.signedLikeLamp(app) else {
            NSLog("Lamp refused the prebuilt \(project.name): it isn't signed as Lamp is")
            try? fm.removeItem(at: archive)
            return false
        }
        // Built under the starter's own folder name: this copy's may be another ("hotshelf-2"), and the bundle id
        // follows it.
        setIdentifier(project.bundleID, in: app)
        let widget = Template.widgetURL(in: app, of: project)
        if fm.fileExists(atPath: widget.path) { setIdentifier(project.bundleID + ".widget", in: widget) }
        do {
            try fm.createDirectory(at: project.builtURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try AppFolder.copy(app, in: work, to: project.builtURL, in: project.dir)
            for part in liveParts {
                let from = unpacked.appendingPathComponent("live").appendingPathComponent(part)
                guard fm.fileExists(atPath: from.path) else { continue }
                try AppFolder.copy(from, in: work, to: LiveReload.folder(project).appendingPathComponent(part), in: project.dir)
            }
        } catch {
            NSLog("Lamp couldn't use the prebuilt \(project.name): \(error.localizedDescription)")
            AppFolder.remove(project.builtURL, in: project.dir)
            return false
        }
        Runtime.markBuilt(project, from: Runtime.fingerprint(project))
        return true
    }

    /// Whether the app's code is still the starter's, file for file, with nothing added: what the prebuilt app was
    /// built from. Lamp's own files there (LampSupport.swift and the like) are written afresh and left out.
    private static func unchanged(_ starter: Starters.Starter, in project: LampProject) -> Bool {
        let fm = FileManager.default
        guard Starters.hasTree(starter) else { return false }
        // Lamp's own files, which every app of the kind gets (a game's or a screen's are its host's, lamp.js and three.js),
        // and the Swift that answers a page's calls while it's still the one Lamp wrote, which a starter doesn't ship.
        var owned: Set<String> = ["Sources/LampSupport.swift", Template.sceneSupportPath,
                                  "\(Template.widgetFolder)/\(Template.widgetSupportFile)", "\(Template.shareFolder)/\(Template.shareSupportFile)",
                                  "\(Template.watchFolder)/\(Template.watchSupportFile)",
                                  "\(Template.watchFolder)/Complications/\(Template.watchSupportFile)"]
        owned.formUnion(DeviceSupport.paths(for: project))
        if let native = GameKit.native, AppFile.text(project.dir.appendingPathComponent(native.path), in: project) == native.text {
            owned.insert(native.path)
        }
        // The app's own code: its Swift, and a page's files in Web/ (a game's or a screen's), whatever they are.
        func swiftFiles(in root: URL) -> Set<String> {
            var found: Set<String> = []
            for folder in ["Sources", Template.widgetFolder, Template.shareFolder, Template.watchFolder] {
                let dir = root.appendingPathComponent(folder)
                for file in (try? fm.subpathsOfDirectory(atPath: dir.path)) ?? [] where file.hasSuffix(".swift") {
                    found.insert("\(folder)/\(file)")
                }
            }
            if project.platform.target.showsPage(project) {
                let web = root.appendingPathComponent(GameKit.webFolder)
                for file in (try? fm.subpathsOfDirectory(atPath: web.path)) ?? [] {
                    var folder: ObjCBool = false
                    if fm.fileExists(atPath: web.appendingPathComponent(file).path, isDirectory: &folder), !folder.boolValue {
                        found.insert("\(GameKit.webFolder)/\(file)")
                    }
                }
            }
            return found.subtracting(owned)
        }
        let shipped = swiftFiles(in: starter.tree)
        guard swiftFiles(in: project.dir) == shipped else { return false }
        return shipped.allSatisfy { file in
            guard let theirs = fm.contents(atPath: starter.tree.appendingPathComponent(file).path) else { return false }
            return AppFile.read(project.dir.appendingPathComponent(file), in: project) == theirs
        }
    }

    private static func setIdentifier(_ id: String, in bundle: URL) {
        let url = bundle.appendingPathComponent("Contents/Info.plist")
        guard let data = try? Data(contentsOf: url),
              var plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else { return }
        plist["CFBundleIdentifier"] = id
        if let out = try? PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0) { try? out.write(to: url) }
    }
}
