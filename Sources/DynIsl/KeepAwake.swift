import AppKit
import IOKit.pwr_mgt

@MainActor
final class KeepAwake: ObservableObject {
    enum StopReason { case user, expired, battery, appQuit }

    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    @Published private(set) var duration: KeepAwakeDuration = .indefinite
    @Published private(set) var lidActive = false
    @Published private(set) var lidError = false
    @Published var allowDisplaySleep: Bool { didSet { d.set(allowDisplaySleep, forKey: "keepAwakeAllowDisplaySleep"); reapplyIfActive() } }
    @Published var lidClosedMode: Bool { didSet { d.set(lidClosedMode, forKey: "keepAwakeLidMode"); reapplyIfActive() } }
    @Published var batteryThreshold: Int { didSet { d.set(batteryThreshold, forKey: "keepAwakeBatteryThreshold") } }

    let lid = LidSleepControl()
    var onChange: ((IslandActivity) -> Void)?

    private let d = UserDefaults.standard
    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?
    private var appObserver: NSObjectProtocol?

    static let durations: [(title: String, value: KeepAwakeDuration)] = [
        (String(localized: "Süresiz"), .indefinite), (String(localized: "15 dakika"), .minutes(15)),
        (String(localized: "30 dakika"), .minutes(30)), (String(localized: "1 saat"), .minutes(60)),
        (String(localized: "2 saat"), .minutes(120)), (String(localized: "4 saat"), .minutes(240)),
        (String(localized: "8 saat"), .minutes(480)),
    ]

    init() {
        d.register(defaults: ["keepAwakeBatteryThreshold": 20])
        allowDisplaySleep = d.bool(forKey: "keepAwakeAllowDisplaySleep")
        lidClosedMode = d.bool(forKey: "keepAwakeLidMode")
        batteryThreshold = d.integer(forKey: "keepAwakeBatteryThreshold")
        lid.recoverIfNeeded()
    }

    func start(_ duration: KeepAwakeDuration) {
        if case .whileApp(let id) = duration, !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) {
            onChange?(.init(icon: "app.dashed", tint: .orange, title: String(localized: "Uyanık tut"), trailing: String(localized: "Uygulama açık değil")))
            return
        }
        applyAssertions()
        guard !assertions.isEmpty else { return }
        isActive = true
        self.duration = duration
        applyLid()
        timer?.invalidate()
        timer = nil
        endDate = KeepAwakeRules.endDate(for: duration, now: Date(), calendar: .current)
        if let endDate {
            timer = Timer.scheduledTimer(withTimeInterval: max(endDate.timeIntervalSinceNow, 1), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(reason: .expired) }
            }
        }
        watchApp(duration)
        onChange?(.init(icon: lidActive ? "laptopcomputer" : "cup.and.saucer.fill", tint: .orange, title: String(localized: "Uyanık tut"),
                        trailing: Self.label(duration)))
    }

    func stop(reason: StopReason = .user) {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }
        releaseAssertions()
        if lidActive { lid.setDisabled(false) }
        lidActive = false
        isActive = false
        endDate = nil
        let app = { if case .whileApp(let id) = self.duration { return Self.appName(id) }; return nil }()
        duration = .indefinite
        switch reason {
        case .user:
            onChange?(.init(icon: "moon.zzz.fill", tint: .indigo, title: String(localized: "Uyanık tut"), trailing: String(localized: "Kapalı")))
        case .expired:
            onChange?(.init(icon: "moon.zzz.fill", tint: .indigo, title: String(localized: "Süre doldu"), trailing: String(localized: "Kapalı")))
        case .battery:
            onChange?(.init(icon: "battery.25percent", tint: .red, title: String(localized: "Pil azaldı"), trailing: String(localized: "Uyanık tut kapandı")))
        case .appQuit:
            onChange?(.init(icon: "moon.zzz.fill", tint: .indigo, title: app ?? String(localized: "Uygulama"),
                            trailing: String(localized: "kapandı, uyanık tut bitti")))
        }
    }

    func toggle() { isActive ? stop() : start(.indefinite) }

    func checkBattery(level: Int, onBattery: Bool) {
        guard isActive, level > 0 else { return }
        if KeepAwakeRules.shouldStopForBattery(level: level, onBattery: onBattery, threshold: batteryThreshold) { stop(reason: .battery) }
    }

    var remainingText: String? {
        guard let endDate else { return nil }
        let m = max(Int(endDate.timeIntervalSinceNow / 60.0 + 0.999), 1)
        return m >= 60 ? String(localized: "\(m / 60) sa \(m % 60) dk kaldı") : String(localized: "\(m) dk kaldı")
    }

    static func label(_ duration: KeepAwakeDuration) -> String {
        switch duration {
        case .indefinite: return String(localized: "Süresiz")
        case .minutes(let m): return m >= 60 ? String(localized: "\(m / 60) sa") : String(localized: "\(m) dk")
        case .until(let t): return String(localized: "\(t.formatted(date: .omitted, time: .shortened))'e kadar")
        case .whileApp(let id): return appName(id) ?? String(localized: "Uygulama açıkken")
        }
    }

    static func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.deletingPathExtension().lastPathComponent
    }

    private func applyAssertions() {
        releaseAssertions()
        let types = allowDisplaySleep ? [kIOPMAssertPreventUserIdleSystemSleep] : [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertPreventUserIdleSystemSleep]
        for type in types {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "DynIsl: Uyanık tut" as CFString, &id) == kIOReturnSuccess {
                assertions.append(id)
            }
        }
    }

    private func releaseAssertions() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
    }

    private func applyLid() {
        if lidClosedMode, !lidActive {
            lidActive = lid.setDisabled(true)
            lidError = !lidActive
        } else if !lidClosedMode, lidActive {
            lid.setDisabled(false)
            lidActive = false
            lidError = false
        }
    }

    private func reapplyIfActive() {
        guard isActive else { lidError = false; return }
        applyAssertions()
        applyLid()
    }

    private func watchApp(_ duration: KeepAwakeDuration) {
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }
        guard case .whileApp(let id) = duration else { return }
        appObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] note in
            let ended = (note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard ended == id, !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) else { return }
                self?.stop(reason: .appQuit)
            }
        }
    }
}
