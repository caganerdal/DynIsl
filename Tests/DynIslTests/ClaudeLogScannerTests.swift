import Foundation
import Testing
@testable import DynIsl

struct ClaudeLogScannerTests {
    private let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Europe/Istanbul")!
        return c
    }()
    private let now = ISO8601DateFormatter().date(from: "2026-10-23T12:00:00Z")!

    private func line(id: String, req: String = "r", at: String = "2026-10-23T09:00:00Z", project: String = "DynIsl",
                      model: String = "claude-opus-5-5", input: Int = 1, output: Int = 2) -> String {
        #"{"type":"assistant","requestId":"\#(req)","timestamp":"\#(at)","cwd":"/p/\#(project)","message":{"id":"\#(id)","model":"\#(model)","usage":{"input_tokens":\#(input),"output_tokens":\#(output),"cache_read_input_tokens":0,"cache_creation_input_tokens":0}}}"#
    }

    private func tempRoot() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("scan-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u.appendingPathComponent("proj/sub"), withIntermediateDirectories: true)
        return u
    }

    private func write(_ url: URL, _ lines: [String], trailingNewline: Bool = true) throws {
        try (lines.joined(separator: "\n") + (trailingNewline ? "\n" : "")).write(to: url, atomically: false, encoding: .utf8)
    }

    private func append(_ url: URL, _ text: String) throws {
        let h = try FileHandle(forWritingTo: url)
        try h.seekToEnd()
        try h.write(contentsOf: Data(text.utf8))
        try h.close()
    }

    @Test func aggregatesRecursivelyAndDedupes() throws {
        let root = try tempRoot()
        try write(root.appendingPathComponent("proj/a.jsonl"), [line(id: "m1"), line(id: "m1"), line(id: "m2", project: "Other", output: 10),
                                                                #"{"type":"user","message":{"content":"x"}}"#])
        try write(root.appendingPathComponent("proj/sub/b.jsonl"), [line(id: "m1"), line(id: "m3", output: 5)])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        #expect(s.scan(now: now))
        let sum = s.summary(now: now)
        #expect(sum.today.total == 3 + 11 + 6)
        #expect(sum.projects.first?.name == "Other" && sum.projects.first?.total == 11)
        #expect(sum.projects.first(where: { $0.name == "DynIsl" })?.total == 9)
    }

    @Test func incrementalAndPartialLines() throws {
        let root = try tempRoot()
        let f = root.appendingPathComponent("proj/a.jsonl")
        try write(f, [line(id: "m1")])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        s.scan(now: now)
        #expect(!s.scan(now: now))
        let next = line(id: "m2", output: 7)
        try append(f, String(next.prefix(30)))
        s.scan(now: now)
        #expect(s.summary(now: now).today.total == 3)
        try append(f, String(next.dropFirst(30)) + "\n")
        #expect(s.scan(now: now))
        #expect(s.summary(now: now).today.total == 3 + 8)
    }

    @Test func truncatedFileIsReread() throws {
        let root = try tempRoot()
        let f = root.appendingPathComponent("proj/a.jsonl")
        try write(f, [line(id: "m1"), line(id: "m2")])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        s.scan(now: now)
        try write(f, [line(id: "m9", output: 1)])
        s.scan(now: now)
        #expect(s.summary(now: now).today.total == 3 + 3 + 2)
    }

    @Test func stateSurvivesRestartWithoutDoubleCounting() throws {
        let root = try tempRoot()
        let f = root.appendingPathComponent("proj/a.jsonl")
        try write(f, [line(id: "m1")])
        let first = ClaudeLogScanner(root: root, calendar: cal)
        first.scan(now: now)
        let data = try JSONEncoder().encode(first.state)
        try append(f, line(id: "m1") + "\n" + line(id: "m2") + "\n")
        let second = ClaudeLogScanner(root: root, state: try JSONDecoder().decode(ScanState.self, from: data), calendar: cal)
        second.scan(now: now)
        #expect(second.summary(now: now).today.total == 6)
    }

    @Test func weekAndDailyBuckets() throws {
        let root = try tempRoot()
        try write(root.appendingPathComponent("proj/a.jsonl"), [
            line(id: "a", at: "2026-10-23T08:00:00Z", output: 9),
            line(id: "b", at: "2026-10-20T08:00:00Z", output: 19),
            line(id: "c", at: "2026-10-10T08:00:00Z", output: 99),
            line(id: "d", at: "2026-09-01T08:00:00Z", output: 999),
        ])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        s.scan(now: now)
        let sum = s.summary(now: now)
        #expect(sum.today.total == 10)
        #expect(sum.week.total == 10 + 20)
        #expect(sum.daily.count == 7)
        #expect(sum.daily.last?.total == 10)
        #expect(sum.daily.first(where: { cal.isDate($0.day, inSameDayAs: ISO8601DateFormatter().date(from: "2026-10-20T08:00:00Z")!) })?.total == 20)
        #expect(!s.state.buckets.keys.contains { $0.day < cal.date(byAdding: .day, value: -31, to: now)! })
    }

    @Test func modelsBreakdown() throws {
        let root = try tempRoot()
        try write(root.appendingPathComponent("proj/a.jsonl"), [line(id: "a", output: 9), line(id: "b", model: "claude-sonnet-5-5", output: 1)])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        s.scan(now: now)
        #expect(s.summary(now: now).models.map(\.name) == ["claude-opus-5-5", "claude-sonnet-5-5"])
    }

    @Test func offsetOnlyProgressCountsAsChange() throws {
        let root = try tempRoot()
        let f = root.appendingPathComponent("proj/a.jsonl")
        try write(f, [line(id: "m1")])
        let s = ClaudeLogScanner(root: root, calendar: cal)
        s.scan(now: now)
        try append(f, #"{"type":"user","message":{"content":"x"}}"# + "\n")
        #expect(s.scan(now: now))
    }

    @Test func checkpointsDuringLongScan() throws {
        let root = try tempRoot()
        for i in 0..<3 { try write(root.appendingPathComponent("proj/\(i).jsonl"), [line(id: "m\(i)")]) }
        let s = ClaudeLogScanner(root: root, calendar: cal)
        var saves = 0
        s.scan(now: now, checkpointEvery: 0) { _ in saves += 1 }
        #expect(saves == 3)
    }
}
