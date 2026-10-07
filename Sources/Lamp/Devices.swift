import Foundation

/// The person's own iPhone or iPad: plugged in or on the same Wi‑Fi and paired with this Mac, found and
/// driven with Xcode's devicectl. An app goes on it signed with the person's Apple account, which Xcode
/// holds (Xcode → Settings → Accounts), through a small Xcode project Lamp writes beside the package
/// (Template.deviceProject): Xcode's own automatic signing registers the phone and makes the certificate
/// and profile, so Lamp never handles the account itself. The phone can't be photographed from here, so
/// the agent keeps looking at the simulator; the phone is for the person to try the app on.
enum Devices {
    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    struct Device: Identifiable, Hashable {
        let udid: String
        let name: String
        let model: String          // "iPhone 16 Pro Max"
        let connected: Bool        // a tunnel to it is open now; it's opened on demand, so false says little
        let developerMode: Bool
        var id: String { udid }
        var family: DeviceFamily { model.hasPrefix("iPad") ? .ipad : .iphone }
    }

    /// This Mac's name on the local network ("Matts-MacBook-Pro.local"), which an app on a phone reaches Lamp
    /// at. Bonjour resolves it on the same Wi‑Fi, and it survives the Mac's address changing.
    static var macHost: String {
        let name = Subprocess.runBlocking("/usr/sbin/scutil", ["--get", "LocalHostName"], mergeErrors: false, timeout: 5).output.trimmed
        return (name.isEmpty ? ProcessInfo.processInfo.hostName.replacingOccurrences(of: ".local", with: "") : name) + ".local"
    }

    /// The Apple team the apps are signed for, as Xcode shows it (ten letters and digits).
    static var team: String {
        get { (UserDefaults.standard.string(forKey: "appleTeam") ?? "").trimmed.uppercased() }
        set { UserDefaults.standard.set(newValue.trimmed.uppercased(), forKey: "appleTeam") }
    }

    /// The teams of the accounts signed in to Xcode: the ones its automatic signing can sign for.
    static func xcodeTeams() -> [(id: String, name: String)] {
        let accounts = UserDefaults(suiteName: "com.apple.dt.Xcode")?.dictionary(forKey: "IDEProvisioningTeamByIdentifier") ?? [:]
        var teams: [(id: String, name: String)] = []
        for case let list as [[String: Any]] in accounts.values {
            for team in list {
                guard let id = team["teamID"] as? String, id.count == 10, !teams.contains(where: { $0.id == id }) else { continue }
                teams.append((id, team["teamName"] as? String ?? id))
            }
        }
        return teams.sorted { $0.name < $1.name }
    }

