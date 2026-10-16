import AppKit
import Charts
import SwiftUI

struct DesktopPage: View {
    @EnvironmentObject var cleaner: DesktopCleaner
    @State private var age = 0
    @State private var excluded: Set<DesktopCategory> = []
    @State private var focus: DesktopCategory?

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(age) * 86400)
        let candidates = cleaner.files.filter { age == 0 || $0.date < cutoff }
        let selected = candidates.filter { !excluded.contains($0.category) }
        let byCategory = Dictionary(grouping: candidates, by: \.category)
        let shown = focus.map { c in candidates.filter { $0.category == c } } ?? candidates

        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = cleaner.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg)
                    Spacer()
                    if !cleaner.lastMoves.isEmpty { Button("Geri al") { cleaner.undo() } }
                    Button("Masaüstünü aç") { NSWorkspace.shared.open(cleaner.desktop) }
                    Button { cleaner.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.12)))
            }

            Card(title: "Masaüstü", icon: "wand.and.stars", tint: .mint) {
                if candidates.isEmpty {
                    Text(cleaner.scanning ? "Taranıyor…" : "Masaüstünde düzenlenecek dosya yok ✨")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 200), spacing: 10)], spacing: 10) {
                        ForEach(DesktopCategory.allCases.filter { byCategory[$0] != nil }) { c in
                            let list = byCategory[c] ?? []
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { !excluded.contains(c) },
                                    set: { on in if on { excluded.remove(c) } else { excluded.insert(c) } }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                Image(systemName: c.icon).foregroundStyle(.mint).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(c.folder).font(.callout.weight(.medium))
                                    Text("\(list.count) dosya · \(ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .fill(focus == c ? Color.mint.opacity(0.18) : Color.primary.opacity(0.04)))
                            .contentShape(Rectangle())
                            .onTapGesture { focus = focus == c ? nil : c }
                            .opacity(excluded.contains(c) ? 0.5 : 1)
                        }
                    }

                    Divider()
                    HStack {
                        Text(focus.map { "\($0.folder) (\(shown.count))" } ?? "Tüm dosyalar (\(shown.count))")
                            .font(.subheadline).foregroundStyle(.secondary)
                        Spacer()
                        if focus != nil { Button("Tümünü göster") { focus = nil }.buttonStyle(.borderless) }
                    }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 140), spacing: 12)], spacing: 12) {
                        ForEach(shown.prefix(60)) { f in DesktopTile(file: f) }
                    }
                    if shown.count > 60 {
                        Text("+\(shown.count - 60) dosya daha").font(.caption).foregroundStyle(.secondary)
                    }
                }
            }

            Text("Her tür masaüstündeki kendi klasörüne, onun içinde ay klasörüne gider (ör. Masaüstü › PDF'ler › 2026-09 Eylül). Klasörlere, proje klasörlerine, kısayollara ve tanınmayan dosya türlerine dokunulmaz. Hiçbir dosya silinmez; son düzenleme geri alınabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text("\(selected.count) dosya seçildi").font(.callout.weight(.medium))
                    Text("Toplam \(ByteCountFormatter.string(fromByteCount: selected.reduce(0) { $0 + $1.size }, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Divider().frame(height: 22)
                Picker("", selection: $age) {
                    Text("Tümü").tag(0)
                    Text("1 haftadan eski").tag(7)
                    Text("1 aydan eski").tag(30)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                Spacer(minLength: 16)
                Button { cleaner.organize(selected) } label: {
                    Label("Düzenle", systemImage: "wand.and.stars").padding(.horizontal, 4)
                }
                .glassButton(prominent: true)
                .tint(.mint)
                .controlSize(.large)
                .disabled(selected.isEmpty)
            }
            .floatingGlassBar()
            .animation(.easeOut(duration: 0.15), value: selected.count)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { NSWorkspace.shared.open(cleaner.desktop) } label: { Label("Masaüstünü aç", systemImage: "folder") }
                    .help("Masaüstünü aç")
                Button { cleaner.scan() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .help("Yeniden tara")
            }
        }
        .onAppear { cleaner.scan() }
    }
}

