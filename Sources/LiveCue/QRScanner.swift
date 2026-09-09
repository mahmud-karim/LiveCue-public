import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    let onResult: (Result<String, Error>) -> Void
    func makeUIViewController(context: Context) -> QRScannerController { QRScannerController(onResult: onResult) }
    func updateUIViewController(_ controller: QRScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: QRScannerController, coordinator: ()) { controller.stop() }
}

final class QRScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let capture = AVCaptureSession()
    private let queue = DispatchQueue(label: "LiveCue.QRScanner")
    private var preview: AVCaptureVideoPreviewLayer?
    private var finished = false
    private let onResult: (Result<String, Error>) -> Void
    init(onResult: @escaping (Result<String, Error>) -> Void) { self.onResult = onResult; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, !self.finished else { return }
                guard granted else { self.fail("Camera access is required. Enable it in Settings, or paste the pairing payload instead."); return }
                self.configure()
            }
        }
    }
    private func configure() {
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), capture.canAddInput(input) else { fail("Camera is unavailable. Paste the pairing payload instead."); return }
        capture.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard capture.canAddOutput(output) else { fail("QR scanning is unavailable."); return }
        capture.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let layer = AVCaptureVideoPreviewLayer(session: capture); layer.videoGravity = .resizeAspectFill
        view.layer.addSublayer(layer); preview = layer; layer.frame = view.bounds
        queue.async { [capture] in capture.startRunning() }
    }
    override func viewDidLayoutSubviews() { super.viewDidLayoutSubviews(); preview?.frame = view.bounds }
    func stop() { finished = true; queue.async { [capture] in if capture.isRunning { capture.stopRunning() } } }
    private func fail(_ message: String) { guard !finished else { return }; stop(); onResult(.failure(NSError(domain: "LiveCue", code: 3, userInfo: [NSLocalizedDescriptionKey: message]))) }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput objects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !finished, let value = (objects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        stop(); onResult(.success(value))
    }
}
