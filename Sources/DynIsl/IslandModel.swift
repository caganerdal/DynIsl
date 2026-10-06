import AppKit
import SwiftUI
import IOKit.ps
import Combine

struct IslandActivity: Equatable {
    var icon: String
    var tint: Color
    var title: String
    var trailing: String
    var ring: Double? = nil
}

enum IslandState: Equatable {
    case idle, privacy, playing, call, meeting, speedTest, download, timer, activity, peek, expanded, hud
}

enum IslandTab: String, CaseIterable, Equatable {
    case media, calendar, shelf, clipboard, system, battery

    var title: String {
        switch self {
        case .media: return String(localized: "Müzik")
        case .calendar: return String(localized: "Takvim")
        case .shelf: return String(localized: "Raf ve AirDrop")
        case .clipboard: return String(localized: "Pano")
        case .system: return String(localized: "Sistem")
        case .battery: return String(localized: "Pil")
        }
    }

    var icon: String {
        switch self {
        case .media: return "music.note"
        case .calendar: return "calendar"
        case .shelf: return "tray.full.fill"
        case .clipboard: return "doc.on.clipboard.fill"
        case .system: return "gauge.with.dots.needle.67percent"
        case .battery: return "battery.75percent"
        }
    }
}

@MainActor
final class IslandModel: ObservableObject {
    @Published private(set) var isExpanded = false
    @Published private(set) var activity: IslandActivity?
    @Published private(set) var timerRemaining: Int?
    @Published private(set) var notchSize = CGSize(width: 200, height: 32)
    @Published private(set) var hasNotch = false
    @Published private(set) var petMood: PetMood = .sleeping
    @Published var tab: IslandTab = .media
    @Published var isFileDragging = false

    let media = NowPlayingService()
    let battery = BatteryMonitor()
    let airdrop = AirDropService()
    let bluetooth = BluetoothMonitor()
    let privacy = PrivacyMonitor()
    let focus = FocusMonitor()
    let calendar = CalendarService()
    let shelf = ShelfStore()
    let downloads = DownloadMonitor()
    let clipboard = ClipboardMonitor()
    let screenshots = ScreenshotMonitor()
    let weather = WeatherService()
    let system = SystemMonitor()
    let batteryInfo = BatteryAnalytics()
    let details = SystemDetails()
    let speedTest = SpeedTest()
    let alerts = SystemAlerts()
    let hud = HUDController()
    let call = CallController()
    let desktopCleaner = DesktopCleaner()
    let keepAwake = KeepAwake()
    let network = NetworkWatcher()
    let updates = UpdateChecker()
    let presentation = PresentationMode()
    let downloadsCleaner = DownloadsCleaner()
    @Published var dashboardPage: DashboardPage? = .overview
    let settings = AppSettings()

    private var activityWork: DispatchWorkItem?
    private var lastCLISound = Date.distantPast
    private var countdown: Timer?
    private var bag: [Any] = []

