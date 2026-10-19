import SwiftUI
import AVFoundation

/// The Mac's camera (or an iPhone through Continuity Camera), for snapping a bottle.
final class Camera: NSObject, ObservableObject, AVCapturePhotoCaptureDelegate {
    let session = AVCaptureSession()
    private let output = AVCapturePhotoOutput()
    private let queue = DispatchQueue(label: "camera")
    @Published var devices: [AVCaptureDevice] = []
    @Published var deviceID: String = ""
    @Published var error: String?
    @Published var ready = false
    var onPhoto: ((NSImage) -> Void)?

    func start() async {
        guard await AVCaptureDevice.requestAccess(for: .video) else {
            await MainActor.run { error = "Hot Shelf isn't allowed to use the camera. Turn it on in System Settings → Privacy & Security → Camera." }
            return
        }
        let found = AVCaptureDevice.DiscoverySession(deviceTypes: [.continuityCamera, .builtInWideAngleCamera, .external],
                                                     mediaType: .video, position: .unspecified).devices
        await MainActor.run {
            devices = found
            guard let first = found.first else { error = "No camera found. Drop or choose a photo instead."; return }
            use(first.uniqueID)
        }
    }

    func use(_ id: String) {
        guard let device = devices.first(where: { $0.uniqueID == id }) else { return }
        deviceID = id
        queue.async { [self] in
            session.beginConfiguration()
            session.sessionPreset = .photo
            session.inputs.forEach(session.removeInput)
            if let input = try? AVCaptureDeviceInput(device: device), session.canAddInput(input) { session.addInput(input) }
            if !session.outputs.contains(output), session.canAddOutput(output) { session.addOutput(output) }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.ready = true }
        }
    }

    func capture() {
        guard ready else { return }
        output.capturePhoto(with: AVCapturePhotoSettings(), delegate: self)
    }

    func stop() {
        queue.async { [session] in session.stopRunning() }
    }

    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        guard let data = photo.fileDataRepresentation(), let image = NSImage(data: data) else { return }
        DispatchQueue.main.async { self.onPhoto?(image) }
    }
}

struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {}
}

struct CameraSheet: View {
    let onPhoto: (NSImage) -> Void
    @StateObject private var camera = Camera()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 14) {
            ZStack {
                Color.black
                if let error = camera.error {
                    Text(error).foregroundStyle(.secondary).multilineTextAlignment(.center).padding()
                } else {
                    CameraPreview(session: camera.session)
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(.white.opacity(0.5), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                        .frame(width: 150, height: 300)
                        .allowsHitTesting(false)
                }
            }
            .frame(width: 520, height: 390)
            .clipShape(RoundedRectangle(cornerRadius: 10))
            Text("Stand the bottle up, label facing you, against something plain.")
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                if camera.devices.count > 1 {
                    Picker("Camera", selection: Binding(get: { camera.deviceID }, set: { camera.use($0) })) {
                        ForEach(camera.devices, id: \.uniqueID) { Text($0.localizedName).tag($0.uniqueID) }
                    }
                    .labelsHidden()
                    .frame(maxWidth: 200)
                }
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button { camera.capture() } label: { Label("Snap", systemImage: "camera.shutter.button") }
                    .keyboardShortcut(.defaultAction)
                    .disabled(!camera.ready)
            }
        }
        .padding(20)
        .task {
            camera.onPhoto = { image in
                camera.stop()
                onPhoto(image)
                dismiss()
            }
            await camera.start()
        }
        .onDisappear { camera.stop() }
    }
}
