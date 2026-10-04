import AppKit

enum DownloadKind: String, CaseIterable, Identifiable {
    case installers, archives, videos, images, documents, audio, folders, other
    var id: String { rawValue }

    var title: String {
        switch self {
        case .installers: return "Kurulum dosyaları"
        case .archives: return "Arşivler"
        case .videos: return "Videolar"
        case .images: return "Görseller"
        case .documents: return "Belgeler"
        case .audio: return "Ses"
        case .folders: return "Klasörler"
        case .other: return "Diğer"
        }
    }

    var icon: String {
        switch self {
        case .installers: return "shippingbox.fill"
        case .archives: return "archivebox.fill"
        case .videos: return "film.fill"
        case .images: return "photo.fill"
        case .documents: return "doc.text.fill"
        case .audio: return "waveform"
        case .folders: return "folder.fill"
        case .other: return "doc.fill"
        }
    }

    var selectedByDefault: Bool { self == .installers || self == .archives }

    static func of(_ url: URL, isFolder: Bool, isApp: Bool) -> DownloadKind {
        if isApp { return .installers }
        if isFolder { return .folders }
        let ext = url.pathExtension.lowercased()
        if ext == "xip" { return .installers }
        switch DesktopCategory.allCases.first(where: { $0.extensions.contains(ext) }) {
        case .installers: return .installers
        case .archives: return .archives
        case .videos: return .videos
        case .images, .design: return .images
        case .audio: return .audio
        case .pdf, .documents, .spreadsheets, .presentations, .code: return .documents
        default: return .other
        }
    }
}

struct OldDownload: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let lastUsed: Date
    let opened: Bool
    let kind: DownloadKind
    var name: String { url.lastPathComponent }
}

@MainActor
final class DownloadsCleaner: ObservableObject {
    @Published private(set) var items: [OldDownload] = []
    @Published private(set) var totalSize: Int64 = 0
    @Published private(set) var scanning = false
    @Published private(set) var message: String?
    @Published private(set) var lastTrashed: [(from: URL, to: URL)] = []

    let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]

    func scan() {
        guard !scanning else { return }
        scanning = true
        let folder = self.folder
        DispatchQueue.global(qos: .utility).async {
            let found = Self.list(in: folder)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.items = found
                    self.totalSize = found.reduce(0) { $0 + $1.size }
                    self.scanning = false
                }
            }
        }
    }

    nonisolated static func list(in dir: URL) -> [OldDownload] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .isPackageKey, .isSymbolicLinkKey, .totalFileAllocatedSizeKey,
                                      .fileAllocatedSizeKey, .addedToDirectoryDateKey, .creationDateKey]
        guard let urls = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                     options: [.skipsHiddenFiles]) else { return [] }
        let downloading: Set<String> = ["download", "crdownload", "part", "partial"]
        return urls.compactMap { url -> OldDownload? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), v.isSymbolicLink != true,
                  !downloading.contains(url.pathExtension.lowercased()) else { return nil }
            let isDir = v.isDirectory == true
            let isApp = isDir && url.pathExtension.lowercased() == "app"
            let size = isDir ? folderSize(url) : Int64(v.totalFileAllocatedSize ?? v.fileAllocatedSize ?? 0)
            let added = v.addedToDirectoryDate ?? v.creationDate ?? Date()
            var used: Date?
            if let md = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) {
                used = MDItemCopyAttribute(md, kMDItemLastUsedDate) as? Date
            }
            let last = max(used ?? added, added)
            return OldDownload(url: url, size: size, lastUsed: last, opened: used.map { $0 > added } ?? false,
                                kind: .of(url, isFolder: isDir, isApp: isApp))
        }
        .sorted { $0.size > $1.size }
    }

    private nonisolated static func folderSize(_ url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let e = FileManager.default.enumerator(at: url, includingPropertiesForKeys: keys) else { return 0 }
        var total: Int64 = 0
        for case let f as URL in e {
            let v = try? f.resourceValues(forKeys: Set(keys))
            total += Int64(v?.totalFileAllocatedSize ?? v?.fileAllocatedSize ?? 0)
        }
        return total
    }

    func moveToTrash(_ list: [OldDownload]) {
        guard !list.isEmpty else { return }
        var moved: [(URL, URL)] = []
        var failed = 0
        for item in list {
            var result: NSURL?
            do {
                try FileManager.default.trashItem(at: item.url, resultingItemURL: &result)
                if let r = result as URL? { moved.append((item.url, r)) }
            } catch {
                failed += 1
            }
        }
        lastTrashed = moved
        let size = ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file)
        message = failed == 0
            ? "\(moved.count) öğe (\(size)) Çöp Sepeti'ne taşındı"
            : "\(moved.count) öğe taşındı, \(failed) öğe taşınamadı (açık ya da kilitli olabilir)"
        scan()
    }

    func undo() {
        let fm = FileManager.default
        var back = 0
        for m in lastTrashed where fm.fileExists(atPath: m.to.path) && !fm.fileExists(atPath: m.from.path) {
            if (try? fm.moveItem(at: m.to, to: m.from)) != nil { back += 1 }
        }
        lastTrashed = []
        message = "\(back) öğe İndirilenler'e geri taşındı"
        scan()
    }

    func dismissMessage() {
        message = nil
        lastTrashed = []
    }

    func reveal(_ item: OldDownload) { NSWorkspace.shared.activateFileViewerSelecting([item.url]) }
    func openFolder() { NSWorkspace.shared.open(folder) }
}
