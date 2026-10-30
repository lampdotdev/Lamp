import Foundation

/// An Android app in a shared file. Its code is app/ (Kotlin, the manifest, resources, its build file), as the agent
/// keeps it; Lamp's own Gradle files beside it (build.sh, the settings, the root build file, gradle.properties, the
/// versions catalogue) never travel, and the Mac that opens the file writes its own (`Template.writeAndroidOwnedFiles`).
/// The app's build file does run when the app is built, as it does for the person who made it: inside the app's
/// sandbox, with only the libraries the settings Lamp writes let Gradle fetch, after the review has shown what it adds.
enum AndroidFiles {
    /// Files read as code: what the review is shown and what must be plain text.
    static let codeExtensions: Set<String> = ["kt", "kts", "java", "xml", "pro", "gradle"]

    /// What goes in a shared file from an app's folder (or comes out of an unpacked one): the code under app/, and
    /// its pictures and files in res/ and assets/ folders as data. Never what a build or this Mac left there
    /// (app/build, a hidden folder such as .gradle or .lamp, local.properties, which names this Mac's tools),
    /// never a link, and never anything else (a library someone dropped in libs/ would be code nobody could read).
    static func list(in root: URL) -> (code: [URL], data: [URL]) {
        let app = root.appendingPathComponent(Template.androidAppFolder)
        let keys: Set<URLResourceKey> = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let items = FileManager.default.enumerator(at: app, includingPropertiesForKeys: Array(keys)) else { return ([], []) }
        var code: [URL] = [], data: [URL] = []
        for case let url as URL in items {
            let relative = Sharing.relativePath(of: url, in: root)
            let name = url.lastPathComponent
            if name.hasPrefix(".") || relative == Template.androidAppFolder + "/build" || name == "local.properties" {
                items.skipDescendants()
                continue
            }
            let values = try? url.resourceValues(forKeys: keys)
            guard values?.isRegularFile == true, values?.isSymbolicLink != true else { continue }
            if codeExtensions.contains(url.pathExtension.lowercased()) {
                code.append(url)
            } else if isData(relative) {
                data.append(url)
            }
        }
        return (code, data)
    }

    /// app/src/<source set>/res/… or app/src/<source set>/assets/…
    private static func isData(_ relative: String) -> Bool {
        let parts = relative.split(separator: "/")
        return parts.count > 4 && parts[0] == Template.androidAppFolder && parts[1] == "src" && (parts[3] == "res" || parts[3] == "assets")
    }

    /// Puts a shared Android app's app/ in place of the one the app has, and Lamp's own Gradle files beside it.
    /// The code is renamed to this Mac's package for the app (`Template.androidPackage`): Lamp installs, opens and
    /// stops the app by that name, which differs from the sender's whenever the folder or the Lamp does.
    static func install(_ package: Sharing.Package, into project: LampProject) throws {
        let fm = FileManager.default
        let app = project.dir.appendingPathComponent(Template.androidAppFolder)
        try? fm.removeItem(at: app)
        let theirs = senderPackage(in: package)
        let ours = Template.androidPackage(for: project)
        for file in package.sources + package.androidData {
            var relative = package.path(of: file)
            guard !relative.contains(".."), relative.hasPrefix(Template.androidAppFolder + "/") else { continue }
            let isCode = package.sources.contains(file)
            if let theirs, isCode { relative = movedPath(relative, from: theirs, to: ours) }
            let target = project.dir.appendingPathComponent(relative)
            try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            if isCode, let text = try? String(contentsOf: file, encoding: .utf8) {
                var renamed = theirs.map { renamePackage(in: text, from: $0, to: ours) } ?? text
                if relative == Template.androidAppFolder + "/build.gradle.kts" { renamed = settingApplicationID(in: renamed, to: ours) }
                try renamed.write(to: target, atomically: true, encoding: .utf8)
            } else {
                try fm.copyItem(at: file, to: target)
            }
        }
        try Template.writeAndroidOwnedFiles(for: project)
    }

