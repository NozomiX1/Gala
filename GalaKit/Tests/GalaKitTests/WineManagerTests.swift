import Testing
import Foundation
@testable import GalaKit

@Test func wineManagerDirectoryStructure() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    #expect(manager.wineDirectory.lastPathComponent == "Wine")
    #expect(manager.bottlesDirectory.lastPathComponent == "Bottles")
}

@Test func wineManagerManagedPathNotInstalled() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    // Managed Wine (active symlink) should not exist in a fresh temp dir.
    // isWineInstalled may still be true if Homebrew Wine is present globally.
    let managedBinary = manager.wineDirectory
        .appendingPathComponent("active")
        .appendingPathComponent("bin")
        .appendingPathComponent("wine64")
    #expect(!FileManager.default.fileExists(atPath: managedBinary.path))
}

@Test func bottleManagerCreatesDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bottlesDir = tempDir.appendingPathComponent("Bottles")
    let bottleManager = BottleManager(bottlesDirectory: bottlesDir)
    let gameId = UUID()
    let prefixPath = bottleManager.prefixPath(for: gameId)

    #expect(prefixPath.contains(gameId.uuidString))
}

@Test func bottleManagerUsesSharedPrefixForEquivalentRuntimeProfiles() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bottlesDir = tempDir.appendingPathComponent("Bottles")
    let bottleManager = BottleManager(bottlesDirectory: bottlesDir)

    let bgi = bottleManager.prefixPath(for: Engine.bgi)
    let artemis = bottleManager.prefixPath(for: Engine.artemis)
    let nscripter = bottleManager.prefixPath(for: Engine.nscripter)
    let yuris = bottleManager.prefixPath(for: Engine.yuris)
    let realLive = bottleManager.prefixPath(for: Engine.realLive)
    let kirikiri = bottleManager.prefixPath(for: Engine.kirikiri)

    #expect(bgi == bottlesDir.appendingPathComponent("Profiles/legacy-video").path)
    #expect(artemis == bgi)
    #expect(nscripter == bgi)
    #expect(yuris == bgi)
    #expect(realLive == bgi)
    #expect(kirikiri == bottlesDir.appendingPathComponent("Profiles/kirikiri").path)
    #expect(kirikiri != bgi)
}

@Test func bottleManagerUsesBaseSharedPrefixWithoutEngine() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bottlesDir = tempDir.appendingPathComponent("Bottles")
    let bottleManager = BottleManager(bottlesDirectory: bottlesDir)

    #expect(bottleManager.prefixPath(for: nil) == bottlesDir.appendingPathComponent("Profiles/base").path)
}

@Test func wineManagerResetRuntimeEnvironmentKeepsLibraryData() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    let libraryFile = tempDir.appendingPathComponent("library.json")
    let coverFile = tempDir.appendingPathComponent("Cache/covers/v1.jpg")
    let wineFile = manager.wineDirectory.appendingPathComponent("active/bin/wine")
    let bottleFile = manager.bottlesDirectory.appendingPathComponent("Profiles/kirikiri/system.reg")
    let fontFile = manager.fontsDirectory.appendingPathComponent("SourceHanSansSC-Regular.otf")
    let toolFile = manager.toolsDirectory.appendingPathComponent("cabextract")

    for file in [coverFile, wineFile, bottleFile, fontFile, toolFile] {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    }
    FileManager.default.createFile(atPath: libraryFile.path, contents: Data("[]".utf8))

    try manager.resetRuntimeEnvironment()

    #expect(FileManager.default.fileExists(atPath: libraryFile.path))
    #expect(FileManager.default.fileExists(atPath: coverFile.path))
    #expect(FileManager.default.fileExists(atPath: manager.wineDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.bottlesDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.fontsDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.toolsDirectory.path))
    #expect(!FileManager.default.fileExists(atPath: wineFile.path))
    #expect(!FileManager.default.fileExists(atPath: bottleFile.path))
    #expect(!FileManager.default.fileExists(atPath: fontFile.path))
    #expect(!FileManager.default.fileExists(atPath: toolFile.path))
}