    init() {
        bag.append(media.objectWillChange.sink { [weak self] _ in self?.objectWillChange.send() })
        for publisher in [battery.objectWillChange, privacy.objectWillChange, focus.objectWillChange,
                          calendar.objectWillChange, shelf.objectWillChange, downloads.objectWillChange,
                          settings.objectWillChange, screenshots.objectWillChange, speedTest.objectWillChange,
                          hud.objectWillChange, call.objectWillChange, keepAwake.objectWillChange, updates.objectWillChange, presentation.objectWillChange] {
            bag.append(publisher.sink { [weak self] _ in self?.objectWillChange.send() })
        }

        battery.onActivity = { [weak self] a in
            guard let self else { return }
            self.batteryInfo.powerSourceChanged()
            if self.settings.notifyBattery { self.showActivity(a) }
        }
        batteryInfo.start()
        keepAwake.onChange = { [weak self] a in self?.showActivity(a, duration: 2) }
        bluetooth.onActivity = { [weak self] a in
            guard let self, self.settings.notifyBluetooth else { return }
            self.showActivity(a)
        }
        bluetooth.onLowBattery = { [weak self] a in
            guard let self, self.settings.airPodsBatteryAlert else { return }
            self.showActivity(a, duration: 5)
        }
        battery.onReminder = { [weak self] in self?.showActivity($0, duration: 6) }
        let syncCharge = { [weak self] in
            guard let self else { return }
            self.battery.chargeLimit = self.settings.chargeLimitAlert ? self.settings.chargeLimit : nil
            self.battery.fullReminderAfter = self.settings.fullPluggedAlert ? 2 * 3600 : nil
        }
        syncCharge()

        bag.append(settings.objectWillChange.receive(on: RunLoop.main).sink { _ in syncCharge() })
        bluetooth.start()
        privacy.onActivity = { [weak self] a in
            guard let self, self.settings.showPrivacy else { return }
            self.showActivity(a)
        }
        privacy.start()
        focus.onActivity = { [weak self] a in
            guard let self, self.settings.notifyFocus else { return }
            self.showActivity(a)
        }
        focus.start()
        calendar.onActivity = { [weak self] a in
            guard let self, self.settings.notifyCalendar else { return }
            self.showActivity(a, duration: 5)
        }
        calendar.leadMinutes = settings.calendarLeadMinutes
        bag.append(settings.$calendarLeadMinutes.sink { [weak self] in self?.calendar.leadMinutes = $0 })
        calendar.start()
        downloads.onFinished = { [weak self] url in
            guard let self else { return }
            if self.settings.downloadsToShelf { self.shelf.add([url]) }
            if self.settings.showDownloads {
                self.showActivity(.init(icon: "arrow.down.circle.fill", tint: .green,
                                        title: url.lastPathComponent, trailing: String(localized: "İndirildi")))
            }
        }
        downloads.start()
        clipboard.isEnabled = settings.clipboardHistory
        bag.append(settings.$clipboardHistory.sink { [weak self] on in
            self?.clipboard.isEnabled = on
            if !on { self?.clipboard.clear() }
        })
        clipboard.start()
        screenshots.onNew = { [weak self] shot in
            guard let self else { return }
            if self.settings.screenshotsToShelf { self.shelf.add([shot.url]) }
            if !self.settings.screenshotPreview || self.presentation.isActive { self.screenshots.dismiss() }
        }
        screenshots.start()

        weather.onActivity = { [weak self] a in
            guard let self, self.settings.rainAlerts, self.settings.showWeather else { return }
            self.showActivity(a, duration: 5)
        }
        weather.manualCity = settings.weatherCity
        bag.append(settings.$weatherCity.debounce(for: .seconds(1.5), scheduler: RunLoop.main)
            .sink { [weak self] in self?.weather.manualCity = $0 })
        if settings.showWeather { weather.start() }
        bag.append(settings.$showWeather.dropFirst().sink { [weak self] on in
            if on { self?.weather.start() }
        })

        network.onActivity = { [weak self] a in
            guard let self, self.settings.notifyNetwork else { return }
            self.showActivity(a, duration: 5)
        }
        network.start()

        shelf.onConverted = { [weak self] kind, r in
            let size = ByteCountFormatter.string(fromByteCount: r.saved, countStyle: .file)
            let text: String
            if r.outputs.isEmpty {
                text = r.skipped > 0 ? String(localized: "Zaten küçük") : String(localized: "Dönüştürülemedi")
            } else if r.saved > 0 {
                text = String(localized: "\(r.outputs.count) dosya · \(size) kazanıldı")
            } else {
                text = kind == .mergePDF ? String(localized: "PDF hazır, rafta") : String(localized: "\(r.outputs.count) dosya hazır")
            }
            self?.showActivity(.init(icon: r.outputs.isEmpty ? "exclamationmark.triangle.fill" : "checkmark.circle.fill",
                                     tint: r.outputs.isEmpty ? .orange : .green, title: kind.title, trailing: text), duration: 3)
        }

        presentation.autoDetect = settings.presentationAuto
        presentation.hideIcons = settings.presentationHideIcons
        bag.append(settings.$presentationAuto.dropFirst().sink { [weak self] in self?.presentation.autoDetect = $0 })
        bag.append(settings.$presentationHideIcons.dropFirst().sink { [weak self] in self?.presentation.hideIcons = $0 })
        presentation.onChange = { [weak self] active, manual in
            guard let self else { return }
            if active { self.screenshots.dismiss() }
            if manual || !active {
                self.showActivity(.init(icon: active ? "play.rectangle.fill" : "rectangle.slash", tint: active ? .purple : .gray,
                                        title: String(localized: "Sunum modu"), trailing: active ? String(localized: "Açık") : String(localized: "Kapalı")), duration: 2, force: true)
            }
        }
        presentation.start()

        for publisher in [battery.objectWillChange, media.objectWillChange] {
            bag.append(publisher.sink { [weak self] _ in DispatchQueue.main.async { self?.updatePetMood() } })
        }
        bag.append(system.$cpu.sink { [weak self] _ in DispatchQueue.main.async { self?.updatePetMood() } })

        updates.onActivity = { [weak self] in self?.showActivity($0, duration: 5) }
        updates.enabled = settings.checkUpdates
        bag.append(settings.$checkUpdates.dropFirst().sink { [weak self] in self?.updates.enabled = $0 })
        updates.start()

        system.onActivity = { [weak self] in self?.showActivity($0, duration: 5) }
        system.alertsEnabled = settings.systemAlerts
        bag.append(settings.$systemAlerts.sink { [weak self] in self?.system.alertsEnabled = $0 })
        system.start()

        speedTest.onFinished = { [weak self] r in
            self?.showActivity(.init(icon: "gauge.with.needle.fill", tint: .cyan, title: String(localized: "Hız testi"),
                                     trailing: "↓ \(Int(r.downMbps)) · ↑ \(Int(r.upMbps)) Mbps"), duration: 6)
        }

        alerts.onActivity = { [weak self] in self?.showActivity($0, duration: 5) }
        let syncAlerts = { [weak self] in
            guard let self else { return }
            self.alerts.diskEnabled = self.settings.alertDisk
            self.alerts.memoryEnabled = self.settings.alertMemory
            self.alerts.thermalEnabled = self.settings.alertThermal
            self.alerts.batteryHealthEnabled = self.settings.alertBatteryHealth
        }
        syncAlerts()
        bag.append(settings.objectWillChange.receive(on: RunLoop.main).sink { _ in syncAlerts() })
        alerts.start { [weak self] in self?.batteryInfo.healthPercent }
        bag.append(batteryInfo.$healthPercent.dropFirst().sink { [weak self] in self?.alerts.checkBatteryHealth($0) })

        bag.append(privacy.objectWillChange.receive(on: RunLoop.main).sink { [weak self] _ in
            guard let self else { return }
            self.call.update(camera: self.privacy.cameraOn, mic: self.privacy.micOn, apps: self.privacy.micApps)
        })

        hud.onNeedsPermission = { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                MainActor.assumeIsolated {
                    guard let self, self.hud.needsPermission else { return }
                    self.showActivity(.init(icon: "lock.fill", tint: .orange, title: String(localized: "Ses göstergesi"),
                                            trailing: String(localized: "İzin gerekli")), duration: 5)
                }
            }
        }
        hud.enabled = settings.replaceHUD
        bag.append(settings.$replaceHUD.dropFirst().sink { [weak self] in self?.hud.enabled = $0 })
        hud.start()

