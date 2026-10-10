import Foundation
@preconcurrency import WhisperKit
import FluidAudio
import NaturalLanguage

enum SpeechModel: String, CaseIterable, Identifiable, Codable, Sendable {
    case parakeet = "parakeet-ultra"
    case whisper = "large-v3"
    case turbo = "large-v3-v20240930_turbo"
    var id: String { rawValue }
    var title: String {
        switch self {
        case .parakeet: "Parakeet Ultra"
        case .whisper: "Whisper large-v3"
        case .turbo: "Whisper large-v3 Turbo"
        }
    }
    var detail: String {
        switch self {
        case .parakeet: "Fast everyday dictation · ~630 MB"
        case .whisper: "Full multilingual model · ~3 GB · slower"
        case .turbo: "Faster Whisper decoder · ~1.6 GB"
        }
    }
}

struct SpeechOutput: Codable, Sendable {
    let text: String
    let language: String
    let audioSeconds: Double
    let processingSeconds: Double
}

actor SpeechEngine {
    static let root = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appendingPathComponent("WisperFlow", isDirectory: true)
    private var whisper: WhisperKit?
    private var parakeet: AsrManager?
    private var loaded: SpeechModel?

    static func path(for model: SpeechModel) -> URL? {
        if model == .parakeet { return root.appendingPathComponent("Models/parakeet-ultra") }
        let pointer = root.appendingPathComponent("Models/\(model.rawValue).path")
        guard let path = try? String(contentsOf: pointer, encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: path)
    }

    func prepare(_ model: SpeechModel, download: Bool, progress: @escaping @Sendable (Double) -> Void = { _ in }) async throws {
        if loaded == model { return }
        // Release the previous model before loading another; do not hold several GB unnecessarily.
        whisper = nil; parakeet = nil; loaded = nil
        let modelRoot = Self.root.appendingPathComponent("Models", isDirectory: true)
        ModelHub.offlineMode = !download
        defer { ModelHub.offlineMode = true }
        try FileManager.default.createDirectory(at: modelRoot, withIntermediateDirectories: true)
        if model == .parakeet {
            let directory = Self.path(for: model)!
            if download {
                _ = try await AsrModels.download(to: directory, version: .ultra)
                progress(1)
            }
            // loadLocal never falls back to a model download, even for damaged files.
            let models = try AsrModels.loadLocal(from: directory, version: .ultra)
            parakeet = AsrManager(models: models)
        } else {
            var directory = Self.path(for: model)
            if download {
                directory = try await WhisperKit.download(variant: model.rawValue, downloadBase: modelRoot) { p in progress(p.fractionCompleted) }
                guard let directory else { throw FlowError.message("Model download did not return a folder.") }
                try directory.path.write(to: modelRoot.appendingPathComponent("\(model.rawValue).path"), atomically: true, encoding: .utf8)
                let tokens = Self.root.appendingPathComponent("Tokenizer", isDirectory: true)
                try FileManager.default.createDirectory(at: tokens, withIntermediateDirectories: true)
                for name in ["tokenizer.json", "tokenizer_config.json"] {
                    let url = URL(string: "https://huggingface.co/openai/whisper-large-v3/resolve/main/\(name)")!
                    let (data, response) = try await URLSession.shared.data(from: url)
                    guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw FlowError.message("Tokenizer download failed.") }
                    try data.write(to: tokens.appendingPathComponent(name), options: .atomic)
                }
            }
            guard let directory else { throw FlowError.message("Download this model first, or import its folder.") }
            let tokens = Self.root.appendingPathComponent("Tokenizer")
            // Parse only local tokenizer files. WhisperKit's default loader can fall back to the Hub.
            let tokenizer = try await LocalTokenizer(folder: tokens)
            let kit = try await WhisperKit(WhisperKitConfig(modelFolder: directory.path, verbose: false, prewarm: false, load: false, download: false))
            kit.tokenizer = tokenizer
            kit.textDecoder.isModelMultilingual = true
            try await kit.loadModels()
            whisper = kit
        }
        loaded = model
    }

    func transcribe(_ samples: [Float], language: String, vocabulary: String = "") async throws -> SpeechOutput {
        guard loaded != nil else { throw FlowError.message("Load a speech model in Settings first.") }
        guard samples.count >= 8000 else { throw FlowError.message("The recording was too short. Try speaking for at least half a second.") }
        let started = Date()
        let text: String
        let detected: String
        if let parakeet {
            var state = try TdtDecoderState()
            let result = try await parakeet.transcribe(samples, decoderState: &state, language: language == "auto" ? nil : Language(rawValue: language))
            text = result.text
            let recognizer = NLLanguageRecognizer()
            recognizer.processString(text)
            detected = recognizer.dominantLanguage?.rawValue ?? (language == "auto" ? "en" : language)
        } else if let whisper {
            let prompt = vocabulary.isEmpty ? nil : whisper.tokenizer?.encode(text: String(vocabulary.prefix(500))).suffix(120).map { $0 }
            let options = DecodingOptions(language: language == "auto" ? nil : language, temperatureFallbackCount: 2,
                detectLanguage: language == "auto", skipSpecialTokens: true, withoutTimestamps: true,
                promptTokens: prompt, concurrentWorkerCount: 1, chunkingStrategy: .vad)
            let results = try await whisper.transcribe(audioArray: samples, decodeOptions: options)
            text = results.map(\.text).joined(separator: " ")
            detected = results.first?.language ?? language
        } else { throw FlowError.message("The model is unavailable.") }
        return SpeechOutput(text: text.trimmingCharacters(in: .whitespacesAndNewlines), language: detected,
            audioSeconds: Double(samples.count) / 16000, processingSeconds: Date().timeIntervalSince(started))
    }

    func transcribeFile(_ url: URL, language: String) async throws -> SpeechOutput {
        let samples = try AudioConverter().resampleAudioFile(url)
        return try await transcribe(samples, language: language)
    }
}

