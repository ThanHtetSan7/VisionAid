import Foundation
import CoreGraphics

/// Follows detections across frames so one-frame false positives are ignored
/// and boxes, bearings and distances stay steady instead of jittering.
final class ObjectTracker {
    /// Frames an object must be seen in before it is reported.
    var minHits = 3
    /// Frames an object may go unseen before it is dropped.
    var maxMisses = 2
    /// How much each new frame moves the smoothed values (0–1; higher = more responsive).
    var smoothing = 0.5

    private struct Track {
        var detection: Detection
        var hits = 1
        var misses = 0
    }

    private var tracks: [Track] = []
    private let lock = NSLock()

    /// Matches this frame's detections to existing tracks and returns the confirmed ones.
    func update(_ detections: [Detection]) -> [Detection] {
        lock.lock()
        defer { lock.unlock() }

        // Pair tracks and detections of the same class, best overlap first.
        var pairs: [(track: Int, detection: Int, iou: Double)] = []
        for (t, track) in tracks.enumerated() {
            for (d, det) in detections.enumerated() where det.label == track.detection.label {
                let iou = track.detection.box.iou(det.box)
                if iou > 0.3 { pairs.append((t, d, iou)) }
            }
        }
        pairs.sort { $0.iou > $1.iou }

        var usedTracks = Set<Int>(), usedDetections = Set<Int>()
        for pair in pairs where !usedTracks.contains(pair.track) && !usedDetections.contains(pair.detection) {
            usedTracks.insert(pair.track)
            usedDetections.insert(pair.detection)
            tracks[pair.track].detection = blend(tracks[pair.track].detection, detections[pair.detection])
            tracks[pair.track].hits += 1
            tracks[pair.track].misses = 0
        }

        for t in tracks.indices where !usedTracks.contains(t) {
            tracks[t].misses += 1
        }
        tracks.removeAll { $0.misses > maxMisses }
        for (d, det) in detections.enumerated() where !usedDetections.contains(d) {
            tracks.append(Track(detection: det))
        }

        return tracks.filter { $0.hits >= minHits }.map(\.detection)
    }

    func reset() {
        lock.lock()
        tracks = []
        lock.unlock()
    }

    /// Moves the tracked values towards the new measurement, keeping the track's id.
    private func blend(_ old: Detection, _ new: Detection) -> Detection {
        let a = smoothing
        func mix(_ x: Double, _ y: Double) -> Double { x + (y - x) * a }
        func mix(_ x: CGFloat, _ y: CGFloat) -> CGFloat { x + (y - x) * CGFloat(a) }

        var d = new
        d.id = old.id
        d.box = CGRect(x: mix(old.box.minX, new.box.minX),
                       y: mix(old.box.minY, new.box.minY),
                       width: mix(old.box.width, new.box.width),
                       height: mix(old.box.height, new.box.height))
        d.angle = mix(old.angle, new.angle)
        d.pathScore = mix(old.pathScore, new.pathScore)
        if let o = old.distance, let n = new.distance {
            d.distance = mix(o, n)
        }
        return d
    }
}

extension CGRect {
    /// Intersection over union: 0 = no overlap, 1 = identical.
    func iou(_ other: CGRect) -> Double {
        let inter = intersection(other)
        guard !inter.isNull else { return 0 }
        let interArea = inter.width * inter.height
        let union = width * height + other.width * other.height - interArea
        return union > 0 ? Double(interArea / union) : 0
    }
}
