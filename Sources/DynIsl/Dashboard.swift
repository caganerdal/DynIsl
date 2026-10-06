import AppKit
import Charts
import SwiftUI

@MainActor
enum DashboardWindow {
    private static var window: NSWindow?
    private static var delegate: CloseDelegate?
    private static var occlusionObserver: Any?

    static func show(model: IslandModel, page: DashboardPage? = nil) {
        if let page { model.dashboardPage = page }
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 1020, height: 680),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = String(localized: "Sistem Paneli")
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.minSize = NSSize(width: 820, height: 560)
            w.isReleasedWhenClosed = false
            w.setFrameAutosaveName("SistemPaneli")
            w.contentView = NSHostingView(rootView: DashboardView()
                .environmentObject(model)
                .environmentObject(model.details)
                .environmentObject(model.batteryInfo)
                .environmentObject(model.speedTest)
                .environmentObject(model.alerts)
                .environmentObject(model.desktopCleaner)
                .environmentObject(model.downloadsCleaner))
            let d = CloseDelegate {
                model.details.end()
                NSApp.setActivationPolicy(.accessory)
                model.desktopCleaner.purge()
                model.downloadsCleaner.purge()
                release()
            }
            w.delegate = d
            delegate = d
            occlusionObserver = NotificationCenter.default.addObserver(
                forName: NSWindow.didChangeOcclusionStateNotification, object: w, queue: .main
            ) { [weak w] _ in
                guard let w else { return }
                MainActor.assumeIsolated { model.details.setPaused(!w.occlusionState.contains(.visible)) }
            }
            if !w.setFrameUsingName("SistemPaneli") { w.center() }
            window = w
        }
        if window?.isVisible == false { model.details.begin() }
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func release() {
        if let o = occlusionObserver { NotificationCenter.default.removeObserver(o) }
        occlusionObserver = nil
        let w = window
        window = nil
        delegate = nil
        DispatchQueue.main.async {
            w?.delegate = nil
            w?.contentView = nil
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { malloc_zone_pressure_relief(nil, 0) }
        }
    }

    private final class CloseDelegate: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

enum DashboardPage: String, CaseIterable, Identifiable {
    case overview, cpu, gpu, memory, storage, network, battery, displays, bluetooth, processes, desktop, downloads, convert
    var id: String { rawValue }

    var title: String {
        switch self {
        case .overview: return String(localized: "Genel Bakış")
        case .cpu: return String(localized: "İşlemci")
        case .gpu: return String(localized: "Grafik")
        case .memory: return String(localized: "Bellek")
        case .storage: return String(localized: "Depolama")
        case .network: return String(localized: "Ağ")
        case .battery: return String(localized: "Pil")
        case .displays: return String(localized: "Ekranlar")
        case .bluetooth: return "Bluetooth"
        case .processes: return String(localized: "İşlemler")
        case .desktop: return String(localized: "Masaüstü Düzenleme")
        case .downloads: return String(localized: "İndirilenler Temizliği")
        case .convert: return String(localized: "Dosya Dönüştürme")
        }
    }

    var icon: String {
        switch self {
        case .overview: return "square.grid.2x2.fill"
        case .cpu: return "cpu.fill"
        case .gpu: return "cube.transparent.fill"
        case .memory: return "memorychip.fill"
        case .storage: return "internaldrive.fill"
        case .network: return "network"
        case .battery: return "battery.75percent"
        case .displays: return "display"
        case .bluetooth: return "dot.radiowaves.left.and.right"
        case .processes: return "list.bullet.rectangle.fill"
        case .desktop: return "wand.and.stars"
        case .downloads: return "arrow.down.circle.fill"
        case .convert: return "arrow.triangle.2.circlepath"
        }
    }

    var tint: Color {
        switch self {
        case .overview: return .gray
        case .cpu: return .blue
        case .gpu: return .purple
        case .memory: return .orange
        case .storage: return .teal
        case .network: return .cyan
        case .battery: return .green
        case .displays: return .indigo
        case .bluetooth: return .blue
        case .processes: return .pink
        case .desktop: return .mint
        case .downloads: return .orange
        case .convert: return .indigo
        }
    }
}

struct DashboardView: View {
    @EnvironmentObject var model: IslandModel
    @State private var pageQuery = ""

    var body: some View {
        NavigationSplitView {
            List(selection: $model.dashboardPage) {
                if pageQuery.isEmpty {
                    Section("Donanım") {
                        ForEach([DashboardPage.overview, .cpu, .gpu, .memory, .storage]) { row($0) }
                    }
                    Section("Bağlantı ve güç") {
                        ForEach([DashboardPage.network, .battery, .displays, .bluetooth]) { row($0) }
                    }
                    Section("Yazılım") {
                        row(.processes)
                        row(.desktop)
                        row(.downloads)
                        row(.convert)
                    }
                } else {
                    let hits = DashboardPage.allCases.filter { $0.title.localizedStandardContains(pageQuery) }
                    if hits.isEmpty { Text("Sonuç yok").foregroundStyle(.secondary) }
                    ForEach(hits) { row($0) }
                }
            }
            .searchable(text: $pageQuery, placement: .sidebar, prompt: Text("Sayfa ara"))
            .navigationSplitViewColumnWidth(min: 190, ideal: 210)
        } detail: {
            let p = model.dashboardPage ?? .overview
            Group {
                switch p {
                case .desktop: DesktopPage()
                case .downloads: DownloadsPage()
                case .convert: ConvertPage()
                case .processes: ProcessesPage()
                default: PageScroll { page(p) }
                }
            }
            .navigationTitle(p.title)
        }
    }

    private func row(_ p: DashboardPage) -> some View {
        Label {
            Text(p.title)
        } icon: {
            Image(systemName: p.icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(p.tint.gradient))
        }
        .tag(p)
    }

    @ViewBuilder private func page(_ p: DashboardPage) -> some View {
        switch p {
        case .overview: OverviewPage()
        case .cpu: CPUPage()
        case .gpu: GPUPage()
        case .memory: MemoryPage()
        case .storage: StoragePage()
        case .network: NetworkPage()
        case .battery: BatteryPage()
        case .displays: DisplaysPage()
        case .bluetooth: BluetoothPage()
        case .processes: ProcessesPage()
        case .desktop: DesktopPage()
        case .downloads: DownloadsPage()
        case .convert: ConvertPage()
        }
    }
}

private let GiB = 1_073_741_824.0

private func gb(_ bytes: Double, digits: Int = 1) -> String {
    String(format: "%.\(digits)f GB", bytes / GiB)
}

