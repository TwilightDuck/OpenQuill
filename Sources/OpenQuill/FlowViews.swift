import SwiftUI
import Charts
import FlowCore

enum FlowPage: String, CaseIterable, Identifiable {
    case dictate = "Dictate", history = "History", statistics = "Statistics", profile = "Speech profile", vocabulary = "Vocabulary", snippets = "Snippets", settings = "Settings"
    var id: String { rawValue }
    var icon: String {
        switch self {
        case .dictate: "waveform"
        case .history: "clock.arrow.circlepath"
        case .statistics: "chart.bar.xaxis"
        case .profile: "person.crop.circle"
        case .vocabulary: "text.book.closed"
        case .snippets: "text.badge.plus"
        case .settings: "slider.horizontal.3"
        }
    }
}

struct FlowWindow: View {
    @Bindable var state: AppState
    @State private var page: FlowPage? = .dictate
    var body: some View {
        Group {
        if state.showSetup { SetupGuide(state: state, reviewSettings: { page = .settings }, startDictating: { page = .dictate }) }
        else {
        NavigationSplitView {
            List(selection: $page) {
                ForEach(FlowPage.allCases) { item in Label(item.rawValue, systemImage: item.icon).tag(item) }
            }
            .navigationSplitViewColumnWidth(min: 175, ideal: 190, max: 220)
            .safeAreaInset(edge: .bottom) {
                Label("Everything stays on this Mac", systemImage: "lock.shield")
                    .font(.caption).foregroundStyle(.secondary).padding(18)
            }
        } detail: {
            VStack(spacing: 0) {
                if let notice = state.notice {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "info.circle").foregroundStyle(Color.flowWarning)
                        Text(notice).font(.callout).textSelection(.enabled)
                        Spacer()
                        Button { state.notice = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain).accessibilityLabel("Dismiss message")
                    }.padding(14).background(Color.flowWarning.opacity(0.08))
                }
                switch page ?? .dictate {
                case .dictate: DictateView(state: state, openSettings: { page = .settings })
                case .history: HistoryView(state: state)
                case .statistics: StatisticsView(state: state)
                case .profile: SpeechProfileView(state: state)
                case .vocabulary: VocabularyView(state: state)
                case .snippets: SnippetsView(state: state)
                case .settings: FlowSettingsView(state: state)
                }
            }
            .navigationTitle(page?.rawValue ?? "Dictate")
        }
        .tint(Color.flowAccent)
        .frame(minWidth: 820, minHeight: 590)
        }
        }.background(Color.flowCanvas).tint(Color.flowAccent)
            .frame(minWidth: 820, minHeight: 590)
    }
}

