import AppKit
import SwiftUI
@preconcurrency import IOBluetooth

@MainActor
final class BluetoothMonitor: NSObject {
    var onActivity: ((IslandActivity) -> Void)?

    private var connectNote: IOBluetoothUserNotification?
    private var disconnectNotes: [String: IOBluetoothUserNotification] = [:]
    private var startedAt = Date()
    private var knownAirPods = UserDefaults.standard.dictionary(forKey: "knownAirPodsSymbols") as? [String: String] ?? [:]
    private let profilerQueue = DispatchQueue(label: "dynamicisland.bluetooth")

    private var lastDisconnect: [String: Date] = [:]
    private var lastAnnounce: [String: Date] = [:]
    private var quietUntil = Date.distantPast
    private var wakeObserver: NSObjectProtocol?

    func start() {
        startedAt = Date()
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.quietUntil = Date().addingTimeInterval(45) }
        }
        connectNote = IOBluetoothDevice.register(forConnectNotifications: self, selector: #selector(deviceConnected(_:device:)))
    }

    @objc nonisolated private func deviceConnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleConnect(device) }
        }
    }

    @objc nonisolated private func deviceDisconnected(_ note: IOBluetoothUserNotification, device: IOBluetoothDevice) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.handleDisconnect(device) }
        }
    }

    private var airPods: [String: String] = [:]
    private var batteryTimer: Timer?
    private var warnedAt: [String: Int] = [:]
    var onLowBattery: ((IslandActivity) -> Void)?

    private func handleConnect(_ device: IOBluetoothDevice) {
        let address = Self.normalize(device.addressString ?? "")
        disconnectNotes[address]?.unregister()
        disconnectNotes[address] = device.register(forDisconnectNotification: self, selector: #selector(deviceDisconnected(_:device:)))

        let now = Date()
        let alreadyConnected = airPods[address] != nil
        let briefDrop = lastDisconnect[address].map { now.timeIntervalSince($0) < 60 } ?? false
        let recentlyShown = lastAnnounce[address].map { now.timeIntervalSince($0) < 120 } ?? false
        let announce = now.timeIntervalSince(startedAt) > 3 && now >= quietUntil
            && !alreadyConnected && !briefDrop && !recentlyShown
        let name = device.name ?? "AirPods"
        let kind = DeviceKind(device: device)

        if let symbol = knownAirPods[address] {
            airPodsConnected(address: address, name: name, symbol: symbol, announce: announce)
        } else if name.lowercased().contains("airpods") {
            airPodsConnected(address: address, name: name, symbol: kind.symbol, announce: announce)
        } else if kind.isAudio {
            identify(address: address, attempts: 6) { [weak self] details in
                guard let self, let symbol = details?.productSymbol else { return }
                self.knownAirPods[address] = symbol
                UserDefaults.standard.set(self.knownAirPods, forKey: "knownAirPodsSymbols")
                self.airPodsConnected(address: address, name: name, symbol: symbol, announce: announce, details: details)
            }
        }
    }

    private func airPodsConnected(address: String, name: String, symbol: String, announce: Bool, details: Details? = nil) {
        airPods[address] = name
        warnedAt[address] = nil
        startBatteryWatch()
        guard announce else { return }
        lastAnnounce[address] = Date()
        onActivity?(.init(icon: symbol, tint: .white, title: name, trailing: String(localized: "Bağlandı")))
        let show: (Details?) -> Void = { [weak self] d in
            guard let self, let d, let battery = d.batteryLevel else { return }
            self.onActivity?(.init(icon: d.productSymbol ?? symbol, tint: .white, title: name,
                                   trailing: pc(battery), ring: Double(battery) / 100))
            self.checkBattery(address: address, name: name, level: battery, symbol: d.productSymbol ?? symbol)
        }
        if let details, details.batteryLevel != nil { show(details) } else { fetchDetails(address: address, attempts: 3, completion: show) }
    }

    private func handleDisconnect(_ device: IOBluetoothDevice) {
        let address = Self.normalize(device.addressString ?? "")
        disconnectNotes[address]?.unregister()
        disconnectNotes[address] = nil
        if airPods[address] != nil { lastDisconnect[address] = Date() }
        airPods[address] = nil
        warnedAt[address] = nil
        if airPods.isEmpty {
            batteryTimer?.invalidate()
            batteryTimer = nil
        }
    }

    private func startBatteryWatch() {
        guard batteryTimer == nil else { return }
        batteryTimer = Timer.repeating(every: 300) { [weak self] _ in
            MainActor.assumeIsolated { self?.pollBatteries() }
        }
    }

    private func pollBatteries() {
        for (address, name) in airPods {
            fetchDetails(address: address, attempts: 1) { [weak self] d in
                guard let self, let level = d?.batteryLevel, self.airPods[address] != nil else { return }
                self.checkBattery(address: address, name: name, level: level, symbol: d?.productSymbol ?? "airpods")
            }
        }
    }

    private func checkBattery(address: String, name: String, level: Int, symbol: String) {
        if level > 25 { warnedAt[address] = nil; return }
        let last = warnedAt[address] ?? 101
        for threshold in [10, 20] where level <= threshold && last > threshold {
            warnedAt[address] = threshold
            onLowBattery?(.init(icon: symbol, tint: threshold == 10 ? .red : .orange, title: name,
                                trailing: String(localized: "\(pc(level)) · Pil azaldı"), ring: Double(level) / 100))
            return
        }
    }

    struct Details {
        var batteryLevel: Int?
        var productSymbol: String?
    }

    private func identify(address: String, attempts: Int, completion: @escaping (Details?) -> Void) {
        profilerQueue.asyncAfter(deadline: .now() + 0.3) {
            let details = Self.readProfiler(address: address)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if details?.productSymbol != nil {
                        completion(details)
                    } else if details == nil, attempts > 1 {
                        self.identify(address: address, attempts: attempts - 1, completion: completion)
                    } else {
                        completion(nil)
                    }
                }
            }
        }
    }

    private func fetchDetails(address: String, attempts: Int, completion: @escaping (Details?) -> Void) {
        profilerQueue.asyncAfter(deadline: .now() + 1.5) {
            let details = Self.readProfiler(address: address)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if details?.batteryLevel == nil, attempts > 1 {
                        self.fetchDetails(address: address, attempts: attempts - 1, completion: completion)
                    } else {
                        completion(details)
                    }
                }
            }
        }
    }

    private nonisolated static func readProfiler(address: String) -> Details? {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()

        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first,
              let connected = bt["device_connected"] as? [[String: Any]] else { return nil }

        for entry in connected {
            for (_, value) in entry {
                guard let info = value as? [String: Any],
                      normalize(info["device_address"] as? String ?? "") == address else { continue }
                let level = { (key: String) -> Int? in
                    (info[key] as? String).flatMap { Int($0.filter(\.isNumber)) }
                }
                let buds = [level("device_batteryLevelLeft"), level("device_batteryLevelRight")].compactMap { $0 }
                let battery = buds.min() ?? level("device_batteryLevelMain")
                let pid = (info["device_productID"] as? String).flatMap { Int($0.dropFirst(2), radix: 16) }
                let vid = (info["device_vendorID"] as? String).flatMap { Int($0.dropFirst(2), radix: 16) }
                let isAppleHeadphones = vid == 0x004C && pid.map { $0 & 0xFF00 == 0x2000 && !beatsIDs.contains($0) } == true
                    && (info["device_minorType"] as? String) == "Headphones"
                return Details(batteryLevel: battery,
                               productSymbol: pid.flatMap(appleAudioSymbol) ?? (isAppleHeadphones ? "airpods" : nil))
            }
        }
        return nil
    }

    private nonisolated static let beatsIDs: Set<Int> = [0x2003, 0x2005, 0x2006, 0x2009, 0x200B, 0x200C, 0x200D,
                                                          0x2010, 0x2011, 0x2016, 0x2017, 0x201D, 0x2025, 0x2026]

    private nonisolated static func appleAudioSymbol(_ pid: Int) -> String? {
        switch pid {
        case 0x200E, 0x2014, 0x2024, 0x2027: return "airpodspro"
        case 0x200A, 0x201F: return "airpodsmax"
        case 0x2013, 0x2019, 0x201B: return "airpods.gen3"
        case 0x2002, 0x200F, 0x2012: return "airpods"
        default: return nil
        }
    }

    nonisolated static func normalize(_ address: String) -> String {
        address.uppercased().filter { $0.isHexDigit }
    }
}

