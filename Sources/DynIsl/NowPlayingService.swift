import AppKit
import SwiftUI

enum MediaSource: String, CaseIterable {
    case spotify, music

    var bundleID: String {
        switch self {
        case .spotify: return "com.spotify.client"
        case .music: return "com.apple.Music"
        }
    }

    var scriptName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Music"
        }
    }

    var displayName: String {
        switch self {
        case .spotify: return "Spotify"
        case .music: return "Apple Music"
        }
    }

    var isRunning: Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty
    }

    private static var iconCache: [MediaSource: NSImage] = [:]

    @MainActor var appIcon: NSImage? {
        if let cached = Self.iconCache[self] { return cached }
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        let icon = NSWorkspace.shared.icon(forFile: url.path)
        Self.iconCache[self] = icon
        return icon
    }
}

enum RepeatMode: String {
    case off, all, one

    var symbol: String { self == .one ? "repeat.1" : "repeat" }
}

struct NowPlayingInfo: Equatable {
    var source: MediaSource
    var title: String
    var artist: String
    var album: String
    var duration: Double
    var position: Double
    var isPlaying: Bool
    var trackID: String
    var artworkURL: String?
    var volume: Int
    var shuffle: Bool
    var repeatMode: RepeatMode
    var favorited: Bool
    var disliked: Bool
    var muted: Bool
    var shareURI: String?
}

