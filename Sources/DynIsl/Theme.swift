import AppKit
import SwiftUI

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

enum IslandMotion: String, CaseIterable, Identifiable {
    case classic, jelly, drop, quick
    var id: String { rawValue }

    var title: String {
        switch self {
        case .classic: return String(localized: "Klasik")
        case .jelly: return String(localized: "Jöle")
        case .drop: return String(localized: "Damla")
        case .quick: return String(localized: "Hızlı")
        }
    }

    func main(_ speed: Double) -> Animation {
        switch self {
        case .classic: return .spring(response: 0.42 * speed, dampingFraction: 0.78)
        case .jelly: return .spring(response: 0.55 * speed, dampingFraction: 0.5)
        case .drop: return .spring(response: 0.42 * speed, dampingFraction: 0.8)
        case .quick: return .spring(response: 0.24 * speed, dampingFraction: 1)
        }
    }

    func width(_ speed: Double, growing: Bool) -> Animation {
        guard self == .drop else { return main(speed) }
        return growing
            ? .spring(response: 0.5 * speed, dampingFraction: 0.82).delay(0.07 * speed)
            : .spring(response: 0.32 * speed, dampingFraction: 0.9)
    }

    func height(_ speed: Double, growing: Bool) -> Animation {
        guard self == .drop else { return main(speed) }
        return growing
            ? .spring(response: 0.34 * speed, dampingFraction: 0.7)
            : .spring(response: 0.42 * speed, dampingFraction: 0.85).delay(0.07 * speed)
    }

    var contentScale: CGFloat { self == .jelly ? 0.84 : self == .quick ? 0.97 : 0.92 }
}

struct PressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.9 : 1)
            .opacity(configuration.isPressed ? 0.8 : 1)
            .animation(.spring(response: 0.18, dampingFraction: 1), value: configuration.isPressed)
    }
}

extension ButtonStyle where Self == PressableStyle {
    static var pressable: PressableStyle { PressableStyle() }
}

struct PageScroll<Content: View, Bar: View>: View {
    let content: Content
    let bar: Bar

    init(@ViewBuilder content: () -> Content, @ViewBuilder bar: () -> Bar) {
        self.content = content()
        self.bar = bar()
    }

    var body: some View {
        ScrollView {
            content
                .padding(24)
                .frame(maxWidth: .infinity, alignment: .topLeading)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) { bar }
    }
}

extension PageScroll where Bar == EmptyView {
    init(@ViewBuilder content: () -> Content) {
        self.init(content: content, bar: { EmptyView() })
    }
}

extension View {
    @ViewBuilder func floatingGlassBar() -> some View {
        let shaped = padding(.leading, 18).padding(.trailing, 8).padding(.vertical, 8)
        Group {
            if #available(macOS 26.0, *) {
                shaped.glassEffect(.regular, in: Capsule())
            } else {
                shaped
                    .background(.regularMaterial, in: Capsule())
                    .overlay(Capsule().stroke(.separator.opacity(0.6)))
            }
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 16)
    }

    @ViewBuilder func glassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26.0, *) {
            if prominent { buttonStyle(.glassProminent) } else { buttonStyle(.glass) }
        } else {
            if prominent { buttonStyle(.borderedProminent) } else { buttonStyle(.bordered) }
        }
    }
}
