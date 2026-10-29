import Foundation
import Testing
@testable import DynIsl

struct NowPlayingParseTests {
    private func line(_ fields: [String]) -> String { fields.joined(separator: NowPlayingService.sep) }

    @Test func parsesSpotify() throws {
        let s = line(["playing", "Song", "Artist", "Album", "215000", "12,5", "spotify:track:1", "https://i.scdn.co/a",
                      "40", "true", "true", "false", "false", "false", "spotify:track:abc"])
        let i = try #require(NowPlayingService.parse(s, source: .spotify))
        #expect(i.title == "Song")
        #expect(i.duration == 215)
        #expect(i.position == 12.5)
        #expect(i.isPlaying)
        #expect(i.volume == 40)
        #expect(i.shuffle)
        #expect(i.repeatMode == .all)
        #expect(!i.muted)
        #expect(i.artworkURL == "https://i.scdn.co/a")
        #expect(i.shareURI == "spotify:track:abc")
    }

    @Test func parsesMusic() throws {
        let s = line(["paused", "Şarkı", "Sanatçı", "Albüm", "180.5", "3", "ABC123", "",
                      "0", "false", "one", "true", "false", "true", ""])
        let i = try #require(NowPlayingService.parse(s, source: .music))
        #expect(i.duration == 180.5)
        #expect(!i.isPlaying)
        #expect(i.repeatMode == .one)
        #expect(i.favorited)
        #expect(i.muted)
        #expect(i.artworkURL == nil)
        #expect(i.shareURI == nil)
    }

    @Test func spotifyZeroVolumeIsMuted() throws {
        let s = line(["playing", "a", "b", "c", "1000", "0", "id", "", "0", "false", "false", "false", "false", "false", ""])
        #expect(try #require(NowPlayingService.parse(s, source: .spotify)).muted)
    }

    @Test func rejectsStoppedAndShortOutput() {
        #expect(NowPlayingService.parse("stopped", source: .music) == nil)
        #expect(NowPlayingService.parse(line(["playing", "a", "b"]), source: .spotify) == nil)
    }

    @Test func durationHasFloor() throws {
        let s = line(["playing", "a", "b", "c", "0", "0", "id", "", "50", "false", "off", "false", "false", "false", ""])
        #expect(try #require(NowPlayingService.parse(s, source: .music)).duration == 1)
    }
}

struct FormattingTests {
    @Test func formatsSeconds() {
        #expect(formatSeconds(0) == "0:00")
        #expect(formatSeconds(65) == "1:05")
        #expect(formatSeconds(-3) == "0:00")
        #expect(formatSeconds(3600) == "60:00")
    }

    @Test func formatsBytes() {
        #expect(SystemMonitor.formatBytes(512) == "512 B")
        #expect(SystemMonitor.formatBytes(1500) == "1.5 KB")
        #expect(SystemMonitor.formatBytes(25_000_000, perSecond: true) == "25 MB/s")
    }

    @Test func normalizesBluetoothAddress() {
        #expect(BluetoothMonitor.normalize("aa-bb-cc:dd:ee:ff") == "AABBCCDDEEFF")
    }

    @Test func readsDateFromScreenshotName() throws {
        let d = try #require(DesktopCleaner.dateInName("Ekran Resmi 2026-10-16 14.02.11.png"))
        let c = Calendar(identifier: .gregorian).dateComponents(in: .current, from: d)
        #expect(c.year == 2026 && c.month == 10 && c.day == 16)
        #expect(DesktopCleaner.dateInName("foto.png") == nil)
    }
}

struct HardeningTests {
    @Test func parseRejectsExtraFields() {
        let f = ["playing", "A|~|B", "Artist", "Album", "1000", "1", "id", "https://i.scdn.co/a", "40", "false", "false", "false", "false", "false", "spotify:track:x"]
        #expect(NowPlayingService.parse(f.joined(separator: NowPlayingService.sep), source: .spotify) == nil)
    }

    @Test func shareURLOnlyForSpotifyURIs() {
        #expect(NowPlayingService.shareURL(for: "spotify:track:abc") == URL(string: "https://open.spotify.com/track/abc"))
        #expect(NowPlayingService.shareURL(for: "https://evil.example/x") == nil)
        #expect(NowPlayingService.shareURL(for: "spotify:track:a/b") == nil)
    }

    @Test func artworkOnlyFromSpotifyCDN() {
        #expect(NowPlayingService.isAllowedArtwork(URL(string: "https://i.scdn.co/image/ab")!))
        #expect(NowPlayingService.isAllowedArtwork(URL(string: "https://image-cdn-ak.spotifycdn.com/image/ab")!))
        #expect(!NowPlayingService.isAllowedArtwork(URL(string: "https://evil.example/a.png")!))
        #expect(!NowPlayingService.isAllowedArtwork(URL(string: "http://i.scdn.co/image/ab")!))
        #expect(!NowPlayingService.isAllowedArtwork(URL(string: "https://i.scdn.co.evil.example/a")!))
    }

    @Test func releasePageMustBeThisRepo() {
        #expect(UpdateChecker.isReleasePage(URL(string: "https://github.com/caganerdal/DynIsl/releases/tag/v0.8.0")!))
        #expect(!UpdateChecker.isReleasePage(URL(string: "https://github.com/someone/else/releases/tag/v1")!))
        #expect(!UpdateChecker.isReleasePage(URL(string: "http://github.com/caganerdal/DynIsl/releases/tag/v1")!))
    }
}