/// Offline adapter: the dependency's public tokenizer factory otherwise retries online on parse failure.
private final class LocalTokenizer: WhisperTokenizer {
    private let base: TokenizerWrapper
    let specialTokens: SpecialTokens
    let allLanguageTokens: Set<Int>
    init(folder: URL) async throws {
        let base = try await AutoTokenizerWrapper.from(modelFolder: folder)
        self.base = base
        func id(_ token: String) throws -> Int {
            guard let id = base.convertTokenToId(token) else { throw FlowError.message("Local tokenizer is incomplete: \(token). Download it again in Settings.") }
            return id
        }
        specialTokens = try SpecialTokens(endToken: id("<|endoftext|>"), englishToken: id("<|en|>"),
            noSpeechToken: id("<|nospeech|>"), noTimestampsToken: id("<|notimestamps|>"),
            specialTokenBegin: id("<|endoftext|>"), startOfPreviousToken: id("<|startofprev|>"),
            startOfTranscriptToken: id("<|startoftranscript|>"), timeTokenBegin: id("<|0.00|>"),
            transcribeToken: id("<|transcribe|>"), translateToken: id("<|translate|>"), whitespaceToken: 220)
        allLanguageTokens = Set(Constants.languages.values.compactMap { base.convertTokenToId("<|\($0)|>") })
    }
    func encode(text: String) -> [Int] { base.encode(text: text) }
    func decode(tokens: [Int]) -> String { base.decode(tokens: tokens) }
    func convertTokenToId(_ token: String) -> Int? { base.convertTokenToId(token) }
    func convertIdToToken(_ id: Int) -> String? { base.convertIdToToken(id) }
    func splitToWordTokens(tokenIds: [Int]) -> (words: [String], wordTokens: [[Int]]) {
        // Word timestamps are disabled; preserve Unicode by decoding complete sequences.
        ([decode(tokens: tokenIds)], [tokenIds])
    }
}
