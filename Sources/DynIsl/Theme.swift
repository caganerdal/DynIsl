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

    var body: some View {
        let shape = NotchShape(topRadius: top, bottomRadius: bottom)
        switch effective {
        case .black:
            shape.fill(Color(.sRGB, red: 0, green: 0, blue: 0, opacity: 1))
        case .melt:
            GeometryReader { g in
                let h = max(g.size.height, 1)
                if h <= notchHeight + 2 {
                    Color.black
                } else {
                    let solid = min(notchHeight / h, 1)
                    let fade = min((notchHeight + 46) / h, 1)
                    ZStack {
                        VisualEffect(material: .hudWindow)
                        Color.black.mask(LinearGradient(stops: [
                            .init(color: .black, location: 0),
                            .init(color: .black, location: solid),
                            .init(color: .black.opacity(0.62), location: fade),
                            .init(color: .black.opacity(0.42), location: 1),
                        ], startPoint: .top, endPoint: .bottom))
                    }
                }
            }
            .clipShape(shape)
        case .glass:
            if #available(macOS 26.0, *) {
                Color.clear.glassEffect(.regular.tint(.black.opacity(0.45)), in: shape)
            } else {
                ZStack {
                    VisualEffect(material: .hudWindow)
                    Color.black.opacity(0.35)
                }
                .clipShape(shape)
            }
        }
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

    func body(content: Content) -> some View {
        if #available(macOS 26.0, *), glass {
            content.background(VisualEffect(material: .underWindowBackground).ignoresSafeArea())
        } else {
            content
        }
    }
}

extension View {
    func glassCard(radius: CGFloat = 14) -> some View { modifier(GlassCardBackground(radius: radius)) }
    func glassWindowBackground() -> some View { modifier(GlassWindowBackground()) }
}

var supportsLiquidGlass: Bool {
    if #available(macOS 26.0, *) { return true }
    return false
}
