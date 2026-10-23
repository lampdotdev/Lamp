import AppKit
import CryptoKit
import Foundation

/// The person's TVs: Samsung's (Tizen) and LG's (webOS), found on the network, set up through their own developer
/// modes, and given a web app Lamp packages, signs and installs itself. A TV app is the same HTML, CSS and JavaScript
/// on both (`TVTemplate`); what differs is the package and the bridge: a signed `.wgt` over sdb for Samsung
/// (`SdbConnection`, `TizenSigning`), an `.ipk` over SSH with LG's developer key for LG. The agent never reaches a TV:
/// it tries the app in the TV preview on this Mac (`TVPreview`), and Play puts it on the TV chosen under Try On.
enum TVs {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// A TV as found on the network and, once one of its setup steps has worked, kept (found is not owned: a
    /// neighbour's TV may answer a scan, and only hands on the TV's own remote prove it's the person's).
    struct Record: Codable, Hashable {
        var id: String            // "samsung:<udn>", "lg:<udn>"
        var maker: String         // "Samsung", "LG"
        var name: String          // the TV's own name for itself
        var model: String         // "The Frame 50", or the model code when nothing better is known
        var modelID: String       // "QN50LS03BAFXZA"
        var address: String
        var os: String            // "Tizen", "webOS"
        var osVersion: String
        var resolution: String    // "3840x2160"
        var frame = false
        var duid: String?
        var developerIP: String?
        var developerMode = false
        /// Every id the TV answered for, one per service (an LG TV has several); a TV kept under any of them is this one.
        var udns: [String]? = nil
        var isSamsung: Bool { maker == "Samsung" }
    }

    static let folder = Edition.supportFolder.appendingPathComponent("TV")
    private static var keptURL: URL { folder.appendingPathComponent("devices.json") }

    static func kept() -> [Record] {
        (try? Data(contentsOf: keptURL)).flatMap { try? JSONDecoder().decode([Record].self, from: $0) } ?? []
    }

    static func keep(_ record: Record) {
        var all = kept().filter { $0.id != record.id }
        all.append(record)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try? JSONEncoder().encode(all).write(to: keptURL, options: .atomic)
    }

    /// Forgets a TV, as the person asks in Settings: found again, it's set up from the start. An LG TV's key goes with
    /// it, since its setup counts as done while the key is here. Samsung's certificates for it stay: they name the TV's
    /// own id, and are as good when it's set up again.
    static func forget(_ id: String) {
        if let address = kept().first(where: { $0.id == id })?.address { WebOS.forgetHost(address) }
        let all = kept().filter { $0.id != id }
        try? JSONEncoder().encode(all).write(to: keptURL, options: .atomic)
        try? FileManager.default.removeItem(at: WebOS.keyURL(id))
    }

    /// Reconnect: the TV's connection is made again from its setup window, for one reset or whose developer mode was
    /// turned on again. An LG TV's key is let go, so the window asks for the passphrase its Developer Mode app shows
    /// now; a Samsung TV's id is read again over a new connection, and its certificates still fit when it's the same.
    static func reconnect(_ id: String) {
        try? FileManager.default.removeItem(at: WebOS.keyURL(id))
        guard var record = kept().first(where: { $0.id == id }) else { return }
        guard record.isSamsung else { WebOS.forgetHost(record.address); return }
        record.duid = nil
        keep(record)
    }

    static func record(_ id: String) -> Record? { kept().first { $0.id == id } ?? lastFound.first { $0.id == id } }
    nonisolated(unsafe) private(set) static var lastFound: [Record] = []

    // MARK: Finding them

    /// The TVs on this network now, and the kept ones that aren't, as device records. A Samsung TV answers on its own
    /// local API; an LG TV describes itself in its UPnP description.
    static func devices() async -> [Device] {
        let found = await scan()
        lastFound = found
        var records = found
        // A kept TV takes what was found now (its address may have moved); one not found keeps what was known.
        for var keptOne in kept() {
            if let now = found.first(where: { $0.id == keptOne.id }) {
                keptOne.address = now.address
                keptOne.developerMode = now.developerMode
                keptOne.developerIP = now.developerIP
                if let udns = now.udns { keptOne.udns = Array(Set(keptOne.udns ?? []).union(udns)).sorted() }
                if keptOne.osVersion.isEmpty { keptOne.osVersion = now.osVersion }
                keep(keptOne)
                records.removeAll { $0.id == keptOne.id }
                records.append(keptOne)
            } else {
                records.append(keptOne)
            }
        }
        let here = Set(found.map(\.id)), keptIDs = Set(kept().map(\.id))
        return records.map { Device.from(tv: $0, onNetwork: here.contains($0.id), kept: keptIDs.contains($0.id)) }
            .sorted { $0.name < $1.name }
    }

