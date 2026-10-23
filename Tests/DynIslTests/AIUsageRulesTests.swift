import Foundation
import Testing
@testable import DynIsl

struct AIUsageRulesTests {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private let statusJSON = """
    {"model":{"id":"claude-opus-5-5","display_name":"Opus 5.5"},"cwd":"/tmp/x",
     "rate_limits":{"five_hour":{"used_percentage":23.5,"resets_at":1800003600},
                    "seven_day":{"used_percentage":41.2,"resets_at":1800300000}}}
    """

    @Test func parsesRateLimits() throws {
        let l = try #require(AIUsageRules.parseStatus(Data(statusJSON.utf8), now: now))
        #expect(l.fiveHour == LimitWindow(usedPercent: 23.5, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(l.sevenDay?.usedPercent == 41.2)
        #expect(l.model == "Opus 5.5")
        #expect(l.updatedAt == now)
    }

    @Test func parsesStatusWithoutLimits() throws {
        let l = try #require(AIUsageRules.parseStatus(Data(#"{"model":{"display_name":"Sonnet 5.5"}}"#.utf8), now: now))
        #expect(l.fiveHour == nil && l.sevenDay == nil)
        #expect(AIUsageRules.statusLine(l) == "Sonnet 5.5")
    }

    @Test func rejectsInvalidJSON() {
        #expect(AIUsageRules.parseStatus(Data("nope".utf8), now: now) == nil)
    }

    @Test func statusLineText() throws {
        let l = try #require(AIUsageRules.parseStatus(Data(statusJSON.utf8), now: now))
        #expect(AIUsageRules.statusLine(l) == "5s %24 · hafta %41")
        #expect(AIUsageRules.statusLine(ClaudeLimits(fiveHour: nil, sevenDay: nil, model: nil, updatedAt: now)) == "Claude")
    }

    @Test func mergeKeepsOldWindowsWhenNewHasNone() {
        let w = LimitWindow(usedPercent: 50, resetsAt: now)
        let old = ClaudeLimits(fiveHour: w, sevenDay: w, model: "A", updatedAt: now.addingTimeInterval(-60))
        let new = ClaudeLimits(fiveHour: nil, sevenDay: nil, model: "B", updatedAt: now)
        let m = AIUsageRules.merge(old: old, new: new)
        #expect(m.fiveHour == w && m.sevenDay == w && m.model == "B" && m.updatedAt == old.updatedAt)
    }

    @Test func mergePrefersNewWindows() {
        let a = LimitWindow(usedPercent: 50, resetsAt: now)
        let b = LimitWindow(usedPercent: 60, resetsAt: now)
        let m = AIUsageRules.merge(old: ClaudeLimits(fiveHour: a, sevenDay: a, model: nil, updatedAt: now),
                                   new: ClaudeLimits(fiveHour: b, sevenDay: nil, model: nil, updatedAt: now.addingTimeInterval(5)))
        #expect(m.fiveHour == b && m.sevenDay == a && m.updatedAt == now.addingTimeInterval(5))
    }

    @Test func expiredWindowIsZero() {
        let w = LimitWindow(usedPercent: 90, resetsAt: now)
        #expect(AIUsageRules.effective(w, now: now.addingTimeInterval(1))?.usedPercent == 0)
        #expect(AIUsageRules.effective(w, now: now.addingTimeInterval(-1))?.usedPercent == 90)
        #expect(AIUsageRules.effective(nil, now: now) == nil)
    }

    @Test func thresholdCrossing() {
        #expect(AIUsageRules.crossed(previous: 70, current: 85, thresholds: [80, 95]) == 80)
        #expect(AIUsageRules.crossed(previous: 70, current: 97, thresholds: [80, 95]) == 95)
        #expect(AIUsageRules.crossed(previous: 85, current: 90, thresholds: [80, 95]) == nil)
        #expect(AIUsageRules.crossed(previous: 90, current: 10, thresholds: [80, 95]) == nil)
    }

    private let logLine = #"{"type":"assistant","requestId":"req_1","timestamp":"2026-10-23T10:00:00.500Z","cwd":"/Users/a/Projects/DynIsl","message":{"id":"msg_1","model":"claude-opus-5-5","content":[{"type":"text","text":"gizli"}],"usage":{"input_tokens":10,"output_tokens":20,"cache_read_input_tokens":300,"cache_creation_input_tokens":40}}}"#

    @Test func parsesLogLine() throws {
        let r = try #require(AIUsageRules.parseLogLine(Substring(logLine)))
        #expect(r.key == "msg_1:req_1")
        #expect(r.project == "DynIsl")
        #expect(r.model == "claude-opus-5-5")
        #expect(r.input == 10 && r.output == 20 && r.cacheRead == 300 && r.cacheWrite == 40)
        #expect(r.total == 370)
        #expect(r.date == ISO8601DateFormatter().date(from: "2026-10-23T10:00:00Z")!.addingTimeInterval(0.5))
    }

    @Test func ignoresNonAssistantAndBrokenLines() {
        #expect(AIUsageRules.parseLogLine(#"{"type":"user","message":{"content":"x"}}"#) == nil)
        #expect(AIUsageRules.parseLogLine(#"{"type":"assistant","message":{"id":"m"}}"#) == nil)
        #expect(AIUsageRules.parseLogLine(#"{"type":"assistant","mess"#) == nil)
    }

