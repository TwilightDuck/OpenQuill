import AppKit
import CoreAudio
import OSLog

/// Mute output, not microphone gain or playback volume, for one recording.
@MainActor
final class RecordingAudioMute: NSObject {
    var onFailure: ((String) -> Void)?
    private var active = false
    private var seenDevices: Set<AudioObjectID> = []
    private var changedDevices: Set<AudioObjectID> = []
    private var listener: AudioObjectPropertyListenerBlock?
    private static let routes = [kAudioHardwarePropertyDefaultOutputDevice, kAudioHardwarePropertyDefaultSystemOutputDevice]
    private static let logger = Logger(subsystem: "be.nick.wisperflow", category: "AudioMute")

    override init() {
        super.init()
        NotificationCenter.default.addObserver(self, selector: #selector(applicationWillTerminate(_:)), name: NSApplication.willTerminateNotification, object: nil)
    }

    @objc private func applicationWillTerminate(_ notification: Notification) { restore() }

    func begin() throws {
        guard !active else { return }
        active = true
        let listener: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Leave the CoreAudio callback before removing listeners on failure.
            Task { @MainActor [weak self] in
                guard let self, self.active else { return }
                do { try self.muteCurrentOutputs() }
                catch { self.restore(); self.onFailure?(error.localizedDescription) }
            }
        }
        self.listener = listener
        do {
            for selector in Self.routes {
                var address = Self.routeAddress(selector)
                guard AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener) == noErr else {
                    throw Self.failure("Could not watch audio output changes. Turn off Mute audio while recording to continue.")
                }
            }
            try muteCurrentOutputs()
        } catch { restore(); throw error }
    }

    func restore() {
        active = false
        if let listener {
            for selector in Self.routes {
                var address = Self.routeAddress(selector)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, .main, listener)
            }
            self.listener = nil
        }
        for device in changedDevices {
            var address = Self.muteAddress
            // Respect an explicit user unmute; leave playback volume untouched.
            guard Self.read(device, &address) == 1 else { continue }
            var unmuted: UInt32 = 0
            if AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &unmuted) != noErr {
                Self.logger.error("Could not restore audio mute on output device \(device).")
            }
        }
        changedDevices.removeAll()
        seenDevices.removeAll()
    }

    private func muteCurrentOutputs() throws {
        for selector in Self.routes {
            var route = Self.routeAddress(selector)
            guard let device = Self.read(AudioObjectID(kAudioObjectSystemObject), &route), device != kAudioObjectUnknown else { continue }
            guard seenDevices.insert(device).inserted else { continue }
            var address = Self.muteAddress
            guard let muted = Self.read(device, &address) else {
                throw Self.failure("This audio output does not support macOS mute. Use its own mute control, or turn off Mute audio while recording.")
            }
            // An already-muted output belongs to the user, not this recording.
            guard muted == 0 else { continue }
            var settable: DarwinBoolean = false
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr, settable.boolValue else {
                throw Self.failure("This audio output does not support macOS mute. Use its own mute control, or turn off Mute audio while recording.")
            }
            var value: UInt32 = 1
            guard AudioObjectSetPropertyData(device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr else {
                throw Self.failure("Could not mute audio. Turn off Mute audio while recording to continue.")
            }
            changedDevices.insert(device)
            guard Self.read(device, &address) == 1 else {
                throw Self.failure("The audio output did not accept mute. Turn off Mute audio while recording to continue.")
            }
        }
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: kAudioDevicePropertyMute, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }
    private static func routeAddress(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
    }
    private static func read(_ object: AudioObjectID, _ address: inout AudioObjectPropertyAddress) -> UInt32? {
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr, size == MemoryLayout<UInt32>.size else { return nil }
        return value
    }
    private static func failure(_ message: String) -> NSError {
        NSError(domain: "OpenQuill.AudioMute", code: 1, userInfo: [NSLocalizedDescriptionKey: message])
    }
}
