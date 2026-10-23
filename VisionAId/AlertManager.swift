import AVFoundation

/// Turns detections into short spoken warnings, without repeating or overwhelming the user.
final class AlertManager {
    var muted = false
    /// Seconds before the same object in the same zone is announced again.
    var cooldown: TimeInterval = 4

    private let synth = AVSpeechSynthesizer()
    private var lastSpoken: [String: (time: Date, distance: Double)] = [:]

    init() {
        // .playback keeps speech audible with the silent switch on; ducks music instead of stopping it.
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
    }

    /// Call on the main thread with the latest frame's located detections.
    func process(_ detections: [Detection]) {
        guard !muted,
              let alert = detections.compactMap({ Alert($0) }).max(by: { $0.score < $1.score })
        else { return }

        // Debounce: skip if recently said, unless it has come at least 2 m closer.
        let now = Date()
        if let last = lastSpoken[alert.key],
           now.timeIntervalSince(last.time) < cooldown,
           last.distance - alert.distance < 2 {
            return
        }

        // Only interrupt current speech for a close, high-risk object.
        if synth.isSpeaking {
            guard alert.isClose && alert.priority >= 2 else { return }
            synth.stopSpeaking(at: .immediate)
        }

        lastSpoken[alert.key] = (now, alert.distance)
        let utterance = AVSpeechUtterance(string: alert.phrase)
        utterance.rate = 0.55
        synth.speak(utterance)
    }

    func stop() {
        synth.stopSpeaking(at: .immediate)
    }
}

private struct Alert {
    enum Zone: String {
        case farLeft = "on your left", left = "slightly left", ahead = "ahead",
             right = "slightly right", farRight = "on your right"
    }

    let label: String
    let zone: Zone
    let distance: Double
    let priority: Int
    let score: Double

    init?(_ d: Detection) {
        guard let p = Obstacles.priority[d.label] else { return nil }
        let dist = d.distance ?? Obstacles.maxDistance
        guard dist <= Obstacles.maxDistance else { return nil }

        label = d.label
        priority = p
        distance = dist
        switch d.angle {
        case ..<(-20.0): zone = .farLeft
        case -20.0 ..< -7.0: zone = .left
        case -7.0 ... 7.0: zone = .ahead
        case 7.0 ... 20.0: zone = .right
        default: zone = .farRight
        }
        // Risk first, then nearness, with a bonus for being straight ahead.
        score = Double(p) * 10 + (Obstacles.maxDistance - dist) + (zone == .ahead ? 3 : 0)
    }

    var isClose: Bool { distance <= Obstacles.closeDistance }
    var key: String { "\(label)-\(zone.rawValue)" }

    var phrase: String {
        let raw = Obstacles.spokenName[label] ?? label
        let name = raw.prefix(1).uppercased() + raw.dropFirst()
        let metres = max(1, Int(distance.rounded()))
        let base = "\(name) \(zone.rawValue), \(metres) \(metres == 1 ? "metre" : "metres")"
        return isClose ? "Caution, \(base)" : base
    }
}
