import Foundation

struct UsageBucketKey: Codable, Hashable {
    var day: Date
    var project: String
    var model: String
}

struct UsageTotals: Codable, Equatable {
    var input = 0
    var output = 0
    var cacheRead = 0
    var cacheWrite = 0
    var total: Int { input + output + cacheRead + cacheWrite }

    mutating func add(_ r: UsageRecord) {
        input += r.input; output += r.output; cacheRead += r.cacheRead; cacheWrite += r.cacheWrite
    }

    mutating func add(_ t: UsageTotals) {
        input += t.input; output += t.output; cacheRead += t.cacheRead; cacheWrite += t.cacheWrite
    }
}

struct ScanState: Codable {
    var offsets: [String: UInt64] = [:]
    var seen: [String: Date] = [:]
    var buckets: [UsageBucketKey: UsageTotals] = [:]
}

struct AIUsageSummary: Equatable {
    struct Named: Equatable { var name: String; var total: Int }
    struct Day: Equatable { var day: Date; var total: Int }
    var today = UsageTotals()
    var week = UsageTotals()
    var daily: [Day] = []
    var projects: [Named] = []
    var models: [Named] = []
}

final class ClaudeLogScanner {
    static let keepDays = 30
    private static let marker = Data(#""type":"assistant""#.utf8)
    private static let chunk = 8 << 20

    let root: URL
    private(set) var state: ScanState
    private let calendar: Calendar

    init(root: URL, state: ScanState = ScanState(), calendar: Calendar = .current) {
        self.root = root
        self.state = state
        self.calendar = calendar
    }

    @discardableResult
    func scan(now: Date) -> Bool {
        let cutoff = calendar.startOfDay(for: calendar.date(byAdding: .day, value: -Self.keepDays, to: now) ?? now)
        var changed = false
        let keys: [URLResourceKey] = [.contentModificationDateKey, .fileSizeKey, .isRegularFileKey]
        guard let walker = FileManager.default.enumerator(at: root, includingPropertiesForKeys: keys) else { return false }
        var present = Set<String>()
        for case let url as URL in walker where url.pathExtension == "jsonl" {
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isRegularFile == true else { continue }
            let path = url.path
            present.insert(path)
            let size = UInt64(v.fileSize ?? 0)
            var offset = state.offsets[path] ?? 0
            if offset == 0, state.offsets[path] == nil, let m = v.contentModificationDate, m < cutoff {
                state.offsets[path] = size
                continue
            }
            if size < offset { offset = 0 }
            guard size > offset else { continue }
            if read(url, from: offset, cutoff: cutoff, newOffset: &offset) { changed = true }
            state.offsets[path] = offset
        }
        state.offsets = state.offsets.filter { present.contains($0.key) }
        let before = state.buckets.count
        state.buckets = state.buckets.filter { $0.key.day >= cutoff }
        state.seen = state.seen.filter { $0.value >= cutoff }
        return changed || state.buckets.count != before
    }

    private func read(_ url: URL, from start: UInt64, cutoff: Date, newOffset: inout UInt64) -> Bool {
        guard let h = try? FileHandle(forReadingFrom: url) else { return false }
        defer { try? h.close() }
        guard (try? h.seek(toOffset: start)) != nil else { return false }
        var offset = start
        var carry = Data()
        var changed = false
        while let data = try? h.read(upToCount: Self.chunk), !data.isEmpty {
            carry.append(data)
            guard let last = carry.lastIndex(of: 0x0A) else { continue }
            let complete = carry[carry.startIndex...last]
            for line in complete.split(separator: 0x0A, omittingEmptySubsequences: true) where line.range(of: Self.marker) != nil {
                if ingest(line, cutoff: cutoff) { changed = true }
            }
            offset += UInt64(complete.count)
            carry = Data(carry[carry.index(after: last)...])
        }
        newOffset = offset
        return changed
    }

    private func ingest(_ line: Data, cutoff: Date) -> Bool {
        guard let text = String(data: line, encoding: .utf8), let r = AIUsageRules.parseLogLine(Substring(text)),
              r.date >= cutoff, state.seen[r.key] == nil else { return false }
        state.seen[r.key] = r.date
        let key = UsageBucketKey(day: calendar.startOfDay(for: r.date), project: r.project, model: r.model)
        state.buckets[key, default: UsageTotals()].add(r)
        return true
    }

    func summary(now: Date) -> AIUsageSummary {
        let today = calendar.startOfDay(for: now)
        let weekStart = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        var s = AIUsageSummary()
        var perDay: [Date: Int] = [:]
        var projects: [String: Int] = [:]
        var models: [String: Int] = [:]
        for (k, t) in state.buckets where k.day >= weekStart {
            s.week.add(t)
            if k.day == today { s.today.add(t) }
            perDay[k.day, default: 0] += t.total
            projects[k.project, default: 0] += t.total
            models[k.model, default: 0] += t.total
        }
        s.daily = (0..<7).compactMap { i in
            calendar.date(byAdding: .day, value: i, to: weekStart).map { AIUsageSummary.Day(day: $0, total: perDay[$0] ?? 0) }
        }
        let sorted: ([String: Int]) -> [AIUsageSummary.Named] = { d in
            d.map { AIUsageSummary.Named(name: $0.key, total: $0.value) }
                .sorted { $0.total != $1.total ? $0.total > $1.total : $0.name < $1.name }
        }
        s.projects = sorted(projects)
        s.models = sorted(models)
        return s
    }
}
