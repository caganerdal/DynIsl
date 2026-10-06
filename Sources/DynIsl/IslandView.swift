import SwiftUI
import Charts
import UniformTypeIdentifiers

struct IslandView: View {
    @EnvironmentObject var model: IslandModel
    @State private var shown: CGSize = .zero

    var body: some View {
        let size = shown == .zero ? model.currentSize : shown
        let motion = model.settings.islandMotion
        let speed = model.settings.animationSpeed
        let expanded = model.state == .expanded
        let top: CGFloat = expanded ? 14 : 6
        let compactHUD = model.hud.current.map { model.settings.hudStyle(for: $0.kind).isCompact } ?? false
        let bottom: CGFloat = expanded || model.state == .peek ? 28 : (model.state == .hud && !compactHUD) || model.state == .charging ? 18 : 10
        let glowing = model.settings.albumGlow && model.media.isPlaying
            && (model.state == .playing || (expanded && model.tab == .media))

        ZStack(alignment: .top) {
            if glowing {
                CAGlow(color: model.media.accent, top: top, bottom: bottom)
                    .transition(.opacity)
            }
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                .opacity(model.state == .idle && model.hasNotch && !model.settings.showPet ? 0 : 1)
                .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 16, y: 6)

            content
                .padding(.horizontal, expanded ? 28 : 14)
                .transition(.opacity.combined(with: .scale(scale: motion.contentScale, anchor: .top)))
                .id(model.state)
                .frame(width: size.width, height: size.height, alignment: .top)
                .clipShape(NotchShape(topRadius: top, bottomRadius: bottom))
        }
        .frame(width: size.width, height: size.height)
        .contentShape(Rectangle())
        .onTapGesture {
            if !expanded, model.state != .peek, model.state != .hud { model.setExpanded(true) }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .animation(motion.main(speed), value: model.state)
        .onAppear { shown = model.currentSize }
        .onChange(of: model.currentSize) { old, new in
            withAnimation(motion.height(speed, growing: new.height > old.height)) { shown.height = new.height }
            withAnimation(motion.width(speed, growing: new.height > old.height || (new.height == old.height && new.width > old.width))) {
                shown.width = new.width
            }
        }
        .animation(.easeInOut(duration: 0.5), value: glowing)
        .preferredColorScheme(.dark)
        .environment(\.islandAccent, model.accent)
    }

