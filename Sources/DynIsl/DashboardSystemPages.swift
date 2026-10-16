import AppKit
import Charts
import SwiftUI

struct OverviewPage: View {
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

func uptime(since d: Date) -> String {
    let s = Int(Date().timeIntervalSince(d))
    let days = s / 86400, hours = (s % 86400) / 3600, mins = (s % 3600) / 60
    if days > 0 { return String(localized: "\(days) gün \(hours) sa") }
    return hours > 0 ? String(localized: "\(hours) sa \(mins) dk") : String(localized: "\(mins) dk")
}

struct CPUPage: View {
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

struct GPUPage: View {
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

struct MemoryPage: View {
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

struct StoragePage: View {
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

struct NetworkPage: View {
    @EnvironmentObject private var weather: WeatherService
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
                            Button("Konum ayarları") { weather.openLocationSettings() }.controlSize(.small)
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

struct SpeedTestCard: View {
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

struct IssuesBanner: View {
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

struct BatteryPage: View {
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

struct DisplaysPage: View {
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

struct BluetoothPage: View {
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

struct ProcessesPage: View {
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
