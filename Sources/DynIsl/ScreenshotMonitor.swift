import AppKit
import ImageIO
import UniformTypeIdentifiers

struct Screenshot: Equatable {
    let url: URL
    let thumbnail: NSImage
    let date: Date
}

@MainActor
final class ScreenshotMonitor: ObservableObject {
    @Published private(set) var current: Screenshot?

    var onNew: ((Screenshot) -> Void)?

    private let query = NSMetadataQuery()
    private var dismissWork: DispatchWorkItem?
    private var seen: Set<URL> = []

    func start() {
        query.predicate = NSPredicate(format: "kMDItemIsScreenCapture == 1")
        query.searchScopes = [NSMetadataQueryUserHomeScope]
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidFinishGathering, object: query, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.markExistingAsSeen() }
        }
        NotificationCenter.default.addObserver(forName: .NSMetadataQueryDidUpdate, object: query, queue: .main) { [weak self] note in
            let added = note.userInfo?[NSMetadataQueryUpdateAddedItemsKey] as? [NSMetadataItem] ?? []
            let urls = added.compactMap { ($0.value(forAttribute: NSMetadataItemPathKey) as? String).map(URL.init(fileURLWithPath:)) }
            MainActor.assumeIsolated { self?.handle(urls) }
        }
        query.start()
    }

    private func markExistingAsSeen() {
        query.disableUpdates()
        for i in 0..<query.resultCount {
            if let item = query.result(at: i) as? NSMetadataItem,
               let path = item.value(forAttribute: NSMetadataItemPathKey) as? String {
                seen.insert(URL(fileURLWithPath: path))
            }
        }
        query.enableUpdates()
    }

    private func handle(_ urls: [URL]) {
        for url in urls where !seen.contains(url) {
            seen.insert(url)
            let created = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? .distantPast
            guard Date().timeIntervalSince(created) < 20,
                  UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true,
                  let thumb = Self.thumbnail(for: url) else { continue }
            let shot = Screenshot(url: url, thumbnail: thumb, date: Date())
            current = shot
            onNew?(shot)
            scheduleDismiss(after: 6)
        }
    }

    func hold() {
        dismissWork?.cancel()
        dismissWork = nil
    }

    func release() {
        if current != nil, dismissWork == nil { scheduleDismiss(after: 2) }
    }

    func dismiss() {
        dismissWork?.cancel()
        dismissWork = nil
        current = nil
    }

    private func scheduleDismiss(after seconds: TimeInterval) {
        dismissWork?.cancel()
        let work = DispatchWorkItem { [weak self] in
            MainActor.assumeIsolated { self?.current = nil; self?.dismissWork = nil }
        }
        dismissWork = work
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds, execute: work)
    }

    func copy(_ shot: Screenshot) {
        let pb = NSPasteboard.general
        pb.clearContents()
        if let img = NSImage(contentsOf: shot.url) { pb.writeObjects([img, shot.url as NSURL]) }
        dismiss()
    }

    func open(_ shot: Screenshot) {
        NSWorkspace.shared.open(shot.url)
        dismiss()
    }

    func trash(_ shot: Screenshot) {
        NSWorkspace.shared.recycle([shot.url])
        dismiss()
    }

    private static func thumbnail(for url: URL) -> NSImage? {
        guard let src = CGImageSourceCreateWithURL(url as CFURL, nil) else { return nil }
        let opts: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceThumbnailMaxPixelSize: 480,
            kCGImageSourceCreateThumbnailWithTransform: true,
        ]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(src, 0, opts as CFDictionary) else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