    /// One SSDP search of the local network (two seconds), then each device that answered as a TV asked who it is.
    static func scan() async -> [Record] {
        var byAddress: [String: [DeviceProbe.SSDPAnswer]] = [:]
        for answer in await DeviceProbe.ssdp("ssdp:all", seconds: 2) { byAddress[answer.address, default: []].append(answer) }
        let earlier = kept() + lastFound
        var records: [Record] = []
        await withTaskGroup(of: Record?.self) { group in
            for (ip, answers) in byAddress {
                let said = answers.map { "\($0.server)\n\($0.location ?? "")\n\($0.searchTarget)" }.joined(separator: "\n").lowercased()
                if said.contains("samsung") {
                    group.addTask { await samsung(at: ip) }
                } else if said.contains("webos") || said.contains("lge") {
                    group.addTask { await lg(at: ip, answers: answers, earlier: earlier) }
                }
            }
            for await record in group { if let record, !records.contains(where: { $0.id == record.id }) { records.append(record) } }
        }
        return records
    }

    private static func fetch(_ url: URL, timeout: TimeInterval = 3) async -> Data? {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              (response as? HTTPURLResponse)?.statusCode == 200 else { return nil }
        return data
    }

    /// A Samsung TV's own description of itself, from its local API.
    static func samsung(at ip: String) async -> Record? {
        guard let data = await fetch(URL(string: "http://\(ip):8001/api/v2/")!),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let device = json["device"] as? [String: Any], (device["OS"] as? String) == "Tizen" else { return nil }
        let modelID = device["modelName"] as? String ?? ""
        let frame = (device["FrameTVSupport"] as? String) == "true"
        // The size is in the model code (QN50…, UN65…).
        let size = modelID.dropFirst(2).prefix(2).allSatisfy(\.isNumber) ? String(modelID.dropFirst(2).prefix(2)) : ""
        let model = frame ? "The Frame" + (size.isEmpty ? "" : " \(size)") : (size.isEmpty ? modelID : "Smart TV \(size)")
        // The year is the first part of its internal model ("22_PONTUSM_FTV"), and each year has one Tizen.
        let year = Int((device["model"] as? String ?? "").prefix(2)) ?? 0
        let tizen = [17: "3.0", 18: "4.0", 19: "5.0", 20: "5.5", 21: "6.0", 22: "6.5", 23: "7.0", 24: "8.0", 25: "9.0", 26: "10.0"][year] ?? ""
        let id = (device["id"] as? String ?? device["duid"] as? String ?? ip).replacingOccurrences(of: "uuid:", with: "")
        return Record(id: "samsung:\(id)", maker: "Samsung", name: device["name"] as? String ?? "Samsung TV", model: model, modelID: modelID,
                      address: ip, os: "Tizen", osVersion: tizen, resolution: device["resolution"] as? String ?? "", frame: frame,
                      duid: nil, developerIP: device["developerIP"] as? String, developerMode: (device["developerMode"] as? String) == "1")
    }

    /// The service an LG TV announces for itself; the description it points at is the TV's own.
    static let lgTV = "urn:lge:device:tv:1"

    /// An LG TV, from the UPnP descriptions its answers point at. It answers for several services, each with a
    /// description and an id of its own, and the first to answer is often one that says nothing of the TV (Netflix's,
    /// a few bytes of "status=ok"), so each is tried until one is an LG TV's: the TV's own service first, which gives
    /// it the same id at every scan. A TV already kept or seen under another of its services' ids (an earlier Lamp
    /// kept whichever answered first, and the TV's own may miss a scan) keeps that id, so its setup, its key and the
    /// apps set to open on it still match: it's the same TV when any id it answers for now is one it had then.
    /// `fetch` is how a description is read; tests answer with recorded ones.
    static func lg(at ip: String, answers: [DeviceProbe.SSDPAnswer], earlier: [Record] = [],
                   fetch: (URL) async -> Data? = { await fetch($0) }) async -> Record? {
        let own = Set(answers.filter { $0.searchTarget.lowercased() == lgTV }.compactMap(\.location))
        var locations: [String] = []
        for location in answers.compactMap(\.location).filter(own.contains) + answers.compactMap(\.location)
            where !locations.contains(location) && URL(string: location)?.host == ip && URL(string: location)?.scheme == "http" {
            locations.append(location)
        }
        // A USN is "uuid:<udn>" or "uuid:<udn>::<type>".
        let udns = Set(answers.compactMap { answer -> String? in
            guard answer.usn.lowercased().hasPrefix("uuid:") else { return nil }
            let udn = answer.usn.dropFirst(5).components(separatedBy: "::")[0]
            return udn.isEmpty ? nil : udn
        })
        for location in locations {
            guard let url = URL(string: location), let data = await fetch(url), var record = lg(at: ip, description: data) else { continue }
            record.udns = Array(udns.union([String(record.id.dropFirst("lg:".count))])).sorted()
            if let seen = earlier.first(where: { tv in
                !tv.isSamsung && !udns.isDisjoint(with: [String(tv.id.dropFirst("lg:".count))] + (tv.udns ?? []))
            }) { record.id = seen.id }
            record.developerMode = FileManager.default.fileExists(atPath: WebOS.keyURL(record.id).path)
            return record
        }
        return nil
    }