private func pct(_ v: Double) -> String { pc(Int((v * 100).rounded())) }

private struct Card<Content: View>: View {
    var title: LocalizedStringKey?
    var icon: String?
    var tint: Color = .accentColor
    @ViewBuilder var content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let title {
                Label {
                    Text(title).font(.headline)
                } icon: {
                    if let icon { Image(systemName: icon).foregroundStyle(tint) }
                }
            }
            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14, style: .continuous).fill(.background.secondary))
        .overlay(RoundedRectangle(cornerRadius: 14, style: .continuous).stroke(.separator.opacity(0.5)))
    }
}

private struct Stat: View {
    let label: LocalizedStringKey
    let value: String
    var tint: Color = .primary

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.system(.title3, design: .rounded).weight(.semibold).monospacedDigit()).foregroundStyle(tint)
        }
    }
}

private struct KeyValue: View {
    let key: LocalizedStringKey
    let value: String

    var body: some View {
        HStack {
            Text(key).foregroundStyle(.secondary)
            Spacer()
            Text(value).monospacedDigit().textSelection(.enabled)
        }
        .font(.callout)
    }
}

private struct HistoryChart: View {
    let values: [Double]
    let tint: Color
    var maxY: Double? = 1
    var format: (Double) -> String = { pct($0) }
    var height: CGFloat = 140

    var body: some View {
        let offset = SystemDetails.historyLength - values.count
        Chart(Array(values.enumerated()), id: \.offset) { j, v in
            let i = j + offset
            AreaMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(LinearGradient(colors: [tint.opacity(0.45), tint.opacity(0.03)], startPoint: .top, endPoint: .bottom))
                .interpolationMethod(.monotone)
            LineMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(tint)
                .interpolationMethod(.monotone)
        }
        .chartXScale(domain: 0...(SystemDetails.historyLength - 1))
        .chartXAxis(.hidden)
        .chartYScale(domain: 0...(maxY ?? max(values.max() ?? 1, 1)))
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.separator)
                AxisValueLabel { Text(format(v.as(Double.self) ?? 0)).font(.caption2) }
            }
        }
        .frame(height: height)
        .animation(.linear(duration: 0.3), value: values.count)
    }
}

private struct DualChart: View {
    let a: [Double]
    let b: [Double]
    let aName: String
    let bName: String
    let aTint: Color
    let bTint: Color

    var body: some View {
        let offset = SystemDetails.historyLength - a.count
        Chart {
            ForEach(Array(a.enumerated()), id: \.offset) { j, v in
                LineMark(x: .value("t", j + offset), y: .value("v", v), series: .value("s", aName))
                    .foregroundStyle(aTint).interpolationMethod(.monotone)
            }
            ForEach(Array(b.enumerated()), id: \.offset) { j, v in
                LineMark(x: .value("t", j + offset), y: .value("v", v), series: .value("s", bName))
                    .foregroundStyle(bTint).interpolationMethod(.monotone)
            }
        }
        .chartXScale(domain: 0...(SystemDetails.historyLength - 1))
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(position: .trailing, values: .automatic(desiredCount: 3)) { v in
                AxisGridLine().foregroundStyle(.separator)
                AxisValueLabel { Text(SystemMonitor.formatBytes(v.as(Double.self) ?? 0, perSecond: true)).font(.caption2) }
            }
        }
        .frame(height: 150)
    }
}

private struct Sparkline: View {
    let values: [Double]
    let tint: Color

    var body: some View {
        Chart(Array(values.suffix(60).enumerated()), id: \.offset) { i, v in
            AreaMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(tint.opacity(0.25)).interpolationMethod(.monotone)
            LineMark(x: .value("t", i), y: .value("v", v))
                .foregroundStyle(tint).interpolationMethod(.monotone)
        }
        .chartXAxis(.hidden).chartYAxis(.hidden)
        .chartYScale(domain: 0...max(values.max() ?? 1, 1))
        .frame(height: 36)
    }
}

private struct UsageBar: View {
    let value: Double
    let tint: Color

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.quaternary)
                Capsule().fill(tint.gradient).frame(width: g.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: 8)
        .animation(.easeOut(duration: 0.4), value: value)
    }
}

