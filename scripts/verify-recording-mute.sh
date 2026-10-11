#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
temporary=$(mktemp -d)
trap 'rm -rf "$temporary"' EXIT
cat > "$temporary/check.swift" <<'SWIFT'
import AppKit
import CoreAudio

@main struct CheckRecordingMute {
    static func read(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector, output: Bool = true) -> UInt32? {
        var address = AudioObjectPropertyAddress(mSelector: selector, mScope: output ? kAudioDevicePropertyScopeOutput : kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr ? value : nil
    }
    static func require(_ condition: Bool, _ message: String) throws {
        if !condition { throw NSError(domain: "AudioMuteCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: message]) }
    }
    static func setMute(_ device: AudioObjectID, _ value: UInt32) throws {
        var address = AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
        var value = value
        try require(AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr, "Could not set test mute state")
    }
    @MainActor static func main() throws {
        let devices = Set([kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice].compactMap {
            read(AudioObjectID(kAudioObjectSystemObject), $0, output: false)
        }.filter { $0 != kAudioObjectUnknown })
        if CommandLine.arguments.contains("--read-only") {
            for device in devices.sorted() {
                print("Output \(device): mute=\(read(device, kAudioDevicePropertyMute).map(String.init) ?? "unsupported") volumeBits=\(read(device, kAudioDevicePropertyVolumeScalar).map(String.init) ?? "unsupported")")
            }
            return
        }
        try require(!devices.isEmpty, "No audio output to exercise")
        let original = try devices.map { device -> (AudioObjectID, UInt32, UInt32?) in
            guard let value = read(device, kAudioDevicePropertyMute) else {
                throw NSError(domain: "AudioMuteCheck", code: 1, userInfo: [NSLocalizedDescriptionKey: "Current output does not expose macOS mute; use a supported output for this check."])
            }
            return (device, value, read(device, kAudioDevicePropertyVolumeScalar))
        }
        let mute = RecordingAudioMute()
        // Always restore the host's starting state, even if a check throws.
        defer { mute.restore(); for (device, value, _) in original { try? setMute(device, value) } }
        try mute.begin(); try mute.begin()
        try require(devices.allSatisfy { read($0, kAudioDevicePropertyMute) == 1 }, "Output was not muted")
        mute.restore(); mute.restore()
        try require(original.allSatisfy { read($0.0, kAudioDevicePropertyMute) == $0.1 }, "Mute state was not restored")

        for device in devices { try setMute(device, 1) }
        try mute.begin(); mute.restore()
        try require(devices.allSatisfy { read($0, kAudioDevicePropertyMute) == 1 }, "Already-muted output was unmuted")

        for device in devices { try setMute(device, 0) }
        try mute.begin()
        for device in devices { try setMute(device, 0) }
        mute.restore()
        try require(devices.allSatisfy { read($0, kAudioDevicePropertyMute) == 0 }, "Explicit user unmute was overwritten")

        try mute.begin()
        NotificationCenter.default.post(name: NSApplication.willTerminateNotification, object: nil)
        try require(devices.allSatisfy { read($0, kAudioDevicePropertyMute) == 0 }, "Normal termination did not restore audio")
        try require(original.allSatisfy { read($0.0, kAudioDevicePropertyVolumeScalar) == $0.2 }, "Playback volume changed")
        print("PASS: native output mute, restore, repeated start/stop, already-muted output, explicit unmute, termination and unchanged volume.")
    }
}
SWIFT
swiftc -swift-version 6 -parse-as-library Sources/OpenQuill/RecordingAudioMute.swift "$temporary/check.swift" -o "$temporary/check"
"$temporary/check" "$@"
