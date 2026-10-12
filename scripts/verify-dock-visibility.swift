import AppKit
import Foundation

// Run after changing Settings → General → Show in Dock, and again after relaunch.
guard CommandLine.arguments.count == 2, ["shown", "hidden"].contains(CommandLine.arguments[1]) else {
    print("Usage: swift scripts/verify-dock-visibility.swift shown|hidden")
    exit(1)
}
let visible = CommandLine.arguments[1] == "shown"
let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
let bundle = root.appendingPathComponent("dist/Open Quill.app").standardizedFileURL
guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "be.nick.wisperflow")
    .first(where: { $0.bundleURL?.standardizedFileURL == bundle }) else {
    print("FAIL: the built Open Quill app is not running")
    exit(1)
}
let data = UserDefaults(suiteName: "be.nick.wisperflow")?.data(forKey: "preferences")
let preferences = data.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
guard (preferences?["showInDock"] as? Bool ?? true) == visible,
      app.activationPolicy == (visible ? .regular : .accessory) else {
    print("FAIL: saved Dock visibility and the running app’s activation policy do not match \(CommandLine.arguments[1])")
    exit(1)
}
print("PASS: Dock visibility is \(CommandLine.arguments[1]); preference and native app policy agree")
