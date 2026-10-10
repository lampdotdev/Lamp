import SwiftUI
import Network
import CoreImage.CIFilterBuiltins

/// One paired phone and its app's chat. The companion cannot browse other projects or reach the
/// gateway, settings, files or approval decisions. Execution still belongs to Store's normal turn.
@MainActor final class PhoneWishes: ObservableObject {
    static let shared = PhoneWishes()
    struct Pairing: Codable {
        let pair: PhoneLink.Pair
        let device: String
        let name: String
    }
    @Published private(set) var pairing: Pairing?
    @Published private(set) var problem: String?
    @Published private(set) var activity: String?
    @Published private(set) var listening = false
    @Published var showCode = false
    private var server: PhoneLinkServer?
    private var ledger: PhoneWishLedger?
    private var starting: Set<UUID> = []
    private var retryAfter: [UUID: Date] = [:]
    private var power: NSObjectProtocol?
    private var transfer: PhoneLink.ChatTransfer?
    private var enabled: Bool { UserDefaults.standard.bool(forKey: "phoneWishesEnabled") }
    private var keyService: String { Edition.bundleID + ".phone-wishes" }

    static func message(for failure: PhoneFailure) -> String {
        [.locked, .unreachable].contains(failure.cause)
            ? "Unlock your iPhone on the same Wi-Fi."
            : failure.message
    }

    func start() {
        guard enabled, server == nil else { return }
        do {
            if ledger == nil {
                var saved = try PhoneWishLedger(file: Edition.supportFolder.appendingPathComponent("PhoneWishes/jobs.json"))
                // A process death cannot prove where an agent stopped. Keep its wish and app for the
                // person on the Mac; never automatically run a possibly completed request twice.
                for job in saved.jobs where [.queued, .building, .approval].contains(job.status.phase) {
                    try saved.update(.init(id: job.id, phase: .needsMac))
                    for message in job.submissions where message.state == .queued {
                        try saved.record(message.id, in: job.id, as: .dispatched)
                    }
                }
                for job in saved.jobs where job.status.phase == .installing {
                    try saved.update(.init(id: job.id, phase: .waitingPhone))
                }
                ledger = saved
            }
            pairing = try PhoneLink.loadKey(Pairing.self, service: keyService)
            guard let pairing, pairing.pair.valid else { return }
            let pairID = pairing.pair.id
            let listener = try PhoneLinkServer(pair: pairing.pair) { [weak self] request in
                await self?.handle(request, pairID: pairID) ?? .init(error: "Mac unavailable")
            }
            server = listener
            listener.start { [weak self] state in
                Task { @MainActor in
                    guard let self, self.pairing?.pair.id == pairID else { return }
                    switch state {
                    case .ready: self.listening = true
                    case .failed: self.problem = "Connect this Mac to Wi-Fi, then try again."; self.stop()
                    default: break
                    }
                }
            }
        } catch { problem = "Couldn't read the iPhone pairing or saved wishes. Try again." }
    }

    func setEnabled(_ value: Bool) {
        UserDefaults.standard.set(value, forKey: "phoneWishesEnabled")
        if value { start() } else { stop() }
    }

    private func stop() {
        server?.stop()
        server = nil
        listening = false
        transfer = nil
    }

    func owns(_ project: LampProject) -> Bool {
        ledger?.jobs.contains { $0.id.uuidString == project.instance } == true
    }

    func mark(_ project: LampProject, _ phase: PhoneLink.Status.Phase, appURL: String? = nil) throws {
        guard let id = UUID(uuidString: project.instance), owns(project) else { return }
        guard ledger != nil else { throw PhoneLink.Failure.storage }
        let previousURL = ledger?.jobs.first { $0.id == id }?.status.appURL
        try ledger?.update(.init(id: id, phase: phase, appURL: appURL ?? previousURL))
        updatePower()
    }

