import SwiftUI
import AVFoundation

struct QRScannerView: UIViewControllerRepresentable {
    enum ScanError: Error { case notFound }

    let completion: (Result<String, Error>) -> Void

    func makeUIViewController(context: Context) -> ScannerViewController {
        let controller = ScannerViewController()
        controller.onCodeFound = { code in
            completion(.success(code))
        }
        controller.onError = { error in
            completion(.failure(error))
        }
        return controller
    }

    func updateUIViewController(_ uiViewController: ScannerViewController, context: Context) {}
}

final class ScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onCodeFound: ((String) -> Void)?
    var onError: ((Error) -> Void)?

    private let captureSession = AVCaptureSession()
    private var previewLayer: AVCaptureVideoPreviewLayer?

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black
        requestCameraAuthorizationAndSetup()
    }

    private func requestCameraAuthorizationAndSetup() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupCamera()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.setupCamera() }
                    else {
                        self.onError?(NSError(domain: "QR", code: -2, userInfo: [NSLocalizedDescriptionKey: "カメラ権限がありません"]))
                        self.dismiss(animated: true)
                    }
                }
            }
        default:
            self.onError?(NSError(domain: "QR", code: -3, userInfo: [NSLocalizedDescriptionKey: "カメラ権限がありません（設定で許可してください）"]))
            self.dismiss(animated: true)
        }
    }

    private func setupCamera() {
        guard let videoDevice = AVCaptureDevice.default(for: .video) else {
            onError?(NSError(domain: "QR", code: -1, userInfo: [NSLocalizedDescriptionKey: "カメラが見つかりません"]))
            return
        }
        do {
            let input = try AVCaptureDeviceInput(device: videoDevice)
            if captureSession.canAddInput(input) { captureSession.addInput(input) }

            let metadataOutput = AVCaptureMetadataOutput()
            if captureSession.canAddOutput(metadataOutput) { captureSession.addOutput(metadataOutput) }
            metadataOutput.setMetadataObjectsDelegate(self, queue: DispatchQueue.main)
            metadataOutput.metadataObjectTypes = [.qr]

            let previewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
            previewLayer.videoGravity = .resizeAspectFill
            previewLayer.frame = view.layer.bounds
            view.layer.addSublayer(previewLayer)
            self.previewLayer = previewLayer

            captureSession.startRunning()
        } catch {
            onError?(error)
        }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              obj.type == .qr, let value = obj.stringValue else { return }
        captureSession.stopRunning()
        onCodeFound?(value)
        dismiss(animated: true)
    }
}


