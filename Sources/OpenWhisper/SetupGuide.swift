import SwiftUI

struct SetupGuide: View {
    @Bindable var state: AppState
    let reviewSettings: () -> Void
    let startDictating: () -> Void
    @State private var step = 0
    @State private var completed = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var scratchFocused: Bool
    private let steps = ["Welcome", "Permissions", "Speech model", "Your controls", "Practice"]

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Label("Open Whisper", systemImage: "waveform").font(.system(size: 13, weight: .semibold))
                Spacer()
                HStack(spacing: 6) {
                    ForEach(steps.indices, id: \.self) { index in
                        Capsule().fill(index <= step ? Color.flowAccent : Color.flowSeparator)
                            .frame(width: index == step ? 36 : 22, height: 4).help(steps[index])
                    }
                }.accessibilityElement(children: .ignore).accessibilityLabel("Setup: \(steps[step]), step \(step + 1) of 5")
                Spacer()
                Button("Skip setup") { state.closeSetup(skipped: true); startDictating() }
                    .buttonStyle(.borderless).foregroundStyle(Color.flowSecondary).disabled(state.phase == .inserting)
            }.padding(.bottom, 20)

            ScrollView {
                VStack(spacing: 24) {
                    if completed { completion }
                    else {
                        switch step {
                        case 0: welcome
                        case 1: permissions
                        case 2: model
                        case 3: controls
                        default: practice
                        }
                    }
                    if let notice = state.notice {
                        Label(notice, systemImage: "info.circle")
                            .font(.system(size: 12)).foregroundStyle(Color.flowWarning).frame(maxWidth: 550)
                    }
                }.frame(maxWidth: .infinity).padding(.vertical, 16)
            }.scrollIndicators(.hidden)
            HStack {
                if step > 0 && !completed {
                    Button("Back") { move(to: step - 1) }.buttonStyle(.borderless)
                        .keyboardShortcut("[", modifiers: .command).disabled(state.phase != .idle)
                }
                Spacer()
                if step == 1 && !permissionsReady {
                    Button("Continue without") { move(to: 2) }.buttonStyle(.borderless)
                }
                if completed {
                    Button("Review settings") {
                        state.closeSetup(skipped: !state.readyToDictate); reviewSettings()
                    }.buttonStyle(.borderless)
                }
                Button(primaryTitle, action: advance).buttonStyle(.borderedProminent)
                    .controlSize(.large).keyboardShortcut(.defaultAction)
                    .disabled(state.phase != .idle || (step == 1 && !permissionsReady))
            }.padding(.top, 20)
        }.padding(32).background(Color.flowCanvas).foregroundStyle(Color.flowText)
            .animation(reduceMotion ? nil : .easeOut(duration: 0.18), value: step)
            .onDisappear { state.leavePractice() }
            .onChange(of: state.practiceFinished) { _, done in if done { scratchFocused = true } }
    }

    private var permissionsReady: Bool { state.microphoneStatus == "Allowed" && state.accessibility }
    private var primaryTitle: String {
        if completed { return state.readyToDictate ? "Start dictating" : "Open dictation" }
        if step == 0 { return "Get started" }
        if step == 2 && !state.modelReady && !state.modelBusy { return "Download \(state.preferences.model.title)" }
        return step == 4 ? "Finish setup" : "Continue"
    }
    private func advance() {
        if completed { state.closeSetup(skipped: !state.readyToDictate); startDictating(); return }
        if step == 2 && !state.modelReady && !state.modelBusy {
            Task { await state.loadModel(download: true) }; return
        }
        if step == 4 { state.leavePractice(); completed = true }
        else { move(to: step + 1) }
    }
    private func move(to destination: Int) {
        state.leavePractice(); state.notice = nil
        step = destination; state.practiceActive = destination == 4
        if destination == 3 { state.refreshInputDevices() }
        if destination == 4 { state.practiceLanguage = state.preferences.language }
    }
    private func heading(_ title: String, _ subtitle: String) -> some View {
        VStack(spacing: 10) {
            Text(title).font(.system(size: 28, weight: .semibold, design: .rounded)).tracking(-0.3)
            Text(subtitle).font(.system(size: 13)).foregroundStyle(Color.flowSecondary).lineSpacing(3)
        }.multilineTextAlignment(.center).frame(maxWidth: 560)
    }

    private var welcome: some View {
        VStack(spacing: 24) {
            ZStack {
                Circle().fill(Color.flowSoft).frame(width: 210, height: 210)
                VStack(spacing: 0) {
                    HStack(spacing: 5) {
                        ForEach(0..<3) { _ in Circle().fill(Color.flowSeparator).frame(width: 6, height: 6) }
                        Spacer()
                    }.padding(12)
                    VStack(alignment: .leading, spacing: 16) {
                        Label("Your words, typed where you are.", systemImage: "text.cursor")
                            .font(.system(size: 16, weight: .medium)).foregroundStyle(Color.flowText)
                        HStack(spacing: 10) {
                            Image(systemName: "waveform").font(.system(size: 24)).foregroundStyle(Color.flowAccent)
                            Text("Meet me at the station at nine.").font(.system(size: 12)).foregroundStyle(Color.flowSecondary)
                        }.padding(12).background(Color.flowSoft, in: RoundedRectangle(cornerRadius: 10))
                    }.padding(.horizontal, 24).padding(.bottom, 24)
                }.frame(width: 380).background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.flowSeparator))
            }.frame(height: 210).accessibilityHidden(true)
            heading("Your voice stays on this Mac.", "Open Whisper turns speech into text locally. Free and open source.")
            HStack(spacing: 10) {
                promise("No account", "person.crop.circle.badge.xmark")
                promise("No cloud transcription", "icloud.slash")
                promise("No audio saved", "waveform.slash")
            }
            Text("The only download is the speech model, when you choose it.")
                .font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
        }
    }
    private func promise(_ text: String, _ symbol: String) -> some View {
        Label(text, systemImage: symbol).font(.system(size: 11, weight: .medium))
            .foregroundStyle(Color.flowAccentText).padding(.horizontal, 12).padding(.vertical, 8)
            .background(Color.flowSoft, in: Capsule())
    }

    private var permissions: some View {
        VStack(spacing: 24) {
            heading("Two permissions, both yours to give.", "Hear your voice. Put your words in the app you’re using.")
            HStack(alignment: .top, spacing: 16) {
                permissionCard("Microphone", symbol: "mic", reason: "To hear you while you dictate. Audio isn’t saved.", allowed: state.microphoneStatus == "Allowed", status: state.microphoneStatus, denied: state.microphoneStatus == "Not allowed") {
                    if state.microphoneStatus == "Not requested" { Button("Allow microphone", action: state.requestMicrophone) }
                    else { Button("Open privacy settings", action: state.openMicrophoneSettings) }
                }
                permissionCard("Accessibility", symbol: "accessibility", reason: "To type into your focused text field and learn from draft edits.", allowed: state.accessibility, status: state.accessibility ? "Allowed" : "Access needed") {
                    Button("Allow Accessibility", action: state.requestAccessibility)
                }
            }.frame(maxWidth: 580)
            Text("You’re in control. macOS grants access only when you approve it.")
                .font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
        }
    }
    private func permissionCard<Actions: View>(_ title: String, symbol: String, reason: String, allowed: Bool, status: String, denied: Bool = false, @ViewBuilder actions: () -> Actions) -> some View {
        VStack(spacing: 14) {
            Image(systemName: symbol).font(.system(size: 24)).foregroundStyle(Color.flowAccent)
                .frame(width: 56, height: 56).background(Color.flowSoft, in: Circle())
            Text(title).font(.system(size: 15, weight: .semibold))
            Text(reason).font(.system(size: 12)).foregroundStyle(Color.flowSecondary)
                .multilineTextAlignment(.center).frame(height: 36)
            Label(status, systemImage: allowed ? "checkmark.circle.fill" : (denied ? "exclamationmark.circle.fill" : "circle"))
                .font(.system(size: 12, weight: .medium)).foregroundStyle(allowed ? Color.flowAccent : (denied ? Color.flowDanger : Color.flowSecondary))
            if !allowed { actions().buttonStyle(.bordered).controlSize(.large) }
        }.frame(maxWidth: .infinity).padding(24)
            .background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
            .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.flowSeparator))
    }

    private var model: some View {
        VStack(spacing: 24) {
            heading("Choose your speech model.", "One download. After this, dictation runs offline.")
            VStack(spacing: 18) {
                HStack(spacing: 28) {
                    Image(systemName: "internaldrive").font(.system(size: 42, weight: .light))
                    Image(systemName: "arrow.right").font(.system(size: 18)).foregroundStyle(Color.flowSecondary)
                    Image(systemName: "cpu").font(.system(size: 42, weight: .light))
                }.foregroundStyle(Color.flowAccent).padding(.vertical, 8).accessibilityHidden(true)
                Picker("Speech model", selection: $state.preferences.model) {
                    ForEach(SpeechModel.allCases) { item in Text(item.title).tag(item) }
                }.pickerStyle(.menu).disabled(state.modelBusy)
                    .onChange(of: state.preferences.model) { _, _ in Task { await state.loadModel(download: false, showError: false) } }
                Text(state.preferences.model.detail).font(.system(size: 12)).foregroundStyle(Color.flowSecondary)
                Text(state.preferences.model.languageCoverage).font(.system(size: 12, weight: .medium)).foregroundStyle(Color.flowAccent)
                Text("Parakeet covers 25 languages. Whisper opens the full 100-language catalog.")
                    .font(.system(size: 11)).foregroundStyle(Color.flowSecondary).multilineTextAlignment(.center)
                if state.modelReady {
                    Label("Installed and running locally", systemImage: "checkmark.circle.fill").foregroundStyle(Color.flowAccent)
                } else if state.modelBusy {
                    if state.progress > 0 { ProgressView(value: state.progress).tint(Color.flowAccent) }
                    else { ProgressView().controlSize(.small) }
                    Text(state.modelStatus).font(.system(size: 12)).foregroundStyle(Color.flowSecondary)
                    Text("You can continue while preparation finishes.").font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
                }
            }.padding(24).frame(maxWidth: 520).background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.flowSeparator))
            Text("Free model files from Hugging Face. No account or API key.")
                .font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
        }
    }

    private var controls: some View {
        VStack(spacing: 24) {
            HStack(spacing: 70) {
                VStack(spacing: 16) {
                    MouseShortcutSymbol(size: 64)
                    Text("Middle-click").font(.system(size: 12, weight: .medium))
                }
                Text("or").foregroundStyle(Color.flowSecondary)
                VStack(spacing: 16) {
                    Text(state.keyboardShortcutLabel).font(.system(size: 25, weight: .medium)).padding(16)
                        .background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 10))
                        .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.flowSeparator))
                    Text("Keyboard shortcut").font(.system(size: 12, weight: .medium))
                }
            }.frame(height: 100)
            heading("Start and stop, your way.", state.preferences.keyboardHoldToTalk == true ? "Hold your keyboard shortcut to speak; release to finish. The middle button toggles. Escape cancels." : "Press once to speak. Press again to finish. Escape cancels.")
            VStack(alignment: .leading, spacing: 16) {
                Toggle("Use the middle mouse button", isOn: $state.preferences.middleMouse)
                LabeledContent("Dictation language") {
                    SpeechLanguagePicker(title: "Dictation language", selection: $state.preferences.language, model: state.preferences.model)
                }
                if !state.preferences.model.supports(state.preferences.language) {
                    Button("Choose Whisper for \(SpeechLanguages.name(state.preferences.language))") { move(to: 2) }.buttonStyle(.borderless)
                }
                Picker("Input device", selection: Binding(get: { state.preferences.inputDeviceUID ?? "" }, set: { state.preferences.inputDeviceUID = $0.isEmpty ? nil : $0 })) {
                    Text("Automatic · \(state.systemInputName ?? "system input")").tag("")
                    ForEach(state.inputDevices) { item in Text(item.name).tag(item.id) }
                    if let selected = state.preferences.inputDeviceUID, !state.inputDevices.contains(where: { $0.id == selected }) {
                        Text("Selected microphone unavailable").tag(selected)
                    }
                }
                HStack {
                    Text("The microphone choice is remembered.").font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
                    Spacer(); Button("Refresh", action: state.refreshInputDevices).buttonStyle(.borderless)
                }
                if let error = state.hotkeyError { Label(error, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(Color.flowWarning) }
            }.padding(24).frame(maxWidth: 520).background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
                .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.flowSeparator))
        }
    }

    private var practice: some View {
        VStack(spacing: 20) {
            heading("Try it here first.", "A scratch space just for you. No messages sent. No history saved.")
            if let notice = state.notice { Label(notice, systemImage: "info.circle").font(.callout).foregroundStyle(Color.flowWarning).multilineTextAlignment(.center) }
            SpeechLanguagePicker(title: "Practice language", selection: $state.practiceLanguage, model: state.preferences.model)
                .buttonStyle(.bordered).disabled(state.phase != .idle)
            if state.modelReady && state.microphoneStatus == "Allowed" && state.inputDeviceAvailable && state.preferences.model.supports(state.practiceLanguage) {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Label(state.phase == .idle ? "Your practice space" : state.phase.title, systemImage: "waveform")
                        Spacer()
                        if state.phase == .recording { ProgressView(value: Double(state.level)).frame(width: 100).tint(Color.flowAccent) }
                    }.font(.system(size: 12, weight: .medium)).foregroundStyle(Color.flowAccent)
                    ZStack(alignment: .topLeading) {
                        if state.practiceText.isEmpty { Text("Your words will appear here.").foregroundStyle(Color.flowSecondary).padding(5) }
                        TextEditor(text: $state.practiceText).font(.system(size: 15)).scrollContentBackground(.hidden)
                            .focused($scratchFocused).accessibilityLabel("Practice text, never sent or saved")
                    }.frame(height: 115)
                    if state.phase == .recording && !state.liveTranscript.isEmpty {
                        Text(state.liveTranscript).font(.callout).foregroundStyle(Color.flowSecondary).lineLimit(2)
                            .accessibilityLabel("Live preview: \(state.liveTranscript)")
                    }
                    Divider()
                    Text(practicePrompt)
                        .font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
                }.padding(20).frame(maxWidth: 520).background(Color.flowRaised, in: RoundedRectangle(cornerRadius: 16))
                    .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.flowSeparator))
                HStack(spacing: 12) {
                    Button(state.phase == .recording ? "Finish practice" : "Start practice", action: state.toggle)
                        .buttonStyle(.bordered).disabled(state.phase != .idle && state.phase != .recording)
                    if state.phase != .idle { Button("Cancel", action: state.cancel).disabled(state.phase == .inserting) }
                    if state.practiceFinished { Label("That’s your voice, typed locally.", systemImage: "checkmark.circle").font(.system(size: 12)).foregroundStyle(Color.flowAccent) }
                }
            Text("\(state.shortcutAvailable ? "You can also use \(state.shortcutLabel)." : "Use Start practice above; dictation shortcuts are unavailable.") Practice text disappears when you leave.")
                    .font(.system(size: 11)).foregroundStyle(Color.flowSecondary)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "waveform").font(.system(size: 38, weight: .light)).foregroundStyle(Color.flowAccent)
                    summary("Microphone: \(state.microphoneStatus)", ready: state.microphoneStatus == "Allowed")
                    summary(state.inputDeviceName, ready: state.inputDeviceAvailable)
                    summary(state.modelStatus, ready: state.modelReady)
                    if !state.preferences.model.supports(state.practiceLanguage) {
                        Text("\(SpeechLanguages.name(state.practiceLanguage)) requires a Whisper model.").font(.callout).foregroundStyle(Color.flowSecondary)
                    }
                    if state.modelBusy { ProgressView().controlSize(.small); if state.progress > 0 { ProgressView(value: state.progress) } }
                    if state.microphoneStatus != "Allowed" { Button("Set up microphone access") { move(to: 1) }.buttonStyle(.bordered) }
                    if !state.inputDeviceAvailable { Button("Choose microphone") { move(to: 3) }.buttonStyle(.bordered) }
                    if !state.modelReady || !state.preferences.model.supports(state.practiceLanguage) { Button(state.modelBusy ? "View model preparation" : "Set up speech model") { move(to: 2) }.buttonStyle(.bordered) }
                    Text("You can finish now and try dictation later.").font(.system(size: 12)).foregroundStyle(Color.flowSecondary)
                }.padding(32).frame(maxWidth: 520).background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
            }
        }
    }

    private var practicePrompt: String {
        switch state.practiceLanguage {
        case "nl": "Probeer: “Ik bel je morgen terug.”"
        case "en": "Try: “Meet me at the station at nine.”"
        case "auto": "Say a short sentence in any language supported by your model."
        default: "Say a short sentence in \(SpeechLanguages.name(state.practiceLanguage))."
        }
    }

    private var completion: some View {
        VStack(spacing: 24) {
            Image(systemName: state.readyToDictate ? "checkmark.seal" : "sparkles")
                .font(.system(size: 56, weight: .light)).foregroundStyle(Color.flowAccent)
                .frame(width: 110, height: 110).background(Color.flowSoft, in: Circle())
            heading(state.readyToDictate ? "You’re ready." : "Your setup, at your pace.",
                    "Dictate into your app. Draft edits there can teach Open Whisper your words.")
            VStack(alignment: .leading, spacing: 16) {
                summary(state.modelReady ? "Speech model installed" : "Speech model still needed", ready: state.modelReady)
                summary("Language: \(SpeechLanguages.name(state.preferences.language))\(state.preferences.model.supports(state.preferences.language) ? "" : " — choose Whisper")", ready: state.preferences.model.supports(state.preferences.language))
                summary("Microphone: \(state.inputDeviceName)", ready: state.microphoneStatus == "Allowed" && state.inputDeviceAvailable)
                summary(state.accessibility ? "Text-field access allowed" : "Accessibility still needed", ready: state.accessibility)
                summary(state.shortcutLabel, ready: state.shortcutAvailable)
            }.font(.system(size: 13)).padding(24).frame(maxWidth: 520, alignment: .leading)
                .background(Color.flowSurface, in: RoundedRectangle(cornerRadius: 16))
            Text("Some apps don’t expose editable text. Learning only runs when the field can be verified.")
                .font(.system(size: 11)).foregroundStyle(Color.flowSecondary).multilineTextAlignment(.center).frame(maxWidth: 520)
        }
    }
    private func summary(_ text: String, ready: Bool) -> some View {
        Label(text, systemImage: ready ? "checkmark.circle.fill" : "circle")
            .foregroundStyle(ready ? Color.flowAccent : Color.flowSecondary)
    }
}
