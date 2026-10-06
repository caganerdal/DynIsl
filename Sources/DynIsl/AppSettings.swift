import AppKit
import SwiftUI
import ServiceManagement

@MainActor
final class AppSettings: ObservableObject {
    private let d = UserDefaults.standard

    @Published var openOnHover: Bool { didSet { d.set(openOnHover, forKey: "openOnHover") } }
    @Published var callMode: Bool { didSet { d.set(callMode, forKey: "callMode") } }
    @Published var hideFromCapture: Bool { didSet { d.set(hideFromCapture, forKey: "hideFromCapture") } }
    @Published var replaceHUD: Bool { didSet { d.set(replaceHUD, forKey: "replaceHUD") } }
    @Published var volumeStep: Int { didSet { d.set(volumeStep, forKey: "volumeStep") } }
    @Published var volumeHUDStyle: HUDStyle { didSet { d.set(volumeHUDStyle.rawValue, forKey: "volumeHUDStyle") } }
    @Published var brightnessHUDStyle: HUDStyle { didSet { d.set(brightnessHUDStyle.rawValue, forKey: "brightnessHUDStyle") } }
    func hudStyle(for kind: HUDInfo.Kind) -> HUDStyle { kind == .volume ? volumeHUDStyle : brightnessHUDStyle }
    @Published var menuBarMode: String { didSet { d.set(menuBarMode, forKey: "menuBarMode") } }
    var showsIconItem: Bool { menuBarMode != "stats" }
    var showsStatsItem: Bool { menuBarMode != "icon" }

    @Published var notifyBattery: Bool { didSet { d.set(notifyBattery, forKey: "notifyBattery") } }
    @Published var notifyBluetooth: Bool { didSet { d.set(notifyBluetooth, forKey: "notifyBluetooth") } }
    @Published var airPodsBatteryAlert: Bool { didSet { d.set(airPodsBatteryAlert, forKey: "airPodsBatteryAlert") } }
    @Published var chargeLimitAlert: Bool { didSet { d.set(chargeLimitAlert, forKey: "chargeLimitAlert") } }
    @Published var chargeLimit: Int { didSet { d.set(chargeLimit, forKey: "chargeLimit") } }
    @Published var fullPluggedAlert: Bool { didSet { d.set(fullPluggedAlert, forKey: "fullPluggedAlert") } }

    @Published var notifyCalendar: Bool { didSet { d.set(notifyCalendar, forKey: "notifyCalendar") } }
    @Published var calendarLeadMinutes: Int { didSet { d.set(calendarLeadMinutes, forKey: "calendarLeadMinutes") } }
    @Published var notifyFocus: Bool { didSet { d.set(notifyFocus, forKey: "notifyFocus") } }
    @Published var notifyNetwork: Bool { didSet { d.set(notifyNetwork, forKey: "notifyNetwork") } }
    @Published var checkUpdates: Bool { didSet { d.set(checkUpdates, forKey: "checkUpdates") } }
    @Published var showPrivacy: Bool { didSet { d.set(showPrivacy, forKey: "showPrivacy") } }
    @Published var showDownloads: Bool { didSet { d.set(showDownloads, forKey: "showDownloads") } }
    @Published var rainAlerts: Bool { didSet { d.set(rainAlerts, forKey: "rainAlerts") } }
    @Published var systemAlerts: Bool { didSet { d.set(systemAlerts, forKey: "systemAlerts") } }
    @Published var alertDisk: Bool { didSet { d.set(alertDisk, forKey: "alertDisk") } }
    @Published var alertMemory: Bool { didSet { d.set(alertMemory, forKey: "alertMemory") } }
    @Published var alertThermal: Bool { didSet { d.set(alertThermal, forKey: "alertThermal") } }
    @Published var alertBatteryHealth: Bool { didSet { d.set(alertBatteryHealth, forKey: "alertBatteryHealth") } }

    @Published var downloadsToShelf: Bool { didSet { d.set(downloadsToShelf, forKey: "downloadsToShelf") } }
    @Published var clipboardHistory: Bool { didSet { d.set(clipboardHistory, forKey: "clipboardHistory") } }
    @Published var screenshotPreview: Bool { didSet { d.set(screenshotPreview, forKey: "screenshotPreview") } }
    @Published var screenshotsToShelf: Bool { didSet { d.set(screenshotsToShelf, forKey: "screenshotsToShelf") } }
    @Published var showWeather: Bool { didSet { d.set(showWeather, forKey: "showWeather") } }
    @Published var weatherCity: String { didSet { d.set(weatherCity, forKey: "weatherCity") } }

