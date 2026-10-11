import AppKit
import ApplicationServices
import Carbon
import SwiftUI
import Observation
import FlowCore

struct DictationShortcut: Codable, Equatable, Sendable {
    var keyCode: UInt32 = UInt32(kVK_Space)
    var modifiers: UInt32 = UInt32(optionKey)
    var key: String = "Space"
    var label: String {
        (modifiers & UInt32(controlKey) != 0 ? "⌃" : "") +
        (modifiers & UInt32(optionKey) != 0 ? "⌥" : "") +
        (modifiers & UInt32(shiftKey) != 0 ? "⇧" : "") +
        (modifiers & UInt32(cmdKey) != 0 ? "⌘" : "") + " " + key
    }
}

@MainActor
final class DictationTriggers {
    var onToggle: (() -> Void)?
    var onStart: (() -> Void)?
    var onFinish: (() -> Void)?
    var onCancel: (() -> Void)?
    var middleEnabled = true
    var holdToTalk = false
    private(set) var shortcut = DictationShortcut()
    private var hotkey: EventHotKeyRef?
    private var handler: EventHandlerRef?
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?
    private var shortcutMonitor: Any?
    private var captured: ((DictationShortcut?) -> Void)?
    var hotkeyError: String?
    var mouseAvailable: Bool { tap != nil }
    var keyboardAvailable: Bool { handler != nil && hotkey != nil }

    func useShortcut(_ value: DictationShortcut) {
        guard value != shortcut else { return }
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil; shortcut = value; register()
    }
    func captureShortcut(_ completion: @escaping (DictationShortcut?) -> Void) {
        cancelShortcutCapture()
        if let hotkey { UnregisterEventHotKey(hotkey) }
        hotkey = nil; captured = completion
        shortcutMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let consumed = MainActor.assumeIsolated {
                guard let self else { return false }
                if event.keyCode == 53 { self.endShortcutCapture(nil); return true }
                let flags = event.modifierFlags
                guard !event.isARepeat, !flags.intersection([.command, .option, .control]).isEmpty else {
                    self.hotkeyError = "Include Command, Option or Control in your shortcut."; return true
                }
                var modifiers: UInt32 = 0
                if flags.contains(.command) { modifiers |= UInt32(cmdKey) }
                if flags.contains(.option) { modifiers |= UInt32(optionKey) }
                if flags.contains(.control) { modifiers |= UInt32(controlKey) }
                if flags.contains(.shift) { modifiers |= UInt32(shiftKey) }
                let labels: [UInt16: String] = [49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 123: "←", 124: "→", 125: "↓", 126: "↑"]
                let key = labels[event.keyCode] ?? event.characters(byApplyingModifiers: [])?.uppercased() ?? "Key \(event.keyCode)"
                self.endShortcutCapture(DictationShortcut(keyCode: UInt32(event.keyCode), modifiers: modifiers, key: key))
                return true
            }
            return consumed ? nil : event
        }
        if shortcutMonitor == nil { endShortcutCapture(nil) }
    }
    func cancelShortcutCapture() { if captured != nil { endShortcutCapture(nil) } }
    private func endShortcutCapture(_ value: DictationShortcut?) {
        if let shortcutMonitor { NSEvent.removeMonitor(shortcutMonitor) }
        shortcutMonitor = nil
        let completion = captured; captured = nil
        if let value { useShortcut(value) }
        register(); completion?(value)
    }
    func register() {
        guard shortcutMonitor == nil else { return }
        let context = Unmanaged.passUnretained(self).toOpaque()
        if handler == nil {
            var events = [EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed)),
                          EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyReleased))]
            let status = InstallEventHandler(GetApplicationEventTarget(), { _, event, pointer in
                guard let pointer, let event else { return OSStatus(eventNotHandledErr) }
                MainActor.assumeIsolated {
                    let owner = Unmanaged<DictationTriggers>.fromOpaque(pointer).takeUnretainedValue()
                    if GetEventKind(event) == UInt32(kEventHotKeyReleased) {
                        if owner.holdToTalk { owner.onFinish?() }
                    } else if owner.holdToTalk { owner.onStart?() }
                    else { owner.onToggle?() }
                }
                return noErr
            }, events.count, &events, context, &handler)
            if status != noErr { hotkeyError = "Keyboard shortcut handler unavailable (\(status))." }
        }
        if handler != nil && hotkey == nil {
            // Non-exclusive registration can succeed while another app suppresses events.
            let status = RegisterEventHotKey(shortcut.keyCode, shortcut.modifiers, EventHotKeyID(signature: 0x57464C57, id: 1), GetApplicationEventTarget(), UInt32(kEventHotKeyExclusive), &hotkey)
            hotkeyError = status == noErr ? nil : "\(shortcut.label) is unavailable (\(status)). Another app may be using it."
        }
        guard tap == nil, AXIsProcessTrusted() else { return }
        let mask = (CGEventMask(1) << CGEventType.otherMouseDown.rawValue) | (CGEventMask(1) << CGEventType.otherMouseUp.rawValue) | (CGEventMask(1) << CGEventType.keyDown.rawValue)
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
            eventsOfInterest: mask, callback: { _, type, event, pointer in
                guard let pointer else { return Unmanaged.passUnretained(event) }
                let consumed = MainActor.assumeIsolated {
                    let owner = Unmanaged<DictationTriggers>.fromOpaque(pointer).takeUnretainedValue()
                    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                        if let tap = owner.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    }
                    guard owner.shortcutMonitor == nil else { return false }
                    if owner.middleEnabled && (type == .otherMouseDown || type == .otherMouseUp) && event.getIntegerValueField(.mouseEventButtonNumber) == 2 {
                        if type == .otherMouseDown { owner.onToggle?() }
                        return true
                    }
                    if type == .keyDown && event.getIntegerValueField(.keyboardEventKeycode) == 53 { owner.onCancel?() }
                    return false
                }
                return consumed ? nil : Unmanaged.passUnretained(event)
            }, userInfo: context)
        if let tap {
            source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
            CGEvent.tapEnable(tap: tap, enable: true)
        }
    }
}

