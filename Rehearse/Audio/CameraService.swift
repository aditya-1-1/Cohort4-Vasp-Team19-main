import Foundation
import SwiftUI
import AVFoundation

/// Manages the front-facing camera session for real-time video during mock interviews.
@MainActor
final class CameraManager: NSObject, ObservableObject {
    static let shared = CameraManager()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var isAvailable = false

    let captureSession = AVCaptureSession()
    private var isConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.rehearse.cameraQueue")

    override private init() {
        super.init()
    }

    /// Checks camera permissions and starts the capture session.
    func checkPermissionsAndStart() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            self.permissionGranted = true
            self.startSession()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.permissionGranted = granted
                    if granted {
                        self.startSession()
                    }
                }
            }
        default:
            self.permissionGranted = false
        }
    }

    private func startSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if !self.isConfigured {
                self.setupSession()
            }
            if !self.captureSession.isRunning && self.isAvailable {
                self.captureSession.startRunning()
                DispatchQueue.main.async {
                    self.isRunning = true
                }
            }
        }
    }

    private func setupSession() {
        captureSession.beginConfiguration()
        captureSession.sessionPreset = .vga640x480

        // Front-facing camera for interview self-view
        let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .front)
            ?? AVCaptureDevice.default(for: .video)

        if let device = device, let input = try? AVCaptureDeviceInput(device: device) {
            if captureSession.canAddInput(input) {
                captureSession.addInput(input)
                DispatchQueue.main.async {
                    self.isAvailable = true
                }
            }
        } else {
            DispatchQueue.main.async {
                self.isAvailable = false
            }
        }

        captureSession.commitConfiguration()
        isConfigured = true
    }

    func stopSession() {
        sessionQueue.async { [weak self] in
            guard let self else { return }
            if self.captureSession.isRunning {
                self.captureSession.stopRunning()
                DispatchQueue.main.async {
                    self.isRunning = false
                }
            }
        }
    }
}

/// A SwiftUI view that renders the live camera preview from AVCaptureSession.
struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

final class CameraPreviewUIView: UIView {
    override class var layerClass: AnyClass {
        AVCaptureVideoPreviewLayer.self
    }

    var previewLayer: AVCaptureVideoPreviewLayer {
        layer as! AVCaptureVideoPreviewLayer
    }

    override init(frame: CGRect) {
        super.init(frame: frame)
        setupLayer()
    }

    required init?(coder: NSCoder) {
        super.init(coder: coder)
        setupLayer()
    }

    private func setupLayer() {
        previewLayer.session = CameraManager.shared.captureSession
        previewLayer.videoGravity = .resizeAspectFill
        if previewLayer.connection?.isVideoOrientationSupported == true {
            previewLayer.connection?.videoOrientation = .portrait
        }
    }
}