    /// An LG TV's UPnP description: its name and model. Its webOS version is read once Lamp can reach it.
    static func lg(at ip: String, description data: Data) -> Record? {
        let text = String(decoding: data, as: UTF8.self)
        func tag(_ name: String) -> String? {
            guard let open = text.range(of: "<\(name)>"), let close = text.range(of: "</\(name)>", range: open.upperBound..<text.endIndex) else { return nil }
            return String(text[open.upperBound..<close.lowerBound]).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard (tag("manufacturer") ?? "").uppercased().hasPrefix("LG") else { return nil }
        let udn = (tag("UDN") ?? ip).replacingOccurrences(of: "uuid:", with: "")
        return Record(id: "lg:\(udn)", maker: "LG", name: tag("friendlyName") ?? "LG TV", model: tag("modelName") ?? "webOS TV",
                      modelID: tag("modelNumber") ?? "", address: ip, os: "webOS", osVersion: "", resolution: "")
    }

    /// This Mac's addresses on the local network, which a Samsung TV in developer mode must name.
    static func macAddresses() -> [String] {
        var result: [String] = []
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0 else { return [] }
        defer { freeifaddrs(interfaces) }
        var next = interfaces
        while let item = next {
            if let address = item.pointee.ifa_addr, address.pointee.sa_family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(address, socklen_t(address.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    let ip = String(cString: host)
                    if !ip.hasPrefix("127.") { result.append(ip) }
                }
            }
            next = item.pointee.ifa_next
        }
        return result
    }

    // MARK: Samsung: connecting, packaging, installing

    /// Connects to a Samsung TV, reads what Lamp needs of it (its device id and Tizen), and keeps it: being reachable
    /// in developer mode with this Mac's address is the proof it's the person's.
    static func connectSamsung(_ record: Record) async throws -> Record {
        try await Task.detached {
            let sdb = try SdbConnection(host: record.address)
            defer { sdb.close() }
            let capability = try sdb.capability()
            let duid = try sdb.shell("0 getduid").trimmingCharacters(in: .whitespacesAndNewlines)
            guard duid.count >= 8, duid.allSatisfy({ $0.isLetter || $0.isNumber }) else { throw Failure(message: "The TV didn't say who it is. Try again.") }
            var updated = record
            updated.duid = duid
            if let version = capability["platform_version"], !version.isEmpty { updated.osVersion = version }
            keep(updated)
            return updated
        }.value
    }

    /// Packages the staged app for the Samsung TV, signs it for that TV, installs it and opens it. `say` hears how far it is.
    static func installSamsung(_ project: LampProject, staged: URL, on record: Record, say: @escaping @Sendable (String) -> Void) async throws {
        var duid = record.duid
        if duid == nil { duid = (try? await connectSamsung(record))?.duid }
        guard let duid else { throw Failure(message: "Lamp hasn't connected to \(record.name) yet.") }
        guard TizenSigning.hasCertificates(for: duid) else {
            throw Failure(message: "\(record.name) needs Samsung's permission for this Mac's apps first: sign in to Samsung in its setup.")
        }
        let ids = TVTemplate.tizenIDs(for: project)
        say("Packaging \(project.name) for \(record.name)…")
        let package = try await TVPackage.wgt(for: project, staged: staged, duid: duid)
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        let data = try Data(contentsOf: package)
        say("Putting \(project.name) on \(record.name)…")
        try await Task.detached {
            let sdb = try SdbConnection(host: record.address)
            defer { sdb.close() }
            let toolPath = (try? sdb.capability())?["sdk_toolpath"] ?? "/home/owner/share/tmp/sdk_tools"
            let remote = "\(toolPath)/\(ids.package).wgt"
            try sdb.push(data, to: remote)
            var output = try sdb.shell("0 vd_appinstall \(ids.package) \(remote)")
            // One signed by another key (an earlier Lamp, another Mac) is taken off first, as Tizen Studio offers to.
            if output.contains("install failed[118") || output.lowercased().contains("signature") {
                _ = try? sdb.shell("0 vd_appuninstall \(ids.package)")
                try sdb.push(data, to: remote)
                output = try sdb.shell("0 vd_appinstall \(ids.package) \(remote)")
            }
            if output.contains("install failed[") || output.lowercased().contains("val[fail]") {
                let reason = output.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
                    .filter { !$0.isEmpty && !$0.hasPrefix("installing") }.suffix(3).joined(separator: " · ")
                throw Failure(message: "\(record.name) didn't install the app: \(reason)")
            }
            say("Opening \(project.name) on \(record.name)…")
            // The install's stream closes before the TV has finished, so it's asked to open the app until it says it has
            // (launched, or resumed when it was open), for half a minute at most.
            var reply = ""
            for _ in 0..<20 {
                reply = try sdb.shell("0 was_execute \(ids.app)")
                let said = reply.lowercased()
                if said.contains("launched") || said.contains("resumed") { return }
                if said.contains("launch failed[400]") || said.contains("denied") { break }
                usleep(1_500_000)
            }
            throw Failure(message: "\(record.name) installed the app but didn't open it: \(reply.trimmingCharacters(in: .whitespacesAndNewlines))")
        }.value
    }

    // MARK: LG

    static func installLG(_ project: LampProject, staged: URL, on record: Record, say: @escaping @Sendable (String) -> Void) async throws {
        guard FileManager.default.fileExists(atPath: WebOS.keyURL(record.id).path) else {
            throw Failure(message: "\(record.name) hasn't let this Mac in yet: enter its Developer Mode passphrase in its setup.")
        }
        say("Packaging \(project.name) for \(record.name)…")
        let package = try await TVPackage.ipk(for: project, staged: staged)
        defer { try? FileManager.default.removeItem(at: package.deletingLastPathComponent()) }
        say("Putting \(project.name) on \(record.name)…")
        try await WebOS.install(package, appID: TVTemplate.webOSID(for: project), on: record)
        say("Opening \(project.name) on \(record.name)…")
        try await WebOS.launch(TVTemplate.webOSID(for: project), on: record)
        await WebOS.extendSession(on: record)
    }

    // MARK: Staging

    /// Where an app's web files are copied before they're shown in the preview or packaged: Lamp's own folder,
    /// which the agent's commands can't write.
    static func stagingFolder(for project: LampProject) -> URL {
        Edition.supportFolder.appendingPathComponent("TV Builds").appendingPathComponent(project.id)
    }

    /// Copies the app's web files into Lamp's folder, as Devices.stage does for a phone: by a command under the app's
    /// own sandbox, so it reads only the app's folder, links kept as links, then none allowed. What the preview shows and
    /// what goes on a TV are only the app's own files. Gives back the copy.
    static func stage(_ project: LampProject) async throws -> URL {
        let fm = FileManager.default
        let dir = stagingFolder(for: project)
        let files = dir.appendingPathComponent("web")
        try? fm.removeItem(at: files)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        let copy = "cd \"$LAMP_FROM\" && /bin/cp -Rp \(Sandbox.quoted(TVTemplate.webFolder)) \"$LAMP_TO\""
        guard let confined = Sandbox.wrapEngine(copy, for: project, opening: [dir.path]) else { throw Failure(message: "Lamp couldn't copy the app's files.") }
        var output: [String] = []
        let status = await Shell.run(confined, cwd: dir, env: ["LAMP_FROM": project.dir.path, "LAMP_TO": files.path], login: false) { output.append($0) }
        guard status == 0 else { throw Failure(message: "Lamp couldn't copy the app's files.\n\n" + output.suffix(4).joined(separator: "\n")) }
        let linked = (fm.enumerator(at: files, includingPropertiesForKeys: [.isSymbolicLinkKey])?.allObjects as? [URL] ?? [])
            .contains { (try? $0.resourceValues(forKeys: [.isSymbolicLinkKey]))?.isSymbolicLink == true }
        if linked {
            try? fm.removeItem(at: files)
            throw Failure(message: "Some of the app's files are shortcuts to other files. Put the files themselves in their place.")
        }
        guard fm.fileExists(atPath: files.appendingPathComponent("index.html").path) else {
            throw Failure(message: "The app has no \(TVTemplate.webFolder)/index.html yet.")
        }
        return files
    }
}

// MARK: - Packages

enum TVPackage {
    /// Every file of a staged app, as paths inside the package and their bytes. Names a TV takes: letters, digits,
    /// dots, dashes and underscores, in folders.
    static func files(in staged: URL) throws -> [(path: String, data: Data)] {
        let fm = FileManager.default
        var files: [(String, Data)] = []
        let base = staged.standardizedFileURL.path
        guard let walk = fm.enumerator(at: staged, includingPropertiesForKeys: [.isRegularFileKey]) else { return [] }
        for case let url as URL in walk where (try? url.resourceValues(forKeys: [.isRegularFileKey]))?.isRegularFile == true {
            let path = String(url.standardizedFileURL.path.dropFirst(base.count + 1))
            if path.hasPrefix(".") || path.contains("/.") { continue }
            guard path.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-/".contains($0)) }) else {
                throw TVs.Failure(message: "A TV can't take a file named \"\(path)\": use letters, digits, dots, dashes and underscores only.")
            }
            files.append((path, try Data(contentsOf: url)))
        }
        return files.sorted { $0.0 < $1.0 }
    }

