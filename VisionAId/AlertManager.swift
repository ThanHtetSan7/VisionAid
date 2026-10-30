import AVFoundation

/// Turns detections into short spoken warnings, without repeating or overwhelming the user.
final class AlertManager {
    var muted = false
    /// Only announce objects in the walking path, not everything in view.
    var pathOnly = true
    /// Seconds before the same object is announced again.
    var cooldown: TimeInterval = 8
    /// Quiet seconds kept between routine announcements.
    var minimumGap: TimeInterval = 2

    private let synth = AVSpeechSynthesizer()
    private var lastSpoken: [UUID: (time: Date, distance: Double, wasClose: Bool)] = [:]
    private var lastUtterance = Date.distantPast

    init() {
        // .playback keeps speech audible with the silent switch on; ducks music instead of stopping it.
        let audio = AVAudioSession.sharedInstance()
        try? audio.setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try? audio.setActive(true)
    }

    /// Call on the main thread with the latest frame's tracked detections.
    func process(_ detections: [Detection]) {
        guard !muted else { return }
        let now = Date()

        // Skip objects already announced, so they can't block the next most important one.
        let alert = detections
            .filter { !pathOnly || $0.inPath }
            .compactMap { Alert($0) }
            .filter { isDue($0, now: now) }
            .max { $0.score < $1.score }
        guard let alert else { return }

        if !alert.isClose && now.timeIntervalSince(lastUtterance) < minimumGap { return }

        // Only interrupt current speech for a close, high-risk object.
        if synth.isSpeaking {
            guard alert.isClose && alert.priority >= 2 else { return }
            synth.stopSpeaking(at: .immediate)
        }

        lastSpoken = lastSpoken.filter { now.timeIntervalSince($0.value.time) < 30 }
        lastSpoken[alert.id] = (now, alert.distance, alert.isClose)
        lastUtterance = now
        let utterance = AVSpeechUtterance(string: alert.phrase)
        utterance.rate = 0.55
        synth.speak(utterance)
    }

    /// New objects are due. Known ones only after the cooldown, or if they became a bigger danger.
    private func isDue(_ alert: Alert, now: Date) -> Bool {
        guard let last = lastSpoken[alert.id] else { return true }
        return now.timeIntervalSince(last.time) >= cooldown
            || last.distance - alert.distance >= 2
            || (alert.isClose && !last.wasClose)
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

    let id: UUID
    let label: String
    let zone: Zone
    /// Nil for classes whose real-world size is unknown.
    let measured: Double?
    /// Distance used for ranking and debouncing; unknown counts as far away.
    let distance: Double
    let priority: Int
    let score: Double

    init?(_ d: Detection) {
        let dist = d.distance ?? Obstacles.maxDistance
        guard dist <= Obstacles.maxDistance else { return nil }

        let p = Obstacles.risk(of: d.label)
        id = d.id
        label = d.label
        priority = p
        measured = d.distance
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

    var isClose: Bool { (measured ?? .infinity) <= Obstacles.closeDistance }

    var phrase: String {
        let raw = Obstacles.spokenName[label] ?? label
        let name = raw.prefix(1).uppercased() + raw.dropFirst()
        var base = "\(name) \(zone.rawValue)"
        if let measured {
            let metres = max(1, Int(measured.rounded()))
            base += ", \(metres) \(metres == 1 ? "metre" : "metres")"
        }
        return isClose ? "Caution, \(base)" : base
    }
}