    func ended(_ project: LampProject, replied: Bool = false) {
        guard let job = ledger?.jobs.first(where: { $0.id.uuidString == project.instance }),
              (replied && job.status.phase != .waitingPhone) || [.queued, .building, .approval, .installing].contains(job.status.phase)
        else { updatePower(); return }
        do { try mark(project, replied ? (job.status.appURL == nil ? .replied : .ready) : .needsMac) }
        catch { problem = "Couldn't save wish progress. Check Lamp on Mac." }
    }

    func reject(_ id: UUID, messageID: UUID) {
        do {
            try ledger?.record(messageID, in: id, as: .dispatched)
            try ledger?.update(.init(id: id, phase: .needsMac))
        }
        catch { problem = "Couldn't save wish progress. Check Lamp on Mac." }
        updatePower()
    }

    func dispatch(_ messageID: UUID, in project: LampProject) throws {
        guard let id = UUID(uuidString: project.instance), ledger != nil else { throw PhoneLink.Failure.storage }
        try ledger?.record(messageID, in: id, as: .dispatched)
        if !Store.shared.busy.contains(project.id) { try mark(project, .building) }
    }

    func posted(_ messageID: UUID, in project: LampProject) {
        guard owns(project), let id = UUID(uuidString: project.instance) else { return }
        do { try ledger?.record(messageID, in: id, as: .posted) }
        catch { problem = "Couldn't save message progress. Check Lamp on Mac." }
    }

    private func updatePower() {
        let working = ledger?.jobs.contains { [.queued, .building, .installing].contains($0.status.phase) } == true
        if working, power == nil {
            // Keep computation and Wi-Fi available while a wish runs. The display can still sleep
            // and the Mac can still lock; no lock or security preference is changed.
            power = ProcessInfo.processInfo.beginActivity(options: [.userInitiatedAllowingIdleSystemSleep, .idleSystemSleepDisabled],
                                                         reason: "Building an iPhone wish")
        } else if !working, let power {
            ProcessInfo.processInfo.endActivity(power)
            self.power = nil
        }
    }

    private func handle(_ request: PhoneLink.Request, pairID: UUID) -> PhoneLink.Reply {
        guard enabled, let pairing, pairing.pair.id == pairID, ledger != nil else { return .init(error: "Pair again on Mac") }
        do {
            if request.action == .hello { showCode = false; return .init() }
            guard let id = request.id else { throw PhoneLink.Failure.invalid }
            let chatID = request.chatID ?? id
            if request.action == .submit {
                guard let wish = request.wish else { throw PhoneLink.Failure.invalid }
                if request.chatID == nil {
                    // A request UUID names a new phone app, never an existing unrelated Mac app.
                    guard ledger?.jobs.contains(where: { $0.id == id }) == true ||
                            !Store.shared.projects.contains(where: { $0.instance == id.uuidString }) else { throw PhoneLink.Failure.invalid }
                    _ = try ledger?.accept(id: id, pairID: pairID, wish: wish)
                } else {
                    if let owned = ledger?.job(chatID, for: pairID), !owned.submissions.contains(where: { $0.id == id }),
                       let project = Store.shared.projects.first(where: { $0.instance == chatID.uuidString }),
                       Store.shared.logs[project.id]?.contains(where: { $0.id == id }) == true { throw PhoneLink.Failure.invalid }
                    _ = try ledger?.reply(id: id, to: chatID, pairID: pairID, text: wish)
                }
            }
            guard let job = ledger?.job(chatID, for: pairID) else {
                return .init(error: "Conversation not found", refused: request.action == .submit)
            }
            for message in job.submissions where message.state == .queued && starting.insert(message.id).inserted {
                updatePower()
                Store.shared.startPhoneMessage(message, in: job, device: pairing.device) { [weak self] in self?.starting.remove(message.id) }
            }
            let project = Store.shared.projects.first { $0.instance == chatID.uuidString }
            if job.status.phase == .waitingPhone, let project, !Store.shared.busy.contains(project.id),
               !job.submissions.contains(where: { $0.state == .queued }),
               (retryAfter[chatID] ?? .distantPast) < Date() {
                retryAfter[chatID] = Date().addingTimeInterval(20)
                Task { await Store.shared.retryPhone(project, udid: pairing.device) }
            }
            var status = ledger?.job(chatID, for: pairID)?.status ?? job.status
            if let project {
                if Store.shared.busy.contains(project.id) {
                    if status.phase.isFinished { status.phase = .building }
                    status.activity = Store.shared.progress[project.id]?.activity
                }
                if Store.shared.approvals[project.id] != nil { status.phase = .approval; status.activity = nil }
            }
            let chunk = try transcript(request, job: job, project: project)
            return .init(status: status, acceptedID: request.action == .submit ? id : nil, chat: chunk)
        } catch {
            let job = request.id.flatMap { ledger?.job(request.chatID ?? $0, for: pairID) }
            let accepted = request.action == .submit && job?.submissions.contains {
                $0.id == request.id && $0.text == request.wish
            } == true
            return .init(status: accepted ? job?.status : nil, error: error.localizedDescription,
                         refused: !accepted, acceptedID: accepted ? request.id : nil)
        }
    }

