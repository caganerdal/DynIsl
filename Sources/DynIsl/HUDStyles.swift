import SwiftUI

extension HUDInfo {
    var shown: Double { muted ? 0 : level }
    var tint: Color { kind == .brightness ? .yellow : .white }
    var percentText: String { muted ? "Sessiz" : "\(Int((shown * 100).rounded()))" }
}

struct HUDSymbol: View {
    let info: HUDInfo

    var body: some View {
        Group {
            switch info.kind {
            case .volume:
                if info.muted || info.level == 0 {
                    Image(systemName: "speaker.slash.fill").foregroundStyle(.white.opacity(0.7))
                } else {
                    Image(systemName: "speaker.wave.3.fill", variableValue: info.level)
                }
            case .brightness:
                Image(systemName: info.level < 0.5 ? "sun.min.fill" : "sun.max.fill")
                    .foregroundStyle(.yellow)
                    .rotationEffect(.degrees(info.level * 180))
                    .scaleEffect(0.85 + info.level * 0.2)
            }
        }
        .font(.system(size: 14, weight: .semibold))
        .frame(width: 24)
        .contentTransition(.symbolEffect(.replace))
        .animation(.spring(response: 0.35, dampingFraction: 0.6), value: info.level)
    }
}

struct MinimalBar: View {
    let info: HUDInfo

    var body: some View {
        HStack(spacing: 8) {
            ZStack(alignment: .leading) {
                Capsule().fill(.white.opacity(0.18))
                Capsule().fill(info.tint.opacity(info.muted ? 0.35 : 1))
                    .frame(width: max(64 * info.shown, info.shown > 0 ? 5 : 0))
                    .shadow(color: info.tint.opacity(0.6), radius: 3)
            }
            .frame(width: 64, height: 5)
            Text(info.muted ? "–" : "\(Int((info.shown * 100).rounded()))")
                .font(.system(size: 11, weight: .semibold, design: .rounded).monospacedDigit())
                .frame(width: 24, alignment: .trailing)
                .contentTransition(.numericText(value: info.shown))
        }
        .animation(.snappy(duration: 0.22), value: info.shown)
    }
}

struct HUDRing: View {
    let info: HUDInfo

    var body: some View {
        HStack(spacing: 6) {
            Text(info.muted ? "–" : "\(Int((info.shown * 100).rounded()))")
                .font(.system(size: 12, weight: .semibold, design: .rounded).monospacedDigit())
                .contentTransition(.numericText(value: info.shown))
            ZStack {
                Circle().stroke(info.tint.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0, to: info.shown)
                    .stroke(info.tint, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
            }
            .frame(width: 17, height: 17)
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.7), value: info.shown)
    }
}

struct SegmentBar: View {
    let info: HUDInfo
    private let count = 16

    var body: some View {
        let lit = Int((info.shown * Double(count)).rounded())
        HStack(spacing: 2) {
            ForEach(0..<count, id: \.self) { i in
                let on = i < lit
                RoundedRectangle(cornerRadius: 1.2, style: .continuous)
                    .fill(on ? segmentColor(i) : .white.opacity(0.14))
                    .frame(width: 4, height: on ? 13 : 9)
                    .scaleEffect(y: on && i == lit - 1 ? 1.15 : 1, anchor: .bottom)
                    .animation(.spring(response: 0.28, dampingFraction: 0.55).delay(Double(i) * 0.008), value: on)
            }
        }
        .frame(height: 16, alignment: .bottom)
    }

    private func segmentColor(_ i: Int) -> Color {
        let t = Double(i) / Double(count - 1)
        if info.kind == .brightness { return Color(hue: 0.15 - 0.06 * t, saturation: 0.55 + 0.4 * t, brightness: 1) }
        return Color(hue: 0.55 - 0.08 * t, saturation: 0.15 + 0.5 * t, brightness: 1)
    }
}

struct LiquidHUD: View {
    @EnvironmentObject var model: IslandModel
    let info: HUDInfo
    let notchHeight: CGFloat
    @State private var shown: Double = 0

    var body: some View {
        GeometryReader { g in
            ZStack(alignment: .topLeading) {
                TimelineView(.animation(minimumInterval: 1.0 / 40)) { ctx in
                    let phase = ctx.date.timeIntervalSinceReferenceDate * 3.2
                    ZStack {
                        LiquidShape(level: shown, phase: phase + 1.6, amplitude: 5)
                            .fill(colors[0].opacity(0.35))
                        LiquidShape(level: shown, phase: phase, amplitude: 4)
                            .fill(LinearGradient(colors: colors, startPoint: .leading, endPoint: .trailing))
                    }
                }
                HStack {
                    HUDSymbol(info: info)
                    Spacer()
                    Text(info.percentText)
                        .font(.system(size: 13, weight: .bold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText(value: info.shown))
                }
                .shadow(color: .black.opacity(0.5), radius: 2)
                .padding(.horizontal, 14)
                .frame(height: notchHeight)
            }
            .contentShape(Rectangle())
            .gesture(DragGesture(minimumDistance: 0).onChanged { v in
                model.hud.setLevel(v.location.x / max(g.size.width, 1))
            })
        }
        .foregroundStyle(.white)
        .onAppear { withAnimation(.spring(response: 0.5, dampingFraction: 0.7)) { shown = info.shown } }
        .onChange(of: info.shown) { _, v in withAnimation(.spring(response: 0.45, dampingFraction: 0.65)) { shown = v } }
        .animation(.snappy(duration: 0.2), value: info.shown)
    }

    private var colors: [Color] {
        info.kind == .brightness
            ? [Color(red: 1, green: 0.62, blue: 0.1), Color(red: 1, green: 0.86, blue: 0.3)]
            : [Color(red: 0.1, green: 0.45, blue: 1), Color(red: 0.3, green: 0.85, blue: 1)]
    }
}

struct LiquidShape: Shape {
    var level: Double
    var phase: Double
    var amplitude: CGFloat

    var animatableData: Double {
        get { level }
        set { level = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var p = Path()
        guard level > 0 else { return p }
        let x0 = rect.width * level
        let amp = level >= 1 ? 0 : amplitude
        p.move(to: .zero)
        p.addLine(to: CGPoint(x: x0, y: 0))
        let steps = 24
        for i in 0...steps {
            let y = rect.height * CGFloat(i) / CGFloat(steps)
            let x = x0 + amp * CGFloat(sin(Double(y) / 9 + phase))
            p.addLine(to: CGPoint(x: x, y: y))
        }
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}