struct DictateView: View {
    @Bindable var state: AppState
    let openSettings: () -> Void
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                if !state.readyToDictate {
                    HStack {
                        Label("Finish setup to start dictating", systemImage: "wand.and.stars")
                        Spacer()
                        Button("Resume setup", action: state.openSetup)
                    }.font(.callout).flowCard()
                }
                HStack {
                    Label(state.modelReady ? "Local model ready" : (state.modelBusy ? "Preparing local model…" : "Setup needed"), systemImage: state.modelReady ? "checkmark.circle.fill" : "arrow.down.circle")
                        .font(.callout).foregroundStyle(state.modelReady ? Color.flowAccent : Color.secondary)
                    Spacer()
                    SpeechLanguagePicker(title: "Dictation language", selection: $state.preferences.language, model: state.preferences.model)
                        .buttonStyle(.bordered).disabled(state.phase != .idle)
                }
                VStack(spacing: 18) {
                    Image(systemName: "waveform").font(.system(size: 46, weight: .light)).foregroundStyle(Color.flowAccent).accessibilityHidden(true)
                    Text(state.phase == .idle ? "Speak your mind." : state.phase.title).font(.system(size: 34, weight: .semibold, design: .rounded)).tracking(-0.8)
                    Text(state.phase == .recording ? "\(Int(state.elapsed))s of \(state.recordingLimitLabel) · \(state.preferences.keyboardHoldToTalk == true && !state.preferences.middleMouse ? "release to finish" : "press again to finish")" : (!state.shortcutAvailable ? "Check shortcut access in Settings." : (state.preferences.middleMouse && state.mouseAvailable ? "Middle-click. Speak. Click again." : "Use \(state.keyboardShortcutLabel) to dictate.")))
                        .font(.body).foregroundStyle(.secondary)
                    HStack(spacing: 12) {
                        if state.preferences.middleMouse && state.mouseAvailable {
                            HStack(spacing: 8) { MouseShortcutSymbol(size: 26); Text("Middle-click") }
                                .padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary, in: Capsule())
                            if state.keyboardAvailable { Text("or").foregroundStyle(.secondary) }
                        }
                        if state.keyboardAvailable {
                            Text(state.keyboardShortcutLabel).padding(.horizontal, 12).padding(.vertical, 8).background(.quaternary, in: Capsule())
                        }
                    }.font(.callout)
                    if state.phase == .processing || state.phase == .cleaning || state.phase == .starting || state.phase == .cancelling { ProgressView().controlSize(.small) }
                    if state.phase == .recording {
                        ProgressView(value: Double(state.level)).tint(Color.flowAccent).frame(width: 220)
                        if let remaining = state.silenceRemaining, remaining < 4.5 { Text("Finishing after silence in \(Int(ceil(remaining)))s").font(.caption).foregroundStyle(.secondary) }
                    }
                    if !state.preferences.model.supports(state.preferences.language) {
                        Text("\(SpeechLanguages.name(state.preferences.language)) requires a Whisper model.").font(.callout).foregroundStyle(.secondary)
                    }
                    if !state.readyToDictate { Button("Set up dictation", action: openSettings).buttonStyle(.borderedProminent) }
                    if state.phase != .idle && state.phase != .inserting { Button("Cancel", action: state.cancel).keyboardShortcut(.cancelAction) }
                }
                .frame(maxWidth: .infinity).padding(.vertical, 38)
                .background(LinearGradient(colors: [Color.flowAccent.opacity(0.10), Color.flowAccent.opacity(0.025)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 24))
                .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(Color.flowAccent.opacity(0.12), lineWidth: 1))
                if state.phase == .recording, !state.liveTranscript.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Label("Live preview · latest speech", systemImage: "waveform").font(.headline)
                        Text(state.liveTranscript).font(.body).foregroundStyle(.secondary)
                        Text("Provisional words from the latest 12 seconds. The whole recording is transcribed when you finish.").font(.caption).foregroundStyle(.secondary)
                    }.flowCard()
                }
                HStack(spacing: 12) {
                    ProfileMetric(title: "Words captured", value: state.totalWords.formatted(), icon: "text.alignleft")
                    ProfileMetric(title: "Personal terms", value: state.personalTerms.count.formatted(), icon: "text.book.closed")
                    ProfileMetric(title: "Dictation limit", value: state.recordingLimitLabel, icon: "timer")
                }
                HStack(spacing: 10) {
                    Image(systemName: "macwindow").foregroundStyle(.secondary)
                    Text(state.currentApp).font(.callout)
                    Spacer()
                    Text(state.modelReady ? state.preferences.model.title : "Model not loaded").font(.caption).foregroundStyle(.secondary)
                }
                if !state.accessibility {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Allow text insertion").font(.headline)
                            Text("Accessibility lets the middle button work and places text at your cursor.").font(.callout).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Allow access", action: state.requestAccessibility)
                    }.padding(18).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
                }
                if !state.lastText.isEmpty {
                    HStack { Text("Latest dictation").font(.headline); Spacer(); Button("Copy") { state.copy(state.lastText) } }
                    Text(state.lastText).font(.body).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                        .padding(18).background(.background, in: RoundedRectangle(cornerRadius: 12))
                }
                HStack {
                    Text("Audio lives in memory and is discarded after transcription.").font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Transcribe audio file…", action: state.transcribeFile).disabled(!state.modelReady || state.phase != .idle)
                }
            }.padding(30)
        }
    }
}

