import AppKit

@MainActor
final class AirDropService: NSObject, NSSharingServiceDelegate {
    var onResult: ((Bool, Int) -> Void)?
    private var pendingCount = 0

    var isAvailable: Bool {
        NSSharingService(named: .sendViaAirDrop) != nil
    }

    @discardableResult
    func share(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty,
              let service = NSSharingService(named: .sendViaAirDrop),
              service.canPerform(withItems: urls) else {
            onResult?(false, urls.count)
            return false
        }
        pendingCount = urls.count
        service.delegate = self
        NSApp.activate(ignoringOtherApps: true)
        service.perform(withItems: urls)
        return true
    }

    func pickAndShare() {
        let panel = NSOpenPanel()
        panel.title = String(localized: "AirDrop ile gönderilecek dosyaları seç")
        panel.prompt = String(localized: "Gönder")
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = true
        panel.canChooseFiles = true
        NSApp.activate(ignoringOtherApps: true)
        panel.begin { [weak self] response in
            MainActor.assumeIsolated {
                guard response == .OK else { return }
                self?.share(panel.urls)
            }
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didShareItems items: [Any]) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onResult?(true, self.pendingCount)
            }
        }
    }

    nonisolated func sharingService(_ sharingService: NSSharingService, didFailToShareItems items: [Any], error: Error) {
        if (error as NSError).code == NSUserCancelledError { return }
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.onResult?(false, self.pendingCount)
            }
        }
    }
}
