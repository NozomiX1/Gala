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

@Test func runtimeEnvironmentStatusReportsMissingDependencies() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    let status = manager.runtimeEnvironmentStatus()

    #expect(!status.isWineInstalled)
    #expect(!status.isFontInstalled)
    #expect(!status.isHelperToolInstalled)
    #expect(!status.hasWineConfiguration)
    #expect(!status.isReady)
}

@Test func runtimeEnvironmentStatusReportsInstalledDependencies() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    let wineBinary = manager.wineDirectory
        .appendingPathComponent("wine-staging-11.6/bin/wine")
    let bottleMarker = manager.bottlesDirectory
        .appendingPathComponent("Profiles/legacy-video/system.reg")

    for file in [wineBinary, manager.fontFileURL, manager.cabextractURL, manager.winetricksURL, bottleMarker] {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    }
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.cabextractURL.path)
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.winetricksURL.path)

    let status = manager.runtimeEnvironmentStatus()

    #expect(status.isWineInstalled)
    #expect(status.isFontInstalled)
    #expect(status.isHelperToolInstalled)
    #expect(status.hasWineConfiguration)
    #expect(status.isReady)
}

@Test func managedDependencyDownloadsUseGalaOwnedReleaseAssets() {
    let dependencies: [(name: String, url: URL)] = [
        ("wine", WineManager.wineDownloadURL),
        ("font", WineManager.fontDownloadURL),
        ("cabextract", WineManager.cabextractDownloadURL),
        ("winetricks", WineManager.winetricksDownloadURL),
    ]

    for dependency in dependencies {
        #expect(dependency.url.host == "github.com", "\(dependency.name) should download from GitHub releases")
        #expect(
            dependency.url.path.hasPrefix("/NozomiX1/Gala/releases/download/deps-v1/"),
            "\(dependency.name) should use the Gala deps-v1 release"
        )
        #expect(!dependency.url.absoluteString.contains("raw.githubusercontent.com"))
        #expect(!dependency.url.absoluteString.contains("Winetricks/winetricks"))
        #expect(!dependency.url.absoluteString.contains("Gcenx/macOS_Wine_builds"))
        #expect(!dependency.url.absoluteString.contains("adobe-fonts/source-han-sans"))
    }
}

@Test func runtimeEnvironmentStatusRequiresAllHelperTools() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    try FileManager.default.createDirectory(
        at: manager.cabextractURL.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: manager.cabextractURL.path, contents: Data("x".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.cabextractURL.path)

    #expect(!manager.runtimeEnvironmentStatus().isHelperToolInstalled)

    FileManager.default.createFile(atPath: manager.winetricksURL.path, contents: Data("x".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.winetricksURL.path)

    #expect(manager.runtimeEnvironmentStatus().isHelperToolInstalled)
}

@Test func runtimeEnvironmentStatusRequiresExecutableHelperTools() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    FileManager.default.createFile(atPath: manager.cabextractURL.path, contents: Data("x".utf8))
    FileManager.default.createFile(atPath: manager.winetricksURL.path, contents: Data("#!/bin/sh\n".utf8))

    #expect(!manager.runtimeEnvironmentStatus().isHelperToolInstalled)
}

@Test func bottleManagerPrefersManagedWinetricks() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    FileManager.default.createFile(atPath: manager.winetricksURL.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: manager.winetricksURL.path)

    #expect(BottleManager.findWinetricks(wineManager: manager) == manager.winetricksURL.path)
}

@Test func bottleManagerWineCommandEnvironmentSuppressesVerboseLogs() {
    let env = BottleManager.wineCommandEnvironment(prefix: "/tmp/prefix", locale: "zh_CN.UTF-8")

    #expect(env["WINEPREFIX"] == "/tmp/prefix")
    #expect(env["LANG"] == "zh_CN.UTF-8")
    #expect(env["LC_ALL"] == "zh_CN.UTF-8")
    #expect(env["WINEDEBUG"] == "-all")
    #expect(env["MVK_CONFIG_LOG_LEVEL"] == "0")
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

@Test func wineManagerResetWineConfigurationKeepsDependenciesAndLibraryData() throws {
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
    let cabextractFile = manager.toolsDirectory.appendingPathComponent("cabextract")
    let winetricksFile = manager.toolsDirectory.appendingPathComponent("winetricks")

    for file in [libraryFile, coverFile, wineFile, bottleFile, fontFile, cabextractFile, winetricksFile] {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    }

    try manager.resetWineConfiguration()

    #expect(FileManager.default.fileExists(atPath: libraryFile.path))
    #expect(FileManager.default.fileExists(atPath: coverFile.path))
    #expect(FileManager.default.fileExists(atPath: wineFile.path))
    #expect(FileManager.default.fileExists(atPath: fontFile.path))
    #expect(FileManager.default.fileExists(atPath: cabextractFile.path))
    #expect(FileManager.default.fileExists(atPath: winetricksFile.path))
    #expect(FileManager.default.fileExists(atPath: manager.bottlesDirectory.path))
    #expect(!FileManager.default.fileExists(atPath: bottleFile.path))
}

@Test func wineManagerResetAllApplicationDataRemovesLibraryCacheAndRuntimeData() throws {
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
    let cabextractFile = manager.toolsDirectory.appendingPathComponent("cabextract")
    let winetricksFile = manager.toolsDirectory.appendingPathComponent("winetricks")

    for file in [libraryFile, coverFile, wineFile, bottleFile, fontFile, cabextractFile, winetricksFile] {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    }

    try manager.resetAllApplicationData()

    #expect(!FileManager.default.fileExists(atPath: libraryFile.path))
    #expect(!FileManager.default.fileExists(atPath: coverFile.path))
    #expect(!FileManager.default.fileExists(atPath: wineFile.path))
    #expect(!FileManager.default.fileExists(atPath: bottleFile.path))
    #expect(!FileManager.default.fileExists(atPath: fontFile.path))
    #expect(!FileManager.default.fileExists(atPath: cabextractFile.path))
    #expect(!FileManager.default.fileExists(atPath: winetricksFile.path))
    #expect(FileManager.default.fileExists(atPath: manager.wineDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.bottlesDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.fontsDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.toolsDirectory.path))
}