    /// The app's icon at `size`, from the one Lamp drew for it, else none.
    static func icon(for project: LampProject, size: Int, in folder: URL) async -> Data? {
        guard let png = AppFile.read(project.dir.appendingPathComponent(".lamp/AppIcon-square.png"), in: project) else { return nil }
        let file = folder.appendingPathComponent("icon-source-\(size).png")
        try? png.write(to: file)
        defer { try? FileManager.default.removeItem(at: file) }
        let out = folder.appendingPathComponent("icon-\(size).png")
        guard await Subprocess.run("/usr/bin/sips", ["-z", "\(size)", "\(size)", file.path, "--out", out.path], timeout: 30).ok else { return nil }
        defer { try? FileManager.default.removeItem(at: out) }
        return try? Data(contentsOf: out)
    }

    /// A signed Samsung package (`.wgt`): the app's files, Lamp's config and icon, and the two signatures.
    static func wgt(for project: LampProject, staged: URL, duid: String) async throws -> URL {
        let work = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-wgt-\(UUID().uuidString)")
        let tree = work.appendingPathComponent("package")
        try FileManager.default.createDirectory(at: tree, withIntermediateDirectories: true)
        var files = try DeviceSupport.fill(self.files(in: staged), for: project).filter { $0.path != "config.xml" && !$0.path.hasSuffix("signature.xml") && $0.path != "signature1.xml" }
        files.append(("config.xml", Data(TVTemplate.tizenConfig(for: project).utf8)))
        if let icon = await icon(for: project, size: 512, in: work) { files.removeAll { $0.path == "icon.png" }; files.append(("icon.png", icon)) }
        files.sort { $0.path < $1.path }
        let signatures = try TizenSigning.signatures(for: files, duid: duid)
        for (path, data) in signatures + files {
            let url = tree.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
        }
        let out = work.appendingPathComponent("app.wgt")
        // The signatures first, as Tizen's own packager writes them.
        let zip = await Subprocess.run("/usr/bin/zip", ["-X", "-D", "-q", out.path] + (signatures + files).map(\.path), cwd: tree, timeout: 120)
        guard zip.ok else { throw TVs.Failure(message: "Lamp couldn't package the app.") }
        return out
    }

