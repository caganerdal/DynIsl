import Foundation
import SwiftUI

struct SystemIssue: Identifiable, Equatable {
    enum Kind: String { case disk, memory, thermal, batteryHealth }
    var id: Kind { kind }
    let kind: Kind
    let icon: String
    let tint: Color
    let title: String
    let detail: String
}

@MainActor
final class SystemAlerts: ObservableObject {
    @Published private(set) var issues: [SystemIssue] = []

    var onActivity: ((IslandActivity) -> Void)?

    var diskEnabled = true
    var memoryEnabled = true
    var thermalEnabled = true
    var batteryHealthEnabled = true

    private var lastShown: [SystemIssue.Kind: Date] = [:]
    private let cooldown: [SystemIssue.Kind: TimeInterval] = [
        .disk: 6 * 3600, .memory: 30 * 60, .thermal: 20 * 60, .batteryHealth: 7 * 24 * 3600,
    ]
    private var memorySource: DispatchSourceMemoryPressure?
    private var diskTimer: Timer?
    private var memoryLevel: DispatchSource.MemoryPressureEvent = .normal

    func start(batteryHealth: @escaping () -> Int?) {
        let src = DispatchSource.makeMemoryPressureSource(eventMask: [.normal, .warning, .critical], queue: .main)
        src.setEventHandler { [weak self, weak src] in
            guard let event = src?.data else { return }
            MainActor.assumeIsolated { self?.memoryChanged(event) }
        }
        src.resume()
        memorySource = src

        NotificationCenter.default.addObserver(forName: ProcessInfo.thermalStateDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkThermal() }
        }

        checkDisk()
        checkThermal()
        diskTimer = Timer.repeating(every: 600) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkDisk() }
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
            MainActor.assumeIsolated { self?.checkBatteryHealth(batteryHealth()) }
        }
    }

    private func checkDisk() {
        guard let v = try? URL(fileURLWithPath: "/").resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey, .volumeTotalCapacityKey,
        ]), let total = v.volumeTotalCapacity, total > 0 else { return }
        let free = Double(v.volumeAvailableCapacityForImportantUsage ?? 0)
        let freeGB = free / 1e9
        let ratio = free / Double(total)
        if ratio < 0.10 || freeGB < 15 {
            raise(SystemIssue(kind: .disk, icon: "internaldrive.fill", tint: freeGB < 5 ? .red : .orange,
                              title: String(localized: "Disk dolmak üzere"), detail: String(localized: "\(Int(freeGB)) GB boş")),
                  enabled: diskEnabled)
        } else {
            clear(.disk)
        }
    }

    private func memoryChanged(_ event: DispatchSource.MemoryPressureEvent) {
        memoryLevel = event
        if event.contains(.critical) {
            raise(SystemIssue(kind: .memory, icon: "memorychip.fill", tint: .red,
                              title: String(localized: "Bellek baskısı kritik"), detail: String(localized: "Uygulama kapat")), enabled: memoryEnabled)
        } else if event.contains(.warning) {
            raise(SystemIssue(kind: .memory, icon: "memorychip.fill", tint: .orange,
                              title: String(localized: "Bellek azalıyor"), detail: String(localized: "Baskı yüksek")), enabled: memoryEnabled)
        } else {
            clear(.memory)
        }
    }

    private func checkThermal() {
        switch ProcessInfo.processInfo.thermalState {
        case .serious:
            raise(SystemIssue(kind: .thermal, icon: "thermometer.high", tint: .orange,
                              title: String(localized: "Mac ısınıyor"), detail: String(localized: "Performans düşebilir")), enabled: thermalEnabled)
        case .critical:
            raise(SystemIssue(kind: .thermal, icon: "thermometer.high", tint: .red,
                              title: String(localized: "Mac çok sıcak"), detail: String(localized: "Yükü azalt")), enabled: thermalEnabled)
        default:
            clear(.thermal)
        }
    }

    func checkBatteryHealth(_ percent: Int?) {
        guard let p = percent else { return }
        if p < 80 {
            raise(SystemIssue(kind: .batteryHealth, icon: "battery.25percent", tint: .orange,
                              title: String(localized: "Pil sağlığı \(pc(p))"), detail: String(localized: "Servis önerilir")), enabled: batteryHealthEnabled)
        } else {
            clear(.batteryHealth)
        }
    }

    private func raise(_ issue: SystemIssue, enabled: Bool) {
        if let i = issues.firstIndex(where: { $0.kind == issue.kind }) {
            if issues[i] != issue { issues[i] = issue }
        } else {
            issues.append(issue)
        }
        guard enabled else { return }
        let now = Date()
        if let last = lastShown[issue.kind], now.timeIntervalSince(last) < (cooldown[issue.kind] ?? 3600) { return }
        lastShown[issue.kind] = now
        onActivity?(.init(icon: issue.icon, tint: issue.tint, title: issue.title, trailing: issue.detail))
    }

    private func clear(_ kind: SystemIssue.Kind) {
        if issues.contains(where: { $0.kind == kind }) { issues.removeAll { $0.kind == kind } }
    }
}
