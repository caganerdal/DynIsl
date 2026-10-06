import AppKit
import SwiftUI
import Combine

final class IslandPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        isOpaque = false
        backgroundColor = .clear
        hasShadow = false
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        isMovable = false
        hidesOnDeactivate = false
        ignoresMouseEvents = true
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect { frameRect }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private let model = IslandModel()
    private var panel: IslandPanel!
    private var statusItem: NSStatusItem!
    private var statusMenu: NSMenu!
    private var keepAwakeMenu: NSMenu?
    private var updateItem: NSMenuItem?
    private var presentationItem: NSMenuItem?
    private var monitors: [Any] = []
    private var settingsBag: Any?
    private var statsBag: [Any] = []
    private var statsItem: NSStatusItem?
    private var termSource: DispatchSourceSignal?
    private var lastStatsKey = ""
    private var dragTimer: Timer?
    private var dragBaseline = 0
    private var collapseWork: DispatchWorkItem?

    private let panelSize = NSSize(width: 820, height: 330)

    func applicationDidFinishLaunching(_ notification: Notification) {
        panel = IslandPanel(contentRect: NSRect(origin: .zero, size: panelSize))
        let host = NSHostingView(rootView: IslandView()
            .environmentObject(model)
            .environmentObject(model.system)
            .environmentObject(model.batteryInfo)
            .environmentObject(model.weather)
            .environmentObject(model.clipboard))
        host.sizingOptions = []
        host.frame = NSRect(origin: .zero, size: panelSize)
        panel.contentView = host

        positionPanel()
        applyCapturePrivacy()
        panel.orderFrontRegardless()

        setupMouseTracking()
        setupStatusItem()
        setupMainMenu()
        handleTerminationSignal()
        OnboardingWindow.showIfNeeded(model: model)
        updateStatsItem()
        statsBag = [
            model.settings.$menuBarMode.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.updateStatsItem() }
            },
            model.settings.$hideFromCapture.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
                MainActor.assumeIsolated { self?.applyCapturePrivacy() }
            },
            model.system.didSample.sink { [weak self] in
                MainActor.assumeIsolated { self?.renderStats() }
            },
        ]

        settingsBag = model.settings.$screenChoice.dropFirst().receive(on: RunLoop.main).sink { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }

        NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification,
            object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.positionPanel() }
        }
    }

    private func targetScreen() -> NSScreen? {
        switch model.settings.screenChoice {
        case "auto": return NSScreen.builtInOrMain
        case "main": return NSScreen.screens.first
        case let name: return NSScreen.screens.first { $0.localizedName == name } ?? NSScreen.builtInOrMain
        }
    }

    private func positionPanel() {
        guard let screen = targetScreen() else { return }
        model.configure(for: screen)
        let f = screen.frame
        panel.setFrame(
            NSRect(x: f.midX - panelSize.width / 2, y: f.maxY - panelSize.height,
                   width: panelSize.width, height: panelSize.height),
            display: true
        )
    }

    private func setupMouseTracking() {
        dragBaseline = NSPasteboard(name: .drag).changeCount
        panel.acceptsMouseMovedEvents = true
        let mask: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDown, .leftMouseDragged, .leftMouseUp]
        if let g = NSEvent.addGlobalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseEvent(e.type) }
        }) { monitors.append(g) }
        if let l = NSEvent.addLocalMonitorForEvents(matching: mask, handler: { [weak self] e in
            MainActor.assumeIsolated { self?.mouseEvent(e.type) }
            return e
        }) { monitors.append(l) }
    }

    private func mouseEvent(_ type: NSEvent.EventType) {
        handleMouse()
        if type == .leftMouseDown || type == .leftMouseDragged { startDragPolling() }
    }

    private func startDragPolling() {
        guard dragTimer == nil else { return }
        dragTimer = Timer.scheduledTimer(withTimeInterval: 1.0 / 30, repeats: true) { [weak self] t in
            MainActor.assumeIsolated {
                guard let self else { t.invalidate(); return }
                self.handleMouse()
                if NSEvent.pressedMouseButtons & 1 == 0 {
                    t.invalidate()
                    self.dragTimer = nil
                }
            }
        }
    }

    private func detectFileDrag() -> Bool {
        let pb = NSPasteboard(name: .drag)
        guard NSEvent.pressedMouseButtons & 1 != 0 else {
            dragBaseline = pb.changeCount
            return false
        }
        return pb.changeCount != dragBaseline && (pb.types?.contains(.fileURL) ?? false)
    }

    private func handleMouse() {
        let fileDrag = detectFileDrag()
        if model.isFileDragging != fileDrag { model.isFileDragging = fileDrag }

        let p = NSEvent.mouseLocation
        let f = panel.frame
        if !fileDrag, !model.isExpanded, panel.ignoresMouseEvents, model.state != .peek, model.state != .hud, !f.contains(p) {
            return
        }
        let size = model.currentSize
        var rect = NSRect(x: f.midX - size.width / 2, y: f.maxY - size.height,
                          width: size.width, height: size.height)
        if fileDrag && !model.isExpanded {
            rect = rect.insetBy(dx: -60, dy: -50)
        } else {
            rect = rect.insetBy(dx: model.isExpanded ? -12 : -6, dy: model.isExpanded ? -12 : -6)
        }
        let inside = rect.contains(p)

        if panel.ignoresMouseEvents == inside { panel.ignoresMouseEvents = !inside }

        if model.state == .peek {
            if inside || fileDrag { model.screenshots.hold() } else { model.screenshots.release() }
            return
        }
        if model.state == .hud {
            if inside { model.hud.hold() } else { model.hud.release() }
            return
        }

        if inside {
            collapseWork?.cancel()
            collapseWork = nil
            if !model.isExpanded, model.settings.openOnHover || fileDrag { model.setExpanded(true) }
        } else if model.isExpanded, !fileDrag, !model.previewHold, collapseWork == nil {
            let work = DispatchWorkItem { [weak self] in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.model.setExpanded(false)
                    self.collapseWork = nil
                    if !self.model.isFileDragging, self.model.tab == .shelf, self.model.shelf.items.isEmpty {
                        self.model.tab = .media
                    }
                }
            }
            collapseWork = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.25, execute: work)
        }
    }

    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage.menuBarIcon

        let menu = NSMenu()
        menu.addItem(item(String(localized: "Sistem Paneli…"), #selector(openDashboard), key: "0"))
        menu.addItem(item(String(localized: "İnternet hız testi"), #selector(runSpeedTest)))
        let awake = NSMenu()
        awake.delegate = self
        awake.autoenablesItems = false
        for (i, d) in KeepAwake.durations.enumerated() {
            let it = item(d.title, #selector(keepAwakeFor(_:)))
            it.tag = i
            awake.addItem(it)
        }
        awake.addItem(.separator())
        awake.addItem(item(String(localized: "Kapat"), #selector(keepAwakeOff)))
        let awakeItem = NSMenuItem(title: String(localized: "Uyanık tut"), action: nil, keyEquivalent: "")
        awakeItem.submenu = awake
        menu.addItem(awakeItem)
        keepAwakeMenu = awake
        let pres = item(String(localized: "Sunum modu"), #selector(togglePresentation), key: "p")
        pres.keyEquivalentModifierMask = [.command, .option]
        menu.addItem(pres)
        presentationItem = pres
        menu.addItem(.separator())
        let test = NSMenu()
        test.addItem(item(String(localized: "Şarj oluyor"), #selector(demoCharging)))
        test.addItem(item(String(localized: "Düşük pil"), #selector(demoLowBattery)))
        test.addItem(item(String(localized: "AirPods bağlandı"), #selector(demoAirPods)))
        test.addItem(item(String(localized: "10 sn zamanlayıcı"), #selector(demoTimer)))
        let testItem = NSMenuItem(title: String(localized: "Bildirimleri test et"), action: nil, keyEquivalent: "")
        testItem.submenu = test
        menu.addItem(testItem)
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Müzik: Oynat / Duraklat"), #selector(togglePlay)))
        menu.addItem(item(String(localized: "AirDrop ile gönder…"), #selector(airDrop)))
        menu.addItem(.separator())
        let upd = item(String(localized: "Güncellemeleri denetle"), #selector(updateMenuAction))
        menu.addItem(upd)
        menu.addItem(item(String(localized: "Sorun bildir…"), #selector(reportProblem)))
        updateItem = upd
        menu.delegate = self
        menu.addItem(.separator())
        menu.addItem(item(String(localized: "Ayarlar…"), #selector(openSettings), key: ","))
        menu.addItem(item(String(localized: "Çıkış"), #selector(quit), key: "q"))
        statusItem.menu = menu
        statusMenu = menu
    }

    private func item(_ title: String, _ action: Selector, key: String = "") -> NSMenuItem {
        let i = NSMenuItem(title: title, action: action, keyEquivalent: key)
        i.target = self
        return i
    }

    @objc private func keepAwakeFor(_ sender: NSMenuItem) {
        model.keepAwake.start(minutes: KeepAwake.durations[sender.tag].minutes)
    }
    @objc private func keepAwakeOff() { model.keepAwake.stop() }

    @objc private func togglePresentation() { model.presentation.toggleManual() }
    @objc private func reportProblem() { UpdateChecker.reportProblem() }

    @objc private func updateMenuAction() {
        if model.updates.available != nil { model.updates.openReleasePage() } else { model.updates.check(manual: true) }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        if menu === statusMenu {
            updateItem?.title = model.updates.available.map { String(localized: "Yeni sürüm var: v\($0.version)…") } ?? String(localized: "Güncellemeleri denetle")
            presentationItem?.state = model.presentation.isActive ? .on : .off
            presentationItem?.title = model.presentation.isActive && !model.presentation.manual
                ? String(localized: "Sunum modu (\(model.presentation.reason ?? String(localized: "otomatik")))") : String(localized: "Sunum modu")
            return
        }
        guard menu === keepAwakeMenu else { return }
        let k = model.keepAwake
        for it in menu.items where it.action == #selector(keepAwakeFor(_:)) {
            it.state = k.isActive && KeepAwake.durations[it.tag].minutes == k.minutes ? .on : .off
        }
        if let off = menu.items.last {
            off.title = k.remainingText.map { String(localized: "Kapat (\($0))") } ?? (k.isActive ? String(localized: "Kapat") : String(localized: "Kapalı"))
            off.isEnabled = k.isActive
            off.state = k.isActive ? .off : .on
        }
    }

    @objc private func demoCharging() {
        let l = model.battery.level
        if model.settings.chargeAnimation { model.showCharging(l); return }
        model.showActivity(.init(icon: "bolt.fill", tint: .green, title: String(localized: "Şarj oluyor"), trailing: pc(l), ring: Double(l) / 100))
    }
    @objc private func demoLowBattery() {
        model.showActivity(.init(icon: "battery.25percent", tint: .orange, title: String(localized: "Düşük pil"), trailing: pc(18), ring: 0.18))
    }
    @objc private func demoAirPods() {
        model.showActivity(.init(icon: "airpodspro", tint: .white, title: "AirPods Pro", trailing: pc(92), ring: 0.92))
    }
    @objc private func demoTimer() { model.startTimer(seconds: 10) }
    @objc private func togglePlay() { model.media.playPause() }
    @objc private func airDrop() { model.airdrop.pickAndShare() }
    @objc private func openSettings() { SettingsWindow.show(model: model) }
    @objc private func openDashboard() { DashboardWindow.show(model: model) }
    @objc private func runSpeedTest() { model.speedTest.start() }

    private func applyCapturePrivacy() {
        panel.sharingType = model.settings.hideFromCapture ? .none : .readOnly
    }

    private func updateStatsItem() {
        let settings = model.settings
        statusItem.isVisible = settings.showsIconItem
        model.system.menuBarActive = settings.showsStatsItem

        if settings.showsStatsItem, statsItem == nil {
            statsItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
            statsItem?.button?.target = self
            renderStats()
        } else if !settings.showsStatsItem, let item = statsItem {
            NSStatusBar.system.removeStatusItem(item)
            statsItem = nil
        }

        guard let stats = statsItem else { return }
        if settings.showsIconItem {
            stats.menu = nil
            stats.button?.action = #selector(openDashboard)
            stats.button?.toolTip = String(localized: "Sistem Paneli'ni aç")
        } else {
            statusItem.menu = nil
            stats.menu = statusMenu
            stats.button?.action = nil
            stats.button?.toolTip = nil
        }
        if settings.showsIconItem, statusItem.menu == nil { statusItem.menu = statusMenu }
    }

    private func renderStats() {
        guard let button = statsItem?.button else { return }
        let sys = model.system
        let cpu = Int(sys.cpu * 100), ram = Int(sys.memory * 100)
        let key = "\(cpu)|\(ram)"
        guard key != lastStatsKey || button.attributedTitle.length == 0 else { return }
        lastStatsKey = key
        let label: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 9, weight: .bold),
            .baselineOffset: 0.5,
        ]
        let value: [NSAttributedString.Key: Any] = [.font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium)]
        let s = NSMutableAttributedString()
        s.append(NSAttributedString(string: "CPU ", attributes: label))
        s.append(NSAttributedString(string: String(format: "%2d%%   ", cpu), attributes: value))
        s.append(NSAttributedString(string: "RAM ", attributes: label))
        s.append(NSAttributedString(string: String(format: "%2d%%", ram), attributes: value))
        button.attributedTitle = s
        let tip = String(localized: "İşlemci kullanımı \(pc(cpu)) · Bellek (RAM) kullanımı \(pc(ram))")
        button.toolTip = model.settings.showsIconItem ? tip + String(localized: "\nTıkla: Sistem Paneli") : tip
    }

    private func setupMainMenu() {
        let main = NSMenu()

        let appItem = NSMenuItem()
        let app = NSMenu()
        app.addItem(item(String(localized: "Sistem Paneli"), #selector(openDashboard), key: "0"))
        app.addItem(item(String(localized: "Ayarlar…"), #selector(openSettings), key: ","))
        app.addItem(.separator())
        app.addItem(NSMenuItem(title: String(localized: "DynIsl'ı Gizle"), action: #selector(NSApplication.hide(_:)), keyEquivalent: "h"))
        app.addItem(.separator())
        app.addItem(item(String(localized: "Çıkış"), #selector(quit), key: "q"))
        appItem.submenu = app
        main.addItem(appItem)

        let editItem = NSMenuItem()
        let edit = NSMenu(title: String(localized: "Düzen"))
        edit.addItem(NSMenuItem(title: String(localized: "Geri Al"), action: Selector(("undo:")), keyEquivalent: "z"))
        edit.addItem(.separator())
        edit.addItem(NSMenuItem(title: String(localized: "Kes"), action: #selector(NSText.cut(_:)), keyEquivalent: "x"))
        edit.addItem(NSMenuItem(title: String(localized: "Kopyala"), action: #selector(NSText.copy(_:)), keyEquivalent: "c"))
        edit.addItem(NSMenuItem(title: String(localized: "Yapıştır"), action: #selector(NSText.paste(_:)), keyEquivalent: "v"))
        edit.addItem(NSMenuItem(title: String(localized: "Tümünü Seç"), action: #selector(NSText.selectAll(_:)), keyEquivalent: "a"))
        editItem.submenu = edit
        main.addItem(editItem)

        let windowItem = NSMenuItem()
        let window = NSMenu(title: String(localized: "Pencere"))
        window.addItem(NSMenuItem(title: String(localized: "Küçült"), action: #selector(NSWindow.performMiniaturize(_:)), keyEquivalent: "m"))
        window.addItem(NSMenuItem(title: String(localized: "Pencereyi Kapat"), action: #selector(NSWindow.performClose(_:)), keyEquivalent: "w"))
        windowItem.submenu = window
        main.addItem(windowItem)
        NSApp.windowsMenu = window

        NSApp.mainMenu = main
    }

    func applicationWillTerminate(_ notification: Notification) {
        cleanUpBeforeExit()
    }

    private func cleanUpBeforeExit() {
        model.call.releaseMute()
        model.speedTest.cancel()
    }

    private func handleTerminationSignal() {
        signal(SIGTERM, SIG_IGN)
        let source = DispatchSource.makeSignalSource(signal: SIGTERM, queue: .main)
        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated { self?.cleanUpBeforeExit() }
            exit(0)
        }
        source.resume()
        termSource = source
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag { DashboardWindow.show(model: model) }
        return true
    }
    @objc private func quit() { NSApp.terminate(nil) }
}

extension NSImage {
    static let menuBarIcon: NSImage = {
        let img = NSImage(size: NSSize(width: 22, height: 16), flipped: false) { _ in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: NSRect(x: 1, y: 3.5, width: 20, height: 9), xRadius: 4.5, yRadius: 4.5).fill()
            NSGraphicsContext.current?.compositingOperation = .clear
            for (i, h) in [2.6, 4.6, 3.4].enumerated() {
                let x = 4.6 + CGFloat(i) * 2.2
                NSBezierPath(roundedRect: NSRect(x: x, y: 8 - h / 2, width: 1.3, height: h),
                             xRadius: 0.65, yRadius: 0.65).fill()
            }
            NSBezierPath(ovalIn: NSRect(x: 14.4, y: 6.1, width: 3.8, height: 3.8)).fill()
            return true
        }
        img.isTemplate = true
        img.accessibilityDescription = "DynIsl"
        return img
    }()
}

extension NSScreen {
    static var builtInOrMain: NSScreen? {
        screens.first { $0.safeAreaInsets.top > 0 } ?? main
    }
}
