import AppKit
import QuickLookThumbnailing

enum DesktopCategory: String, CaseIterable, Identifiable {
    case screenshots, pdf, documents, spreadsheets, presentations, code, images, design, videos, audio, archives, installers
    var id: String { rawValue }

    var folder: String {
        switch self {
        case .screenshots: return String(localized: "Ekran Görüntüleri")
        case .pdf: return String(localized: "PDF'ler")
        case .documents: return String(localized: "Belgeler")
        case .spreadsheets: return String(localized: "Tablolar")
        case .presentations: return String(localized: "Sunumlar")
        case .code: return String(localized: "Kod")
        case .images: return String(localized: "Görseller")
        case .design: return String(localized: "Tasarımlar")
        case .videos: return String(localized: "Videolar")
        case .audio: return String(localized: "Ses")
        case .archives: return String(localized: "Arşivler")
        case .installers: return String(localized: "Kurulum Dosyaları")
        }
    }

    var icon: String {
        switch self {
        case .screenshots: return "camera.viewfinder"
        case .pdf: return "doc.richtext.fill"
        case .documents: return "doc.text.fill"
        case .spreadsheets: return "tablecells.fill"
        case .presentations: return "rectangle.on.rectangle.angled.fill"
        case .code: return "chevron.left.forwardslash.chevron.right"
        case .images: return "photo.fill"
        case .design: return "paintbrush.pointed.fill"
        case .videos: return "film.fill"
        case .audio: return "waveform"
        case .archives: return "archivebox.fill"
        case .installers: return "shippingbox.fill"
        }
    }

    var extensions: Set<String> {
        switch self {
        case .screenshots: return []
        case .pdf: return ["pdf"]
        case .documents: return ["doc", "docx", "pages", "odt", "rtf", "txt", "md", "tex"]
        case .spreadsheets: return ["xls", "xlsx", "xlsm", "numbers", "csv", "ods", "tsv"]
        case .presentations: return ["ppt", "pptx", "key", "odp"]
        case .code: return ["swift", "py", "ipynb", "java", "kt", "c", "h", "cpp", "hpp", "cc", "cs", "m", "mm",
                            "js", "ts", "jsx", "tsx", "html", "css", "scss", "json", "xml", "yml", "yaml", "toml",
                            "sh", "zsh", "pl", "pro", "go", "rs", "rb", "php", "sql", "r", "dart", "lua", "asm", "hs", "scala"]
        case .images: return ["png", "jpg", "jpeg", "heic", "heif", "gif", "webp", "tiff", "tif", "bmp", "svg",
                              "cr2", "cr3", "nef", "arw", "dng", "raf", "orf", "rw2"]
        case .design: return ["psd", "ai", "afdesign", "afphoto", "afpub", "sketch", "fig", "xd", "indd"]
        case .videos: return ["mov", "mp4", "m4v", "avi", "mkv", "webm"]
        case .audio: return ["mp3", "wav", "aif", "aiff", "flac", "m4a", "ogg", "flp", "mid", "midi"]
        case .archives: return ["zip", "rar", "7z", "tar", "gz", "tgz", "bz2", "xz"]
        case .installers: return ["dmg", "pkg", "mpkg", "iso"]
        }
    }
}

struct DesktopFile: Identifiable, Equatable {
    var id: URL { url }
    let url: URL
    let size: Int64
    let date: Date
    let category: DesktopCategory
    var name: String { url.lastPathComponent }
}

@MainActor
final class DesktopCleaner: ObservableObject {
    @Published private(set) var files: [DesktopFile] = []
    @Published private(set) var thumbnails: [URL: NSImage] = [:]
    @Published private(set) var lastMoves: [(from: URL, to: URL)] = []
    @Published private(set) var message: String?
    @Published private(set) var scanning = false

    let desktop = FileManager.default.urls(for: .desktopDirectory, in: .userDomainMask)[0]

    func folder(for category: DesktopCategory) -> URL {
        desktop.appendingPathComponent(category.folder, isDirectory: true)
    }