    /// An LG package (`.ipk`): an ar archive of the package's version, its control file and its data, as LG's packager makes it.
    static func ipk(for project: LampProject, staged: URL) async throws -> URL {
        let fm = FileManager.default
        let id = TVTemplate.webOSID(for: project)
        let work = fm.temporaryDirectory.appendingPathComponent("lamp-ipk-\(UUID().uuidString)")
        let app = work.appendingPathComponent("data/usr/palm/applications/\(id)")
        let info = work.appendingPathComponent("data/usr/palm/packages/\(id)")
        try fm.createDirectory(at: app, withIntermediateDirectories: true)
        try fm.createDirectory(at: info, withIntermediateDirectories: true)
        try fm.createDirectory(at: work.appendingPathComponent("control"), withIntermediateDirectories: true)
        var size = 0
        for (path, data) in DeviceSupport.fill(try files(in: staged), for: project) where path != "appinfo.json" {
            let url = app.appendingPathComponent(path)
            try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url)
            size += data.count
        }
        try Data(TVTemplate.webOSAppInfo(for: project).utf8).write(to: app.appendingPathComponent("appinfo.json"))
        if let icon = await icon(for: project, size: 80, in: work) { try icon.write(to: app.appendingPathComponent("icon.png")) }
        if let large = await icon(for: project, size: 130, in: work) { try large.write(to: app.appendingPathComponent("largeIcon.png")) }
        let packageInfo = ["app": id, "id": id, "loc_name": project.name, "package_format_version": 2, "vendor": "Lamp", "version": "1.0.0"] as [String: Any]
        try JSONSerialization.data(withJSONObject: packageInfo, options: [.sortedKeys]).write(to: info.appendingPathComponent("packageinfo.json"))
        let control = """
            Package: \(id)
            Version: 1.0.0
            Section: misc
            Priority: optional
            Architecture: all
            Installed-Size: \(max(1, size / 1024))
            Maintainer: Lamp
            Description: \(project.name)
            webOS-Package-Format-Version: 2
            webOS-Packager-Version: x.y.x

            """
        try Data(control.utf8).write(to: work.appendingPathComponent("control/control"))
        // No resource forks or Mac metadata in what goes on the TV, and files owned by nobody in particular.
        let env = ["COPYFILE_DISABLE": "1"]
        for (archive, folder, root) in [("control.tar.gz", "control", "./control"), ("data.tar.gz", "data", "./usr")] {
            let tar = await Subprocess.run("/usr/bin/tar", ["--uid", "0", "--gid", "0", "--format", "ustar", "-czf",
                                                            work.appendingPathComponent(archive).path, "-C", work.appendingPathComponent(folder).path, root],
                                           env: env, timeout: 120)
            guard tar.ok else { throw TVs.Failure(message: "Lamp couldn't package the app: \(tar.output)") }
        }
        var ar = Data("!<arch>\n".utf8)
        for (name, data) in [("debian-binary", Data("2.0\n".utf8)),
                             ("control.tar.gz", try Data(contentsOf: work.appendingPathComponent("control.tar.gz"))),
                             ("data.tar.gz", try Data(contentsOf: work.appendingPathComponent("data.tar.gz")))] {
            func field(_ s: String, _ width: Int) -> String { s.padding(toLength: width, withPad: " ", startingAt: 0) }
            let header = field(name + "/", 16) + field(String(Int(Date().timeIntervalSince1970)), 12) + field("0", 6) + field("0", 6)
                + field("100644", 8) + field(String(data.count), 10) + "`\n"
            ar.append(Data(header.utf8))
            ar.append(data)
            if data.count % 2 == 1 { ar.append(0x0A) }
        }
        let out = work.appendingPathComponent("\(id)_1.0.0_all.ipk")
        try ar.write(to: out)
        return out
    }
}

