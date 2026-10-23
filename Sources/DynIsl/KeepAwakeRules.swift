import Foundation

enum KeepAwakeDuration: Equatable {
    case indefinite
    case minutes(Int)
    case until(Date)
    case whileApp(String)
}

enum KeepAwakeRules {
    nonisolated static func endDate(for duration: KeepAwakeDuration, now: Date, calendar: Calendar) -> Date? {
        switch duration {
        case .indefinite, .whileApp:
            return nil
        case .minutes(let m):
            return now.addingTimeInterval(TimeInterval(m * 60))
        case .until(let t):
            return t > now ? t : calendar.date(byAdding: .day, value: 1, to: t)
        }
    }

    nonisolated static func shouldStopForBattery(level: Int, onBattery: Bool, threshold: Int) -> Bool {
        onBattery && level <= threshold
    }

    nonisolated static func sudoersContent(user: String) -> String {
        "\(user) ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n"
    }

    nonisolated static func sleepDisabled(fromPmsetOutput output: String) -> Bool {
        output.split(separator: "\n").contains { line in
            let parts = line.split(whereSeparator: \.isWhitespace)
            return parts.first == "SleepDisabled" && parts.dropFirst().first == "1"
        }
    }
}
