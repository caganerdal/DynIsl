import AppKit

struct CodexLimits: Equatable {
    var primary: LimitWindow?
    var secondary: LimitWindow?
    var updatedAt: Date
}

@MainActor
final class AIUsageStore: ObservableObject {
    @Published private(set) var limits: ClaudeLimits?
    @Published private(set) var summary = AIUsageSummary()
    @Published private(set) var codex: CodexLimits?
    @Published private(set) var linked = false
    @Published private(set) var linkMessage: String?
    @Published private(set) var scanning = false
    @Published var alertsEnabled: Bool { didSet { UserDefaults.standard.set(alertsEnabled, forKey: "aiUsageAlerts") } }

    var onChange: ((IslandActivity) -> Void)?

    private let home = FileManager.default.homeDirectoryForCurrentUser
    private var settingsURL: URL { home.appendingPathComponent(".claude/settings.json") }
    private var cacheURL: URL { CLI.usageURL.deletingLastPathComponent().appendingPathComponent("ai-scan.json") }
    private let queue = DispatchQueue(label: "local.dynamicisland.ai-scan", qos: .utility)
    private var scanner: ClaudeLogScanner?
    private var lastScan = Date.distantPast
    private var resetTimer: Timer?
    private var refreshTimer: Timer?

    init() {
        UserDefaults.standard.register(defaults: ["aiUsageAlerts": true])
        alertsEnabled = UserDefaults.standard.bool(forKey: "aiUsageAlerts")
        limits = CLI.readUsage()
        refreshLink()
        let token = CLI.token(create: true)
        DistributedNotificationCenter.default().addObserver(forName: CLI.usageNotificationName, object: nil, queue: .main) { [weak self] note in
            guard let token, note.userInfo?["token"] as? String == token else { return }
            MainActor.assumeIsolated { self?.reloadLimits() }
        }
        scheduleReset()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: 600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        refreshTimer?.tolerance = 120
        refresh(force: true)
    }

    var fiveHour: LimitWindow? { AIUsageRules.effective(limits?.fiveHour, now: Date()) }
    var sevenDay: LimitWindow? { AIUsageRules.effective(limits?.sevenDay, now: Date()) }

    func reloadLimits() {
        guard let new = CLI.readUsage(), new != limits else { return }
        let alerts = AIUsageRules.alerts(old: limits, new: new)
        limits = new
        scheduleReset()
        if alertsEnabled, let a = alerts.last { announce(a) }
        refresh()
    }

    func refresh(force: Bool = false) {
        guard !scanning, force || Date().timeIntervalSince(lastScan) > 60 else { return }
        scanning = true
        lastScan = Date()
        let root = home.appendingPathComponent(".claude/projects")
        let codexRoot = home.appendingPathComponent(".codex/sessions")
        let cacheURL = cacheURL
        let existing = scanner
        queue.async {
            let s = existing ?? ClaudeLogScanner(root: root, state: Self.loadState(cacheURL))
            let now = Date()
            if s.scan(now: now) || existing == nil { Self.saveState(s.state, to: cacheURL) }
            let summary = s.summary(now: now)
            let codex = Self.readCodex(codexRoot, now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanner = s
                    self.summary = summary
                    self.codex = codex
                    self.scanning = false
                }
            }
        }
    }

    private func announce(_ a: AIUsageRules.UsageAlert) {
        switch a {
        case .fiveHour(let t):
            onChange?(.init(icon: "sparkle", tint: t >= 95 ? .red : .orange, title: String(localized: "Claude 5 saatlik limit"),
                            trailing: "%\(Int(t))", ring: t / 100))
        case .sevenDay(let t):
            onChange?(.init(icon: "sparkle", tint: .orange, title: String(localized: "Claude haftalık limit"),
                            trailing: "%\(Int(t))", ring: t / 100))
        }
    }

    private func scheduleReset() {
        resetTimer?.invalidate()
        resetTimer = nil
        guard let w = limits?.fiveHour, w.usedPercent >= AIUsageRules.fiveHourThresholds[0], w.resetsAt > Date() else { return }
        resetTimer = Timer.scheduledTimer(withTimeInterval: w.resetsAt.timeIntervalSinceNow + 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.objectWillChange.send()
                if self.alertsEnabled {
                    self.onChange?(.init(icon: "sparkle", tint: .green, title: "Claude", trailing: String(localized: "Limitin açıldı")))
                }
            }
        }
    }

    var linkCommand: String {
        let exe = Bundle.main.executablePath ?? "island"
        return "'" + exe.replacingOccurrences(of: "'", with: "'\\''") + "' claude-status"
    }

    func refreshLink() {
        let current = try? Data(contentsOf: settingsURL)
        linked = AIUsageRules.isLinked(settings: current)
        guard linked, let current, AIUsageRules.statusCommand(settings: current) != linkCommand,
              let out = try? AIUsageRules.connect(settings: current, command: linkCommand) else { return }
        try? out.write(to: settingsURL, options: .atomic)
    }

    func connect() {
        let current = try? Data(contentsOf: settingsURL)
        do {
            let out = try AIUsageRules.connect(settings: current, command: linkCommand)
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let current {
                try current.write(to: settingsURL.appendingPathExtension("dynisl-backup"), options: .atomic)
            }
            try out.write(to: settingsURL, options: .atomic)
            linkMessage = String(localized: "Bağlandı. Claude Code'da bir sonraki yanıttan sonra limitler görünür.")
        } catch AIUsageRules.LinkError.foreignStatusLine {
            linkMessage = String(localized: "Claude Code'da zaten başka bir durum çubuğu var; üzerine yazmadım. Kendi betiğinin sonuna stdin'i \"island claude-status\" komutuna aktaran bir satır ekleyebilirsin.")
        } catch AIUsageRules.LinkError.invalidSettings {
            linkMessage = String(localized: "~/.claude/settings.json okunamadı (geçersiz JSON); dokunmadım.")
        } catch {
            linkMessage = String(localized: "Ayar dosyası yazılamadı.")
        }
        refreshLink()
    }

    func disconnect() {
        guard let current = try? Data(contentsOf: settingsURL), let out = AIUsageRules.disconnect(settings: current) else { return }
        do {
            try out.write(to: settingsURL, options: .atomic)
            linkMessage = nil
        } catch {
            linkMessage = String(localized: "Ayar dosyası yazılamadı.")
        }
        refreshLink()
    }

    nonisolated private static func loadState(_ url: URL) -> ScanState {
        (try? Data(contentsOf: url)).flatMap { try? JSONDecoder().decode(ScanState.self, from: $0) } ?? ScanState()
    }

    nonisolated private static func saveState(_ state: ScanState, to url: URL) {
        guard let data = try? JSONEncoder().encode(state) else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if (try? data.write(to: url, options: .atomic)) != nil {
            try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        }
    }

    nonisolated private static func readCodex(_ root: URL, now: Date) -> CodexLimits? {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var newest: (URL, Date)?
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate else { continue }
            if newest == nil || m > newest!.1 { newest = (url, m) }
        }
        guard let (url, modified) = newest, let h = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? h.close() }
        let size = (try? h.seekToEnd()) ?? 0
        try? h.seek(toOffset: size > 262_144 ? size - 262_144 : 0)
        guard let data = try? h.readToEnd(), let text = String(data: data, encoding: .utf8) else { return nil }
        for line in text.split(separator: "\n").reversed() {
            if let r = AIUsageRules.parseCodex(line, now: modified) {
                return CodexLimits(primary: r.primary, secondary: r.secondary, updatedAt: modified)
            }
        }
        return nil
    }
}
