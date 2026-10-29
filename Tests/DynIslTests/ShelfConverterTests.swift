import AppKit
import Testing
@testable import DynIsl

struct ShelfConverterTests {
    private func dir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("conv-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func png(_ url: URL) throws {
        let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: 4, pixelsHigh: 4, bitsPerSample: 8, samplesPerPixel: 4,
                                   hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
        try rep.representation(using: .png, properties: [:])!.write(to: url)
    }

    @Test func danglingSymlinkAtOutputNameIsNotFollowed() throws {
        let d = try dir()
        let target = d.appendingPathComponent("planted.jpg")
        try png(d.appendingPathComponent("a.png"))
        try FileManager.default.createSymbolicLink(at: d.appendingPathComponent("a.jpg"), withDestinationURL: target)
        let r = ShelfConverter.run(.toJPEG, on: [d.appendingPathComponent("a.png")])
        #expect(!FileManager.default.fileExists(atPath: target.path))
        #expect(r.outputs == [d.appendingPathComponent("a 2.jpg")])
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: d.appendingPathComponent("a.jpg").path)) != nil)
    }

    @Test func writesPlainNameAndLeavesNoTempFiles() throws {
        let d = try dir()
        try png(d.appendingPathComponent("b.png"))
        let r = ShelfConverter.run(.toJPEG, on: [d.appendingPathComponent("b.png")])
        #expect(r.outputs == [d.appendingPathComponent("b.jpg")])
        #expect(try FileManager.default.contentsOfDirectory(atPath: d.path).sorted() == ["b.jpg", "b.png"])
    }
}

struct TrustedExecutableTests {
    private func exe() throws -> URL {
        let d = FileManager.default.temporaryDirectory.appendingPathComponent("exe-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: d, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o755])
        let f = d.appendingPathComponent("claude")
        FileManager.default.createFile(atPath: f.path, contents: Data("#!/bin/sh\n".utf8), attributes: [.posixPermissions: 0o755])
        return f
    }

    @Test func ownedExecutableIsTrusted() throws {
        #expect(AIUsageStore.isTrustedExecutable(try exe().path))
    }

    @Test func worldWritableFileIsRejected() throws {
        let f = try exe()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.path)
        #expect(!AIUsageStore.isTrustedExecutable(f.path))
    }

    @Test func groupWritableDirectoryIsRejected() throws {
        let f = try exe()
        try FileManager.default.setAttributes([.posixPermissions: 0o775], ofItemAtPath: f.deletingLastPathComponent().path)
        #expect(!AIUsageStore.isTrustedExecutable(f.path))
    }

    @Test func symlinkToWritableTargetIsRejected() throws {
        let f = try exe()
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: f.path)
        let link = f.deletingLastPathComponent().appendingPathComponent("link")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: f)
        #expect(!AIUsageStore.isTrustedExecutable(link.path))
    }

    @Test func missingFileIsRejected() {
        #expect(!AIUsageStore.isTrustedExecutable("/nonexistent/claude"))
    }
}
