import AVFoundation

/// Captures portrait frames from the back camera and hands each one to `onFrame`.
final class CameraManager: NSObject {
    let session = AVCaptureSession()
    var onFrame: ((CVPixelBuffer) -> Void)?

    private let output = AVCaptureVideoDataOutput()
    private let sessionQueue = DispatchQueue(label: "visionaid.session")
    private let frameQueue = DispatchQueue(label: "visionaid.frames", qos: .userInitiated)
    private var isConfigured = false
    private var input: AVCaptureDeviceInput?
    private var useUltraWide = false

    /// Field of view in degrees across the long side of the frame, used for bearing and distance.
    private(set) var fieldOfView: Double = 70

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

    /// Switches between the ultra-wide (0.5x, sees more) and main (1x, detects better) cameras.
    func setUltraWide(_ on: Bool) {
        sessionQueue.async {
            guard on != self.useUltraWide || !self.isConfigured else { return }
            self.useUltraWide = on
            guard self.isConfigured else { return }
            self.session.beginConfiguration()
            if let old = self.input { self.session.removeInput(old) }
            self.addCamera()
            self.applyPortraitRotation()
            self.session.commitConfiguration()
        }
    }

    private func configure() {
        session.beginConfiguration()
        defer { session.commitConfiguration() }

        // 720p is plenty for a 640x640 model and keeps processing cheap.
        session.sessionPreset = .hd1280x720
        guard addCamera() else { return }

        output.videoSettings = [kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA]
        // Drop frames that arrive while the model is still busy, so alerts never lag behind reality.
        output.alwaysDiscardsLateVideoFrames = true
        output.setSampleBufferDelegate(self, queue: frameQueue)
        guard session.canAddOutput(output) else { return }
        session.addOutput(output)

        applyPortraitRotation()
        isConfigured = true
    }

    /// Adds the chosen back camera; ultra-wide falls back to the main camera on phones without one.
    @discardableResult
    private func addCamera() -> Bool {
        let wide = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back)
        let camera = useUltraWide
            ? AVCaptureDevice.default(.builtInUltraWideCamera, for: .video, position: .back) ?? wide
            : wide
        guard let camera,
              let newInput = try? AVCaptureDeviceInput(device: camera),
              session.canAddInput(newInput) else { return false }
        session.addInput(newInput)
        input = newInput

        let format = camera.activeFormat
        fieldOfView = Double(camera.isGeometricDistortionCorrectionEnabled
                             ? format.geometricDistortionCorrectedVideoFieldOfView
                             : format.videoFieldOfView)
        return true
    }

    /// Rotates buffers to portrait so the model sees the scene upright (phone is chest-mounted, portrait).
    /// Must be reapplied after changing inputs, because the connection is rebuilt.
    private func applyPortraitRotation() {
        if let connection = output.connection(with: .video), connection.isVideoRotationAngleSupported(90) {
            connection.videoRotationAngle = 90
        }
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
