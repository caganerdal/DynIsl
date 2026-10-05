import AppKit

struct DownloadItem: Identifiable, Equatable {
    let id: ObjectIdentifier
    var name: String
    var fraction: Double?
}

@MainActor
final class DownloadMonitor: ObservableObject {
    @Published private(set) var active: [DownloadItem] = []

    var onFinished: ((URL) -> Void)?

    private var subscriber: Any?
    private var tracked: [ObjectIdentifier: Progress] = [:]
    private var timer: Timer?

    private static let tempExtensions = ["download", "crdownload", "part", "partial"]

    let directory = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    func start() {
        subscriber = Progress.addSubscriber(forFileURL: directory) { [weak self] progress in
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self?.track(progress) }
            }
            return {
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.finish(progress) }
                }
            }
        }
    }

    var summary: DownloadItem? {
        guard let first = active.first else { return nil }
        guard active.count > 1 else { return first }
        let known = active.compactMap(\.fraction)
        let avg = known.isEmpty ? nil : known.reduce(0, +) / Double(known.count)
        return DownloadItem(id: first.id, name: String(localized: "\(active.count) indirme"), fraction: avg)
    }

    private func track(_ progress: Progress) {
        let kind = progress.userInfo[.fileOperationKindKey] as? Progress.FileOperationKind
        guard kind == nil || kind == .downloading else { return }
        let id = ObjectIdentifier(progress)
        guard tracked[id] == nil else { return }
        tracked[id] = progress
        active.append(DownloadItem(id: id, name: Self.displayName(for: progress), fraction: Self.fraction(of: progress)))
        if timer == nil {
            timer = Timer.repeating(every: 0.5, tolerance: 0.2) { [weak self] _ in
                MainActor.assumeIsolated { self?.poll() }
            }
        }
    }

    private func poll() {
        var changed = active
        for i in changed.indices {
            if let p = tracked[changed[i].id] { changed[i].fraction = Self.fraction(of: p) }
        }
        if changed != active { active = changed }
    }

    private func finish(_ progress: Progress) {
        let id = ObjectIdentifier(progress)
        guard tracked.removeValue(forKey: id) != nil else { return }
        active.removeAll { $0.id == id }
        if tracked.isEmpty { timer?.invalidate(); timer = nil }

        guard !progress.isCancelled, let url = Self.fileURL(of: progress) else { return }
        let finalURL = Self.stripTempExtension(url)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { [weak self] in
            MainActor.assumeIsolated {
                if FileManager.default.fileExists(atPath: finalURL.path) {
                    self?.onFinished?(finalURL)
                }
            }
        }
    }

    private static func fraction(of p: Progress) -> Double? {
        guard p.totalUnitCount > 0 else { return nil }
        return min(max(p.fractionCompleted, 0), 1)
    }

    private static func fileURL(of p: Progress) -> URL? {
        p.fileURL ?? (p.userInfo[.fileURLKey] as? URL)
    }

    private static func displayName(for p: Progress) -> String {
        if let url = fileURL(of: p) { return stripTempExtension(url).lastPathComponent }
        return String(localized: "İndirme")
    }

    static func stripTempExtension(_ url: URL) -> URL {
        tempExtensions.contains(url.pathExtension.lowercased()) ? url.deletingPathExtension() : url
    }
}