struct HistoryView: View {
    @Bindable var state: AppState
    @State private var editing: Dictation?
    @State private var editedText = ""
    @State private var confirmClear = false
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                TextField("Search dictations or apps", text: $state.historySearch).textFieldStyle(.roundedBorder)
                Button("Export…", action: state.exportHistory).disabled(state.data.dictations.isEmpty)
                Button("Clear…") { confirmClear = true }.disabled(state.data.dictations.isEmpty)
            }.padding(20)
            if state.filteredHistory.isEmpty {
                ContentUnavailableView("Your words will appear here", systemImage: "clock.arrow.circlepath", description: Text("Dictations are saved locally when history is enabled."))
            } else {
                List(state.filteredHistory) { record in
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text(record.appName).font(.headline)
                            Text(SpeechLanguages.name(record.language)).font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Text(record.date, format: .dateTime.month(.abbreviated).day().hour().minute()).font(.caption).foregroundStyle(.secondary)
                        }
                        Text(record.corrected ?? record.text).textSelection(.enabled).font(.body)
                        HStack(spacing: 14) {
                            Text("\(record.wordCount) words · \(record.processingSeconds, specifier: "%.2f")s processing").font(.caption).foregroundStyle(.secondary)
                            Spacer()
                            Button("Copy") { state.copy(record.corrected ?? record.text) }
                            Button("Correct") { editing = record; editedText = record.corrected ?? record.text }
                            Button { state.removeRecord(record.id) } label: { Image(systemName: "trash") }.accessibilityLabel("Delete dictation")
                        }.buttonStyle(.borderless)
                        DisclosureGroup("Transcription details") {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(record.delivery).foregroundStyle(.secondary)
                                Text(record.original).textSelection(.enabled)
                            }.font(.callout).padding(.top, 6)
                        }
                    }.padding(.vertical, 12)
                }.listStyle(.inset)
            }
        }
        .confirmationDialog("Delete all local dictation history?", isPresented: $confirmClear) { Button("Delete history", role: .destructive, action: state.clearHistory) }
        .sheet(item: $editing) { record in
            VStack(alignment: .leading, spacing: 18) {
                Text("Correct dictation").font(.title2.bold())
                TextEditor(text: $editedText).font(.body).frame(height: 180).border(.quaternary)
                Text("Short substitutions teach spelling and names. Seeing the same correction twice activates it for this app and language. You can also enable it immediately in Vocabulary.")
                    .font(.callout).foregroundStyle(.secondary)
                HStack { Spacer(); Button("Cancel") { editing = nil }; Button("Save correction") { state.correctRecord(record.id, text: editedText); editing = nil }.buttonStyle(.borderedProminent) }
            }.padding(24).frame(width: 500)
        }
    }
}

