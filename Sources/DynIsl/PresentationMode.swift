import AppKit

@MainActor
final class PresentationMode: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var manual = false
    @Published private(set) var reason: String?

    var autoDetect = true { didSet { evaluate() } }
    var hideIcons = true { didSet { applyCover() } }
    var onChange: ((Bool, Bool) -> Void)?

    private static let presentationApps: Set<String> = [
        "com.apple.iWork.Keynote", "com.microsoft.Powerpoint", "org.libreoffice.script", "com.kingsoft.wpsoffice.mac",
    ]

    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var covers: [NSWindow] = []

    func start() {
        let nc = NSWorkspace.shared.notificationCenter
        for name in [NSWorkspace.didActivateApplicationNotification, NSWorkspace.didLaunchApplicationNotification,
                     NSWorkspace.didTerminateApplicationNotification, NSWorkspace.activeSpaceDidChangeNotification] {
            observers.append(nc.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.evaluate() }
            })
        }
        observers.append(NotificationCenter.default.addObserver(
            forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.evaluate()
                self?.applyCover()
            }
        })
        evaluate()
    }

    func toggleManual() {
        manual.toggle()
        evaluate()
    }

    private func evaluate() {
        let presenterRunning = NSWorkspace.shared.runningApplications.contains {
            Self.presentationApps.contains($0.bundleIdentifier ?? "")
        }
        if autoDetect && presenterRunning {
            if timer == nil {
                timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
                    MainActor.assumeIsolated { self?.evaluate() }
                }
            }
        } else {
            timer?.invalidate()
            timer = nil
        }

        var why: String?
        if manual {
            why = "Elle açıldı"
        } else if autoDetect {
            if presenterRunning, let name = Self.slideshowApp() {
                why = "\(name) sunumu"
            } else if Self.isMirroring() {
                why = "Ekran yansıtılıyor"
            }
        }
        if reason != why { reason = why }
        let active = why != nil
        guard active != isActive else { return }
        isActive = active
        applyCover()
        onChange?(active, manual)
    }

    private static func slideshowApp() -> String? {
        guard let app = NSWorkspace.shared.frontmostApplication,
              presentationApps.contains(app.bundleIdentifier ?? "") else { return nil }
        let pid = app.processIdentifier
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let screens = NSScreen.screens.map(\.frame.size)
        for w in list where (w[kCGWindowOwnerPID as String] as? pid_t) == pid {
            guard let b = w[kCGWindowBounds as String] as? [String: CGFloat],
                  let width = b["Width"], let height = b["Height"] else { continue }
            if screens.contains(where: { abs($0.width - width) < 2 && abs($0.height - height) < 2 }) {
                return app.localizedName ?? "Sunum"
            }
        }
        return nil
    }

    private static func isMirroring() -> Bool {
        var count: UInt32 = 0
        var ids = [CGDirectDisplayID](repeating: 0, count: 8)
        guard CGGetOnlineDisplayList(8, &ids, &count) == .success else { return false }
        return ids.prefix(Int(count)).contains { CGDisplayIsInMirrorSet($0) != 0 }
    }

    private func applyCover() {
        covers.forEach { $0.orderOut(nil) }
        covers.removeAll()
        guard isActive, hideIcons else { return }
        for screen in NSScreen.screens {
            let w = NSWindow(contentRect: screen.frame, styleMask: .borderless, backing: .buffered, defer: false)
            w.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.desktopIconWindow)) + 1)
            w.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            w.ignoresMouseEvents = true
            w.isReleasedWhenClosed = false
            w.hasShadow = false
            w.backgroundColor = .black
            let iv = NSImageView(frame: NSRect(origin: .zero, size: screen.frame.size))
            iv.imageScaling = .scaleAxesIndependently
            iv.autoresizingMask = [.width, .height]
            if let url = NSWorkspace.shared.desktopImageURL(for: screen), let img = NSImage(contentsOf: url) {
                iv.image = Self.aspectFill(img, to: screen.frame.size)
            }
            w.contentView = iv
            w.setFrame(screen.frame, display: false)
            w.orderFront(nil)
            covers.append(w)
        }
    }

    private static func aspectFill(_ img: NSImage, to size: NSSize) -> NSImage {
        let s = max(size.width / max(img.size.width, 1), size.height / max(img.size.height, 1))
        let drawn = NSSize(width: img.size.width * s, height: img.size.height * s)
        let out = NSImage(size: size)
        out.lockFocus()
        img.draw(in: NSRect(x: (size.width - drawn.width) / 2, y: (size.height - drawn.height) / 2,
                            width: drawn.width, height: drawn.height))
        out.unlockFocus()
        return out
    }
}
