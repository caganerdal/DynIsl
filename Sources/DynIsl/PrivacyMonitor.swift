import AppKit
import CoreAudio
import CoreMediaIO

@MainActor
final class PrivacyMonitor: ObservableObject {
    @Published private(set) var cameraOn = false
    @Published private(set) var micOn = false
    @Published private(set) var micApps: [String] = []

    var isActive: Bool { cameraOn || micOn }

    var onActivity: ((IslandActivity) -> Void)?
    private var timer: Timer?

    private static let ignoredPrefixes = ["com.apple.corespeech", "com.apple.siri", "com.apple.assistant"]

    private var watchedProcesses: Set<AudioObjectID> = []
    private var watchedCameras: Set<CMIOObjectID> = []
    private var refreshScheduled = false

    func start() {
        refresh(notify: false)
        watchAudio()
        watchCameras()
        timer = Timer.repeating(every: 60) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(notify: true) }
        }
    }

    private func scheduleRefresh() {
        guard !refreshScheduled else { return }
        refreshScheduled = true
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { [weak self] in
            MainActor.assumeIsolated {
                self?.refreshScheduled = false
                self?.refresh(notify: true)
            }
        }
    }

    private func watchAudio() {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyProcessObjectList,
                                              mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.watchAudioProcesses()
                self?.scheduleRefresh()
            }
        }
        watchAudioProcesses()
    }

    private func watchAudioProcesses() {
        for id in Self.audioProcesses() where !watchedProcesses.contains(id) {
            watchedProcesses.insert(id)
            var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyIsRunningInput,
                                                  mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
            AudioObjectAddPropertyListenerBlock(id, &addr, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
    }

    private func watchCameras() {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &addr, .main) { [weak self] _, _ in
            MainActor.assumeIsolated {
                self?.watchCameraDevices()
                self?.scheduleRefresh()
            }
        }
        watchCameraDevices()
    }

    private func watchCameraDevices() {
        for d in Self.cameraDevices() where !watchedCameras.contains(d) {
            watchedCameras.insert(d)
            var addr = CMIOObjectPropertyAddress(
                mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
                mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
                mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
            )
            CMIOObjectAddPropertyListenerBlock(d, &addr, .main) { [weak self] _, _ in
                MainActor.assumeIsolated { self?.scheduleRefresh() }
            }
        }
    }

    private func refresh(notify: Bool) {
        let camera = Self.isCameraRunning()
        let apps = Self.appsUsingMicrophone()
        let mic = !apps.isEmpty

        if notify {
            if camera && !cameraOn {
                onActivity?(.init(icon: "video.fill", tint: .green, title: "Kamera", trailing: "Kullanımda"))
            } else if mic && !micOn {
                onActivity?(.init(icon: "mic.fill", tint: .orange, title: apps.first ?? "Mikrofon", trailing: "Mikrofon açık"))
            }
        }
        if cameraOn != camera { cameraOn = camera }
        if micOn != mic { micOn = mic }
        if micApps != apps { micApps = apps }
    }

    private static func audioProcesses() -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var addr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyProcessObjectList,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &addr, 0, nil, &size, &ids) == noErr else { return [] }
        return ids
    }

    private static func appsUsingMicrophone() -> [String] {
        let ids = audioProcesses()
        let ownID = Bundle.main.bundleIdentifier
        var names: [String] = []
        for id in ids where uint32(id, kAudioProcessPropertyIsRunningInput) != 0 {
            guard let bid = bundleID(of: id), bid != ownID,
                  !ignoredPrefixes.contains(where: { bid.lowercased().hasPrefix($0) }) else { continue }
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: bid).first?.localizedName
                ?? bid.components(separatedBy: ".").last ?? bid
            if !names.contains(name) { names.append(name) }
        }
        return names
    }

    private static func uint32(_ obj: AudioObjectID, _ selector: AudioObjectPropertySelector) -> UInt32 {
        var addr = AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &value) == noErr ? value : 0
    }

    private static func bundleID(of obj: AudioObjectID) -> String? {
        var addr = AudioObjectPropertyAddress(mSelector: kAudioProcessPropertyBundleID, mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(obj, &addr, 0, nil, &size, &ref) == noErr, let ref else { return nil }
        let s = ref.takeRetainedValue() as String
        return s.isEmpty ? nil : s
    }

    private static func cameraDevices() -> [CMIOObjectID] {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var devices = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &addr, 0, nil, size, &used, &devices) == noErr else { return [] }
        return devices
    }

    private static func isCameraRunning() -> Bool {
        var addr = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
        for d in cameraDevices() {
            var running: UInt32 = 0
            var u: UInt32 = 0
            if CMIOObjectGetPropertyData(d, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &u, &running) == noErr, running != 0 {
                return true
            }
        }
        return false
    }
}
