import Foundation

/// A TV app's files in a shared file (`Sharing`): what's under Web/ and Phone/, the agent's HTML, CSS and JavaScript as
/// code and the pictures, sounds and fonts beside them as data. Never Lamp's own script in Web/, which the Mac that
/// opens the file writes itself, never a hidden file or a link, and nothing from anywhere else in the app's folder.
enum TVFiles {
    /// Files read as code: what the review is shown, and what must be plain text.
    static let codeExtensions: Set<String> = ["html", "htm", "css", "js", "mjs", "json", "svg", "txt", "md", "xml", "csv"]
    static let folders = [TVTemplate.webFolder, TVTemplate.phoneFolder]

    static func list(in root: URL) -> (code: [URL], data: [URL]) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var code: [URL] = [], data: [URL] = []
        for folder in folders {
            guard let items = fm.enumerator(at: root.appendingPathComponent(folder), includingPropertiesForKeys: Array(keys)) else { continue }
            for case let url as URL in items {
                if url.lastPathComponent.hasPrefix(".") { items.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
                if Sharing.relativePath(of: url, in: root) == TVTemplate.supportFile { continue }
                if codeExtensions.contains(url.pathExtension.lowercased()) { code.append(url) } else { data.append(url) }
            }
        }
        return (code, data)
    }

    /// Puts a shared TV app's Web/ and Phone/ in place of the app's, and Lamp's own script back in Web/, which is what
    /// marks the folder as a TV app: without it the app wouldn't read as one until its next build.
    static func install(_ package: Sharing.Package, into project: LampProject) throws {
        let fm = FileManager.default
        for folder in folders { try? fm.removeItem(at: project.dir.appendingPathComponent(folder)) }
        for file in package.sources + package.webData {
            let relative = package.path(of: file)
            guard !relative.contains(".."), folders.contains(where: { relative.hasPrefix($0 + "/") }),
                  relative != TVTemplate.supportFile else { continue }
            let target = project.dir.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try fm.copyItem(at: file, to: target)
        }
        try TVTemplate.writeOwnedFiles(for: project)
    }

    // MARK: - The review

    /// Where a TV app's code reaches beyond itself, in the words the review uses for a Mac app's: a page's scripts fetch
    /// and send over the network, can load a script from the internet and can run text as code, which hide what the app
    /// does as loading code at runtime does in Swift. Lamp's AI blocks are the web library's (`DeviceSupport.webJS`).
    static let checks: [Sharing.Capability] = [
        Sharing.Capability(label: "Uses AI (your OpenRouter credit)", icon: "sparkles", level: .ordinary, patterns: ["LampAI.", "LampQuestion."]),
        Sharing.Capability(label: "Connects to the internet", icon: "network", level: .ordinary,
                           patterns: ["fetch(", "XMLHttpRequest", "WebSocket", "EventSource", "http://", "https://"]),
        Sharing.Capability(label: "Loads code from the internet (can hide what it does)", icon: "eye.slash", level: .sensitive,
                           patterns: ["<script src=\"http", "<script src='http", "import(\"http", "import('http", "importScripts("]),
        Sharing.Capability(label: "Loads code at runtime (can hide what it does)", icon: "eye.slash", level: .sensitive,
                           patterns: ["eval(", "new Function(", "document.write("]),
    ]

    static func detected(in sources: [URL]) -> [Sharing.Capability] {
        let everything = sources.compactMap { try? String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
        return checks.filter { item in item.patterns.contains { everything.contains($0) } }
    }
}

extension Sharing.Manifest {
    /// One of a wish's other apps in the file, in a folder of its own (`Parts`): which, and what it's made for.
    struct Part: Codable {
        var folder: String
        var platform: Platform
        var family: DeviceFamily?
    }
}

extension Sharing.Package {
    /// One of a wish's other apps as unpacked: its folder in the wish, and its files read as an app's are.
    struct Part {
        let folder: String
        let package: Sharing.Package
    }
}

extension Sharing {
    /// The wording the review gets for a TV app, and for a wish of several apps.
    static let webReview = """

        This app is a TV app: HTML, CSS and JavaScript under Web/ (and, under Phone/, a page a phone opens as its \
        controller or second screen), run by a Samsung or LG TV's browser, or by Lamp's preview on this Mac, with no \
        build step. Lamp's own script, lamp.js, isn't in the file; the LampAI, LampQuestion, LampStore and LampAssets \
        objects its code uses are Lamp's blocks for the web, like the ones above. Its reach is what its scripts fetch \
        and where they send data; a script loaded from the internet, or text run as code, can hide what it does.

        """