@MainActor
struct TextTarget {
    private static var accessibilityRequested = Set<pid_t>()
    let app: NSRunningApplication
    let element: AXUIElement?
    let value: String?
    let selection: CFRange?
    let secure: Bool
    var appName: String { app.localizedName ?? "Unknown app" }
    var bundleID: String { app.bundleIdentifier ?? "unknown" }
    var screen: NSScreen? {
        let root = AXUIElementCreateApplication(app.processIdentifier)
        guard let rawWindow = Self.attribute(root, kAXFocusedWindowAttribute), CFGetTypeID(rawWindow) == AXUIElementGetTypeID() else { return nil }
        let window = rawWindow as! AXUIElement
        guard let rawPosition = Self.attribute(window, kAXPositionAttribute), CFGetTypeID(rawPosition) == AXValueGetTypeID(),
              let rawSize = Self.attribute(window, kAXSizeAttribute), CFGetTypeID(rawSize) == AXValueGetTypeID() else { return nil }
        var position = CGPoint.zero, size = CGSize.zero
        guard AXValueGetValue(rawPosition as! AXValue, .cgPoint, &position),
              AXValueGetValue(rawSize as! AXValue, .cgSize, &size),
              position.x.isFinite, position.y.isFinite, size.width.isFinite, size.height.isFinite else { return nil }
        // AX coordinates start at the primary display's top-left; AppKit starts at its bottom-left.
        let primaryTop = NSScreen.screens.first?.frame.maxY ?? 0
        let center = NSPoint(x: position.x + size.width / 2, y: primaryTop - position.y - size.height / 2)
        return NSScreen.screens.first { $0.frame.contains(center) }
    }