// MARK: - LG

/// LG's developer mode, reached the way LG's own tools do: the TV hands out a key (on its key server, port 9991, while
/// Developer Mode's Key Server is on) locked with a passphrase it shows; with it, SSH as `prisoner` on port 9922 takes
/// packages to /media/developer/temp and the TV's app service installs and opens them. The session it's in lapses
/// after about 50 hours unless renewed, which every install does.
enum WebOS {
    static func keyURL(_ id: String) -> URL {
        TVs.folder.appendingPathComponent("LG").appendingPathComponent(id.replacingOccurrences(of: ":", with: "-") + ".key")
    }
    private static var knownHosts: URL { TVs.folder.appendingPathComponent("LG/known_hosts") }

    /// Lets go of the host key kept for a TV's address, for Reconnect and Forget: a reset TV answers SSH with a new one.
    static func forgetHost(_ address: String) {
        guard !address.isEmpty, let text = try? String(contentsOf: knownHosts, encoding: .utf8) else { return }
        let kept = text.split(separator: "\n", omittingEmptySubsequences: false).filter { line in
            let hosts = line.split(separator: " ").first.map { $0.split(separator: ",") } ?? []
            return !hosts.contains { $0 == Substring(address) || $0 == Substring("[\(address)]:9922") }
        }
        try? kept.joined(separator: "\n").write(to: knownHosts, atomically: true, encoding: .utf8)
    }

