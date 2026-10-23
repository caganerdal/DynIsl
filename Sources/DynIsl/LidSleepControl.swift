import AppKit

@MainActor
final class LidSleepControl: ObservableObject {
    @Published private(set) var isInstalled = false
    @Published private(set) var working = false

    nonisolated static let sudoersPath = "/etc/sudoers.d/dynisl"
    private static let engagedKey = "lidSleepEngaged"

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
    func setDisabled(_ on: Bool) -> Bool {
        let ok = Self.run("/usr/bin/sudo", ["-n", "/usr/bin/pmset", "-a", "disablesleep", on ? "1" : "0"]) == 0
        if ok {
            if on { UserDefaults.standard.set(true, forKey: Self.engagedKey) } else { UserDefaults.standard.removeObject(forKey: Self.engagedKey) }
        }
        return ok
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
        if !setDisabled(false) { UserDefaults.standard.removeObject(forKey: Self.engagedKey) }
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