        bag.append($isExpanded.combineLatest($tab).sink { [weak self] expanded, tab in
            self?.system.isVisible = expanded && tab == .system
            self?.media.isVisible = expanded && tab == .media
            self?.batteryInfo.isVisible = expanded && tab == .battery
        })
        bag.append(settings.$hiddenTabs.sink { [weak self] hidden in
            if let self, hidden.contains(self.tab) { self.tab = .media }
        })

        DistributedNotificationCenter.default().addObserver(
            forName: CLI.notificationName, object: nil, queue: .main
        ) { [weak self] note in
            let info = note.userInfo ?? [:]
            let icon = (info["icon"] as? String).flatMap {
                $0.count <= 64 && NSImage(systemSymbolName: $0, accessibilityDescription: nil) != nil ? $0 : nil
            } ?? "terminal.fill"
            let activity = IslandActivity(
                icon: icon,
                tint: Self.color(named: info["tint"] as? String ?? "white"),
                title: Self.sanitize(info["title"] as? String ?? "Terminal", max: 40),
                trailing: Self.sanitize(info["message"] as? String ?? "", max: 80)
            )
            let duration = min(max(info["duration"] as? Double ?? 4, 1), 15)
            let sound = info["sound"] as? Bool ?? false
            MainActor.assumeIsolated {
                guard let self else { return }
                self.showActivity(activity, duration: duration)
                if sound, Date().timeIntervalSince(self.lastCLISound) > 3 {
                    self.lastCLISound = Date()
                    NSSound(named: "Glass")?.play()
                }
            }
        }
        airdrop.onResult = { [weak self] ok, count in
            if ok {
                self?.showActivity(.init(icon: "checkmark.circle.fill", tint: .blue, title: "AirDrop", trailing: String(localized: "\(count) dosya gitti")))
            } else {
                self?.showActivity(.init(icon: "exclamationmark.triangle.fill", tint: .yellow, title: "AirDrop", trailing: String(localized: "Gönderilemedi")))
            }
        }
    }

    func configure(for screen: NSScreen) {
        let top = screen.safeAreaInsets.top
        if top > 0,
           let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea {
            hasNotch = true
            notchSize = CGSize(width: screen.frame.width - left.width - right.width, height: top)
        } else {
            hasNotch = false
            notchSize = CGSize(width: 190, height: 30)
        }
    }

    var state: IslandState {
        if hud.current != nil { return .hud }
        if isExpanded { return .expanded }
        if screenshots.current != nil { return .peek }
        if activity != nil { return .activity }
        if timerRemaining != nil { return .timer }
        if settings.showDownloads, downloads.summary != nil { return .download }
        if speedTest.isRunning { return .speedTest }
        if settings.notifyCalendar, calendar.imminent != nil { return .meeting }
        if settings.callMode, settings.showPrivacy, call.isActive { return .call }
        if media.isPlaying { return .playing }
        if settings.showPrivacy, privacy.isActive { return .privacy }
        return .idle
    }

    var expandedSize: CGSize {
        let extra: CGFloat
        switch tab {
        case .media: extra = media.info != nil ? 190 : 150
        case .battery: extra = 196
        case .system: extra = 176
        default: extra = 150
        }
        return CGSize(width: CGFloat(settings.islandWidth), height: notchSize.height + extra)
    }

    var currentSize: CGSize {
        switch state {
        case .idle: return CGSize(width: notchSize.width + 2 * petEar, height: notchSize.height)
        case .call:
            let w = textWidth(call.appName ?? String(localized: "Görüşme"), weight: .medium) + 34
            return CGSize(width: notchSize.width + 2 * min(max(w, 100), 180), height: notchSize.height)
        case .playing: return CGSize(width: notchSize.width + 100 + 2 * petEar, height: notchSize.height)
        case .timer, .meeting, .privacy, .download, .speedTest: return CGSize(width: notchSize.width + 100, height: notchSize.height)
        case .activity: return CGSize(width: notchSize.width + 2 * activityEarWidth, height: notchSize.height)
        case .hud:
            let style = hud.current.map { settings.hudStyle(for: $0.kind) } ?? .classic
            if style.isCompact { return CGSize(width: notchSize.width + 2 * style.earWidth, height: notchSize.height) }
            return CGSize(width: max(400, notchSize.width + 190), height: notchSize.height + 34)
        case .peek: return CGSize(width: max(500, notchSize.width + 240), height: notchSize.height + 118)
        case .expanded: return expandedSize
        }
    }

    private var widthCache: [String: CGFloat] = [:]
    private func textWidth(_ s: String, weight: NSFont.Weight) -> CGFloat {
        if let w = widthCache[s] { return w }
        let w = (s as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: weight)]).width
        if widthCache.count > 200 { widthCache.removeAll() }
        widthCache[s] = w
        return w
    }

    private var activityEarWidth: CGFloat = 130

    private static func earWidth(for a: IslandActivity) -> CGFloat {
        let left = 26 + (a.title as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .medium)]).width
        let right = (a.trailing as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
            + (a.ring != nil ? 22 : 0)
        return min(max(max(left, right) + 22, 110), 230)
    }

    private func updatePetMood() {
        let m: PetMood
        if system.cpu >= 0.85 { m = .hot }
        else if battery.hasBattery, !battery.isPluggedIn, battery.level <= 20 { m = .tired }
        else if media.isPlaying { m = .dancing }
        else { m = .sleeping }
        if m != petMood { petMood = m }
    }

    var petEar: CGFloat { settings.showPet ? 30 : 0 }

    var accent: Color? {
        switch settings.accentMode {
        case .classic: return nil
        case .system: return Color(nsColor: .controlAccentColor)
        case .album: return media.isPlaying && media.artwork != nil ? media.accent : Color(nsColor: .controlAccentColor)
        case .custom: return Color(hex: settings.accentHex) ?? .blue
        }
    }

    private(set) var previewHold = false
    private var previewWork: DispatchWorkItem?

    func previewAppearance() {
        previewHold = true
        if !isExpanded { setExpanded(true) }
        previewWork?.cancel()
        let w = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                self?.previewHold = false
                self?.setExpanded(false)
            }
        }
        previewWork = w
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5, execute: w)
    }

    func setExpanded(_ value: Bool) {
        isExpanded = value
        if value, isFileDragging { tab = .shelf }
        if value { shelf.prune() }
    }

    nonisolated static func sanitize(_ s: String, max: Int) -> String {
        let clean = String(s.unicodeScalars.map { CharacterSet.controlCharacters.contains($0) ? " " : Character($0) })
            .trimmingCharacters(in: .whitespaces)
        return clean.count > max ? String(clean.prefix(max - 1)) + "…" : clean
    }

    nonisolated static func color(named name: String) -> Color {
        switch name.lowercased() {
        case "green", "yeşil": return .green
        case "red", "kırmızı": return .red
        case "orange", "turuncu": return .orange
        case "yellow", "sarı": return .yellow
        case "blue", "mavi": return .blue
        case "purple", "mor": return .purple
        case "pink", "pembe": return .pink
        case "teal": return .teal
        default: return .white
        }
    }

    func showActivity(_ a: IslandActivity, duration: TimeInterval = 3, force: Bool = false) {
        guard force || !presentation.isActive else { return }
        activityWork?.cancel()
        activityEarWidth = Self.earWidth(for: a)
        activity = a
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.activity = nil }
        }
        activityWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: work)
    }

    func startTimer(seconds: Int) {
        countdown?.invalidate()
        timerRemaining = seconds
        countdown = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self, let r = self.timerRemaining else { t.invalidate(); return }
                if r <= 1 {
                    t.invalidate()
                    self.timerRemaining = nil
                    NSSound(named: "Glass")?.play()
                    self.showActivity(.init(icon: "timer", tint: .orange, title: String(localized: "Zamanlayıcı"), trailing: String(localized: "Bitti!")))
                } else {
                    self.timerRemaining = r - 1
                }
            }
        }
    }

    func cancelTimer() {
        countdown?.invalidate()
        timerRemaining = nil
    }
}

