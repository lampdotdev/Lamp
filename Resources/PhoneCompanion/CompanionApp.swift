import SwiftUI
import Network
import AVFoundation

@main struct CompanionApp: App {
    @StateObject private var model = CompanionModel()
    @Environment(\.scenePhase) private var phase
    var body: some Scene {
        WindowGroup {
            CompanionView(model: model)
                .onChange(of: phase) { _, value in model.setActive(value == .active) }
                .onAppear { model.setActive(true) }
        }
    }
}

@MainActor final class CompanionModel: ObservableObject {
    struct Pending: Codable {
        let id: UUID
        let wish: String
        var status: PhoneLink.Status? // Reads the first prototype's saved wish too.
        var chatID: UUID?
        var refused: Bool?
        var problem: String?
    }
    struct Saved: Codable {
        var draft = ""
        var pending: Pending?
        var chatID: UUID?
        var transcript: PhoneLink.Chat?
        var status: PhoneLink.Status?
    }
    @Published var saved = Saved()
    @Published var paired = false
    @Published var message: String?
    @Published var scanning = false
    @Published var connectionProblem = false
    private var pair: PhoneLink.Pair?
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var exchange: PhoneLinkExchange?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var active = false
    private var hello = true
    private var canSave = true
    private var assembly = PhoneLink.ChatAssembly()
    private let queue = DispatchQueue(label: "lamp.companion.discovery")
    private let file = URL.applicationSupportDirectory.appendingPathComponent("wish.json")
    private var keyService: String { (Bundle.main.bundleIdentifier ?? "lamp.companion") + ".pair" }

