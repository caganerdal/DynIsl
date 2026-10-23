import SwiftUI
import UniformTypeIdentifiers

struct SystemCard: View {
    @EnvironmentObject private var keepAwake: KeepAwake
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var sys: SystemMonitor

    var body: some View {
        HStack(alignment: .center, spacing: 18) {
            RingGauge(value: sys.cpu, label: "CPU", detail: pc(Int(sys.cpu * 100)), tint: gaugeTint(sys.cpu))
            RingGauge(value: sys.memory, label: "RAM",
                      detail: String(format: "%.1f / %.0f GB", sys.memoryUsed / 1_073_741_824, sys.memoryTotal / 1_073_741_824),
                      tint: gaugeTint(sys.memory))
            VStack(alignment: .leading, spacing: 8) {
                Text("AĞ").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                Label(SystemMonitor.formatBytes(sys.downBytesPerSec, perSecond: true), systemImage: "arrow.down")
                    .foregroundStyle(.cyan)
                Label(SystemMonitor.formatBytes(sys.upBytesPerSec, perSecond: true), systemImage: "arrow.up")
                    .foregroundStyle(.purple)
                Pill(keepAwake.isActive ? "☕ Uyanık" : "Uyanık tut",
                     tint: keepAwake.isActive ? .orange : .gray) { keepAwake.toggle() }
                    .help(keepAwake.remainingText ?? String(localized: "Mac uykuya girmesin"))
            }
            .font(.system(size: 12, weight: .medium).monospacedDigit())
            .frame(width: 96, alignment: .leading)

            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("EN ÇOK İŞLEMCİ").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button("Ayrıntılar ›") { DashboardWindow.show(model: model, page: .overview) }
                        .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(model.accent ?? .blue)
                }
                if sys.topProcesses.isEmpty {
                    Text("Ölçülüyor…").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                ForEach(sys.topProcesses) { p in
                    HStack {
                        Text(p.name).font(.system(size: 11)).lineLimit(1)
                        Spacer(minLength: 6)
                        Text(pc(Int(p.cpu)))
                            .font(.system(size: 11, weight: .semibold).monospacedDigit())
                            .foregroundStyle(p.cpu >= 90 ? .orange : .white.opacity(0.8))
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .animation(.easeOut(duration: 0.4), value: sys.cpu)
    }

    private func gaugeTint(_ v: Double) -> Color {
        v >= 0.85 ? .red : v >= 0.65 ? .orange : .green
    }
}

struct RingGauge: View {
    let value: Double
    let label: String
    let detail: String
    let tint: Color

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle().stroke(tint.opacity(0.18), lineWidth: 7)
                Circle()
                    .trim(from: 0, to: min(max(value, 0.005), 1))
                    .stroke(tint, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(label).font(.system(size: 11, weight: .bold))
            }
            .frame(width: 60, height: 60)
            Text(detail).font(.system(size: 10, weight: .medium).monospacedDigit()).foregroundStyle(.secondary)
                .lineLimit(1).fixedSize()
        }
    }
}

struct BatteryCard: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var b: BatteryAnalytics

    var body: some View {
        HStack(alignment: .top, spacing: 18) {
            VStack(alignment: .leading, spacing: 7) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(pc(b.level)).font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(stateLine(b)).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(2)
                }
                InfoRow(icon: "bolt.fill", tint: .yellow,
                        title: b.isCharging ? "Şarj gücü" : b.externalPower ? "Güç" : "Güç çekişi",
                        value: (b.isCharging || !b.externalPower ? String(format: "%.1f W", b.watts) : String(localized: "Adaptörden"))
                            + (b.adapterWatts.map { String(localized: " · \($0) W adaptör") } ?? ""))
                InfoRow(icon: "heart.fill", tint: healthTint(b.healthPercent), title: "Sağlık",
                        value: [b.healthPercent.map { pc($0) }, b.condition].compactMap { $0 }.joined(separator: " · "))
                VStack(alignment: .leading, spacing: 3) {
                    InfoRow(icon: "arrow.triangle.2.circlepath", tint: .blue, title: "Döngü",
                            value: "\(b.cycleCount) / \(b.designCycles)")
                    GeometryReader { g in
                        ZStack(alignment: .leading) {
                            Capsule().fill(.white.opacity(0.12))
                            Capsule().fill(.blue)
                                .frame(width: g.size.width * min(Double(b.cycleCount) / Double(max(b.designCycles, 1)), 1))
                        }
                    }
                    .frame(height: 4)
                }
            }
            .frame(width: 220, alignment: .leading)

