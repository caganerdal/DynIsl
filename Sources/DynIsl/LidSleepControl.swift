import AppKit

@MainActor
final class LidSleepControl: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var working = false
    @Published private(set) var recoveryNeeded = false

    nonisolated static let sudoersPath = "/etc/sudoers.d/dynisl"
    private static let engagedKey = "lidSleepEngaged"
    private let queue = DispatchQueue(label: "local.dynamicisland.lid")

    init() {
        refresh()
    }

    func refresh() {
        isInstalled = FileManager.default.fileExists(atPath: Self.sudoersPath)
    }

    func install() async -> Bool {
        let user = NSUserName()
        guard !user.isEmpty, user.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || "._-".contains($0)) }) else { return false }
        let line = KeepAwakeRules.sudoersContent(user: user).trimmingCharacters(in: .newlines)
        let script = "T=$(/usr/bin/mktemp /private/tmp/dynisl.XXXXXX) || exit 1; "
            + "/usr/bin/printf '%s\\n' \(Self.quoted(line)) > \"$T\" && /usr/sbin/visudo -cf \"$T\" "
            + "&& /usr/bin/install -m 0440 -o root -g wheel \"$T\" \(Self.sudoersPath); R=$?; /bin/rm -f \"$T\"; exit $R"
        let ok = await runAsAdmin(script)
        refresh()
        return ok && isInstalled
    }

    func uninstall() async -> Bool {
        let ok = await runAsAdmin("/usr/bin/pmset -a disablesleep 0; /bin/rm -f \(Self.sudoersPath)")
        UserDefaults.standard.removeObject(forKey: Self.engagedKey)
        refresh()
        return ok && !isInstalled
    }

    @discardableResult
    func setDisabled(_ on: Bool) async -> Bool {
        let ok = await withCheckedContinuation { c in queue.async { c.resume(returning: Self.pmset(on)) } }
        record(on, ok)
        return ok
    }

    @discardableResult
    func setDisabledNow(_ on: Bool) -> Bool {
        let ok = queue.sync { Self.pmset(on) }
        record(on, ok)
        return ok
    }

    private func record(_ on: Bool, _ ok: Bool) {
        guard ok else { return }
        if on { UserDefaults.standard.set(true, forKey: Self.engagedKey) } else { UserDefaults.standard.removeObject(forKey: Self.engagedKey) }
    }

    private nonisolated static func pmset(_ on: Bool) -> Bool {
        run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]) == 0
    }

    nonisolated func currentlyDisabled() -> Bool {
        let pipe = Pipe()
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        p.arguments = ["-g"]
        p.standardOutput = pipe
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return false }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return KeepAwakeRules.sleepDisabled(fromPmsetOutput: String(decoding: data, as: UTF8.self))
    }

    func recoverIfNeeded() {
        guard UserDefaults.standard.bool(forKey: Self.engagedKey) else { return }
        Task {
            guard !(await setDisabled(false)) else { return }
            let stillDisabled = await withCheckedContinuation { c in queue.async { c.resume(returning: self.currentlyDisabled()) } }
            if stillDisabled { recoveryNeeded = true } else { UserDefaults.standard.removeObject(forKey: Self.engagedKey) }
        }
    }

    func restoreSleepWithAdmin() async -> Bool {
        let ok = await runAsAdmin("/usr/bin/pmset -a disablesleep 0")
        let stillDisabled = await withCheckedContinuation { c in queue.async { c.resume(returning: self.currentlyDisabled()) } }
        if ok, !stillDisabled {
            UserDefaults.standard.removeObject(forKey: Self.engagedKey)
            recoveryNeeded = false
            return true
        }
        return false
    }

    private func runAsAdmin(_ command: String) async -> Bool {
        working = true
        defer { working = false }
        let escaped = command.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        let source = "do shell script \"\(escaped)\" with administrator privileges"
        return await Task.detached(priority: .userInitiated) {
            var err: NSDictionary?
            NSAppleScript(source: source)?.executeAndReturnError(&err)
            return err == nil
        }.value
    }

    private nonisolated static func run(_ path: String, _ args: [String]) -> Int32 {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        p.standardOutput = FileHandle.nullDevice
        p.standardError = FileHandle.nullDevice
        guard (try? p.run()) != nil else { return -1 }
        p.waitUntilExit()
        return p.terminationStatus
    }

    private static func quoted(_ s: String) -> String {
        "'" + s.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