    /// Fetches the TV's key and unlocks it with the passphrase the TV shows; keeps the TV once SSH answers with it.
    static func connect(_ record: TVs.Record, passphrase: String) async throws -> TVs.Record {
        let fm = FileManager.default
        let key = keyURL(record.id)
        try fm.createDirectory(at: key.deletingLastPathComponent(), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        var request = URLRequest(url: URL(string: "http://\(record.address):9991/webos_rsa")!, timeoutInterval: 8)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        guard let (data, response) = try? await URLSession.shared.data(for: request), (response as? HTTPURLResponse)?.statusCode == 200,
              String(decoding: data, as: UTF8.self).contains("PRIVATE KEY") else {
            throw TVs.Failure(message: "\(record.name) didn't hand out its key. In the Developer Mode app on the TV, turn Key Server on, then try again.")
        }
        // The key is tried before it's kept: one that doesn't let Lamp in mustn't stand for a TV that's set up.
        let staged = key.deletingLastPathComponent().appendingPathComponent(".staging-\(UUID().uuidString).key")
        defer { try? fm.removeItem(at: staged) }
        try data.write(to: staged, options: .atomic)
        try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: staged.path)
        let unlock = await Subprocess.run("/usr/bin/ssh-keygen", ["-p", "-P", passphrase, "-N", "", "-f", staged.path], timeout: 30)
        guard unlock.ok else {
            throw TVs.Failure(message: "That passphrase didn't open the TV's key. It's the six letters and digits the Developer Mode app shows.")
        }
        var updated = record
        let version = try await ssh(record, "cat /var/run/nyx/os_info.json 2>/dev/null || echo '{}'", key: staged)
        if fm.fileExists(atPath: key.path) { try fm.removeItem(at: key) }
        try fm.moveItem(at: staged, to: key)
        if let json = try? JSONSerialization.jsonObject(with: Data(version.utf8)) as? [String: Any] {
            updated.osVersion = (json["webos_release"] as? String) ?? (json["core_os_release"] as? String) ?? ""
        }
        updated.developerMode = true
        TVs.keep(updated)
        return updated
    }

    private static func sshOptions(_ record: TVs.Record, key: URL? = nil) -> [String] {
        ["-i", (key ?? keyURL(record.id)).path, "-p", "9922", "-o", "IdentitiesOnly=yes", "-o", "BatchMode=yes", "-o", "ConnectTimeout=10",
         "-o", "UserKnownHostsFile=\(knownHosts.path)", "-o", "StrictHostKeyChecking=accept-new",
         "-o", "HostKeyAlgorithms=+ssh-rsa", "-o", "PubkeyAcceptedAlgorithms=+ssh-rsa"]
    }

    @discardableResult
    static func ssh(_ record: TVs.Record, _ command: String, key: URL? = nil, timeout: TimeInterval = 60) async throws -> String {
        let result = await Subprocess.run("/usr/bin/ssh", sshOptions(record, key: key) + ["prisoner@\(record.address)", command], mergeErrors: false, timeout: timeout)
        guard result.ok else { throw unanswered(record, result) }
        return result.output
    }

    private static func unanswered(_ record: TVs.Record, _ result: Subprocess.Result) -> TVs.Failure {
        TVs.Failure(message: "\(record.name) didn't answer: \(result.errors.trimmed.isEmpty ? "it may have left developer mode" : result.errors.trimmed)")
    }

    static func install(_ package: URL, appID: String, on record: TVs.Record) async throws {
        let remote = "/media/developer/temp/\(package.lastPathComponent)"
        try await put(package, to: remote, on: record)
        let payload = "{\"id\":\"\(appID)\",\"ipkUrl\":\"\(remote)\",\"subscribe\":true}"
        let reply: String
        do {
            reply = try await luna(record, "luna://com.webos.appInstallService/dev/install", payload,
                                   until: #""state":"installed"|failed|"returnValue":false"#)
        } catch {
            try? await ssh(record, "/bin/rm -f '\(remote)'")
            throw error
        }
        try? await ssh(record, "/bin/rm -f '\(remote)'")
        guard reply.contains(#""state":"installed""#) else {
            throw TVs.Failure(message: "\(record.name) didn't install the app\(said(reply))")
        }
    }

    /// Calls a service on the TV and gives back its replies up to the first that `until` (a pattern) matches.
    /// `luna-send-pub` gives up as soon as its input closes, before any reply, so its input is kept open until that
    /// reply comes, as LG's own tools keep it, and `-w` ends a call nothing answers. The service and payload are
    /// Lamp's own, with no single quotes in them.
    static func luna(_ record: TVs.Record, _ uri: String, _ payload: String, until: String, seconds: Int = 120) async throws -> String {
        func answered(_ line: Substring) -> Bool { line.range(of: until, options: [.regularExpression, .caseInsensitive]) != nil }
        let result = await Subprocess.run("/usr/bin/ssh", sshOptions(record) + ["prisoner@\(record.address)",
                                          "luna-send-pub -w \(seconds * 1000) -i \(uri) '\(payload)'"],
                                          mergeErrors: false, timeout: TimeInterval(seconds + 30),
                                          keepInputOpenUntil: { $0.split(separator: "\n").contains(where: answered) })
        guard result.ok else { throw unanswered(record, result) }
        let lines = result.output.split(separator: "\n")
        return (lines.firstIndex(where: answered).map { lines[...$0] } ?? lines[...]).joined(separator: "\n")
    }

    /// The TV's reason in a reply, for the person: what it says went wrong, else nothing.
    private static func said(_ reply: String) -> String {
        guard let line = reply.split(separator: "\n").last,
              let json = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any] else { return "." }
        let details = json["details"] as? [String: Any]
        let reason = (details?["reason"] as? String) ?? (json["errorText"] as? String) ?? (details?["state"] as? String) ?? ""
        return reason.isEmpty ? "." : ": \(reason)"
    }

