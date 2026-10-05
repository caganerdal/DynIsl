import AppKit

@MainActor
final class UpdateChecker: ObservableObject {
    struct Release: Equatable {
        let version: String
        let url: URL
        let notes: String
    }

    @Published private(set) var available: Release?
    @Published private(set) var checking = false
    @Published private(set) var lastResult: String?

    var enabled = true { didSet { if enabled { checkIfDue() } } }
    var onActivity: ((IslandActivity) -> Void)?

    static let current = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
    static let sourcePath = Bundle.main.infoDictionary?["DynIslSourcePath"] as? String
    private static let api = URL(string: "https://api.github.com/repos/caganerdal/DynIsl/releases/latest")!
    private static let interval: TimeInterval = 24 * 3600

    private let d = UserDefaults.standard
    private var timer: Timer?
    private var wakeObserver: NSObjectProtocol?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.checkIfDue() }
        }
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                MainActor.assumeIsolated { self?.checkIfDue() }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in self?.checkIfDue() }
    }

    func checkIfDue() {
        guard enabled else { return }
        let last = d.object(forKey: "updateLastCheck") as? Date ?? .distantPast
        if Date().timeIntervalSince(last) >= Self.interval { check(manual: false) }
    }

    func check(manual: Bool) {
        guard !checking else { return }
        checking = true
        var req = URLRequest(url: Self.api, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 15)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("DynIsl/\(Self.current)", forHTTPHeaderField: "User-Agent")
        URLSession.shared.dataTask(with: req) { data, response, _ in
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let json = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.finish(status: status, json: json, manual: manual) }
            }
        }.resume()
    }

    private func finish(status: Int, json: [String: Any]?, manual: Bool) {
        checking = false
        guard status == 200 || status == 404 else {
            lastResult = "Denetlenemedi, internet bağlantını kontrol et"
            if manual { onActivity?(.init(icon: "exclamationmark.triangle.fill", tint: .orange, title: "Güncelleme", trailing: "Denetlenemedi")) }
            return
        }
        d.set(Date(), forKey: "updateLastCheck")
        guard let json, let tag = json["tag_name"] as? String,
              let page = (json["html_url"] as? String).flatMap(URL.init(string:)),
              page.host == "github.com",
              Self.isNewer(tag, than: Self.current) else {
            available = nil
            lastResult = "Güncelsin (v\(Self.current))"
            if manual { onActivity?(.init(icon: "checkmark.seal.fill", tint: .green, title: "Güncelsin", trailing: "v\(Self.current)")) }
            return
        }
        let version = Self.clean(tag)
        available = Release(version: version, url: page, notes: String((json["body"] as? String ?? "").prefix(2000)))
        lastResult = "Yeni sürüm var: v\(version)"
        if manual || d.string(forKey: "updateNotifiedVersion") != version {
            d.set(version, forKey: "updateNotifiedVersion")
            onActivity?(.init(icon: "arrow.down.app.fill", tint: .blue, title: "Yeni sürüm", trailing: "v\(version)"))
        }
    }

    static func reportProblem() {
        var size = 0
        sysctlbyname("hw.model", nil, &size, nil, 0)
        var model = [CChar](repeating: 0, count: max(size, 1))
        sysctlbyname("hw.model", &model, &size, nil, 0)
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        let os = ProcessInfo.processInfo.operatingSystemVersion
        let body = """
        **Ne oldu?**


        **Ne bekliyordun?**


        **Nasıl tekrar edilir?** (biliyorsan)


        ---
        DynIsl \(current) (yapı \(build)) · macOS \(os.majorVersion).\(os.minorVersion).\(os.patchVersion) · \(String(cString: model))
        """
        var c = URLComponents(string: "https://github.com/caganerdal/DynIsl/issues/new")!
        c.queryItems = [URLQueryItem(name: "body", value: body)]
        if let url = c.url { NSWorkspace.shared.open(url) }
    }

    func openReleasePage() {
        if let url = available?.url { NSWorkspace.shared.open(url) }
    }

    var updateCommand: String {
        let dir = Self.sourcePath.map { "cd '" + $0.replacingOccurrences(of: "'", with: "'\\''") + "'" } ?? "cd DynIsl"
        return "\(dir) && git pull --ff-only && ./build-app.sh install"
    }

    var canRunUpdate: Bool {
        guard let p = Self.sourcePath else { return false }
        return FileManager.default.fileExists(atPath: p + "/build-app.sh") && FileManager.default.fileExists(atPath: p + "/.git")
    }

    func runUpdate() {
        guard canRunUpdate else { return }
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("DynIsl", isDirectory: true)
        let file = dir.appendingPathComponent("guncelle.command")
        let script = "#!/bin/zsh\n\(updateCommand)\necho\necho \"Bitti, bu pencereyi kapatabilirsin.\"\n"
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try script.write(to: file, atomically: true, encoding: .utf8)
            try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: file.path)
            NSWorkspace.shared.open(file)
        } catch {
            copyCommand()
        }
    }

    func copyCommand() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(updateCommand, forType: .string)
    }

    static func clean(_ tag: String) -> String {
        tag.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: CharacterSet(charactersIn: "vV"))
    }

    static func isNewer(_ tag: String, than current: String) -> Bool {
        let a = clean(tag).split(separator: ".").map { Int($0) ?? 0 }
        let b = clean(current).split(separator: ".").map { Int($0) ?? 0 }
        for i in 0..<max(a.count, b.count) {
            let x = i < a.count ? a[i] : 0, y = i < b.count ? b[i] : 0
            if x != y { return x > y }
        }
        return false
    }
}