    /// The package the sender's code is written in: its build file's namespace, when that's a package name.
    static func senderPackage(in package: Sharing.Package) -> String? {
        guard let build = package.sources.first(where: { package.path(of: $0) == Template.androidAppFolder + "/build.gradle.kts" }),
              let text = try? String(contentsOf: build, encoding: .utf8),
              let match = text.firstMatch(of: #/namespace\s*=\s*"([A-Za-z_][A-Za-z0-9_]*(?:\.[A-Za-z_][A-Za-z0-9_]*)+)"/#) else { return nil }
        return String(match.1)
    }

    /// The package name wherever it stands as one (`package a.b`, `import a.b.R`, `"a.b"`), not inside a longer name.
    static func renamePackage(in text: String, from old: String, to new: String) -> String {
        guard old != new else { return text }
        let escaped = NSRegularExpression.escapedPattern(for: old)
        guard let pattern = try? NSRegularExpression(pattern: "(?<![A-Za-z0-9_.])\(escaped)(?![A-Za-z0-9_])") else { return text }
        return pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text),
                                                withTemplate: NSRegularExpression.escapedTemplate(for: new))
    }

    /// Kotlin and Java sit in folders named after their package: app/src/main/kotlin/a/b/X.kt.
    static func movedPath(_ relative: String, from old: String, to new: String) -> String {
        let oldPath = old.replacingOccurrences(of: ".", with: "/"), newPath = new.replacingOccurrences(of: ".", with: "/")
        for root in ["/kotlin/", "/java/"] where relative.contains(root + oldPath + "/") {
            return relative.replacingOccurrences(of: root + oldPath + "/", with: root + newPath + "/")
        }
        return relative
    }

    /// The id Android installs the app under is this Mac's for the app, whatever the sender's said and however
    /// they said it. Set by a block of its own at the end of the file, which Gradle runs after the sender's, so
    /// nothing of theirs is rewritten (a one-line `defaultConfig { … }` keeps its other settings and its braces).
    static func settingApplicationID(in text: String, to id: String) -> String {
        text + (text.hasSuffix("\n") ? "" : "\n")
            + "\n// Set by Lamp when the app was opened from a shared file: the id Lamp installs and opens it by.\n"
            + "android { defaultConfig { applicationId = \"\(id)\" } }\n"
    }

    // MARK: - The review

    /// Where an Android app's code reaches beyond itself, in the words the review uses for a Mac app's: what its
    /// manifests ask Android for, what its Kotlin and Java do that the build file and manifest can't show, and the
    /// libraries its build files bring in beyond the ones Lamp's catalog offers.
    static func detected(in package: Sharing.Package) -> [Sharing.Capability] {
        var manifests: [String] = [], kotlin = "", gradle = ""
        for file in package.sources {
            guard let text = try? String(contentsOf: file, encoding: .utf8) else { continue }
            switch file.pathExtension.lowercased() {
            case "kt", "java": kotlin += text + "\n"
            case "kts", "gradle": gradle += text + "\n"
            case "xml" where file.lastPathComponent == "AndroidManifest.xml": manifests.append(text)
            default: break
            }
        }
        var found: [Sharing.Capability] = []
        func add(_ item: Sharing.Capability) { if !found.contains(where: { $0.label == item.label }) { found.append(item) } }
        for permission in permissions(in: manifests) { add(capability(for: permission)) }
        // The build files run on this Mac while the app builds, so they're held to the same checks as the app's code.
        for item in kotlinChecks where item.patterns.contains(where: { kotlin.contains($0) || gradle.contains($0) }) { add(item) }
        let outside = libraries(in: gradle)
        if !outside.isEmpty {
            let named = outside.prefix(4).joined(separator: ", ") + (outside.count > 4 ? " and \(outside.count - 4) more" : "")
            add(Sharing.Capability(label: "Builds in code from outside Lamp (\(named))", icon: "shippingbox", level: .powerful, patterns: []))
        }
        return found
    }

    /// The permissions the manifests ask for, by their short name ("CAMERA"), in the order they're written. Read as
    /// XML, so any quoting and any prefix bound to Android's namespace count, and nothing outside the file is fetched.
    static func permissions(in manifests: [String]) -> [String] {
        var names: [String] = []
        for manifest in manifests {
            let reader = PermissionReader()
            let parser = XMLParser(data: Data(manifest.utf8))
            parser.shouldProcessNamespaces = true
            parser.shouldReportNamespacePrefixes = true
            parser.shouldResolveExternalEntities = false
            parser.delegate = reader
            parser.parse()
            for name in reader.names where !names.contains(name) { names.append(name) }
        }
        return names
    }

    private final class PermissionReader: NSObject, XMLParserDelegate {
        static let android = "http://schemas.android.com/apk/res/android"
        var names: [String] = []
        private var prefixes: [String: [String]] = [:]
        func parser(_ parser: XMLParser, didStartMappingPrefix prefix: String, toURI namespaceURI: String) {
            prefixes[prefix, default: []].append(namespaceURI)
        }
        func parser(_ parser: XMLParser, didEndMappingPrefix prefix: String) { _ = prefixes[prefix]?.popLast() }
        func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                    attributes: [String: String] = [:]) {
            guard elementName == "uses-permission" || elementName == "uses-permission-sdk-23" else { return }
            for (key, value) in attributes {
                let parts = key.split(separator: ":", maxSplits: 1).map(String.init)
                guard parts.count == 2, parts[1] == "name", prefixes[parts[0]]?.last == Self.android else { continue }
                names.append(String(value.split(separator: ".").last ?? Substring(value)))
            }
        }
    }

    private static func listed(_ label: String) -> Sharing.Capability {
        Sharing.checklist.first { $0.label == label }!
    }

    /// A permission as the review says it: the Mac's line where there's one for the same access, else plain words
    /// for the access, else its own name in lower case.
    static func capability(for permission: String) -> Sharing.Capability {
        switch permission {
        case "INTERNET": return listed("Connects to the internet")
        case "CAMERA", "RECORD_AUDIO": return listed("Uses the camera or microphone")
        case "READ_CONTACTS", "WRITE_CONTACTS", "READ_CALENDAR", "WRITE_CALENDAR", "GET_ACCOUNTS":
            return listed("Reads your mail, contacts, calendar or reminders")
        case "RECEIVE_BOOT_COMPLETED": return listed("Starts itself automatically or installs background items")
        default: break
        }
        let plain: [String: (String, String, Sharing.Capability.Level)] = [
            "ACCESS_FINE_LOCATION": ("Knows where you are", "location", .powerful),
            "ACCESS_COARSE_LOCATION": ("Knows where you are", "location", .powerful),
            "ACCESS_BACKGROUND_LOCATION": ("Knows where you are, also while it's closed", "location", .sensitive),
            "POST_NOTIFICATIONS": ("Shows notifications", "bell", .ordinary),
            "VIBRATE": ("Vibrates", "iphone.radiowaves.left.and.right", .ordinary),
            "ACCESS_NETWORK_STATE": ("Checks whether you're online", "network", .ordinary),
            "ACCESS_WIFI_STATE": ("Checks whether you're online", "network", .ordinary),
            "WAKE_LOCK": ("Keeps the device awake", "sun.max", .ordinary),
            "FOREGROUND_SERVICE": ("Keeps working while it's out of sight", "gearshape.arrow.triangle.2.circlepath", .powerful),
            "READ_SMS": ("Reads or sends your text messages", "message", .sensitive),
            "RECEIVE_SMS": ("Reads or sends your text messages", "message", .sensitive),
            "SEND_SMS": ("Reads or sends your text messages", "message", .sensitive),
            "READ_CALL_LOG": ("Makes calls or reads your calls", "phone", .sensitive),
            "CALL_PHONE": ("Makes calls or reads your calls", "phone", .sensitive),
            "READ_PHONE_STATE": ("Makes calls or reads your calls", "phone", .sensitive),
            "READ_EXTERNAL_STORAGE": ("Reads your photos, videos or music", "photo", .powerful),
            "READ_MEDIA_IMAGES": ("Reads your photos, videos or music", "photo", .powerful),
            "READ_MEDIA_VIDEO": ("Reads your photos, videos or music", "photo", .powerful),
            "READ_MEDIA_AUDIO": ("Reads your photos, videos or music", "photo", .powerful),
            "WRITE_EXTERNAL_STORAGE": ("Changes your files", "folder", .powerful),
            "MANAGE_EXTERNAL_STORAGE": ("Reads and changes all your files", "folder.badge.questionmark", .sensitive),
            "BLUETOOTH_CONNECT": ("Uses Bluetooth", "dot.radiowaves.left.and.right", .powerful),
            "BLUETOOTH_SCAN": ("Uses Bluetooth", "dot.radiowaves.left.and.right", .powerful),
            "QUERY_ALL_PACKAGES": ("Sees which other apps you have", "square.grid.2x2", .sensitive),
            "REQUEST_INSTALL_PACKAGES": ("Installs other apps", "square.and.arrow.down", .sensitive),
            "SYSTEM_ALERT_WINDOW": ("Draws over other apps", "rectangle.on.rectangle", .sensitive),
            "ACTIVITY_RECOGNITION": ("Reads your activity and body sensors", "figure.walk", .powerful),
            "BODY_SENSORS": ("Reads your activity and body sensors", "figure.walk", .powerful),
        ]
        let key = permission.hasPrefix("FOREGROUND_SERVICE") ? "FOREGROUND_SERVICE" : permission
        if let (label, icon, level) = plain[key] { return Sharing.Capability(label: label, icon: icon, level: level, patterns: []) }
        let words = permission.lowercased().replacingOccurrences(of: "_", with: " ")
        return Sharing.Capability(label: "Asks Android to “\(words)”", icon: "lock.open", level: .powerful, patterns: [])
    }

    /// What Kotlin or Java does that a manifest doesn't declare, in the Mac's lines for the same thing.
    private static let kotlinChecks: [Sharing.Capability] = [
        Sharing.Capability(label: "Runs other programs or shell commands", icon: "terminal", level: .powerful,
                           patterns: ["Runtime.getRuntime().exec", "ProcessBuilder(", "exec {", "exec(", "providers.exec", "commandLine("]),
        Sharing.Capability(label: "Loads code at runtime (can hide what it does)", icon: "eye.slash", level: .sensitive,
                           patterns: ["DexClassLoader", "PathClassLoader", "URLClassLoader", "System.loadLibrary", "System.load(", "Class.forName"]),
    ]

    /// Libraries and build plugins the build files name that Lamp's catalog doesn't offer, by their short name
    /// ("retrofit"). A library from the catalog is named through it (`libs.…`), or spelt out with its group.
    static func libraries(in gradle: String) -> [String] {
        let catalogue = Template.androidVersionsCatalogue
        var known = Set(catalogue.matches(of: #/module\s*=\s*"([^"]+)"/#).map { String($0.1) })
        for match in catalogue.matches(of: #/group\s*=\s*"([^"]+)",\s*name\s*=\s*"([^"]+)"/#) { known.insert("\(match.1):\(match.2)") }
        let plugins = Set(catalogue.matches(of: #/id\s*=\s*"([^"]+)"/#).map { String($0.1) })
        var names: [String] = []
        func add(_ name: String) { if !names.contains(name) { names.append(name) } }
        for match in gradle.matches(of: #/"([A-Za-z0-9_.\-]+):([A-Za-z0-9_.\-]+)(?::[^"]*)?"/#)
        where !known.contains("\(match.1):\(match.2)") {
            add(String(match.2))
        }
        for match in gradle.matches(of: #/\bid\s*\(\s*"([^"]+)"\s*\)/#) where !plugins.contains(String(match.1)) {
            add(String(match.1))
        }
        for match in gradle.matches(of: #/\bkotlin\s*\(\s*"([^"]+)"\s*\)/#) { add("kotlin-" + match.1) }
        if gradle.contains("files(") || gradle.contains("fileTree(") { add("files of its own") }
        return names
    }
}
