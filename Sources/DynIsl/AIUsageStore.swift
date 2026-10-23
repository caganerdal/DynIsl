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
    private var announcedReset: Date?

    init() {
        UserDefaults.standard.register(defaults: ["aiUsageAlerts": true])
        alertsEnabled = UserDefaults.standard.bool(forKey: "aiUsageAlerts")
        limits = CLI.readUsage()
        refreshLink()
        DistributedNotificationCenter.default().addObserver(forName: CLI.usageNotificationName, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reloadLimits() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.scheduleReset() }
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
            if s.scan(now: now, checkpoint: { Self.saveState($0, to: cacheURL) }) { Self.saveState(s.state, to: cacheURL) }
            let summary = s.summary(now: now)
            let codex = Self.readCodex(codexRoot, now: now)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.scanner = s
                    self.summary = summary
                    self.codex = codex ?? self.codex
                    self.scanning = false
                }
            }
        }
    }

    private func announce(_ a: AIUsageRules.UsageAlert) {
        switch a {
        case .fiveHour(let t):
            onChange?(.init(icon: "sparkle", tint: t >= 95 ? .red : .orange, title: String(localized: "Claude 5 saatlik limit"),
                            trailing: pc(Int(t)), ring: t / 100))
        case .sevenDay(let t):
            onChange?(.init(icon: "sparkle", tint: .orange, title: String(localized: "Claude haftalık limit"),
                            trailing: pc(Int(t)), ring: t / 100))
        }
    }

    private func scheduleReset() {
        resetTimer?.invalidate()
        resetTimer = nil
        guard let w = limits?.fiveHour, w.usedPercent >= AIUsageRules.fiveHourThresholds[0], announcedReset != w.resetsAt else { return }
        let wait = w.resetsAt.timeIntervalSinceNow
        if wait <= 0 {
            if wait > -900 { announceReset(w.resetsAt) }
            return
        }
        resetTimer = Timer.scheduledTimer(withTimeInterval: wait + 1, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.announceReset(w.resetsAt) }
        }
    }

    private func announceReset(_ at: Date) {
        guard announcedReset != at else { return }
        announcedReset = at
        objectWillChange.send()
        if alertsEnabled {
            onChange?(.init(icon: "sparkle", tint: .green, title: "Claude", trailing: String(localized: "Limitin açıldı")))
        }
    }

    private var executable: String { Bundle.main.executablePath ?? "island" }
    var linkCommand: String { AIUsageRules.linkCommand(executable: executable) }
    private var settingsTarget: URL { settingsURL.resolvingSymlinksInPath() }

    func refreshLink() {
        let current = try? Data(contentsOf: settingsTarget)
        linked = AIUsageRules.isLinked(settings: current)
        guard linked, let current, let command = AIUsageRules.statusCommand(settings: current),
              AIUsageRules.shouldRelink(current: command, executable: executable, exists: { FileManager.default.isExecutableFile(atPath: $0) }),
              let out = try? AIUsageRules.connect(settings: current, command: linkCommand) else { return }
        backup(current)
        try? writeSettings(out, expected: current)
    }

    private func backup(_ data: Data) {
        let url = settingsURL.appendingPathExtension("dynisl-backup")
        guard !FileManager.default.fileExists(atPath: url.path) else { return }
        FileManager.default.createFile(atPath: url.path, contents: data, attributes: [.posixPermissions: 0o600])
    }

    private func writeSettings(_ out: Data, expected: Data?) throws {
        try Self.writePreservingMode(out, to: settingsTarget, expected: expected)
    }

    nonisolated static func writePreservingMode(_ out: Data, to target: URL, expected: Data?) throws {
        guard (try? Data(contentsOf: target)) == expected else { throw CocoaError(.fileWriteUnknown) }
        let mode = (try? FileManager.default.attributesOfItem(atPath: target.path)[.posixPermissions] as? NSNumber)?.int16Value ?? 0o600
        let tmp = target.deletingLastPathComponent().appendingPathComponent(".\(target.lastPathComponent).dynisl-\(getpid())")
        guard FileManager.default.createFile(atPath: tmp.path, contents: out, attributes: [.posixPermissions: mode]) else {
            throw CocoaError(.fileWriteUnknown)
        }
        guard rename(tmp.path, target.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            throw CocoaError(.fileWriteUnknown)
        }
    }


    func connect() {
        let current = try? Data(contentsOf: settingsTarget)
        do {
            let out = try AIUsageRules.connect(settings: current, command: linkCommand)
            try FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            if let current { backup(current) }
            try writeSettings(out, expected: current)
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
        guard let current = try? Data(contentsOf: settingsTarget), let out = AIUsageRules.disconnect(settings: current) else { return }
        do {
            try writeSettings(out, expected: current)
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
        let tmp = url.deletingLastPathComponent().appendingPathComponent(".\(url.lastPathComponent).tmp")
        if FileManager.default.createFile(atPath: tmp.path, contents: data, attributes: [.posixPermissions: 0o600]),
           rename(tmp.path, url.path) != 0 {
            try? FileManager.default.removeItem(at: tmp)
        }
    }

    nonisolated private static func readCodex(_ root: URL, now: Date) -> CodexLimits? {
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: [.contentModificationDateKey]) else { return nil }
        var files: [(URL, Date)] = []
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            if let m = try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate { files.append((url, m)) }
        }
        for (url, modified) in files.sorted(by: { $0.1 > $1.1 }).prefix(5) {
            guard let h = try? FileHandle(forReadingFrom: url) else { continue }
            defer { try? h.close() }
            let size = (try? h.seekToEnd()) ?? 0
            let start = size > 262_144 ? size - 262_144 : 0
            try? h.seek(toOffset: start)
            guard let data = try? h.readToEnd() else { continue }
            var lines = String(decoding: data, as: UTF8.self).split(separator: "\n")
            if start > 0, !lines.isEmpty { lines.removeFirst() }
            for line in lines.reversed() {
                if let r = AIUsageRules.parseCodex(line, now: modified) {
                    return CodexLimits(primary: r.primary, secondary: r.secondary, updatedAt: modified)
                }
            }
        }
        return nil
    }
}
