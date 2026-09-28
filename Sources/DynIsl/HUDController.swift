import AppKit

struct HUDInfo: Equatable {
    enum Kind { case volume, brightness }
    var kind: Kind
    var level: Double
    var muted: Bool
}

@MainActor
final class HUDController: ObservableObject {
    @Published private(set) var current: HUDInfo?
    @Published private(set) var needsPermission = false

    var enabled = true { didSet { if enabled != oldValue { apply() } } }

    let tap = MediaKeyTap()
    private var hideWork: DispatchWorkItem?
    private var held = false
    private var trustTimer: Timer?
    private var lastOwnChange = Date.distantPast

    private static let feedbackSound: NSSound? = {
        let path = "/System/Library/LoginPlugins/BezelServices.loginPlugin/Contents/Resources/volume.aiff"
        return FileManager.default.fileExists(atPath: path) ? NSSound(contentsOfFile: path, byReference: true) : NSSound(named: "Pop")
    }()

    func start() {
        tap.handler = { [weak self] key, isRepeat, fine in
            guard let self else { return false }
            let handled = self.handle(key, fine: fine)
            self.tap.markHandled(key, handled)
            return handled
        }
        tap.onKeyUp = { [weak self] key in
            if key == .volumeUp || key == .volumeDown { self?.playFeedbackIfEnabled() }
        }
        VolumeControl.observe { [weak self] in
            MainActor.assumeIsolated { self?.volumeChangedElsewhere() }
        }
        apply()
    }

    func requestPermission() {
        MediaKeyTap.requestTrust()
        waitForTrust()
    }

    func openAccessibilitySettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility") {
            NSWorkspace.shared.open(url)
        }
    }

    private func apply() {
        if enabled {
            if MediaKeyTap.isTrusted {
                tap.start()
                needsPermission = false
            } else {
                needsPermission = true
                waitForTrust()
            }
        } else {
            tap.stop()
            trustTimer?.invalidate()
            trustTimer = nil
        }
    }

    private func waitForTrust() {
        guard trustTimer == nil else { return }
        trustTimer = Timer.repeating(every: 2) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                if MediaKeyTap.isTrusted {
                    t.invalidate()
                    self.trustTimer = nil
                    self.needsPermission = false
                    if self.enabled { self.tap.start() }
                }
            }
        }
    }

    private func handle(_ key: MediaKeyTap.Key, fine: Bool) -> Bool {
        let step: Float = fine ? 1.0 / 64 : 1.0 / 16
        switch key {
        case .volumeUp, .volumeDown:
            guard VolumeControl.isSettable else { return false }
            var v = VolumeControl.volume
            if VolumeControl.isMuted { VolumeControl.isMuted = false }
            v += key == .volumeUp ? step : -step
            v = (v / step).rounded() * step
            v = min(max(v, 0), 1)
            lastOwnChange = Date()
            VolumeControl.volume = v
            show(HUDInfo(kind: .volume, level: Double(v), muted: v == 0))
        case .mute:
            guard VolumeControl.isSettable else { return false }
            lastOwnChange = Date()
            let muted = !VolumeControl.isMuted
            VolumeControl.isMuted = muted
            show(HUDInfo(kind: .volume, level: Double(VolumeControl.volume), muted: muted))
        case .brightnessUp, .brightnessDown:
            guard BrightnessControl.isAvailable else { return false }
            var b = BrightnessControl.brightness + (key == .brightnessUp ? step : -step)
            b = min(max((b / step).rounded() * step, 0), 1)
            BrightnessControl.brightness = b
            show(HUDInfo(kind: .brightness, level: Double(b), muted: false))
        }
        return true
    }

    private func volumeChangedElsewhere() {
        guard enabled, Date().timeIntervalSince(lastOwnChange) > 0.4 else { return }
        show(HUDInfo(kind: .volume, level: Double(VolumeControl.volume), muted: VolumeControl.isMuted))
    }

    private func playFeedbackIfEnabled() {
        let on = UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["com.apple.sound.beep.feedback"] as? Int == 1
        guard on, !VolumeControl.isMuted else { return }
        Self.feedbackSound?.stop()
        Self.feedbackSound?.play()
    }

    private func show(_ info: HUDInfo) {
        current = info
        scheduleHide()
    }

    private func scheduleHide() {
        hideWork?.cancel()
        guard !held else { return }
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.current = nil }
        }
        hideWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6, execute: work)
    }

    func hold() {
        guard !held else { return }
        held = true
        hideWork?.cancel()
    }

    func release() {
        guard held else { return }
        held = false
        scheduleHide()
    }

    func setLevel(_ level: Double) {
        guard var info = current else { return }
        let l = min(max(level, 0), 1)
        switch info.kind {
        case .volume:
            lastOwnChange = Date()
            if VolumeControl.isMuted, l > 0 { VolumeControl.isMuted = false }
            VolumeControl.volume = Float(l)
            info.muted = l == 0
        case .brightness:
            BrightnessControl.brightness = Float(l)
        }
        info.level = l
        current = info
    }
}