    @Published var islandWidth: Int { didSet { d.set(islandWidth, forKey: "islandWidth") } }
    @Published var animationSpeed: Double { didSet { d.set(animationSpeed, forKey: "animationSpeed") } }
    @Published var albumGlow: Bool { didSet { d.set(albumGlow, forKey: "albumGlow") } }
    @Published var showPet: Bool { didSet { d.set(showPet, forKey: "showPet") } }
    @Published var chargeAnimation: Bool { didSet { d.set(chargeAnimation, forKey: "chargeAnimation") } }
    @Published var equalizerStyle: EqualizerStyle { didSet { d.set(equalizerStyle.rawValue, forKey: "equalizerStyle") } }
    @Published var activityStyle: ActivityStyle { didSet { d.set(activityStyle.rawValue, forKey: "activityStyle") } }
    @Published var islandMotion: IslandMotion { didSet { d.set(islandMotion.rawValue, forKey: "islandMotion") } }
    @Published var accentMode: AccentMode { didSet { d.set(accentMode.rawValue, forKey: "accentMode") } }
    @Published var accentHex: String { didSet { d.set(accentHex, forKey: "accentHex") } }
    @Published var presentationAuto: Bool { didSet { d.set(presentationAuto, forKey: "presentationAuto") } }
    @Published var presentationHideIcons: Bool { didSet { d.set(presentationHideIcons, forKey: "presentationHideIcons") } }
    @Published var screenChoice: String { didSet { d.set(screenChoice, forKey: "screenChoice") } }
    @Published var tabOrder: [IslandTab] { didSet { d.set(tabOrder.map(\.rawValue), forKey: "tabOrder") } }
    @Published var hiddenTabs: Set<IslandTab> { didSet { d.set(hiddenTabs.map(\.rawValue), forKey: "hiddenTabs") } }

    @Published private(set) var launchAtLogin = SMAppService.mainApp.status == .enabled
    @Published private(set) var launchAtLoginNeedsApproval = SMAppService.mainApp.status == .requiresApproval

    init() {
        d.register(defaults: [
            "openOnHover": true, "notifyBattery": true, "notifyBluetooth": true,
            "airPodsBatteryAlert": true, "chargeLimitAlert": true, "chargeLimit": 80, "fullPluggedAlert": true,
            "notifyCalendar": true, "calendarLeadMinutes": 10, "notifyFocus": true, "notifyNetwork": true, "checkUpdates": true,
            "showPrivacy": true, "showDownloads": true, "downloadsToShelf": true,
            "clipboardHistory": true, "screenshotPreview": true, "screenshotsToShelf": false,
            "rainAlerts": true, "systemAlerts": true,
            "alertDisk": true, "alertMemory": true, "alertThermal": true, "alertBatteryHealth": true, "showWeather": true, "weatherCity": "",
            "islandWidth": 660, "menuBarStats": true, "menuBarMode": "both", "replaceHUD": true, "volumeStep": 5, "hideFromCapture": true, "callMode": true, "animationSpeed": 1.0, "albumGlow": true, "showPet": true, "chargeAnimation": true, "accentHex": "0A84FF", "presentationAuto": true, "presentationHideIcons": true, "screenChoice": "auto",
        ])
        openOnHover = d.bool(forKey: "openOnHover")
        if d.object(forKey: "menuBarMode") == nil, !d.bool(forKey: "menuBarStats") {
            d.set("icon", forKey: "menuBarMode")
        }
        menuBarMode = d.string(forKey: "menuBarMode") ?? "both"
        replaceHUD = d.bool(forKey: "replaceHUD")
        volumeStep = d.integer(forKey: "volumeStep")
        volumeHUDStyle = HUDStyle(rawValue: d.string(forKey: "volumeHUDStyle") ?? "") ?? .classic
        brightnessHUDStyle = HUDStyle(rawValue: d.string(forKey: "brightnessHUDStyle") ?? "") ?? .classic
        hideFromCapture = d.bool(forKey: "hideFromCapture")
        callMode = d.bool(forKey: "callMode")
        notifyBattery = d.bool(forKey: "notifyBattery")
        notifyBluetooth = d.bool(forKey: "notifyBluetooth")
        airPodsBatteryAlert = d.bool(forKey: "airPodsBatteryAlert")
        chargeLimitAlert = d.bool(forKey: "chargeLimitAlert")
        chargeLimit = d.integer(forKey: "chargeLimit")
        fullPluggedAlert = d.bool(forKey: "fullPluggedAlert")

        notifyCalendar = d.bool(forKey: "notifyCalendar")
        calendarLeadMinutes = d.integer(forKey: "calendarLeadMinutes")
        notifyFocus = d.bool(forKey: "notifyFocus")
        notifyNetwork = d.bool(forKey: "notifyNetwork")
        checkUpdates = d.bool(forKey: "checkUpdates")
        showPrivacy = d.bool(forKey: "showPrivacy")
        showDownloads = d.bool(forKey: "showDownloads")
        rainAlerts = d.bool(forKey: "rainAlerts")
        systemAlerts = d.bool(forKey: "systemAlerts")
        alertDisk = d.bool(forKey: "alertDisk")
        alertMemory = d.bool(forKey: "alertMemory")
        alertThermal = d.bool(forKey: "alertThermal")
        alertBatteryHealth = d.bool(forKey: "alertBatteryHealth")
        downloadsToShelf = d.bool(forKey: "downloadsToShelf")
        clipboardHistory = d.bool(forKey: "clipboardHistory")
        screenshotPreview = d.bool(forKey: "screenshotPreview")
        screenshotsToShelf = d.bool(forKey: "screenshotsToShelf")
        showWeather = d.bool(forKey: "showWeather")
        weatherCity = d.string(forKey: "weatherCity") ?? ""
        islandWidth = d.integer(forKey: "islandWidth")
        animationSpeed = d.double(forKey: "animationSpeed")
        albumGlow = d.bool(forKey: "albumGlow")
        showPet = d.bool(forKey: "showPet")
        chargeAnimation = d.bool(forKey: "chargeAnimation")
        equalizerStyle = EqualizerStyle(rawValue: d.string(forKey: "equalizerStyle") ?? "") ?? .bars
        activityStyle = ActivityStyle(rawValue: d.string(forKey: "activityStyle") ?? "") ?? .slide
        islandMotion = IslandMotion(rawValue: d.string(forKey: "islandMotion") ?? "") ?? .classic
        accentMode = AccentMode(rawValue: d.string(forKey: "accentMode") ?? "") ?? .classic
        accentHex = d.string(forKey: "accentHex") ?? "0A84FF"
        presentationAuto = d.bool(forKey: "presentationAuto")
        presentationHideIcons = d.bool(forKey: "presentationHideIcons")
        screenChoice = d.string(forKey: "screenChoice") ?? "auto"
        let saved = (d.stringArray(forKey: "tabOrder") ?? []).compactMap(IslandTab.init(rawValue:))
        tabOrder = saved + IslandTab.allCases.filter { !saved.contains($0) }
        hiddenTabs = Set((d.stringArray(forKey: "hiddenTabs") ?? []).compactMap(IslandTab.init(rawValue:)))
    }