    static func capture() -> TextTarget? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              app.processIdentifier != ProcessInfo.processInfo.processIdentifier else { return nil }
        let root = AXUIElementCreateApplication(app.processIdentifier)
        if accessibilityRequested.insert(app.processIdentifier).inserted,
           let url = app.bundleURL,
           FileManager.default.fileExists(atPath: url.appendingPathComponent("Contents/Frameworks/Electron Framework.framework").path) {
            // Electron documents this assistive-technology flag for exposing its web text tree.
            // It neither grants macOS permission nor logs keyboard input.
            AXUIElementSetAttributeValue(root, "AXManualAccessibility" as CFString, kCFBooleanTrue)
        }
        var focused: CFTypeRef?
        AXUIElementCopyAttributeValue(root, kAXFocusedUIElementAttribute as CFString, &focused)
        guard let focused, CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return TextTarget(app: app, element: nil, value: nil, selection: nil, secure: false)
        }
        let element = focused as! AXUIElement
        let secure = attribute(element, kAXSubroleAttribute) as? String == kAXSecureTextFieldSubrole
        guard !secure else { return TextTarget(app: app, element: element, value: nil, selection: nil, secure: true) }
        let raw = attribute(element, kAXSelectedTextRangeAttribute)
            ?? (attribute(element, kAXSelectedTextRangesAttribute) as? [AXValue]).flatMap { $0.count == 1 ? $0.first : nil }
        var range: CFRange?
        if let raw, CFGetTypeID(raw) == AXValueGetTypeID() {
            var result = CFRange()
            if AXValueGetValue(raw as! AXValue, .cfRange, &result) { range = result }
        }
        return TextTarget(app: app, element: element, value: textValue(element), selection: range, secure: false)
    }

    static func attribute(_ element: AXUIElement, _ name: String) -> CFTypeRef? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value
    }

    static func textValue(_ element: AXUIElement) -> String? {
        guard attribute(element, kAXSubroleAttribute) as? String != kAXSecureTextFieldSubrole else { return nil }
        let fallback = attribute(element, kAXValueAttribute) as? String
        let role = attribute(element, kAXRoleAttribute) as? String
        guard [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? ""),
              let count = attribute(element, kAXNumberOfCharactersAttribute) as? Int, count >= 0, count <= 100_000 else {
            return fallback
        }
        if count == 0 { return fallback ?? "" }
        var range = CFRange(location: 0, length: count)
        guard let parameter = AXValueCreate(.cfRange, &range) else { return fallback }
        for name in [kAXStringForRangeParameterizedAttribute, kAXAttributedStringForRangeParameterizedAttribute] {
            var result: CFTypeRef?
            if AXUIElementCopyParameterizedAttributeValue(element, name as CFString, parameter, &result) == .success {
                let string = (result as? String) ?? (result as? NSAttributedString)?.string
                if let string, string.utf16.count == count { return string }
            }
        }
        return fallback
    }

    var stillFocused: Bool {
        guard let current = Self.capture(), current.app.processIdentifier == app.processIdentifier, !current.secure,
              let element, let currentElement = current.element else { return false }
        return CFEqual(element, currentElement)
    }

    func insert(_ text: String, allowPaste: Bool, pressEnter: Bool = false) async -> (status: String, anchor: SpanAnchor?) {
        guard !Task.isCancelled else { return ("Cancelled", nil) }
        guard !text.isEmpty else { return ("Saved — no text to insert", nil) }
        guard !secure, stillFocused, let element else { return ("Saved — target changed", nil) }
        // A caret move or typing while decoding invalidates the insertion target.
        let current = Self.capture()
        guard current?.value == value, current?.selection?.location == selection?.location,
              current?.selection?.length == selection?.length else { return ("Saved — field changed", nil) }
        let expected = expectedValue(text)
        let role = Self.attribute(element, kAXRoleAttribute) as? String
        let textInput = [kAXTextFieldRole, kAXTextAreaRole, kAXComboBoxRole].contains(role ?? "")
        // Normal text input reaches web editors' input handlers. An AX setter can report
        // success even when a Chromium editor does not change its document.
        if textInput, CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState) {
            let units = Array(text.utf16)
            var offset = 0
            while offset < units.count {
                guard stillFocused else { return ("Typing stopped — focus changed", nil) }
                var end = min(offset + 20, units.count)
                // Keep a surrogate pair in the same event, including emoji.
                if end < units.count, (0xD800...0xDBFF).contains(units[end - 1]) { end -= 1 }
                guard let down = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: true),
                      let up = CGEvent(keyboardEventSource: source, virtualKey: 0, keyDown: false) else {
                    return (offset == 0 ? "Saved — text input unavailable" : "Typing stopped — text input unavailable", nil)
                }
                Array(units[offset..<end]).withUnsafeBufferPointer { buffer in
                    down.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                    up.keyboardSetUnicodeString(stringLength: buffer.count, unicodeString: buffer.baseAddress)
                }
                down.flags = []; up.flags = []
                // Deliver only to the captured app, even if another app activates during delivery.
                down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
                offset = end
            }
            // Once any text event is sent, never retry via AX or paste: delivery may be partial.
            let anchor = await verifiedAnchor(text, expected: expected)
            return await completeDelivery(text: text, status: anchor != nil ? "Inserted via typing" : "Text input sent — unverified", anchor: anchor, expected: expected, pressEnter: pressEnter, allowUnverified: true)
        }
        var settable = DarwinBoolean(false)
        let canWrite = AXUIElementIsAttributeSettable(element, kAXSelectedTextAttribute as CFString, &settable) == .success && settable.boolValue
        if canWrite {
            let status = AXUIElementSetAttributeValue(element, kAXSelectedTextAttribute as CFString, text as CFString)
            if status == .success {
                let anchor = await verifiedAnchor(text, expected: expected)
                return await completeDelivery(text: text, status: anchor != nil ? "Inserted" : "Sent to field — unverified", anchor: anchor, expected: expected, pressEnter: pressEnter)
            }
        }
        guard allowPaste, stillFocused else { return ("Saved — use Copy", nil) }
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: 9, keyDown: false) else {
            return ("Saved — paste unavailable", nil)
        }
        // Optional clipboard fallback. Restore only if no one else changed the clipboard.
        let clipboard = NSPasteboard.general
        let previous = (clipboard.pasteboardItems ?? []).map { item in
            item.types.compactMap { type in item.data(forType: type).map { (type, $0) } }
        }
        guard stillFocused else { return ("Saved — target changed", nil) }
        clipboard.clearContents()
        clipboard.setString(text, forType: .string)
        let changeCount = clipboard.changeCount
        let pasteSent = stillFocused
        if pasteSent {
            down.flags = .maskCommand; up.flags = .maskCommand
            down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        }
        try? await Task.sleep(for: .milliseconds(350))
        if clipboard.changeCount == changeCount {
            clipboard.clearContents()
            let items = previous.map { values in
                let item = NSPasteboardItem()
                for (type, data) in values { item.setData(data, forType: type) }
                return item
            }
            clipboard.writeObjects(items)
        }
        guard pasteSent else { return ("Saved — target changed", nil) }
        let anchor = await verifiedAnchor(text, expected: expected)
        return await completeDelivery(text: text, status: anchor != nil ? "Inserted via paste" : "Paste sent — unverified", anchor: anchor, expected: expected, pressEnter: pressEnter, allowUnverified: true)
    }

    /// Called only after the entire text operation has been dispatched, never a partial edit.
    private func completeDelivery(text: String, status: String, anchor: SpanAnchor?, expected: (value: String, prefix: String, suffix: String)?, pressEnter: Bool, allowUnverified: Bool = false) async -> (status: String, anchor: SpanAnchor?) {
        guard pressEnter else { return (status, anchor) }
        guard anchor != nil || allowUnverified else { return (status + " · Enter skipped — text not confirmed", anchor) }
        // Allow the editor to process its queued text input before the Return event.
        try? await Task.sleep(for: .milliseconds(150))
        guard !Task.isCancelled, stillFocused else { return (status + " · Enter skipped — target changed", anchor) }
        if let element, let currentValue = Self.textValue(element) {
            let confirmed = expected.map { currentValue == $0.value }
                ?? value.map { TextProcessing.isExactInsertion(before: $0, after: currentValue, inserted: text) } ?? false
            if !confirmed {
                return (status + " · Enter skipped — field changed", anchor)
            }
        }
        guard CGPreflightPostEventAccess(), let source = CGEventSource(stateID: .privateState),
              let down = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Return), keyDown: true),
              let up = CGEvent(keyboardEventSource: source, virtualKey: UInt16(kVK_Return), keyDown: false), stillFocused else {
            return (status + " · Enter unavailable", anchor)
        }
        down.flags = []; up.flags = []
        down.postToPid(app.processIdentifier); up.postToPid(app.processIdentifier)
        // Enter may submit/clear the field; do not watch it as a recognition correction.
        return (status + " · Enter pressed", nil)
    }

    private func verifiedAnchor(_ text: String, expected: (value: String, prefix: String, suffix: String)?) async -> SpanAnchor? {
        guard let element, value != nil else { return nil }
        for _ in 0..<8 {
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled, stillFocused else { return nil }
            guard let currentValue = Self.textValue(element) else { continue }
            if let expected, currentValue == expected.value {
                return SpanAnchor(element: element, target: self, prefix: expected.prefix, suffix: expected.suffix, inserted: text)
            }
            if expected == nil, selection == nil, let value,
               let context = TextProcessing.insertionContext(before: value, after: currentValue, inserted: text) {
                return SpanAnchor(element: element, target: self, prefix: context.prefix, suffix: context.suffix, inserted: text)
            }
        }
        return nil
    }

    private func expectedValue(_ text: String) -> (value: String, prefix: String, suffix: String)? {
        guard let value, let selection, selection.location >= 0, selection.length >= 0,
              selection.location <= value.utf16.count, selection.length <= value.utf16.count - selection.location else { return nil }
        // Claude's empty rich editor exposes a placeholder paragraph that typing replaces.
        if bundleID == "com.anthropic.claudefordesktop", value == "\n",
           selection.location == 0, selection.length == 0, let element,
           Self.attribute(element, kAXRoleAttribute) as? String == kAXTextAreaRole,
           Self.attribute(element, kAXNumberOfCharactersAttribute) as? Int == 1 {
            return (text, "", "")
        }
        let string = value as NSString
        let prefix = string.substring(to: selection.location)
        let suffix = string.substring(from: selection.location + selection.length)
        return (prefix + text + suffix, prefix, suffix)
    }
}

