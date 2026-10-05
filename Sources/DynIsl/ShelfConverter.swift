import AppKit
import ImageIO
import PDFKit
import Quartz
import UniformTypeIdentifiers

enum ShelfConversion: CaseIterable, Identifiable {
    case toJPEG, shrink, mergePDF, compressPDF
    var id: Self { self }

    var title: String {
        switch self {
        case .toJPEG: return "JPG'ye çevir"
        case .shrink: return "Görselleri küçült"
        case .mergePDF: return "Tek PDF yap"
        case .compressPDF: return "PDF'i sıkıştır"
        }
    }

    var icon: String {
        switch self {
        case .toJPEG: return "photo"
        case .shrink: return "arrow.down.right.and.arrow.up.left"
        case .mergePDF: return "doc.on.doc"
        case .compressPDF: return "doc.zipper"
        }
    }

    func inputs(from urls: [URL]) -> [URL] {
        switch self {
        case .toJPEG: return urls.filter { ShelfConverter.isImage($0) && !["jpg", "jpeg"].contains($0.pathExtension.lowercased()) }
        case .shrink: return urls.filter(ShelfConverter.isImage)
        case .mergePDF:
            let list = urls.filter { ShelfConverter.isImage($0) || ShelfConverter.isPDF($0) }
            return list.count >= 2 || list.contains(where: ShelfConverter.isImage) ? list : []
        case .compressPDF: return urls.filter(ShelfConverter.isPDF)
        }
    }
}

enum ShelfConverter {
    struct Result {
        var outputs: [URL] = []
        var saved: Int64 = 0
        var skipped = 0
        var failed = 0
    }

    static func isImage(_ url: URL) -> Bool {
        UTType(filenameExtension: url.pathExtension)?.conforms(to: .image) == true && !isPDF(url)
    }

    static func isPDF(_ url: URL) -> Bool { url.pathExtension.lowercased() == "pdf" }

    static func run(_ kind: ShelfConversion, on urls: [URL]) -> Result {
        var r = Result()
        switch kind {
        case .toJPEG:
            for u in urls {
                let out = unique(folder(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + ".jpg"))
                if writeJPEG(from: u, to: out, maxPixel: nil, quality: 0.9) { r.outputs.append(out) } else { r.failed += 1 }
            }
        case .shrink:
            for u in urls {
                let out = unique(folder(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + " (küçük).jpg"))
                guard writeJPEG(from: u, to: out, maxPixel: 1600, quality: 0.75) else { r.failed += 1; continue }
                let delta = size(u) - size(out)
                if delta <= 0 { try? FileManager.default.removeItem(at: out); r.skipped += 1; continue }
                r.saved += delta
                r.outputs.append(out)
            }
        case .mergePDF:
            let doc = PDFDocument()
            for u in urls {
                if isPDF(u), let src = PDFDocument(url: u) {
                    for i in 0..<src.pageCount { if let p = src.page(at: i) { doc.insert(p, at: doc.pageCount) } }
                } else if let img = NSImage(contentsOf: u), let page = PDFPage(image: img) {
                    doc.insert(page, at: doc.pageCount)
                } else {
                    r.failed += 1
                }
            }
            let f = DateFormatter()
            f.dateFormat = "yyyy-MM-dd HH.mm"
            let out = unique(folder(for: urls[0]).appendingPathComponent("Birleştirilmiş \(f.string(from: Date())).pdf"))
            if doc.pageCount > 0, doc.write(to: out) { r.outputs.append(out) } else { r.failed += 1 }
        case .compressPDF:
            for u in urls {
                guard let doc = PDFDocument(url: u) else { r.failed += 1; continue }
                let out = unique(folder(for: u).appendingPathComponent(u.deletingPathExtension().lastPathComponent + " (küçük).pdf"))
                guard let filter = reduceFilter,
                      doc.write(to: out, withOptions: [PDFDocumentWriteOption(rawValue: "QuartzFilter"): filter]) else {
                    r.failed += 1; continue
                }
                let delta = size(u) - size(out)
                if delta <= size(u) / 20 { try? FileManager.default.removeItem(at: out); r.skipped += 1; continue }
                r.saved += delta
                r.outputs.append(out)
            }
        }
        return r
    }

    private static var reduceFilter: QuartzFilter? {
        QuartzFilter(url: URL(fileURLWithPath: "/System/Library/Filters/Reduce File Size.qfilter"))
    }

    private static func writeJPEG(from src: URL, to dst: URL, maxPixel: Int?, quality: Double) -> Bool {
        guard let source = CGImageSourceCreateWithURL(src as CFURL, nil) else { return false }
        var opts: [CFString: Any] = [kCGImageSourceCreateThumbnailWithTransform: true,
                                     kCGImageSourceCreateThumbnailFromImageAlways: true]
        if let maxPixel {
            opts[kCGImageSourceThumbnailMaxPixelSize] = maxPixel
        } else if let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any] {
            let w = props[kCGImagePropertyPixelWidth] as? Int ?? 4096
            let h = props[kCGImagePropertyPixelHeight] as? Int ?? 4096
            opts[kCGImageSourceThumbnailMaxPixelSize] = max(w, h)
        }
        guard let image = CGImageSourceCreateThumbnailAtIndex(source, 0, opts as CFDictionary),
              let dest = CGImageDestinationCreateWithURL(dst as CFURL, UTType.jpeg.identifier as CFString, 1, nil) else { return false }
        CGImageDestinationAddImage(dest, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        return CGImageDestinationFinalize(dest)
    }

    private static func folder(for url: URL) -> URL {
        let dir = url.deletingLastPathComponent()
        if FileManager.default.isWritableFile(atPath: dir.path) { return dir }
        return FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    private static func size(_ url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
    }

    private static func unique(_ url: URL) -> URL {
        let fm = FileManager.default
        guard fm.fileExists(atPath: url.path) else { return url }
        let base = url.deletingPathExtension().lastPathComponent, ext = url.pathExtension
        var i = 2
        while true {
            let c = url.deletingLastPathComponent().appendingPathComponent("\(base) \(i).\(ext)")
            if !fm.fileExists(atPath: c.path) { return c }
            i += 1
        }
    }
}