    @ViewBuilder private var content: some View {
        switch model.state {
        case .idle:
            if model.settings.showPet {
                CompactRow(height: model.notchSize.height) {
                    Color.clear.frame(width: 1)
                } trailing: {
                    IslandPet(mood: model.petMood).offset(x: 4)
                }
                .help("Ada kedisi")
            }
        case .playing:
            CompactRow(height: model.notchSize.height) {
                Artwork(image: model.media.artwork, id: model.media.artworkID, size: 20, corner: 5)
            } trailing: {
                HStack(spacing: 5) {
                    PrivacyDots()
                    CAEqualizer(color: model.media.accent, style: model.settings.equalizerStyle)
                    if model.settings.showPet { IslandPet(mood: model.petMood).padding(.leading, 4) }
                }
            }
        case .meeting:
            if let e = model.calendar.imminent {
                CompactRow(height: model.notchSize.height) {
                    Image(systemName: e.meetingURL != nil ? "video.fill" : "calendar")
                        .foregroundStyle(e.color)
                } trailing: {
                    HStack(spacing: 5) {
                        PrivacyDots()
                        Text(countdown(to: e.start))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(e.color)
                    }
                }
            }
        case .download:
            if let d = model.downloads.summary {
                CompactRow(height: model.notchSize.height) {
                    Image(systemName: "arrow.down.circle.fill").foregroundStyle(.blue)
                        .symbolEffect(.pulse, options: .repeating)
                } trailing: {
                    HStack(spacing: 5) {
                        if let f = d.fraction {
                            Text("\(Int(f * 100))")
                                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                                .foregroundStyle(.blue)
                                .contentTransition(.numericText())
                        }
                        ProgressRing(value: d.fraction, tint: .blue)
                    }
                    .animation(.easeOut(duration: 0.3), value: d.fraction)
                }
                .help(d.name)
            }
        case .call:
            CompactRow(height: model.notchSize.height) {
                HStack(spacing: 5) {
                    Image(systemName: model.call.usesCamera ? "video.fill" : "mic.fill")
                        .foregroundStyle(model.call.usesCamera ? .green : .orange)
                    Text(model.call.appName ?? String(localized: "Görüşme")).font(.system(size: 12, weight: .medium)).lineLimit(1)
                }
            } trailing: {
                HStack(spacing: 5) {
                    if model.call.micMuted {
                        Image(systemName: "mic.slash.fill").foregroundStyle(.red).font(.system(size: 11))
                    }
                    if let start = model.call.startedAt { ElapsedText(since: start, tint: .white) }
                }
            }
        case .speedTest:
            CompactRow(height: model.notchSize.height) {
                Image(systemName: "gauge.with.needle.fill").foregroundStyle(.cyan)
            } trailing: {
                ProgressRing(value: nil, tint: .cyan)
            }
            .help("İnternet hız testi sürüyor")
        case .privacy:
            CompactRow(height: model.notchSize.height) {
                HStack(spacing: 4) {
                    if model.privacy.cameraOn { Image(systemName: "video.fill").foregroundStyle(.green) }
                    if model.privacy.micOn { Image(systemName: "mic.fill").foregroundStyle(.orange) }
                }
                .font(.system(size: 11))
            } trailing: {
                PrivacyDots()
            }
        case .timer:
            CompactRow(height: model.notchSize.height) {
                Image(systemName: "timer").foregroundStyle(model.accent ?? .orange)
            } trailing: {
                HStack(spacing: 5) {
                    PrivacyDots()
                    Text(formatSeconds(model.timerRemaining ?? 0))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.accent ?? .orange)
                }
            }
        case .activity:
            if let a = model.activity {
                let style = model.settings.activityStyle
                CompactRow(height: model.notchSize.height) {
                    HStack(spacing: 6) {
                        if SpinningSymbol.spins(a.icon) {
                            SpinningSymbol(name: a.icon, tint: a.tint)
                        } else {
                            Image(systemName: a.icon).foregroundStyle(a.tint)
                                .contentTransition(.symbolEffect(.replace))
                        }
                        RevealText(text: a.title, active: style == .typewriter)
                            .font(.system(size: 12, weight: .medium)).lineLimit(1).truncationMode(.middle)
                    }
                    .modifier(PopIn(active: style == .pop))
                } trailing: {
                    HStack(spacing: 6) {
                        RevealText(text: a.trailing, active: style == .typewriter, delay: Double(a.title.count) * 0.026)
                            .font(.system(size: 12, weight: .semibold).monospacedDigit())
                            .foregroundStyle(a.ring != nil ? .white : a.tint)
                            .lineLimit(1)
                            .contentTransition(.numericText())
                        if let ring = a.ring {
                            LevelRing(value: ring)
                        }
                    }
                    .animation(.snappy, value: a)
                    .modifier(PopIn(active: style == .pop, delay: 0.14))
                }
                .id(a)
            }
        case .hud:
            if let info = model.hud.current {
                switch model.settings.hudStyle(for: info.kind) {
                case .classic:
                    LevelHUD(info: info, notchHeight: model.notchSize.height)
                        .padding(.bottom, 10)
                case .liquid:
                    LiquidHUD(info: info, notchHeight: model.notchSize.height)
                        .padding(.horizontal, -14)
                case .minimal:
                    CompactRow(height: model.notchSize.height) {
                        HUDSymbol(info: info)
                    } trailing: {
                        MinimalBar(info: info)
                    }
                case .ring:
                    CompactRow(height: model.notchSize.height) {
                        HUDSymbol(info: info)
                    } trailing: {
                        HUDRing(info: info)
                    }
                case .segments:
                    CompactRow(height: model.notchSize.height) {
                        HUDSymbol(info: info)
                    } trailing: {
                        SegmentBar(info: info)
                    }
                }
            }
        case .charging:
            if let level = model.chargeLevel {
                ChargingView(level: level, notchHeight: model.notchSize.height)
                    .padding(.bottom, 10)
            }
        case .peek:
            if let shot = model.screenshots.current {
                ScreenshotPeek(shot: shot)
                    .padding(.top, model.notchSize.height + 6)
                    .padding(.bottom, 16)
            }
        case .expanded:
            ExpandedView()
                .padding(.bottom, 18)
        }
    }
}