struct StatisticsView: View {
    let state: AppState
    var days: [(date: Date, words: Int)] {
        (0..<7).reversed().map { offset in
            let day = Calendar.current.startOfDay(for: Calendar.current.date(byAdding: .day, value: -offset, to: Date())!)
            return (day, state.data.dictations.filter { Calendar.current.isDate($0.date, inSameDayAs: day) }.reduce(0) { $0 + $1.wordCount })
        }
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                HStack(spacing: 28) {
                    metric("Words dictated", value: state.totalWords.formatted())
                    metric("Speaking pace", value: "\(state.wordsPerMinute) wpm")
                    metric("Average processing", value: String(format: "%.2fs", state.averageLatency))
                }
                Divider()
                Text("Your week in words").font(.title3.bold())
                Chart(days, id: \.date) { day in
                    BarMark(x: .value("Day", day.date, unit: .day), y: .value("Words", day.words))
                        .foregroundStyle(Color.flowAccent).cornerRadius(4)
                }.chartXAxis { AxisMarks(values: .stride(by: .day)) { value in AxisValueLabel(format: .dateTime.weekday(.abbreviated)) } }
                    .frame(height: 220)
                    .accessibilityLabel("Dictated words per day for the last seven days")
                HStack(spacing: 28) {
                    metric("Dictations", value: state.data.dictations.count.formatted())
                    metric("Active corrections", value: state.activeRules.formatted())
                    metric("Estimated time saved", value: "\(max(0, Int(Double(state.totalWords) / 45 - state.totalAudio / 60))) min")
                }
                Text("Word counts use this Mac’s language-aware word boundaries; punctuation and emoji aren’t words. Counts and pace are estimates, particularly for languages without spaces. Time saved assumes typing at 45 words per minute. Processing measures model inference after recording ends.")
                    .font(.caption).foregroundStyle(.secondary)
                if !state.data.dictations.isEmpty {
                    Divider()
                    Text("Where you dictate").font(.title3.bold())
                    ForEach(Array(Dictionary(grouping: state.data.dictations, by: \.appName).map { ($0.key, $0.value.reduce(0) { $0 + $1.wordCount }) }.sorted { $0.1 > $1.1 }.prefix(6)), id: \.0) { app, words in
                        HStack { Text(app); Spacer(); Text("\(words.formatted()) words").foregroundStyle(.secondary) }.font(.callout)
                    }
                }
            }.padding(30)
        }
    }
    func metric(_ title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 10) { Text(value).font(.system(size: 28, weight: .semibold, design: .rounded)).monospacedDigit(); Text(title).font(.callout).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).flowCard()
    }
}

struct VocabularyView: View {
    @Bindable var state: AppState
    @State private var confirmClear = false
    @State private var teaching = false
    @State private var heard = ""
    @State private var spelling = ""
    @State private var language = "*"
    @State private var invalid = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Make every name yours.").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                        Text("Teach the spelling once. Keep it on this Mac.").font(.callout).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Teach a name or term", systemImage: "plus") { teaching = true }.buttonStyle(.borderedProminent)
                }
                HStack(spacing: 12) {
                    ProfileMetric(title: "Personal terms", value: state.personalTerms.count.formatted(), icon: "text.book.closed")
                    ProfileMetric(title: "Active spelling rules", value: state.activeRules.formatted(), icon: "checkmark.circle")
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text("Recognition hints").font(.headline)
                    Text("Names, products and technical terms, separated by commas. Whisper uses these during recognition. With Parakeet, use a spelling rule below to fix a name it mishears.").font(.callout).foregroundStyle(.secondary)
                    TextEditor(text: $state.preferences.vocabulary).font(.body).frame(height: 80).padding(8)
                        .background(.background, in: RoundedRectangle(cornerRadius: 10)).accessibilityLabel("Recognition hints")
                }.flowCard()
                HStack { Text("Spelling & corrections").font(.title3.bold()); Spacer(); Button("Reset…") { confirmClear = true }.disabled(state.data.corrections.isEmpty) }
                Text("Automatic learning watches a verified field for one minute and activates short replacements after two observations. Editors that hide their text, including some Codex and Claude fields, need History → Correct or an explicit spelling rule. These are text rules, not speech model training.")
                    .font(.callout).foregroundStyle(.secondary)
                if state.data.corrections.isEmpty {
                    ContentUnavailableView("Ready to learn your words", systemImage: "text.badge.plus", description: Text("Add a name above, or correct a transcript in History."))
                }
                ForEach(state.data.corrections) { rule in
                    HStack(alignment: .top, spacing: 12) {
                        Toggle("Use \(rule.from) correction", isOn: Binding(get: { rule.enabled }, set: { state.setRule(rule.id, enabled: $0) })).labelsHidden().toggleStyle(.switch).controlSize(.small)
                        VStack(alignment: .leading, spacing: 6) {
                            Text("\(rule.from) → \(rule.to)").font(.headline).textSelection(.enabled)
                            Text("\(rule.bundleID == "*" ? "All apps" : (state.preferences.apps.first { $0.bundleID == rule.bundleID }?.name ?? rule.bundleID)) · \(SpeechLanguages.name(rule.language)) · \(rule.observations == 0 ? "Taught by you" : "Observed \(rule.observations)×")")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button { state.removeRule(rule.id) } label: { Image(systemName: "trash") }.buttonStyle(.borderless).accessibilityLabel("Delete correction")
                    }.flowCard()
                }
            }.padding(30)
        }
        .confirmationDialog("Delete all learned corrections?", isPresented: $confirmClear) { Button("Delete corrections", role: .destructive, action: state.clearLearning) }
        .sheet(isPresented: $teaching) {
            VStack(alignment: .leading, spacing: 18) {
                Text("Teach a name or term").font(.title2.bold())
                Text("Enter what the model writes and the spelling you want. This rule applies immediately across apps.").font(.callout).foregroundStyle(.secondary)
                TextField("Heard as", text: $heard).textFieldStyle(.roundedBorder)
                TextField("Write as", text: $spelling).textFieldStyle(.roundedBorder)
                LabeledContent("Language") { SpeechLanguagePicker(title: "Spelling rule language", selection: $language, special: "*") }
                if invalid { Text("Use two different names or short phrases, up to 128 characters each.").font(.caption).foregroundStyle(Color.flowDanger) }
                HStack { Spacer(); Button("Cancel") { teaching = false }; Button("Save spelling") {
                    if state.teachName(from: heard, to: spelling, language: language) { heard = ""; spelling = ""; invalid = false; teaching = false }
                    else { invalid = true }
                }.buttonStyle(.borderedProminent).disabled(heard.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || spelling.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty) }
            }.padding(26).frame(width: 460)
        }
    }
}