private struct OverviewPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails
    @EnvironmentObject var battery: BatteryAnalytics

    var body: some View {
        let d = details
        let b = battery
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 16) {
                Image(nsImage: NSImage(named: NSImage.computerName) ?? NSApp.applicationIconImage)
                    .resizable().frame(width: 64, height: 64)
                VStack(alignment: .leading, spacing: 3) {
                    Text(d.modelName).font(.title.weight(.semibold))
                    Text(String(localized: "\(d.chip) · \(d.performanceCores + d.efficiencyCores) çekirdekli CPU\(d.gpuCores.map { String(localized: " · \($0) çekirdekli GPU") } ?? "") · \(Int(d.memoryTotal / GiB)) GB bellek"))
                        .foregroundStyle(.secondary)
                    Text(String(localized: "macOS \(d.osVersion)\(d.bootDate.map { String(localized: " · \(uptime(since: $0)) açık") } ?? "")"))
                        .font(.callout).foregroundStyle(.secondary)
                }
            }

            IssuesBanner()

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 220), spacing: 14)], spacing: 14) {
                tile(.cpu, value: pct(d.cpuTotal), detail: String(localized: "Yük \(String(format: "%.2f", d.loadAverage.first ?? 0))"), history: d.cpuHistory)
                tile(.gpu, value: pct(d.gpuUsage), detail: gb(d.gpuMemory, digits: 2) + String(localized: " bellek"), history: d.gpuHistory)
                tile(.memory, value: gb(d.memUsed), detail: String(localized: "\(Int(d.memoryTotal / GiB)) GB'ın \(pct(d.memTotalRatio))'i"), history: d.memHistory)
                if let v = d.volumes.first(where: \.isInternal) ?? d.volumes.first {
                    tile(.storage, value: String(localized: "\(Int(v.available / 1e9)) GB boş"), detail: "\(v.name) · \(Int(v.total / 1e9)) GB", history: nil)
                }
                tile(.network, value: "↓ " + SystemMonitor.formatBytes(d.netDown, perSecond: true),
                     detail: "↑ " + SystemMonitor.formatBytes(d.netUp, perSecond: true), history: d.netHistory.map(\.down))
                if b.level > 0 {
                    tile(.battery, value: pc(b.level), detail: [b.healthPercent.map { String(localized: "Sağlık \(pc($0))") }, String(localized: "\(b.cycleCount) döngü")].compactMap { $0 }.joined(separator: " · "), history: nil)
                }
            }
        }
    }

    private func tile(_ p: DashboardPage, value: String, detail: String, history: [Double]?) -> some View {
        Button { model.dashboardPage = p } label: {
            Card(title: "\(p.title)", icon: p.icon, tint: p.tint) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(value).font(.system(size: 26, weight: .semibold, design: .rounded).monospacedDigit())
                    Text(detail).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    if let history, history.count > 1 { Sparkline(values: history, tint: p.tint) } else { Spacer().frame(height: 36) }
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private func uptime(since d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    let days = s / 86400, hours = (s % 86400) / 3600, mins = (s % 3600) / 60
    if days > 0 { return String(localized: "\(days) gün \(hours) sa") }
    return hours > 0 ? String(localized: "\(hours) sa \(mins) dk") : String(localized: "\(mins) dk")
}

private struct CPUPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let d = details
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Kullanım", icon: "cpu.fill", tint: .blue) {
                HStack(spacing: 32) {
                    Stat(label: "Toplam", value: pct(d.cpuTotal), tint: .blue)
                    Stat(label: "Kullanıcı", value: pct(d.cpuUser))
                    Stat(label: "Sistem", value: pct(d.cpuSystem))
                    Stat(label: "Yük (1 · 5 · 15 dk)", value: d.loadAverage.map { String(format: "%.2f", $0) }.joined(separator: " · "))
                    Stat(label: "Isı durumu", value: thermalText(d.thermal), tint: thermalTint(d.thermal))
                }
                HistoryChart(values: d.cpuHistory, tint: .blue)
            }
            Card(title: "Çekirdekler", icon: "square.grid.3x3.fill", tint: .blue) {
                if d.efficiencyCores > 0 {
                    coreGroup(String(localized: "Verimlilik çekirdekleri"), Array(d.cores.prefix(d.efficiencyCores)), tint: .teal, prefix: "E")
                }
                coreGroup(d.efficiencyCores > 0 ? String(localized: "Performans çekirdekleri") : String(localized: "Çekirdekler"),
                          Array(d.cores.dropFirst(d.efficiencyCores)), tint: .blue, prefix: "P")
            }
            Card(title: "Bilgi", icon: "info.circle.fill", tint: .gray) {
                KeyValue(key: "İşlemci", value: d.chip)
                KeyValue(key: "Çekirdekler", value: String(localized: "\(d.performanceCores) performans + \(d.efficiencyCores) verimlilik"))
                KeyValue(key: "Model kimliği", value: d.modelID)
                if let boot = d.bootDate { KeyValue(key: "Açık kalma süresi", value: uptime(since: boot)) }
            }
        }
    }

    private func coreGroup(_ title: String, _ loads: [Double], tint: Color, prefix: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            HStack(alignment: .bottom, spacing: 10) {
                ForEach(Array(loads.enumerated()), id: \.offset) { i, v in
                    VStack(spacing: 4) {
                        ZStack(alignment: .bottom) {
                            RoundedRectangle(cornerRadius: 5).fill(.quaternary)
                            RoundedRectangle(cornerRadius: 5).fill(tint.gradient).frame(height: 70 * min(max(v, 0.02), 1))
                        }
                        .frame(width: 34, height: 70)
                        Text(pct(v)).font(.caption2.monospacedDigit())
                        Text("\(prefix)\(i + 1)").font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
            .animation(.easeOut(duration: 0.4), value: loads)
        }
    }

    private func thermalText(_ t: ProcessInfo.ThermalState) -> String {
        switch t {
        case .nominal: return String(localized: "Normal")
        case .fair: return String(localized: "Ilık")
        case .serious: return String(localized: "Sıcak")
        case .critical: return String(localized: "Kritik")
        @unknown default: return "—"
        }
    }

    private func thermalTint(_ t: ProcessInfo.ThermalState) -> Color {
        switch t {
        case .nominal: return .green
        case .fair: return .yellow
        case .serious: return .orange
        default: return .red
        }
    }
}

private struct GPUPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let d = details
        Card(title: "Grafik işlemcisi", icon: "cube.transparent.fill", tint: .purple) {
            HStack(spacing: 32) {
                Stat(label: "Kullanım", value: pct(d.gpuUsage), tint: .purple)
                Stat(label: "Kullanılan bellek", value: gb(d.gpuMemory, digits: 2))
                if let c = d.gpuCores { Stat(label: "Çekirdek", value: "\(c)") }
                Stat(label: "Yonga", value: d.chip)
            }
            HistoryChart(values: d.gpuHistory, tint: .purple)
            Text("Apple Silicon'da GPU belleği sistem belleğiyle paylaşılır (birleşik bellek).")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct MemoryPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let d = details
        let parts: [(String, Double, Color)] = [
            (String(localized: "Uygulama"), d.memApp, .orange), (String(localized: "Kablolu"), d.memWired, .red),
            (String(localized: "Sıkıştırılmış"), d.memCompressed, .yellow), (String(localized: "Önbellek"), d.memCached, .gray),
        ]
        let free = max(d.memoryTotal - parts.reduce(0) { $0 + $1.1 }, 0)
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Bellek", icon: "memorychip.fill", tint: .orange) {
                HStack(spacing: 32) {
                    Stat(label: "Kullanılan", value: gb(d.memUsed), tint: .orange)
                    Stat(label: "Toplam", value: "\(Int(d.memoryTotal / GiB)) GB")
                    Stat(label: "Bellek baskısı", value: pressureText(d.pressure), tint: pressureTint(d.pressure))
                    Stat(label: "Swap", value: "\(gb(d.swapUsed, digits: 2)) / \(gb(d.swapTotal, digits: 0))")
                }
                GeometryReader { g in
                    HStack(spacing: 2) {
                        ForEach(parts, id: \.0) { name, v, c in
                            Rectangle().fill(c.gradient).frame(width: max(g.size.width * v / d.memoryTotal - 2, 0))
                        }
                        Rectangle().fill(.quaternary)
                    }
                    .clipShape(Capsule())
                }
                .frame(height: 14)
                HStack(spacing: 16) {
                    ForEach(parts, id: \.0) { name, v, c in legend(name, gb(v), c) }
                    legend(String(localized: "Boş"), gb(free), Color.primary.opacity(0.18))
                }
                HistoryChart(values: d.memHistory, tint: .orange)
            }
            Card(title: "Terimler", icon: "questionmark.circle", tint: .gray) {
                Text("**Uygulama:** açık uygulamaların kullandığı bellek. **Kablolu:** sistemin boşaltamadığı bellek. **Sıkıştırılmış:** yer açmak için sıkıştırılan bellek. **Önbellek:** gerektiğinde hemen boşaltılabilen dosya önbelleği — dolu olması sorun değildir. Önemli olan **bellek baskısı**dır.")
                    .font(.callout).foregroundStyle(.secondary)
            }
        }
    }

    private func legend(_ name: String, _ value: String, _ c: Color) -> some View {
        HStack(spacing: 5) {
            Circle().fill(c).frame(width: 8, height: 8)
            Text(name).foregroundStyle(.secondary)
            Text(value).monospacedDigit()
        }
        .font(.caption)
    }

    private func pressureText(_ p: Int) -> String { p >= 4 ? String(localized: "Kritik") : p >= 2 ? String(localized: "Uyarı") : String(localized: "Normal") }
    private func pressureTint(_ p: Int) -> Color { p >= 4 ? .red : p >= 2 ? .yellow : .green }
}

