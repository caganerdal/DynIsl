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
    @Published var batteryThreshold: Int {
        didSet {
            d.set(batteryThreshold, forKey: "keepAwakeBatteryThreshold")
            if let s = batteryState?() { checkBattery(level: s.level, onBattery: s.onBattery) }
        }
    }

    let lid = LidSleepControl()
    var onChange: ((IslandActivity) -> Void)?
    var batteryState: (() -> (level: Int, onBattery: Bool)?)?

    private let d = UserDefaults.standard
    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?
    private var appObserver: NSObjectProtocol?
    private var wakeObserver: NSObjectProtocol?
    private var lidWanted = false
    private var lidGeneration = 0

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
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.handleWake() }
        }
    }

    func start(_ duration: KeepAwakeDuration) {
        if case .whileApp(let id) = duration, !NSWorkspace.shared.runningApplications.contains(where: { $0.bundleIdentifier == id }) {
            onChange?(.init(icon: "app.dashed", tint: .orange, title: String(localized: "Uyanık tut"), trailing: String(localized: "Uygulama açık değil")))
            return
        }
        if let s = batteryState?(), s.level > 0,
           KeepAwakeRules.shouldStopForBattery(level: s.level, onBattery: s.onBattery, threshold: batteryThreshold) {
            onChange?(.init(icon: "battery.25percent", tint: .red, title: String(localized: "Pil azaldı"),
                            trailing: String(localized: "Önce şarja tak")))
            return
        }
        guard applyAssertions() else { return }
        isActive = true
        self.duration = duration
        applyLid()
        endDate = KeepAwakeRules.endDate(for: duration, now: Date(), calendar: .current)
        scheduleTimer()
        watchApp(duration)
        onChange?(.init(icon: lidWanted ? "laptopcomputer" : "cup.and.saucer.fill", tint: .orange, title: String(localized: "Uyanık tut"),
                        trailing: Self.label(duration)))
    }

    func handleWake(now: Date = Date()) {
        guard isActive, let endDate else { return }
        if endDate <= now { stop(reason: .expired) } else { scheduleTimer(now: now) }
    }

    func shutdown() {
        let engaged = lidWanted || lidActive
        stop()
        if engaged { lid.setDisabledNow(false) }
    }

    private func scheduleTimer(now: Date = Date()) {
        timer?.invalidate()
        timer = nil
        guard let endDate else { return }
        timer = Timer.scheduledTimer(withTimeInterval: max(endDate.timeIntervalSince(now), 1), repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: .expired) }
        }
    }

    func stop(reason: StopReason = .user) {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        if let o = appObserver { NSWorkspace.shared.notificationCenter.removeObserver(o); appObserver = nil }
        releaseAssertions()
        isActive = false
        applyLid()
        lidActive = false
        lidError = false
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
        case .until(let t): return String(localized: "\(t.formatted(date: .omitted, time: .shortened)) saatine kadar")
        case .whileApp(let id): return appName(id) ?? String(localized: "Uygulama açıkken")
        }
    }

    static func appName(_ bundleID: String) -> String? {
        NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == bundleID }?.localizedName
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.deletingPathExtension().lastPathComponent
    }

    @discardableResult
    private func applyAssertions() -> Bool {
        let types = allowDisplaySleep ? [kIOPMAssertPreventUserIdleSystemSleep] : [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertPreventUserIdleSystemSleep]
        var created: [IOPMAssertionID] = []
        for type in types {
            var id: IOPMAssertionID = 0
            if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                           "DynIsl Keep Awake" as CFString, &id) == kIOReturnSuccess {
                created.append(id)
            }
        }
        guard created.count == types.count else {
            created.forEach { IOPMAssertionRelease($0) }
            return !assertions.isEmpty
        }
        releaseAssertions()
        assertions = created
        return true
    }

    private func releaseAssertions() {
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
    }

    private func applyLid() {
        let want = isActive && lidClosedMode
        guard want != lidWanted else { return }
        lidWanted = want
        lidGeneration += 1
        let generation = lidGeneration
        Task {
            let ok = await lid.setDisabled(want)
            guard generation == lidGeneration else { return }
            lidActive = want && ok
            lidError = want && !ok
            if want && !ok {
                onChange?(.init(icon: "exclamationmark.triangle.fill", tint: .orange, title: String(localized: "Kapak modu açılamadı"),
                                trailing: String(localized: "Normal uyanık tut açık")))
            }
        }
    }

    func reapply() { reapplyIfActive() }

    private func reapplyIfActive() {
        guard isActive else { lidError = false; return }
        if lidError { lidWanted = false }
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
