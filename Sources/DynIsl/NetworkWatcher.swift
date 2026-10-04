import AppKit
import Network

@MainActor
final class NetworkWatcher {
    var onActivity: ((IslandActivity) -> Void)?

    private let monitor = NWPathMonitor()
    private var online: Bool?
    private var downSince: Date?
    private var notifiedDown = false
    private var pending: DispatchWorkItem?
    private var quietUntil = Date.distantPast
    private var observers: [NSObjectProtocol] = []

    private static let confirmDelay: TimeInterval = 4

    func start() {
        monitor.pathUpdateHandler = { [weak self] path in
            let ok = path.status == .satisfied
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.update(ok) }
            }
        }
        monitor.start(queue: DispatchQueue(label: "dynisl.network"))

        let nc = NSWorkspace.shared.notificationCenter
        observers.append(nc.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset(quietFor: .infinity) }
        })
        observers.append(nc.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reset(quietFor: 20) }
        })
    }

    private func reset(quietFor seconds: TimeInterval) {
        pending?.cancel()
        pending = nil
        downSince = nil
        notifiedDown = false
        quietUntil = seconds.isInfinite ? .distantFuture : Date().addingTimeInterval(seconds)
        if seconds.isFinite, online == false { scheduleDownCheck(after: seconds) }
    }

    private func update(_ ok: Bool) {
        let was = online
        online = ok
        guard let was, was != ok else { return }
        if ok {
            pending?.cancel()
            pending = nil
            if notifiedDown, let since = downSince {
                onActivity?(.init(icon: "wifi", tint: .green, title: "İnternet geri geldi",
                                  trailing: Self.duration(Date().timeIntervalSince(since)) + " kesikti"))
            }
            downSince = nil
            notifiedDown = false
        } else {
            downSince = Date()
            scheduleDownCheck(after: Self.confirmDelay)
        }
    }

    private func scheduleDownCheck(after delay: TimeInterval) {
        pending?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.online == false, !self.notifiedDown else { return }
                if Date() < self.quietUntil {
                    if self.quietUntil != .distantFuture {
                        self.scheduleDownCheck(after: self.quietUntil.timeIntervalSinceNow + 0.5)
                    }
                    return
                }
                if self.downSince == nil { self.downSince = Date() }
                self.notifiedDown = true
                self.onActivity?(.init(icon: "wifi.slash", tint: .red, title: "İnternet yok", trailing: "Bağlantı koptu"))
            }
        }
        pending = work
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: work)
    }

    private static func duration(_ t: TimeInterval) -> String {
        let s = max(Int(t), 1)
        if s < 60 { return "\(s) sn" }
        if s < 3600 { return s % 60 == 0 ? "\(s / 60) dk" : "\(s / 60) dk \(s % 60) sn" }
        return "\(s / 3600) sa \(s % 3600 / 60) dk"
    }
}