private struct StoragePage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let d = details
        VStack(alignment: .leading, spacing: 16) {
            ForEach(d.volumes) { v in
                Card(title: "\(v.name)", icon: v.isInternal ? "internaldrive.fill" : "externaldrive.fill", tint: .teal) {
                    HStack(spacing: 32) {
                        Stat(label: "Boş", value: "\(Int(v.available / 1e9)) GB", tint: .teal)
                        Stat(label: "Kullanılan", value: "\(Int(v.used / 1e9)) GB")
                        Stat(label: "Kapasite", value: "\(Int(v.total / 1e9)) GB")
                        Spacer()
                        if v.isEjectable {
                            Button("Çıkar", systemImage: "eject.fill") { d.eject(v) }
                        }
                    }
                    UsageBar(value: v.used / v.total, tint: v.available / v.total < 0.1 ? .red : .teal)
                    Text([v.format, v.isInternal ? String(localized: "Dahili") : String(localized: "Harici")].filter { !$0.isEmpty }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Card(title: "Okuma / yazma", icon: "arrow.up.arrow.down", tint: .teal) {
                HStack(spacing: 32) {
                    Stat(label: "Okuma", value: SystemMonitor.formatBytes(d.diskRead, perSecond: true), tint: .teal)
                    Stat(label: "Yazma", value: SystemMonitor.formatBytes(d.diskWrite, perSecond: true), tint: .pink)
                }
                DualChart(a: d.diskHistory.map(\.read), b: d.diskHistory.map(\.write),
                          aName: String(localized: "Okuma"), bName: String(localized: "Yazma"), aTint: .teal, bTint: .pink)
            }
        }
    }
}

private struct NetworkPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let d = details
        VStack(alignment: .leading, spacing: 16) {
            SpeedTestCard()
            Card(title: "Trafik", icon: "arrow.up.arrow.down.circle.fill", tint: .cyan) {
                HStack(spacing: 32) {
                    Stat(label: "İndirme", value: SystemMonitor.formatBytes(d.netDown, perSecond: true), tint: .cyan)
                    Stat(label: "Yükleme", value: SystemMonitor.formatBytes(d.netUp, perSecond: true), tint: .purple)
                }
                DualChart(a: d.netHistory.map(\.down), b: d.netHistory.map(\.up),
                          aName: String(localized: "İndirme"), bName: String(localized: "Yükleme"), aTint: .cyan, bTint: .purple)
            }
            if let w = d.wifi {
                Card(title: "Wi-Fi", icon: "wifi", tint: .blue) {
                    HStack(spacing: 32) {
                        Stat(label: "Ağ", value: w.ssid ?? "—")
                        Stat(label: "Sinyal", value: "\(w.rssi) dBm", tint: signalTint(w.rssi))
                        Stat(label: "Bağlantı hızı", value: "\(Int(w.txRate)) Mbps")
                        if let ch = w.channel { Stat(label: "Kanal", value: "\(ch)\(w.band.map { " · \($0)" } ?? "")") }
                    }
                    UsageBar(value: signalQuality(w.rssi), tint: signalTint(w.rssi))
                    KeyValue(key: "Sinyal kalitesi", value: signalText(w.rssi))
                    KeyValue(key: "Gürültü", value: "\(w.noise) dBm · SNR \(w.rssi - w.noise) dB")
                    if let s = w.security { KeyValue(key: "Güvenlik", value: s) }
                    if w.ssid == nil {
                        HStack {
                            Text("Ağ adını görmek için macOS konum izni gerekiyor.").font(.caption).foregroundStyle(.secondary)
                            Button("Konum ayarları") { model.weather.openLocationSettings() }.controlSize(.small)
                        }
                    }
                }
            }
            Card(title: "Arayüzler", icon: "point.3.connected.trianglepath.dotted", tint: .gray) {
                ForEach(d.interfaces) { i in
                    HStack {
                        Text("\(i.kind) (\(i.name))").frame(width: 160, alignment: .leading)
                        Text(i.ipv4 ?? "—").monospacedDigit().textSelection(.enabled)
                        Spacer()
                        Text("↓ \(SystemMonitor.formatBytes(Double(i.received)))  ↑ \(SystemMonitor.formatBytes(Double(i.sent)))")
                            .foregroundStyle(.secondary).monospacedDigit()
                    }
                    .font(.callout)
                }
                Text("Toplamlar bilgisayar açıldığından beri").font(.caption).foregroundStyle(.tertiary)
            }
        }
    }

    private func signalQuality(_ rssi: Int) -> Double { min(max(Double(rssi + 90) / 60, 0), 1) }
    private func signalText(_ rssi: Int) -> String {
        rssi >= -55 ? String(localized: "Mükemmel") : rssi >= -67 ? String(localized: "İyi") : rssi >= -75 ? String(localized: "Orta") : String(localized: "Zayıf")
    }
    private func signalTint(_ rssi: Int) -> Color { rssi >= -67 ? .green : rssi >= -75 ? .yellow : .red }
}

