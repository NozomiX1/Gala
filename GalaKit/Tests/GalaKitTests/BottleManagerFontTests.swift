import Testing
import Foundation
@testable import GalaKit

@Test func installBundledFontCopiesFontFile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let prefix = dir.appendingPathComponent("prefix")
    let fontsDir = prefix.appendingPathComponent("drive_c/windows/Fonts")
    try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    // Create a fake font source file
    let fakeFont = dir.appendingPathComponent("TestFont.otf")
    try Data("fake font data".utf8).write(to: fakeFont)

    try BottleManager.installBundledFont(prefix: prefix.path, fontSource: fakeFont)

    let installedFont = fontsDir.appendingPathComponent("TestFont.otf")
    #expect(FileManager.default.fileExists(atPath: installedFont.path))
}

@Test func installBundledFontIsIdempotent() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let prefix = dir.appendingPathComponent("prefix")
    let fontsDir = prefix.appendingPathComponent("drive_c/windows/Fonts")
    try FileManager.default.createDirectory(at: fontsDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let fakeFont = dir.appendingPathComponent("TestFont.otf")
    try Data("fake font data".utf8).write(to: fakeFont)

    // Install twice — should not throw
    try BottleManager.installBundledFont(prefix: prefix.path, fontSource: fakeFont)
    try BottleManager.installBundledFont(prefix: prefix.path, fontSource: fakeFont)

    let installedFont = fontsDir.appendingPathComponent("TestFont.otf")
    #expect(FileManager.default.fileExists(atPath: installedFont.path))
}

@Test func installBundledFontSkipsIfSourceMissing() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let prefix = dir.appendingPathComponent("prefix")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let missingFont = dir.appendingPathComponent("NoSuchFont.otf")

    // Should not throw — just skips
    try BottleManager.installBundledFont(prefix: prefix.path, fontSource: missingFont)
}
