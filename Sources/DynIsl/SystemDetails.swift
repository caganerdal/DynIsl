import AppKit
import CoreWLAN
import Darwin
import IOKit

struct VolumeInfo: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let name: String
    let total: Double
    let available: Double
    let format: String
    let isInternal: Bool
    let isEjectable: Bool
    var used: Double { max(total - available, 0) }
}

struct InterfaceInfo: Identifiable, Equatable {
    var id: String { name }
    let name: String
    let kind: String
    let ipv4: String?
    let received: UInt64
    let sent: UInt64
}

struct WiFiInfo: Equatable {
    var ssid: String?
    var rssi: Int
    var noise: Int
    var txRate: Double
    var channel: Int?
    var band: String?
    var security: String?
}

struct DisplayInfo: Identifiable, Equatable {
    let id: CGDirectDisplayID
    let name: String
    let points: CGSize
    let pixels: CGSize
    let refreshRate: Int
    let isBuiltIn: Bool
    let isMain: Bool
}

struct BluetoothDeviceInfo: Identifiable, Equatable {
    var id: String { address }
    let name: String
    let address: String
    let kind: String
    let connected: Bool
    let batteries: [(String, Int)]

    static func == (a: Self, b: Self) -> Bool {
        a.address == b.address && a.connected == b.connected && a.batteries.map(\.1) == b.batteries.map(\.1)
    }
}

struct ProcessRow: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let cpu: Double
    let memory: Double
    let icon: NSImage?

    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.cpu == b.cpu && a.memory == b.memory }
}

@MainActor
final class SystemDetails: ObservableObject {
    static let historyLength = 120