private struct DesktopPage: View {
    @EnvironmentObject var cleaner: DesktopCleaner
    @State private var age = 0
    @State private var excluded: Set<DesktopCategory> = []
    @State private var focus: DesktopCategory?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(age) * 86400)
        let candidates = cleaner.files.filter { age == 0 || $0.date < cutoff }
        let selected = candidates.filter { !excluded.contains($0.category) }
        let byCategory = Dictionary(grouping: candidates, by: \.category)
        let shown = focus.map { c in candidates.filter { $0.category == c } } ?? candidates

        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = cleaner.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg)
                    Spacer()
                    if !cleaner.lastMoves.isEmpty { Button("Geri al") { cleaner.undo() } }
                    Button("Masaüstünü aç") { NSWorkspace.shared.open(cleaner.desktop) }
                    Button { cleaner.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.12)))
            }

            Card(title: "Masaüstü", icon: "wand.and.stars", tint: .mint) {
                if candidates.isEmpty {
                    Text(cleaner.scanning ? "Taranıyor…" : "Masaüstünde düzenlenecek dosya yok ✨")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(DesktopCategory.allCases.filter { byCategory[$0] != nil }) { c in
                            let list = byCategory[c] ?? []
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { !excluded.contains(c) },
                                    set: { on in if on { excluded.remove(c) } else { excluded.insert(c) } }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                Image(systemName: c.icon).foregroundStyle(.mint).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.folder).font(.callout.weight(.medium))
                                    Text("\(list.count) dosya · \(ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(focus == c ? Color.mint.opacity(0.18) : Color.primary.opacity(0.04)))
                            .contentShape(Rectangle())
                            .onTapGesture { focus = focus == c ? nil : c }
                            .opacity(excluded.contains(c) ? 0.5 : 1)
                        }
                    }

                    Divider()
                    HStack {
                        Text(focus.map { "\($0.folder) (\(shown.count))" } ?? "Tüm dosyalar (\(shown.count))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if focus != nil { Button("Tümünü göster") { focus = nil }.buttonStyle(.borderless) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(shown.prefix(60)) { f in DesktopTile(file: f) }
                    }
                    if shown.count > 60 {
                        Text("+\(shown.count - 60) dosya daha").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Her tür masaüstündeki kendi klasörüne, onun içinde ay klasörüne gider (ör. Masaüstü › PDF'ler › 2026-09 Eylül). Klasörlere, proje klasörlerine, kısayollara ve tanınmayan dosya türlerine dokunulmaz. Hiçbir dosya silinmez; son düzenleme geri alınabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(selected.count) dosya seçildi").font(.callout.weight(.medium))
                    Text("Toplam \(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.size }, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Divider().frame(height: 22)
                Picker("", selection: $age) {
                    Text("Tümü").tag(0)
                    Text("1 haftadan eski").tag(7)
                    Text("1 aydan eski").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 16)
                Button { cleaner.organize(selected) } label: {
                    Label("Düzenle", systemImage: "wand.and.stars").padding(.horizontal, 4)
                }
                .glassButton(prominent: true)
                .tint(.mint)
                .controlSize(.large)
                .disabled(selected.isEmpty)
            }
            .floatingGlassBar()
            .animation(.easeOut(duration: 0.15), value: selected.count)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { NSWorkspace.shared.open(cleaner.desktop) } label: { Label("Masaüstünü aç", systemImage: "folder") }
                    .help("Masaüstünü aç")
                Button { cleaner.scan() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .help("Yeniden tara")
            }
        }
        .onAppear { cleaner.scan() }
    }
}

private struct DesktopTile: View {
    @EnvironmentObject var cleaner: DesktopCleaner
    let file: DesktopFile
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
                if let img = cleaner.thumbnails[file.url] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(file.category == .screenshots || file.category == .images ? 0 : 10)
                } else {
                    Image(systemName: file.category.icon).font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(hover ? 0.4 : 0), lineWidth: 2))
            Text(file.name).font(.caption).lineLimit(1).truncationMode(.middle)
            Text("\(file.category.folder) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { cleaner.open(file) }
        .contextMenu {
            Button("Aç") { cleaner.open(file) }
            Button("Finder'da göster") { cleaner.reveal(file) }
            Divider()
            Button("Sadece bunu düzenle") { cleaner.organize([file]) }
        }
        .help("Çift tıkla aç · sağ tıkla seçenekler")
    }
}

private struct DownloadsPage: View {
    @EnvironmentObject var cleaner: DownloadsCleaner
    @State private var age = 90
    @State private var kinds: Set<DownloadKind> = Set(DownloadKind.allCases.filter(\.selectedByDefault))
    @State private var unchecked: Set<URL> = []
    @State private var confirm = false

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(age) * 86400)
        let candidates = cleaner.items.filter { $0.lastUsed < cutoff }
        let byKind = Dictionary(grouping: candidates, by: \.kind)
        let shown = candidates.filter { kinds.contains($0.kind) }
        let selected = shown.filter { !unchecked.contains($0.url) }
        let selectedSize = selected.reduce(0) { $0 + $1.size }

        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = cleaner.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg)
                    Spacer()
                    if !cleaner.lastTrashed.isEmpty { Button("Geri al") { cleaner.undo() } }
                    Button { cleaner.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.12)))
            }

            Card(title: "İndirilenler", icon: "arrow.down.circle.fill", tint: .orange) {
                Stat(label: "Klasörün tamamı", value: ByteCountFormatter.string(fromByteCount: cleaner.totalSize, countStyle: .file))

                if candidates.isEmpty {
                    Text(cleaner.scanning ? "Taranıyor…" : "Bu süredir açılmamış öğe yok ✨")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(DownloadKind.allCases.filter { byKind[$0] != nil }) { k in
                            let list = byKind[k] ?? []
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { kinds.contains(k) },
                                    set: { on in if on { kinds.insert(k) } else { kinds.remove(k) } }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                Image(systemName: k.icon).foregroundStyle(.orange).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.title).font(.callout.weight(.medium))
                                    Text("\(list.count) öğe · \(ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                            .opacity(kinds.contains(k) ? 1 : 0.5)
                        }
                    }

                    if !shown.isEmpty {
                        Divider()
                        VStack(spacing: 0) {
                            ForEach(shown.prefix(150)) { item in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { !unchecked.contains(item.url) },
                                        set: { on in if on { unchecked.remove(item.url) } else { unchecked.insert(item.url) } }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable().frame(width: 20, height: 20)
                                    Text(item.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 12)
                                    Text(item.opened ? "Son açılış \(item.lastUsed.formatted(.relative(presentation: .named)))"
                                                     : "Hiç açılmadı · \(item.lastUsed.formatted(.relative(presentation: .named))) indirildi")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 230, alignment: .trailing)
                                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                        .font(.callout.monospacedDigit())
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.vertical, 5)
                                .opacity(unchecked.contains(item.url) ? 0.5 : 1)
                                .contentShape(Rectangle())
                                .contextMenu { Button("Finder'da göster") { cleaner.reveal(item) } }
                                .onTapGesture(count: 2) { cleaner.reveal(item) }
                            }
                        }
                        if shown.count > 150 {
                            Text("+\(shown.count - 150) öğe daha").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Seçtiğin süredir açılmamış dosya ve klasörler en büyükten küçüğe listelenir. Varsayılan olarak sadece kurulum dosyaları ve arşivler seçilidir. Hiçbir şey kalıcı olarak silinmez: öğeler Çöp Sepeti'ne gider ve son işlem geri alınabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "\(selected.count) öğe seçildi")).font(.callout.weight(.medium))
                    Text("Açılacak yer \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Divider().frame(height: 22)
                Picker("", selection: $age) {
                    Text("1 ay").tag(30)
                    Text("3 ay").tag(90)
                    Text("6 ay").tag(180)
                    Text("1 yıl").tag(365)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Bu süredir açılmamış öğeler listelenir")
                Spacer(minLength: 16)
                Button(role: .destructive) { confirm = true } label: {
                    Label("Çöp Sepeti'ne taşı", systemImage: "trash.fill").padding(.horizontal, 4)
                }
                .glassButton(prominent: true)
                .tint(.orange)
                .controlSize(.large)
                .disabled(selected.isEmpty)
            }
            .floatingGlassBar()
            .animation(.easeOut(duration: 0.15), value: selectedSize)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { cleaner.openFolder() } label: { Label("İndirilenler'i aç", systemImage: "folder") }
                    .help("İndirilenler'i aç")
                Button { cleaner.scan() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .help("Yeniden tara")
            }
        }
        .onAppear { cleaner.scan() }
        .alert("\(selected.count) öğe Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button("Taşı", role: .destructive) {
                cleaner.moveToTrash(selected)
                unchecked.removeAll()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)) yer açılacak. Çöp Sepeti boşaltılana kadar geri alabilirsin.")
        }
    }
}

