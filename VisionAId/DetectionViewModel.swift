import SwiftUI
import UIKit
import Observation
import QuartzCore
import CoreMotion

/// Wires camera → detector → voice alerts, and publishes results for the UI.
@Observable
final class DetectionViewModel {
    var detections: [Detection] = []
    var imageSize = CGSize(width: 720, height: 1280)
    var fps: Double = 0
    var inferenceMs: Double = 0
    var isRunning = false
    var isLoadingModel = false
    var errorMessage: String?

    var modelSize: ObstacleDetector.ModelSize = .yolo11m {
        didSet { loadModel() }
    }
    var muted = false {
        didSet { alerts.muted = muted; if muted { alerts.stop() } }
    }

    // User settings, saved between launches.

    /// Object classes to detect and announce.
    var enabledLabels: Set<String> = Set(UserDefaults.standard.stringArray(forKey: Keys.labels) ?? Array(Obstacles.defaultEnabled)) {
        didSet {
            detector.enabledLabels = enabledLabels
            UserDefaults.standard.set(Array(enabledLabels), forKey: Keys.labels)
        }
    }
    /// Minimum confidence (0–1). Higher means fewer false alarms but more misses.
    var minConfidence: Double = UserDefaults.standard.object(forKey: Keys.confidence) as? Double ?? 0.5 {
        didSet {
            detector.minConfidence = Float(minConfidence)
            UserDefaults.standard.set(minConfidence, forKey: Keys.confidence)
        }
    }
    /// Only announce objects in the walking path. Off announces everything nearby.
    var pathOnly: Bool = UserDefaults.standard.object(forKey: Keys.pathOnly) as? Bool ?? true {
        didSet {
            alerts.pathOnly = pathOnly
            UserDefaults.standard.set(pathOnly, forKey: Keys.pathOnly)
        }
    }
    /// Ultra-wide lens: wider view, but smaller objects that are harder to detect.
    var ultraWide: Bool = UserDefaults.standard.bool(forKey: Keys.ultraWide) {
        didSet {
            camera.setUltraWide(ultraWide)
            UserDefaults.standard.set(ultraWide, forKey: Keys.ultraWide)
        }
    }

    private enum Keys {
        static let labels = "enabledLabels", confidence = "minConfidence", ultraWide = "ultraWide", pathOnly = "pathOnly"
    }

    @ObservationIgnored let camera = CameraManager()
    @ObservationIgnored private let detector = ObstacleDetector()
    @ObservationIgnored private let alerts = AlertManager()
    @ObservationIgnored private let tracker = ObjectTracker()
    @ObservationIgnored private let motion = CMMotionManager()
    @ObservationIgnored private let modelQueue = DispatchQueue(label: "visionaid.model", qos: .userInitiated)
    @ObservationIgnored private var frameTimes: [CFTimeInterval] = []

    init() {
        camera.onFrame = { [weak self] buffer in self?.handle(buffer) }
        detector.enabledLabels = enabledLabels
        detector.minConfidence = Float(minConfidence)
        camera.setUltraWide(ultraWide)
        alerts.pathOnly = pathOnly
        motion.deviceMotionUpdateInterval = 1.0 / 30
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
            motion.startDeviceMotionUpdates()
            camera.start()
        } else {
            motion.stopDeviceMotionUpdates()
            camera.stop()
            alerts.stop()
            tracker.reset()
            detections = []
            fps = 0
        }
    }

    /// Loads off the main thread: Core ML can take a long time preparing a model for the Neural Engine,
    /// especially on the first launch after installing, and the UI must stay up meanwhile.
    private func loadModel() {
        let size = modelSize
        isLoadingModel = true
        modelQueue.async { [weak self] in
            guard let self else { return }
            var failure: String?
            do {
                try self.detector.load(size)
            } catch {
                failure = error.localizedDescription
            }
            DispatchQueue.main.async {
                if let failure { self.errorMessage = failure }
                if self.modelSize == size { self.isLoadingModel = false }
            }
        }
    }

    /// Runs on the camera frame queue.
    private func handle(_ buffer: CVPixelBuffer) {
        let size = CGSize(width: CVPixelBufferGetWidth(buffer), height: CVPixelBufferGetHeight(buffer))
        let gravity = motion.deviceMotion.map { SIMD3($0.gravity.x, $0.gravity.y, $0.gravity.z) }
        let geometry = CameraGeometry(fieldOfView: camera.fieldOfView, imageSize: size, gravity: gravity)

        let start = CACurrentMediaTime()
        let raw = detector.detect(buffer).map { geometry.locate($0) }
        let elapsed = (CACurrentMediaTime() - start) * 1000
        let results = tracker.update(raw)

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