            Rectangle().fill(.white.opacity(0.12)).frame(width: 1)

            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text("SON 24 SAAT").font(.system(size: 9, weight: .bold)).tracking(0.6).foregroundStyle(.secondary)
                    Spacer()
                    Button("Ayrıntılar ›") { DashboardWindow.show(model: model, page: .battery) }
                        .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(model.accent ?? .blue)
                }
                let data = b.last24h
                if data.count >= 2 {
                    BatteryGraph(samples: data)
                        .frame(maxHeight: .infinity)
                } else {
                    Text("Grafik için veri toplanıyor — birkaç saat içinde dolacak")
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                HStack(spacing: 12) {
                    if let d = b.drainPerHour {
                        Label(String(localized: "Pilde ort. \(pc(Int(d.rounded())))/sa"), systemImage: "chart.line.downtrend.xyaxis")
                    }
                    if b.onBatteryToday > 60 {
                        Label("Bugün pilde \(formatMinutes(Int(b.onBatteryToday / 60)))", systemImage: "clock")
                    }
                }
                .font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func stateLine(_ b: BatteryAnalytics) -> String {
        if b.fullyCharged { return String(localized: "Tamamen dolu") }
        if b.isCharging { return b.minutesToFull.map { String(localized: "Şarj oluyor\n\(formatMinutes($0))'da dolar") } ?? String(localized: "Şarj oluyor") }
        if b.externalPower { return String(localized: "Adaptöre bağlı\nşarj beklemede") }
        return b.minutesToEmpty.map { String(localized: "Pilde\n~\(formatMinutes($0)) kaldı") } ?? String(localized: "Pilde\nhesaplanıyor…")
    }

    private func healthTint(_ p: Int?) -> Color {
        guard let p else { return .gray }
        return p >= 80 ? .pink : p >= 70 ? .orange : .red
    }
}

struct InfoRow: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon).font(.system(size: 10)).foregroundStyle(tint).frame(width: 14)
            Text(title).font(.system(size: 11)).foregroundStyle(.secondary)
            Spacer(minLength: 4)
            Text(value).font(.system(size: 11, weight: .medium).monospacedDigit()).lineLimit(1)
        }
    }
}

struct ClipboardCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject var clip: ClipboardMonitor

    var body: some View {
        if !settings.clipboardHistory {
            VStack(spacing: 8) {
                Text("Pano geçmişi kapalı").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Pill("Aç", tint: .blue) { settings.clipboardHistory = true }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if clip.items.isEmpty {
            VStack(spacing: 6) {
                Image(systemName: "doc.on.clipboard").font(.system(size: 22)).foregroundStyle(.secondary)
                Text("Kopyaladıkların burada görünecek").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Pano · \(clip.items.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Button("Temizle") { withAnimation(.snappy) { clip.clear() } }
                        .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                }
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVStack(spacing: 2) {
                        ForEach(clip.items) { item in
                            ClipRow(item: item)
                        }
                    }
                }
            }
        }
    }
}

struct ClipRow: View {
    @EnvironmentObject private var clipboard: ClipboardMonitor
    @EnvironmentObject var model: IslandModel
    let item: ClipItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch item.content {
                case .text:
                    Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.secondary)
                case .image(let thumb, _, _, _, _):
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: 22, height: 22)

            Text(item.preview).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if hover {
                Button { withAnimation(.snappy) { clipboard.remove(item) } } label: {
                    Image(systemName: "xmark").font(.system(size: 9, weight: .bold)).foregroundStyle(.secondary)
                }
                .buttonStyle(.pressable)
            } else {
                Text([item.sourceApp, item.date.formatted(.relative(presentation: .named))]
                        .compactMap { $0 }.joined(separator: " · "))
                    .font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
            }
        }
        .padding(.horizontal, 8).frame(height: 28)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.white.opacity(hover ? 0.1 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture {
            withAnimation(.snappy) { clipboard.copy(item) }
            model.showActivity(.init(icon: "doc.on.doc.fill", tint: .blue, title: String(localized: "Panoya kopyalandı"), trailing: "✓"), duration: 1.5)
        }
        .help("Tıkla: tekrar kopyala")
    }
}

