import Foundation

enum CLI {
    static let usageNotificationName = Notification.Name("local.dynamicisland.ai-usage")
    static let usageURL = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/DynamicIsland/ai-usage.json")

    static func runIfNeeded() -> Int32? {
        let args = CommandLine.arguments.dropFirst().filter { !$0.hasPrefix("-psn_") && !$0.hasPrefix("-NS") && $0 != "YES" }
        guard args.first == "claude-status" else { return nil }
        return claudeStatus()
    }

    static func readUsage() -> ClaudeLimits? {
        (try? Data(contentsOf: usageURL)).flatMap { try? JSONDecoder().decode(ClaudeLimits.self, from: $0) }
    }

    @discardableResult
    static func writeUsage(_ limits: ClaudeLimits) -> Bool {
        guard let out = try? JSONEncoder().encode(limits) else { return false }
        let dir = usageURL.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let tmp = dir.appendingPathComponent(".ai-usage-\(getpid()).json")
        guard FileManager.default.createFile(atPath: tmp.path, contents: out, attributes: [.posixPermissions: 0o600]),
              rename(tmp.path, usageURL.path) == 0 else {
            try? FileManager.default.removeItem(at: tmp)
            return false
        }
        return true
    }

    private static func claudeStatus() -> Int32 {
        let data = FileHandle.standardInput.readDataToEndOfFile()
        let now = Date()
        guard let new = AIUsageRules.parseStatus(data, now: now) else {
            print("Claude")
            return 0
        }
        let old = readUsage()
        let merged = AIUsageRules.merge(old: old, new: new)
        if AIUsageRules.shouldWrite(old: old, new: merged), writeUsage(merged) {
            DistributedNotificationCenter.default().postNotificationName(usageNotificationName, object: nil, userInfo: nil, deliverImmediately: true)
        }
        var shown = merged
        shown.fiveHour = AIUsageRules.effective(merged.fiveHour, now: now)
        shown.sevenDay = AIUsageRules.effective(merged.sevenDay, now: now)
        print(AIUsageRules.statusLine(shown, five: String(localized: "5s"), week: String(localized: "hafta"), percent: { pc(Int($0.rounded())) }))
        return 0
    }
}