    var visibleTabs: [IslandTab] { tabOrder.filter { !hiddenTabs.contains($0) } }

    func moveTab(_ tab: IslandTab, by offset: Int) {
        guard let i = tabOrder.firstIndex(of: tab) else { return }
        let j = i + offset
        guard tabOrder.indices.contains(j) else { return }
        tabOrder.swapAt(i, j)
    }

    func setTab(_ tab: IslandTab, visible: Bool) {
        guard tab != .media else { return }
        if visible { hiddenTabs.remove(tab) } else { hiddenTabs.insert(tab) }
    }

    func spring(_ response: Double, _ damping: Double) -> Animation {
        .spring(response: response * animationSpeed, dampingFraction: damping)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Giriş öğesi değiştirilemedi: \(error)")
        }
        refreshLaunchAtLogin()
    }

    func refreshLaunchAtLogin() {
        let status = SMAppService.mainApp.status
        launchAtLogin = status == .enabled
        launchAtLoginNeedsApproval = status == .requiresApproval
    }
}

@MainActor
enum SettingsWindow {
    private static var window: NSWindow?
    private static var closer: Closer?

    static func show(model: IslandModel) {
        if window == nil {
            let w = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .fullSizeContentView],
                backing: .buffered, defer: false
            )
            w.title = String(localized: "DynIsl Ayarları")
            w.titlebarAppearsTransparent = true
            w.toolbarStyle = .unified
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: SettingsView(settings: model.settings)
                .environmentObject(model)
                .environmentObject(model.weather))
            w.center()
            let c = Closer {
                let old = window
                window = nil
                closer = nil
                DispatchQueue.main.async {
                    old?.delegate = nil
                    old?.contentView = nil
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) { malloc_zone_pressure_relief(nil, 0) }
                }
            }
            w.delegate = c
            closer = c
            window = w
        }
        model.settings.refreshLaunchAtLogin()
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }

    private final class Closer: NSObject, NSWindowDelegate {
        let onClose: () -> Void
        init(onClose: @escaping () -> Void) { self.onClose = onClose }
        func windowWillClose(_ notification: Notification) { onClose() }
    }
}

enum SettingsPage: String, CaseIterable, Identifiable {
    case general, appearance, notifications, features, permissions
    var id: String { rawValue }

    var title: String {
        switch self {
        case .general: return String(localized: "Genel")
        case .appearance: return String(localized: "Görünüm")
        case .notifications: return String(localized: "Bildirimler")
        case .features: return String(localized: "Özellikler")
        case .permissions: return String(localized: "İzinler")
        }
    }

    var icon: String {
        switch self {
        case .general: return "gearshape.fill"
        case .appearance: return "paintbrush.fill"
        case .notifications: return "bell.badge.fill"
        case .features: return "square.grid.2x2.fill"
        case .permissions: return "lock.shield.fill"
        }
    }

    var tint: Color {
        switch self {
        case .general: return .gray
        case .appearance: return .purple
        case .notifications: return .red
        case .features: return .blue
        case .permissions: return .green
        }
    }