    func scan() {
        scanning = true
        let desktop = self.desktop
        DispatchQueue.global(qos: .utility).async {
            let found = Self.classify(in: desktop)
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self.files = found
                    self.scanning = false
                    self.loadThumbnails()
                }
            }
        }
    }

    nonisolated static func classify(in dir: URL) -> [DesktopFile] {
        let keys: [URLResourceKey] = [.fileSizeKey, .creationDateKey, .addedToDirectoryDateKey, .isRegularFileKey,
                                      .isAliasFileKey, .isSymbolicLinkKey, .isPackageKey]
        guard let items = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: keys,
                                                                      options: [.skipsHiddenFiles]) else { return [] }
        let downloading: Set<String> = ["download", "crdownload", "part", "partial"]
        let shotPrefixes = ["ekran resmi", "ekran kaydı", "screenshot", "screen shot", "screen recording"]
        return items.compactMap { url -> DesktopFile? in
            guard let v = try? url.resourceValues(forKeys: Set(keys)),
                  v.isRegularFile == true, v.isAliasFile != true, v.isSymbolicLink != true, v.isPackage != true else { return nil }
            let ext = url.pathExtension.lowercased()
            guard !downloading.contains(ext) else { return nil }

            let category: DesktopCategory
            if isScreenCapture(url, prefixes: shotPrefixes) {
                category = .screenshots
            } else if let c = DesktopCategory.allCases.first(where: { $0.extensions.contains(ext) }) {
                category = c
            } else {
                return nil
            }
            let date = (category == .screenshots ? dateInName(url.lastPathComponent) : nil)
                ?? v.addedToDirectoryDate ?? v.creationDate ?? Date()
            return DesktopFile(url: url, size: Int64(v.fileSize ?? 0), date: date, category: category)
        }
        .sorted { $0.date > $1.date }
    }

    private nonisolated static func isScreenCapture(_ url: URL, prefixes: [String]) -> Bool {
        let ext = url.pathExtension.lowercased()
        guard ["png", "jpg", "jpeg", "heic", "tiff", "mov", "mp4"].contains(ext) else { return false }
        if let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL),
           let flag = MDItemCopyAttribute(item, "kMDItemIsScreenCapture" as CFString) as? Bool, flag {
            return true
        }
        let lower = url.lastPathComponent.lowercased()
        return prefixes.contains { lower.hasPrefix($0) }
    }

    private nonisolated static func dateInName(_ name: String) -> Date? {
        guard let r = name.range(of: #"\d{4}-\d{2}-\d{2}"#, options: .regularExpression) else { return nil }
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f.date(from: String(name[r]))
    }

    private func loadThumbnails() {
        for f in files.prefix(80) where thumbnails[f.url] == nil {
            let req = QLThumbnailGenerator.Request(fileAt: f.url, size: CGSize(width: 160, height: 100),
                                                   scale: 2, representationTypes: .all)
            QLThumbnailGenerator.shared.generateBestRepresentation(for: req) { [weak self] rep, _ in
                guard let img = rep?.nsImage else { return }
                DispatchQueue.main.async {
                    MainActor.assumeIsolated { self?.thumbnails[f.url] = img }
                }
            }
        }
    }

    func organize(_ list: [DesktopFile]) {
        guard !list.isEmpty else { return }
        let fm = FileManager.default
        let month = DateFormatter()
        month.locale = appLocale
        month.dateFormat = "yyyy-MM LLLL"
        var moves: [(URL, URL)] = []
        var failed = 0
        for f in list {
            let dir = folder(for: f.category).appendingPathComponent(month.string(from: f.date), isDirectory: true)
            do {
                try fm.createDirectory(at: dir, withIntermediateDirectories: true)
                let dest = Self.uniqueURL(dir.appendingPathComponent(f.name))
                try fm.moveItem(at: f.url, to: dest)
                moves.append((f.url, dest))
            } catch {
                failed += 1
            }
        }
        lastMoves = moves
        let size = ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file)
        let kinds = Set(list.map(\.category)).count
        message = failed == 0
            ? String(localized: "\(moves.count) dosya (\(size)) \(kinds) klasöre düzenlendi")
            : String(localized: "\(moves.count) dosya düzenlendi, \(failed) dosya taşınamadı (açık ya da kilitli olabilir)")
        scan()
    }

    func undo() {
        let fm = FileManager.default
        var back = 0
        for m in lastMoves where fm.fileExists(atPath: m.to.path) {
            if (try? fm.moveItem(at: m.to, to: Self.uniqueURL(m.from))) != nil { back += 1 }
        }
        for m in lastMoves {
            let monthDir = m.to.deletingLastPathComponent()
            for dir in [monthDir, monthDir.deletingLastPathComponent()] {
                if let c = try? fm.contentsOfDirectory(atPath: dir.path), c.filter({ $0 != ".DS_Store" }).isEmpty {
                    try? fm.removeItem(at: dir)
                }
            }
        }
        lastMoves = []
        message = String(localized: "\(back) dosya masaüstüne geri taşındı")
        scan()
    }

    func openFolder(_ c: DesktopCategory) {
        let url = folder(for: c)
        NSWorkspace.shared.open(FileManager.default.fileExists(atPath: url.path) ? url : desktop)
    }

    func reveal(_ f: DesktopFile) { NSWorkspace.shared.activateFileViewerSelecting([f.url]) }
    func open(_ f: DesktopFile) { NSWorkspace.shared.open(f.url) }

    func purge() {
        files = []
        thumbnails = [:]
    }

    func dismissMessage() {
        message = nil
        lastMoves = []
    }

    private static func uniqueURL(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var i = 2
        while true {
            let name = ext.isEmpty ? "\(base) \(i)" : "\(base) \(i).\(ext)"
            let candidate = url.deletingLastPathComponent().appendingPathComponent(name)
            if !fm.fileExists(atPath: candidate.path) { return candidate }
            i += 1
        }
    }
}
