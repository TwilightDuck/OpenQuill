import Foundation

/// Quiet-pause tracking is driven by captured audio time, never the UI timer.
public struct RecordingActivity: Sendable {
    public let maximumSeconds: Double
    public private(set) var seconds = 0.0
    private var voicedSeconds = 0.0
    private var hasSpoken = false
    private var lastVoice: Double?
    public let threshold: Float
    public init(maximumSeconds: Double = 180, thresholdDB: Double = -42) {
        self.maximumSeconds = maximumSeconds.isFinite ? min(1800, max(60, maximumSeconds)) : 180
        threshold = Float(pow(10, thresholdDB / 20))
    }
    public mutating func append(rms: Float, duration: Double) {
        guard duration > 0 else { return }
        seconds += duration
        if rms >= threshold {
            voicedSeconds += duration
            if voicedSeconds >= 0.25 { hasSpoken = true }
            if hasSpoken { lastVoice = seconds }
        } else { voicedSeconds = 0 }
    }
    public var silenceSeconds: Double? { lastVoice.map { max(0, seconds - $0) } }
    public func shouldStop(silenceEnabled: Bool, delay: Double) -> Bool {
        seconds >= maximumSeconds || (silenceEnabled && (silenceSeconds ?? 0) >= max(2, delay))
    }
}

public struct SpeechProfile: Sendable {
    public let recordings: [Dictation]
    public init(records: [Dictation]) { recordings = records.filter { $0.bundleID != "import" } }
    public var words: Int { recordings.reduce(0) { $0 + $1.wordCount } }
    public var seconds: Double { recordings.reduce(0) { $0 + $1.audioSeconds } }
    public var pace: Int { seconds > 0 ? Int(Double(words) / seconds * 60) : 0 }
    public var correctedCount: Int { recordings.filter { $0.corrected != nil && $0.corrected != $0.text }.count }
    public var languages: [(name: String, words: Int)] {
        Dictionary(grouping: recordings, by: \.language).map { language, records in
            (language, records.reduce(0) { $0 + $1.wordCount })
        }.sorted { $0.words == $1.words ? $0.name < $1.name : $0.words > $1.words }
    }
    /// These are observations of transcripts, not a judgment of pronunciation or fluency.
    public var phrases: [(name: String, count: Int)] {
        let text = recordings.map { $0.corrected ?? $0.text }.joined(separator: "\n")
        return ["um", "uh", "you know", "sort of", "kind of", "eh", "euh", "zeg maar"].compactMap { phrase in
            let pattern = "(?<![\\p{L}\\p{N}_])" + NSRegularExpression.escapedPattern(for: phrase) + "(?![\\p{L}\\p{N}_])"
            guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
            let count = regex.numberOfMatches(in: text, range: NSRange(text.startIndex..., in: text))
            return count > 0 ? (phrase, count) : nil
        }.sorted { $0.count == $1.count ? $0.name < $1.name : $0.count > $1.count }
    }
}