@MainActor
struct SpanAnchor {
    let element: AXUIElement
    let target: TextTarget
    let prefix: String
    let suffix: String
    let inserted: String
}

@Observable @MainActor
private final class RecordingDisplay {
    var title = "Listening"
    var detail = ""
    var level: Float = 0
    var elapsed = 0.0
    var maximumSeconds = 180.0
    var remaining: Double?
    var levels = Array(repeating: Float(0), count: 24)
    var middleMouse = true
    var shortcut = "⌥ Space"
    var holdToTalk = false
    var preview = ""
    var notchDepth: CGFloat = 0
    var presented = false
}

struct MouseShortcutSymbol: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.34).stroke(.primary.opacity(0.8), lineWidth: 1.5)
            Rectangle().fill(.primary.opacity(0.5)).frame(width: 1, height: size * 0.32).offset(y: -size * 0.29)
            Rectangle().fill(.primary.opacity(0.5)).frame(height: 1).offset(y: -size * 0.12)
            Capsule().fill(Color.flowAccent).frame(width: size * 0.25, height: size * 0.39).offset(y: -size * 0.18)
        }.frame(width: size * 0.72, height: size)
            .accessibilityLabel("Middle mouse button")
    }
}

private struct ListeningOverlay: View {
    let display: RecordingDisplay
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    var body: some View {
        VStack(spacing: 6) {
        HStack(spacing: 12) {
            if display.title == "Listening" {
                HStack(spacing: 3) {
                    ForEach(display.levels.suffix(5).indices, id: \.self) { index in
                        Capsule().fill(Color.flowAccent)
                            .frame(width: 3, height: max(3, CGFloat(display.levels[index]) * 20))
                    }
                }.frame(width: 27, height: 24)
                    .animation(reduceMotion ? nil : .linear(duration: 0.05), value: display.levels)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Microphone level")
                    .accessibilityValue("\(Int(display.level * 100)) percent")
                VStack(alignment: .leading, spacing: 2) {
                    Text("Listening").font(.system(size: 12, weight: .semibold))
                    Text(display.remaining.map { $0 < 2 ? "Stopping…" : elapsed } ?? elapsed)
                        .font(.system(size: 11, design: .monospaced)).monospacedDigit().foregroundStyle(.secondary)
                        .accessibilityLabel("Elapsed \(elapsed), limit \(Duration.seconds(display.maximumSeconds).formatted(.time(pattern: .minuteSecond)))")
                }
                Spacer(minLength: 8)
                HStack(spacing: 7) {
                    if display.middleMouse { MouseShortcutSymbol() }
                    else {
                        Text(display.shortcut).font(.system(size: 11, weight: .semibold))
                            .padding(5).overlay(RoundedRectangle(cornerRadius: 5).stroke(.primary.opacity(0.25)))
                    }
                    Text(display.holdToTalk && !display.middleMouse ? "release to finish" : "to finish").font(.system(size: 12, weight: .medium))
                }.accessibilityElement(children: .combine)
            } else {
                Image(systemName: "waveform").foregroundStyle(Color.flowAccent).font(.system(size: 17))
                VStack(alignment: .leading, spacing: 2) {
                    Text(display.title == "Transcribing locally" ? "Transcribing" : display.title).font(.system(size: 12, weight: .semibold))
                    Text(display.detail).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 8)
                ProgressView().controlSize(.mini)
            }
        }
        if display.title == "Listening", !display.preview.isEmpty {
            Text(String(display.preview.suffix(90)).replacingOccurrences(of: "\n", with: " "))
                .font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
                .accessibilityLabel("Live preview of latest speech").accessibilityValue(display.preview)
        }
        }.padding(.horizontal, 16).padding(.vertical, 12)
            .padding(.top, display.notchDepth)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background {
                if display.notchDepth > 0 {
                    UnevenRoundedRectangle(bottomLeadingRadius: 18, bottomTrailingRadius: 18).fill(.black)
                } else {
                    Capsule().fill(.regularMaterial)
                        .overlay(Capsule().strokeBorder(.primary.opacity(0.08), lineWidth: 1))
                }
            }
            .environment(\.colorScheme, display.notchDepth > 0 ? .dark : colorScheme)
            .scaleEffect(x: display.presented || reduceMotion ? 1 : 0.7,
                         y: display.presented || reduceMotion ? 1 : 0.02,
                         anchor: display.notchDepth > 0 ? .top : .bottom)
            .opacity(display.presented ? 1 : 0)
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .spring(response: 0.32, dampingFraction: 1), value: display.presented)
    }
    private var elapsed: String { Duration.seconds(display.elapsed).formatted(.time(pattern: .minuteSecond)) }
}

