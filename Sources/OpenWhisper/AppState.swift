import AppKit
import AVFoundation
@preconcurrency import ApplicationServices
import FlowCore
import Observation

struct AppPreference: Codable, Identifiable {
    var id: String { bundleID }
    let bundleID: String
    var name: String
    var language = "default"
    var spokenPunctuation: Bool? = nil
    var pressEnterAfterDictation: Bool?
    var localCleanup: Bool?
}

struct Preferences: Codable {
    var language = "en"
    var model = SpeechModel.parakeet
    var keepHistory = true
    var learnCorrections = true
    var middleMouse = true
    var clipboardFallback = false
    var spokenPunctuation = false
    var vocabulary = ""
    var apps: [AppPreference] = []
    // Optional fields preserve preferences saved by earlier versions.
    var autoStopSilence: Bool?
    var silenceDelay: Double?
    var quietThresholdDB: Double?
    var dialect: String?
    var recordingLimitMinutes: Int?
    var inputDeviceUID: String?
    var setupStatus: String?
    var keyboardShortcut: DictationShortcut?
    var keyboardHoldToTalk: Bool?
    var livePreview: Bool?
    var localCleanup: Bool?
}

enum DictationPhase: Equatable {
    case idle, starting, recording, processing, cleaning, inserting, cancelling
    var title: String {
        switch self {
        case .idle: "Ready to dictate"
        case .starting: "Starting microphone"
        case .recording: "Listening"
        case .processing: "Transcribing locally"
        case .cleaning: "Polishing locally"
        case .inserting: "Inserting text"
        case .cancelling: "Cancelling"
        }
    }
}

