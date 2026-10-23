import Foundation
import CoreGraphics

/// One detected obstacle. `box` is normalised (0–1) with a top-left origin.
struct Detection: Identifiable {
    let id = UUID()
    let label: String
    let confidence: Float
    let box: CGRect
    /// Horizontal bearing in degrees from straight ahead (negative = left).
    var angle: Double = 0
    /// Estimated distance in metres.
    var distance: Double?
}

/// Which COCO classes count as obstacles, how dangerous each is, and their typical size.
enum Obstacles {
    /// Higher number = higher risk = spoken first.
    static let priority: [String: Int] = [
        "car": 3, "bus": 3, "truck": 3, "motorcycle": 3, "train": 3,
        "bicycle": 2, "dog": 2, "horse": 2,
        "person": 1, "cat": 1, "bench": 1, "chair": 1,
        "fire hydrant": 1, "potted plant": 1, "suitcase": 1, "parking meter": 1
    ]

    /// Typical real-world height in metres, used to estimate distance from box height.
    static let realHeight: [String: Double] = [
        "car": 1.5, "bus": 3.0, "truck": 3.0, "motorcycle": 1.1, "train": 3.5,
        "bicycle": 1.0, "dog": 0.5, "horse": 1.6,
        "person": 1.7, "cat": 0.3, "bench": 0.8, "chair": 0.9,
        "fire hydrant": 0.7, "potted plant": 0.8, "suitcase": 0.6, "parking meter": 1.3
    ]

    /// Names that sound more natural when spoken.
    static let spokenName: [String: String] = [
        "bicycle": "bike", "motorcycle": "motorbike", "potted plant": "plant", "parking meter": "post"
    ]

    /// Objects nearer than this get a "Caution" alert and may interrupt speech.
    static let closeDistance = 2.5
    /// Objects further away than this are ignored.
    static let maxDistance = 10.0
}

/// Turns a box into a bearing and distance using a pinhole camera model.
struct CameraGeometry {
    /// Camera field of view in degrees, measured across the long side of the image.
    let fieldOfView: Double
    let imageSize: CGSize

    /// Focal length in pixels.
    private var focalPx: Double {
        let longSide = Double(max(imageSize.width, imageSize.height))
        return (longSide / 2) / tan(fieldOfView * .pi / 360)
    }

    func locate(_ detection: Detection) -> Detection {
        var d = detection
        let dx = (Double(d.box.midX) - 0.5) * Double(imageSize.width)
        d.angle = atan(dx / focalPx) * 180 / .pi

        if let realHeight = Obstacles.realHeight[d.label] {
            let boxPx = Double(d.box.height * imageSize.height)
            if boxPx > 0 {
                var estimate = realHeight * focalPx / boxPx
                // Cut off at both top and bottom of frame: it's right in front of the user.
                if d.box.minY < 0.02 && d.box.maxY > 0.98 {
                    estimate = min(estimate, Obstacles.closeDistance)
                }
                d.distance = estimate
            }
        }
        return d
    }
}