    init() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
                if saved.chatID == nil, let pending = saved.pending {
                    saved.chatID = pending.id
                    saved.status = pending.status
                    if saved.draft == pending.wish { saved.draft = "" }
                }
            }
            pair = try PhoneLink.loadKey(PhoneLink.Pair.self, service: keyService)
            paired = pair?.valid == true
        } catch {
            canSave = false
            message = "Couldn't read the saved conversation. Reopen Lamp."
        }
    }

    func saveDraft() { do { try persist(saved) } catch { message = "Couldn't save. Try again." } }

    private func persist(_ next: Saved) throws {
        guard canSave else { throw PhoneLink.Failure.storage }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        saved = next
    }

    var canSend: Bool {
        canSave && saved.pending == nil && !saved.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && saved.draft.count <= 4000
    }
    var canStartApp: Bool {
        saved.pending == nil && saved.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && saved.chatID != nil && saved.status?.phase.isFinished == true
    }

    func send() {
        let scalars = saved.draft.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        let text = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard canSend, !text.isEmpty else { return }
        let id = UUID()
        do {
            let request = PhoneLink.Request(action: .submit, id: id, wish: text, chatID: saved.chatID)
            guard try JSONEncoder().encode(request).count <= PhoneLink.limit else {
                message = "Message is too long. Shorten it and try again."
                return
            }
            var next = saved
            next.pending = Pending(id: id, wish: text, chatID: saved.chatID)
            next.chatID = saved.chatID ?? id
            next.status = .init(id: next.chatID!, phase: .queued, appURL: saved.status?.appURL)
            next.draft = ""
            try persist(next)
            assembly = .init()
            poll()
        } catch { message = "Couldn't save. Try again." }
    }

    func newApp() {
        guard canStartApp else { return }
        do {
            try persist(Saved())
            message = nil
            restart()
        } catch { message = "Couldn't save. Try again." }
    }

    func editMessage() {
        guard let pending = saved.pending, pending.refused == true else { return }
        do {
            var next = saved
            next.draft = pending.wish + (saved.draft.isEmpty ? "" : "\n\n" + saved.draft)
            next.pending = nil
            if pending.chatID == nil { next.chatID = nil; next.status = nil; next.transcript = nil }
            try persist(next)
            message = nil
        } catch { message = "Couldn't save. Try again." }
    }

    func scanned(_ text: String) {
        guard let found = PhoneLink.Pair.read(text) else { message = "Scan the code in Lamp on Mac."; return }
        if let pair, pair.id != found.id, saved.chatID != nil {
            message = "Start a new app before pairing with another Mac."
            scanning = false
            return
        }
        do {
            try PhoneLink.saveKey(found, service: keyService)
            pair = found
            paired = true
            scanning = false
            hello = true
            restart()
        } catch { message = "Couldn't save pairing. Try again." }
    }

    func setActive(_ value: Bool) {
        guard active != value else { return }
        active = value
        restart()
    }

    private func restart() {
        generation = UUID()
        timer?.cancel(); timer = nil
        browser?.cancel(); browser = nil
        exchange?.cancel(); exchange = nil
        endpoint = nil
        assembly = .init()
        guard active, let pair, pair.valid else { return }
        let ticket = generation
        let parameters = NWParameters.tcp
        parameters.requiredInterfaceType = .wifi
        parameters.includePeerToPeer = false
        let browser = NWBrowser(for: .bonjour(type: PhoneLink.service, domain: "local."), using: parameters)
        self.browser = browser
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            let endpoint = results.first { result in
                if case .service(let name, _, _, _) = result.endpoint { return name == pair.id.uuidString }
                return false
            }?.endpoint
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                self.endpoint = endpoint
                self.poll()
            }
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .waiting = state {
                Task { @MainActor in
                    guard let self, self.generation == ticket else { return }
                    self.message = "Allow Local Network for Lamp in Settings."
                }
            }
        }
        browser.start(queue: queue)
        timer = Task { [weak self] in
            while !Task.isCancelled {
                self?.poll()
                try? await Task.sleep(for: .seconds(2))
            }
        }
    }

    private func poll() {
        guard active, exchange == nil, let pair else { return }
        guard let endpoint else { connectionProblem = true; message = "Waiting for Mac on Wi-Fi"; return }
        let request: PhoneLink.Request
        if hello { request = .init(action: .hello) }
        else if let pending = saved.pending, pending.refused != true {
            request = .init(action: .submit, id: pending.id, wish: pending.wish, chatID: pending.chatID)
        } else if let id = saved.chatID, saved.pending?.refused != true || saved.pending?.chatID != nil {
            request = .init(action: .status, id: id, revision: assembly.revision, offset: assembly.data.count)
        } else if saved.pending?.refused == true { return }
        else { request = .init(action: .hello) }
        let ticket = generation
        let exchange = PhoneLinkExchange(endpoint: endpoint, pair: pair)
        self.exchange = exchange
        exchange.start(request) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                self.exchange = nil
                switch result {
                case .failure:
                    self.assembly = .init()
                    self.connectionProblem = true
                    self.message = "Waiting for Mac on Wi-Fi"
                case .success(let reply):
                    self.connectionProblem = false
                    var next = self.saved
                    if let accepted = reply.acceptedID, accepted == next.pending?.id { next.pending = nil }
                    if let status = reply.status, status.id == next.chatID { next.status = status }
                    if reply.refused == true, request.action == .submit, request.id == next.pending?.id {
                        next.pending?.refused = true
                        next.pending?.problem = reply.error
                    }
                    var more = false
                    do {
                        // A new Send can abandon an older snapshot while its next chunk is travelling.
                        // Its acknowledgement is still considered above; that old chunk is just stale.
                        let stale = request.revision != nil && request.revision != self.assembly.revision
                        if !stale, let chunk = reply.chat, let id = next.chatID {
                            if let chat = try self.assembly.append(chunk, for: id) { next.transcript = chat }
                            else { more = true }
                        }
                        try self.persist(next)
                        if reply.error == nil { self.hello = false }
                        self.message = reply.error
                        if reply.error == nil, more || (request.action == .hello && next.pending != nil) { self.poll() }
                    } catch {
                        self.assembly = .init()
                        self.message = "Couldn't save the conversation. Reopen Lamp."
                    }
                }
            }
        }
    }

    func openApp() {
        guard let text = saved.status?.appURL, let url = URL(string: text),
              url.scheme?.hasPrefix("lamp-app-") == true else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            if !opened { Task { @MainActor in self?.message = "Couldn't open app. Check Lamp on Mac." } }
        }
    }
}

