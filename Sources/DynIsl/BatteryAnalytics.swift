import Foundation
import IOKit

struct BatterySample: Codable, Equatable {
    var date: Date
    var level: Int
    var charging: Bool
    var watts: Double
}

@MainActor
final class BatteryAnalytics: ObservableObject {
    @Published private(set) var level = 0
    @Published private(set) var isCharging = false
    @Published private(set) var externalPower = false
    @Published private(set) var fullyCharged = false
    @Published private(set) var watts: Double = 0
    @Published private(set) var voltage: Double = 0
    @Published private(set) var minutesToEmpty: Int?
    @Published private(set) var minutesToFull: Int?
    @Published private(set) var cycleCount = 0
    @Published private(set) var designCycles = 1000
    @Published private(set) var adapterName: String?
    @Published private(set) var adapterWatts: Int?
    @Published private(set) var designCapacity = 0
    @Published private(set) var fullCapacity = 0

    @Published private(set) var healthPercent: Int?
    @Published private(set) var condition: String?

    @Published private(set) var history: [BatterySample] = []

    var isVisible = false { didSet { if isVisible != oldValue { reschedule() } } }

    private var liveTimer: Timer?
    private var sampleTimer: Timer?
    private var healthTimer: Timer?
    private let storeURL: URL = {
        let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynamicIsland", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir.appendingPathComponent("battery-history.json")
    }()

    func start() {
        loadHistory()
        readLive()
        record()
        refreshHealth()
        reschedule()
        sampleTimer = Timer.repeating(every: 300) { [weak self] _ in
            MainActor.assumeIsolated { self?.readLive(); self?.record() }
        }
        healthTimer = Timer.repeating(every: 6 * 3600) { [weak self] _ in
            MainActor.assumeIsolated { self?.refreshHealth() }
        }
    }

    func powerSourceChanged() {
        readLive()
        record()
    }

    private func reschedule() {
        liveTimer?.invalidate()
        liveTimer = nil
        guard isVisible else { return }
        readLive()
        liveTimer = Timer.repeating(every: 3) { [weak self] _ in
            MainActor.assumeIsolated { self?.readLive() }
        }
    }

    private func readLive() {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("AppleSmartBattery"))
        guard service != 0 else { return }
        defer { IOObjectRelease(service) }
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(service, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let d = props?.takeRetainedValue() as? [String: Any] else { return }

        func int(_ k: String) -> Int? { (d[k] as? NSNumber)?.intValue }
        level = int("CurrentCapacity") ?? level
        isCharging = d["IsCharging"] as? Bool ?? false
        externalPower = d["ExternalConnected"] as? Bool ?? false
        fullyCharged = d["FullyCharged"] as? Bool ?? false
        let mV = Double(int("Voltage") ?? 0)
        let mA = Double((d["Amperage"] as? NSNumber)?.int64Value ?? 0)
        voltage = mV / 1000
        watts = abs(mV * mA) / 1_000_000
        cycleCount = int("CycleCount") ?? cycleCount
        designCycles = int("DesignCycleCount9C") ?? designCycles
        let toEmpty = int("AvgTimeToEmpty") ?? 65535
        let toFull = int("AvgTimeToFull") ?? 65535
        minutesToEmpty = (!externalPower && toEmpty < 65535 && toEmpty > 0) ? toEmpty : nil
        minutesToFull = (isCharging && toFull < 65535 && toFull > 0) ? toFull : nil

        if let ad = d["AdapterDetails"] as? [String: Any], externalPower {
            adapterWatts = (ad["Watts"] as? NSNumber)?.intValue
            adapterName = (ad["Name"] as? String)?.trimmingCharacters(in: .whitespaces)
        } else {
            adapterWatts = nil
            adapterName = nil
        }
        if let bd = d["BatteryData"] as? [String: Any] {
            designCapacity = (bd["DesignCapacity"] as? NSNumber)?.intValue ?? designCapacity
            fullCapacity = (bd["NominalChargeCapacity"] as? NSNumber)?.intValue ?? fullCapacity
        }
    }

    private func refreshHealth() {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["-json", "SPPowerDataType"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let items = (try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["SPPowerDataType"] as? [[String: Any]] ?? []
            let health = items.compactMap { $0["sppower_battery_health_info"] as? [String: Any] }.first
            let pct = (health?["sppower_battery_health_maximum_capacity"] as? String).flatMap { Int($0.filter(\.isNumber)) }
            let cond = health?["sppower_battery_health"] as? String
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.healthPercent = pct
                    self.condition = cond.map(Self.translateCondition)
                }
            }
        }
    }

    private nonisolated static func translateCondition(_ c: String) -> String {
        switch c.lowercased() {
        case "good", "normal": return "Normal"
        case "fair": return "İyi değil"
        case "poor", "service recommended", "check battery": return "Servis önerilir"
        default: return c
        }
    }

    private func record() {
        guard level > 0 else { return }
        let s = BatterySample(date: Date(), level: level, charging: isCharging || externalPower, watts: watts)
        if let last = history.last, s.date.timeIntervalSince(last.date) < 60 { history.removeLast() }
        history.append(s)
        let cutoff = Date().addingTimeInterval(-48 * 3600)
        history.removeAll { $0.date < cutoff }
        saveHistory()
    }

    private func loadHistory() {
        guard let data = try? Data(contentsOf: storeURL),
              let h = try? JSONDecoder().decode([BatterySample].self, from: data) else { return }
        history = h
    }

    private func saveHistory() {
        if let data = try? JSONEncoder().encode(history) { try? data.write(to: storeURL, options: .atomic) }
    }

    var last24h: [BatterySample] {
        let cutoff = Date().addingTimeInterval(-24 * 3600)
        return history.filter { $0.date >= cutoff }
    }

    var drainPerHour: Double? {
        var drop = 0.0, hours = 0.0
        for (a, b) in zip(last24h, last24h.dropFirst()) where !a.charging && !b.charging {
            let dt = b.date.timeIntervalSince(a.date) / 3600
            guard dt > 0, dt < 0.5, b.level <= a.level else { continue }
            drop += Double(a.level - b.level)
            hours += dt
        }
        return hours >= 0.25 ? drop / hours : nil
    }

    var onBatteryToday: TimeInterval {
        let start = Calendar.current.startOfDay(for: Date())
        let today = history.filter { $0.date >= start }
        var t: TimeInterval = 0
        for (a, b) in zip(today, today.dropFirst()) where !a.charging {
            let dt = b.date.timeIntervalSince(a.date)
            if dt < 1800 { t += dt }
        }
        return t
    }

    var unpluggedSince: Date? {
        guard !externalPower, let lastCharging = history.lastIndex(where: \.charging) else { return nil }
        return history.indices.contains(lastCharging + 1) ? history[lastCharging + 1].date : nil
    }

    var wearFromDesign: Int? {
        guard designCapacity > 0, fullCapacity > 0 else { return nil }
        return Int((Double(fullCapacity) / Double(designCapacity) * 100).rounded())
    }
}

func formatMinutes(_ m: Int) -> String {
    m < 60 ? "\(m) dk" : "\(m / 60) sa \(m % 60) dk"
}