@MainActor
final class NowPlayingService: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?
    @Published private(set) var artwork: NSImage?
    @Published private(set) var artworkID = 0
    @Published private(set) var direction = 1
    @Published private(set) var accent: Color = .white
    @Published private(set) var permissionDenied = false

    private var anchor: (position: Double, date: Date) = (0, .distantPast)
    private var preferred: MediaSource?
    private var artworkKey: String?
    private var pollTimer: Timer?
    private let queue = DispatchQueue(label: "dynamicisland.applescript")

    var isPlaying: Bool { info?.isPlaying ?? false }

    var isVisible = false {
        didSet { if isVisible && !oldValue { refresh() } }
    }

    var elapsed: Double {
        guard let info else { return 0 }
        let p = info.isPlaying ? anchor.position + Date().timeIntervalSince(anchor.date) : anchor.position
        return min(max(p, 0), info.duration)
    }

    init() {
        let dnc = DistributedNotificationCenter.default()
        dnc.addObserver(forName: .init("com.spotify.client.PlaybackStateChanged"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferred = .spotify; self?.refresh() }
        }
        dnc.addObserver(forName: .init("com.apple.Music.playerInfo"), object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.preferred = .music; self?.refresh() }
        }
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
        pollTimer = Timer.repeating(every: 5) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.isPlaying, self.isVisible else { return }
                self.refresh()
            }
        }
        refresh()
    }

    func refresh() {
        var sources = MediaSource.allCases.filter(\.isRunning)
        if let p = preferred, let i = sources.firstIndex(of: p) {
            sources.swapAt(0, i)
        }
        guard !sources.isEmpty else {
            apply(nil, denied: false)
            return
        }
        queue.async {
            var results: [NowPlayingInfo] = []
            var denied = false
            for s in sources {
                switch Self.query(s) {
                case .success(let i?): results.append(i)
                case .success(nil): break
                case .failure(let e): if e.code == -1743 { denied = true }
                }
            }
            let pick = results.first(where: \.isPlaying) ?? results.first
            DispatchQueue.main.async {
                MainActor.assumeIsolated { self.apply(pick, denied: denied) }
            }
        }
    }

    private func apply(_ new: NowPlayingInfo?, denied: Bool) {
        let deniedNow = denied && new == nil
        if permissionDenied != deniedNow { permissionDenied = deniedNow }
        if info != new { info = new }
        anchor = (new?.position ?? 0, Date())
        if let new {
            let key = "\(new.source.rawValue):\(new.trackID)"
            if key != artworkKey {
                artworkKey = key
                loadArtwork(for: new)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
                    MainActor.assumeIsolated { self.direction = 1 }
                }
            }
        } else {
            artworkKey = nil
            artwork = nil
            accent = .white
        }
    }

    struct ScriptError: Error { let code: Int }

    private nonisolated static let sep = "|~|"

    private nonisolated static func query(_ source: MediaSource) -> Result<NowPlayingInfo?, ScriptError> {
        guard source.isRunning else { return .success(nil) }
        let script: String
        switch source {
        case .spotify:
            script = """
            tell application "Spotify"
                set s to player state as string
                if s is "stopped" then return "stopped"
                set t to current track
                set art to ""
                try
                    set art to artwork url of t
                end try
                set u to ""
                try
                    set u to spotify url of t
                end try
                return s & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (duration of t) & "\(sep)" & player position & "\(sep)" & (id of t) & "\(sep)" & art & "\(sep)" & (sound volume as string) & "\(sep)" & (shuffling as string) & "\(sep)" & (repeating as string) & "\(sep)false\(sep)false\(sep)false\(sep)" & u
            end tell
            """
        case .music:
            script = """
            tell application "Music"
                set s to player state as string
                if s is "stopped" then return "stopped"
                set t to current track
                set fav to false
                set dis to false
                try
                    set fav to favorited of t
                    set dis to disliked of t
                end try
                return s & "\(sep)" & (name of t) & "\(sep)" & (artist of t) & "\(sep)" & (album of t) & "\(sep)" & (duration of t) & "\(sep)" & player position & "\(sep)" & (persistent ID of t) & "\(sep)" & "" & "\(sep)" & (sound volume as string) & "\(sep)" & (shuffle enabled as string) & "\(sep)" & (song repeat as string) & "\(sep)" & (fav as string) & "\(sep)" & (dis as string) & "\(sep)" & (mute as string) & "\(sep)" & ""
            end tell
            """
        }
        switch run(script, cache: true) {
        case .failure(let e): return .failure(e)
        case .success(let d):
            guard let str = d.stringValue, str != "stopped" else { return .success(nil) }
            let f = str.components(separatedBy: sep)
            guard f.count >= 15 else { return .success(nil) }
            let num = { (s: String) in Double(s.replacingOccurrences(of: ",", with: ".")) ?? 0 }
            var duration = num(f[4])
            if source == .spotify { duration /= 1000 }
            let volume = Int(num(f[8]))
            let repeatMode: RepeatMode = source == .spotify
                ? (f[10] == "true" ? .all : .off)
                : (RepeatMode(rawValue: f[10]) ?? .off)
            return .success(NowPlayingInfo(
                source: source, title: f[1], artist: f[2], album: f[3],
                duration: max(duration, 1), position: num(f[5]),
                isPlaying: f[0] == "playing", trackID: f[6],
                artworkURL: f[7].isEmpty ? nil : f[7],
                volume: volume, shuffle: f[9] == "true", repeatMode: repeatMode,
                favorited: f[11] == "true", disliked: f[12] == "true",
                muted: source == .spotify ? volume == 0 : f[13] == "true",
                shareURI: f[14].isEmpty ? nil : f[14]
            ))
        }
    }

    private nonisolated(unsafe) static var compiled: [String: NSAppleScript] = [:]

    private nonisolated static func run(_ source: String, cache: Bool = false) -> Result<NSAppleEventDescriptor, ScriptError> {
        var err: NSDictionary?
        let script: NSAppleScript
        if cache, let s = compiled[source] {
            script = s
        } else {
            guard let s = NSAppleScript(source: source) else { return .failure(ScriptError(code: -1)) }
            if cache { compiled[source] = s }
            script = s
        }
        let result = script.executeAndReturnError(&err)
        if let err { return .failure(ScriptError(code: err[NSAppleScript.errorNumber] as? Int ?? -1)) }
        return .success(result)
    }

    func playPause() {
        guard var i = info else { return }
        i.isPlaying.toggle()
        anchor = (elapsed, Date())
        info = i
        send("playpause")
    }

    func next() {
        direction = 1
        send("next track")
    }

    func previous() {
        direction = -1
        send(info?.source == .music ? "back track" : "previous track")
    }

    func seek(to fraction: Double) {
        guard let i = info else { return }
        let target = min(max(fraction, 0), 1) * i.duration
        anchor = (target, Date())
        objectWillChange.send()
        send(String(format: "set player position to %.2f", target))
    }

    private var lastVolumeSend = Date.distantPast
    private var volumeBeforeMute = 50

    func setVolume(_ v: Int, final: Bool = false) {
        guard var i = info else { return }
        let v = min(max(v, 0), 100)
        i.volume = v
        if i.source == .spotify { i.muted = v == 0 }
        info = i
        if final || Date().timeIntervalSince(lastVolumeSend) > 0.08 {
            lastVolumeSend = Date()
            send("set sound volume to \(v)", refreshAfter: final)
        }
    }

    func toggleMute() {
        guard var i = info else { return }
        switch i.source {
        case .music:
            i.muted.toggle()
            info = i
            send("set mute to \(i.muted)")
        case .spotify:
            if i.volume > 0 {
                volumeBeforeMute = i.volume
                setVolume(0, final: true)
            } else {
                setVolume(volumeBeforeMute, final: true)
            }
        }
    }

    func toggleShuffle() {
        guard var i = info else { return }
        i.shuffle.toggle()
        info = i
        send(i.source == .spotify ? "set shuffling to \(i.shuffle)" : "set shuffle enabled to \(i.shuffle)")
    }

    func cycleRepeat() {
        guard var i = info else { return }
        switch i.source {
        case .spotify:
            i.repeatMode = i.repeatMode == .off ? .all : .off
            send("set repeating to \(i.repeatMode != .off)")
        case .music:
            i.repeatMode = switch i.repeatMode { case .off: .all; case .all: .one; case .one: .off }
            send("set song repeat to \(i.repeatMode.rawValue)")
        }
        info = i
    }

    func toggleFavorite() {
        guard var i = info, i.source == .music else { return }
        i.favorited.toggle()
        if i.favorited { i.disliked = false }
        info = i
        send("set favorited of current track to \(i.favorited)")
    }

    func toggleDislike() {
        guard var i = info, i.source == .music else { return }
        i.disliked.toggle()
        if i.disliked { i.favorited = false }
        info = i
        send("set disliked of current track to \(i.disliked)")
    }

    func revealInApp() {
        guard let i = info else { return }
        if i.source == .music { send("reveal current track") }
        send("activate", refreshAfter: false)
    }

    var shareLink: URL? {
        guard let uri = info?.shareURI else { return nil }
        let parts = uri.split(separator: ":")
        guard parts.count == 3, parts[0] == "spotify" else { return URL(string: uri) }
        return URL(string: "https://open.spotify.com/\(parts[1])/\(parts[2])")
    }

    private func send(_ command: String, refreshAfter: Bool = true) {
        guard let source = info?.source, source.isRunning else { return }
        let script = "tell application \"\(source.scriptName)\" to \(command)"
        queue.async {
            _ = Self.run(script)
            guard refreshAfter else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                MainActor.assumeIsolated { self.refresh() }
            }
        }
    }

    func open(_ source: MediaSource) {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: source.bundleID) else { return }
        guard source.isRunning else {
            NSWorkspace.shared.openApplication(at: url, configuration: .init())
            return
        }
        queue.async {
            if case .failure = Self.run("tell application id \"\(source.bundleID)\"\nreopen\nactivate\nend tell") {
                DispatchQueue.main.async {
                    NSWorkspace.shared.open(url)
                }
            }
        }
    }

    func openAutomationSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") {
            NSWorkspace.shared.open(url)
        }
    }

    private func loadArtwork(for info: NowPlayingInfo) {
        let key = artworkKey
        let finish: (NSImage?) -> Void = { img in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    guard self.artworkKey == key else { return }
                    if img == nil && self.artwork == nil { return }
                    self.artwork = img
                    self.artworkID += 1
                    self.accent = img.map { Color(nsColor: $0.accentColor) } ?? .white
                }
            }
        }
        switch info.source {
        case .spotify:
            guard let s = info.artworkURL, let url = URL(string: s), url.scheme?.lowercased() == "https" else { finish(nil); return }
            URLSession.shared.dataTask(with: url) { data, _, _ in
                finish(data.flatMap(NSImage.init(data:)))
            }.resume()
        case .music:
            queue.async {
                guard MediaSource.music.isRunning else { finish(nil); return }
                let r = Self.run("tell application \"Music\" to get raw data of artwork 1 of current track")
                if case .success(let d) = r { finish(NSImage(data: d.data)) } else { finish(nil) }
            }
        }
    }
}

extension NSImage {
    var accentColor: NSColor {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil, pixelsWide: 1, pixelsHigh: 1, bitsPerSample: 8,
            samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
            colorSpaceName: .deviceRGB, bytesPerRow: 4, bitsPerPixel: 32
        ) else { return .white }
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        NSGraphicsContext.current?.imageInterpolation = .high
        draw(in: NSRect(x: 0, y: 0, width: 1, height: 1))
        NSGraphicsContext.restoreGraphicsState()
        guard let c = rep.colorAt(x: 0, y: 0)?.usingColorSpace(.deviceRGB) else { return .white }
        return NSColor(
            hue: c.hueComponent,
            saturation: min(c.saturationComponent * 1.4, 0.9),
            brightness: max(c.brightnessComponent, 0.8),
            alpha: 1
        )
    }
}
