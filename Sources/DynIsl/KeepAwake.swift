import Foundation
import IOKit.pwr_mgt

@MainActor
final class KeepAwake: ObservableObject {
    @Published private(set) var isActive = false
    @Published private(set) var endDate: Date?
    private(set) var minutes = 0

    var onChange: ((IslandActivity) -> Void)?

    private var assertions: [IOPMAssertionID] = []
    private var timer: Timer?

    static let durations: [(title: String, minutes: Int)] = [
        ("Süresiz", 0), ("30 dakika", 30), ("1 saat", 60), ("2 saat", 120), ("4 saat", 240),
    ]

    func start(minutes: Int) {
        if !isActive {
            for type in [kIOPMAssertPreventUserIdleDisplaySleep, kIOPMAssertPreventUserIdleSystemSleep] {
                var id: IOPMAssertionID = 0
                if IOPMAssertionCreateWithName(type as CFString, IOPMAssertionLevel(kIOPMAssertionLevelOn),
                                               "DynIsl: Uyanık tut" as CFString, &id) == kIOReturnSuccess {
                    assertions.append(id)
                }
            }
            guard !assertions.isEmpty else { return }
            isActive = true
        }
        self.minutes = minutes
        timer?.invalidate()
        timer = nil
        if minutes > 0 {
            let end = Date().addingTimeInterval(TimeInterval(minutes * 60))
            endDate = end
            timer = Timer.scheduledTimer(withTimeInterval: TimeInterval(minutes * 60), repeats: false) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop(expired: true) }
            }
        } else {
            endDate = nil
        }
        onChange?(.init(icon: "cup.and.saucer.fill", tint: .orange, title: "Uyanık tut",
                        trailing: minutes > 0 ? Self.short(minutes) : "Süresiz"))
    }

    func stop(expired: Bool = false) {
        guard isActive else { return }
        timer?.invalidate()
        timer = nil
        assertions.forEach { IOPMAssertionRelease($0) }
        assertions.removeAll()
        isActive = false
        endDate = nil
        onChange?(.init(icon: "moon.zzz.fill", tint: .indigo, title: expired ? "Süre doldu" : "Uyanık tut",
                        trailing: "Kapalı"))
    }

    func toggle() { isActive ? stop() : start(minutes: 0) }

    var remainingText: String? {
        guard let endDate else { return nil }
        let m = max(Int(endDate.timeIntervalSinceNow / 60.0 + 0.999), 1)
        return m >= 60 ? "\(m / 60) sa \(m % 60) dk kaldı" : "\(m) dk kaldı"
    }

    private static func short(_ minutes: Int) -> String {
        minutes >= 60 ? "\(minutes / 60) sa" : "\(minutes) dk"
    }
}