private struct SpinningSymbol: View {
    let name: String
    let tint: Color
    @State private var appeared = false
    @State private var start = Date()

    static func spins(_ name: String) -> Bool {
        name.hasPrefix("airpods") || name.hasPrefix("beats") || name == "headphones"
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
            let angle = ctx.date.timeIntervalSince(start) * 130
            Image(systemName: name)
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(tint)
                .contentTransition(.symbolEffect(.replace))
                .rotation3DEffect(.degrees(angle), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
        }
        .frame(width: 22, height: 20)
        .scaleEffect(appeared ? 1 : 0.4)
        .opacity(appeared ? 1 : 0)
        .onAppear {
            start = Date()
            withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
        }
    }
}

private struct LevelRing: View {
    let value: Double
    @State private var shown: Double = 0

    var body: some View {
        let color: Color = value <= 0.1 ? .red : value <= 0.2 ? .orange : .green
        ZStack {
            Circle().stroke(color.opacity(0.25), lineWidth: 2.5)
            Circle()
                .trim(from: 0, to: shown)
                .stroke(color, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                .rotationEffect(.degrees(-90))
        }
        .frame(width: 16, height: 16)
        .onAppear { withAnimation(.easeOut(duration: 0.7).delay(0.15)) { shown = value } }
        .onChange(of: value) { _, v in withAnimation(.easeOut(duration: 0.5)) { shown = v } }
    }
}

private struct CompactRow<L: View, T: View>: View {
    let height: CGFloat
    @ViewBuilder var leading: L
    @ViewBuilder var trailing: T

    var body: some View {
        HStack {
            leading
            Spacer(minLength: 0)
            trailing
        }
        .frame(height: height)
        .foregroundStyle(.white)
    }
}

private struct ExpandedView: View {
    @EnvironmentObject var model: IslandModel
    @State private var forward = true