    static let searchIndex: [(title: String, anchor: String, page: SettingsPage)] = [
        (String(localized: "Oturum açınca başlat"), "launchAtLogin", .general),
        (String(localized: "Ada nasıl açılsın"), "openOnHover", .general),
        (String(localized: "macOS göstergesi yerine adada göster"), "replaceHUD", .general),
        (String(localized: "Ses göstergesi"), "volumeHUDStyle", .general),
        (String(localized: "Parlaklık göstergesi"), "brightnessHUDStyle", .general),
        (String(localized: "Her basışta"), "volumeStep", .general),
        (String(localized: "Yeni sürümleri günde bir kez denetle"), "checkUpdates", .general),
        (String(localized: "Vurgu rengi"), "accentMode", .appearance),
        (String(localized: "Açılış animasyonu"), "islandMotion", .appearance),
        (String(localized: "Bildirim girişi"), "activityStyle", .appearance),
        (String(localized: "Ekolayzer"), "equalizerStyle", .appearance),
        (String(localized: "Şarj animasyonu"), "chargeAnimation", .appearance),
        (String(localized: "Ada kedisi"), "showPet", .appearance),
        (String(localized: "Müzik çalarken kapak rengi parıltısı"), "albumGlow", .appearance),
        (String(localized: "Göster"), "menuBarMode", .appearance),
        (String(localized: "Ada hangi ekranda"), "screenChoice", .appearance),
        (String(localized: "Açık ada genişliği"), "islandWidth", .appearance),
        (String(localized: "Animasyon hızı"), "animationSpeed", .appearance),
        (String(localized: "Şarj takılınca/çıkarılınca, düşük pil, tam dolu"), "notifyBattery", .notifications),
        (String(localized: "Şarj sınırına gelince hatırlat"), "chargeLimitAlert", .notifications),
        (String(localized: "Şarj sınırı"), "chargeLimit", .notifications),
        (String(localized: "Bağlanınca"), "notifyBluetooth", .notifications),
        (String(localized: "Toplantılardan önce haber ver"), "notifyCalendar", .notifications),
        (String(localized: "Ne kadar önce"), "calendarLeadMinutes", .notifications),
        (String(localized: "Görüşme modu (süre ve mikrofonu kapatma)"), "callMode", .notifications),
        (String(localized: "Kamera ve mikrofon göstergesi"), "showPrivacy", .notifications),
        (String(localized: "İndirme ilerlemesi"), "showDownloads", .notifications),
        (String(localized: "İnternet koptu / geri geldi"), "notifyNetwork", .notifications),
        (String(localized: "Odak modu"), "notifyFocus", .notifications),
        (String(localized: "Yağmur uyarısı"), "rainAlerts", .notifications),
        (String(localized: "Sistem uyarıları"), "systemAlertsGroup", .notifications),
        (String(localized: "Bir uygulama işlemciyi uzun süre yorarsa"), "systemAlerts", .notifications),
        (String(localized: "Disk dolmak üzereyse"), "alertDisk", .notifications),
        (String(localized: "Bellek baskısı yükselirse"), "alertMemory", .notifications),
        (String(localized: "Mac ısınırsa"), "alertThermal", .notifications),
        (String(localized: "Keynote/PowerPoint sunumunda ve ekran yansıtılırken kendiliğinden aç"), "presentationAuto", .features),
        (String(localized: "Masaüstü simgelerini gizle"), "presentationHideIcons", .features),
        (String(localized: "Hava durumunu göster"), "showWeather", .features),
        (String(localized: "Biten indirmeleri rafa ekle"), "downloadsToShelf", .features),
        (String(localized: "Ekran görüntülerini rafa ekle"), "screenshotsToShelf", .features),
        (String(localized: "Ekran görüntüsü önizlemesi"), "screenshotPreview", .features),
        (String(localized: "Pano geçmişi"), "clipboardHistory", .features),
        (String(localized: "Ekran paylaşımı ve kayıtlarda adayı gizle"), "hideFromCapture", .features),
        (String(localized: "Takvim"), "permCalendar", .permissions),
        (String(localized: "Odak için Tam Disk Erişimi"), "permFocus", .permissions),
        (String(localized: "Spotify / Apple Music kontrolü"), "permMedia", .permissions),
        (String(localized: "Erişilebilirlik (ses ve parlaklık tuşları)"), "permAccessibility", .permissions),
        (String(localized: "Konum (hava durumu)"), "permLocation", .permissions),
        (String(localized: "Ses ve parlaklık"), "replaceHUD", .general),
        (String(localized: "Güncellemeler"), "checkUpdates", .general),
        (String(localized: "Tema"), "accentMode", .appearance),
        (String(localized: "Ada"), "islandMotion", .appearance),
        (String(localized: "Menü çubuğu"), "menuBarMode", .appearance),
        (String(localized: "Sekmeler"), "screenChoice", .appearance),
        (String(localized: "Mac pili ve şarj"), "notifyBattery", .notifications),
        (String(localized: "AirPods"), "notifyBluetooth", .notifications),
        (String(localized: "Takvim"), "notifyCalendar", .notifications),
        (String(localized: "Diğer"), "callMode", .notifications),
        (String(localized: "Sunum modu"), "presentationAuto", .features),
        (String(localized: "Hava durumu"), "showWeather", .features),
        (String(localized: "Raf"), "downloadsToShelf", .features),
        (String(localized: "Pano"), "clipboardHistory", .features),
        (String(localized: "Gizlilik"), "hideFromCapture", .features),
        (String(localized: "Rehber"), "about", .general),
        (String(localized: "Sorun bildir…"), "about", .general),
        (String(localized: "Terminal komutu"), "terminal", .features),
        (String(localized: "Erişilebilirlik"), "permAccessibility", .permissions),
        (String(localized: "Tam Disk Erişimi"), "permFocus", .permissions),
        (String(localized: "Konum"), "permLocation", .permissions),
    ]
}

private struct SettingsView: View {
    @EnvironmentObject var model: IslandModel
    @EnvironmentObject var weather: WeatherService
    @ObservedObject var settings: AppSettings
    @State private var page: SettingsPage? = .general
    @State private var query = ""
    @State private var flash: String?
    @State private var advancedOpen = false
    @State private var alertsOpen = false
    @State private var target: String?