    private func transcript(_ request: PhoneLink.Request, job: PhoneWishLedger.Job, project: LampProject?) throws -> PhoneLink.ChatChunk {
        if let revision = request.revision, let transfer, transfer.chatID == job.id,
           transfer.revision == revision, Date().timeIntervalSince(transfer.created) < 30 {
            return try transfer.chunk(at: request.offset ?? 0)
        }
        let store = Store.shared
        let raw = project.map { store.logs[$0.id] ?? [] } ?? []
        let lines = project.map { Transcript.withoutSpentOffers(raw, dir: $0.dir) } ?? raw
        var queued = (project.map { store.queued[$0.id] ?? [] } ?? []).map {
            PhoneLink.ChatLine(id: $0.phoneID ?? $0.id, kind: .user, text: $0.text,
                               attachments: $0.attachments.count + $0.kept.count, queued: true)
        }
        let known = Set(raw.map(\.id) + queued.map(\.id))
        queued += job.submissions.filter { $0.state != .posted && !known.contains($0.id) }.map {
            .init(id: $0.id, kind: .user, text: $0.text, queued: true)
        }
        let chat = PhoneTranscript.chat(id: job.id, title: project?.title ?? "New App", lines: lines, queued: queued)
        let frozen = try PhoneLink.ChatTransfer(chat)
        transfer = frozen
        return try frozen.chunk(at: 0)
    }

    func install(on device: Devices.Device) {
        guard activity == nil else { return }
        problem = nil
        activity = "Checking iPhone"
        PhoneSetup.shared.perform(phone: device.udid, cancelled: { [weak self] in self?.activity = nil }) { [weak self] in
            Task { await self?.installPrepared(on: device) }
        }
    }