    static func partsReview(_ parts: [String]) -> String {
        guard !parts.isEmpty else { return "" }
        return """

        This file is a wish of more than one app, made to work together (a TV app with the iPhone app that controls \
        it, a Mac app with an Android app): beside the app at the root, \(parts.joined(separator: ", ")), each in its own \
        folder, whose files are named with the folder first. Judge each as you would the app at the root, and what \
        they share between them as data going from one to the other.

        """
    }
}

/// A three.js game's files in a shared file (`Sharing`): its page in Web/, the agent's HTML, CSS and JavaScript as code
/// and its models, pictures and sounds as data, and the Swift that answers the page's calls of the device
/// (Sources/Native.swift) as code too. Never Lamp's runtime beside the page (lamp-game.js, lamp-controllers.js, lamp.js,
/// three/) or the app around it, which the Mac that opens the file writes itself (`GameKit.write`), never a hidden file
/// or a link. A C++ game isn't shared: Lamp makes no new ones (`GameKit.engine(for:)`).
enum GameFiles {
    static let native = "Sources/Native.swift"

    /// Lamp's own files in a game's Web/, by their path in the app.
    static func isLamps(_ relative: String) -> Bool {
        relative == "\(GameKit.webFolder)/lamp-game.js" || relative == "\(GameKit.webFolder)/lamp.js" || relative == GameKit.controllersFile
            || relative == "\(GameKit.webFolder)/\(GamePage.deviceFile)"
            || relative.hasPrefix("\(GameKit.webFolder)/three/")
    }

    static func list(in root: URL) -> (code: [URL], data: [URL]) {
        let fm = FileManager.default
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        var code: [URL] = [], data: [URL] = []
        if let items = fm.enumerator(at: root.appendingPathComponent(GameKit.webFolder), includingPropertiesForKeys: Array(keys)) {
            for case let url as URL in items {
                if url.lastPathComponent.hasPrefix(".") { items.skipDescendants(); continue }
                let values = try? url.resourceValues(forKeys: keys)
                guard values?.isRegularFile == true, values?.isSymbolicLink != true, !isLamps(Sharing.relativePath(of: url, in: root)) else { continue }
                if TVFiles.codeExtensions.contains(url.pathExtension.lowercased()) { code.append(url) } else { data.append(url) }
            }
        }
        let swift = root.appendingPathComponent(native)
        if let values = try? swift.resourceValues(forKeys: keys), values.isRegularFile == true, values.isSymbolicLink != true { code.append(swift) }
        return (code, data)
    }

    /// Puts a shared game's page in place of the game's, and its Native.swift when the file has one, then Lamp's own
    /// files around them, which make the folder a three.js game.
    static func install(_ package: Sharing.Package, into project: LampProject) throws {
        let fm = FileManager.default
        // The file's page and Native.swift take the place of the game's; a file without a Native.swift leaves the game
        // with Lamp's own, written again by `GameKit.write`, not the one it had.
        try? fm.removeItem(at: project.dir.appendingPathComponent(GameKit.webFolder))
        try? fm.removeItem(at: project.dir.appendingPathComponent(native))
        for file in package.sources + package.webData {
            let relative = package.path(of: file)
            guard !relative.contains(".."), relative == native || relative.hasPrefix(GameKit.webFolder + "/"), !isLamps(relative) else { continue }
            let target = project.dir.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? fm.removeItem(at: target)
            try fm.copyItem(at: file, to: target)
        }
        try GameKit.write(for: project)
    }
}
