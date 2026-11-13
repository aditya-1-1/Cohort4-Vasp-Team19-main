import Foundation
import SwiftUI
import AVFoundation
import Vision

/// Tracks real-time eye contact and face orientation from camera frames using Apple's Vision framework.
final class VisionEyeTracker: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate, @unchecked Sendable {
    weak var delegate: VisionEyeTrackerDelegate?
    private var lastProcessTime: TimeInterval = 0
    private let minInterval: TimeInterval = 0.15 // Process ~6-7 fps for high responsiveness with low battery/CPU overhead
    private var totalFrames = 0
    private var eyeContactFrames = 0

    func reset() {
        totalFrames = 0
        eyeContactFrames = 0
    }

    var eyeContactPercent: Int {
        guard totalFrames > 0 else { return 0 }
        return Int((Double(eyeContactFrames) / Double(totalFrames) * 100).rounded())
    }

    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        let now = CACurrentMediaTime()
        guard now - lastProcessTime >= minInterval else { return }
        lastProcessTime = now

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }

        let request = VNDetectFaceLandmarksRequest { [weak self] req, _ in
            guard let self else { return }
            guard let faces = req.results as? [VNFaceObservation], let face = faces.first else {
                self.totalFrames += 1
                self.delegate?.didUpdateEyeContact(hasEyeContact: false, percent: self.eyeContactPercent)
                return
            }

            // Head yaw (turning left/right) and pitch (nodding up/down)
            let yaw = abs(face.yaw?.doubleValue ?? 0.0)
            let pitch = abs(face.pitch?.doubleValue ?? 0.0)

            // Candidate is looking towards the screen/camera when yaw and pitch are within ~20 degrees (0.35 rad)
            let hasContact = yaw < 0.35 && pitch < 0.35

            self.totalFrames += 1
            if hasContact {
                self.eyeContactFrames += 1
            }
            self.delegate?.didUpdateEyeContact(hasEyeContact: hasContact, percent: self.eyeContactPercent)
        }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .leftMirrored, options: [:])
        try? handler.perform([request])
    }
}

protocol VisionEyeTrackerDelegate: AnyObject, Sendable {
    func didUpdateEyeContact(hasEyeContact: Bool, percent: Int)
}

/// Manages the front-facing camera session for real-time video and eye contact analysis during mock interviews.
@MainActor
final class CameraManager: NSObject, ObservableObject, VisionEyeTrackerDelegate {
    static let shared = CameraManager()

    @Published private(set) var isRunning = false
    @Published private(set) var permissionGranted = false
    @Published private(set) var isAvailable = false
    @Published private(set) var hasEyeContact = false
    @Published private(set) var currentEyeContactPercent = 0

    let captureSession = AVCaptureSession()
    private var isConfigured = false
    private let sessionQueue = DispatchQueue(label: "com.rehearse.cameraQueue")
    private let visionQueue = DispatchQueue(label: "com.rehearse.visionQueue", qos: .userInitiated)
    private let eyeTracker = VisionEyeTracker()

    override private init() {
        super.init()
        eyeTracker.delegate = self
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

        // Add real-time video sample output for Vision face and eye tracking
        let videoOutput = AVCaptureVideoDataOutput()
        videoOutput.videoSettings = [
            (kCVPixelBufferPixelFormatTypeKey as String): Int(kCVPixelFormatType_32BGRA)
        ]
        videoOutput.alwaysDiscardsLateVideoFrames = true
        videoOutput.setSampleBufferDelegate(eyeTracker, queue: visionQueue)
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
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

    func resetEyeContactTracking() {
        eyeTracker.reset()
        hasEyeContact = false
        currentEyeContactPercent = 0
    }

    nonisolated func didUpdateEyeContact(hasEyeContact: Bool, percent: Int) {
        Task { @MainActor in
            self.hasEyeContact = hasEyeContact
            self.currentEyeContactPercent = percent
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