    private static let advancedAnchors: Set<String> = ["screenChoice", "islandWidth", "animationSpeed"]
    private static let alertAnchors: Set<String> = ["systemAlerts", "alertDisk", "alertMemory", "alertThermal", "alertBatteryHealth"]

    private func go(to hit: (title: String, anchor: String, page: SettingsPage)) {
        withAnimation(.spring(response: 0.35, dampingFraction: 1)) {
            page = hit.page
            query = ""
            if Self.advancedAnchors.contains(hit.anchor) { advancedOpen = true }
            if Self.alertAnchors.contains(hit.anchor) { alertsOpen = true }
        }
        target = nil
        DispatchQueue.main.async { target = hit.anchor }
    }

    var body: some View {
        NavigationSplitView {
            List(selection: $page) {
                if query.isEmpty {
                    ForEach(SettingsPage.allCases) { p in
                        Label {
                            Text(p.title)
                        } icon: {
                            SettingsPageIcon(page: p)
                        }
                        .tag(p)
                    }
                } else {
                    let hits = SettingsPage.searchIndex.filter { $0.title.localizedStandardContains(query) || $0.page.title.localizedStandardContains(query) }
                    if hits.isEmpty {
                        Text("Sonuç yok").foregroundStyle(.secondary)
                    }
                    ForEach(Array(hits.enumerated()), id: \.offset) { _, hit in
                        Button { go(to: hit) } label: {
                            HStack(spacing: 9) {
                                SettingsPageIcon(page: hit.page)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(hit.title).lineLimit(1)
                                    Text(hit.page.title).font(.caption).foregroundStyle(.secondary)
                                }
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.pressable)
                        .transition(.opacity.combined(with: .offset(y: -4)))
                    }
                }
            }
            .searchable(text: $query, placement: .sidebar, prompt: Text("Ayarlarda ara"))
            .animation(.snappy(duration: 0.22), value: query)
            .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            let p = page ?? .general
            ScrollViewReader { proxy in
                Group {
                    switch p {
                    case .general: general
                    case .appearance: appearance
                    case .notifications: notifications
                    case .features: features
                    case .permissions: permissions
                    }
                }
                .id(p)
                .transition(.opacity.combined(with: .offset(y: 10)))
                .environment(\.settingFlash, flash)
                .onChange(of: target) { _, anchor in
                    guard let anchor else { return }
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                        withAnimation(.spring(response: 0.45, dampingFraction: 1)) { proxy.scrollTo(anchor, anchor: .center) }
                        flash = anchor
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.8) { if flash == anchor { flash = nil } }
                    }
                }
            }
            .animation(.spring(response: 0.35, dampingFraction: 1), value: p)
            .navigationTitle(p.title)
        }
        .frame(minWidth: 760, minHeight: 560)
    }

    private var general: some View {
        Form {
            Section {
                Toggle("Oturum açınca başlat", isOn: Binding(
                    get: { settings.launchAtLogin },
                    set: { settings.setLaunchAtLogin($0) }
                ))
                .settingAnchor("launchAtLogin")
                if settings.launchAtLoginNeedsApproval {
                    HStack {
                        Text("Sistem Ayarları'nda onay bekliyor").font(.caption).foregroundStyle(.orange)
                        Spacer()
                        Button("Onayla…") { SMAppService.openSystemSettingsLoginItems() }
                    }
                }
                Picker("Ada nasıl açılsın", selection: $settings.openOnHover) {
                    Text("Üzerine gelince").tag(true)
                    Text("Tıklayınca").tag(false)
                }
                .settingAnchor("openOnHover")
            }
            Section("Ses ve parlaklık") {
                Toggle("macOS göstergesi yerine adada göster", isOn: $settings.replaceHUD)
                    .settingAnchor("replaceHUD")
                if settings.replaceHUD {
                    if model.hud.needsPermission {
                        HStack {
                            Text("Erişilebilirlik izni gerekiyor. DynIsl listede zaten açıksa − ile kaldırıp yeniden ekle.")
                                .font(.caption).foregroundStyle(.orange)
                            Spacer()
                            Button("İzin ver…") { model.hud.requestPermission(); model.hud.openAccessibilitySettings() }
                        }
                    }
                    HStack {
                        Picker("Ses göstergesi", selection: $settings.volumeHUDStyle) {
                            ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .settingAnchor("volumeHUDStyle")
                        Button("Dene") { model.hud.preview(.volume) }
                    }
                    HStack {
                        Picker("Parlaklık göstergesi", selection: $settings.brightnessHUDStyle) {
                            ForEach(HUDStyle.allCases) { Text($0.title).tag($0) }
                        }
                        .settingAnchor("brightnessHUDStyle")
                        Button("Dene") { model.hud.preview(.brightness) }
                    }
                    Picker("Her basışta", selection: $settings.volumeStep) {
                        Text(pc(2)).tag(2)
                        Text(pc(5)).tag(5)
                        Text(pc(10)).tag(10)
                        Text("macOS gibi (16 kademe)").tag(0)
                    }
                    .settingAnchor("volumeStep")
                    Text("⇧⌥ ile basınca %1 ince ayar.").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Güncellemeler") {
                Toggle("Yeni sürümleri günde bir kez denetle", isOn: $settings.checkUpdates)
                    .settingAnchor("checkUpdates")
                HStack {
                    Text(model.updates.checking ? String(localized: "Denetleniyor…") : (model.updates.lastResult ?? String(localized: "Henüz denetlenmedi")))
                        .foregroundStyle(model.updates.available != nil ? .blue : .secondary)
                    Spacer()
                    Button("Şimdi denetle") { model.updates.check(manual: true) }
                        .disabled(model.updates.checking)
                }
                if let r = model.updates.available {
                    if !r.notes.isEmpty {
                        Text(r.notes).font(.caption).foregroundStyle(.secondary).lineLimit(8)
                    }
                    HStack {
                        Button("Neler yeni?") { model.updates.openReleasePage() }
                        Spacer()
                        Button("Komutu kopyala") { model.updates.copyCommand() }
                        if model.updates.canRunUpdate {
                            Button("Güncelle") { model.updates.runUpdate() }.buttonStyle(.borderedProminent)
                        }
                    }
                }
            }
            Section {
                HStack {
                    Image(nsImage: NSApp.applicationIconImage).resizable().frame(width: 32, height: 32)
                    VStack(alignment: .leading) {
                        Text("DynIsl").font(.headline)
                        Text("Sürüm \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "–")")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    Spacer()
                    Button("Rehber") { OnboardingWindow.show(model: model) }
                    Button("Sorun bildir…") { UpdateChecker.reportProblem() }
                    Button("Çıkış") { NSApp.terminate(nil) }
                }
                .settingAnchor("about")
            }
        }
        .formStyle(.grouped)
    }

    private var appearance: some View {
        Form {
            Section("Tema") {
                Text("Değiştirdiğin anda ada birkaç saniye açılıp önizleme gösterir.").font(.caption).foregroundStyle(.secondary)
                Picker("Vurgu rengi", selection: $settings.accentMode) {
                    ForEach(AccentMode.allCases) { Text($0.title).tag($0) }
                }
                .settingAnchor("accentMode")
                if settings.accentMode == .custom {
                    ColorPicker("Renk", selection: Binding(
                        get: { Color(hex: settings.accentHex) ?? .blue },
                        set: { settings.accentHex = $0.hex }
                    ), supportsOpacity: false)
                }
            }
            Section("Ada") {
                HStack {
                    Picker("Açılış animasyonu", selection: $settings.islandMotion) {
                        ForEach(IslandMotion.allCases) { Text($0.title).tag($0) }
                    }
                    .settingAnchor("islandMotion")
                    Button("Dene") { model.previewAppearance() }
                }
                HStack {
                    Picker("Bildirim girişi", selection: $settings.activityStyle) {
                        ForEach(ActivityStyle.allCases) { Text($0.title).tag($0) }
                    }
                    .settingAnchor("activityStyle")
                    Button("Dene") {
                        model.showActivity(.init(icon: "airpodspro", tint: .white, title: "AirPods Pro", trailing: pc(92), ring: 0.92))
                    }
                }
                Picker("Ekolayzer", selection: $settings.equalizerStyle) {
                    ForEach(EqualizerStyle.allCases) { Text($0.title).tag($0) }
                }
                .settingAnchor("equalizerStyle")
                HStack {
                    Toggle("Şarj animasyonu", isOn: $settings.chargeAnimation)
                        .settingAnchor("chargeAnimation")
                    Spacer()
                    Button("Dene") { model.showCharging(model.battery.level) }
                        .disabled(!settings.chargeAnimation)
                }
                Toggle("Ada kedisi", isOn: $settings.showPet)
                    .settingAnchor("showPet")
                Text("Boşken uyur, müzik çalınca dans eder, pil azalınca yorulur, Mac zorlanınca terler.")
                    .font(.caption).foregroundStyle(.secondary)
                Toggle("Müzik çalarken kapak rengi parıltısı", isOn: $settings.albumGlow)
                    .settingAnchor("albumGlow")
            }
            Section("Menü çubuğu") {
                Picker("Göster", selection: $settings.menuBarMode) {
                    Text("Simge ve CPU/RAM").tag("both")
                    Text("Sadece simge").tag("icon")
                    Text("Sadece CPU/RAM").tag("stats")
                }
                .settingAnchor("menuBarMode")
                if settings.menuBarMode == "stats" {
                    Text("Menüye CPU/RAM göstergesine tıklayarak ulaşırsın.")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            Section("Sekmeler") {
                ForEach(Array(settings.tabOrder.enumerated()), id: \.element) { i, tab in
                    HStack {
                        Image(systemName: tab.icon).frame(width: 20)
                        Toggle(tab.title, isOn: Binding(
                            get: { !settings.hiddenTabs.contains(tab) },
                            set: { settings.setTab(tab, visible: $0) }
                        ))
                        .disabled(tab == .media)
                        Spacer()
                        Button { settings.moveTab(tab, by: -1) } label: { Image(systemName: "chevron.up") }
                            .buttonStyle(.borderless).disabled(i == 0)
                        Button { settings.moveTab(tab, by: 1) } label: { Image(systemName: "chevron.down") }
                            .buttonStyle(.borderless).disabled(i == settings.tabOrder.count - 1)
                    }
                }
            }
            Section {
                DisclosureGroup("Gelişmiş", isExpanded: $advancedOpen) {
                    Picker("Ada hangi ekranda", selection: $settings.screenChoice) {
                        Text("Çentikli ekran (otomatik)").tag("auto")
                        Text("Ana ekran").tag("main")
                        ForEach(NSScreen.screens, id: \.localizedName) { s in
                            Text(s.localizedName).tag(s.localizedName)
                        }
                    }
                    .settingAnchor("screenChoice")
                    Picker("Açık ada genişliği", selection: $settings.islandWidth) {
                        Text("Normal").tag(660)
                        Text("Geniş").tag(740)
                    }
                    .settingAnchor("islandWidth")
                    Picker("Animasyon hızı", selection: $settings.animationSpeed) {
                        Text("Hızlı").tag(0.75)
                        Text("Normal").tag(1.0)
                        Text("Yavaş").tag(1.35)
                    }
                    .settingAnchor("animationSpeed")
                }
            }
        }
        .formStyle(.grouped)
        .onChange(of: settings.accentMode) { model.previewAppearance() }
        .onChange(of: settings.accentHex) { model.previewAppearance() }
    }

    private var notifications: some View {
        Form {
            Section("Mac pili ve şarj") {
                Toggle("Şarj takılınca/çıkarılınca, düşük pil, tam dolu", isOn: $settings.notifyBattery)
                    .settingAnchor("notifyBattery")
                Toggle("Şarj sınırına gelince hatırlat", isOn: $settings.chargeLimitAlert)
                    .settingAnchor("chargeLimitAlert")
                if settings.chargeLimitAlert {
                    Picker("Şarj sınırı", selection: $settings.chargeLimit) {
                        Text(pc(80)).tag(80)
                        Text(pc(85)).tag(85)
                        Text(pc(90)).tag(90)
                    }
                    .settingAnchor("chargeLimit")
                }
                Toggle("2 saatten uzun %100'de kalırsa hatırlat", isOn: $settings.fullPluggedAlert)
                    .settingAnchor("fullPluggedAlert")
            }
            Section("AirPods") {
                Toggle("Bağlanınca", isOn: $settings.notifyBluetooth)
                    .settingAnchor("notifyBluetooth")
                Toggle("Pili azalınca (%20 ve %10)", isOn: $settings.airPodsBatteryAlert)
                    .settingAnchor("airPodsBatteryAlert")
            }
            Section("Takvim") {
                Toggle("Toplantılardan önce haber ver", isOn: $settings.notifyCalendar)
                    .settingAnchor("notifyCalendar")
                if settings.notifyCalendar {
                    Picker("Ne kadar önce", selection: $settings.calendarLeadMinutes) {
                        Text("5 dk").tag(5)
                        Text("10 dk").tag(10)
                        Text("15 dk").tag(15)
                        Text("30 dk").tag(30)
                    }
                    .settingAnchor("calendarLeadMinutes")
                }
            }
            Section("Diğer") {
                Toggle("Görüşme modu (süre ve mikrofonu kapatma)", isOn: $settings.callMode)
                    .settingAnchor("callMode")
                Toggle("Kamera ve mikrofon göstergesi", isOn: $settings.showPrivacy)
                    .settingAnchor("showPrivacy")
                Toggle("İndirme ilerlemesi", isOn: $settings.showDownloads)
                    .settingAnchor("showDownloads")
                Toggle("İnternet koptu / geri geldi", isOn: $settings.notifyNetwork)
                    .settingAnchor("notifyNetwork")
                Toggle("Odak modu", isOn: $settings.notifyFocus)
                    .settingAnchor("notifyFocus")
                Toggle("Yağmur uyarısı", isOn: $settings.rainAlerts)
                    .settingAnchor("rainAlerts")
            }
            Section {
                DisclosureGroup("Sistem uyarıları", isExpanded: $alertsOpen) {
                    Toggle("Bir uygulama işlemciyi uzun süre yorarsa", isOn: $settings.systemAlerts)
                        .settingAnchor("systemAlerts")
                    Toggle("Disk dolmak üzereyse", isOn: $settings.alertDisk)
                        .settingAnchor("alertDisk")
                    Toggle("Bellek baskısı yükselirse", isOn: $settings.alertMemory)
                        .settingAnchor("alertMemory")
                    Toggle("Mac ısınırsa", isOn: $settings.alertThermal)
                        .settingAnchor("alertThermal")
                    Toggle("Pil sağlığı %80'in altına inerse", isOn: $settings.alertBatteryHealth)
                        .settingAnchor("alertBatteryHealth")
                }
                .settingAnchor("systemAlertsGroup")
            }
        }
        .formStyle(.grouped)
    }

    private var features: some View {
        Form {
            Section("Sunum modu") {
                HStack {
                    Text(model.presentation.isActive ? "Açık · \(model.presentation.reason ?? "")" : "Kapalı")
                        .foregroundStyle(model.presentation.isActive ? .purple : .secondary)
                    Spacer()
                    Button(model.presentation.manual ? "Kapat" : "Şimdi aç") { model.presentation.toggleManual() }
                }
                Toggle("Keynote/PowerPoint sunumunda ve ekran yansıtılırken kendiliğinden aç", isOn: $settings.presentationAuto)
                    .settingAnchor("presentationAuto")
                Toggle("Masaüstü simgelerini gizle", isOn: $settings.presentationHideIcons)
                    .settingAnchor("presentationHideIcons")
                Text("Bildirimleri susturur. Zoom/Meet/Teams paylaşımında menüden ya da ⌥⌘P ile aç.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Section("Hava durumu") {
                Toggle("Hava durumunu göster", isOn: $settings.showWeather)
                    .settingAnchor("showWeather")
                if settings.showWeather {
                    TextField("Şehir (boşsa konumun kullanılır)", text: $settings.weatherCity)
                        .onSubmit { model.weather.manualCity = settings.weatherCity }
                    if let status = weather.status {
                        Text(status).font(.caption).foregroundStyle(.orange)
                    }
                }
            }
            Section("Raf") {
                Toggle("Biten indirmeleri rafa ekle", isOn: $settings.downloadsToShelf)
                    .settingAnchor("downloadsToShelf")
                Toggle("Ekran görüntülerini rafa ekle", isOn: $settings.screenshotsToShelf)
                    .settingAnchor("screenshotsToShelf")
                Toggle("Ekran görüntüsü önizlemesi", isOn: $settings.screenshotPreview)
                    .settingAnchor("screenshotPreview")
            }
            Section("Pano") {
                Toggle("Pano geçmişi", isOn: $settings.clipboardHistory)
                    .settingAnchor("clipboardHistory")
                if settings.clipboardHistory {
                    HStack {
                        Text("Sadece bellekte tutulur, şifre yöneticisi kopyaları kaydedilmez.")
                            .font(.caption).foregroundStyle(.secondary)
                        Spacer()
                        Button("Temizle") { model.clipboard.clear() }
                    }
                }
            }
            Section("Gizlilik") {
                Toggle("Ekran paylaşımı ve kayıtlarda adayı gizle", isOn: $settings.hideFromCapture)
                    .settingAnchor("hideFromCapture")
            }
            Section("Terminal komutu") {
                Text("island \"Build bitti\" · island -s \"Testler geçti\" · island run npm test")
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)
                    .foregroundStyle(.secondary)
                    .settingAnchor("terminal")
            }
        }
        .formStyle(.grouped)
    }

    private var permissions: some View {
        Form {
            Section {
                PermissionRow(title: "Takvim", ok: model.calendar.access == .granted) {
                    model.calendar.access == .unknown ? model.calendar.requestAccess() : model.calendar.openSettings()
                }
                .settingAnchor("permCalendar")
                PermissionRow(title: "Odak için Tam Disk Erişimi", ok: !model.focus.needsPermission) {
                    model.focus.openPermissionSettings()
                }
                .settingAnchor("permFocus")
                PermissionRow(title: "Spotify / Apple Music kontrolü", ok: !model.media.permissionDenied) {
                    model.media.openAutomationSettings()
                }
                .settingAnchor("permMedia")
                PermissionRow(title: "Erişilebilirlik (ses ve parlaklık tuşları)", ok: !model.hud.needsPermission) {
                    model.hud.requestPermission()
                    model.hud.openAccessibilitySettings()
                }
                .settingAnchor("permAccessibility")
                PermissionRow(title: "Konum (hava durumu)", ok: weather.now != nil || !settings.weatherCity.isEmpty) {
                    model.weather.openLocationSettings()
                }
                .settingAnchor("permLocation")
            }
        }
        .formStyle(.grouped)
    }
}

private struct SettingsPageIcon: View {
    let page: SettingsPage

    var body: some View {
        Image(systemName: page.icon)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.white)
            .frame(width: 22, height: 22)
            .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(page.tint.gradient))
    }
}

private struct SettingFlashKey: EnvironmentKey {
    static let defaultValue: String? = nil
}

extension EnvironmentValues {
    var settingFlash: String? {
        get { self[SettingFlashKey.self] }
        set { self[SettingFlashKey.self] = newValue }
    }
}

private struct SettingAnchor: ViewModifier {
    let id: String
    @Environment(\.settingFlash) private var flash
    @State private var lit = false
    @State private var task: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: 7, style: .continuous)
                    .fill(Color.accentColor.opacity(lit ? 0.26 : 0))
                    .padding(.horizontal, -8)
                    .padding(.vertical, -4)
            )
            .id(id)
            .onChange(of: flash) { _, f in if f == id { pulse() } }
    }

    private func pulse() {
        task?.cancel()
        task = Task { @MainActor in
            for _ in 0..<2 {
                withAnimation(.easeOut(duration: 0.22)) { lit = true }
                try? await Task.sleep(for: .milliseconds(420))
                withAnimation(.easeIn(duration: 0.32)) { lit = false }
                try? await Task.sleep(for: .milliseconds(360))
            }
        }
    }
}

private extension View {
    func settingAnchor(_ id: String) -> some View { modifier(SettingAnchor(id: id)) }
}

private struct PermissionRow: View {
    let title: LocalizedStringKey
    let ok: Bool
    let fix: () -> Void

    var body: some View {
        HStack {
            Image(systemName: ok ? "checkmark.circle.fill" : "exclamationmark.circle.fill")
                .foregroundStyle(ok ? .green : .orange)
            Text(title)
            Spacer()
            if !ok { Button("Ayarla…", action: fix) }
        }
    }
}
