import SwiftUI
import UniformTypeIdentifiers

struct ExpandedView: View {
    @EnvironmentObject private var media: NowPlayingService
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject private var shelf: ShelfStore
    @EnvironmentObject var model: IslandModel
    @State private var forward = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(settings.visibleTabs, id: \.self) { tab in
                        TabButton(icon: tab.icon, selected: model.tab == tab) {
                            let tabs = settings.visibleTabs
                            forward = (tabs.firstIndex(of: tab) ?? 0) >= (tabs.firstIndex(of: model.tab) ?? 0)
                            model.tab = tab
                        }
                            .help(tab.title)
                            .overlay(alignment: .topTrailing) {
                                if tab == .shelf, !shelf.items.isEmpty {
                                    Text("\(shelf.items.count)")
                                        .font(.system(size: 8, weight: .bold))
                                        .padding(.horizontal, 3.5).padding(.vertical, 1)
                                        .background(Capsule().fill(model.accent ?? .blue))
                                        .offset(x: 2, y: -2)
                                }
                            }
                    }
                    TabButton(icon: "gearshape.fill", selected: false) { SettingsWindow.show(model: model) }
                        .help("Ayarlar")
                }
                Spacer()
                StatusIcons()
            }
            .frame(height: model.notchSize.height)

            Group {
                switch model.tab {
                case .media:
                    HStack(alignment: .top, spacing: 20) {
                        VStack(spacing: 0) {
                            PlayerCard()
                            if media.info != nil {
                                Spacer(minLength: 10)
                                MediaControlsBar()
                            }
                        }
                        .frame(maxHeight: .infinity, alignment: .top)
                        Rectangle().fill(.white.opacity(0.12)).frame(width: 1)
                        StatusCard().frame(width: 150)
                    }
                case .calendar:
                    CalendarCard()
                case .shelf:
                    ShelfCard()
                case .clipboard:
                    ClipboardCard()
                case .system:
                    SystemCard()
                case .battery:
                    BatteryCard()
                case .ai:
                    AICard()
                }
            }
            .frame(maxHeight: .infinity)
            .id(model.tab)
            .transition(settings.calmMotion ? .opacity : .asymmetric(
                insertion: .offset(x: forward ? 24 : -24).combined(with: .opacity),
                removal: .opacity
            ))
        }
        .animation(settings.calmMotion ? .easeOut(duration: 0.12) : .easeOut(duration: 0.22 * settings.animationSpeed), value: model.tab)
        .foregroundStyle(.white)
    }
}

struct TabButton: View {
    let icon: String
    let selected: Bool
    let action: () -> Void
    @Environment(\.islandAccent) private var accent

    var body: some View {
        Button(action: action) {
            Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 22)
                .background(Capsule().fill(selected ? (accent?.opacity(0.4) ?? .white.opacity(0.18)) : .clear))
                .foregroundStyle(selected ? .white : .white.opacity(0.5))
                .contentShape(Capsule())
        }
        .buttonStyle(.pressable)
    }
}

struct PlayerCard: View {
    @EnvironmentObject private var media: NowPlayingService
    var body: some View {
        let m = media
        if let info = m.info {
            HStack(spacing: 14) {
                Artwork(image: m.artwork, id: m.artworkID, size: 76, corner: 14)
                    .overlay(alignment: .bottomTrailing) {
                        SourceBadge(source: info.source).offset(x: 7, y: 7)
                    }
                VStack(alignment: .leading, spacing: 4) {
                    SourceLabel(source: info.source)
                        .id(info.source)
                        .transition(.opacity)

                    ZStack(alignment: .leading) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(info.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                            Text(info.artist).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(1)
                        }
                        .id(info.trackID)
                        .transition(.trackSlide(m.direction))
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .clipped()

                    TimelineView(.periodic(from: .now, by: 0.5)) { _ in
                        let elapsed = m.elapsed
                        VStack(spacing: 3) {
                            ProgressBar(value: elapsed / info.duration, tint: m.accent) { m.seek(to: $0) }
                                .frame(height: 10)
                            HStack {
                                Text(formatSeconds(Int(elapsed)))
                                Spacer()
                                Text("-" + formatSeconds(Int(info.duration - elapsed)))
                            }
                            .font(.system(size: 10).monospacedDigit())
                            .foregroundStyle(.secondary)
                        }
                    }
                    .padding(.top, 2)

                    HStack(spacing: 22) {
                        IconButton("backward.fill") { m.previous() }
                        IconButton(info.isPlaying ? "pause.fill" : "play.fill", size: 20) { m.playPause() }
                        IconButton("forward.fill") { m.next() }
                    }
                    .frame(maxWidth: .infinity)
                }
            }
            .frame(maxWidth: .infinity)
            .animation(.spring(response: 0.45, dampingFraction: 0.86), value: info.trackID)
            .animation(.easeInOut(duration: 0.3), value: info.source)
            .animation(.easeInOut(duration: 0.6), value: m.accent)
        } else {
            EmptyPlayer()
        }
    }
}

