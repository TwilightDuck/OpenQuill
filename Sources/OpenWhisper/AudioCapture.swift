@preconcurrency import AVFoundation
import Foundation
import FlowCore

/// The audio tap is the sole owner of the converter. The lock protects samples read by the UI.
private final class AudioSink: @unchecked Sendable {
    private let lock = NSLock()
    private let converter: AVAudioConverter
    private let format: AVAudioFormat
    private var samples: [Float] = []
    private var energy: Float = 0
    private var failure: String?
    private var activity: RecordingActivity
    init(input: AVAudioFormat, maximumSeconds: Double, thresholdDB: Double) throws {
        activity = RecordingActivity(maximumSeconds: maximumSeconds, thresholdDB: thresholdDB)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false),
              let converter = AVAudioConverter(from: input, to: format) else {
            throw FlowError.message("This microphone’s audio format is unsupported.")
        }
        self.format = format; self.converter = converter
    }
    func append(_ buffer: AVAudioPCMBuffer) {
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * 16000 / buffer.format.sampleRate + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: capacity) else { return }
        var supplied = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if supplied { status.pointee = .noDataNow; return nil }
            supplied = true; status.pointee = .haveData; return buffer
        }
        lock.lock(); defer { lock.unlock() }
        if let error { failure = error.localizedDescription; return }
        guard let channel = output.floatChannelData?.pointee else { return }
        let values = Array(UnsafeBufferPointer(start: channel, count: Int(output.frameLength)))
        // Bound the audio buffer to the same captured limit used by the controller.
        let accepted = values.prefix(max(0, Int(16000 * activity.maximumSeconds) - samples.count))
        samples.append(contentsOf: accepted)
        if !accepted.isEmpty {
            energy = sqrt(accepted.reduce(Float(0)) { $0 + $1 * $1 } / Float(accepted.count))
            activity.append(rms: energy, duration: Double(accepted.count) / 16000)
        }
    }
    func snapshot() -> (samples: [Float], error: String?) {
        lock.lock(); defer { lock.unlock() }
        return (samples, failure)
    }
    func status() -> (level: Float, activity: RecordingActivity) {
        lock.lock(); defer { lock.unlock() }
        // A logarithmic meter stays responsive for quieter voices.
        let db = 20 * log10(max(energy, 0.00001))
        return (min(1, max(0, (db + 55) / 45)), activity)
    }
}

@MainActor
final class AudioCapture {
    private var engine: AVAudioEngine?
    private var sink: AudioSink?
    var status: (level: Float, activity: RecordingActivity) { sink?.status() ?? (0, RecordingActivity()) }
    func start(maximumSeconds: Double, thresholdDB: Double) throws {
        let engine = AVAudioEngine()
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else { throw FlowError.message("No microphone is available. Check your input device in System Settings.") }
        let sink = try AudioSink(input: format, maximumSeconds: maximumSeconds, thresholdDB: thresholdDB)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in sink.append(buffer) }
        do { try engine.start() } catch { input.removeTap(onBus: 0); throw error }
        self.engine = engine; self.sink = sink
    }
    func stop() throws -> [Float] {
        engine?.inputNode.removeTap(onBus: 0)
        engine?.stop(); engine = nil
        let result = sink?.snapshot(); sink = nil
        if let error = result?.error { throw FlowError.message(error) }
        return result?.samples ?? []
    }
    func cancel() { _ = try? stop() }
}

enum FlowError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
