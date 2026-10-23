import AVFoundation

/// Captures portrait frames from the back camera and hands each one to `onFrame`.
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "visionaid.session")
    private let frameQueue = DispatchQueue(label: "visionaid.frames", qos: .userInitiated)
    private var isConfigured = false
    private var device: AVCaptureDevice?

    /// Field of view in degrees across the long side of the frame, used for bearing and distance.
    var fieldOfView: Double {
        guard let d = device else { return 70 }
        let format = d.activeFormat
        return Double(d.isGeometricDistortionCorrectionEnabled
                      ? format.geometricDistortionCorrectedVideoFieldOfView
                      : format.videoFieldOfView)
    }

    /// Asks for camera permission. Returns false if the user refused.
    func requestAccess() async -> Bool {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized: return true
        case .notDetermined: return await AVCaptureDevice.requestAccess(for: .video)
        default: return false
        }
    }

    func start() {
        sessionQueue.async {
            if !self.isConfigured { self.configure() }
            if !self.session.isRunning { self.session.startRunning() }
        }
    }

    func stop() {
        sessionQueue.async {
            if self.session.isRunning { self.session.stopRunning() }
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 720p is plenty for a 640x640 model and keeps processing cheap.
        session.sessionPreset = .hd1280x720

        // Ultra-wide (0.5x) sees more of the path; fall back to the main camera on older phones.
        guard let camera = AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back)
                ?? AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(input) else { return }
        session.addInput(input)
        device = camera

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Drop frames that arrive while the model is still busy, so alerts never lag behind reality.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        // Rotate buffers to portrait so the model sees the scene upright (phone is chest-mounted, portrait).
        if let connection = output.connection(with: .video) {
            if #available(iOS 17.0, *) {
                if connection.isVideoRotationAngleSupported(90) { connection.videoRotationAngle = 90 }
            } else if connection.isVideoOrientationSupported {
                connection.videoOrientation = .portrait
            }
        }
        isConfigured = true
    }
}

extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput,
                       didOutput sampleBuffer: CMSampleBuffer,
                       from connection: AVCaptureConnection) {
        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else { return }
        onFrame?(pixelBuffer)
    }
}