    @Test func ignoresZeroUsageSyntheticLines() {
        let l = #"{"type":"assistant","requestId":"r","timestamp":"2026-10-23T10:00:00Z","cwd":"/p/x","message":{"id":"m","model":"<synthetic>","usage":{"input_tokens":0,"output_tokens":0,"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
        #expect(AIUsageRules.parseLogLine(Substring(l)) == nil)
    }

    @Test func connectAddsStatusLineAndKeepsOtherKeys() throws {
        let original = Data(#"{"hooks":{"Stop":[]},"model":"opus"}"#.utf8)
        let out = try AIUsageRules.connect(settings: original, command: "/x/island claude-status")
        let d = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(d["model"] as? String == "opus")
        #expect(d["hooks"] != nil)
        let s = try #require(d["statusLine"] as? [String: Any])
        #expect(s["type"] as? String == "command" && s["command"] as? String == "/x/island claude-status")
    }

    @Test func connectWorksWithoutSettingsFile() throws {
        let out = try AIUsageRules.connect(settings: nil, command: "c claude-status")
        let d = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect((d["statusLine"] as? [String: Any])?["command"] as? String == "c claude-status")
    }

    @Test func connectRefusesForeignStatusLineAndBadJSON() {
        let foreign = Data(#"{"statusLine":{"type":"command","command":"my-script.sh"}}"#.utf8)
        #expect(throws: AIUsageRules.LinkError.foreignStatusLine) { try AIUsageRules.connect(settings: foreign, command: "c claude-status") }
        #expect(throws: AIUsageRules.LinkError.invalidSettings) { try AIUsageRules.connect(settings: Data("{bad".utf8), command: "c claude-status") }
    }

    @Test func connectAcceptsOwnExistingStatusLine() throws {
        let own = Data(#"{"statusLine":{"type":"command","command":"/old/island claude-status"}}"#.utf8)
        let out = try AIUsageRules.connect(settings: own, command: "/new/island claude-status")
        let d = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect((d["statusLine"] as? [String: Any])?["command"] as? String == "/new/island claude-status")
    }

    @Test func readsStatusCommand() {
        #expect(AIUsageRules.statusCommand(settings: Data(#"{"statusLine":{"command":"/a/island claude-status"}}"#.utf8)) == "/a/island claude-status")
        #expect(AIUsageRules.statusCommand(settings: Data("{}".utf8)) == nil)
    }

    @Test func linkedStatus() {
        #expect(AIUsageRules.isLinked(settings: Data(#"{"statusLine":{"command":"/a/island claude-status"}}"#.utf8)))
        #expect(!AIUsageRules.isLinked(settings: Data(#"{"statusLine":{"command":"x.sh"}}"#.utf8)))
        #expect(!AIUsageRules.isLinked(settings: nil))
    }

    @Test func disconnectRemovesOnlyOwnStatusLine() throws {
        let own = Data(#"{"statusLine":{"type":"command","command":"/a/island claude-status"},"model":"opus"}"#.utf8)
        let out = try #require(AIUsageRules.disconnect(settings: own))
        let d = try #require(try JSONSerialization.jsonObject(with: out) as? [String: Any])
        #expect(d["statusLine"] == nil && d["model"] as? String == "opus")
        #expect(AIUsageRules.disconnect(settings: Data(#"{"statusLine":{"command":"x.sh"}}"#.utf8)) == nil)
    }

    @Test func parsesCodexRateLimits() throws {
        let line = #"{"timestamp":"2026-10-23T10:00:00Z","type":"event_msg","payload":{"type":"token_count","rate_limits":{"primary":{"used_percent":12.0,"window_minutes":300,"resets_at":1800003600},"secondary":{"used_percent":30.5,"window_minutes":10080,"resets_in_seconds":7200}}}}"#
        let r = try #require(AIUsageRules.parseCodex(Substring(line), now: now))
        #expect(r.primary == LimitWindow(usedPercent: 12, resetsAt: Date(timeIntervalSince1970: 1_800_003_600)))
        #expect(r.secondary == LimitWindow(usedPercent: 30.5, resetsAt: now.addingTimeInterval(7200)))
        #expect(AIUsageRules.parseCodex(#"{"type":"event_msg","payload":{"type":"agent_message"}}"#, now: now) == nil)
    }

    private func limits(_ five: Double?, _ week: Double?, fiveReset: TimeInterval = 3600) -> ClaudeLimits {
        ClaudeLimits(fiveHour: five.map { LimitWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(fiveReset)) },
                     sevenDay: week.map { LimitWindow(usedPercent: $0, resetsAt: now.addingTimeInterval(86400)) },
                     model: nil, updatedAt: now)
    }

    @Test func alertsOnThresholdCrossing() {
        #expect(AIUsageRules.alerts(old: limits(70, 50), new: limits(82, 50)) == [.fiveHour(80)])
        #expect(AIUsageRules.alerts(old: limits(82, 85), new: limits(96, 91)) == [.fiveHour(95), .sevenDay(90)])
        #expect(AIUsageRules.alerts(old: limits(82, 50), new: limits(84, 50)) == [])
    }

    @Test func noAlertsOnFirstReading() {
        #expect(AIUsageRules.alerts(old: nil, new: limits(99, 99)) == [])
    }

    @Test func newWindowStartsFromZero() {
        #expect(AIUsageRules.alerts(old: limits(90, 10), new: limits(85, 10, fiveReset: 5 * 3600)) == [.fiveHour(80)])
    }
}