private struct DeviceKind {
    let symbol: String
    let isAudio: Bool

    init(device: IOBluetoothDevice) {
        let name = (device.name ?? "").lowercased()
        let major = device.deviceClassMajor
        let minor = device.deviceClassMinor

        if name.contains("airpods max") { symbol = "airpodsmax"; isAudio = true }
        else if name.contains("airpods pro") { symbol = "airpodspro"; isAudio = true }
        else if name.contains("airpods") { symbol = "airpods"; isAudio = true }
        else if name.contains("beats") { symbol = "beats.headphones"; isAudio = true }
        else if major == UInt32(kBluetoothDeviceClassMajorAudio) {
            isAudio = true
            if minor == 0x05 || name.contains("speaker") || name.contains("jbl") || name.contains("homepod") {
                symbol = "hifispeaker.fill"
            } else {
                symbol = "headphones"
            }
        } else if major == UInt32(kBluetoothDeviceClassMajorPeripheral) {
            isAudio = false
            switch minor & 0x30 {
            case 0x10: symbol = "keyboard.fill"
            case 0x20: symbol = "computermouse.fill"
            default: symbol = name.contains("controller") ? "gamecontroller.fill" : "keyboard.fill"
            }
        } else if major == UInt32(kBluetoothDeviceClassMajorPhone) {
            symbol = "iphone"; isAudio = false
        } else {
            symbol = "wave.3.right"; isAudio = false
        }
    }
}
