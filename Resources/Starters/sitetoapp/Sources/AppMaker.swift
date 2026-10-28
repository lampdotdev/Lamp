import AppKit
import CoreServices

/// Makes a site into a Mac app of its own, in ~/Applications: a copy of this app that opens only that site, with
/// its name, its icon and its own sign-in, camera and microphone permissions.
enum AppMaker {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static var folder: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Applications")
    }

    static func appURL(for site: Site) -> URL {
        let name = site.name.replacingOccurrences(of: "/", with: "-").replacingOccurrences(of: ":", with: "-")
        return folder.appendingPathComponent(name + ".app")
    }

    static func bundleID(for site: Site) -> String {
        let host = site.host.lowercased().map { $0.isLetter || $0.isNumber || $0 == "." || $0 == "-" ? String($0) : "-" }.joined()
        return "dev.lamp.site.\(host).\(site.id.uuidString.prefix(8).lowercased())"
    }

    /// Builds (or rebuilds) the site's app and returns where it is.
    static func make(_ site: Site, icon: CGImage?) async throws -> URL {
        let destination = appURL(for: site)
        let id = bundleID(for: site)
        // Its own app can't be replaced while it's open.
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: id) {
            app.terminate()
        }
        let icns = icon.flatMap(SiteIcon.icns)
        let source = Bundle.main.bundleURL
        return try await Task.detached(priority: .userInitiated) {
            try build(site, id: id, icns: icns, from: source, to: destination)
        }.value
    }

    private static func build(_ site: Site, id: String, icns: Data?, from source: URL, to destination: URL) throws -> URL {
        let files = FileManager.default
        try files.createDirectory(at: folder, withIntermediateDirectories: true)

        if files.fileExists(atPath: destination.path) {
            let info = NSDictionary(contentsOf: destination.appendingPathComponent("Contents/Info.plist"))
            guard info?["LampSiteID"] as? String == site.id.uuidString else {
                throw Failure(message: "There's already an app called “\(destination.deletingPathExtension().lastPathComponent)” in your Applications folder. Rename the site and try again.")
            }
        }

        let work = files.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try files.createDirectory(at: work, withIntermediateDirectories: true)
        defer { try? files.removeItem(at: work) }
        let app = work.appendingPathComponent(destination.lastPathComponent)
        try files.copyItem(at: source, to: app)

        let contents = app.appendingPathComponent("Contents")
        for leftover in ["_CodeSignature", "embedded.provisionprofile", "PlugIns", "Extensions", "Library"] {
            try? files.removeItem(at: contents.appendingPathComponent(leftover))
        }

        // Who the copy is: the site's name, its own id (so macOS keeps its permissions and Dock place apart),
        // and the site it opens.
        let plist = contents.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plist),
              var info = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw Failure(message: "Couldn't read this app's own settings to copy them.")
        }
        info["CFBundleIdentifier"] = id
        info["CFBundleName"] = String(site.name.prefix(15))
        info["CFBundleDisplayName"] = site.name
        info["LampSiteURL"] = site.url
        info["LampSiteName"] = site.name
        info["LampSiteID"] = site.id.uuidString
        info["LampInstall"] = ["dataID": id]
        info["NSCameraUsageDescription"] = "\(site.name) uses your camera for calls."
        info["NSMicrophoneUsageDescription"] = "\(site.name) uses your microphone for calls."
        for key in ["CFBundleIconName", "LampPhoneSecret", "LampAppGroup", "LampICloudContainer", "LampBackground",
                    "LSUIElement", "CFBundleDocumentTypes", "NSServices"] {
            info.removeValue(forKey: key)
        }
        if let icns {
            let resources = contents.appendingPathComponent("Resources")
            try files.createDirectory(at: resources, withIntermediateDirectories: true)
            try icns.write(to: resources.appendingPathComponent("SiteIcon.icns"))
            info["CFBundleIconFile"] = "SiteIcon"
        }
        try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0).write(to: plist)

        // Signed afresh for this Mac, as the copy is no longer the app that was signed.
        try run("/usr/bin/xattr", ["-cr", app.path])
        try run("/usr/bin/codesign", ["--force", "--deep", "--sign", "-", app.path])

        if files.fileExists(atPath: destination.path) {
            _ = try files.replaceItemAt(destination, withItemAt: app)
        } else {
            try files.moveItem(at: app, to: destination)
        }
        LSRegisterURL(destination as CFURL, true)
        return destination
    }

    private static func run(_ tool: String, _ arguments: [String]) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: tool)
        process.arguments = arguments
        let errors = Pipe()
        process.standardError = errors
        process.standardOutput = Pipe()
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
            print("AppMaker: \(tool) failed: \(text)")
            throw Failure(message: "macOS wouldn't sign the new app. \(text.trimmingCharacters(in: .whitespacesAndNewlines))")
        }
    }
}

extension Library {
    /// Makes the site's Dock app and opens it.
    func makeApp(for site: Site) {
        guard !making.contains(site.id) else { return }
        making.insert(site.id)
        Task {
            defer { making.remove(site.id) }
            do {
                let image = icon(for: site).flatMap { $0.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                    ?? SiteIcon.appIcon(from: nil, name: site.name)
                let url = try await AppMaker.make(site, icon: image)
                var current = self.site(site.id) ?? site
                current.appPath = url.path
                save(current)
                made = current
                let configuration = NSWorkspace.OpenConfiguration()
                configuration.activates = true
                _ = try? await NSWorkspace.shared.openApplication(at: url, configuration: configuration)
            } catch {
                makeError = error.localizedDescription
            }
        }
    }

    func revealApp(for site: Site) {
        guard let path = site.appPath, FileManager.default.fileExists(atPath: path) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
    }

    func hasApp(_ site: Site) -> Bool {
        site.appPath.map { FileManager.default.fileExists(atPath: $0) } ?? false
    }
}
