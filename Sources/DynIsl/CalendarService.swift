import AppKit
import EventKit
import SwiftUI

struct UpcomingEvent: Identifiable, Equatable {
    var id: String
    var title: String
    var start: Date
    var end: Date
    var color: Color
    var location: String?
    var meetingURL: URL?
}

@MainActor
final class CalendarService: ObservableObject {
    enum Access { case unknown, granted, denied }

    @Published private(set) var access: Access = .unknown
    @Published private(set) var upcoming: [UpcomingEvent] = []

    var onActivity: ((IslandActivity) -> Void)?

    var leadMinutes = 10

    private let store = EKEventStore()
    private var timer: Timer?
    private var notified: Set<String> = []
    private var lastSignature: String?

    func start() {
        updateAccess()
        if access == .unknown { requestAccess() }
        NotificationCenter.default.addObserver(forName: .EKEventStoreChanged, object: store, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.reload() }
        }
        timer = Timer.repeating(every: 20, tolerance: 0.25) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        reload()
    }

    func requestAccess() {
        NSApp.activate(ignoringOtherApps: true)
        store.requestFullAccessToEvents { [weak self] _, _ in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.updateAccess()
                    self?.reload()
                }
            }
        }
    }

    func openSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Calendars") {
            NSWorkspace.shared.open(url)
        }
    }

    func join(_ event: UpcomingEvent) {
        if let url = event.meetingURL { NSWorkspace.shared.open(url) }
    }

    func openInCalendar(_ event: UpcomingEvent) {
        if let url = URL(string: "ical://") { NSWorkspace.shared.open(url) }
    }

    private func updateAccess() {
        switch EKEventStore.authorizationStatus(for: .event) {
        case .fullAccess: access = .granted
        case .notDetermined: access = .unknown
        default: access = .denied
        }
    }

    private func reload() {
        guard access == .granted else { upcoming = []; return }
        let now = Date()
        let predicate = store.predicateForEvents(
            withStart: now.addingTimeInterval(-3 * 3600),
            end: now.addingTimeInterval(36 * 3600),
            calendars: nil
        )
        let events = store.events(matching: predicate)
            .filter { !$0.isAllDay && $0.endDate > now && $0.status != .canceled }
            .sorted { $0.startDate < $1.startDate }
            .prefix(6)
            .map { e in
                UpcomingEvent(
                    id: (e.eventIdentifier ?? UUID().uuidString) + "\(e.startDate.timeIntervalSince1970)",
                    title: e.title?.isEmpty == false ? e.title! : "Adsız etkinlik",
                    start: e.startDate, end: e.endDate,
                    color: Color(cgColor: e.calendar.cgColor),
                    location: e.location?.isEmpty == false ? e.location : nil,
                    meetingURL: Self.meetingURL(in: e)
                )
            }
        upcoming = Array(events)
        tick()
    }

    private func tick() {
        let now = Date()
        let signature = imminent.map { "\($0.id)|\(Int(ceil($0.start.timeIntervalSince(now) / 60)))" }
        if signature != lastSignature {
            lastSignature = signature
            objectWillChange.send()
        }
        if upcoming.contains(where: { $0.end <= now }) { upcoming.removeAll { $0.end <= now } }

        for e in upcoming {
            let minutes = Int(ceil(e.start.timeIntervalSince(now) / 60))
            let soonKey = e.id + ".soon"
            let nowKey = e.id + ".now"
            if minutes <= leadMinutes, minutes > 1, !notified.contains(soonKey) {
                notified.insert(soonKey)
                onActivity?(.init(icon: "calendar", tint: e.color, title: e.title, trailing: "\(minutes) dk sonra"))
            } else if minutes <= 1, now < e.start.addingTimeInterval(120), !notified.contains(nowKey) {
                notified.insert(nowKey)
                notified.insert(soonKey)
                onActivity?(.init(icon: e.meetingURL != nil ? "video.fill" : "calendar", tint: e.color,
                                  title: e.title, trailing: "Başlıyor"))
            }
        }
    }

    var imminent: UpcomingEvent? {
        let now = Date()
        return upcoming.first { e in
            let until = e.start.timeIntervalSince(now)
            return until <= 5 * 60 && until > -60
        }
    }

    private static func meetingURL(in event: EKEvent) -> URL? {
        let hosts = ["zoom.us", "meet.google.com", "teams.microsoft.com", "teams.live.com", "webex.com", "facetime.apple.com"]
        let texts = [event.url?.absoluteString, event.location, event.notes].compactMap { $0 }
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue) else { return nil }
        for text in texts {
            let matches = detector.matches(in: text, range: NSRange(text.startIndex..., in: text))
            for m in matches {
                if let url = m.url, url.scheme?.lowercased() == "https", let host = url.host?.lowercased(),
                   hosts.contains(where: { host == $0 || host.hasSuffix("." + $0) }) {
                    return url
                }
            }
        }
        return nil
    }
}
