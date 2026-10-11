import AppKit
import SwiftUI
import FlowCore

@Observable @MainActor
final class TextFieldCheckState {
    var status = "Focus an empty Claude draft during the countdown. Nothing is submitted."
    var busy = false
    var anchor: SpanAnchor?
    let fixture = "Send this to Quillzeta tomorrow."

    func finish(_ message: String) {
        status = message
        let file = Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("text-field-check-result.txt")
        try? message.write(to: file, atomically: true, encoding: .utf8)
    }

    func insert() {
        guard !busy else { return }
        busy = true; anchor = nil; status = "Focus the empty Claude prompt within 10 seconds."
        Task {
            defer { busy = false }
            try? await Task.sleep(for: .seconds(10))
            guard let target = TextTarget.capture(), target.bundleID == "com.anthropic.claudefordesktop",
                  !target.secure, let value = target.value, ["", "\n"].contains(value),
                  target.selection?.location == 0, target.selection?.length == 0 else {
                finish("SKIPPED: an empty Claude prompt must be focused."); return
            }
            let result = await target.insert(fixture, allowPaste: false, pressEnter: false)
            guard let verified = result.anchor, verified.prefix.isEmpty, verified.suffix.isEmpty,
                  verified.inserted == fixture, TextTarget.textValue(verified.element) == fixture else {
                finish("FAIL: empty draft insertion could not be verified (\(result.status))."); return
            }
            anchor = verified
            finish("PASS: exact insertion verified. Change Quillzeta to Quillzetta in Claude, then check the correction.")
        }
    }

    func correction() {
        guard !busy, let anchor else { return }
        busy = true; status = "Focus the corrected Claude prompt within 10 seconds."
        Task {
            defer { busy = false }
            try? await Task.sleep(for: .seconds(10))
            guard anchor.target.stillFocused, let value = TextTarget.textValue(anchor.element),
                  let edited = TextProcessing.editedSpan(value: value, prefix: anchor.prefix, suffix: anchor.suffix),
                  edited == "Send this to Quillzetta tomorrow.",
                  let change = TextProcessing.correction(original: anchor.inserted, edited: edited, requireSharedContext: true),
                  change.from == "Quillzeta", change.to == "Quillzetta" else {
                finish("FAIL: destination correction was not an exact anchored name edit."); return
            }
            finish("PASS: exact insertion and destination name correction verified. Remove the unsent test draft.")
        }
    }
}

@main struct TextFieldCheck: App {
    @State private var state = TextFieldCheckState()
    var body: some Scene {
        Window("Open Quill Text Field Check", id: "check") {
            VStack(alignment: .leading, spacing: 20) {
                Text("Claude text delivery check").font(.title)
                Text(state.status).textSelection(.enabled)
                Button("Insert test text in 10 seconds", action: state.insert).disabled(state.busy)
                Button("Check destination correction in 10 seconds", action: state.correction)
                    .disabled(state.busy || state.anchor == nil)
            }.padding(32).frame(width: 620, height: 260)
        }
    }
}
