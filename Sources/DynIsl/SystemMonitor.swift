import AppKit
import Combine
import Darwin

struct ProcessUsage: Identifiable, Equatable {
    let id: pid_t
    let name: String
    let cpu: Double
}

@MainActor
final class SystemMonitor: ObservableObject {
    @Published private(set) var cpu: Double = 0
    @Published private(set) var memoryUsed: Double = 0
    @Published private(set) var downBytesPerSec: Double = 0
    @Published private(set) var upBytesPerSec: Double = 0
    @Published private(set) var topProcesses: [ProcessUsage] = []

    let memoryTotal = Double(ProcessInfo.processInfo.physicalMemory)
    var memory: Double { memoryTotal > 0 ? memoryUsed / memoryTotal : 0 }

    var onActivity: ((IslandActivity) -> Void)?
    var alertsEnabled = true

    var isVisible = false { didSet { if isVisible != oldValue { reschedule() } } }
    var menuBarActive = false { didSet { if menuBarActive != oldValue { reschedule() } } }

    private var timer: Timer?
    private var lastTicks: [UInt64]?
    private var lastNet: (down: UInt64, up: UInt64, at: Date)?
    private var lastProcTimes: [pid_t: UInt64] = [:]
    private var lastProcSample = Date()
    private var hotSince: [pid_t: Date] = [:]
    private var alerted: Set<pid_t> = []
    private let ownPID = getpid()
    private let tickToNanos: Double = {
        var tb = mach_timebase_info_data_t()
        mach_timebase_info(&tb)
        return Double(tb.numer) / Double(tb.denom)
    }()

    func start() {
        sample()
        reschedule()
    }

    private func reschedule() {
        timer?.invalidate()
        timer = Timer.repeating(every: isVisible ? 2 : (menuBarActive ? 3 : 10)) { [weak self] _ in
            MainActor.assumeIsolated { self?.sample() }
        }
        if isVisible { sample() }
    }

    let didSample = PassthroughSubject<Void, Never>()
    private var lastProcessScan = Date.distantPast

    private func sample() {
        cpu = Self.cpuUsage(last: &lastTicks) ?? cpu
        memoryUsed = Self.memoryUsed()
        if isVisible {
            sampleNetwork()
        } else {
            lastNet = nil
        }
        if isVisible || (alertsEnabled && Date().timeIntervalSince(lastProcessScan) >= 15) {
            lastProcessScan = Date()
            sampleProcesses()
        }
        didSample.send()
    }

    private static func cpuUsage(last: inout [UInt64]?) -> Double? {
        var count: mach_msg_type_number_t = 0
        var info: processor_info_array_t?
        var cpuCount: natural_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &cpuCount, &info, &count) == KERN_SUCCESS,
              let info else { return nil }
        defer { vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info), vm_size_t(Int(count) * MemoryLayout<integer_t>.stride)) }

        var totals = [UInt64](repeating: 0, count: 4)
        for c in 0..<Int(cpuCount) {
            for s in 0..<4 {
                totals[s] += UInt64(UInt32(bitPattern: info[c * Int(CPU_STATE_MAX) + s]))
            }
        }
        defer { last = totals }
        guard let prev = last else { return nil }
        let d = zip(totals, prev).map { $0 &- $1 }
        let busy = Double(d[Int(CPU_STATE_USER)] + d[Int(CPU_STATE_SYSTEM)] + d[Int(CPU_STATE_NICE)])
        let all = busy + Double(d[Int(CPU_STATE_IDLE)])
        return all > 0 ? busy / all : nil
    }

    private static func memoryUsed() -> Double {
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let r = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard r == KERN_SUCCESS else { return 0 }
        let page = Double(vm_kernel_page_size)
        let app = Double(stats.internal_page_count) - Double(stats.purgeable_count)
        return (app + Double(stats.wire_count) + Double(stats.compressor_page_count)) * page
    }

    private func sampleNetwork() {
        var down: UInt64 = 0, up: UInt64 = 0
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return }
        defer { freeifaddrs(ifaddr) }
        var p: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = p {
            let name = String(cString: cur.pointee.ifa_name)
            if name.hasPrefix("en"), let data = cur.pointee.ifa_data,
               cur.pointee.ifa_addr?.pointee.sa_family == UInt8(AF_LINK) {
                let d = data.assumingMemoryBound(to: if_data.self).pointee
                down += UInt64(d.ifi_ibytes)
                up += UInt64(d.ifi_obytes)
            }
            p = cur.pointee.ifa_next
        }
        let now = Date()
        if let last = lastNet {
            let dt = now.timeIntervalSince(last.at)
            if dt > 0, down >= last.down, up >= last.up {
                downBytesPerSec = Double(down - last.down) / dt
                upBytesPerSec = Double(up - last.up) / dt
            }
        }
        lastNet = (down, up, now)
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
        var usages: [ProcessUsage] = []
        for pid in pids.prefix(Int(n)) where pid > 0 {
            var info = proc_taskinfo()
            let r = proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &info, Int32(MemoryLayout<proc_taskinfo>.size))
            guard r == Int32(MemoryLayout<proc_taskinfo>.size) else { continue }
            let total = info.pti_total_user + info.pti_total_system
            times[pid] = total
            if let prev = lastProcTimes[pid], total >= prev, dt > 0 {
                let pct = Double(total - prev) * tickToNanos / 1e9 / dt * 100
                if pct >= 1 { usages.append(ProcessUsage(id: pid, name: "", cpu: pct)) }
            }
        }
        lastProcTimes = times

        let top = usages.sorted { $0.cpu > $1.cpu }.prefix(4).map {
            ProcessUsage(id: $0.id, name: Self.name(of: $0.id), cpu: $0.cpu)
        }
        topProcesses = top
        checkHotProcesses(usages)
    }

    private func checkHotProcesses(_ usages: [ProcessUsage]) {
        let hot = Set(usages.filter { $0.cpu >= 90 && $0.id != ownPID }.map(\.id))
        hotSince = hotSince.filter { hot.contains($0.key) }
        alerted = alerted.filter { hot.contains($0) }
        for pid in hot where hotSince[pid] == nil { hotSince[pid] = Date() }
        guard alertsEnabled else { return }
        for (pid, since) in hotSince where Date().timeIntervalSince(since) >= 60 && !alerted.contains(pid) {
            alerted.insert(pid)
            let pct = usages.first { $0.id == pid }?.cpu ?? 90
            onActivity?(.init(icon: "flame.fill", tint: .orange, title: Self.name(of: pid), trailing: "%\(Int(pct)) CPU"))
        }
    }

    private static func name(of pid: pid_t) -> String {
        if let app = NSRunningApplication(processIdentifier: pid), let n = app.localizedName { return n }
        var buf = [CChar](repeating: 0, count: 256)
        proc_name(pid, &buf, UInt32(buf.count))
        let n = String(cString: buf)
        return n.isEmpty ? "pid \(pid)" : n
    }

    nonisolated static func formatBytes(_ b: Double, perSecond: Bool = false) -> String {
        let units = ["B", "KB", "MB", "GB", "TB"]
        var v = b, i = 0
        while v >= 1000, i < units.count - 1 { v /= 1000; i += 1 }
        let s = v < 10 && i > 0 ? String(format: "%.1f", v) : String(format: "%.0f", v)
        return s + " " + units[i] + (perSecond ? "/s" : "")
    }
}
