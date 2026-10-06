import AppKit
import SwiftUI

@MainActor
enum OnboardingWindow {
    private static var window: NSWindow?
    private static var delegate: Closer?
    static let doneKey = "onboardingDone"

    static func showIfNeeded(model: IslandModel) {
        guard !UserDefaults.standard.bool(forKey: doneKey) else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { show(model: model) }
    }

    static func show(model: IslandModel) {
        if window == nil {
            let w = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 470),
                             styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
            w.titlebarAppearsTransparent = true
            w.titleVisibility = .hidden
            w.isMovableByWindowBackground = true
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: OnboardingView(settings: model.settings) { finish() }
                .environmentObject(model))
            let d = Closer { UserDefaults.standard.set(true, forKey: doneKey); window = nil }
            w.delegate = d
            delegate = d
            w.center()
            window = w
        }
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private static func finish() {
        UserDefaults.standard.set(true, forKey: doneKey)
        window?.close()
    }

    private final class Closer: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

private struct OnboardingView: View {
    @EnvironmentObject var model: IslandModel
    @ObservedObject var settings: AppSettings
    let done: () -> Void
    @State private var page = 0
    private let pages = 4

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch page {
                case 0: welcome
                case 1: permissions
                case 2: personalize
                default: tips
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 40)
            .padding(.top, 36)
            .transition(.asymmetric(insertion: .move(edge: .trailing).combined(with: .opacity),
                                    removal: .move(edge: .leading).combined(with: .opacity)))
            .id(page)

