import AppKit
import SwiftUI
import Foundation

@main
enum OpenWhisperEntry {
    static func main() {
        let args = CommandLine.arguments
        if args.contains("--transcribe") || args.contains("--download-model") {
            Task {
                do {
                    func value(_ key: String) -> String? {
                        guard let index = args.firstIndex(of: key), index + 1 < args.count else { return nil }
                        return args[index + 1]
                    }
                    let modelName = value("--model") ?? SpeechModel.parakeet.rawValue
                    guard let model = SpeechModel(rawValue: modelName) else { throw FlowError.message("Unknown model: \(modelName)") }
                    let engine = SpeechEngine()
                    try await engine.prepare(model, download: args.contains("--download-model"))
                    if let path = value("--transcribe") {
                        let result = try await engine.transcribeFile(URL(fileURLWithPath: path), language: value("--language") ?? "en")
                        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                        let json = try encoder.encode(result)
                        FileHandle.standardOutput.write(json); FileHandle.standardOutput.write(Data("\n".utf8))
                    } else { print("Ready: \(model.title)") }
                    exit(0)
                } catch {
                    FileHandle.standardError.write(Data("\(error.localizedDescription)\n".utf8)); exit(1)
                }
            }
            dispatchMain()
        } else {
            OpenWhisperApplication.main()
        }
    }
}

@MainActor
final class FlowAppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}

struct OpenWhisperApplication: App {
    @NSApplicationDelegateAdaptor(FlowAppDelegate.self) private var delegate
    @State private var state = AppState()
    var body: some Scene {
        Window("Open Whisper", id: "main") {
            FlowWindow(state: state)
        }
        .defaultSize(width: 980, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(after: .appInfo) {
                Button("Transcribe audio file…", action: state.transcribeFile).disabled(!state.modelReady || state.phase != .idle)
            }
            CommandGroup(replacing: .help) {
                Button("Show Setup Guide…", action: state.openSetup).disabled(state.phase != .idle)
            }
        }
        MenuBarExtra {
            FlowMenu(state: state)
        } label: {
            Image(systemName: state.phase == .recording ? "mic.fill" : "waveform")
                .accessibilityLabel("Open Whisper")
        }
    }
}

struct FlowMenu: View {
    @Bindable var state: AppState
    @Environment(\.openWindow) private var openWindow
    var body: some View {
        Text(state.phase == .idle ? state.modelStatus : state.phase.title)
        Button(state.phase == .recording ? "Finish dictation" : "Start dictation") { state.toggle() }
            .disabled(!state.modelReady || (state.phase != .idle && state.phase != .recording))
        if state.phase != .idle && state.phase != .inserting { Button("Cancel", action: state.cancel) }
        Divider()
        Button("Open Open Whisper") { openWindow(id: "main"); NSApp.activate(ignoringOtherApps: true) }
        if !state.lastText.isEmpty { Button("Copy latest dictation") { state.copy(state.lastText) } }
        Divider()
        Button("Quit Open Whisper") { state.cancel(); NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