@MainActor
final class RecordingPanel {
    private var panel: NSPanel?
    private let display = RecordingDisplay()
    private var dismissal: Task<Void, Never>?
    func show(title: String, detail: String, maximumSeconds: Double = 180, middleMouse: Bool = true, shortcut: String = "⌥ Space", holdToTalk: Bool = false, screen targetScreen: NSScreen? = nil) {
        dismissal?.cancel(); dismissal = nil
        if panel == nil {
            let panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: 280, height: 56), styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            panel.level = .floating; panel.isOpaque = false; panel.backgroundColor = .clear
            panel.hasShadow = true; panel.ignoresMouseEvents = true
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.contentView = NSHostingView(rootView: ListeningOverlay(display: display))
            self.panel = panel
        }
        display.title = title; display.detail = detail
        display.preview = ""; resizeForPreview()
        if title == "Listening" {
            display.middleMouse = middleMouse
            display.shortcut = shortcut; display.holdToTalk = holdToTalk
            display.maximumSeconds = maximumSeconds
            display.level = 0; display.elapsed = 0; display.remaining = nil
            display.levels = Array(repeating: 0, count: 24)
        }
        let screen = targetScreen ?? NSScreen.main ?? NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.screens.first
        if (panel?.isVisible != true || title == "Listening"), let panel, let screen {
            // Prefer the captured target window's display; the mouse can be on another display.
            let screenID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber
            let builtIn = screenID.map { CGDisplayIsBuiltin($0.uint32Value) != 0 } ?? false
            let left = screen.auxiliaryTopLeftArea, right = screen.auxiliaryTopRightArea
            let hasNotch = builtIn && screen.safeAreaInsets.top > 0 && left != nil && right != nil
            display.notchDepth = hasNotch ? screen.safeAreaInsets.top : 0
            let width = hasNotch ? max(280, right!.minX - left!.maxX + 20) : 280
            let height = 56 + display.notchDepth
            let centerX = hasNotch ? (left!.maxX + right!.minX) / 2 : screen.visibleFrame.midX
            let bottom = hasNotch ? screen.frame.maxY - height : screen.visibleFrame.minY + 24
            panel.setFrame(NSRect(x: centerX - width / 2, y: bottom, width: width, height: height), display: true)
            panel.level = hasNotch ? .statusBar : .floating
            panel.orderFrontRegardless()
            // Let the persistent hosting view commit the collapsed shape before expansion.
            Task { @MainActor [weak self] in
                await Task.yield()
                guard let self, self.panel?.isVisible == true, self.dismissal == nil else { return }
                self.display.presented = true
            }
        } else {
            display.presented = true
        }
    }
    func update(level: Float, elapsed: Double, remaining: Double?) {
        display.level = level; display.elapsed = elapsed; display.remaining = remaining
        display.levels.removeFirst(); display.levels.append(level)
    }
    func preview(_ text: String) {
        guard display.title == "Listening" else { return }
        display.preview = text; resizeForPreview()
    }
    private func resizeForPreview() {
        guard let panel else { return }
        var frame = panel.frame
        let height = 56 + display.notchDepth + (display.preview.isEmpty ? 0 : 24)
        if display.notchDepth > 0 { frame.origin.y += frame.height - height }
        frame.size.height = height
        panel.setFrame(frame, display: true)
    }
    func hide() {
        display.presented = false
        dismissal?.cancel()
        dismissal = Task { @MainActor [weak self] in
            do { try await Task.sleep(for: .milliseconds(350)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.dismissal = nil
        }
    }
}