struct DesktopTile: View {
    @EnvironmentObject var cleaner: DesktopCleaner
    let file: DesktopFile
    @State private var hover = false

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            ZStack {
                RoundedRectangle(cornerRadius: 8, style: .continuous).fill(.quaternary)
                if let img = cleaner.thumbnails[file.url] {
                    Image(nsImage: img).resizable().aspectRatio(contentMode: .fit).padding(file.category == .screenshots || file.category == .images ? 0 : 10)
                } else {
                    Image(systemName: file.category.icon).font(.title2).foregroundStyle(.secondary)
                }
            }
            .frame(height: 84)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous).stroke(.white.opacity(hover ? 0.4 : 0), lineWidth: 2))
            Text(file.name).font(.caption).lineLimit(1).truncationMode(.middle)
            Text("\(file.category.folder) · \(ByteCountFormatter.string(fromByteCount: file.size, countStyle: .file))")
                .font(.caption2).foregroundStyle(.secondary).lineLimit(1)
        }
        .onHover { hover = $0 }
        .onTapGesture(count: 2) { cleaner.open(file) }
        .contextMenu {
            Button("Aç") { cleaner.open(file) }
            Button("Finder'da göster") { cleaner.reveal(file) }
            Divider()
            Button("Sadece bunu düzenle") { cleaner.organize([file]) }
        }
        .help("Çift tıkla aç · sağ tıkla seçenekler")
    }
}

struct DownloadsPage: View {
    @EnvironmentObject var cleaner: DownloadsCleaner
    @State private var age = 90
    @State private var kinds: Set<DownloadKind> = Set(DownloadKind.allCases.filter(\.selectedByDefault))
    @State private var unchecked: Set<URL> = []
    @State private var confirm = false

