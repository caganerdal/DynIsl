import AppKit

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var items: [URL] = []

    private let key = "shelfItems"
    let limit = 12

    init() {
        let paths = UserDefaults.standard.stringArray(forKey: key) ?? []
        items = paths.map { URL(fileURLWithPath: $0) }
        prune()
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

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: key)
    }
}
