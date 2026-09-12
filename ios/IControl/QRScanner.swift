import SwiftUI
import AVFoundation

struct QRScanner: UIViewControllerRepresentable {
    var scanned: (String) -> Void
    func makeUIViewController(context: Context) -> ScannerController { ScannerController(scanned: scanned) }
    func updateUIViewController(_ uiViewController: ScannerController, context: Context) {}
    static func dismantleUIViewController(_ controller: ScannerController, coordinator: ()) { controller.stop() }
}
final class ScannerController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    private let session = AVCaptureSession()
    private let queue = DispatchQueue(label: "IControl.camera")
    private var preview: AVCaptureVideoPreviewLayer?
    private var scanned: (String) -> Void
    private var visible = false
    private var delivered = false
    private let message = UILabel()
    init(scanned: @escaping (String) -> Void) { self.scanned = scanned; super.init(nibName: nil, bundle: nil) }
    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
    override func viewDidLoad() {
        super.viewDidLoad(); view.backgroundColor = .black
        message.textColor = .white; message.numberOfLines = 0; message.textAlignment = .center
        message.text = "Allow camera access to scan the IControl QR. You can also paste the pairing URL."
        view.addSubview(message)
    }
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated); visible = true
        AVCaptureDevice.requestAccess(for: .video) { [weak self] allowed in
            DispatchQueue.main.async {
                guard let self, self.visible else { return }
                if allowed { self.configure() }
                else { self.message.text = "Camera access denied. Enable Camera for IControl in Settings, or close this scanner and paste the pairing URL." }
            }
        }
    }
    override func viewDidDisappear(_ animated: Bool) { super.viewDidDisappear(animated); stop() }
    func stop() { visible = false; queue.async { [session] in session.stopRunning() } }
    private func configure() {
        guard session.inputs.isEmpty else { queue.async { [session] in session.startRunning() }; return }
        guard let camera = AVCaptureDevice.default(for: .video), let input = try? AVCaptureDeviceInput(device: camera), session.canAddInput(input) else {
            message.text = "Camera unavailable. Close this scanner and paste the pairing URL."; return
        }
        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else { message.text = "QR scanning unavailable. Use manual pairing."; return }
        session.addOutput(output); output.setMetadataObjectsDelegate(self, queue: .main); output.metadataObjectTypes = [.qr]
        let preview = AVCaptureVideoPreviewLayer(session: session); preview.videoGravity = .resizeAspectFill
        self.preview = preview; view.layer.insertSublayer(preview, at: 0); view.setNeedsLayout()
        message.text = "Point at the QR in the IControl window"
        queue.async { [session] in session.startRunning() }
    }
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews(); preview?.frame = view.bounds
        message.frame = CGRect(x:24,y:view.safeAreaInsets.top+24,width:view.bounds.width-48,height:100)
        if let connection = preview?.connection, connection.isVideoRotationAngleSupported(90) {
            let orientation = view.window?.windowScene?.interfaceOrientation ?? .portrait
            let angle: CGFloat = orientation == .landscapeLeft ? 0 : orientation == .landscapeRight ? 180 : orientation == .portraitUpsideDown ? 270 : 90
            if connection.isVideoRotationAngleSupported(angle) { connection.videoRotationAngle = angle }
        }
    }
    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard visible, !delivered, let value = (metadataObjects.first as? AVMetadataMachineReadableCodeObject)?.stringValue else { return }
        guard (try? Pairing(value)) != nil else { message.text = "This QR is not an IControl pairing URL."; return }
        delivered = true; stop(); scanned(value)
    }
}