struct CalendarCard: View {
    @EnvironmentObject private var calendar: CalendarService
    var body: some View {
        let cal = calendar
        switch cal.access {
        case .granted:
            if cal.upcoming.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "calendar.badge.checkmark").font(.system(size: 22)).foregroundStyle(.secondary)
                    Text("Yaklaşan etkinlik yok").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 6) {
                    ForEach(cal.upcoming.prefix(3)) { e in
                        EventRow(event: e)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            }
        case .unknown, .denied:
            VStack(spacing: 10) {
                Label("Yaklaşan toplantıları görmek için takvim izni gerekli", systemImage: "calendar")
                    .font(.system(size: 12, weight: .medium))
                Pill(cal.access == .unknown ? "İzin ver" : "Ayarları aç", tint: .red) {
                    cal.access == .unknown ? cal.requestAccess() : cal.openSettings()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

struct EventRow: View {
    @EnvironmentObject private var calendar: CalendarService
    let event: UpcomingEvent
    @State private var hover = false

    var body: some View {
        HStack(spacing: 10) {
            Capsule().fill(event.color).frame(width: 3, height: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(event.title).font(.system(size: 13, weight: .semibold)).lineLimit(1)
                Text(timeText).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 8)
            if event.meetingURL != nil {
                Pill("Katıl", tint: .green) { calendar.join(event) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hover ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { calendar.openInCalendar(event) }
    }

    private static let timeFormatter: DateFormatter = {
        let f = DateFormatter()
        f.locale = appLocale
        f.dateFormat = "HH:mm"
        return f
    }()

    private var timeText: String {
        let f = Self.timeFormatter
        var range = "\(f.string(from: event.start)) – \(f.string(from: event.end))"
        if Calendar.current.isDateInTomorrow(event.start) { range = String(localized: "Yarın ") + range }
        let now = Date()
        if event.start <= now {
            return range + String(localized: " · şu an")
        }
        let mins = Int(ceil(event.start.timeIntervalSince(now) / 60))
        if mins < 60 { return range + String(localized: " · \(mins) dk sonra") }
        if let loc = event.location, event.meetingURL == nil { return range + " · " + loc }
        return range
    }
}

struct ShelfCard: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject var model: IslandModel
    @State private var shelfTargeted = false
    @State private var airdropTargeted = false

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(.white.opacity(shelfTargeted ? 0.14 : 0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: shelf.items.isEmpty ? [6, 5] : []))
                            .foregroundStyle(.white.opacity(shelfTargeted ? 0.8 : 0.2))
                    )
                if shelf.items.isEmpty {
                    VStack(spacing: 6) {
                        Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 24))
                            .foregroundStyle(.white.opacity(0.7))
                            .scaleEffect(shelfTargeted ? 1.15 : 1)
                        Text(shelfTargeted ? "Rafa bırak" : "Dosyaları rafa sürükle")
                            .font(.system(size: 12, weight: .semibold))
                        Text("Sonra buradan istediğin yere sürükle")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text("Raf · \(shelf.items.count)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                            Spacer()
                            let options = ShelfConversion.allCases.filter { !$0.inputs(from: shelf.items).isEmpty }
                            if shelf.converting {
                                ProgressView().controlSize(.mini)
                            } else if !options.isEmpty {
                                Menu {
                                    ForEach(options) { c in
                                        Button { shelf.convert(c) } label: {
                                            Label("\(c.title) (\(c.inputs(from: shelf.items).count))", systemImage: c.icon)
                                        }
                                    }
                                } label: {
                                    Text("Dönüştür").font(.system(size: 10, weight: .semibold)).foregroundStyle(.orange)
                                }
                                .menuStyle(.borderlessButton)
                                .menuIndicator(.hidden)
                                .fixedSize()
                            }
                            Button("AirDrop'la") { model.airdrop.share(shelf.items) }
                                .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(model.accent ?? .blue)
                            Button("Temizle") { withAnimation(.snappy) { shelf.clear() } }
                                .buttonStyle(.pressable).font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                        }
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 6) {
                                ForEach(shelf.items, id: \.self) { url in
                                    ShelfItemView(url: url)
                                        .transition(.scale(scale: 0.6).combined(with: .opacity))
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 10).padding(.vertical, 8)
                }
            }
            .frame(maxWidth: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                let files = urls.filter(\.isFileURL)
                guard !files.isEmpty else { return false }
                withAnimation(.spring(response: 0.35, dampingFraction: 0.75)) { shelf.add(files) }
                return true
            } isTargeted: { shelfTargeted = $0 }

            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(.blue.opacity(airdropTargeted ? 0.3 : 0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: [6, 5]))
                        .foregroundStyle(.blue.opacity(airdropTargeted ? 1 : 0.5))
                )
                .overlay(
                    VStack(spacing: 6) {
                        AirDropGlyph(size: 26)
                            .foregroundStyle(.blue)
                            .scaleEffect(airdropTargeted ? 1.2 : 1)
                        Text("AirDrop").font(.system(size: 12, weight: .semibold))
                        Text(airdropTargeted ? "Bırak ve gönder" : "Sürükle ya da tıkla")
                            .font(.system(size: 10)).foregroundStyle(.secondary)
                    }
                )
                .frame(width: 120)
                .contentShape(Rectangle())
                .onTapGesture { model.airdrop.pickAndShare() }
                .dropDestination(for: URL.self) { urls, _ in
                    let files = urls.filter(\.isFileURL)
                    guard !files.isEmpty else { return false }
                    model.airdrop.share(files)
                    return true
                } isTargeted: { airdropTargeted = $0 }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: shelfTargeted)
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: airdropTargeted)
    }
}

