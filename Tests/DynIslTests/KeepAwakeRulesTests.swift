import Foundation
import Testing
@testable import DynIsl

struct KeepAwakeRulesTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()

    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: hour, minute: minute))!
    }

    @Test func endDateMinutes() {
        let now = date(23, 12)
        #expect(KeepAwakeRules.endDate(for: .minutes(30), now: now, calendar: cal) == now.addingTimeInterval(1800))
    }

    @Test func endDateUntilFuture() {
        #expect(KeepAwakeRules.endDate(for: .until(date(23, 18)), now: date(23, 12), calendar: cal) == date(23, 18))
    }

    @Test func endDateUntilPastMeansTomorrow() {
        #expect(KeepAwakeRules.endDate(for: .until(date(23, 7)), now: date(23, 23), calendar: cal) == date(24, 7))
    }

    @Test func indefiniteHasNoEnd() {
        #expect(KeepAwakeRules.endDate(for: .indefinite, now: date(23, 12), calendar: cal) == nil)
        #expect(KeepAwakeRules.endDate(for: .whileApp("com.apple.Safari"), now: date(23, 12), calendar: cal) == nil)
    }

    @Test func batteryStopsOnlyOnBattery() {
        #expect(KeepAwakeRules.shouldStopForBattery(level: 15, onBattery: true, threshold: 20))
        #expect(!KeepAwakeRules.shouldStopForBattery(level: 15, onBattery: false, threshold: 20))
        #expect(!KeepAwakeRules.shouldStopForBattery(level: 21, onBattery: true, threshold: 20))
        #expect(KeepAwakeRules.shouldStopForBattery(level: 20, onBattery: true, threshold: 20))
    }

    @Test func sudoersLine() {
        #expect(KeepAwakeRules.sudoersContent(user: "ali")
                == "ali ALL=(root) NOPASSWD: /usr/bin/pmset -a disablesleep 0, /usr/bin/pmset -a disablesleep 1\n")
    }

    @Test func parsesSleepDisabled() {
        #expect(KeepAwakeRules.sleepDisabled(fromPmsetOutput: "System-wide power settings:\n SleepDisabled\t\t1\n"))
        #expect(!KeepAwakeRules.sleepDisabled(fromPmsetOutput: " SleepDisabled 0"))
        #expect(!KeepAwakeRules.sleepDisabled(fromPmsetOutput: ""))
    }
}