            HStack {
                if page > 0 {
                    Button("Geri") { withAnimation(.snappy) { page -= 1 } }
                        .glassButton()
                } else {
                    Button("Atla") { done() }.buttonStyle(.borderless).foregroundStyle(.secondary)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<pages, id: \.self) { i in
                        Capsule().fill(i == page ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == page ? 18 : 6, height: 6)
                    }
                }
                .animation(.snappy, value: page)
                Spacer()
                if page < pages - 1 {
                    Button("İleri") { withAnimation(.snappy) { page += 1 } }
                        .keyboardShortcut(.defaultAction)
                        .glassButton(prominent: true)
                } else {
                    Button("Başla") { done() }
                        .keyboardShortcut(.defaultAction)
                        .glassButton(prominent: true)
                }
            }
            .controlSize(.large)
            .padding(20)
        }
        .frame(width: 600, height: 470)
        .glassWindowBackground()
    }

    private var welcome: some View {
        VStack(spacing: 18) {
            Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 96, height: 96)
            Text("DynIsl'a hoş geldin").font(.largeTitle.weight(.bold))
            Text("Çentiğin artık işe yarıyor. Birkaç adımda kuralım.")
                .font(.title3).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 12) {
                Feature(icon: "music.note", tint: .pink, title: "Müzik ve canlı bildirimler",
                        text: "Çalan şarkı, AirPods, şarj, toplantılar ve daha fazlası çentikte.")
                Feature(icon: "speaker.wave.2.fill", tint: .blue, title: "Ses ve parlaklık göstergesi",
                        text: "macOS'unkinin yerine adada, istediğin stilde.")
                Feature(icon: "gauge.with.dots.needle.67percent", tint: .green, title: "Sistem Paneli",
                        text: "İşlemci, bellek, pil, dosya dönüştürme ve masaüstü düzenleme.")
            }
            .padding(.top, 8)
        }
    }

    private var permissions: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("İzinler").font(.title.weight(.bold))
            Text("Hepsi isteğe bağlı. Vermediğin izin sadece ilgili özelliği kapatır.")
                .foregroundStyle(.secondary)
            VStack(spacing: 10) {
                Permission(icon: "keyboard", tint: .blue, title: "Erişilebilirlik",
                           why: "Ses ve parlaklık tuşlarını yakalayıp adada göstermek için. Sadece bu tuşlar dinlenir.",
                           ok: !model.hud.needsPermission) {
                    model.hud.requestPermission()
                    model.hud.openAccessibilitySettings()
                }
                Permission(icon: "calendar", tint: .red, title: "Takvim",
                           why: "Yaklaşan toplantıları haber vermek için.",
                           ok: model.calendar.access == .granted) {
                    model.calendar.access == .unknown ? model.calendar.requestAccess() : model.calendar.openSettings()
                }
                Permission(icon: "location.fill", tint: .teal, title: "Konum",
                           why: "Hava durumu için, yaklaşık 1 km'ye yuvarlanır. İstersen şehir de yazabilirsin.",
                           ok: model.weather.now != nil || !settings.weatherCity.isEmpty) {
                    model.weather.openLocationSettings()
                }
                Permission(icon: "moon.fill", tint: .indigo, title: "Tam Disk Erişimi",
                           why: "Sadece etkin Odak modunu okumak için. İstemezsen atlayabilirsin.",
                           ok: !model.focus.needsPermission) {
                    model.focus.openPermissionSettings()
                }
            }
            Text("Spotify ve Apple Music kontrolü için izin, ilk şarkı çaldığında macOS tarafından sorulur.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private var personalize: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Sana göre ayarla").font(.title.weight(.bold))
            Text("Bunların hepsini sonra Ayarlar'dan değiştirebilirsin.").foregroundStyle(.secondary)
            Form {
                Picker("Ada nasıl açılsın", selection: $settings.openOnHover) {
                    Text("Üzerine gelince").tag(true)
                    Text("Tıklayınca").tag(false)
                }
                Toggle("Ada kedisi", isOn: $settings.showPet)
                Toggle("Ses ve parlaklığı adada göster", isOn: $settings.replaceHUD)
                if settings.replaceHUD {
                    HStack {
                        Picker("Gösterge stili", selection: Binding(
                            get: { settings.volumeHUDStyle },
                            set: { settings.volumeHUDStyle = $0; settings.brightnessHUDStyle = $0 }
                        )) {
                            ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
                        }
                        Button("Dene") { model.hud.preview(.volume) }
                    }
                }
                Picker("Menü çubuğu", selection: $settings.menuBarMode) {
                    Text("Simge ve CPU/RAM").tag("both")
                    Text("Sadece simge").tag("icon")
                    Text("Sadece CPU/RAM").tag("stats")
                }
            }
            .formStyle(.grouped)
            .scrollDisabled(true)
            .padding(.horizontal, -20)
        }
    }

    private var tips: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Hazırsın 🎉").font(.title.weight(.bold))
            VStack(alignment: .leading, spacing: 12) {
                Feature(icon: "cursorarrow.rays", tint: .orange, title: "Çentiğe gel ya da tıkla",
                        text: "Ada açılır: müzik, takvim, raf, pano, sistem ve pil sekmeleri.")
                Feature(icon: "tray.and.arrow.down.fill", tint: .purple, title: "Dosyaları adaya sürükle",
                        text: "Rafa bırak, AirDrop'la ya da JPG'ye çevir, küçült, PDF yap.")
                Feature(icon: "menubar.rectangle", tint: .gray, title: "Menü çubuğu",
                        text: "Sistem Paneli, Uyanık tut, Sunum modu (⌥⌘P) ve Ayarlar burada.")
                Feature(icon: "ladybug.fill", tint: .red, title: "Bir sorun mu var?",
                        text: "Menü çubuğundan \"Sorun bildir…\" ile bana ulaşabilirsin.")
            }
            Spacer()
            Text("Bu rehberi Ayarlar › Genel'den yeniden açabilirsin.")
                .font(.caption).foregroundStyle(.secondary)
        }
    }
}

private struct Feature: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let text: LocalizedStringKey

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(RoundedRectangle(cornerRadius: 9, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.headline)
                Text(text).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct Permission: View {
    let icon: String
    let tint: Color
    let title: LocalizedStringKey
    let why: LocalizedStringKey
    let ok: Bool
    let fix: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(.white)
                .frame(width: 30, height: 30)
                .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(tint.gradient))
            VStack(alignment: .leading, spacing: 1) {
                Text(title).font(.callout.weight(.semibold))
                Text(why).font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 12)
            if ok {
                Label("Verildi", systemImage: "checkmark.circle.fill").foregroundStyle(.green).labelStyle(.iconOnly)
                    .font(.title3)
            } else {
                Button("İzin ver", action: fix)
            }
        }
        .padding(10)
        .glassCard(radius: 10)
    }
}
