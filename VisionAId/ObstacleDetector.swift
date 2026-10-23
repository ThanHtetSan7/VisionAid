import CoreML
import Vision

/// Runs a YOLOv8 Core ML model (exported with NMS) on camera frames.
final class ObstacleDetector {
    enum ModelSize: String, CaseIterable, Identifiable {
        case nano = "yolov8n"
        case small = "yolov8s"
        var id: String { rawValue }
        var title: String { self == .nano ? "YOLOv8n" : "YOLOv8s" }
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

    var confidenceThreshold: Double = 0.4 { didSet { applyThresholds() } }
    var iouThreshold: Double = 0.45 { didSet { applyThresholds() } }

    func load(_ size: ModelSize) throws {
        // Xcode compiles .mlpackage into .mlmodelc inside the app bundle.
        guard let url = Bundle.main.url(forResource: size.rawValue, withExtension: "mlmodelc") else {
            throw LoadError.missingModel(size.rawValue)
        }
        let config = MLModelConfiguration()
        config.computeUnits = .all // let Core ML use the Neural Engine
        let vnModel = try VNCoreMLModel(for: MLModel(contentsOf: url, configuration: config))

        let newRequest = VNCoreMLRequest(model: vnModel)
        newRequest.imageCropAndScaleOption = .scaleFill

        lock.lock()
        model = vnModel
        request = newRequest
        lock.unlock()
        applyThresholds()
    }

    /// Returns obstacle detections for one frame. Called on the camera's frame queue.
    func detect(_ pixelBuffer: CVPixelBuffer) -> [Detection] {
        lock.lock()
        defer { lock.unlock() }
        guard let request else { return [] }

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up)
        do { try handler.perform([request]) } catch { return [] }

        let observations = request.results as? [VNRecognizedObjectObservation] ?? []
        return observations.compactMap { obs in
            guard let top = obs.labels.first, Obstacles.priority[top.identifier] != nil else { return nil }
            // Vision uses a bottom-left origin; flip to top-left for SwiftUI.
            let b = obs.boundingBox
            let box = CGRect(x: b.minX, y: 1 - b.maxY, width: b.width, height: b.height)
            return Detection(label: top.identifier, confidence: top.confidence, box: box)
        }
    }

    private func applyThresholds() {
        lock.lock()
        model?.featureProvider = ThresholdProvider(iou: iouThreshold, confidence: confidenceThreshold)
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