    var body: some View {
        VStack(spacing: 8) {
            HStack {
                HStack(spacing: 2) {
                    ForEach(model.settings.visibleTabs, id: \.self) { tab in
                        TabButton(icon: tab.icon, selected: model.tab == tab) {
                            let tabs = model.settings.visibleTabs
                            forward = (tabs.firstIndex(of: tab) ?? 0) >= (tabs.firstIndex(of: model.tab) ?? 0)
                            model.tab = tab
                        }
                            .help(tab.title)
                            .overlay(alignment: .topTrailing) {
                                if tab == .shelf, !model.shelf.items.isEmpty {
                                    Text("\(model.shelf.items.count)")
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
                            if model.media.info != nil {
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
                }
            }
            .frame(maxHeight: .infinity)
            .id(model.tab)
            .transition(.asymmetric(
                insertion: .offset(x: forward ? 36 : -36).combined(with: .opacity),
                removal: .offset(x: forward ? -36 : 36).combined(with: .opacity)
            ))
        }
        .animation(model.settings.spring(0.32, 1), value: model.tab)
        .foregroundStyle(.white)
    }
}

private struct TabButton: View {
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

private struct PlayerCard: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        let m = model.media
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

private struct EmptyPlayer: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        VStack(spacing: 10) {
            if model.media.permissionDenied {
                Label("Müzik uygulamalarını kontrol izni yok", systemImage: "lock.fill")
                    .font(.system(size: 12, weight: .medium))
                Pill("Ayarları aç", tint: .blue) { model.media.openAutomationSettings() }
            } else {
                Text("Şu an bir şey çalmıyor")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                HStack(spacing: 8) {
                    Pill("Spotify", tint: .green) { model.media.open(.spotify) }
                    Pill("Apple Music", tint: .pink) { model.media.open(.music) }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct SourceBadge: View {
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

private struct SourceLabel: View {
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

private struct MediaControlsBar: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        let m = model.media
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

private struct ToggleIcon: View {
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

private struct VolumeSlider: View {
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

private struct StatusCard: View {
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
            if model.settings.showWeather, let w = weather.now {
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

private struct PrivacyDots: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        HStack(spacing: 3) {
            if model.settings.showPrivacy {
                if model.privacy.cameraOn { Circle().fill(.green).frame(width: 6, height: 6) }
                if model.privacy.micOn { Circle().fill(.orange).frame(width: 6, height: 6) }
            }
        }
    }
}

private struct StatusIcons: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        HStack(spacing: 8) {
            if model.settings.callMode, let start = model.call.startedAt {
                Button { model.call.toggleMute() } label: {
                    HStack(spacing: 4) {
                        Image(systemName: model.call.micMuted ? "mic.slash.fill" : "mic.fill")
                        ElapsedText(since: start, tint: model.call.micMuted ? .red : .white)
                    }
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(model.call.micMuted ? .red : .white)
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Capsule().fill((model.call.micMuted ? Color.red : Color.green).opacity(0.22)))
                    .contentShape(Capsule())
                }
                .buttonStyle(.pressable)
                .help(model.call.micMuted ? "Mikrofonu aç" : "Mikrofonu kapat (tüm uygulamalar için)")
            }
            if model.settings.notifyFocus, let f = model.focus.current {
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
            if model.settings.showPrivacy, model.privacy.cameraOn {
                Image(systemName: "video.fill").foregroundStyle(.green).help("Kamera kullanımda")
            }
            if model.settings.showPrivacy, model.privacy.micOn {
                Image(systemName: "mic.fill").foregroundStyle(.orange)
                    .help(String(localized: "Mikrofon: ") + model.privacy.micApps.joined(separator: ", "))
            }
            if model.battery.hasBattery {
                Button { model.tab = .battery } label: {
                    HStack(spacing: 5) {
                        Text(pc(model.battery.level)).font(.system(size: 11, weight: .medium))
                        Image(systemName: model.battery.symbol)
                            .foregroundStyle(model.battery.isCharging ? .green : .white)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.pressable)
                .help("Pil analizi")
            }
        }
        .font(.system(size: 11))
        .animation(.spring(response: 0.35, dampingFraction: 0.8), value: model.focus.current)
    }
}

private struct ElapsedText: View {
    let since: Date
    let tint: Color

    var body: some View {
        TimelineView(.periodic(from: since, by: 1)) { ctx in
            let s = max(Int(ctx.date.timeIntervalSince(since)), 0)
            Text(s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s % 3600 / 60, s % 60)
                           : String(format: "%d:%02d", s / 60, s % 60))
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)
        }
    }
}

private struct ProgressRing: View {
    let value: Double?
    let tint: Color

    var body: some View {
        ZStack {
            Circle().stroke(tint.opacity(0.25), lineWidth: 2.5)
            if let value {
                Circle()
                    .trim(from: 0, to: max(value, 0.02))
                    .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            } else {
                TimelineView(.animation(minimumInterval: 1.0 / 30)) { ctx in
                    Circle()
                        .trim(from: 0, to: 0.3)
                        .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                        .rotationEffect(.degrees(ctx.date.timeIntervalSinceReferenceDate * 360))
                }
            }
        }
        .frame(width: 16, height: 16)
    }
}

private struct LevelHUD: View {
    @EnvironmentObject var model: IslandModel
    let info: HUDInfo
    let notchHeight: CGFloat

    var body: some View {
        let shown = info.muted ? 0 : info.level
        VStack(spacing: 6) {
            HStack {
                HUDSymbol(info: info)
                Spacer()
                Text(info.muted ? "Sessiz" : "\(Int((shown * 100).rounded()))")
                    .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                    .foregroundStyle(.white.opacity(info.muted ? 0.6 : 1))
                    .contentTransition(.numericText(value: shown))
            }
            .frame(height: notchHeight)

            HUDSlider(value: shown, tint: info.kind == .brightness ? .yellow : (model.accent ?? .white), dimmed: info.muted) {
                model.hud.setLevel($0)
            }
        }
        .foregroundStyle(.white)
        .animation(.snappy(duration: 0.2), value: shown)
    }
}

private struct HUDSlider: View {
    let value: Double
    let tint: Color
    let dimmed: Bool
    let onChange: (Double) -> Void
    @State private var dragging = false

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.16))
                Capsule()
                    .fill(tint.opacity(dimmed ? 0.35 : 1))
                    .frame(width: max(g.size.width * value, value > 0 ? 8 : 0))
            }
            .frame(height: dragging ? 10 : 7)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { v in
                        dragging = true
                        onChange(v.location.x / g.size.width)
                    }
                    .onEnded { _ in dragging = false }
            )
            .animation(.easeOut(duration: 0.15), value: dragging)
        }
        .frame(height: 14)
    }
}

private struct ScreenshotPeek: View {
    @EnvironmentObject var model: IslandModel
    let shot: Screenshot

    var body: some View {
        let s = model.screenshots
        HStack(spacing: 14) {
            Image(nsImage: shot.thumbnail)
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(maxWidth: 150, maxHeight: 88)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.5), radius: 6, y: 3)
                .onDrag { NSItemProvider(object: shot.url as NSURL) }
                .help("Sürükleyip istediğin yere bırak")

            VStack(alignment: .leading, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Ekran görüntüsü").font(.system(size: 13, weight: .semibold))
                    Text("Sürükle ya da bir işlem seç").font(.system(size: 11)).foregroundStyle(.secondary)
                }
                HStack(spacing: 6) {
                    Pill("Kopyala", tint: .blue) { s.copy(shot) }
                    Pill("Rafa koy", tint: .white) {
                        model.shelf.add([shot.url])
                        s.dismiss()
                    }
                    Pill("Aç", tint: .white) { s.open(shot) }
                    Pill("Sil", tint: .red) { s.trash(shot) }
                        .help("Çöp Sepeti'ne taşır")
                }
            }
            Spacer(minLength: 0)
        }
        .foregroundStyle(.white)
    }
}

private struct SystemCard: View {
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
                Pill(model.keepAwake.isActive ? "☕ Uyanık" : "Uyanık tut",
                     tint: model.keepAwake.isActive ? .orange : .gray) { model.keepAwake.toggle() }
                    .help(model.keepAwake.remainingText ?? String(localized: "Mac uykuya girmesin"))
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

private struct RingGauge: View {
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

private struct BatteryCard: View {
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
                    Chart(data, id: \.date) { s in
                        AreaMark(x: .value("Saat", s.date), y: .value("Seviye", s.level))
                            .foregroundStyle(LinearGradient(colors: [.green.opacity(0.5), .green.opacity(0.02)],
                                                            startPoint: .top, endPoint: .bottom))
                            .interpolationMethod(.monotone)
                        LineMark(x: .value("Saat", s.date), y: .value("Seviye", s.level))
                            .foregroundStyle(.green)
                            .interpolationMethod(.monotone)
                    }
                    .chartYScale(domain: 0...100)
                    .chartYAxis {
                        AxisMarks(values: [0, 50, 100]) { v in
                            AxisGridLine().foregroundStyle(.white.opacity(0.1))
                            AxisValueLabel { Text("\(v.as(Int.self) ?? 0)").font(.system(size: 8)) }
                        }
                    }
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .hour, count: 6)) { _ in
                            AxisValueLabel(format: .dateTime.hour()).font(.system(size: 8))
                        }
                    }
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

private struct InfoRow: View {
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

private struct ClipboardCard: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var clip: ClipboardMonitor

