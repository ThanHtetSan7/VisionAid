import SwiftUI
import UIKit
import Observation
import QuartzCore

/// Wires camera → detector → voice alerts, and publishes results for the UI.
@Observable
final class DetectionViewModel {
    var detections: [Detection] = []
    var imageSize = CGSize(width: 720, height: 1280)
    var fps: Double = 0
    var inferenceMs: Double = 0
    var isRunning = false
    var errorMessage: String?

    var modelSize: ObstacleDetector.ModelSize = .nano {
        didSet { loadModel() }
    }
    var muted = false {
        didSet { alerts.muted = muted; if muted { alerts.stop() } }
    }

    @ObservationIgnored let camera = CameraManager()
    @ObservationIgnored private let detector = ObstacleDetector()
    @ObservationIgnored private let alerts = AlertManager()
    @ObservationIgnored private var frameTimes: [CFTimeInterval] = []

    init() {
        camera.onFrame = { [weak self] buffer in self?.handle(buffer) }
        loadModel()
    }

    func start() async {
        guard await camera.requestAccess() else {
            await MainActor.run { errorMessage = "Camera access is needed. Enable it in Settings > VisionAid." }
            return
        }
        await MainActor.run { setRunning(true) }
    }

    func toggle() {
        setRunning(!isRunning)
    }

    private func setRunning(_ running: Bool) {
        isRunning = running
        UIApplication.shared.isIdleTimerDisabled = running // keep screen on while walking
        if running {
            camera.start()
        } else {
            camera.stop()
            alerts.stop()
            detections = []
            fps = 0
        }
    }

    private func loadModel() {
        do {
            try detector.load(modelSize)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    /// Runs on the camera frame queue.
    private func handle(_ buffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let geometry = CameraGeometry(fieldOfView: camera.fieldOfView, imageSize: size)

        let start = CACurrentMediaTime()
        let results = detector.detect(buffer).map { geometry.locate($0) }
        let elapsed = (CACurrentMediaTime() - start) * 1000

        DispatchQueue.main.async {
            guard self.isRunning else { return }
            self.detections = results
            self.imageSize = size
            self.inferenceMs = elapsed
            self.updateFPS()
            self.alerts.process(results)
        }
    }

    private func updateFPS() {
        let now = CACurrentMediaTime()
        frameTimes.append(now)
        frameTimes.removeAll { now - $0 > 1 }
        fps = Double(frameTimes.count)
    }
}