struct EmptyPlayer: View {
    @EnvironmentObject private var media: NowPlayingService
    var body: some View {
        VStack(spacing: 10) {
            if media.permissionDenied {
                Label("Müzik uygulamalarını kontrol izni yok", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                Pill("Ayarları aç", tint: .blue) { media.openAutomationSettings() }
            } else {
                Text("Şu an bir şey çalmıyor")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill("Spotify", tint: .green) { media.open(.spotify) }
                    Pill("Apple Music", tint: .pink) { media.open(.music) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct SourceBadge: View {
    let source: MediaSource

    var body: some View {
        Group {
            if let icon = source.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high)
            } else {
                Image(systemName: "music.note").frame(width: 24, height: 24).background(Circle().fill(.gray))
            }
        }
        .frame(width: 26, height: 26)
        .shadow(color: .black.opacity(0.6), radius: 3)
        .help(source.displayName)
    }
}

struct SourceLabel: View {
    let source: MediaSource

    var body: some View {
        HStack(spacing: 4) {
            if let icon = source.appIcon {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 13, height: 13)
            }
            Text(source.displayName.uppercased())
                .font(.system(size: 9, weight: .bold))
                .tracking(0.6)
                .foregroundStyle(source == .spotify ? Color(red: 0.12, green: 0.84, blue: 0.38) : Color(red: 0.98, green: 0.24, blue: 0.35))
        }
    }
}

struct MediaControlsBar: View {
    @EnvironmentObject private var media: NowPlayingService
    @EnvironmentObject var model: IslandModel

    var body: some View {
        let m = media
        if let info = m.info {
            HStack(spacing: 4) {
                IconButton(volumeSymbol(info), size: 12) { m.toggleMute() }
                    .help(info.muted ? "Sesi aç" : "Sessize al")
                VolumeSlider(value: info.muted ? 0 : info.volume, tint: m.accent) { v, final in
                    m.setVolume(v, final: final)
                }
                .frame(minWidth: 50, maxWidth: .infinity)
                Text("\(info.muted ? 0 : info.volume)")
                    .font(.system(size: 10).monospacedDigit())
                    .foregroundStyle(.secondary)
                    .frame(width: 22, alignment: .leading)

                ToggleIcon("shuffle", on: info.shuffle, tint: m.accent, help: "Karışık çal") { m.toggleShuffle() }
                ToggleIcon(info.repeatMode.symbol, on: info.repeatMode != .off, tint: m.accent,
                           help: repeatHelp(info)) { m.cycleRepeat() }

                switch info.source {
                case .music:
                    ToggleIcon(info.favorited ? "star.fill" : "star", on: info.favorited, tint: .pink,
                               help: info.favorited ? "Favorilerden çıkar" : "Favorilere ekle") { m.toggleFavorite() }
                    ToggleIcon(info.disliked ? "hand.thumbsdown.fill" : "hand.thumbsdown", on: info.disliked, tint: .white,
                               help: "Sevmedim (daha az öner)") { m.toggleDislike() }
                case .spotify:
                    ToggleIcon("link", on: false, tint: .white, help: "Şarkı linkini kopyala") {
                        guard let url = m.shareLink else { return }
                        NSPasteboard.general.clearContents()
                        NSPasteboard.general.setString(url.absoluteString, forType: .string)
                        model.showActivity(.init(icon: "link", tint: .green, title: "Spotify", trailing: String(localized: "Link kopyalandı")), duration: 2)
                    }
                }
                ToggleIcon("arrow.up.forward.app", on: false, tint: .white,
                           help: "\(info.source.displayName)'da aç") { m.revealInApp() }
            }
        }
    }

    private func volumeSymbol(_ i: NowPlayingInfo) -> String {
        if i.muted || i.volume == 0 { return "speaker.slash.fill" }
        switch i.volume {
        case ..<34: return "speaker.wave.1.fill"
        case ..<67: return "speaker.wave.2.fill"
        default: return "speaker.wave.3.fill"
        }
    }

    private func repeatHelp(_ i: NowPlayingInfo) -> LocalizedStringKey {
        switch i.repeatMode {
        case .off: return "Tekrar: kapalı"
        case .all: return "Tekrar: tümü"
        case .one: return "Tekrar: bu şarkı"
        }
    }
}

struct ToggleIcon: View {
    let name: String
    let on: Bool
    let tint: Color
    let help: LocalizedStringKey
    let action: () -> Void

    init(_ name: String, on: Bool, tint: Color, help: LocalizedStringKey, action: @escaping () -> Void) {
        self.name = name; self.on = on; self.tint = tint; self.help = help; self.action = action
    }

    @State private var hover = false

    var body: some View {
        Button(action: action) {
            Image(systemName: name)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(on ? tint : .white.opacity(hover ? 0.95 : 0.6))
                .frame(width: 28, height: 24)
                .background(
                    RoundedRectangle(cornerRadius: 7, style: .continuous)
                        .fill(on ? tint.opacity(0.2) : .white.opacity(hover ? 0.1 : 0))
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.pressable)
        .onHover { hover = $0 }
        .help(help)
        .animation(.easeOut(duration: 0.15), value: on)
    }
}

struct VolumeSlider: View {
    let value: Int
    let tint: Color
    let onChange: (Int, Bool) -> Void
    @State private var dragValue: Double?
    @State private var hover = false

    var body: some View {
        GeometryReader { geo in
            let shown = dragValue ?? Double(value) / 100
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.15))
                Capsule().fill(tint).frame(width: max(geo.size.width * shown, 0))
            }
            .frame(height: hover || dragValue != nil ? 6 : 4)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { g in
                        let v = min(max(g.location.x / geo.size.width, 0), 1)
                        dragValue = v
                        onChange(Int(v * 100), false)
                    }
                    .onEnded { g in
                        let v = min(max(g.location.x / geo.size.width, 0), 1)
                        onChange(Int(v * 100), true)
                        dragValue = nil
                    }
            )
            .onHover { hover = $0 }
            .animation(.easeOut(duration: 0.15), value: hover)
        }
        .frame(height: 16)
    }
}