struct SpeechProfileView: View {
    @Bindable var state: AppState
    var body: some View {
        let profile = state.profile
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Your voice, over time.").font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.6)
                Text("A private picture of your dictation habits, built from your saved transcripts.").font(.callout).foregroundStyle(.secondary)
                HStack(spacing: 12) {
                    ProfileMetric(title: "Dictation pace", value: profile.words > 0 ? "\(profile.pace) wpm" : "—", icon: "speedometer")
                    ProfileMetric(title: "Transcripts corrected", value: profile.correctedCount.formatted(), icon: "pencil.line")
                    ProfileMetric(title: "Personal terms", value: state.personalTerms.count.formatted(), icon: "text.book.closed")
                }
                VStack(alignment: .leading, spacing: 14) {
                    Text("Languages & dialect").font(.title3.bold())
                    if profile.languages.isEmpty { Text("Language use appears after your first saved dictation.").foregroundStyle(.secondary) }
                    ForEach(profile.languages, id: \.name) { item in
                        VStack(spacing: 8) {
                            HStack {
                                Text(SpeechLanguages.name(item.name))
                                Spacer()
                                Text("\(item.words.formatted()) words · \(profile.words > 0 ? Int(Double(item.words) / Double(profile.words) * 100) : 0)%").foregroundStyle(.secondary)
                            }.font(.callout)
                            ProgressView(value: Double(item.words), total: Double(max(1, profile.words))).tint(Color.flowAccent)
                        }
                    }
                    Divider()
                    TextField("My dialect or accent", text: Binding(get: { state.preferences.dialect ?? "" }, set: { state.preferences.dialect = $0 })).textFieldStyle(.roundedBorder)
                    Text("For example: Flemish, West Flemish, or British English. This is your own description; it does not change the speech model. Automatic language detection distinguishes languages, not dialects.").font(.caption).foregroundStyle(.secondary)
                }.flowCard()
                VStack(alignment: .leading, spacing: 14) {
                    Text("Phrases to reflect on").font(.title3.bold())
                    if profile.phrases.isEmpty {
                        Text("No selected filler phrases found in your saved transcripts yet.").font(.callout).foregroundStyle(.secondary)
                    } else {
                        ForEach(profile.phrases.prefix(6), id: \.name) { phrase in
                            HStack { Text("“\(phrase.name)”"); Spacer(); Text("\(phrase.count)×").monospacedDigit().foregroundStyle(.secondary) }.font(.callout)
                        }
                        Text("For clearer phrasing, try a brief pause where you would normally use a filler. These phrases can also be useful in natural conversation.").font(.callout).foregroundStyle(.secondary)
                    }
                    Text("Filler phrase analysis currently covers English and Dutch. Speech models may remove fillers. These counts describe saved text; they are not a grammar, pronunciation or fluency score.").font(.caption).foregroundStyle(.secondary)
                }.flowCard()
                Text("Language totals follow the selected or detected language. Pace includes pauses and uses estimated word boundaries, including languages without spaces. This profile excludes imported audio and follows retained history; deleting history changes these statistics. No audio recordings or voiceprints are stored.").font(.caption).foregroundStyle(.secondary)
            }.padding(30)
        }
    }
}

