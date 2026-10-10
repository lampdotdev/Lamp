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
        var status: PhoneLink.Status
    }
    struct Saved: Codable {
        var draft = ""
        var pending: Pending?
    }
    @Published var saved = Saved()
    @Published var paired = false
    @Published var message: String?
    @Published var scanning = false
    @Published var refused = false
    private var pair: PhoneLink.Pair?
    private var browser: NWBrowser?
    private var endpoint: NWEndpoint?
    private var exchange: PhoneLinkExchange?
    private var timer: Task<Void, Never>?
    private var generation = UUID()
    private var active = false
    private var hello = true
    private var canSave = true
    private let queue = DispatchQueue(label: "lamp.companion.discovery")
    private let file = URL.applicationSupportDirectory.appendingPathComponent("wish.json")
    private var keyService: String { (Bundle.main.bundleIdentifier ?? "lamp.companion") + ".pair" }

    init() {
        do {
            if FileManager.default.fileExists(atPath: file.path) {
                saved = try JSONDecoder().decode(Saved.self, from: Data(contentsOf: file))
            }
            pair = try PhoneLink.loadKey(PhoneLink.Pair.self, service: keyService)
            paired = pair?.valid == true
        } catch {
            canSave = false
            message = "Couldn't read the saved wish. Reopen Lamp."
        }
    }

    func saveDraft() { do { try persist(saved) } catch { message = "Couldn't save. Try again." } }

    private func persist(_ next: Saved) throws {
        guard canSave else { throw PhoneLink.Failure.storage }
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try JSONEncoder().encode(next).write(to: file, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        saved = next
    }

    func send() {
        let scalars = saved.draft.unicodeScalars.filter { $0 == "\n" || !CharacterSet.controlCharacters.contains($0) }
        let wish = String(String.UnicodeScalarView(scalars)).trimmingCharacters(in: .whitespacesAndNewlines)
        guard saved.pending == nil, !wish.isEmpty, wish.count <= 4000 else { return }
        let id = UUID()
        do {
            let request = PhoneLink.Request(action: .submit, id: id, wish: wish)
            guard try JSONEncoder().encode(request).count <= PhoneLink.limit else {
                message = "Wish is too long. Shorten it and try again."
                return
            }
            try persist(Saved(draft: wish, pending: Pending(id: id, wish: wish, status: .init(id: id, phase: .queued))))
            refused = false
            poll()
        } catch { message = "Couldn't save. Try again." }
    }

    func newWish() {
        do { try persist(Saved()); message = nil }
        catch { message = "Couldn't save. Try again." }
    }

    func editWish() {
        do { try persist(Saved(draft: saved.pending?.wish ?? saved.draft)); refused = false; message = nil }
        catch { message = "Couldn't save. Try again." }
    }

    func scanned(_ text: String) {
        guard let found = PhoneLink.Pair.read(text) else { message = "Scan the code in Lamp on Mac."; return }
        if let pending = saved.pending, ![.ready, .needsMac].contains(pending.status.phase),
           let pair, pair.id != found.id {
            message = "Finish the current wish before pairing with another Mac."
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
        guard active, !refused, exchange == nil, let pair else { return }
        guard let endpoint else { message = "Waiting for Mac on Wi-Fi"; return }
        let request: PhoneLink.Request
        if hello { request = .init(action: .hello) }
        else if let pending = saved.pending {
            request = .init(action: .submit, id: pending.id, wish: pending.wish)
        } else { request = .init(action: .hello) }
        let ticket = generation
        let exchange = PhoneLinkExchange(endpoint: endpoint, pair: pair)
        self.exchange = exchange
        exchange.start(request) { [weak self] result in
            Task { @MainActor in
                guard let self, self.generation == ticket else { return }
                self.exchange = nil
                switch result {
                case .failure: self.message = "Waiting for Mac on Wi-Fi"
                case .success(let reply):
                    if let error = reply.error { self.message = error; self.refused = reply.refused == true; return }
                    self.hello = false
                    self.message = nil
                    self.refused = false
                    if let status = reply.status, status.id == self.saved.pending?.id {
                        var next = self.saved
                        next.pending?.status = status
                        do { try self.persist(next) }
                        catch { self.message = "Couldn't save progress. Reopen Lamp." }
                    }
                }
            }
        }
    }

    func openApp() {
        guard let text = saved.pending?.status.appURL, let url = URL(string: text),
              url.scheme?.hasPrefix("lamp-app-") == true else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] opened in
            if !opened { Task { @MainActor in self?.message = "Couldn't open app. Check Lamp on Mac." } }
        }
    }
}

private struct CompanionView: View {
    @ObservedObject var model: CompanionModel
    @FocusState private var writing: Bool
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 20) {
                if !model.paired {
                    Text("In Lamp on Mac, open Settings → Experimental → iPhone wishes.")
                    Button("Scan Mac Code") { model.scanning = true }.buttonStyle(.borderedProminent)
                } else if let pending = model.saved.pending {
                    Text(pending.wish)
                    if ![.ready, .needsMac].contains(pending.status.phase) {
                        HStack { ProgressView(); Text(pending.status.phase.text) }
                    } else { Text(pending.status.phase.text).foregroundStyle(.secondary) }
                    if pending.status.phase == .ready {
                        Button("Open App") { model.openApp() }.buttonStyle(.borderedProminent)
                    }
                    if [.ready, .needsMac].contains(pending.status.phase) {
                        Button("New Wish") { model.newWish() }.buttonStyle(.bordered)
                    }
                } else {
                    Text("What would you like to make?")
                    TextEditor(text: $model.saved.draft).focused($writing)
                        .frame(minHeight: 150, maxHeight: 240)
                        .padding(8).background(.quaternary, in: RoundedRectangle(cornerRadius: 12))
                        .accessibilityLabel("Wish")
                        .onChange(of: model.saved.draft) { _, _ in model.saveDraft() }
                    Button("Send") { writing = false; model.send() }.buttonStyle(.borderedProminent)
                        .disabled(model.saved.draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.saved.draft.count > 4000)
                }
                if let message = model.message { Text(message).foregroundStyle(.secondary) }
                if model.refused { Button("Edit Wish") { model.editWish() } }
                if model.paired, model.message != nil {
                    Button("Scan Mac Code") { model.scanning = true }
                }
                Spacer()
            }
            .padding(24)
            .navigationTitle("Lamp")
            .sheet(isPresented: $model.scanning) {
                NavigationStack {
                    CodeScanner(scanned: model.scanned)
                        .navigationTitle("Scan Mac Code").navigationBarTitleDisplayMode(.inline)
                        .toolbar { Button("Cancel") { model.scanning = false } }
                }
            }
        }
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
