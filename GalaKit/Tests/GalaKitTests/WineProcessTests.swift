import Testing
import Foundation
@testable import GalaKit

@Test func wineserverURLResolvesSiblingExecutable() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bin = dir.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let wine = bin.appendingPathComponent("wine")
    let wineserver = bin.appendingPathComponent("wineserver")
    FileManager.default.createFile(atPath: wine.path, contents: nil)
    FileManager.default.createFile(atPath: wineserver.path, contents: nil)
    try FileManager.default.setAttributes(
        [.posixPermissions: 0o755],
        ofItemAtPath: wineserver.path
    )

    #expect(WineProcess.wineserverURL(for: wine)?.path == wineserver.path)
}

@Test func wineserverURLReturnsNilWhenMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let bin = dir.appendingPathComponent("bin")
    try FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let wine = bin.appendingPathComponent("wine")
    FileManager.default.createFile(atPath: wine.path, contents: nil)

    #expect(WineProcess.wineserverURL(for: wine) == nil)
}

@Test func logTailReadsOnlyRequestedSuffix() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let log = dir.appendingPathComponent("wine.log")
    let content = String(repeating: "noise\n", count: 200) + "meaningful-tail"
    try content.write(to: log, atomically: true, encoding: .utf8)

    let tail = WineProcess.logTail(from: log, limit: 21)

    #expect(tail == "noise\nmeaningful-tail")
}
