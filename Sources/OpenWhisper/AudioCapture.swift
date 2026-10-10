@preconcurrency import AVFoundation
import Foundation
import FlowCore
import CoreMedia

struct AudioInputDevice: Identifiable {
    let id: String
    let name: String
    static var systemInputName: String? { AVCaptureDevice.default(for: .audio)?.localizedName }

    static func available() -> [AudioInputDevice] {
        captureDevices.map { AudioInputDevice(id: $0.uniqueID, name: $0.localizedName) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    static var captureDevices: [AVCaptureDevice] {
        AVCaptureDevice.DiscoverySession(deviceTypes: [.microphone], mediaType: .audio, position: .unspecified).devices
    }
}

/// The serial capture delegate owns conversion; the lock protects samples read by the UI.
private final class AudioSink: NSObject, AVCaptureAudioDataOutputSampleBufferDelegate, @unchecked Sendable {
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private let format: AVAudioFormat
    private var samples: [Float] = []
    private var energy: Float = 0
    private var failure: String?
    private var activity: RecordingActivity
    init(maximumSeconds: Double, thresholdDB: Double) throws {
        activity = RecordingActivity(maximumSeconds: maximumSeconds, thresholdDB: thresholdDB)
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16000, channels: 1, interleaved: false) else { throw FlowError.message("Could not prepare microphone audio.") }
        self.format = format
        super.init()
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        guard let description = CMSampleBufferGetFormatDescription(sampleBuffer) else { fail("This microphone’s audio format is unsupported."); return }
        let inputFormat = AVAudioFormat(cmAudioFormatDescription: description)
        let frames = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frames > 0, frames <= Int(Int32.max),
              let buffer = AVAudioPCMBuffer(pcmFormat: inputFormat, frameCapacity: AVAudioFrameCount(frames)) else { return }
        buffer.frameLength = AVAudioFrameCount(frames)
        guard CMSampleBufferCopyPCMDataIntoAudioBufferList(sampleBuffer, at: 0, frameCount: Int32(frames), into: buffer.mutableAudioBufferList) == noErr else { fail("Could not read microphone audio."); return }
        append(buffer)
    }
    private func fail(_ message: String) {
        lock.lock(); failure = message; lock.unlock()
    }
    private func append(_ buffer: AVAudioPCMBuffer) {
        if converter?.inputFormat != buffer.format { converter = AVAudioConverter(from: buffer.format, to: format) }
        guard let converter else { fail("This microphone’s audio format is unsupported."); return }
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
    private var session: AVCaptureSession?
    private var sink: AudioSink?
    private let audioQueue = DispatchQueue(label: "OpenWhisper.microphone")
    var status: (level: Float, activity: RecordingActivity) { sink?.status() ?? (0, RecordingActivity()) }
    func start(maximumSeconds: Double, thresholdDB: Double, deviceUID: String? = nil) throws {
        let device = deviceUID.flatMap { uid in AudioInputDevice.captureDevices.first { $0.uniqueID == uid } } ?? (deviceUID == nil ? AVCaptureDevice.default(for: .audio) : nil)
        guard let device else { throw FlowError.message("Your microphone is unavailable. Choose another input device or Automatic in Settings.") }
        let input = try AVCaptureDeviceInput(device: device)
        let session = AVCaptureSession()
        let output = AVCaptureAudioDataOutput()
        let sink = try AudioSink(maximumSeconds: maximumSeconds, thresholdDB: thresholdDB)
        guard session.canAddInput(input), session.canAddOutput(output) else { throw FlowError.message("Could not use \(device.localizedName). Choose another input device in Settings.") }
        session.addInput(input); session.addOutput(output)
        output.setSampleBufferDelegate(sink, queue: audioQueue)
        session.startRunning()
        guard session.isRunning else { throw FlowError.message("Could not start \(device.localizedName). Check your microphone in Settings.") }
        self.session = session; self.sink = sink
    }
    func stop() throws -> [Float] {
        session?.stopRunning(); session = nil
        let result = audioQueue.sync { sink?.snapshot() }; sink = nil
        if let error = result?.error { throw FlowError.message(error) }
        if result?.samples.isEmpty == true { throw FlowError.message("No audio arrived from the microphone. Check the selected input; a MacBook’s built-in microphone needs its lid open.") }
        return result?.samples ?? []
    }
    func cancel() { _ = try? stop() }
}

enum FlowError: LocalizedError {
    case message(String)
    var errorDescription: String? { if case let .message(text) = self { text } else { nil } }
}
