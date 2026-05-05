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

@Test func fontSubstitutesCoverLegacyWin32MenuFonts() {
    let sourceNames = Set(BottleManager.cjkFontSubstitutes.map(\.sourceName))

    #expect(sourceNames.contains("MS Sans Serif"))
    #expect(sourceNames.contains("Microsoft Sans Serif"))
    #expect(sourceNames.contains("System"))
    #expect(sourceNames.contains("Small Fonts"))
    #expect(sourceNames.contains("Arial"))
    #expect(sourceNames.contains("Arial Unicode MS"))
}

@Test func windowMetricFontsCoverLegacyWin32Dialogs() {
    let valueNames = Set(BottleManager.cjkWindowMetricFonts.map(\.valueName))

    #expect(valueNames.contains("CaptionFont"))
    #expect(valueNames.contains("IconFont"))
    #expect(valueNames.contains("MenuFont"))
    #expect(valueNames.contains("MessageFont"))
    #expect(valueNames.contains("SmCaptionFont"))
    #expect(valueNames.contains("StatusFont"))
}

@Test func windowMetricFontUsesCJKFaceAndCharset() throws {
    let metric = try #require(BottleManager.cjkWindowMetricFonts.first { $0.valueName == "MessageFont" })

    #expect(metric.data.count == 92)
    #expect(metric.data[23] == 0x86)

    let faceBytes = metric.data[28...]
    let faceCodeUnits = stride(from: 0, to: faceBytes.count, by: 2).compactMap { offset -> UInt16? in
        guard offset + 1 < faceBytes.count else { return nil }
        let value = UInt16(faceBytes[faceBytes.index(faceBytes.startIndex, offsetBy: offset)])
            | UInt16(faceBytes[faceBytes.index(faceBytes.startIndex, offsetBy: offset + 1)]) << 8
        return value == 0 ? nil : value
    }

    #expect(String(decoding: faceCodeUnits, as: UTF16.self) == "Source Han Sans SC")
}