    private func installPrepared(on device: Devices.Device) async {
        defer { activity = nil }
        do {
            guard !ledgerJobsInFlight else { throw Devices.Failure(message: "Wait for the current wish to finish.") }
            let devices = await Devices.list()
            guard devices.contains(where: { $0.udid == device.udid && $0.wifi }) else {
                throw Devices.Failure(message: "Connect the iPhone and this Mac to the same Wi-Fi, with the iPhone unplugged.")
            }
            let folder = Edition.supportFolder.appendingPathComponent("PhoneCompanion")
            let project = LampProject(id: "companion", name: "Lamp", exe: "LampCompanion", dir: folder, platform: .iphone)
            let sources = folder.appendingPathComponent("Sources")
            try FileManager.default.createDirectory(at: sources, withIntermediateDirectories: true)
            for name in ["PhoneLink.swift", "CompanionApp.swift"] {
                guard let bundled = Bundle.main.url(forResource: name, withExtension: nil, subdirectory: "PhoneCompanion") else {
                    throw Devices.Failure(message: "The iPhone app is missing. Build Lamp again.")
                }
                try Data(contentsOf: bundled).write(to: sources.appendingPathComponent(name), options: .atomic)
            }
            if let icon = Bundle.main.url(forResource: "AppIcon.png", withExtension: nil, subdirectory: "PhoneCompanion") {
                try FileManager.default.createDirectory(at: folder.appendingPathComponent(".lamp"), withIntermediateDirectories: true)
                try Data(contentsOf: icon).write(to: Icons.squareURL(project), options: .atomic)
            }
            try Template.writeDeviceProject(for: project, team: Devices.team)
            let info = folder.appendingPathComponent(".lamp/device/Info.plist")
            var plist = try PropertyListSerialization.propertyList(from: Data(contentsOf: info), format: nil) as! [String: Any]
            plist["NSBonjourServices"] = [PhoneLink.service]
            plist["NSCameraUsageDescription"] = "Scan Lamp's pairing code on your Mac."
            plist["NSLocalNetworkUsageDescription"] = "Send wishes to Lamp on your Mac."
            try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0).write(to: info, options: .atomic)
            activity = "Building iPhone app"
            var output = ""
            let app: URL
            do { app = try await Devices.build(project, team: Devices.team, udid: device.udid) { output += $0 + "\n" } }
            catch { throw Devices.Failure(message: Self.message(for: PhoneFailure(stage: .build, output: output))) }
            activity = "Installing"
            guard await Devices.list().contains(where: { $0.udid == device.udid && $0.wifi }) else {
                throw Devices.Failure(message: "Unlock your iPhone on the same Wi-Fi, then try again.")
            }
            do { try await Devices.install(app, on: device.udid) }
            catch let failure as PhoneFailure { throw Devices.Failure(message: Self.message(for: failure)) }
            // Opening is deliberately left to the phone. devicectl --console would own its lifetime.
            let newPairing = try Pairing(pair: PhoneLink.Pair(), device: device.udid, name: device.name)
            try PhoneLink.saveKey(newPairing, service: keyService)
            stop()
            pairing = newPairing
            setEnabled(true)
            showCode = true
        } catch { problem = error.localizedDescription }
    }

    private var ledgerJobsInFlight: Bool {
        ledger?.jobs.contains { !$0.status.phase.isFinished } == true
    }

    var code: NSImage? {
        guard showCode, let pairing else { return nil }
        let filter = CIFilter.qrCodeGenerator()
        filter.message = Data(pairing.pair.invitation.utf8)
        guard let output = filter.outputImage?.transformed(by: CGAffineTransform(scaleX: 6, y: 6)),
              let image = CIContext().createCGImage(output, from: output.extent) else { return nil }
        return NSImage(cgImage: image, size: NSSize(width: 240, height: 240))
    }
}

struct PhoneWishSettings: View {
    @ObservedObject private var model = PhoneWishes.shared
    @AppStorage("phoneWishesEnabled") private var enabled = false
    @State private var devices: [Devices.Device] = []
    var body: some View {
        Form {
            Section {
                Toggle("iPhone wishes", isOn: $enabled).toggleStyle(.checkbox)
                    .disabled(model.activity != nil)
                    .onChange(of: enabled) { model.setEnabled(enabled) }
                if enabled {
                    VStack(alignment: .leading, spacing: 12) {
                        if let activity = model.activity { ProgressView(activity) }
                        else if let code = model.code {
                            Text("Open Lamp on iPhone and scan this code.")
                            Image(nsImage: code).interpolation(.none).resizable().frame(width: 240, height: 240)
                        } else if let pairing = model.pairing {
                            Text(pairing.name)
                            Button("Pair Again…") { model.showCode = true }
                        } else if devices.isEmpty {
                            Text("Unlock your paired iPhone on the same Wi-Fi.").foregroundStyle(.secondary)
                            Button("Check Again") { Task { devices = await Devices.list().filter { $0.paired && $0.wifi } } }
                        } else {
                            ForEach(devices) { device in
                                Button("Install Lamp on \(device.name)…") { model.install(on: device) }
                            }
                            Text("Uses one of your three free app slots. Reinstall after seven days.").foregroundStyle(.secondary)
                        }
                        if let problem = model.problem { Text(problem).foregroundStyle(.orange) }
                    }.underCheckbox()
                }
            }
        }
        .settingsPane()
        .task { if enabled { model.start() }; devices = await Devices.list().filter { $0.paired && $0.wifi } }
    }
}