    @Published private(set) var modelName = "Mac"
    @Published private(set) var modelID = ""
    @Published private(set) var chip = ""
    @Published private(set) var performanceCores = 0
    @Published private(set) var efficiencyCores = 0
    @Published private(set) var gpuCores: Int?
    let osVersion = ProcessInfo.processInfo.operatingSystemVersionString
    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)

    @Published private(set) var cpuTotal: Double = 0
    @Published private(set) var cpuUser: Double = 0
    @Published private(set) var cpuSystem: Double = 0
    @Published private(set) var cores: [Double] = []
    @Published private(set) var loadAverage: [Double] = [0, 0, 0]
    @Published private(set) var thermal: ProcessInfo.ThermalState = .nominal
    @Published private(set) var cpuHistory: [Double] = []

    @Published private(set) var gpuUsage: Double = 0
    @Published private(set) var gpuMemory: Double = 0
    @Published private(set) var gpuHistory: [Double] = []

    @Published private(set) var memApp: Double = 0
    @Published private(set) var memWired: Double = 0
    @Published private(set) var memCompressed: Double = 0
    @Published private(set) var memCached: Double = 0
    @Published private(set) var swapUsed: Double = 0
    @Published private(set) var swapTotal: Double = 0
    @Published private(set) var pressure = 1
    @Published private(set) var memHistory: [Double] = []
    var memUsed: Double { memApp + memWired + memCompressed }

    @Published private(set) var volumes: [VolumeInfo] = []
    @Published private(set) var diskRead: Double = 0
    @Published private(set) var diskWrite: Double = 0
    @Published private(set) var diskHistory: [(read: Double, write: Double)] = []

    @Published private(set) var interfaces: [InterfaceInfo] = []
    @Published private(set) var netDown: Double = 0
    @Published private(set) var netUp: Double = 0
    @Published private(set) var netHistory: [(down: Double, up: Double)] = []
    @Published private(set) var wifi: WiFiInfo?

    @Published private(set) var displays: [DisplayInfo] = []
    @Published private(set) var bluetooth: [BluetoothDeviceInfo] = []
    @Published private(set) var processes: [ProcessRow] = []
    @Published private(set) var bootDate: Date?

    private var timer: Timer?
    private var slowTimer: Timer?
    private var active = 0
    private var paused = false
    private var hardwareLoaded = false
    private var nameCache: [pid_t: String] = [:]
    private var lastBluetooth = Date.distantPast

    var wantsProcesses = false { didSet { if wantsProcesses && !oldValue { lastProcTimes = [:] } } }
    var wantsBluetooth = false { didSet { if wantsBluetooth && !oldValue { sampleBluetooth() } } }
    private var lastCoreTicks: [[UInt64]] = []
    private var lastDisk: (read: UInt64, write: UInt64, at: Date)?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    private var lastProcTimes: [pid_t: UInt64] = [:]
    private var lastProcSample = Date()
    private var iconCache: [pid_t: NSImage] = [:]
    private let tickToNanos: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    init() {
        performanceCores = Self.sysctlInt("hw.perflevel0.logicalcpu") ?? 0
        efficiencyCores = Self.sysctlInt("hw.perflevel1.logicalcpu") ?? 0
        modelID = Self.sysctlString("hw.model") ?? ""
        chip = Self.sysctlString("machdep.cpu.brand_string") ?? ""
        var tv = timeval()
        var size = MemoryLayout<timeval>.size
        if sysctlbyname("kern.boottime", &tv, &size, nil, 0) == 0 {
            bootDate = Date(timeIntervalSince1970: TimeInterval(tv.tv_sec))
        }
    }

    func begin() {
        active += 1
        guard active == 1 else { return }
        if !hardwareLoaded {
            hardwareLoaded = true
            loadHardwareName()
        }
        startTimers()
    }

    func end() {
        active = max(active - 1, 0)
        guard active == 0 else { return }
        stopTimers()
    }

    func setPaused(_ p: Bool) {
        guard p != paused else { return }
        paused = p
        if p { stopTimers() } else if active > 0 { startTimers() }
    }

    private func startTimers() {
        guard !paused, timer == nil else { return }
        sampleFast()
        sampleSlow()
        timer = Timer.repeating(every: 1, tolerance: 0.1) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleFast() }
        }
        slowTimer = Timer.repeating(every: 10) { [weak self] _ in
            MainActor.assumeIsolated { self?.sampleSlow() }
        }
    }

    private func stopTimers() {
        timer?.invalidate(); timer = nil
        slowTimer?.invalidate(); slowTimer = nil
        lastCoreTicks = []
        lastDisk = nil
        lastNet = nil
        lastProcTimes = [:]
    }

    private func sampleFast() {
        sampleCPU()
        sampleGPU()
        sampleMemory()
        sampleDiskIO()
        sampleNetwork()
        if wantsProcesses { sampleProcesses() }
        thermal = ProcessInfo.processInfo.thermalState
        var la = [Double](repeating: 0, count: 3)
        getloadavg(&la, 3)
        loadAverage = la
    }

    private func sampleSlow() {
        sampleVolumes()
        sampleWiFi()
        sampleDisplays()
        if wantsBluetooth, Date().timeIntervalSince(lastBluetooth) >= 30 { sampleBluetooth() }
    }

    private func push<T>(_ value: T, to history: inout [T]) {
        history.append(value)
        if history.count > Self.historyLength { history.removeFirst(history.count - Self.historyLength) }
    }

    private func sampleCPU() {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var n: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &n, &info, &count) == KERN_SUCCESS,
              let info else { return }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }

        var ticks: [[UInt64]] = []
        for c in 0..<Int(n) {
            ticks.append((0..<Int(CPU_STATE_MAX)).map { UInt64(UInt32(bitPattern: info[c * Int(CPU_STATE_MAX) + $0])) })
        }
        defer { lastCoreTicks = ticks }
        guard lastCoreTicks.count == ticks.count else { return }

        var perCore: [Double] = []
        var tUser = 0.0, tSys = 0.0, tAll = 0.0
        for (now, prev) in zip(ticks, lastCoreTicks) {
            let d = zip(now, prev).map { Double($0 &- $1) }
            let user = d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_NICE)]
            let sys = d[Int(CPU_STATE_SYSTEM)]
            let all = user + sys + d[Int(CPU_STATE_IDLE)]
            perCore.append(all > 0 ? (user + sys) / all : 0)
            tUser += user; tSys += sys; tAll += all
        }
        cores = perCore
        cpuUser = tAll > 0 ? tUser / tAll : 0
        cpuSystem = tAll > 0 ? tSys / tAll : 0
        cpuTotal = cpuUser + cpuSystem
        push(cpuTotal, to: &cpuHistory)
    }

    private func sampleGPU() {
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOAccelerator"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            defer { IOObjectRelease(entry); entry = IOIteratorNext(iter) }
            guard let stats = IORegistryEntryCreateCFProperty(entry, "PerformanceStatistics" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? [String: Any] else { continue }
            gpuUsage = Double((stats["Device Utilization %"] as? NSNumber)?.intValue ?? 0) / 100
            gpuMemory = (stats["In use system memory"] as? NSNumber)?.doubleValue ?? 0
            if gpuCores == nil {
                gpuCores = (IORegistryEntryCreateCFProperty(entry, "gpu-core-count" as CFString, kCFAllocatorDefault, 0)?
                    .takeRetainedValue() as? NSNumber)?.intValue
            }
            push(gpuUsage, to: &gpuHistory)
            return
        }
    }

    private func sampleMemory() {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return }
        let page = Double(vm_kernel_page_size)
        memApp = (Double(stats.internal_page_count) - Double(stats.purgeable_count)) * page
        memWired = Double(stats.wire_count) * page
        memCompressed = Double(stats.compressor_page_count) * page
        memCached = (Double(stats.external_page_count) + Double(stats.purgeable_count)) * page

        var swap = xsw_usage()
        var size = MemoryLayout<xsw_usage>.size
        if sysctlbyname("vm.swapusage", &swap, &size, nil, 0) == 0 {
            swapUsed = Double(swap.xsu_used)
            swapTotal = Double(swap.xsu_total)
        }
        pressure = Self.sysctlInt("kern.memorystatus_vm_pressure_level") ?? 1
        push(memTotalRatio, to: &memHistory)
    }

    var memTotalRatio: Double { memoryTotal > 0 ? memUsed / memoryTotal : 0 }

    private func sampleVolumes() {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityForImportantUsageKey,
                                      .volumeAvailableCapacityKey, .volumeLocalizedFormatDescriptionKey,
                                      .volumeIsInternalKey, .volumeIsEjectableKey, .volumeIsBrowsableKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys, options: [.skipHiddenVolumes]) ?? []
        volumes = urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.volumeIsBrowsable ?? true,
                  let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let avail = v.volumeAvailableCapacityForImportantUsage.map(Double.init)
                ?? v.volumeAvailableCapacity.map(Double.init) ?? 0
            return VolumeInfo(url: url, name: v.volumeName ?? url.lastPathComponent, total: Double(total),
                              available: avail, format: v.volumeLocalizedFormatDescription ?? "",
                              isInternal: v.volumeIsInternal ?? false, isEjectable: v.volumeIsEjectable ?? false)
        }
    }

    func eject(_ v: VolumeInfo) {
        try? NSWorkspace.shared.unmountAndEjectDevice(at: v.url)
        sampleVolumes()
    }

    private func sampleDiskIO() {
        var read: UInt64 = 0, write: UInt64 = 0
        var iter: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching("IOBlockStorageDriver"), &iter) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iter) }
        var entry = IOIteratorNext(iter)
        while entry != 0 {
            if let stats = IORegistryEntryCreateCFProperty(entry, "Statistics" as CFString, kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                read += (stats["Bytes (Read)"] as? NSNumber)?.uint64Value ?? 0
                write += (stats["Bytes (Write)"] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
            entry = IOIteratorNext(iter)
        }
        let now = Date()
        if let l = lastDisk, read >= l.read, write >= l.write {
            let dt = now.timeIntervalSince(l.at)
            if dt > 0 {
                diskRead = Double(read - l.read) / dt
                diskWrite = Double(write - l.write) / dt
            }
        }
        lastDisk = (read, write, now)
        push((diskRead, diskWrite), to: &diskHistory)
    }

    private func sampleNetwork() {
        var list: [String: (kind: String, ip: String?, rx: UInt64, tx: UInt64)] = [:]
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        let wifiName = CWWiFiClient.shared().interface()?.interfaceName
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            defer { p = cur.pointee.ifa_next }
            let name = String(cString: cur.pointee.ifa_name)
            guard name.hasPrefix("en") || name.hasPrefix("bridge") || name.hasPrefix("utun") else { continue }
            var e = list[name] ?? (name == wifiName ? "Wi-Fi" : name.hasPrefix("utun") ? "VPN" : name.hasPrefix("bridge") ? "Köprü" : "Ethernet", nil, 0, 0)
            guard let addr = cur.pointee.ifa_addr else { continue }
            if addr.pointee.sa_family == UInt8(AF_LINK), let data = cur.pointee.ifa_data {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                e.rx = UInt64(d.ifi_ibytes); e.tx = UInt64(d.ifi_obytes)
            } else if addr.pointee.sa_family == UInt8(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len), &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST) == 0 {
                    e.ip = String(cString: host)
                }
            }
            list[name] = e
        }
        interfaces = list.filter { $0.value.ip != nil }
            .map { InterfaceInfo(name: $0.key, kind: $0.value.kind, ipv4: $0.value.ip, received: $0.value.rx, sent: $0.value.tx) }
            .sorted { ($0.kind == "Wi-Fi" ? 0 : 1, $0.name) < ($1.kind == "Wi-Fi" ? 0 : 1, $1.name) }

        let down = list.filter { $0.key.hasPrefix("en") }.values.reduce(0) { $0 + $1.rx }
        let up = list.filter { $0.key.hasPrefix("en") }.values.reduce(0) { $0 + $1.tx }
        let now = Date()
        if let l = lastNet, down >= l.down, up >= l.up {
            let dt = now.timeIntervalSince(l.at)
            if dt > 0 {
                netDown = Double(down - l.down) / dt
                netUp = Double(up - l.up) / dt
            }
        }
        lastNet = (down, up, now)
        push((netDown, netUp), to: &netHistory)
    }

    private func sampleWiFi() {
        guard let i = CWWiFiClient.shared().interface(), i.powerOn() else { wifi = nil; return }
        let ch = i.wlanChannel()
        let band: String? = switch ch?.channelBand {
        case .band2GHz: "2,4 GHz"
        case .band5GHz: "5 GHz"
        case .band6GHz: "6 GHz"
        default: nil
        }
        let security: String? = switch i.security() {
        case .wpa2Personal, .wpa2Enterprise: "WPA2"
        case .wpa3Personal, .wpa3Enterprise, .wpa3Transition: "WPA3"
        case .none: "Açık"
        case .unknown: nil
        default: "WPA"
        }
        wifi = WiFiInfo(ssid: i.ssid(), rssi: i.rssiValue(), noise: i.noiseMeasurement(),
                        txRate: i.transmitRate(), channel: ch?.channelNumber, band: band, security: security)
    }

    private func sampleDisplays() {
        displays = NSScreen.screens.compactMap { s in
            guard let id = s.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else { return nil }
            let mode = CGDisplayCopyDisplayMode(id)
            return DisplayInfo(
                id: id, name: s.localizedName, points: s.frame.size,
                pixels: CGSize(width: mode?.pixelWidth ?? 0, height: mode?.pixelHeight ?? 0),
                refreshRate: s.maximumFramesPerSecond, isBuiltIn: CGDisplayIsBuiltin(id) != 0,
                isMain: s == NSScreen.screens.first
            )
        }
    }

    private func sampleBluetooth() {
        lastBluetooth = Date()
        DispatchQueue.global(qos: .utility).async {
            let devices = Self.readBluetooth()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { if self.bluetooth != devices { self.bluetooth = devices } }
            }
        }
    }

    private nonisolated static func readBluetooth() -> [BluetoothDeviceInfo] {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        p.arguments = ["-json", "SPBluetoothDataType"]
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return [] }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        guard let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let bt = (root["SPBluetoothDataType"] as? [[String: Any]])?.first else { return [] }
        var out: [BluetoothDeviceInfo] = []
        for (section, connected) in [("device_connected", true), ("device_not_connected", false)] {
            for entry in bt[section] as? [[String: Any]] ?? [] {
                for (name, value) in entry {
                    guard let info = value as? [String: Any] else { continue }
                    let lvl = { (k: String) in (info[k] as? String).flatMap { Int($0.filter(\.isNumber)) } }
                    let batteries = [("Sol", lvl("device_batteryLevelLeft")), ("Sağ", lvl("device_batteryLevelRight")),
                                     ("Kutu", lvl("device_batteryLevelCase")), ("Pil", lvl("device_batteryLevelMain"))]
                        .compactMap { k, v in v.map { (k, $0) } }
                    out.append(BluetoothDeviceInfo(name: name, address: info["device_address"] as? String ?? name,
                                                   kind: info["device_minorType"] as? String ?? "",
                                                   connected: connected, batteries: batteries))
                }
            }
        }
        return out
    }

    private func sampleProcesses() {
        let now = Date()
        let dt = now.timeIntervalSince(lastProcSample)
        lastProcSample = now
        let size = proc_listallpids(nil, 0)
        guard size > 0 else { return }
        var pids = [pid_t](repeating: 0, count: Int(size) + 32)
        let n = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return }

        var times: [pid_t: UInt64] = [:]
        var rows: [(pid: pid_t, cpu: Double, mem: Double)] = []
        for pid in pids.prefix(Int(n)) where pid > 0 {
            var info = proc_taskinfo()
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
                    == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }
            let total = info.pti_total_user + info.pti_total_system
            times[pid] = total
            let cpu = lastProcTimes[pid].map { total >= $0 && dt > 0 ? Double(total - $0) * tickToNanos / 1e9 / dt * 100 : 0 } ?? 0
            rows.append((pid, cpu, Double(info.pti_resident_size)))
        }
        lastProcTimes = times

        let byCPU = rows.sorted { $0.cpu > $1.cpu }.prefix(12)
        let byMem = rows.sorted { $0.mem > $1.mem }.prefix(12)
        var seen = Set<pid_t>()
        processes = (byCPU + byMem).filter { seen.insert($0.pid).inserted }.map { r in
            if nameCache[r.pid] == nil {
                let app = NSRunningApplication(processIdentifier: r.pid)
                nameCache[r.pid] = app?.localizedName ?? Self.procName(r.pid)
                if let icon = app?.icon { iconCache[r.pid] = icon }
            }
            return ProcessRow(id: r.pid, name: nameCache[r.pid] ?? "", cpu: r.cpu, memory: r.mem, icon: iconCache[r.pid])
        }
        if nameCache.count > 400 {
            nameCache = nameCache.filter { times[$0.key] != nil }
            iconCache = iconCache.filter { times[$0.key] != nil }
        }
    }

    private static func procName(_ pid: pid_t) -> String {
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, UInt32(buf.count))
        let n = String(cString: buf)
        return n.isEmpty ? "pid \(pid)" : n
    }

    private func loadHardwareName() {
        DispatchQueue.global(qos: .utility).async {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
            p.arguments = ["-json", "SPHardwareDataType"]
            let pipe = Pipe()
            p.standardOutput = pipe
            p.standardError = FileHandle.nullDevice
            guard (try? p.run()) != nil else { return }
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            let hw = ((try? JSONSerialization.jsonObject(with: data) as? [String: Any])?["SPHardwareDataType"] as? [[String: Any]])?.first
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    if let n = hw?["machine_name"] as? String { self.modelName = n }
                    if let c = hw?["chip_type"] as? String { self.chip = c }
                }
            }
        }
    }

    private static func sysctlInt(_ name: String) -> Int? {
        var v: Int64 = 0
        var size = MemoryLayout<Int64>.size
        guard sysctlbyname(name, &v, &size, nil, 0) == 0 else { return nil }
        return size == 4 ? Int(Int32(truncatingIfNeeded: v)) : Int(v)
    }

    private static func sysctlString(_ name: String) -> String? {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return nil }
        var buf = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buf, &size, nil, 0) == 0 else { return nil }
        return String(cString: buf)
    }
}
