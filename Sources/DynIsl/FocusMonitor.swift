import AppKit
import SwiftUI

struct FocusMode: Equatable {
    var id: String
    var name: String
    var symbol: String
    var tint: Color
}

@MainActor
final class FocusMonitor: ObservableObject {
    @Published private(set) var current: FocusMode?
    @Published private(set) var needsPermission = false

    var onActivity: ((IslandActivity) -> Void)?
    private var timer: Timer?
    private var started = false

    private static let dbDir = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/DoNotDisturb/DB")

    private var watcher: DispatchSourceFileSystemObject?

    func start() {
        refresh(notify: false)
        started = true
        watchDirectory()
        timer = Timer.repeating(every: 20) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.refresh(notify: true)
                if self.watcher == nil { self.watchDirectory() }
            }
        }
    }

    private func watchDirectory() {
        let fd = open(Self.dbDir.path, O_EVTONLY)
        guard fd >= 0 else { return }
        let src = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .rename, .delete], queue: .main)
        src.setEventHandler { [weak self] in
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                MainActor.assumeIsolated { self?.refresh(notify: true) }
            }
        }
        src.setCancelHandler { close(fd) }
        src.resume()
        watcher = src
    }

    func openPermissionSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
            NSWorkspace.shared.open(url)
        }
    }

    private func refresh(notify: Bool) {
        var assertions: Any = [String: Any]()
        do {
            let data = try Data(contentsOf: Self.dbDir.appendingPathComponent("Assertions.json"))
            assertions = try JSONSerialization.jsonObject(with: data)
            if needsPermission { needsPermission = false }
        } catch {
            switch (error as NSError).code {
            case NSFileReadNoPermissionError:
                if !needsPermission { needsPermission = true }
                return
            case NSFileReadNoSuchFileError:
                break
            default:
                return
            }
        }

        let newMode = Self.activeModeID(in: assertions).map(Self.mode(for:))
        guard newMode != current else { return }
        let old = current
        current = newMode

        guard notify else { return }
        if let m = newMode {
            onActivity?(.init(icon: m.symbol, tint: m.tint, title: m.name, trailing: String(localized: "Açık")))
        } else if let o = old {
            onActivity?(.init(icon: o.symbol, tint: .gray, title: o.name, trailing: String(localized: "Kapandı")))
        }
    }

    private static func activeModeID(in json: Any) -> String? {
        var records: [[String: Any]] = []
        collect(key: "storeAssertionRecords", in: json, into: &records)
        for record in records.reversed() {
            var ids: [String] = []
            collectStrings(key: "assertionDetailsModeIdentifier", in: record, into: &ids)
            if let id = ids.first { return id }
        }
        return nil
    }

    private static func mode(for id: String) -> FocusMode {
        var fallback = FocusMode(id: id, name: defaultName(for: id), symbol: "moon.fill", tint: .indigo)
        guard let data = try? Data(contentsOf: dbDir.appendingPathComponent("ModeConfigurations.json")),
              let json = try? JSONSerialization.jsonObject(with: data),
              let mode = findMode(id: id, in: json) else { return fallback }
        if let name = mode["name"] as? String, !name.isEmpty { fallback.name = name }
        if let symbol = mode["symbolImageName"] as? String, NSImage(systemSymbolName: symbol, accessibilityDescription: nil) != nil {
            fallback.symbol = symbol
        }
        if let tint = mode["tintColorName"] as? String { fallback.tint = color(named: tint) }
        return fallback
    }

    private static func defaultName(for id: String) -> String {
        if id.hasSuffix(".default") { return String(localized: "Rahatsız Etme") }
        if id.contains("sleep") { return String(localized: "Uyku") }
        if id.contains("work") { return String(localized: "İş") }
        if id.contains("personal") { return String(localized: "Kişisel") }
        if id.contains("driving") { return String(localized: "Araç Kullanma") }
        return String(localized: "Odak")
    }

    private static func findMode(id: String, in json: Any) -> [String: Any]? {
        if let dict = json as? [String: Any] {
            if dict["modeIdentifier"] as? String == id, dict["name"] != nil { return dict }
            for v in dict.values { if let m = findMode(id: id, in: v) { return m } }
        } else if let arr = json as? [Any] {
            for v in arr { if let m = findMode(id: id, in: v) { return m } }
        }
        return nil
    }

    private static func collect(key: String, in json: Any, into out: inout [[String: Any]]) {
        if let dict = json as? [String: Any] {
            for (k, v) in dict {
                if k == key, let arr = v as? [[String: Any]] { out.append(contentsOf: arr) }
                else { collect(key: key, in: v, into: &out) }
            }
        } else if let arr = json as? [Any] {
            for v in arr { collect(key: key, in: v, into: &out) }
        }
    }

    private static func collectStrings(key: String, in json: Any, into out: inout [String]) {
        if let dict = json as? [String: Any] {
            for (k, v) in dict {
                if k == key, let s = v as? String { out.append(s) }
                else { collectStrings(key: key, in: v, into: &out) }
            }
        } else if let arr = json as? [Any] {
            for v in arr { collectStrings(key: key, in: v, into: &out) }
        }
    }

    private static func color(named name: String) -> Color {
        let n = name.lowercased()
        let table: [(String, Color)] = [
            ("indigo", .indigo), ("purple", .purple), ("pink", .pink), ("red", .red),
            ("orange", .orange), ("yellow", .yellow), ("green", .green), ("mint", .mint),
            ("teal", .teal), ("cyan", .cyan), ("blue", .blue), ("brown", .brown), ("gray", .gray),
        ]
        return table.first { n.contains($0.0) }?.1 ?? .indigo
    }
}