private struct ConvertPage: View {
    @State private var files: [URL] = []
    @State private var targeted = false
    @State private var busy: ShelfConversion?
    @State private var outputs: [URL] = []
    @State private var message: String?

    var body: some View {
        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Dosyalar", icon: "arrow.triangle.2.circlepath", tint: .indigo) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.indigo.opacity(targeted ? 0.16 : 0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: files.isEmpty ? [6, 5] : []))
                            .foregroundStyle(Color.indigo.opacity(targeted ? 0.9 : 0.35)))
                    if files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 28)).foregroundStyle(.indigo)
                            Text("Görsel ya da PDF dosyalarını buraya sürükle").font(.callout.weight(.medium))
                            Button("Dosya seç…") { pick() }
                        }
                        .padding(28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(files, id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(fileSize(url)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    Button { files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                            HStack {
                                Button("Dosya ekle…") { pick() }
                                Spacer()
                                Button("Listeyi temizle") { files.removeAll(); outputs.removeAll(); message = nil }
                            }
                            .padding(.top, 8)
                        }
                        .padding(12)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    add(urls)
                    return true
                } isTargeted: { targeted = $0 }
            }

            if let message {
                Card(title: "Sonuç", icon: "checkmark.circle.fill", tint: .green) {
                    Text(message)
                    ForEach(outputs, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(fileSize(url)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                }
            }

            Text("Yeni dosyalar asıl dosyaların yanına kaydedilir; asıl dosyalara dokunulmaz. Küçültme görsellerin en uzun kenarını 1600 piksele indirir. Her şey bilgisayarda yapılır, hiçbir dosya internete yüklenmez.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 8) {
                ForEach(ShelfConversion.allCases) { c in
                    let count = c.inputs(from: files).count
                    Button { run(c) } label: {
                        Label(count > 0 ? "\(c.title) (\(count))" : c.title, systemImage: c.icon)
                    }
                    .glassButton(prominent: count > 0)
                    .tint(.indigo)
                    .disabled(count == 0 || busy != nil)
                }
                Spacer(minLength: 8)
                if busy != nil { ProgressView().controlSize(.small).padding(.trailing, 8) }
            }
            .floatingGlassBar()
        }
        .toolbar {
            ToolbarItem {
                Button { pick() } label: { Label("Dosya seç…", systemImage: "plus") }
                    .help("Dosya seç…")
            }
        }
    }

    private func add(_ urls: [URL]) {
        for u in urls where u.isFileURL && !files.contains(u)
            && (ShelfConverter.isImage(u) || ShelfConverter.isPDF(u)) { files.append(u) }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func run(_ kind: ShelfConversion) {
        let inputs = kind.inputs(from: files)
        guard !inputs.isEmpty else { return }
        busy = kind
        DispatchQueue.global(qos: .userInitiated).async {
            let r = ShelfConverter.run(kind, on: inputs)
            DispatchQueue.main.async {
                busy = nil
                outputs = r.outputs
                let saved = ByteCountFormatter.string(fromByteCount: r.saved, countStyle: .file)
                var parts = [String(localized: "\(kind.title): \(r.outputs.count) dosya hazır")]
                if r.saved > 0 { parts.append(String(localized: "\(saved) yer kazanıldı")) }
                if r.skipped > 0 { parts.append(String(localized: "\(r.skipped) dosya zaten küçük")) }
                if r.failed > 0 { parts.append(String(localized: "\(r.failed) dosya dönüştürülemedi")) }
                message = parts.joined(separator: " · ")
            }
        }
    }

    private func fileSize(_ url: URL) -> String {
        ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0), countStyle: .file)
    }
}

private struct SpeedTestCard: View {
    @EnvironmentObject var test: SpeedTest