struct ShelfItemView: View {
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject var model: IslandModel
    let url: URL
    @State private var hover = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: shelf.icon(for: url))
                .resizable().interpolation(.high)
                .frame(width: 38, height: 38)
            Text(url.lastPathComponent)
                .font(.system(size: 9))
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .truncationMode(.middle)
                .frame(width: 60, height: 24, alignment: .top)
        }
        .padding(4)
        .background(RoundedRectangle(cornerRadius: 8).fill(.white.opacity(hover ? 0.1 : 0)))
        .overlay(alignment: .topTrailing) {
            if hover {
                Button { withAnimation(.snappy) { shelf.remove(url) } } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 13))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .gray)
                }
                .buttonStyle(.pressable)
                .offset(x: 3, y: -3)
            }
        }
        .onHover { hover = $0 }
        .help(url.path)
        .onDrag { NSItemProvider(object: url as NSURL) }
        .onTapGesture(count: 2) { shelf.open(url) }
        .contextMenu {
            Button("Aç") { shelf.open(url) }
            Button("Finder'da göster") { shelf.reveal(url) }
            Button("AirDrop ile gönder") { model.airdrop.share([url]) }
            Divider()
            Button("Raftan kaldır") { shelf.remove(url) }
        }
    }
}

struct AirDropGlyph: View {
    let size: CGFloat

    var body: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                let r = size * (0.36 + CGFloat(i) * 0.32)
                Circle()
                    .trim(from: 0.58, to: 0.92)
                    .stroke(style: StrokeStyle(lineWidth: size * 0.1, lineCap: .round))
                    .frame(width: r, height: r)
                    .rotationEffect(.degrees(0))
            }
            Circle().frame(width: size * 0.16, height: size * 0.16)
                .offset(y: size * 0.02)
        }
        .frame(width: size, height: size)
        .offset(y: size * 0.12)
    }
}

struct Artwork: View {
    let image: NSImage?
    var id: Int = 0
    let size: CGFloat
    let corner: CGFloat

    var body: some View {
        ZStack {
            Group {
                if let image {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                } else {
                    LinearGradient(colors: [.gray.opacity(0.6), .gray.opacity(0.3)], startPoint: .topLeading, endPoint: .bottomTrailing)
                        .overlay(
                            Image(systemName: "music.note")
                                .font(.system(size: size * 0.42, weight: .bold))
                                .foregroundStyle(.white.opacity(0.9))
                        )
                }
            }
            .frame(width: size, height: size)
            .id(id)
            .transition(.artworkSwap)
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: corner, style: .continuous))
        .animation(.spring(response: 0.55, dampingFraction: 0.82), value: id)
    }
}

struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

struct ProgressBar: View {
    let value: Double
    let tint: Color
    let onSeek: (Double) -> Void
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
            }
            .frame(height: hover ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(SpatialTapGesture().onEnded { onSeek($0.location.x / geo.size.width) })
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
        }
    }
}

struct IconButton: View {
    let name: String
    var size: CGFloat = 15
    let action: () -> Void

    init(_ name: String, size: CGFloat = 15, action: @escaping () -> Void) {
        self.name = name; self.size = size; self.action = action
    }

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: size))
                .contentTransition(.symbolEffect(.replace))
                .animation(.snappy(duration: 0.25), value: name)
                .frame(width: 30, height: 30)
                .background(Circle().fill(.white.opacity(hover ? 0.12 : 0)))
                .contentShape(Circle())
        }
        .buttonStyle(.pressable)
        .onHover { hover = $0 }
    }
}

struct Pill: View {
    let title: LocalizedStringKey
    let tint: Color
    let action: () -> Void

    init(_ title: LocalizedStringKey, tint: Color, action: @escaping () -> Void) {
        self.title = title; self.tint = tint; self.action = action
    }

    init(verbatim title: String, tint: Color, action: @escaping () -> Void) {
        self.init(LocalizedStringKey(title), tint: tint, action: action)
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .lineLimit(1)
                .fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5)
                .background(Capsule().fill(tint.opacity(0.22)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.pressable)
    }
}

struct BatteryGraph: View {
    let samples: [BatterySample]

    var body: some View {
        Canvas { ctx, size in
            guard let first = samples.first?.date, let last = samples.last?.date, last > first else { return }
            let plot = CGRect(x: 0, y: 4, width: size.width - 22, height: size.height - 18)
            let span = last.timeIntervalSince(first)
            func point(_ s: BatterySample) -> CGPoint {
                CGPoint(x: plot.minX + plot.width * s.date.timeIntervalSince(first) / span,
                        y: plot.maxY - plot.height * CGFloat(min(max(s.level, 0), 100)) / 100)
            }
            for v in [0, 50, 100] {
                let y = plot.maxY - plot.height * CGFloat(v) / 100
                var line = Path()
                line.move(to: CGPoint(x: plot.minX, y: y))
                line.addLine(to: CGPoint(x: plot.maxX, y: y))
                ctx.stroke(line, with: .color(.white.opacity(0.1)), lineWidth: 0.5)
                ctx.draw(Text("\(v)").font(.system(size: 8)).foregroundStyle(.secondary),
                         at: CGPoint(x: plot.maxX + 4, y: y), anchor: .leading)
            }
            var line = Path()
            line.addLines(samples.map(point))
            var area = line
            area.addLine(to: CGPoint(x: plot.maxX, y: plot.maxY))
            area.addLine(to: CGPoint(x: plot.minX, y: plot.maxY))
            area.closeSubpath()
            ctx.fill(area, with: .linearGradient(Gradient(colors: [.green.opacity(0.5), .green.opacity(0.02)]),
                                                 startPoint: CGPoint(x: 0, y: plot.minY), endPoint: CGPoint(x: 0, y: plot.maxY)))
            ctx.stroke(line, with: .color(.green), style: StrokeStyle(lineWidth: 1.5, lineCap: .round, lineJoin: .round))
            let cal = Calendar.current
            var tick = cal.dateInterval(of: .hour, for: first)?.end ?? first
            while tick < last {
                let x = plot.minX + plot.width * tick.timeIntervalSince(first) / span
                if cal.component(.hour, from: tick) % 6 == 0, x > 10, x < plot.maxX - 10 {
                    ctx.draw(Text(tick, format: .dateTime.hour()).font(.system(size: 8)).foregroundStyle(.secondary),
                             at: CGPoint(x: x, y: plot.maxY + 8), anchor: .center)
                }
                tick = tick.addingTimeInterval(3600)
            }
        }
    }
}