@MainActor
final class BatteryMonitor: ObservableObject {
    @Published private(set) var level = 100
    @Published private(set) var isCharging = false
    @Published private(set) var isPluggedIn = false
    @Published private(set) var hasBattery = false

    var onActivity: ((IslandActivity) -> Void)?
    var onReminder: ((IslandActivity) -> Void)?
    var chargeLimit: Int? = 80
    var fullReminderAfter: TimeInterval? = 2 * 3600
    private var limitNotified = false
    private var fullSince: Date?
    private var fullNotifiedAt = Date.distantPast
    private var runLoopSource: CFRunLoopSource?
    private var poll: Timer?

    init() {
        refresh(notify: false)
        let ctx = Unmanaged.passUnretained(self).toOpaque()
        if let src = IOPSNotificationCreateRunLoopSource({ ctx in
            guard let ctx else { return }
            let me = Unmanaged<BatteryMonitor>.fromOpaque(ctx).takeUnretainedValue()
            MainActor.assumeIsolated { me.refresh(notify: true) }
        }, ctx)?.takeRetainedValue() {
            CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)
            runLoopSource = src
        }
        poll = Timer.repeating(every: 60) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh(notify: true) }
        }
    }

    private func refresh(notify: Bool) {
        let snapshot = IOPSCopyPowerSourcesInfo().takeRetainedValue()
        let sources = IOPSCopyPowerSourcesList(snapshot).takeRetainedValue() as [CFTypeRef]
        for source in sources {
            guard let desc = IOPSGetPowerSourceDescription(snapshot, source)?.takeUnretainedValue() as? [String: Any],
                  desc[kIOPSTypeKey] as? String == kIOPSInternalBatteryType else { continue }
            if !hasBattery { hasBattery = true }
            let current = desc[kIOPSCurrentCapacityKey] as? Int ?? 0
            let max = desc[kIOPSMaxCapacityKey] as? Int ?? 100
            let newLevel = max > 0 ? Int((Double(current) / Double(max) * 100).rounded()) : current
            let plugged = (desc[kIOPSPowerSourceStateKey] as? String) == kIOPSACPowerValue
            let charged = desc[kIOPSIsChargedKey] as? Bool ?? (newLevel >= 100)

            if notify {
                if plugged != isPluggedIn {
                    onActivity?(plugged ? chargingActivity(newLevel) : unpluggedActivity(newLevel))
                } else if !plugged, newLevel < level, let low = lowBatteryActivity(from: level, to: newLevel) {
                    onActivity?(low)
                } else if plugged, charged, level < 100, newLevel >= 100 {
                    onActivity?(.init(icon: "battery.100percent", tint: .green, title: String(localized: "Tamamen şarj oldu"), trailing: pc(100), ring: 1))
                }
            }
            let charging = desc[kIOPSIsChargingKey] as? Bool ?? false
            if notify { checkReminders(old: level, new: newLevel, plugged: plugged, charging: charging, charged: charged) }
            if level != newLevel { level = newLevel }
            if isPluggedIn != plugged { isPluggedIn = plugged }
            if isCharging != charging { isCharging = charging }
        }
    }

    private func checkReminders(old: Int, new: Int, plugged: Bool, charging: Bool, charged: Bool) {
        guard plugged else {
            limitNotified = false
            fullSince = nil
            return
        }
        if let limit = chargeLimit, limit < 100, charging, old < limit, new >= limit, !limitNotified {
            limitNotified = true
            onReminder?(.init(icon: "powerplug.fill", tint: .green, title: String(localized: "Pil \(pc(new))"),
                              trailing: String(localized: "Şarjı çıkarabilirsin"), ring: Double(new) / 100))
        }
        if new >= 100 || charged {
            let since = fullSince ?? Date()
            fullSince = since
            if let after = fullReminderAfter, Date().timeIntervalSince(since) >= after,
               Date().timeIntervalSince(fullNotifiedAt) > 24 * 3600 {
                fullNotifiedAt = Date()
                let hours = Int(Date().timeIntervalSince(since) / 3600)
                onReminder?(.init(icon: "battery.100percent", tint: .yellow, title: String(localized: "\(hours) saattir \(pc(100))"),
                                  trailing: String(localized: "Pil için çıkarabilirsin"), ring: 1))
            }
        } else {
            fullSince = nil
        }
    }

    private func chargingActivity(_ l: Int) -> IslandActivity {
        .init(icon: "bolt.fill", tint: .green, title: String(localized: "Şarj oluyor"), trailing: pc(l), ring: Double(l) / 100)
    }

    private func unpluggedActivity(_ l: Int) -> IslandActivity {
        .init(icon: symbol(for: l, charging: false), tint: l <= 20 ? .orange : .white,
              title: String(localized: "Pil gücü"), trailing: pc(l), ring: Double(l) / 100)
    }

    private func lowBatteryActivity(from old: Int, to new: Int) -> IslandActivity? {
        for (threshold, tint) in [(10, Color.red), (20, Color.orange)] where old > threshold && new <= threshold {
            return .init(icon: "battery.25percent", tint: tint, title: String(localized: "Düşük pil"), trailing: pc(new), ring: Double(new) / 100)
        }
        return nil
    }

    var symbol: String { symbol(for: level, charging: isCharging) }

    private func symbol(for level: Int, charging: Bool) -> String {
        if charging { return "battery.100percent.bolt" }
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}