    var body: some View {
        Card(title: "İnternet hız testi", icon: "gauge.with.needle.fill", tint: .cyan) {
            HStack(alignment: .center, spacing: 32) {
                if let r = test.last {
                    Stat(label: "İndirme", value: String(format: "%.0f Mbps", r.downMbps), tint: .cyan)
                    Stat(label: "Yükleme", value: String(format: "%.0f Mbps", r.upMbps), tint: .purple)
                    Stat(label: "Gecikme", value: String(format: "%.0f ms", r.ping))
                    Stat(label: "Tepkisellik", value: r.responsivenessText)
                } else if !test.isRunning {
                    Text("Henüz test yapılmadı").foregroundStyle(.secondary)
                }
                Spacer()
                if test.isRunning {
                    TimelineView(.periodic(from: .now, by: 1)) { ctx in
                        let s = Int(ctx.date.timeIntervalSince(test.startedAt ?? ctx.date))
                        HStack(spacing: 8) {
                            ProgressView().controlSize(.small)
                            Text("Ölçülüyor… \(s) sn").foregroundStyle(.secondary).monospacedDigit()
                        }
                    }
                    Button("Durdur") { test.cancel() }
                } else {
                    Button { test.start() } label: { Label("Testi başlat", systemImage: "play.fill") }
                        .glassButton(prominent: true)
                }
            }
            if let e = test.error { Text(e).font(.caption).foregroundStyle(.orange) }
            if let r = test.last {
                Text("\(r.date.formatted(date: .abbreviated, time: .shortened)) · \(r.interface ?? "") · Apple sunucuları")
                    .font(.caption).foregroundStyle(.tertiary)
            }
            if test.history.count > 1 {
                Divider()
                Text("Geçmiş").font(.subheadline).foregroundStyle(.secondary)
                Chart(test.history.reversed()) { r in
                    LineMark(x: .value("Tarih", r.date), y: .value("Mbps", r.downMbps), series: .value("s", String(localized: "İndirme")))
                        .foregroundStyle(.cyan).symbol(.circle)
                    LineMark(x: .value("Tarih", r.date), y: .value("Mbps", r.upMbps), series: .value("s", String(localized: "Yükleme")))
                        .foregroundStyle(.purple).symbol(.circle)
                }
                .chartYAxisLabel("Mbps")
                .frame(height: 120)
                ForEach(test.history.prefix(5)) { r in
                    HStack {
                        Text(r.date.formatted(date: .abbreviated, time: .shortened)).foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "↓ %.0f  ↑ %.0f Mbps  ·  %.0f ms", r.downMbps, r.upMbps, r.ping)).monospacedDigit()
                    }
                    .font(.callout)
                }
            }
            Text("Test ~20 sn sürer ve bu sürede bağlantını yoğun kullanır.").font(.caption).foregroundStyle(.tertiary)
        }
    }
}

private struct IssuesBanner: View {
    @EnvironmentObject var alerts: SystemAlerts

    var body: some View {
        if !alerts.issues.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(alerts.issues) { i in
                    HStack(spacing: 10) {
                        Image(systemName: i.icon).foregroundStyle(i.tint).frame(width: 20)
                        Text(i.title).fontWeight(.semibold)
                        Text(i.detail).foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(14)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Color.orange.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(Color.orange.opacity(0.35)))
        }
    }
}

private struct BatteryPage: View {
    @EnvironmentObject var battery: BatteryAnalytics