struct StatusCard: View {
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var weather: WeatherService

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            TimelineView(.periodic(from: .now, by: 1)) { ctx in
                VStack(alignment: .leading, spacing: 0) {
                    Text(ctx.date, format: .dateTime.hour().minute())
                        .font(.system(size: 30, weight: .semibold, design: .rounded))
                    Text(ctx.date, format: .dateTime.weekday(.wide).day().month(.wide))
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            if settings.showWeather, let w = weather.now {
                HStack(spacing: 5) {
                    Image(systemName: w.symbol)
                        .symbolRenderingMode(.multicolor)
                    Text("\(w.temperature)°").font(.system(size: 13, weight: .semibold))
                    Text(w.summary).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                }
                .padding(.top, 6)
                .help([w.place, String(localized: "En yüksek \(w.high)° · En düşük \(w.low)°")].compactMap { $0 }.joined(separator: " · "))
            }

            Spacer(minLength: 8)

            VStack(alignment: .leading, spacing: 5) {
                Text("ZAMANLAYICI")
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.6)
                    .foregroundStyle(.secondary)
                HStack(spacing: 6) {
                    if let r = model.timerRemaining {
                        Text(formatSeconds(r))
                            .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(model.accent ?? .orange)
                            .contentTransition(.numericText(countsDown: true))
                            .animation(.snappy, value: r)
                        Spacer(minLength: 0)
                        Pill("İptal", tint: .red) { model.cancelTimer() }
                    } else {
                        Pill("1 dk", tint: model.accent ?? .orange) { model.startTimer(seconds: 60) }
                        Pill("5 dk", tint: model.accent ?? .orange) { model.startTimer(seconds: 300) }
                        Pill("25 dk", tint: model.accent ?? .orange) { model.startTimer(seconds: 1500) }
                    }
                }
                .frame(height: 24)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct StatusIcons: View {
    @EnvironmentObject private var battery: BatteryMonitor
    @EnvironmentObject private var focus: FocusMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            if settings.notifyFocus, let f = focus.current {
                HStack(spacing: 4) {
                    Image(systemName: f.symbol)
                    Text(f.name).lineLimit(1)
                }
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(f.tint)
                .padding(.horizontal, 7).padding(.vertical, 3)
                .background(Capsule().fill(f.tint.opacity(0.18)))
                .frame(maxWidth: 90)
                .help("Odak: \(f.name)")
                .transition(.scale.combined(with: .opacity))
            }
            if battery.hasBattery {
                Button { model.tab = .battery } label: {
                    HStack(spacing: 5) {
                        Text(pc(battery.level)).font(.system(size: 11, weight: .medium))
                        Image(systemName: battery.symbol)
                            .foregroundStyle(battery.isCharging ? .green : .white)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help("Pil analizi")
            }
        }
        .font(.system(size: 11))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: focus.current)
    }
}