    var body: some View {
        let cutoff = Date().addingTimeInterval(-Double(age) * 86400)
        let candidates = cleaner.items.filter { $0.lastUsed < cutoff }
        let byKind = Dictionary(grouping: candidates, by: \.kind)
        let shown = candidates.filter { kinds.contains($0.kind) }
        let selected = shown.filter { !unchecked.contains($0.url) }
        let selectedSize = selected.reduce(0) { $0 + $1.size }

        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            if let msg = cleaner.message {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                    Text(msg)
                    Spacer()
                    if !cleaner.lastTrashed.isEmpty { Button("Geri al") { cleaner.undo() } }
                    Button { cleaner.dismissMessage() } label: { Image(systemName: "xmark") }.buttonStyle(.borderless)
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 10, style: .continuous).fill(Color.green.opacity(0.12)))
            }

            Card(title: "İndirilenler", icon: "arrow.down.circle.fill", tint: .orange) {
                Stat(label: "Klasörün tamamı", value: ByteCountFormatter.string(fromByteCount: cleaner.totalSize, countStyle: .file))

                if candidates.isEmpty {
                    Text(cleaner.scanning ? "Taranıyor…" : "Bu süredir açılmamış öğe yok ✨")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, minHeight: 60)
                } else {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 10)], spacing: 10) {
                        ForEach(DownloadKind.allCases.filter { byKind[$0] != nil }) { k in
                            let list = byKind[k] ?? []
                            HStack(spacing: 8) {
                                Toggle("", isOn: Binding(
                                    get: { kinds.contains(k) },
                                    set: { on in if on { kinds.insert(k) } else { kinds.remove(k) } }
                                ))
                                .toggleStyle(.checkbox)
                                .labelsHidden()
                                Image(systemName: k.icon).foregroundStyle(.orange).frame(width: 18)
                                VStack(alignment: .leading, spacing: 1) {
                                    Text(k.title).font(.callout.weight(.medium))
                                    Text("\(list.count) öğe · \(ByteCountFormatter.string(fromByteCount: list.reduce(0) { $0 + $1.size }, countStyle: .file))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                            }
                            .padding(8)
                            .background(RoundedRectangle(cornerRadius: 8, style: .continuous).fill(Color.primary.opacity(0.04)))
                            .opacity(kinds.contains(k) ? 1 : 0.5)
                        }
                    }

                    if !shown.isEmpty {
                        Divider()
                        VStack(spacing: 0) {
                            ForEach(shown.prefix(150)) { item in
                                HStack(spacing: 10) {
                                    Toggle("", isOn: Binding(
                                        get: { !unchecked.contains(item.url) },
                                        set: { on in if on { unchecked.remove(item.url) } else { unchecked.insert(item.url) } }
                                    ))
                                    .toggleStyle(.checkbox)
                                    .labelsHidden()
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: item.url.path))
                                        .resizable().frame(width: 20, height: 20)
                                    Text(item.name).lineLimit(1).truncationMode(.middle)
                                    Spacer(minLength: 12)
                                    Text(item.opened ? "Son açılış \(item.lastUsed.formatted(.relative(presentation: .named)))"
                                                     : "Hiç açılmadı · \(item.lastUsed.formatted(.relative(presentation: .named))) indirildi")
                                        .font(.caption).foregroundStyle(.secondary)
                                        .frame(width: 230, alignment: .trailing)
                                    Text(ByteCountFormatter.string(fromByteCount: item.size, countStyle: .file))
                                        .font(.callout.monospacedDigit())
                                        .frame(width: 80, alignment: .trailing)
                                }
                                .padding(.vertical, 5)
                                .opacity(unchecked.contains(item.url) ? 0.5 : 1)
                                .contentShape(Rectangle())
                                .contextMenu { Button("Finder'da göster") { cleaner.reveal(item) } }
                                .onTapGesture(count: 2) { cleaner.reveal(item) }
                            }
                        }
                        if shown.count > 150 {
                            Text("+\(shown.count - 150) öğe daha").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Text("Seçtiğin süredir açılmamış dosya ve klasörler en büyükten küçüğe listelenir. Varsayılan olarak sadece kurulum dosyaları ve arşivler seçilidir. Hiçbir şey kalıcı olarak silinmez: öğeler Çöp Sepeti'ne gider ve son işlem geri alınabilir.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 1) {
                    Text(String(localized: "\(selected.count) öğe seçildi")).font(.callout.weight(.medium))
                    Text("Açılacak yer \(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file))")
                        .font(.caption).foregroundStyle(.secondary).monospacedDigit()
                        .contentTransition(.numericText())
                }
                Divider().frame(height: 22)
                Picker("", selection: $age) {
                    Text("1 ay").tag(30)
                    Text("3 ay").tag(90)
                    Text("6 ay").tag(180)
                    Text("1 yıl").tag(365)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help("Bu süredir açılmamış öğeler listelenir")
                Spacer(minLength: 16)
                Button(role: .destructive) { confirm = true } label: {
                    Label("Çöp Sepeti'ne taşı", systemImage: "trash.fill").padding(.horizontal, 4)
                }
                .glassButton(prominent: true)
                .tint(.orange)
                .controlSize(.large)
                .disabled(selected.isEmpty)
            }
            .floatingGlassBar()
            .animation(.easeOut(duration: 0.15), value: selectedSize)
        }
        .toolbar {
            ToolbarItemGroup {
                Button { cleaner.openFolder() } label: { Label("İndirilenler'i aç", systemImage: "folder") }
                    .help("İndirilenler'i aç")
                Button { cleaner.scan() } label: { Label("Yeniden tara", systemImage: "arrow.clockwise") }
                    .help("Yeniden tara")
            }
        }
        .onAppear { cleaner.scan() }
        .alert("\(selected.count) öğe Çöp Sepeti'ne taşınsın mı?", isPresented: $confirm) {
            Button("Taşı", role: .destructive) {
                cleaner.moveToTrash(selected)
                unchecked.removeAll()
            }
            Button("Vazgeç", role: .cancel) {}
        } message: {
            Text("\(ByteCountFormatter.string(fromByteCount: selectedSize, countStyle: .file)) yer açılacak. Çöp Sepeti boşaltılana kadar geri alabilirsin.")
        }
    }
}

struct ConvertPage: View {
    @State private var files: [URL] = []
    @State private var targeted = false
    @State private var busy: ShelfConversion?
    @State private var outputs: [URL] = []
    @State private var message: String?