    var body: some View {
        let b = battery
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Durum", icon: "battery.100percent.bolt", tint: .green) {
                HStack(spacing: 32) {
                    Stat(label: "Şarj", value: pc(b.level), tint: .green)
                    if b.isCharging {
                        Stat(label: "Şarj gücü", value: String(format: "%.1f W", b.watts))
                    } else if b.externalPower {
                        Stat(label: "Güç", value: String(localized: "Adaptörden"))
                    } else {
                        Stat(label: "Güç çekişi", value: String(format: "%.1f W", b.watts))
                    }
                    Stat(label: "Voltaj", value: String(format: "%.2f V", b.voltage))
                    if let m = b.minutesToFull { Stat(label: "Dolmasına", value: formatMinutes(m)) }
                    if let m = b.minutesToEmpty { Stat(label: "Kalan süre", value: formatMinutes(m)) }
                }
                if let name = b.adapterName {
                    KeyValue(key: "Adaptör", value: "\(name)\(b.adapterWatts.map { " · \($0) W" } ?? "")")
                }
            }
            Card(title: "Sağlık", icon: "heart.fill", tint: .pink) {
                HStack(spacing: 32) {
                    Stat(label: "Maksimum kapasite", value: b.healthPercent.map { pc($0) } ?? "—", tint: .pink)
                    Stat(label: "Durum", value: b.condition ?? "—")
                    Stat(label: "Döngü", value: "\(b.cycleCount) / \(b.designCycles)")
                }
                UsageBar(value: Double(b.cycleCount) / Double(max(b.designCycles, 1)), tint: .blue)
                if b.designCapacity > 0 {
                    KeyValue(key: "Tasarım kapasitesi", value: "\(b.designCapacity) mAh")
                    KeyValue(key: "Şu anki tam kapasite", value: "\(b.fullCapacity) mAh")
                }
                Text("Apple, pil 1000 döngüye ya da %80 kapasiteye ulaşana kadar normal kabul eder.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Card(title: "Son 48 saat", icon: "chart.xyaxis.line", tint: .green) {
                if b.history.count >= 2 {
                    Chart(b.history, id: \.date) { s in
                        AreaMark(x: .value("Saat", s.date), y: .value("Seviye", s.level))
                            .foregroundStyle(LinearGradient(colors: [.green.opacity(0.4), .green.opacity(0.02)], startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Saat", s.date), y: .value("Seviye", s.level))
                            .foregroundStyle(.green).interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .frame(height: 170)
                } else {
                    Text("Veri toplanıyor — ilk birkaç saatten sonra grafik dolacak.").foregroundStyle(.secondary)
                }
                HStack(spacing: 24) {
                    if let dr = b.drainPerHour { KeyValue(key: "Pilde ortalama tüketim", value: String(localized: "\(pc(Int(dr.rounded()))) / saat")) }
                    if b.onBatteryToday > 60 { KeyValue(key: "Bugün pilde", value: formatMinutes(Int(b.onBatteryToday / 60))) }
                }
            }
        }
        .onAppear { b.isVisible = true }
        .onDisappear { b.isVisible = false }
    }
}

private struct DisplaysPage: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(details.displays) { s in
                Card(title: "\(s.name)", icon: s.isBuiltIn ? "laptopcomputer" : "display", tint: .indigo) {
                    HStack(spacing: 32) {
                        Stat(label: "Çözünürlük", value: "\(Int(s.pixels.width)) × \(Int(s.pixels.height))", tint: .indigo)
                        Stat(label: "Görünen boyut", value: "\(Int(s.points.width)) × \(Int(s.points.height))")
                        Stat(label: "Yenileme hızı", value: "\(s.refreshRate) Hz")
                    }
                    Text([s.isBuiltIn ? String(localized: "Dahili ekran") : String(localized: "Harici ekran"), s.isMain ? String(localized: "Ana ekran (menü çubuğu)") : nil]
                        .compactMap { $0 }.joined(separator: " · "))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct BluetoothPage: View {
    @EnvironmentObject var details: SystemDetails

    var body: some View {
        let devices = details.bluetooth
        VStack(alignment: .leading, spacing: 16) {
            section("Bağlı", devices.filter(\.connected))
            section("Eşlenmiş, bağlı değil", devices.filter { !$0.connected })
            if devices.isEmpty { Text("Cihazlar okunuyor…").foregroundStyle(.secondary) }
        }
        .onAppear { details.wantsBluetooth = true }
        .onDisappear { details.wantsBluetooth = false }
    }

    @ViewBuilder private func section(_ title: LocalizedStringKey, _ list: [BluetoothDeviceInfo]) -> some View {
        if !list.isEmpty {
            Card(title: title, icon: "dot.radiowaves.left.and.right", tint: .blue) {
                ForEach(list) { dev in
                    HStack(spacing: 10) {
                        Image(systemName: symbol(dev)).frame(width: 22).foregroundStyle(dev.connected ? .blue : .secondary)
                        Text(dev.name)
                        if !dev.connected && !dev.batteries.isEmpty {
                            Text("son bilinen").font(.caption2).foregroundStyle(.tertiary)
                        }
                        Spacer()
                        ForEach(dev.batteries, id: \.0) { name, level in
                            HStack(spacing: 3) {
                                Text(name).foregroundStyle(.secondary)
                                Text(pc(level)).monospacedDigit().foregroundStyle(level <= 20 ? .orange : .primary)
                            }
                            .font(.caption)
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(Capsule().fill(.quaternary))
                        }
                    }
                    .opacity(dev.connected ? 1 : 0.6)
                }
            }
        }
    }

    private func symbol(_ d: BluetoothDeviceInfo) -> String {
        let n = d.name.lowercased(), k = d.kind.lowercased()
        if n.contains("airpods max") { return "airpodsmax" }
        if n.contains("airpods pro") { return "airpodspro" }
        if n.contains("airpods") { return "airpods" }
        if n.contains("iphone") { return "iphone" }
        if k.contains("mouse") { return "computermouse.fill" }
        if k.contains("keyboard") { return "keyboard.fill" }
        if k.contains("speaker") { return "hifispeaker.fill" }
        if k.contains("headphone") || k.contains("headset") { return "headphones" }
        return "wave.3.right"
    }
}

private struct ProcessesPage: View {
    @EnvironmentObject var details: SystemDetails
    @State private var sortByMemory = false
    @State private var query = ""
    @State private var selected: pid_t?
    @State private var confirmForce = false
    @State private var failed = false

    var body: some View {
        let rows = details.processes.sorted { sortByMemory ? $0.memory > $1.memory : $0.cpu > $1.cpu }
        let current = rows.first { $0.id == selected }
        PageScroll {
            Card {
                HStack {
                    Text(query.isEmpty ? "En çok kaynak kullananlar" : "Arama sonuçları").font(.headline)
                    Spacer()
                    Picker("Sırala", selection: $sortByMemory) {
                        Text("İşlemci").tag(false)
                        Text("Bellek").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 180)
                }
                VStack(spacing: 0) {
                    HStack {
                        Text("Uygulama").frame(maxWidth: .infinity, alignment: .leading)
                        Text("İşlemci").frame(width: 70, alignment: .trailing)
                        Text("Bellek").frame(width: 80, alignment: .trailing)
                    }
                    .font(.caption).foregroundStyle(.secondary)
                    .padding(.horizontal, 8).padding(.bottom, 6)
                    Divider()
                    ForEach(rows) { p in
                        HStack(spacing: 10) {
                            Group {
                                if let icon = p.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                            }
                            .frame(width: 18, height: 18)
                            Text(p.name).lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                            Text((p.cpu / 100).formatted(.percent.precision(.fractionLength(1)))).monospacedDigit()
                                .foregroundStyle(p.cpu >= 80 ? .orange : .primary)
                                .frame(width: 70, alignment: .trailing)
                            Text(p.memory >= GiB ? gb(p.memory, digits: 2) : "\(Int(p.memory / 1_048_576)) MB").monospacedDigit()
                                .frame(width: 80, alignment: .trailing)
                        }
                        .font(.callout)
                        .padding(.horizontal, 8).padding(.vertical, 5)
                        .background(RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .fill(selected == p.id ? Color.accentColor.opacity(0.22) : .clear))
                        .contentShape(Rectangle())
                        .onTapGesture { selected = selected == p.id ? nil : p.id }
                    }
                }
                Text("İşlemci yüzdesi tek çekirdeğe göredir (2 çekirdeği tam kullanan = %200).")
                    .font(.caption).foregroundStyle(.tertiary)
                if rows.isEmpty { Text(query.isEmpty ? "Ölçülüyor…" : "Sonuç yok").foregroundStyle(.secondary) }
            }
        } bar: {
            HStack(spacing: 12) {
                if let p = current {
                    Group {
                        if let icon = p.icon { Image(nsImage: icon).resizable() } else { Image(systemName: "gearshape").foregroundStyle(.secondary) }
                    }
                    .frame(width: 26, height: 26)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(p.name).font(.callout.weight(.medium)).lineLimit(1)
                        Text(p.isApp ? "pid \(p.id)" : "Sadece uygulamalardan çıkış yaptırılabilir")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer(minLength: 16)
                    Button("Çıkış Yaptır") { failed = !details.quit(p.id, force: false) }
                        .glassButton()
                        .controlSize(.large)
                        .disabled(!p.isApp)
                    Button("Zorla Çıkış Yaptır", role: .destructive) { confirmForce = true }
                        .glassButton(prominent: true)
                        .tint(.red)
                        .controlSize(.large)
                        .disabled(!p.isApp)
                } else {
                    Image(systemName: "hand.tap").foregroundStyle(.secondary)
                    Text("Çıkış yaptırmak için listeden bir uygulama seç").foregroundStyle(.secondary)
                    Spacer()
                }
            }
            .frame(minHeight: 34)
            .floatingGlassBar()
        }
        .searchable(text: $query, placement: .toolbar, prompt: Text("İşlem ara"))
        .onChange(of: query) { _, q in details.processQuery = q }
        .onAppear { details.wantsProcesses = true }
        .onDisappear {
            details.wantsProcesses = false
            details.processQuery = ""
        }
        .alert("\(current?.name ?? "") uygulamasından zorla çıkış yaptırılsın mı?", isPresented: $confirmForce) {
            Button("Zorla Çıkış Yaptır", role: .destructive) {
                if let id = current?.id { failed = !details.quit(id, force: true) }
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("Kaydedilmemiş değişiklikler kaybolabilir.")
        }
        .alert("Uygulamadan çıkış yaptırılamadı", isPresented: $failed) {
            Button("Tamam", role: .cancel) {}
        }
    }
}
