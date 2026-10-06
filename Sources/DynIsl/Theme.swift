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