    var body: some View {
        PageScroll {
        VStack(alignment: .leading, spacing: 16) {
            Card(title: "Dosyalar", icon: "arrow.triangle.2.circlepath", tint: .indigo) {
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.indigo.opacity(targeted ? 0.16 : 0.05))
                        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .strokeBorder(style: StrokeStyle(lineWidth: 1.2, dash: files.isEmpty ? [6, 5] : []))
                            .foregroundStyle(Color.indigo.opacity(targeted ? 0.9 : 0.35)))
                    if files.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "square.and.arrow.down.on.square").font(.system(size: 28)).foregroundStyle(.indigo)
                            Text("Görsel ya da PDF dosyalarını buraya sürükle").font(.callout.weight(.medium))
                            Button("Dosya seç…") { pick() }
                        }
                        .padding(28)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(files, id: \.self) { url in
                                HStack(spacing: 10) {
                                    Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                                    Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                                    Spacer()
                                    Text(fileSize(url)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                                    Button { files.removeAll { $0 == url } } label: { Image(systemName: "xmark.circle.fill") }
                                        .buttonStyle(.borderless).foregroundStyle(.secondary)
                                }
                                .padding(.vertical, 5)
                            }
                            HStack {
                                Button("Dosya ekle…") { pick() }
                                Spacer()
                                Button("Listeyi temizle") { files.removeAll(); outputs.removeAll(); message = nil }
                            }
                            .padding(.top, 8)
                        }
                        .padding(12)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    add(urls)
                    return true
                } isTargeted: { targeted = $0 }
            }

            if let message {
                Card(title: "Sonuç", icon: "checkmark.circle.fill", tint: .green) {
                    Text(message)
                    ForEach(outputs, id: \.self) { url in
                        HStack(spacing: 10) {
                            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().frame(width: 20, height: 20)
                            Text(url.lastPathComponent).lineLimit(1).truncationMode(.middle)
                            Spacer()
                            Text(fileSize(url)).font(.callout.monospacedDigit()).foregroundStyle(.secondary)
                            Button("Finder'da göster") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        }
                    }
                }
            }

            Text("Yeni dosyalar asıl dosyaların yanına kaydedilir; asıl dosyalara dokunulmaz. Küçültme görsellerin en uzun kenarını 1600 piksele indirir. Her şey bilgisayarda yapılır, hiçbir dosya internete yüklenmez.")
                .font(.caption).foregroundStyle(.secondary)
        }
        } bar: {
            HStack(spacing: 8) {
                ForEach(ShelfConversion.allCases) { c in
                    let count = c.inputs(from: files).count
                    Button { run(c) } label: {
                        Label(count > 0 ? "\(c.title) (\(count))" : c.title, systemImage: c.icon)
                    }
                    .glassButton(prominent: count > 0)
                    .tint(.indigo)
                    .disabled(count == 0 || busy != nil)
                }
                Spacer(minLength: 8)
                if busy != nil { ProgressView().controlSize(.small).padding(.trailing, 8) }
            }
            .floatingGlassBar()
        }
        .toolbar {
            ToolbarItem {
                Button { pick() } label: { Label("Dosya seç…", systemImage: "plus") }
                    .help("Dosya seç…")
            }
        }
    }

    private func add(_ urls: [URL]) {
        for u in urls where u.isFileURL && !files.contains(u)
            && (ShelfConverter.isImage(u) || ShelfConverter.isPDF(u)) { files.append(u) }
    }

    private func pick() {
        let panel = NSOpenPanel()
        panel.allowsMultipleSelection = true
        panel.canChooseDirectories = false
        panel.allowedContentTypes = [.image, .pdf]
        if panel.runModal() == .OK { add(panel.urls) }
    }

    private func run(_ kind: ShelfConversion) {
        let inputs = kind.inputs(from: files)
        guard !inputs.isEmpty else { return }
        busy = kind
        DispatchQueue.global(qos: .userInitiated).async {
            let r = ShelfConverter.run(kind, on: inputs)
            DispatchQueue.main.async {
                busy = nil
                outputs = r.outputs
                let saved = ByteCountFormatter.string(fromByteCount: r.saved, countStyle: .file)
                var parts = [String(localized: "\(kind.title): \(r.outputs.count) dosya hazır")]
                if r.saved > 0 { parts.append(String(localized: "\(saved) yer kazanıldı")) }
                if r.skipped > 0 { parts.append(String(localized: "\(r.skipped) dosya zaten küçük")) }
                if r.failed > 0 { parts.append(String(localized: "\(r.failed) dosya dönüştürülemedi")) }
                message = parts.joined(separator: " · ")
            }
        }
    }

    private func fileSize(_ url: URL) -> String {
        ByteCountFormatter.string(fromByteCount: Int64((try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0), countStyle: .file)
    }
}
