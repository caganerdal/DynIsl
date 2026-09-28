import AppKit
import CoreAudio

@MainActor
final class CallController: ObservableObject {
    @Published private(set) var startedAt: Date?
    @Published private(set) var micMuted = false
    @Published private(set) var appName: String?
    @Published private(set) var usesCamera = false

    var isActive: Bool { startedAt != nil }

    private var savedVolume: Float32?
    private var mutedDevice: AudioObjectID?

    func update(camera: Bool, mic: Bool, apps: [String]) {
        let active = camera || mic
        if active, startedAt == nil {
            startedAt = Date()
        } else if !active, startedAt != nil {
            startedAt = nil
            if micMuted { setMuted(false) }
        }
        if usesCamera != camera { usesCamera = camera }
        let name = apps.first
        if appName != name { appName = name }
    }

    func toggleMute() { setMuted(!micMuted) }

    private func setMuted(_ mute: Bool) {
        let dev = mute ? Self.defaultInput : (mutedDevice ?? Self.defaultInput)
        guard dev != 0 else { return }
        if var addr = Self.settableAddress(dev, kAudioDevicePropertyMute) {
            var v: UInt32 = mute ? 1 : 0
            AudioObjectSetPropertyData(dev, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &v)
        } else if var addr = Self.settableAddress(dev, kAudioDevicePropertyVolumeScalar) {
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if mute {
                AudioObjectGetPropertyData(dev, &addr, 0, nil, &size, &v)
                savedVolume = v
                v = 0
            } else {
                v = savedVolume ?? 0.75
                savedVolume = nil
            }
            AudioObjectSetPropertyData(dev, &addr, 0, nil, size, &v)
        } else {
            return
        }
        mutedDevice = mute ? dev : nil
        micMuted = mute
    }

    private static var defaultInput: AudioObjectID {
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultInputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return dev
    }

    private static func settableAddress(_ dev: AudioObjectID, _ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress? {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeInput,
                                              mElement: kAudioObjectPropertyElementMain)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(dev, &addr),
              AudioObjectIsPropertySettable(dev, &addr, &settable) == noErr, settable.boolValue else { return nil }
        return addr
    }
}