    /// The teams to offer: those signed in to Xcode first, then any the Mac has an Apple Development
    /// certificate for from earlier ("Matt Rubens (Z925397W9T)" → ("Z925397W9T", "Matt Rubens")).
    static func knownTeams() async -> [(id: String, name: String)] {
        let output = await Subprocess.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], timeout: 20).output
        var teams: [(id: String, name: String)] = xcodeTeams()
        for line in output.split(separator: "\n") where line.contains("\"Apple Development: ") {
            guard let open = line.lastIndex(of: "("), let close = line.lastIndex(of: ")"), open < close else { continue }
            let id = String(line[line.index(after: open)..<close])
            let start = line.range(of: "Apple Development: ")!.upperBound
            let name = String(line[start..<open]).trimmed
            if id.count == 10, !teams.contains(where: { $0.id == id }) { teams.append((id, name)) }
        }
        return teams
    }

    /// Paired iPhones and iPads, connected ones first.
    static func list() async -> [Device] {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lamp-devices-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: file) }
        let result = await Subprocess.run("/usr/bin/xcrun", ["devicectl", "list", "devices", "--timeout", "5", "--json-output", file.path],
                                          mergeErrors: false, timeout: 30)
        guard result.ok, let data = try? Data(contentsOf: file),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let devices = (json["result"] as? [String: Any])?["devices"] as? [[String: Any]] else { return [] }
        return devices.compactMap { entry -> Device? in
            let hardware = entry["hardwareProperties"] as? [String: Any] ?? [:]
            let properties = entry["deviceProperties"] as? [String: Any] ?? [:]
            let connection = entry["connectionProperties"] as? [String: Any] ?? [:]
            guard hardware["reality"] as? String == "physical", let udid = hardware["udid"] as? String,
                  ["iPhone", "iPad"].contains(hardware["deviceType"] as? String ?? ""),
                  connection["pairingState"] as? String == "paired" else { return nil }
            return Device(udid: udid, name: properties["name"] as? String ?? "iPhone",
                          model: hardware["marketingName"] as? String ?? (hardware["deviceType"] as? String ?? "iPhone"),
                          connected: connection["tunnelState"] as? String == "connected" || properties["ddiServicesAvailable"] as? Bool == true,
                          developerMode: properties["developerModeStatus"] as? String == "enabled")
        }
        .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    /// Builds the app for the phone with Xcode, signed for the team, and gives back the bundle. Automatic
    /// signing may register the phone and make a certificate and profile, which is slow the first time.
    static func build(_ project: LampProject, team: String, udid: String, started: (@MainActor (Process) -> Void)? = nil,
                      onLine: @escaping @MainActor (String) -> Void) async throws -> URL {
        let dir = project.dir.appendingPathComponent(".lamp/device")
        let app = dir.appendingPathComponent("DerivedData/Build/Products/Release-iphoneos/\(project.exe).app")
        let status = await Shell.run("""
            xcodebuild -project "$LAMP_PROJECT" -scheme "$LAMP_SCHEME" -configuration Release -destination "id=$LAMP_UDID" \\
              -derivedDataPath "$LAMP_DERIVED" -allowProvisioningUpdates -allowProvisioningDeviceRegistration \\
              DEVELOPMENT_TEAM="$LAMP_TEAM" build 2>&1
            """, cwd: dir, env: ["LAMP_PROJECT": dir.appendingPathComponent("\(project.exe).xcodeproj").path, "LAMP_SCHEME": project.exe,
                                 "LAMP_UDID": udid, "LAMP_DERIVED": dir.appendingPathComponent("DerivedData").path, "LAMP_TEAM": team],
            started: started, onLine: onLine)
        guard status == 0, FileManager.default.fileExists(atPath: app.path) else { throw Failure(message: "Xcode couldn't build the app for the phone.") }
        return app
    }

    static func install(_ app: URL, on udid: String) async throws {
        let result = await Subprocess.run("/usr/bin/xcrun", ["devicectl", "device", "install", "app", "--device", udid, app.path],
                                          mergeErrors: true, timeout: 300)
        guard result.ok else {
            throw Failure(message: "The app couldn't be put on the phone. Plug it in or put it on the same Wi‑Fi as this Mac, and unlock it.\n\n\(tail(result.output))")
        }
    }

    /// Launches the app and stays attached: what it prints goes to the log until it quits, as on the
    /// simulator. The process is devicectl's, kept so a later launch or Stop can end it.
    static func launch(_ bundleID: String, on udid: String, log: URL) throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "device", "process", "launch", "--device", udid, "--terminate-existing", "--console", bundleID]
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        try process.run()
        return process
    }

    /// The last lines of a tool's output, for a message: the reason is at the end, after the noise.
    static func tail(_ output: String, lines: Int = 12) -> String {
        output.split(separator: "\n").map(String.init).filter { !$0.trimmed.isEmpty }.suffix(lines).joined(separator: "\n")
    }

    /// What's wrong before anything is tried, in plain words, or nil when the phone is ready.
    static func problem(_ device: Device?, team: String) -> String? {
        guard let device else { return "That phone isn't paired with this Mac any more. Plug it in and choose it again under Try On." }
        guard device.developerMode else { return "Turn on Developer Mode on \(device.name) (Settings → Privacy & Security → Developer Mode), then try again." }
        guard team.count == 10 else { return "Choose your Apple team in Lamp's Settings → Building → Experimental first." }
        let signedIn = xcodeTeams()
        guard signedIn.isEmpty || signedIn.contains(where: { $0.id == team }) else {
            return "Xcode is signed in to \(signedIn.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")), not team \(team). Choose that team in Lamp's Settings → Building → Experimental, or sign in to the other account in Xcode → Settings → Accounts."
        }
        return nil
    }
}