extension View {
    func flowCard() -> some View {
        self.padding(20).frame(maxWidth: .infinity, alignment: .leading)
            .background(.background, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(.primary.opacity(0.06), lineWidth: 1))
    }
}

private struct ProfileMetric: View {
    let title: String
    let value: String
    let icon: String
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: icon).foregroundStyle(Color.flowAccent).font(.system(size: 16, weight: .medium))
            Text(value).font(.system(size: 25, weight: .semibold, design: .rounded)).monospacedDigit()
            Text(title).font(.caption).foregroundStyle(.secondary)
        }.frame(maxWidth: .infinity, alignment: .leading).flowCard()
    }
}

struct FlowSettingsView: View {
    @Bindable var state: AppState
    var body: some View {
        Form {
            Section("General") {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Setup guide").font(.headline)
                        Text("Permissions, your microphone, and a safe place to try dictation.").font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Open setup guide", action: state.openSetup).disabled(state.phase != .idle)
                }
            }
            Section("Local speech model") {
                Picker("Model", selection: $state.preferences.model) { ForEach(SpeechModel.allCases) { Text($0.title).tag($0) } }.disabled(state.modelBusy || state.phase != .idle)
                    .onChange(of: state.preferences.model) { _, _ in Task { await state.loadModel(download: false) } }
                Text(state.preferences.model.detail).font(.callout).foregroundStyle(.secondary)
                Text(state.preferences.model.languageCoverage).font(.caption).foregroundStyle(Color.flowAccent)
                if !state.preferences.model.supports(state.preferences.language) {
                    Text("Choose Whisper for \(SpeechLanguages.name(state.preferences.language)), then download or load its model.").font(.callout).foregroundStyle(Color.flowWarning)
                }
                Text(state.modelStatus).font(.callout)
                if state.modelBusy { ProgressView(); if state.progress > 0 { ProgressView(value: state.progress) } }
                HStack {
                    Button("Download model") { Task { await state.loadModel(download: true) } }.buttonStyle(.borderedProminent)
                    Button("Load existing model") { Task { await state.loadModel(download: false) } }
                }.disabled(state.modelBusy || state.phase != .idle)
                Text("Downloads fetch free model files from Hugging Face. Loading and dictation use local files only. No account, subscription or API key.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Dictation") {
                HStack {
                    Picker("Input device", selection: Binding(get: { state.preferences.inputDeviceUID ?? "" }, set: { state.preferences.inputDeviceUID = $0.isEmpty ? nil : $0 })) {
                        Text("Automatic · \(state.systemInputName ?? "system input")").tag("")
                        ForEach(state.inputDevices) { device in Text(device.name).tag(device.id) }
                        if let selected = state.preferences.inputDeviceUID, !state.inputDevices.contains(where: { $0.id == selected }) {
                            Text("Selected microphone unavailable").tag(selected)
                        }
                    }
                    Button("Refresh", action: state.refreshInputDevices)
                }.disabled(state.phase != .idle)
                Text("Automatic follows your Mac’s input device. A selected microphone is remembered; switching applies to the next recording.").font(.caption).foregroundStyle(.secondary)
                Toggle("Middle mouse button starts and stops dictation", isOn: $state.preferences.middleMouse)
                HStack {
                    LabeledContent("Keyboard shortcut", value: state.capturingShortcut ? "Press your shortcut…" : state.keyboardShortcutLabel)
                    if state.capturingShortcut { Button("Cancel", action: state.cancelShortcutRecording) }
                    else {
                        Button("Record shortcut", action: state.recordShortcut)
                        Button("Reset") { state.preferences.keyboardShortcut = nil; state.refreshPermissions() }
                    }
                }.disabled(state.phase != .idle)
                Text("Include Command, Option or Control. Escape cancels shortcut recording. Your middle button continues to toggle independently.").font(.caption).foregroundStyle(.secondary)
                Picker("Keyboard behavior", selection: Binding(get: { state.preferences.keyboardHoldToTalk ?? false }, set: { state.preferences.keyboardHoldToTalk = $0 })) {
                    Text("Press to start and stop").tag(false)
                    Text("Hold to talk, release to finish").tag(true)
                }.disabled(state.phase != .idle)
                LabeledContent("Keyboard access", value: state.keyboardAvailable ? "Available" : "Unavailable")
                LabeledContent("Middle mouse access", value: state.mouseAvailable ? "Available" : (state.accessibility ? "Unavailable · Refresh access" : "Allow Accessibility, then refresh"))
                if let error = state.hotkeyError { Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(Color.flowWarning) }
                Toggle("Show live transcript preview", isOn: Binding(get: { state.preferences.livePreview ?? true }, set: { state.preferences.livePreview = $0 })).disabled(state.phase != .idle)
                Text("A provisional preview of the latest 12 seconds appears while you speak. It stays out of your text field until you finish. Preview adds local model work; Whisper can update more slowly.").font(.caption).foregroundStyle(.secondary)
                LabeledContent("Default language") { SpeechLanguagePicker(title: "Default language", selection: $state.preferences.language, model: state.preferences.model) }.disabled(state.phase != .idle)
                Toggle("Recognize spoken punctuation commands", isOn: $state.preferences.spokenPunctuation)
                Text("Commands currently cover English and Dutch: “new paragraph” or “nieuwe alinea”. Model punctuation is preserved in every language. Esc cancels.").font(.caption).foregroundStyle(.secondary)
                Picker("Maximum recording", selection: Binding(get: { state.recordingLimitMinutes }, set: { state.preferences.recordingLimitMinutes = $0 })) {
                    ForEach(1...30, id: \.self) { minutes in Text(minutes == 1 ? "1 minute" : "\(minutes) minutes").tag(minutes) }
                }.disabled(state.phase != .idle)
                Text("Choose 1–30 minutes. At the limit, dictation finishes and inserts your text. Longer recordings take more memory and may take longer to transcribe.").font(.caption).foregroundStyle(.secondary)
                Toggle("Finish automatically after a quiet pause", isOn: Binding(get: { state.preferences.autoStopSilence ?? false }, set: { state.preferences.autoStopSilence = $0 }))
                if state.preferences.autoStopSilence ?? false {
                    Picker("Quiet pause", selection: Binding(get: { state.preferences.silenceDelay ?? 5 }, set: { state.preferences.silenceDelay = $0 })) {
                        Text("3 seconds").tag(3.0); Text("5 seconds").tag(5.0); Text("8 seconds").tag(8.0); Text("10 seconds").tag(10.0)
                    }
                    Picker("Microphone sensitivity (next recording)", selection: Binding(get: { state.preferences.quietThresholdDB ?? -42 }, set: { state.preferences.quietThresholdDB = $0 })) {
                        Text("Quiet voice · −50 dB").tag(-50.0); Text("Balanced · −42 dB").tag(-42.0); Text("Noisy room · −34 dB").tag(-34.0)
                    }
                }
                Text("Off by default. After speech begins, a quiet pause can finish the recording and insert the text. This uses microphone loudness; background noise can keep it running. Adjust sensitivity for your room.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Local AI cleanup") {
                Toggle("Lightly polish dictation before inserting", isOn: Binding(get: { state.preferences.localCleanup ?? false }, set: { state.preferences.localCleanup = $0 })).disabled(state.phase != .idle)
                Label(state.cleanupAvailability, systemImage: "cpu").font(.callout).foregroundStyle(.secondary)
                Text("Optional, off by default. Uses Apple’s on-device model to tidy fillers, obvious grammar slips and spoken self-corrections. Requires macOS 26+, Apple Intelligence and a supported language. No account or cloud fallback. If unavailable, too long, or unsuccessful, your original transcript is used. AI can change wording; review important text. Snippets expand afterward to preserve their exact saved text.").font(.caption).foregroundStyle(.secondary)
            }
            Section("Permissions and privacy") {
                HStack {
                    LabeledContent("Microphone", value: state.microphoneStatus)
                    if state.microphoneStatus == "Not requested" { Button("Allow microphone", action: state.requestMicrophone) }
                    else if state.microphoneStatus != "Allowed" { Button("Open microphone settings", action: state.openMicrophoneSettings) }
                }
                HStack {
                    Label(state.accessibility ? "Accessibility allowed" : "Accessibility needed", systemImage: state.accessibility ? "checkmark.circle" : "hand.raised")
                    Spacer()
                    if !state.accessibility { Button("Allow Accessibility", action: state.requestAccessibility) }
                    Button("Refresh", action: state.refreshPermissions)
                }
                if !state.accessibility {
                    Text("Already enabled in macOS? Remove the old Open Quill entry, add the current app again, enable it, then quit and reopen Open Quill. The app checks actual access, not the saved switch.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                Toggle("Keep dictation history", isOn: $state.preferences.keepHistory)
                Toggle("Learn from corrections in dictated text", isOn: $state.preferences.learnCorrections)
                Toggle("Allow clipboard paste for unsupported text fields", isOn: $state.preferences.clipboardFallback)
                Text("Clipboard fallback briefly uses the system clipboard, which may sync through Universal Clipboard. It is off by default. Password fields are excluded.").font(.caption).foregroundStyle(.secondary)
                Button("Show local data folder") { NSWorkspace.shared.open(SpeechEngine.root) }
                Text("Stores up to 1,000 transcripts. Audio is never saved. Turning history off stops new entries; existing entries can be deleted in History.").font(.caption).foregroundStyle(.secondary)
            }
            if !state.preferences.apps.isEmpty {
                Section("App preferences") {
                    ForEach($state.preferences.apps) { $app in
                        VStack(alignment: .leading, spacing: 10) {
                            Text(app.name).font(.headline)
                            LabeledContent("Language") { SpeechLanguagePicker(title: "Language for \(app.name)", selection: $app.language, model: state.preferences.model, special: "default") }.disabled(state.phase != .idle)
                            Picker("Spoken punctuation commands", selection: $app.spokenPunctuation) {
                                Text("Use default").tag(Optional<Bool>.none)
                                Text("Enabled").tag(Optional.some(true))
                                Text("Disabled").tag(Optional.some(false))
                            }
                            Picker("Local AI cleanup", selection: $app.localCleanup) {
                                Text("Use default").tag(Optional<Bool>.none)
                                Text("Enabled").tag(Optional.some(true))
                                Text("Disabled").tag(Optional.some(false))
                            }.disabled(state.phase != .idle)
                            Toggle("Press Enter after dictation", isOn: Binding(get: { app.pressEnterAfterDictation ?? false }, set: { app.pressEnterAfterDictation = $0 }))
                            Text("Only for \(app.name). Enter is pressed after text delivery if the original field still has focus. In chat apps, this may send your message. Turn it off to learn from draft corrections before sending. Off by default.").font(.caption).foregroundStyle(.secondary)
                        }.padding(.vertical, 6)
                    }
                }
            }
            Section("Open model credits") {
                Text("Parakeet Ultra: Moondream / NVIDIA, CC BY 4.0. FluidAudio: Apache 2.0. Whisper / WhisperKit: MIT. See THIRD_PARTY_NOTICES.md in the source for links and licenses.").font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped).onAppear(perform: state.refreshInputDevices).onDisappear(perform: state.cancelShortcutRecording)
    }
}
