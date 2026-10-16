import AVFoundation
import SwiftUI
import Vision

/// Watches a camera for barcodes. Any camera the Mac has will do, including an iPhone used as the Mac's
/// camera (Continuity Camera), which is the easiest one to hold a book's back cover up to.
final class BarcodeScanner: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    @Published private(set) var cameras: [AVCaptureDevice] = []
    @Published private(set) var cameraID: String?
    @Published private(set) var access = AVCaptureDevice.authorizationStatus(for: .video)
    /// Goes up each time a camera is connected, so the preview can set itself up for it.
    @Published private(set) var connected = 0
    /// Called on the main thread with each barcode number seen clearly, at most once every few seconds.
    var onCode: ((String) -> Void)?

    let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "Shelves.scanner")
    // Only touched on `queue`.
    private var lastLook = Date.distantPast
    private var candidate: String?
    private var lastReported: (code: String, at: Date)?

    func start() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { _ in
                DispatchQueue.main.async { self.start() }
            }
        case .authorized:
            access = .authorized
            let found = AVCaptureDevice.DiscoverySession(
                deviceTypes: [.builtInWideAngleCamera, .continuityCamera, .external],
                mediaType: .video, position: .unspecified).devices
            cameras = found
            // The camera macOS would pick by itself, which is the iPhone when it's nearby and ready.
            use(cameraID ?? AVCaptureDevice.systemPreferredCamera?.uniqueID ?? found.first?.uniqueID)
        case let status:
            access = status
        }
    }

    func stop() {
        queue.async { self.session.stopRunning() }
    }

    func use(_ id: String?) {
        guard let id else { return }
        cameraID = id
        queue.async { [self] in
            session.beginConfiguration()
            session.inputs.forEach(session.removeInput)
            if session.outputs.isEmpty {
                let output = AVCaptureVideoDataOutput()
                output.alwaysDiscardsLateVideoFrames = true
                output.setSampleBufferDelegate(self, queue: queue)
                if session.canAddOutput(output) { session.addOutput(output) }
            }
            if let device = AVCaptureDevice(uniqueID: id), let input = try? AVCaptureDeviceInput(device: device),
               session.canAddInput(input) {
                session.addInput(input)
            }
            session.commitConfiguration()
            if !session.isRunning { session.startRunning() }
            DispatchQueue.main.async { self.connected += 1 }
        }
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // Five looks a second is plenty, and leaves the Mac cool.
        guard Date().timeIntervalSince(lastLook) > 0.2, let pixels = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        lastLook = Date()
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.ean13, .ean8, .upce]
        try? VNImageRequestHandler(cvPixelBuffer: pixels, orientation: .up).perform([request])
        guard let code = request.results?.compactMap(\.payloadStringValue).first else { return }
        // The same number twice in a row before believing it, and not the same one again straight away.
        defer { candidate = code }
        guard code == candidate else { return }
        if let last = lastReported, last.code == code, Date().timeIntervalSince(last.at) < 4 { return }
        lastReported = (code, Date())
        DispatchQueue.main.async { self.onCode?(code) }
    }
}

/// What the camera sees, mirrored like a looking glass so holding something up feels natural.
struct CameraPreview: NSViewRepresentable {
    let session: AVCaptureSession
    /// Read only so a new camera updates the view: its connection is new, and is mirrored again.
    let connected: Int

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        view.layer = layer
        view.wantsLayer = true
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        guard let connection = (view.layer as? AVCaptureVideoPreviewLayer)?.connection,
              connection.isVideoMirroringSupported else { return }
        connection.automaticallyAdjustsVideoMirroring = false
        connection.isVideoMirrored = true
    }
}
