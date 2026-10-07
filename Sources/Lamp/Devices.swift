import Foundation
import Security
import CryptoKit

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
        let paired: Bool           // trusted this Mac for development; until then nothing can be put on it
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

    /// Prefer Xcode's signed-in teams, then teams with a valid development signing identity on this Mac.
    static func knownTeams() async -> [(id: String, name: String)] {
        let output = await Subprocess.run("/usr/bin/security", ["find-identity", "-v", "-p", "codesigning"], timeout: 20).output
        let fingerprints = Set(output.split(separator: "\n").compactMap { line -> String? in
            line.split(whereSeparator: \.isWhitespace).first {
                $0.range(of: #"^[0-9A-Fa-f]{40}$"#, options: .regularExpression) != nil
            }.map { String($0).uppercased() }
        })
        var teams = xcodeTeams()
        var found: CFTypeRef?
        let query: [String: Any] = [kSecClass as String: kSecClassCertificate,
                                   kSecMatchSubjectContains as String: "Apple Development",
                                   kSecMatchLimit as String: kSecMatchLimitAll, kSecReturnRef as String: true]
        guard SecItemCopyMatching(query as CFDictionary, &found) == errSecSuccess,
              let certificates = found as? [SecCertificate] else { return teams }
        for certificate in certificates {
            let fingerprint = Insecure.SHA1.hash(data: SecCertificateCopyData(certificate) as Data)
                .map { String(format: "%02X", $0) }.joined()
            guard fingerprints.contains(fingerprint), let team = certificateTeam(certificate),
                  !teams.contains(where: { $0.id == team.id }) else { continue }
            teams.append(team)
        }
        return teams
    }

    /// The common name's parenthesised ID identifies the developer, not necessarily their team. The
    /// certificate's subject organizational unit is the signing Team ID, as Xcode writes into projects.
    static func certificateTeam(_ certificate: SecCertificate) -> (id: String, name: String)? {
        guard let values = SecCertificateCopyValues(certificate, [kSecOIDX509V1SubjectName] as CFArray, nil) as? [String: Any],
              let subject = values[kSecOIDX509V1SubjectName as String] as? [String: Any],
              let fields = subject[kSecPropertyKeyValue as String] as? [[String: Any]] else { return nil }
        func field(_ oid: CFString) -> String? {
            fields.first { $0[kSecPropertyKeyLabel as String] as? String == oid as String }?[kSecPropertyKeyValue as String] as? String
        }
        guard let id = field(kSecOIDOrganizationalUnitName)?.uppercased(),
              id.range(of: #"^[A-Z0-9]{10}$"#, options: .regularExpression) != nil,
              let commonName = field(kSecOIDCommonName), commonName.hasPrefix("Apple Development: ") else { return nil }
        let name = commonName.dropFirst("Apple Development: ".count)
            .replacingOccurrences(of: #" \([A-Z0-9]{10}\)$"#, with: "", options: .regularExpression)
        return (id, name)
    }

    /// The iPhones and iPads the Mac can see: paired ones, and plugged-in ones that haven't yet trusted
    /// this Mac for development, which Try On offers to pair. Connected ones first.
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
                  ["iPhone", "iPad"].contains(hardware["deviceType"] as? String ?? "") else { return nil }
            return Device(udid: udid, name: properties["name"] as? String ?? (hardware["deviceType"] as? String ?? "iPhone"),
                          model: hardware["marketingName"] as? String ?? (hardware["deviceType"] as? String ?? "iPhone"),
                          connected: connection["tunnelState"] as? String == "connected" || properties["ddiServicesAvailable"] as? Bool == true,
                          paired: connection["pairingState"] as? String == "paired",
                          developerMode: properties["developerModeStatus"] as? String == "enabled")
        }
        .sorted { ($0.connected ? 0 : 1, $0.name) < ($1.connected ? 0 : 1, $1.name) }
    }

    /// Pairs a plugged-in phone with this Mac for development: the phone shows "Trust This Computer?" and
    /// asks for its passcode, and this waits for the answer. What Xcode's Devices window does on its own.
    static func pair(_ udid: String) async throws {
        let result = await Subprocess.run("/usr/bin/xcrun", ["devicectl", "manage", "pair", "--device", udid, "--timeout", "120"],
                                          mergeErrors: true, timeout: 150)
        guard result.ok else {
            let output = result.output.lowercased()
            if output.contains("cancel") || output.contains("denied") || output.contains("rejected") {
                throw Failure(message: "The phone didn't trust this Mac. Tap Trust when it asks, and enter its passcode.")
            }
            if output.contains("locked") || output.contains("passcode") {
                throw Failure(message: "Unlock the phone, then try pairing again.")
            }
            throw Failure(message: "Couldn't pair with the phone. Plug it in with a cable, unlock it, and try again.\n\n\(tail(result.output, lines: 4))")
        }
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
            throw PhoneFailure(stage: .install, output: result.output + "\n" + result.errors)
        }
    }

    /// Launches the app and stays attached: what it prints goes to the log until it quits, as on the
    /// simulator. The process is devicectl's, kept so a later launch or Stop can end it.
    @MainActor
    static func launch(_ bundleID: String, on udid: String, log: URL, started: (Process) -> Void,
                       cancelled: () -> Bool) async throws -> Process {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xcrun")
        process.arguments = ["devicectl", "device", "process", "launch", "--device", udid, "--terminate-existing", "--console", bundleID]
        if !FileManager.default.fileExists(atPath: log.path) { FileManager.default.createFile(atPath: log.path, contents: nil) }
        let handle = try FileHandle(forWritingTo: log)
        let offset = handle.seekToEndOfFile()
        process.standardOutput = handle
        process.standardError = handle
        process.standardInput = FileHandle.nullDevice
        defer { try? handle.close() }
        do {
            try process.run()
            started(process)
            try await PhoneLaunch.wait(process, bundleID: bundleID, output: log, offset: offset, cancelled: cancelled)
            return process
        } catch {
            Subprocess.terminateTree(process)
            throw error
        }
    }

    /// The last lines of a tool's output, for a message: the reason is at the end, after the noise.
    static func tail(_ output: String, lines: Int = 12) -> String {
        output.split(separator: "\n").map(String.init).filter { !$0.trimmed.isEmpty }.suffix(lines).joined(separator: "\n")
    }

    /// What's wrong before anything is tried, in plain words, or nil when the phone is ready.
    static func problem(_ device: Device?, team: String) -> String? {
        guard let device else { return "Lamp can't see that phone. Plug it in with a data cable and unlock it, then Retry. If it still doesn't appear, choose it again under Try On." }
        guard device.paired else { return "\(device.name) hasn't trusted this Mac yet. Choose Pair under Try On, and tap Trust on the phone." }
        guard device.developerMode else { return "Turn on Developer Mode on \(device.name) in Settings → Privacy & Security → Developer Mode. Restart, unlock it, and confirm Turn On, then Retry." }
        guard team.count == 10 else { return "Choose your Apple team in Lamp's Settings → Building → Experimental first." }
        let signedIn = xcodeTeams()
        guard signedIn.isEmpty || signedIn.contains(where: { $0.id == team }) else {
            return "Xcode is signed in to \(signedIn.map { "\($0.name) (\($0.id))" }.joined(separator: ", ")), not team \(team). Choose that team in Lamp's Settings → Building → Experimental, or sign in to the other account in Xcode → Settings → Accounts."
        }
        return nil
    }
}