private struct CompanionView: View {
    @ObservedObject var model: CompanionModel
    @FocusState private var writing: Bool
    @State private var atBottom = true
    @State private var startingApp = false
    var body: some View {
        NavigationStack {
            Group {
                if !model.paired {
                    VStack(alignment: .leading, spacing: 20) {
                        Text("In Lamp on Mac, open Settings → Experimental → iPhone wishes.")
                        Button("Scan Mac Code") { model.scanning = true }.buttonStyle(.borderedProminent)
                        if let message = model.message { Text(message).foregroundStyle(.secondary) }
                        Spacer()
                    }.padding(24)
                } else {
                    conversation
                }
            }
            .navigationTitle(model.saved.transcript?.title ?? "Lamp")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if model.canStartApp { Button("New App") { startingApp = true } }
            }
            .confirmationDialog("Start a new app? This conversation stays on your Mac.", isPresented: $startingApp, titleVisibility: .visible) {
                Button("New App") { model.newApp() }
            }
            .sheet(isPresented: $model.scanning) {
                NavigationStack {
                    CodeScanner(scanned: model.scanned)
                        .navigationTitle("Scan Mac Code").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Cancel") { model.scanning = false } }
                }
            }
        }
    }

    private var conversation: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 20) {
                        if model.saved.chatID == nil { Text("What would you like to make?").foregroundStyle(.secondary) }
                        ForEach(model.saved.transcript?.lines ?? []) { line in
                            chatLine(line)
                        }
                        if let pending = model.saved.pending,
                           model.saved.transcript?.lines.contains(where: { $0.id == pending.id }) != true {
                            chatLine(.init(id: pending.id, kind: .user, text: pending.wish, queued: pending.refused != true))
                            if pending.refused == true { Text(pending.problem ?? "Message not sent.").foregroundStyle(.secondary) }
                        }
                        if let message = model.message { Text(message).foregroundStyle(.secondary) }
                        else if let status = model.saved.status, !status.phase.isFinished {
                            if status.phase == .approval {
                                Text("Approve this request in Lamp on Mac.").foregroundStyle(.secondary)
                            } else {
                                HStack { ProgressView(); Text(status.activity ?? status.phase.text) }.foregroundStyle(.secondary)
                            }
                        } else if model.saved.status?.phase == .needsMac {
                            Text("Check Lamp on Mac.").foregroundStyle(.secondary)
                        }
                        if model.saved.pending?.refused == true {
                            Button("Edit Message") { model.editMessage(); writing = true }
                        }
                        if model.saved.status?.phase == .ready, model.saved.status?.appURL != nil {
                            Button("Open App") { model.openApp() }.buttonStyle(.borderedProminent)
                        }
                        if model.connectionProblem { Button("Scan Mac Code") { model.scanning = true } }
                        Color.clear.frame(height: 1).id("bottom")
                            .onAppear { atBottom = true }.onDisappear { atBottom = false }
                    }.padding(20)
                }
                .defaultScrollAnchor(.bottom)
                .onChange(of: model.saved.transcript) { _, _ in if atBottom { proxy.scrollTo("bottom") } }
                .onChange(of: model.saved.pending?.id) { _, id in if id != nil { proxy.scrollTo("bottom") } }
            }
            Divider()
            HStack(alignment: .bottom, spacing: 12) {
                TextField(model.saved.chatID == nil ? "Describe an app…" : "Message…", text: $model.saved.draft, axis: .vertical)
                    .lineLimit(1...6).focused($writing).padding(10)
                    .background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Message")
                    .onChange(of: model.saved.draft) { _, _ in model.saveDraft() }
                Button("Send") { model.send() }.disabled(!model.canSend).padding(.bottom, 10)
            }.padding(12)
        }
    }

    private func chatLine(_ line: PhoneLink.ChatLine) -> some View {
        VStack(alignment: line.kind == .user ? .trailing : .leading, spacing: 6) {
            if !line.text.isEmpty {
                if line.kind == .agent {
                    Text((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.text))
                        .textSelection(.enabled)
                } else {
                    Text(line.text).textSelection(.enabled)
                        .foregroundStyle(line.kind == .user ? Color.primary : Color.secondary)
                        .padding(line.kind == .user ? 12 : 0)
                        .background(line.kind == .user ? Color.accentColor.opacity(0.12) : .clear, in: RoundedRectangle(cornerRadius: 12))
                }
            }
            if line.attachments > 0 { Text(line.attachments == 1 ? "Attachment on Mac" : "Attachments on Mac").font(.footnote).foregroundStyle(.secondary) }
            if line.queued { Text("Queued").font(.footnote).foregroundStyle(.secondary) }
        }.frame(maxWidth: .infinity, alignment: line.kind == .user ? .trailing : .leading)
    }
}

private struct CodeScanner: UIViewControllerRepresentable {
    let scanned: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(scanned: scanned) }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
}

private final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "lamp.companion.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var delivered = false
    private let scanned: (String) -> Void
    init(scanned: @escaping (String) -> Void) { self.scanned = scanned; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self else { return }
                guard allowed, let camera = AVCaptureDevice.default(for: .video),
                      let input = try? AVCaptureDeviceInput(device: camera), self.session.canAddInput(input) else {
                    let label = UILabel(); label.text = "Allow Camera for Lamp in Settings."; label.textAlignment = .center
                    label.frame = self.view.bounds; label.autoresizingMask = [.flexibleWidth, .flexibleHeight]
                    self.view.addSubview(label); return
                }
                self.session.addInput(input)
                let output = AVCaptureMetadataOutput()
                guard self.session.canAddOutput(output) else { return }
                self.session.addOutput(output)
                output.setMetadataObjectsDelegate(self, queue: .main)
                output.metadataObjectTypes = [.qr]
                let preview = AVCaptureVideoPreviewLayer(session: self.session)
                preview.videoGravity = .resizeAspectFill; preview.frame = self.view.bounds
                self.view.layer.addSublayer(preview); self.preview = preview
                self.queue.async { self.session.startRunning() }
            }
        }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        queue.async { self.session.stopRunning() }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !delivered, let text = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue,
              PhoneLink.Pair.read(text) != nil else { return }
        delivered = true
        scanned(text)
    }
}
