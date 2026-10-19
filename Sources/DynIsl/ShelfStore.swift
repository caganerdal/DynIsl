import AppKit

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let key = "shelfItems"
    private let bookmarkKey = "shelfBookmarks"
    let limit = 12

    init() {
        if let marks = UserDefaults.standard.array(forKey: bookmarkKey) as? [Data] {
            items = marks.compactMap { data in
                var stale = false
                return try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale)
            }
        } else {
            items = (UserDefaults.standard.stringArray(forKey: key) ?? []).map { URL(fileURLWithPath: $0) }
            UserDefaults.standard.removeObject(forKey: key)
        }
        prune()
        save()
    }

    func add(_ urls: [URL]) {
        for url in urls where url.isFileURL && !items.contains(url) {
            items.append(url)
        }
        if items.count > limit { items.removeFirst(items.count - limit) }
        save()
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        iconCache[url] = nil
        save()
    }

    func clear() {
        items.removeAll()
        iconCache.removeAll()
        save()
    }

    func prune() {
        refreshMovedItems()
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        if existing.count != items.count {
            items = existing
            save()
        }
    }

    @Published private(set) var converting = false
    var onConverted: ((ShelfConversion, ShelfConverter.Result) -> Void)?

    func convert(_ kind: ShelfConversion) {
        let inputs = kind.inputs(from: items)
        guard !inputs.isEmpty, !converting else { return }
        converting = true
        DispatchQueue.global(qos: .userInitiated).async {
            let result = ShelfConverter.run(kind, on: inputs)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.converting = false
                    self.add(result.outputs)
                    self.onConverted?(kind, result)
                }
            }
        }
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }

    private var iconCache: [URL: NSImage] = [:]

    func icon(for url: URL) -> NSImage {
        if let i = iconCache[url] { return i }
        let i = NSWorkspace.shared.icon(forFile: url.path)
        iconCache[url] = i
        return i
    }

    private var bookmarks: [URL: Data] = [:]

    private func refreshMovedItems() {
        var changed = false
        items = items.map { url in
            guard let data = bookmarks[url] else { return url }
            var stale = false
            guard let resolved = try? URL(resolvingBookmarkData: data, options: [.withoutUI], bookmarkDataIsStale: &stale),
                  resolved.standardizedFileURL != url.standardizedFileURL else { return url }
            changed = true
            return resolved
        }
        if changed { save() }
    }

    private func save() {
        var next: [URL: Data] = [:]
        for url in items {
            if let d = bookmarks[url] ?? (try? url.bookmarkData()) { next[url] = d }
        }
        bookmarks = next
        UserDefaults.standard.set(items.compactMap { next[$0] }, forKey: bookmarkKey)
    }
}
