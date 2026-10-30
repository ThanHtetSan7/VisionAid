import Foundation
import CoreGraphics
import simd

/// One detected obstacle. `box` is normalised (0–1) with a top-left origin.
struct Detection: Identifiable {
    var id = UUID()
    let label: String
    let confidence: Float
    var box: CGRect
    /// Horizontal bearing in degrees from straight ahead (negative = left).
    var angle: Double = 0
    /// Estimated distance in metres.
    var distance: Double?
    /// How sure we are that it is in the walking path (0–1), smoothed across frames.
    var pathScore: Double = 0
    var inPath: Bool { pathScore >= 0.5 }
}

/// Which COCO classes count as obstacles, how dangerous each is, and their typical size.
enum Obstacles {
    /// Every class the COCO-trained YOLO models can detect, in model order.
    static let allLabels = [
        "person", "bicycle", "car", "motorcycle", "airplane", "bus", "train", "truck", "boat",
        "traffic light", "fire hydrant", "stop sign", "parking meter", "bench", "bird", "cat", "dog",
        "horse", "sheep", "cow", "elephant", "bear", "zebra", "giraffe", "backpack", "umbrella",
        "handbag", "tie", "suitcase", "frisbee", "skis", "snowboard", "sports ball", "kite",
        "baseball bat", "baseball glove", "skateboard", "surfboard", "tennis racket", "bottle",
        "wine glass", "cup", "fork", "knife", "spoon", "bowl", "banana", "apple", "sandwich", "orange",
        "broccoli", "carrot", "hot dog", "pizza", "donut", "cake", "chair", "couch", "potted plant",
        "bed", "dining table", "toilet", "tv", "laptop", "mouse", "remote", "keyboard", "cell phone",
        "microwave", "oven", "toaster", "sink", "refrigerator", "book", "clock", "vase", "scissors",
        "teddy bear", "hair drier", "toothbrush"
    ]

    /// Classes switched on until the user changes them: the ones that matter when walking.
    static let defaultEnabled = Set(priority.keys)

    /// Higher number = higher risk = spoken first.
    static let priority: [String: Int] = [
        "car": 3, "bus": 3, "truck": 3, "motorcycle": 3, "train": 3,
        "bicycle": 2, "dog": 2, "horse": 2,
        "person": 1, "cat": 1, "bench": 1, "chair": 1,
        "fire hydrant": 1, "potted plant": 1, "suitcase": 1, "parking meter": 1
    ]

    /// Risk for any class; ones not listed above are low risk.
    static func risk(of label: String) -> Int { priority[label] ?? 1 }

    /// Typical real-world height in metres, used to estimate distance from box height.
    static let realHeight: [String: Double] = [
        "car": 1.5, "bus": 3.0, "truck": 3.0, "motorcycle": 1.1, "train": 3.5,
        "bicycle": 1.0, "dog": 0.5, "horse": 1.6,
        "person": 1.7, "cat": 0.3, "bench": 0.8, "chair": 0.9,
        "fire hydrant": 0.7, "potted plant": 0.8, "suitcase": 0.6, "parking meter": 1.3,
        "sheep": 0.9, "cow": 1.4, "couch": 0.85, "dining table": 0.75, "bed": 0.6,
        "toilet": 0.75, "refrigerator": 1.7, "backpack": 0.5, "stop sign": 0.75
    ]

    /// Names that sound more natural when spoken.
    static let spokenName: [String: String] = [
        "bicycle": "bike", "motorcycle": "motorbike", "potted plant": "plant", "parking meter": "post"
    ]

    /// Objects nearer than this get a "Caution" alert and may interrupt speech.
    static let closeDistance = 2.5
    /// Objects further away than this are ignored.
    static let maxDistance = 10.0

    /// Height of the camera above the ground in metres (chest-mounted phone).
    static let cameraHeight = 1.3
    /// Half the width of the walking corridor in metres.
    static let pathHalfWidth = 0.75
    /// Bearing treated as "in the path" when an object's position on the ground is unknown.
    static let pathBearing = 10.0
    /// Ground positions further away than this are too sensitive to tilt to trust.
    static let maxGroundDistance = 15.0
    /// Classes that stand on the ground, so the bottom of their box marks where they are.
    static let onGround = Set(realHeight.keys).subtracting(["stop sign"])
}

/// Turns a box into a bearing, distance and path position using a pinhole camera model.
struct CameraGeometry {
    /// Camera field of view in degrees, measured across the long side of the image.
    let fieldOfView: Double
    let imageSize: CGSize
    /// Gravity in device coordinates, used to find the ground. Nil if unavailable.
    var gravity: SIMD3<Double>?

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
                // Cut off by the bottom of the frame: it's right in front of the user.
                if d.box.maxY > 0.98 {
                    estimate = min(estimate, Obstacles.closeDistance)
                }
                d.distance = estimate
            }
        }

        // Fall back to bearing alone, and improve on it where the ground position is known.
        d.pathScore = abs(d.angle) <= Obstacles.pathBearing ? 1 : 0
        if Obstacles.onGround.contains(d.label), d.box.maxY <= 0.98,
           let centre = groundPoint(x: Double(d.box.midX), y: Double(d.box.maxY)),
           centre.forward > 0, hypot(centre.forward, centre.right) <= Obstacles.maxGroundDistance,
           let near = groundPoint(x: Double(d.box.midX - d.box.width / 4), y: Double(d.box.maxY)),
           let far = groundPoint(x: Double(d.box.midX + d.box.width / 4), y: Double(d.box.maxY)) {
            d.distance = hypot(centre.forward, centre.right)
            // Only the middle of the box: the corners of an angled car aren't on the ground there.
            let inCorridor = min(near.right, far.right) <= Obstacles.pathHalfWidth
                && max(near.right, far.right) >= -Obstacles.pathHalfWidth
            d.pathScore = inCorridor ? 1 : 0
        }
        return d
    }

    /// Where a point in the image (0–1, top-left origin) meets the ground, in metres from the
    /// user's feet. Nil at or above the horizon, or if the phone's tilt isn't known.
    func groundPoint(x: Double, y: Double) -> (forward: Double, right: Double)? {
        guard let gravity, simd_length(gravity) > 0 else { return nil }
        let down = simd_normalize(gravity)

        // Device axes: x right, y up, z out of the screen, so the back camera looks along -z.
        let ray = simd_normalize(SIMD3((x - 0.5) * Double(imageSize.width),
                                       (0.5 - y) * Double(imageSize.height),
                                       -focalPx))
        let descent = simd_dot(ray, down)
        guard descent > 0.01 else { return nil }
        let point = ray * (Obstacles.cameraHeight / descent)

        let axis = SIMD3<Double>(0, 0, -1)
        let level = axis - down * simd_dot(axis, down)
        guard simd_length(level) > 0.1 else { return nil } // camera pointing straight down
        let forward = simd_normalize(level)
        let right = simd_cross(forward, -down)
        return (simd_dot(point, forward), simd_dot(point, right))
    }
}
