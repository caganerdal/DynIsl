import SwiftUI
import UniformTypeIdentifiers

struct IslandView: View {
    @EnvironmentObject private var calendar: CalendarService
    @EnvironmentObject private var downloads: DownloadMonitor
    @EnvironmentObject private var hud: HUDController
    @EnvironmentObject private var media: NowPlayingService
    @EnvironmentObject private var screenshots: ScreenshotMonitor
    @EnvironmentObject private var settings: AppSettings
    @EnvironmentObject var model: IslandModel
    @State private var shown: CGSize = .zero

    var body: some View {
        let size = shown == .zero ? model.currentSize : shown
        let motion = settings.islandMotion
        let speed = settings.animationSpeed
        let calm = settings.calmMotion
        let mainAnimation: Animation = calm ? .easeOut(duration: 0.18) : motion.main(speed)
        let expanded = model.state == .expanded
        let top: CGFloat = expanded ? 14 : 6
        let compactHUD = hud.current.map { settings.hudStyle(for: $0.kind).isCompact } ?? false
        let bottom: CGFloat = expanded || model.state == .peek ? 28 : (model.state == .hud && !compactHUD) || model.state == .charging ? 18 : 10
        let glowing = settings.albumGlow && media.isPlaying
            && (model.state == .playing || (expanded && model.tab == .media))

        ZStack(alignment: .top) {
            if glowing {
                CAGlow(color: media.accent, top: top, bottom: bottom)
                    .transition(.opacity)
            }
            NotchShape(topRadius: top, bottomRadius: bottom)
                .fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
                .opacity(model.state == .idle && model.hasNotch && !settings.showPet ? 0 : 1)
                .shadow(color: .black.opacity(expanded ? 0.5 : 0), radius: 16, y: 6)

            content
                .padding(.horizontal, expanded ? 28 : 14)
                .transition(!calm && motion == .jelly ? .opacity.combined(with: .scale(scale: motion.contentScale, anchor: .top)) : .opacity)
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
        .animation(mainAnimation, value: model.state)
        .onAppear { shown = model.currentSize }
        .onChange(of: model.currentSize) { old, new in
            withAnimation(calm ? mainAnimation : motion.height(speed, growing: new.height > old.height)) { shown.height = new.height }
            withAnimation(calm ? mainAnimation : motion.width(speed, growing: new.height > old.height || (new.height == old.height && new.width > old.width))) {
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
            if settings.showPet {
                CompactRow(height: model.notchSize.height) {
                    Color.clear.frame(width: 1)
                } trailing: {
                    IslandPet(mood: model.petMood).offset(x: 4)
                }
                .help("Ada kedisi")
            }
        case .playing:
            CompactRow(height: model.notchSize.height) {
                Artwork(image: media.artwork, id: media.artworkID, size: 20, corner: 5)
            } trailing: {
                HStack(spacing: 5) {
                    CAEqualizer(color: media.accent, style: settings.equalizerStyle)
                    if settings.showPet { IslandPet(mood: model.petMood).padding(.leading, 4) }
                }
            }
        case .meeting:
            if let e = calendar.imminent {
                CompactRow(height: model.notchSize.height) {
                    Image(systemName: e.meetingURL != nil ? "video.fill" : "calendar")
                        .foregroundStyle(e.color)
                } trailing: {
                    HStack(spacing: 5) {
                        Text(countdown(to: e.start))
                            .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                            .foregroundStyle(e.color)
                    }
                }
            }
        case .download:
            if let d = downloads.summary {
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
        case .speedTest:
            CompactRow(height: model.notchSize.height) {
                Image(systemName: "gauge.with.needle.fill").foregroundStyle(.cyan)
            } trailing: {
                ProgressRing(value: nil, tint: .cyan)
            }
            .help("İnternet hız testi sürüyor")
        case .timer:
            CompactRow(height: model.notchSize.height) {
                Image(systemName: "timer").foregroundStyle(model.accent ?? .orange)
            } trailing: {
                HStack(spacing: 5) {
                    Text(formatSeconds(model.timerRemaining ?? 0))
                        .font(.system(size: 13, weight: .semibold, design: .rounded).monospacedDigit())
                        .foregroundStyle(model.accent ?? .orange)
                }
            }
        case .activity:
            if let a = model.activity {
                let style = settings.activityStyle
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
            if let info = hud.current {
                switch settings.hudStyle(for: info.kind) {
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
            if let shot = screenshots.current {
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

struct SpinningSymbol: View {
    let name: String
    let tint: Color
    @State private var appeared = false
    @State private var spin = false

    static func spins(_ name: String) -> Bool {
        name.hasPrefix("airpods") || name.hasPrefix("beats") || name == "headphones"
    }

    var body: some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .medium))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
            .rotation3DEffect(.degrees(spin ? 360 : 0), axis: (x: 0, y: 1, z: 0), perspective: 0.5)
            .animation(.linear(duration: 360.0 / 130).repeatForever(autoreverses: false), value: spin)
            .frame(width: 22, height: 20)
            .scaleEffect(appeared ? 1 : 0.4)
            .opacity(appeared ? 1 : 0)
            .onAppear {
                spin = true
                withAnimation(.spring(response: 0.45, dampingFraction: 0.6)) { appeared = true }
            }
    }
}

struct LevelRing: View {
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

struct CompactRow<L: View, T: View>: View {
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

struct ProgressRing: View {
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
                IndeterminateArc(tint: tint)
            }
        }
        .frame(width: 16, height: 16)
    }
}

struct IndeterminateArc: View {
    let tint: Color
    @State private var spin = false

    var body: some View {
        Circle()
            .trim(from: 0, to: 0.3)
            .stroke(tint, style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
            .rotationEffect(.degrees(spin ? 360 : 0))
            .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: spin)
            .onAppear { spin = true }
    }
}

struct LevelHUD: View {
    @EnvironmentObject private var hud: HUDController
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
                hud.setLevel($0)
            }
        }
        .foregroundStyle(.white)
        .animation(.snappy(duration: 0.2), value: shown)
    }
}

struct HUDSlider: View {
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

struct ScreenshotPeek: View {
    @EnvironmentObject private var screenshots: ScreenshotMonitor
    @EnvironmentObject private var shelf: ShelfStore
    let shot: Screenshot

    var body: some View {
        let s = screenshots
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
                        shelf.add([shot.url])
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

extension AnyTransition {
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
