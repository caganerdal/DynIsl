import AppKit
import SwiftUI

enum IslandTheme: String, CaseIterable, Identifiable {
    case black, melt, glass
    var id: String { rawValue }

    var title: String {
        switch self {
        case .black: return String(localized: "Siyah")
        case .melt: return String(localized: "Erime")
        case .glass: return String(localized: "Cam")
        }
    }
}

enum AccentMode: String, CaseIterable, Identifiable {
    case classic, system, album, custom
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return String(localized: "Klasik")
        case .system: return String(localized: "macOS vurgu rengi")
        case .album: return String(localized: "Çalan şarkının rengi")
        case .custom: return String(localized: "Özel")
        }
    }
}

private struct IslandAccentKey: EnvironmentKey {
    static let defaultValue: Color? = nil
}

extension EnvironmentValues {
    var islandAccent: Color? {
        get { self[IslandAccentKey.self] }
        set { self[IslandAccentKey.self] = newValue }
    }
}

extension Color {
    init?(hex: String) {
        let s = hex.trimmingCharacters(in: CharacterSet(charactersIn: "# "))
        guard s.count == 6, let v = UInt32(s, radix: 16) else { return nil }
        self.init(red: Double((v >> 16) & 0xFF) / 255, green: Double((v >> 8) & 0xFF) / 255, blue: Double(v & 0xFF) / 255)
    }

    var hex: String {
        guard let c = NSColor(self).usingColorSpace(.sRGB) else { return "0A84FF" }
        return String(format: "%02X%02X%02X", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }
}

struct VisualEffect: NSViewRepresentable {
    var material: NSVisualEffectView.Material
    var blending: NSVisualEffectView.BlendingMode = .behindWindow

    final class PassThrough: NSVisualEffectView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }

    func makeNSView(context: Context) -> NSVisualEffectView {
        let v = PassThrough()
        v.state = .active
        v.material = material
        v.blendingMode = blending
        return v
    }

    func updateNSView(_ v: NSVisualEffectView, context: Context) {
        v.material = material
        v.blendingMode = blending
    }
}

struct IslandBackground: View {
    let theme: IslandTheme
    let hasNotch: Bool
    let notchHeight: CGFloat
    let top: CGFloat
    let bottom: CGFloat
    var clarity: Double = 0.7

    private var c: Double { min(max(clarity, 0), 1) }
    private var dim: Double { 0.5 - 0.44 * c }

    var body: some View {
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)
        GeometryReader { g in
            let h = max(g.size.height, 1)
            if effective == .black || h <= notchHeight + 2 {
                shape.fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
            } else {
                let band = effective == .melt ? min((notchHeight + 28) / h, 1) : 0
                ZStack {
                    glass(shape)
                    if effective == .melt { notchBand(height: h).clipShape(shape) }
                    shape.stroke(Color.white.opacity(0.12), lineWidth: 6)
                        .blur(radius: 4)
                        .clipShape(shape)
                        .mask(fadeFrom(band))
                    shape.stroke(LinearGradient(stops: [
                        .init(color: .white.opacity(0.10), location: 0),
                        .init(color: .white.opacity(0.22), location: 0.6),
                        .init(color: .white.opacity(0.55), location: 1),
                    ], startPoint: .top, endPoint: .bottom), lineWidth: 1)
                    .mask(fadeFrom(band))
                }
            }
        }
    }

    @ViewBuilder private func glass(_ shape: NotchShape) -> some View {
        if #available(macOS 26.0, *) {
            let base: Glass = c < 0.35 ? .regular : .clear
            Color.clear.glassEffect(base.tint(.black.opacity(effective == .glass ? dim * 0.7 : dim)), in: shape)
        } else {
            ZStack {
                VisualEffect(material: .hudWindow)
                Color.black.opacity(dim)
            }
            .clipShape(shape)
        }
    }

    private func fadeFrom(_ start: CGFloat) -> LinearGradient {
        LinearGradient(stops: [
            .init(color: .clear, location: 0),
            .init(color: .clear, location: start),
            .init(color: .black, location: min(start + 0.12, 1)),
        ], startPoint: .top, endPoint: .bottom)
    }

    private func notchBand(height h: CGFloat) -> some View {
        Color.black.mask(LinearGradient(stops: [
            .init(color: .black, location: 0),
            .init(color: .black, location: min(notchHeight / h, 1)),
            .init(color: .clear, location: min((notchHeight + 28) / h, 1)),
        ], startPoint: .top, endPoint: .bottom))
    }

    private var effective: IslandTheme {
        theme == .glass && hasNotch ? .melt : theme
    }
}

struct GlassCardBackground: ViewModifier {
    let radius: CGFloat
    @AppStorage("glassWindows") private var glass = true

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        if #available(macOS 26.0, *), glass {
            content.glassEffect(.regular, in: shape)
        } else {
            content
                .background(shape.fill(.background.secondary))
                .overlay(shape.stroke(.separator.opacity(0.5)))
        }
    }
}

struct GlassWindowBackground: ViewModifier {
    @AppStorage("glassWindows") private var glass = true
    @Environment(\.colorScheme) private var scheme

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            content.background(backdrop.ignoresSafeArea())
        } else {
            content
        }
    }

    @available(macOS 26.0, *)
    private var backdrop: some View {
        let dark: [Color] = [
            .init(hex: "0A0E24")!, .init(hex: "3A1F9E")!, .init(hex: "07304F")!,
            .init(hex: "5B2196")!, .init(hex: "101638")!, .init(hex: "0E6A8A")!,
            .init(hex: "080C1E")!, .init(hex: "8A1F6E")!, .init(hex: "0B2A4A")!,
        ]
        let light: [Color] = [
            .init(hex: "DCE3FF")!, .init(hex: "EAD9FF")!, .init(hex: "CFEAFF")!,
            .init(hex: "F1D9F5")!, .init(hex: "F6F7FF")!, .init(hex: "C9F0F2")!,
            .init(hex: "DFE6FF")!, .init(hex: "FFDCEB")!, .init(hex: "D6E8FF")!,
        ]
        return MeshGradient(width: 3, height: 3, points: [
            [0, 0], [0.5, 0], [1, 0],
            [0, 0.5], [0.55, 0.45], [1, 0.5],
            [0, 1], [0.5, 1], [1, 1],
        ], colors: scheme == .dark ? dark : light)
    }
}

struct GlassButtonStyle: ViewModifier {
    let prominent: Bool
    @AppStorage("glassWindows") private var glass = true

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            if prominent { content.buttonStyle(.glassProminent) } else { content.buttonStyle(.glass) }
        } else {
            content
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 14) -> some View { modifier(GlassCardBackground(radius: radius)) }
    func glassWindowBackground() -> some View { modifier(GlassWindowBackground()) }
    func glassButton(prominent: Bool = false) -> some View { modifier(GlassButtonStyle(prominent: prominent)) }
}

var supportsLiquidGlass: Bool {
    if #available(macOS 26.0, *) { return true }
    return false
}
