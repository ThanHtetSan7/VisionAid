import CoreML
import Vision

/// Runs a YOLO Core ML model (exported with NMS) on camera frames.
final class ObstacleDetector {
    enum ModelSize: String, CaseIterable, Identifiable {
        case yolo11s, yolo11m
        var id: String { rawValue }
        var title: String { rawValue.replacingOccurrences(of: "yolo", with: "YOLO") }
    }

    enum LoadError: LocalizedError {
        case missingModel(String)
        var errorDescription: String? {
            switch self {
            case .missingModel(let name): return "\(name).mlpackage is not in the app target."
            }
        }
    }

    private var model: VNCoreMLModel?
    private var request: VNCoreMLRequest?
    private let lock = NSLock()

    /// Guards the user's filter settings separately, so changing them never waits on inference.
    private let filterLock = NSLock()
    private var _enabledLabels = Obstacles.defaultEnabled
    private var _minConfidence: Float = 0.5

    /// Classes to report; everything else is discarded.
    var enabledLabels: Set<String> {
        get { filterLock.withLock { _enabledLabels } }
        set { filterLock.withLock { _enabledLabels = newValue } }
    }

    /// Detections below this confidence are discarded.
    var minConfidence: Float {
        get { filterLock.withLock { _minConfidence } }
        set { filterLock.withLock { _minConfidence = newValue } }
    }

    /// Thresholds for the model's built-in NMS. Confidence stays low here; `minConfidence` does the real filtering.
    private let nmsConfidence = 0.2
    private let iouThreshold = 0.45

    func load(_ size: ModelSize) throws {
        // Xcode compiles .mlpackage into .mlmodelc inside the app bundle.
        guard let url = Bundle.main.url(forResource: size.rawValue, withExtension: "mlmodelc") else {
            throw LoadError.missingModel(size.rawValue)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all // let Core ML use the Neural Engine
        let vnModel = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))

        let newRequest = VNCoreMLRequest(model: vnModel)
        // Letterbox like YOLO's training images; stretching a 9:16 frame to a square distorts every object.
        // Vision maps the boxes back to the full frame for us.
        newRequest.imageCropAndScaleOption = .scaleFit

        lock.lock()
        model = vnModel
        request = newRequest
        lock.unlock()
        applyThresholds()
    }

    /// Returns obstacle detections for one frame. Called on the camera's frame queue.
    func detect(_ pixelBuffer: CVPixelBuffer) -> [Detection] {
        let (labels, minConfidence) = filterLock.withLock { (_enabledLabels, _minConfidence) }

        lock.lock()
        defer { lock.unlock() }
        guard let request else { return [] }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }

        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        return observations.compactMap { obs in
            guard let top = obs.labels.first,
                  top.confidence >= minConfidence,
                  labels.contains(top.identifier) else { return nil }
            // Vision uses a bottom-left origin; flip to top-left for SwiftUI.
            let b = obs.boundingBox
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            return Detection(label: top.identifier, confidence: top.confidence, box: box)
        }
    }

    private func applyThresholds() {
        lock.lock()
        model?.featureProvider = ThresholdProvider(iou: iouThreshold, confidence: nmsConfidence)
        lock.unlock()
    }
}

/// Feeds the IoU and confidence thresholds into the model's built-in NMS.
private final class ThresholdProvider: MLFeatureProvider {
    private let values: [String: MLFeatureValue]

    init(iou: Double, confidence: Double) {
        values = ["iouThreshold": MLFeatureValue(double: iou),
                  "confidenceThreshold": MLFeatureValue(double: confidence)]
    }

    var featureNames: Set<String> { Set(values.keys) }
    func featureValue(for featureName: String) -> MLFeatureValue? { values[featureName] }
}