@Observable @MainActor
final class AppState {
    var preferences: Preferences {
        didSet {
            if let data = try? JSONEncoder().encode(preferences) { UserDefaults.standard.set(data, forKey: "preferences") }
            triggers.middleEnabled = preferences.middleMouse
            triggers.useShortcut(preferences.keyboardShortcut ?? DictationShortcut())
            triggers.holdToTalk = preferences.keyboardHoldToTalk ?? false
            if !preferences.learnCorrections { watch = nil }
        }
    }
    private(set) var data: FlowData
    var phase = DictationPhase.idle
    var modelStatus = "Choose Download in Settings to get started"
    var modelReady = false
    var modelBusy = false
    var progress: Double = 0
    var notice: String?
    var showSetup = false
    var practiceActive = false
    var practiceText = ""
    var practiceLanguage = "en"
    var practiceFinished = false
    var liveTranscript = ""
    var capturingShortcut = false
    var cleanupAvailability = LocalCleanup.availability
    var currentApp = "No text field selected"
    var level: Float = 0
    var elapsed: Double = 0
    var silenceRemaining: Double?
    private(set) var recordingMaximumSeconds = 180.0
    var accessibility = AXIsProcessTrusted()
    var mouseAvailable = false
    var keyboardAvailable = false
    var lastText = ""
    var historySearch = ""
    var hotkeyError: String?
    var microphoneStatus = AppState.describeMicrophone()
    var inputDevices = AudioInputDevice.available()
    var systemInputName = AudioInputDevice.systemInputName
    private static func describeMicrophone() -> String {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized: "Allowed"
        case .denied, .restricted: "Not allowed"
        case .notDetermined: "Not requested"
        @unknown default: "Unknown"
        }
    }
    private let engine = SpeechEngine()
    private let cleanup = LocalCleanup()
    private let capture = AudioCapture()
    private let panel = RecordingPanel()
    private let triggers = DictationTriggers()
    private let store = DiskStore(url: SpeechEngine.root.appendingPathComponent("history.json"))
    private var storeReadable = true
    private var target: TextTarget?
    private var run: Task<Void, Never>?
    private var previewTask: Task<Void, Never>?
    private var timer: Timer?
    private var meterTimer: Timer?
    private var generation = UUID()
    private var recordingLanguage = "en"
    private var recordingPunctuation = false
    private var recordingPressEnter = false
    private var recordingInputDeviceUID: String?
    private var recordingPractice = false
    private var recordingCleanup = false
    private var recordingSnippets: [SpokenSnippet] = []
    private var finishAfterStart = false
    private var recordingStarted = Date()
    private var watch: EditWatch?

    struct EditWatch {
        let anchor: SpanAnchor
        let recordID: UUID
        let language: String
        let expires: Date
        var candidate: String?
        var changedAt = Date()
    }

    init() {
        let savedPreferences = UserDefaults.standard.data(forKey: "preferences")
        preferences = savedPreferences.flatMap { try? JSONDecoder().decode(Preferences.self, from: $0) } ?? Preferences()
        do { data = try store.load() }
        catch { data = FlowData(); storeReadable = false; notice = "History could not be read. Your original file is preserved: \(error.localizedDescription)" }
        let existingModel = SpeechEngine.path(for: preferences.model).map { FileManager.default.fileExists(atPath: $0.path) } ?? false
        showSetup = preferences.setupStatus == nil && savedPreferences == nil && data.dictations.isEmpty && !existingModel && !accessibility && microphoneStatus != "Allowed"
        practiceLanguage = preferences.language
        triggers.middleEnabled = preferences.middleMouse
        triggers.onToggle = { [weak self] in self?.toggle() }
        triggers.onCancel = { [weak self] in self?.cancel() }
        triggers.onStart = { [weak self] in if self?.phase == .idle { self?.toggle() } }
        triggers.onFinish = { [weak self] in
            if self?.phase == .starting { self?.finishAfterStart = true }
            else if self?.phase == .recording { self?.finish() }
        }
        triggers.useShortcut(preferences.keyboardShortcut ?? DictationShortcut())
        triggers.holdToTalk = preferences.keyboardHoldToTalk ?? false
        triggers.register()
        hotkeyError = triggers.hotkeyError
        mouseAvailable = triggers.mouseAvailable
        keyboardAvailable = triggers.keyboardAvailable
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        RunLoop.main.add(timer, forMode: .common); self.timer = timer
        Task { await loadModel(download: false, showError: false) }
    }

    var filteredHistory: [Dictation] {
        data.dictations.filter { historySearch.isEmpty || $0.text.localizedCaseInsensitiveContains(historySearch) || $0.appName.localizedCaseInsensitiveContains(historySearch) }
    }
    var totalWords: Int { data.dictations.reduce(0) { $0 + $1.wordCount } }
    var totalAudio: Double { data.dictations.reduce(0) { $0 + $1.audioSeconds } }
    var wordsPerMinute: Int { totalAudio > 0 ? Int(Double(totalWords) / totalAudio * 60) : 0 }
    var averageLatency: Double { data.dictations.isEmpty ? 0 : data.dictations.reduce(0) { $0 + $1.processingSeconds } / Double(data.dictations.count) }
    var activeRules: Int { data.corrections.filter(\.enabled).count }
    var recordingLimitMinutes: Int { min(30, max(1, preferences.recordingLimitMinutes ?? 3)) }
    var recordingLimitLabel: String {
        let minutes = phase == .recording ? Int(recordingMaximumSeconds / 60) : recordingLimitMinutes
        return minutes == 1 ? "1 minute" : "\(minutes) minutes"
    }
    var profile: SpeechProfile { SpeechProfile(records: data.dictations) }
    var inputDeviceAvailable: Bool { preferences.inputDeviceUID.map { uid in inputDevices.contains { $0.id == uid } } ?? (systemInputName != nil) }
    var shortcutAvailable: Bool { keyboardAvailable || (preferences.middleMouse && mouseAvailable) }
    var keyboardShortcutLabel: String { (preferences.keyboardShortcut ?? DictationShortcut()).label }
    var shortcutLabel: String {
        if preferences.middleMouse && mouseAvailable {
            return keyboardAvailable ? "Middle-click or \(keyboardShortcutLabel)" : "Middle-click"
        }
        return keyboardAvailable ? keyboardShortcutLabel : "No dictation shortcut available"
    }
    var readyToDictate: Bool { modelReady && preferences.model.supports(preferences.language) && microphoneStatus == "Allowed" && accessibility && inputDeviceAvailable && shortcutAvailable }
    var inputDeviceName: String {
        guard let uid = preferences.inputDeviceUID else { return systemInputName.map { "Automatic · \($0)" } ?? "No system input available" }
        return inputDevices.first(where: { $0.id == uid })?.name ?? "Selected microphone unavailable"
    }
    var personalTerms: [String] {
        let terms = preferences.vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        return Array(Set(terms + data.corrections.filter(\.enabled).map(\.to))).sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    func refreshPermissions() {
        accessibility = AXIsProcessTrusted()
        microphoneStatus = Self.describeMicrophone()
        triggers.register(); mouseAvailable = triggers.mouseAvailable
        keyboardAvailable = triggers.keyboardAvailable; hotkeyError = triggers.hotkeyError
        cleanupAvailability = LocalCleanup.availability
    }

    func recordShortcut() {
        guard phase == .idle else { return }
        capturingShortcut = true
        triggers.captureShortcut { [weak self] shortcut in
            guard let self else { return }
            if let shortcut { self.preferences.keyboardShortcut = shortcut }
            self.capturingShortcut = false; self.refreshPermissions()
        }
    }
    func cancelShortcutRecording() { triggers.cancelShortcutCapture(); capturingShortcut = false }

    func refreshInputDevices() {
        inputDevices = AudioInputDevice.available(); systemInputName = AudioInputDevice.systemInputName
    }

    func openSetup() {
        guard phase == .idle else { return }
        finishWatch(); notice = nil; refreshPermissions(); refreshInputDevices()
        practiceText = ""; practiceFinished = false; practiceActive = false
        practiceLanguage = preferences.language
        showSetup = true; showWindow()
    }
    func closeSetup(skipped: Bool) {
        guard phase != .inserting else { return }
        if phase != .idle { cancel() }
        practiceActive = false; practiceText = ""; practiceFinished = false
        preferences.setupStatus = skipped ? "skipped" : "complete"
        showSetup = false
    }
    func leavePractice() {
        if recordingPractice && phase != .idle { cancel() }
        practiceActive = false; practiceText = ""; practiceFinished = false
    }

    func requestAccessibility() {
        refreshPermissions()
        guard !accessibility else {
            notice = "Accessibility is already allowed. Select a text field in another app, then use \(shortcutLabel)."
            return
        }
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        _ = AXIsProcessTrustedWithOptions(options)
        refreshPermissions()
        if !accessibility {
            notice = "If Open Whisper is already enabled in Settings, remove its old entry with −, then add this copy with +: \(Bundle.main.bundleURL.path). Enable it and quit and reopen Open Whisper."
        }
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")!)
    }
    func requestMicrophone() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .audio)
            microphoneStatus = Self.describeMicrophone()
            notice = allowed ? "Microphone access is allowed." : "Allow Open Whisper under System Settings → Privacy & Security → Microphone."
        }
    }
    func openMicrophoneSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone")!)
    }

    func loadModel(download: Bool, showError: Bool = true) async {
        guard !modelBusy, phase == .idle else { return }
        modelBusy = true; modelReady = false; progress = 0
        let selected = preferences.model
        modelStatus = download ? "Downloading \(selected.title)…" : "Loading \(selected.title)…"
        do {
            try await engine.prepare(selected, download: download) { [weak self] value in
                Task { @MainActor in self?.progress = value }
            }
            modelReady = true; modelStatus = "\(selected.title) · running on your Mac"
        } catch {
            modelStatus = "Model needs setup"
            if showError { notice = error.localizedDescription }
        }
        modelBusy = false
    }

    func toggle() {
        if phase == .recording { finish(); return }
        guard phase == .idle else { return }
        if showSetup && !practiceActive { return }
        let practice = showSetup && practiceActive
        notice = nil
        guard modelReady, !modelBusy else { notice = "Open Settings and download or load a speech model first."; showWindow(); return }
        guard practice || AXIsProcessTrusted() else { notice = "Allow Accessibility in Settings before dictating into other apps."; showWindow(); return }
        finishWatch()
        target = practice ? nil : TextTarget.capture()
        recordingPractice = practice
        if practice { currentApp = "Practice" }
        guard target?.secure != true else { notice = "Dictation is disabled in password fields."; return }
        if let target {
            currentApp = target.appName
            if !preferences.apps.contains(where: { $0.bundleID == target.bundleID }) {
                preferences.apps.append(AppPreference(bundleID: target.bundleID, name: target.appName))
            }
        }
        let app = preferences.apps.first { $0.bundleID == target?.bundleID }
        recordingLanguage = practice ? practiceLanguage : (app?.language == "default" || app == nil ? preferences.language : app!.language)
        guard preferences.model.supports(recordingLanguage) else {
            notice = "\(SpeechLanguages.name(recordingLanguage)) requires Whisper. Choose a Whisper model in Settings; download it once to use this language offline."
            showWindow(); return
        }
        recordingPunctuation = app?.spokenPunctuation ?? preferences.spokenPunctuation
        recordingPressEnter = !practice && (app?.pressEnterAfterDictation ?? false)
        recordingCleanup = app?.localCleanup ?? preferences.localCleanup ?? false
        recordingSnippets = data.snippets
        finishAfterStart = false; liveTranscript = ""
        recordingMaximumSeconds = Double(recordingLimitMinutes) * 60
        recordingInputDeviceUID = preferences.inputDeviceUID
        phase = .starting
        let session = UUID(); generation = session
        run = Task { [self] in
            let permitted = await AVCaptureDevice.requestAccess(for: .audio)
            guard generation == session, !Task.isCancelled else { phase = .idle; return }
            guard permitted else { phase = .idle; notice = "Allow microphone access in System Settings → Privacy & Security → Microphone."; return }
            // On first permission prompt the user may have selected another app.
            guard target == nil || target?.stillFocused == true else { phase = .idle; notice = "Select your text field and click the middle button again."; return }
            do {
                try capture.start(maximumSeconds: recordingMaximumSeconds, thresholdDB: preferences.quietThresholdDB ?? -42, deviceUID: recordingInputDeviceUID); phase = .recording; recordingStarted = Date(); elapsed = 0
                level = 0; silenceRemaining = nil
                panel.show(title: "Listening", detail: currentApp, maximumSeconds: recordingMaximumSeconds, middleMouse: preferences.middleMouse && mouseAvailable, shortcut: keyboardShortcutLabel, holdToTalk: preferences.keyboardHoldToTalk ?? false, screen: target?.screen)
                let meterTimer = Timer(timeInterval: 1.0 / 30, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.updateRecording() }
                }
                RunLoop.main.add(meterTimer, forMode: .common); self.meterTimer = meterTimer
                if preferences.livePreview ?? true { startPreview(session: session) }
                if finishAfterStart { finish() }
            } catch { phase = .idle; notice = error.localizedDescription }
        }
    }

    private func finish() {
        guard phase == .recording else { return }
        meterTimer?.invalidate(); meterTimer = nil
        let samples: [Float]
        do { samples = try capture.stop() } catch {
            let pending = previewTask; pending?.cancel(); previewTask = nil
            liveTranscript = ""; panel.hide(); notice = error.localizedDescription; phase = .cancelling
            run = Task { await pending?.value; phase = .idle }
            return
        }
        phase = .processing
        let processingStarted = Date()
        let pendingPreview = previewTask; pendingPreview?.cancel(); previewTask = nil
        liveTranscript = ""
        panel.show(title: "Transcribing locally", detail: "\(preferences.model.title) · Esc to cancel")
        let session = generation
        let target = target
        let language = recordingLanguage
        let punctuation = recordingPunctuation
        let pressEnter = recordingPressEnter
        let practice = recordingPractice
        let useCleanup = recordingCleanup
        let snippets = recordingSnippets
        let hints = data.corrections.filter { $0.enabled && ($0.bundleID == "*" || $0.bundleID == target?.bundleID) && ($0.language == "*" || $0.language == language) }.map(\.to)
        let vocabulary = ([preferences.vocabulary] + hints).joined(separator: ", ")
        run = Task {
            defer { phase = .idle; panel.hide() }
            do {
                await pendingPreview?.value
                guard generation == session, !Task.isCancelled else { return }
                let result = try await engine.transcribe(samples, language: language, vocabulary: vocabulary)
                guard generation == session, !Task.isCancelled else { return }
                guard !result.text.isEmpty else { notice = "No speech detected. Try moving closer to the microphone."; return }
                let actualLanguage = language == "auto" ? result.language : language
                var transcript = result.text
                if useCleanup {
                    phase = .cleaning; panel.show(title: "Polishing locally", detail: "On-device AI · Esc to cancel")
                    let spellings = data.corrections.filter { $0.enabled && ($0.bundleID == "*" || $0.bundleID == target?.bundleID) && ($0.language == "*" || $0.language == actualLanguage) }.flatMap { [$0.from, $0.to] }
                    let vocabulary = preferences.vocabulary.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    let phrases = SnippetProcessing.matchingTriggers(transcript, snippets: snippets, language: actualLanguage)
                        + (spellings + vocabulary).filter { !$0.isEmpty && transcript.localizedCaseInsensitiveContains($0) }
                    let output = await cleanup.clean(transcript, language: actualLanguage, protectedPhrases: phrases)
                    guard generation == session, !Task.isCancelled else { return }
                    transcript = output.text
                    if !output.applied { notice = "\(output.status). Using the original transcript." }
                }
                let corrected = TextProcessing.clean(transcript, corrections: data.corrections,
                    bundleID: target?.bundleID ?? "", language: actualLanguage, spokenPunctuation: punctuation)
                let cleaned = SnippetProcessing.expand(corrected, snippets: snippets, language: actualLanguage)
                if practice {
                    guard showSetup, practiceActive else { return }
                    practiceText = cleaned; practiceFinished = true
                    return
                }
                lastText = cleaned
                let processingSeconds = Date().timeIntervalSince(processingStarted)
                // Insertion is a commit boundary; Esc cancels decoding, not an already delivered edit.
                phase = .inserting
                panel.show(title: "Inserting text", detail: target?.appName ?? "Saving transcript")
                let delivery = await target?.insert(cleaned, allowPaste: preferences.clipboardFallback, pressEnter: pressEnter) ?? (status: "Saved — no target field", anchor: nil)
                let record = Dictation(original: result.text, text: cleaned, appName: target?.appName ?? "Open Whisper",
                    bundleID: target?.bundleID ?? "", language: actualLanguage, audioSeconds: result.audioSeconds,
                    processingSeconds: processingSeconds, delivery: delivery.status)
                if preferences.keepHistory {
                    data.dictations.insert(record, at: 0)
                    data.dictations = Array(data.dictations.prefix(1000)); persist()
                }
                if let anchor = delivery.anchor, preferences.learnCorrections, actualLanguage != "unknown" {
                    watch = EditWatch(anchor: anchor, recordID: record.id, language: actualLanguage, expires: Date().addingTimeInterval(60))
                }
                if delivery.anchor == nil {
                    if delivery.status.hasPrefix("Inserted"), delivery.status.contains("Enter pressed") { notice = nil }
                    else if delivery.status.contains("unverified") {
                        notice = "Couldn’t confirm the text in \(target?.appName ?? "this field"). Correction tracking is off for this dictation. Your transcript is available below."
                    } else { notice = "\(delivery.status). Your transcript is available on the Dictate screen." }
                }
            } catch {
                if generation == session { notice = error.localizedDescription }
            }
        }
    }

    func cancel() {
        guard phase != .idle, phase != .inserting else { return }
        generation = UUID(); run?.cancel()
        if phase == .recording {
            meterTimer?.invalidate(); meterTimer = nil; capture.cancel(); panel.hide(); liveTranscript = ""
            let pending = previewTask; pending?.cancel(); previewTask = nil; phase = .cancelling
            run = Task { await pending?.value; phase = .idle }
        }
        else { phase = .cancelling }
    }

    private func startPreview(session: UUID) {
        let language = recordingLanguage
        let vocabulary = preferences.vocabulary
        previewTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled {
                do {
                    try await Task.sleep(for: .seconds(2))
                    guard generation == session, phase == .recording else { return }
                    guard capture.status.activity.silenceSeconds.map({ $0 < 2 }) == true else { continue }
                    let samples = capture.previewSamples
                    guard samples.count >= 8000 else { continue }
                    let result = try await engine.transcribe(samples, language: language, vocabulary: vocabulary)
                    guard !Task.isCancelled, generation == session, phase == .recording else { return }
                    liveTranscript = result.text
                    panel.preview(result.text)
                } catch { return }
            }
        }
    }

    private func updateRecording() {
        guard phase == .recording else { return }
        let status = capture.status
        // Fast attack, gentle release; the input itself is sampled by the audio tap.
        level += (status.level - level) * (status.level > level ? 0.8 : 0.3)
        elapsed = max(status.activity.seconds, Date().timeIntervalSince(recordingStarted))
        let enabled = preferences.autoStopSilence ?? false
        let delay = preferences.silenceDelay ?? 5
        silenceRemaining = enabled ? status.activity.silenceSeconds.map { max(0, delay - $0) } : nil
        panel.update(level: level, elapsed: elapsed, remaining: silenceRemaining)
        if elapsed >= recordingMaximumSeconds || status.activity.shouldStop(silenceEnabled: enabled, delay: delay) { finish() }
    }

    private func tick() {
        refreshPermissions()
        if phase == .idle, let app = NSWorkspace.shared.frontmostApplication, app.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            currentApp = app.localizedName ?? "Unknown app"
        }
        guard var watch else { return }
        guard preferences.learnCorrections else { self.watch = nil; return }
        if !watch.anchor.target.stillFocused || Date() > watch.expires { finishWatch(); return }
        guard let value = TextTarget.textValue(watch.anchor.element) else { return }
        guard let edited = TextProcessing.editedSpan(value: value, prefix: watch.anchor.prefix, suffix: watch.anchor.suffix) else {
            self.watch = nil; return
        }
        guard !edited.isEmpty else { self.watch = nil; return }
        // Deleting a mistaken word before retyping it can span several polls.
        // Discard the pending guess, but keep watching the anchored span.
        guard edited == watch.anchor.inserted || TextProcessing.correction(original: watch.anchor.inserted, edited: edited,
            requireSharedContext: watch.anchor.prefix.isEmpty && watch.anchor.suffix.isEmpty, language: watch.language) != nil else {
            watch.candidate = nil; self.watch = watch; return
        }
        if watch.candidate != edited { watch.candidate = edited; watch.changedAt = Date() }
        self.watch = watch
        if edited != watch.anchor.inserted, Date().timeIntervalSince(watch.changedAt) >= 2 { finishWatch() }
    }

    private func finishWatch() {
        defer { watch = nil }
        guard let watch, let edited = watch.candidate, Date().timeIntervalSince(watch.changedAt) >= 2,
              edited != watch.anchor.inserted else { return }
        data.learn(original: watch.anchor.inserted, edited: edited, bundleID: watch.anchor.target.bundleID, language: watch.language)
        if let index = data.dictations.firstIndex(where: { $0.id == watch.recordID }) { data.dictations[index].corrected = edited }
        persist()
    }

    func setRule(_ id: UUID, enabled: Bool) {
        guard let index = data.corrections.firstIndex(where: { $0.id == id }) else { return }
        let rule = data.corrections[index]
        if enabled {
            for other in data.corrections.indices where data.corrections[other].from.caseInsensitiveCompare(rule.from) == .orderedSame && data.corrections[other].bundleID == rule.bundleID && data.corrections[other].language == rule.language {
                data.corrections[other].enabled = false
            }
        }
        data.corrections[index].enabled = enabled
        data.corrections[index].userDisabled = !enabled
        persist()
    }
    func removeRule(_ id: UUID) { data.corrections.removeAll { $0.id == id }; persist() }
    @discardableResult func saveSnippet(_ snippet: SpokenSnippet) -> Bool {
        guard snippet.valid, !data.snippets.contains(where: { $0.id != snippet.id && $0.trigger.caseInsensitiveCompare(snippet.trigger) == .orderedSame }) else { return false }
        if let index = data.snippets.firstIndex(where: { $0.id == snippet.id }) { data.snippets[index] = snippet }
        else { data.snippets.append(snippet) }
        persist(); return true
    }
    func setSnippet(_ id: UUID, enabled: Bool) {
        guard let index = data.snippets.firstIndex(where: { $0.id == id }) else { return }
        data.snippets[index].enabled = enabled; persist()
    }
    func removeSnippet(_ id: UUID) { data.snippets.removeAll { $0.id == id }; persist() }
    @discardableResult func teachName(from: String, to: String, language: String) -> Bool {
        guard data.teach(from: from, to: to, language: language) else { return false }
        persist(); return true
    }
    func removeRecord(_ id: UUID) { data.dictations.removeAll { $0.id == id }; persist() }
    func correctRecord(_ id: UUID, text: String) {
        guard let index = data.dictations.firstIndex(where: { $0.id == id }) else { return }
        let record = data.dictations[index]
        data.dictations[index].corrected = text
        if preferences.learnCorrections, record.language != "unknown" { data.learn(original: record.text, edited: text, bundleID: record.bundleID, language: record.language) }
        persist()
    }
    func clearHistory() { data.dictations = []; persist() }
    func clearLearning() { watch = nil; data.corrections = []; persist() }
    func copy(_ text: String) { NSPasteboard.general.clearContents(); NSPasteboard.general.setString(text, forType: .string) }
    func exportHistory() {
        let panel = NSSavePanel(); panel.nameFieldStringValue = "Open Whisper History.json"; panel.allowedContentTypes = [.json]
        if panel.runModal() == .OK, let url = panel.url {
            do { try JSONEncoder().encode(data.dictations).write(to: url, options: .atomic) } catch { notice = error.localizedDescription }
        }
    }
    func transcribeFile() {
        guard modelReady, phase == .idle else { return }
        let dialog = NSOpenPanel(); dialog.allowedContentTypes = [.audio]; dialog.allowsMultipleSelection = false
        guard dialog.runModal() == .OK, let url = dialog.url else { return }
        phase = .processing
        run = Task {
            defer { phase = .idle }
            do {
                let result = try await engine.transcribeFile(url, language: preferences.language)
                guard !Task.isCancelled else { return }
                lastText = result.text
                if preferences.keepHistory {
                    data.dictations.insert(Dictation(original: result.text, text: result.text, appName: "Audio import", bundleID: "import",
                        language: result.language, audioSeconds: result.audioSeconds, processingSeconds: result.processingSeconds, delivery: "Imported — use Copy"), at: 0)
                    data.dictations = Array(data.dictations.prefix(1000)); persist()
                }
            } catch { if !Task.isCancelled { notice = error.localizedDescription } }
        }
    }
    func showWindow() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first { $0.canBecomeKey && !($0 is NSPanel) }?.makeKeyAndOrderFront(nil)
    }
    private func persist() {
        guard storeReadable else { notice = "History was not saved because the original history file could not be read. Preserve or repair it before saving."; return }
        do { try store.save(data) } catch { notice = "Could not save local history: \(error.localizedDescription)" }
    }
}
