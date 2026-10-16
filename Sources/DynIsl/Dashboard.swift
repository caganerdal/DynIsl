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
            w.contentView = NSHostingView(rootView: DashboardView().islandServices(model))
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

let GiB = 1_073_741_824.0

func gb(_ bytes: Double, digits: Int = 1) -> String {
    String(format: "%.\(digits)f GB", bytes / GiB)
}

func pct(_ v: Double) -> String { pc(Int((v * 100).rounded())) }

struct Card<Content: View>: View {
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

struct Stat: View {
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

struct KeyValue: View {
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

struct HistoryChart: View {
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

struct DualChart: View {
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

struct Sparkline: View {
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

struct UsageBar: View {
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