    var body: some View {
        if !model.settings.clipboardHistory {
            VStack(spacing: 8) {
                Text("Pano geçmişi kapalı").font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Pill("Aç", tint: .blue) { model.settings.clipboardHistory = true }
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

private struct ClipRow: View {
    @EnvironmentObject var model: IslandModel
    let item: ClipItem
    @State private var hover = false

    var body: some View {
        HStack(spacing: 8) {
            Group {
                switch item.content {
                case .text:
                    Image(systemName: "text.alignleft").font(.system(size: 11)).foregroundStyle(.secondary)
                case .image(let thumb, _, _):
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                        .clipShape(RoundedRectangle(cornerRadius: 4))
                }
            }
            .frame(width: 22, height: 22)

            Text(item.preview).font(.system(size: 12)).lineLimit(1).truncationMode(.tail)
            Spacer(minLength: 8)
            if hover {
                Button { withAnimation(.snappy) { model.clipboard.remove(item) } } label: {
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
            withAnimation(.snappy) { model.clipboard.copy(item) }
            model.showActivity(.init(icon: "doc.on.doc.fill", tint: .blue, title: String(localized: "Panoya kopyalandı"), trailing: "✓"), duration: 1.5)
        }
        .help("Tıkla: tekrar kopyala")
    }
}

private struct CalendarCard: View {
    @EnvironmentObject var model: IslandModel

    var body: some View {
        let cal = model.calendar
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

private struct EventRow: View {
    @EnvironmentObject var model: IslandModel
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
                Pill("Katıl", tint: .green) { model.calendar.join(event) }
            }
        }
        .padding(.horizontal, 8).padding(.vertical, 3)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(.white.opacity(hover ? 0.08 : 0)))
        .contentShape(Rectangle())
        .onHover { hover = $0 }
        .onTapGesture { model.calendar.openInCalendar(event) }
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

private struct ShelfCard: View {
    @EnvironmentObject var model: IslandModel
    @State private var shelfTargeted = false
    @State private var airdropTargeted = false

    var body: some View {
        let shelf = model.shelf
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

private struct ShelfItemView: View {
    @EnvironmentObject var model: IslandModel
    let url: URL
    @State private var hover = false

    var body: some View {
        VStack(spacing: 3) {
            Image(nsImage: model.shelf.icon(for: url))
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
                Button { withAnimation(.snappy) { model.shelf.remove(url) } } label: {
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
        .onTapGesture(count: 2) { model.shelf.open(url) }
        .contextMenu {
            Button("Aç") { model.shelf.open(url) }
            Button("Finder'da göster") { model.shelf.reveal(url) }
            Button("AirDrop ile gönder") { model.airdrop.share([url]) }
            Divider()
            Button("Raftan kaldır") { model.shelf.remove(url) }
        }
    }
}

private struct AirDropGlyph: View {
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

private struct Artwork: View {
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

private struct BlurFade: ViewModifier {
    let radius: CGFloat
    let opacity: Double

    func body(content: Content) -> some View {
        content.blur(radius: radius).opacity(opacity)
    }
}

private extension AnyTransition {
    static let blurFade = AnyTransition.modifier(
        active: BlurFade(radius: 8, opacity: 0),
        identity: BlurFade(radius: 0, opacity: 1)
    )

    static let artworkSwap = AnyTransition.asymmetric(
        insertion: .scale(scale: 1.25).combined(with: .blurFade),
        removal: .scale(scale: 0.85).combined(with: .blurFade)
    )

    static func trackSlide(_ direction: Int) -> AnyTransition {
        let d = CGFloat(direction)
        return .asymmetric(
            insertion: .offset(x: 28 * d).combined(with: .blurFade),
            removal: .offset(x: -28 * d).combined(with: .blurFade)
        )
    }
}

private struct ProgressBar: View {
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

private struct IconButton: View {
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

private struct Pill: View {
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

struct NotchShape: Shape {
    var topRadius: CGFloat
    var bottomRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topRadius, bottomRadius) }
        set { topRadius = newValue.first; bottomRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let w = rect.width, h = rect.height
        let t = topRadius, b = min(bottomRadius, h / 2)
        var p = Path()
        p.move(to: .zero)
        p.addQuadCurve(to: CGPoint(x: t, y: t), control: CGPoint(x: t, y: 0))
        p.addLine(to: CGPoint(x: t, y: h - b))
        p.addQuadCurve(to: CGPoint(x: t + b, y: h), control: CGPoint(x: t, y: h))
        p.addLine(to: CGPoint(x: w - t - b, y: h))
        p.addQuadCurve(to: CGPoint(x: w - t, y: h - b), control: CGPoint(x: w - t, y: h))
        p.addLine(to: CGPoint(x: w - t, y: t))
        p.addQuadCurve(to: CGPoint(x: w, y: 0), control: CGPoint(x: w - t, y: 0))
        p.closeSubpath()
        return p
    }
}

func countdown(to date: Date) -> String {
    let mins = Int(ceil(date.timeIntervalSinceNow / 60))
    return mins <= 0 ? String(localized: "Şimdi") : String(localized: "\(mins) dk")
}

func formatSeconds(_ s: Int) -> String {
    String(format: "%d:%02d", max(s, 0) / 60, max(s, 0) % 60)
}