    /// Copies a file to the TV the way LG's own installer (ares-install) does: into the developer folder over SFTP, which
    /// the TV's SSH server has built in, and on a TV whose server offers none, streamed into `cat` over SSH. The
    /// developer-mode shell has no `scp` program, so scp's old protocol (`-O`), which runs one on the TV, can't work.
    /// The name is the package's own (letters, digits, dots, dashes and underscores), so it needs no quoting beyond this.
    static func put(_ file: URL, to remote: String, on record: TVs.Record) async throws {
        try await ssh(record, "/bin/mkdir -p '\((remote as NSString).deletingLastPathComponent)'")
        let host = "prisoner@\(record.address)"
        let batch = "put \"\(file.path)\" \"\(remote)\"\n"
        let sftp = await Subprocess.run("/usr/bin/sftp", ["-b", "-"] + sshOptions(record).map { $0 == "-p" ? "-P" : $0 } + [host],
                                        timeout: 300, input: Data(batch.utf8))
        if sftp.ok { return }
        let stream = await Subprocess.run("/usr/bin/ssh", sshOptions(record) + [host, "/bin/cat > '\(remote)'"], mergeErrors: false,
                                          timeout: 300, input: try Data(contentsOf: file))
        guard stream.ok else {
            throw TVs.Failure(message: "Lamp couldn't copy the app to \(record.name): \((stream.errors.trimmed.isEmpty ? sftp.output : stream.errors).trimmed)")
        }
    }

    static func launch(_ appID: String, on record: TVs.Record) async throws {
        let reply = try await luna(record, "luna://com.webos.applicationManager/launch", "{\"id\":\"\(appID)\"}", until: "returnValue", seconds: 30)
        guard reply.contains(#""returnValue":true"#) else {
            throw TVs.Failure(message: "\(record.name) installed the app but didn't open it\(said(reply))")
        }
    }

    /// Developer mode lapses after about 50 hours; asking LG to reset its clock with the TV's own session token keeps it.
    static func extendSession(on record: TVs.Record) async {
        guard let token = try? await ssh(record, "cat /var/luna/preferences/devmode_enabled").trimmed,
              token.allSatisfy({ $0.isLetter || $0.isNumber }), !token.isEmpty,
              let url = URL(string: "https://developer.lge.com/secure/ResetDevModeSession.dev?sessionToken=\(token)") else { return }
        _ = try? await URLSession.shared.data(from: url)
    }
}

// MARK: - Device records

extension Device {
    /// A TV as a device record. Its setup state is worked out here from what's kept: developer mode pointed at this Mac
    /// and Samsung's certificate for a Samsung TV, the key for an LG TV.
    static func from(tv record: TVs.Record, onNetwork: Bool, kept: Bool) -> Device {
        let kind: Kind = record.isSamsung ? .samsungTV : .lgTV
        var screens: [Screen] = []
        let parts = record.resolution.split(separator: "x").compactMap { Int($0) }
        if parts.count == 2 { screens = [Screen(name: "TV", width: parts[0], height: parts[1], scale: max(1, parts[0] / 1920))] }
        var device = Device(id: record.id, kind: kind, maker: record.maker, model: record.model, modelID: record.modelID, name: record.name,
                            os: record.os, osVersion: record.osVersion, screens: screens, input: ["remote with a d-pad"],
                            features: record.frame ? ["Art Mode"] : [], reach: .network)
        device.connected = onNetwork
        device.paired = kept
        device.developerMode = record.isSamsung
            ? record.developerMode && TVs.macAddresses().contains(record.developerIP ?? "")
            : FileManager.default.fileExists(atPath: WebOS.keyURL(record.id).path)
        device.address = record.address
        device.duid = record.duid
        return device
    }
}
