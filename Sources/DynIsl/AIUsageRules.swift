import Foundation

struct LimitWindow: Codable, Equatable {
    var usedPercent: Double
    var resetsAt: Date
}

struct ClaudeLimits: Codable, Equatable {
    var fiveHour: LimitWindow?
    var sevenDay: LimitWindow?
    var model: String?
    var updatedAt: Date
}

struct UsageRecord: Equatable {
    var key: String
    var date: Date
    var project: String
    var model: String
    var input: Int
    var output: Int
    var cacheRead: Int
    var cacheWrite: Int
    var total: Int { input + output + cacheRead + cacheWrite }
}

enum AIUsageRules {
    enum LinkError: Error, Equatable { case invalidSettings, foreignStatusLine }

    static let statusCommandSuffix = "claude-status"

    static func parseStatus(_ data: Data, now: Date) -> ClaudeLimits? {
        guard let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return nil }
        let limits = json["rate_limits"] as? [String: Any]
        let model = json["model"] as? [String: Any]
        return ClaudeLimits(fiveHour: window(limits?["five_hour"]), sevenDay: window(limits?["seven_day"]),
                            model: model?["display_name"] as? String ?? model?["id"] as? String, updatedAt: now)
    }

    private static func window(_ any: Any?) -> LimitWindow? {
        guard let d = any as? [String: Any], let used = number(d["used_percentage"]), let reset = number(d["resets_at"]) else { return nil }
        return LimitWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: reset))
    }

    private static func number(_ any: Any?) -> Double? {
        (any as? NSNumber)?.doubleValue
    }

    static func statusLine(_ l: ClaudeLimits) -> String {
        var parts: [String] = []
        if let w = l.fiveHour { parts.append("5s %\(Int(w.usedPercent.rounded()))") }
        if let w = l.sevenDay { parts.append("hafta %\(Int(w.usedPercent.rounded()))") }
        return parts.isEmpty ? (l.model ?? "Claude") : parts.joined(separator: " · ")
    }

    static func merge(old: ClaudeLimits?, new: ClaudeLimits) -> ClaudeLimits {
        guard let old, new.fiveHour == nil, new.sevenDay == nil else {
            return ClaudeLimits(fiveHour: new.fiveHour ?? old?.fiveHour, sevenDay: new.sevenDay ?? old?.sevenDay,
                                model: new.model ?? old?.model, updatedAt: new.updatedAt)
        }
        return ClaudeLimits(fiveHour: old.fiveHour, sevenDay: old.sevenDay, model: new.model ?? old.model, updatedAt: old.updatedAt)
    }

    static func effective(_ w: LimitWindow?, now: Date) -> LimitWindow? {
        guard let w else { return nil }
        return w.resetsAt <= now ? LimitWindow(usedPercent: 0, resetsAt: w.resetsAt) : w
    }

    enum UsageAlert: Equatable { case fiveHour(Double), sevenDay(Double) }

    static let fiveHourThresholds: [Double] = [80, 95]
    static let sevenDayThresholds: [Double] = [90]

    static func alerts(old: ClaudeLimits?, new: ClaudeLimits) -> [UsageAlert] {
        guard let old else { return [] }
        func previous(_ o: LimitWindow?, _ n: LimitWindow) -> Double {
            guard let o, abs(o.resetsAt.timeIntervalSince(n.resetsAt)) < 600 else { return 0 }
            return o.usedPercent
        }
        var out: [UsageAlert] = []
        if let n = new.fiveHour, let t = crossed(previous: previous(old.fiveHour, n), current: n.usedPercent, thresholds: fiveHourThresholds) {
            out.append(.fiveHour(t))
        }
        if let n = new.sevenDay, let t = crossed(previous: previous(old.sevenDay, n), current: n.usedPercent, thresholds: sevenDayThresholds) {
            out.append(.sevenDay(t))
        }
        return out
    }

    static func crossed(previous: Double, current: Double, thresholds: [Double]) -> Double? {
        thresholds.filter { previous < $0 && current >= $0 }.max()
    }

    private static let isoFractional: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()
    private static let iso = ISO8601DateFormatter()

    static func date(_ s: String?) -> Date? {
        guard let s else { return nil }
        return isoFractional.date(from: s) ?? iso.date(from: s)
    }

    static func parseLogLine(_ line: Substring) -> UsageRecord? {
        guard line.contains("\"assistant\""), line.contains("\"usage\""),
              let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              json["type"] as? String == "assistant",
              let message = json["message"] as? [String: Any],
              let usage = message["usage"] as? [String: Any],
              let date = date(json["timestamp"] as? String) else { return nil }
        let id = message["id"] as? String ?? json["uuid"] as? String ?? ""
        let cwd = json["cwd"] as? String ?? ""
        let record = UsageRecord(key: "\(id):\(json["requestId"] as? String ?? "")", date: date,
                           project: cwd.isEmpty ? "?" : (cwd as NSString).lastPathComponent,
                           model: message["model"] as? String ?? "?",
                           input: usage["input_tokens"] as? Int ?? 0, output: usage["output_tokens"] as? Int ?? 0,
                           cacheRead: usage["cache_read_input_tokens"] as? Int ?? 0,
                           cacheWrite: usage["cache_creation_input_tokens"] as? Int ?? 0)
        return record.total > 0 ? record : nil
    }

    private static func isOwn(_ statusLine: Any?) -> Bool {
        ((statusLine as? [String: Any])?["command"] as? String)?.hasSuffix(" " + statusCommandSuffix) == true
    }

    static func statusCommand(settings: Data) -> String? {
        ((try? JSONSerialization.jsonObject(with: settings)) as? [String: Any]).flatMap { ($0["statusLine"] as? [String: Any])?["command"] as? String }
    }

    static func isLinked(settings: Data?) -> Bool {
        guard let settings, let d = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any] else { return false }
        return isOwn(d["statusLine"])
    }

    static func connect(settings: Data?, command: String) throws -> Data {
        var d: [String: Any] = [:]
        if let settings, !settings.isEmpty {
            guard let parsed = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any] else { throw LinkError.invalidSettings }
            d = parsed
        }
        if let existing = d["statusLine"], !isOwn(existing) { throw LinkError.foreignStatusLine }
        d["statusLine"] = ["type": "command", "command": command, "padding": 0]
        return try JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func disconnect(settings: Data) -> Data? {
        guard var d = (try? JSONSerialization.jsonObject(with: settings)) as? [String: Any], isOwn(d["statusLine"]) else { return nil }
        d.removeValue(forKey: "statusLine")
        return try? JSONSerialization.data(withJSONObject: d, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    static func parseCodex(_ line: Substring, now: Date) -> (primary: LimitWindow?, secondary: LimitWindow?)? {
        guard line.contains("rate_limits"),
              let json = (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any],
              let payload = json["payload"] as? [String: Any],
              let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        func w(_ any: Any?) -> LimitWindow? {
            guard let d = any as? [String: Any], let used = number(d["used_percent"]) else { return nil }
            if let at = number(d["resets_at"]) { return LimitWindow(usedPercent: used, resetsAt: Date(timeIntervalSince1970: at)) }
            if let s = number(d["resets_in_seconds"]) { return LimitWindow(usedPercent: used, resetsAt: now.addingTimeInterval(s)) }
            return nil
        }
        let p = w(limits["primary"]), s = w(limits["secondary"])
        return p == nil && s == nil ? nil : (p, s)
    }
}
