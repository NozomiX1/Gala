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

@Test func japaneseFontNamesMisreadUnderTheChineseCodePageAreMapped() {
    // The exact names 穢翼のユースティア asks for, as traced with WINEDEBUG=+font.
    let mincho = "\u{4FF5}\u{4FFD} \u{67E7}\u{632C}", gothic = "\u{4FF5}\u{4FFD} \u{50D1}\u{50D4}\u{50E2}\u{50CB}"
    #expect(BottleManager.misreadAsGBK("ＭＳ 明朝") == mincho)
    #expect(BottleManager.misreadAsGBK("ＭＳ ゴシック") == gothic)

    func targets(_ installed: Set<String>) -> [String: String] {
        Dictionary(uniqueKeysWithValues: BottleManager.misreadJapaneseFontSubstitutes(installedFamilies: installed)
            .map { ($0.sourceName, $0.targetName) })
    }
    let best = targets(["SimSong", "STHeiti", "STSong", "Arial Unicode MS"])
    #expect(best[mincho] == "SimSong")
    #expect(best[gothic] == "STHeiti")

    // Without the on-demand fonts the two options must still be two different typefaces.
    let bare = targets(["STSong", "Arial Unicode MS"])
    #expect(bare[mincho] == "STSong")
    #expect(bare[gothic] == "Arial Unicode MS")

    // And they are part of what every new prefix gets.
    #expect(Set(BottleManager.cjkFontSubstitutes.map(\.sourceName)).isSuperset(of: [mincho, gothic]))
}

@Test func aMissingFontIsNotMistakenForItsFallback() {
    #expect(BottleManager.isFontInstalled(postScriptName: "Helvetica"))
    #expect(!BottleManager.isFontInstalled(postScriptName: "Gala-No-Such-Font"))
}

@Test func askingForFontsMacOSDoesNotOfferReturnsInsteadOfWaiting() async {
    let started = Date()
    await BottleManager.downloadOnDemandFonts(["Gala-No-Such-Font"], timeout: 20)
    #expect(Date().timeIntervalSince(started) < 15)
}

@Test func aPrefixIsCheckedForSubstitutesTheWayWineWritesThem() throws {
    let prefix = FileManager.default.temporaryDirectory.appendingPathComponent("gala-font-\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: prefix, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: prefix) }
    let wanted = BottleManager.misreadJapaneseFontSubstitutes(installedFamilies: ["SimSong", "STHeiti"])

    // A prefix configured by 1.x: other substitutes, none for the misread names.
    try #"""
    [Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes] 1775509734
    "SimHei"="Source Han Sans SC"
    """#.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
    #expect(!BottleManager.prefix(prefix, has: wanted))

    // Copied from a real system.reg after `wine reg add`.
    try #"""
    [Software\\Microsoft\\Windows NT\\CurrentVersion\\FontSubstitutes] 1775509734
    "\x4ff5\x4ffd \x4ff9\x50d1\x50d4\x50e2\x50cb"="STHeiti"
    "\x4ff5\x4ffd \x4ff9\x67e7\x632c"="SimSong"
    "\x4ff5\x4ffd \x50d1\x50d4\x50e2\x50cb"="STHeiti"
    "\x4ff5\x4ffd \x67e7\x632c"="SimSong"
    """#.write(to: prefix.appendingPathComponent("system.reg"), atomically: true, encoding: .utf8)
    #expect(BottleManager.prefix(prefix, has: wanted))

    // Pointing at the fallbacks is out of date once the better fonts are installed.
    #expect(!BottleManager.prefix(prefix, has: BottleManager.misreadJapaneseFontSubstitutes(installedFamilies: [])))
}
