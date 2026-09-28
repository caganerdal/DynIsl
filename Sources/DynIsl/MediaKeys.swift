import AppKit
import AudioToolbox
import CoreAudio

enum VolumeControl {
    static var device: AudioObjectID {
        var dev = AudioObjectID(0)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &dev)
        return dev
    }

    private static var volumeAddress = AudioObjectPropertyAddress(
        mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    private static var muteAddress = AudioObjectPropertyAddress(
        mSelector: kAudioDevicePropertyMute,
        mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)

    static var isSettable: Bool {
        var settable: DarwinBoolean = false
        let dev = device
        guard AudioObjectHasProperty(dev, &volumeAddress) else { return false }
        AudioObjectIsPropertySettable(dev, &volumeAddress, &settable)
        return settable.boolValue
    }

    static var volume: Float {
        get {
            var v: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            AudioObjectGetPropertyData(device, &volumeAddress, 0, nil, &size, &v)
            return v
        }
        set {
            var v = Float32(min(max(newValue, 0), 1))
            AudioObjectSetPropertyData(device, &volumeAddress, 0, nil, UInt32(MemoryLayout<Float32>.size), &v)
        }
    }

    static var isMuted: Bool {
        get {
            var m: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            let dev = device
            guard AudioObjectHasProperty(dev, &muteAddress) else { return false }
            AudioObjectGetPropertyData(dev, &muteAddress, 0, nil, &size, &m)
            return m != 0
        }
        set {
            var m: UInt32 = newValue ? 1 : 0
            let dev = device
            guard AudioObjectHasProperty(dev, &muteAddress) else { return }
            AudioObjectSetPropertyData(dev, &muteAddress, 0, nil, UInt32(MemoryLayout<UInt32>.size), &m)
        }
    }

    static var deviceName: String? {
        var ref: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        var a = AudioObjectPropertyAddress(mSelector: kAudioObjectPropertyName,
                                           mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        guard AudioObjectGetPropertyData(device, &a, 0, nil, &size, &ref) == noErr else { return nil }
        return ref?.takeRetainedValue() as String?
    }

    static func observe(_ onChange: @escaping () -> Void) {
        let queue = DispatchQueue.main
        var defAddr = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                                                 mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var current = device
        let listener: AudioObjectPropertyListenerBlock = { _, _ in onChange() }
        func attach(_ dev: AudioObjectID) {
            AudioObjectAddPropertyListenerBlock(dev, &volumeAddress, queue, listener)
            AudioObjectAddPropertyListenerBlock(dev, &muteAddress, queue, listener)
        }
        attach(current)
        AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &defAddr, queue) { _, _ in
            let new = device
            guard new != current else { return }
            AudioObjectRemovePropertyListenerBlock(current, &volumeAddress, queue, listener)
            AudioObjectRemovePropertyListenerBlock(current, &muteAddress, queue, listener)
            current = new
            attach(new)
        }
    }
}

enum BrightnessControl {
    private typealias GetFn = @convention(c) (UInt32, UnsafeMutablePointer<Float>) -> Int32
    private typealias SetFn = @convention(c) (UInt32, Float) -> Int32

    private static let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
    private static let getFn: GetFn? = dlsym(handle, "DisplayServicesGetBrightness").map { unsafeBitCast($0, to: GetFn.self) }
    private static let setFn: SetFn? = dlsym(handle, "DisplayServicesSetBrightness").map { unsafeBitCast($0, to: SetFn.self) }

    static var builtInDisplay: CGDirectDisplayID? {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var n: UInt32 = 0
        CGGetActiveDisplayList(16, &ids, &n)
        return ids.prefix(Int(n)).first { CGDisplayIsBuiltin($0) != 0 }
    }

    static var isAvailable: Bool { getFn != nil && setFn != nil && builtInDisplay != nil }

    static var brightness: Float {
        get {
            guard let d = builtInDisplay, let getFn else { return 0 }
            var b: Float = 0
            _ = getFn(d, &b)
            return b
        }
        set {
            guard let d = builtInDisplay, let setFn else { return }
            _ = setFn(d, min(max(newValue, 0), 1))
        }
    }
}

@MainActor
final class MediaKeyTap {
    enum Key { case volumeUp, volumeDown, mute, brightnessUp, brightnessDown }

    var handler: ((Key, _ isRepeat: Bool, _ fine: Bool) -> Bool)?
    var onKeyUp: ((Key) -> Void)?

    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    var isRunning: Bool { tap != nil }

    static var isTrusted: Bool { AXIsProcessTrusted() }

    static func requestTrust() {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        _ = AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    @discardableResult
    func start() -> Bool {
        guard tap == nil, Self.isTrusted else { return tap != nil }
        let mask = CGEventMask(1 << 14)
        let me = Unmanaged.passUnretained(self).toOpaque()
        guard let t = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                        eventsOfInterest: mask, callback: mediaKeyCallback, userInfo: me) else { return false }
        tap = t
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        return true
    }

    func stop() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let s = source { CFRunLoopRemoveSource(CFRunLoopGetMain(), s, .commonModes) }
        tap = nil
        source = nil
    }

    fileprivate func reenable() {
        if let t = tap { CGEvent.tapEnable(tap: t, enable: true) }
    }

    fileprivate func handle(_ event: CGEvent) -> Bool {
        guard let ns = NSEvent(cgEvent: event), ns.type == .systemDefined, ns.subtype.rawValue == 8 else { return false }
        let data = ns.data1
        let code = (data & 0xFFFF_0000) >> 16
        let flags = data & 0x0000_FFFF
        let isDown = ((flags & 0xFF00) >> 8) == 0x0A
        let isRepeat = (flags & 0x1) == 1

        let key: Key
        switch code {
        case 0: key = .volumeUp
        case 1: key = .volumeDown
        case 7: key = .mute
        case 2: key = .brightnessUp
        case 3: key = .brightnessDown
        default: return false
        }
        let mods = ns.modifierFlags.intersection([.shift, .option, .command, .control])
        if mods == .option { return false }
        let fine = mods.contains(.shift) && mods.contains(.option)

        if isDown {
            return handler?(key, isRepeat, fine) ?? false
        } else {
            guard handler != nil, keyWasHandled(key) else { return false }
            onKeyUp?(key)
            return true
        }
    }

    private var handledKeys: Set<Int> = []
    func markHandled(_ key: Key, _ handled: Bool) {
        let id = Self.id(key)
        if handled { handledKeys.insert(id) } else { handledKeys.remove(id) }
    }
    private func keyWasHandled(_ key: Key) -> Bool { handledKeys.remove(Self.id(key)) != nil }
    private static func id(_ k: Key) -> Int {
        switch k { case .volumeUp: 0; case .volumeDown: 1; case .mute: 7; case .brightnessUp: 2; case .brightnessDown: 3 }
    }
}

private func mediaKeyCallback(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent,
                              userInfo: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    guard let userInfo else { return Unmanaged.passUnretained(event) }
    let tap = Unmanaged<MediaKeyTap>.fromOpaque(userInfo).takeUnretainedValue()
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        MainActor.assumeIsolated { tap.reenable() }
        return Unmanaged.passUnretained(event)
    }
    let swallow = MainActor.assumeIsolated { tap.handle(event) }
    return swallow ? nil : Unmanaged.passUnretained(event)
}
