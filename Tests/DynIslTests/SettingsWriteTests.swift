import Foundation
import Testing
@testable import DynIsl

struct SettingsWriteTests {
    private func dir() throws -> URL {
        let u = FileManager.default.temporaryDirectory.appendingPathComponent("sw-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: u, withIntermediateDirectories: true)
        return u
    }

    private func mode(_ url: URL) -> Int16? {
        (try? FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.int16Value
    }

    @Test func keepsPrivatePermissions() throws {
        let f = try dir().appendingPathComponent("settings.json")
        FileManager.default.createFile(atPath: f.path, contents: Data("{}".utf8), attributes: [.posixPermissions: 0o600])
        try AIUsageStore.writePreservingMode(Data(#"{"a":1}"#.utf8), to: f, expected: Data("{}".utf8))
        #expect(mode(f) == 0o600)
        #expect(try Data(contentsOf: f) == Data(#"{"a":1}"#.utf8))
    }

    @Test func newFileIsPrivate() throws {
        let f = try dir().appendingPathComponent("settings.json")
        try AIUsageStore.writePreservingMode(Data("{}".utf8), to: f, expected: nil)
        #expect(mode(f) == 0o600)
    }

    @Test func refusesWhenChangedMeanwhile() throws {
        let f = try dir().appendingPathComponent("settings.json")
        try Data(#"{"changed":true}"#.utf8).write(to: f)
        #expect(throws: (any Error).self) { try AIUsageStore.writePreservingMode(Data("{}".utf8), to: f, expected: Data("{}".utf8)) }
        #expect(try Data(contentsOf: f) == Data(#"{"changed":true}"#.utf8))
    }

    @Test func writesThroughSymlink() throws {
        let d = try dir()
        let real = d.appendingPathComponent("real.json")
        let link = d.appendingPathComponent("settings.json")
        try Data("{}".utf8).write(to: real)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)
        try AIUsageStore.writePreservingMode(Data(#"{"a":1}"#.utf8), to: link.resolvingSymlinksInPath(), expected: Data("{}".utf8))
        #expect((try? FileManager.default.destinationOfSymbolicLink(atPath: link.path)) != nil)
        #expect(try Data(contentsOf: real) == Data(#"{"a":1}"#.utf8))
    }
}
