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
        .appendingPathComponent("Profiles/common/system.reg")

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
    let dependencies: [(name: String, url: URL, release: String)] = [
        ("wine", WineManager.wineDownloadURL, "deps-v1"),
        ("font", WineManager.fontDownloadURL, "deps-v1"),
        ("cabextract", WineManager.cabextractDownloadURL, "deps-v1"),
        ("winetricks", WineManager.winetricksDownloadURL, "deps-v1"),
        ("dxmt", WineManager.dxmtDownloadURL, "deps-v2"),
        ("media foundation runtime", WineManager.mediaFoundationRuntimeDownloadURL, "deps-v3"),
    ]

    for dependency in dependencies {
        #expect(dependency.url.host == "github.com", "\(dependency.name) should download from GitHub releases")
        #expect(
            dependency.url.path.hasPrefix("/NozomiX1/Gala/releases/download/\(dependency.release)/"),
            "\(dependency.name) should use the Gala \(dependency.release) release"
        )
        #expect(!dependency.url.absoluteString.contains("raw.githubusercontent.com"))
        #expect(!dependency.url.absoluteString.contains("Winetricks/winetricks"))
        #expect(!dependency.url.absoluteString.contains("Gcenx/macOS_Wine_builds"))
        #expect(!dependency.url.absoluteString.contains("adobe-fonts/source-han-sans"))
    }
}

@Test func wineManagerDXMTPathsAreAppManaged() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)

    #expect(manager.dxmtArchiveURL.path == tempDir.appendingPathComponent("Cache/dxmt/v0.80/dxmt-v0.80-builtin.tar.gz").path)
    #expect(manager.dxmtWineDirectory.path == tempDir.appendingPathComponent("Wine/wine-staging-11.6-dxmt-v0.80").path)
}

@Test func wineManagerMediaFoundationRuntimePathsAreAppManaged() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)

    #expect(manager.mediaFoundationRuntimeArchiveURL.path == tempDir.appendingPathComponent("Cache/media-foundation/gala-mf-runtime-1.0/gala-mf-runtime-1.0-macos.tar.gz").path)
    #expect(manager.mediaFoundationRuntimeDirectory.path == tempDir.appendingPathComponent("Tools/MediaFoundation/gala-mf-runtime-1.0").path)
    #expect(manager.mediaFoundationFFmpegURL.path == tempDir.appendingPathComponent("Tools/MediaFoundation/gala-mf-runtime-1.0/bin/ffmpeg").path)
}

@Test func wineManagerSelectsDXMTWineForArtemisD3D11ProfilesOnly() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    let baseWine = manager.wineDirectory
        .appendingPathComponent("active/Contents/Resources/wine/bin/wine")
    let dxmtWine = manager.dxmtWineDirectory
        .appendingPathComponent("Contents/Resources/wine/bin/wine")

    for file in [baseWine, dxmtWine] {
        try FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        FileManager.default.createFile(atPath: file.path, contents: Data("x".utf8))
    }

    let commonGame = Game(
        title: "KiriKiri",
        executablePath: tempDir.appendingPathComponent("game.exe").path,
        engine: .kirikiri
    )
    let artemisGame = Game(
        title: "Amakano 3",
        executablePath: tempDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisD3D11
    )
    let artemisMFGame = Game(
        title: "Amakano 3",
        executablePath: tempDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisMFD3D11
    )

    #expect(manager.wineBinaryURL(for: commonGame)?.path == baseWine.path)
    #expect(manager.wineBinaryURL(for: artemisGame)?.path == dxmtWine.path)
    #expect(manager.wineBinaryURL(for: artemisMFGame)?.path == dxmtWine.path)
}

@Test func wineManagerDoesNotUseDXMTVariantAsDefaultWine() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)
    let dxmtWine = manager.dxmtWineDirectory
        .appendingPathComponent("Contents/Resources/wine/bin/wine")
    try FileManager.default.createDirectory(
        at: dxmtWine.deletingLastPathComponent(),
        withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: dxmtWine.path, contents: Data("x".utf8))

    let commonGame = Game(
        title: "KiriKiri",
        executablePath: tempDir.appendingPathComponent("game.exe").path,
        engine: .kirikiri
    )
    let artemisGame = Game(
        title: "Amakano 3",
        executablePath: tempDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisD3D11
    )
    let artemisMFGame = Game(
        title: "Amakano 3",
        executablePath: tempDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisMFD3D11
    )

    #expect(manager.wineBinaryURL == nil)
    #expect(manager.wineBinaryURL(for: commonGame) == nil)
    #expect(manager.wineBinaryURL(for: artemisGame)?.path == dxmtWine.path)
    #expect(manager.wineBinaryURL(for: artemisMFGame)?.path == dxmtWine.path)
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

@Test func wineManagerProvidesAppManagedWinetricksCacheDirectory() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let manager = WineManager(baseURL: tempDir)

    #expect(manager.winetricksCacheDirectory.path == tempDir.appendingPathComponent("Cache/winetricks").path)
}

@Test func bottleManagerWinetricksEnvironmentUsesAppManagedCache() {
    let env = BottleManager.winetricksEnvironment(
        prefix: "/tmp/prefix",
        locale: "zh_CN.UTF-8",
        wineBinary: "/tmp/Wine/bin/wine",
        toolsDirectory: "/tmp/Gala/Tools",
        cacheDirectory: "/tmp/Gala/Cache/winetricks"
    )

    #expect(env["WINEPREFIX"] == "/tmp/prefix")
    #expect(env["WINE"] == "/tmp/Wine/bin/wine")
    #expect(env["PATH"]?.hasPrefix("/tmp/Gala/Tools:") == true)
    #expect(env["W_CACHE"] == "/tmp/Gala/Cache/winetricks")
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
    let unknown = bottleManager.prefixPath(for: Engine.unknown)
    let majiro = bottleManager.prefixPath(for: Engine.majiro)
    let ikuraGDLFamilyProject = bottleManager.prefixPath(for: Engine.ikuraGDLFamilyProject)
    let artemisD3D11 = bottleManager.prefixPath(for: Engine.artemisD3D11)
    let artemisMFD3D11 = bottleManager.prefixPath(for: Engine.artemisMFD3D11)
    let kirikiri = bottleManager.prefixPath(for: Engine.kirikiri)

    #expect(bgi == bottlesDir.appendingPathComponent("Profiles/common").path)
    #expect(artemis == bgi)
    #expect(nscripter == bgi)
    #expect(yuris == bgi)
    #expect(realLive == bgi)
    #expect(unknown == bgi)
    #expect(majiro == bgi)
    #expect(ikuraGDLFamilyProject == bottlesDir.appendingPathComponent("Profiles/do-kizunar").path)
    #expect(ikuraGDLFamilyProject != bgi)
    #expect(artemisD3D11 == bottlesDir.appendingPathComponent("Profiles/artemis-d3d11").path)
    #expect(artemisD3D11 != bgi)
    #expect(artemisMFD3D11 == bottlesDir.appendingPathComponent("Profiles/artemis-mf-d3d11").path)
    #expect(artemisMFD3D11 != artemisD3D11)
    #expect(kirikiri == bottlesDir.appendingPathComponent("Profiles/kirikiri").path)
    #expect(kirikiri != bgi)
}

@Test func bottleManagerUsesCommonSharedPrefixWithoutEngine() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let bottlesDir = tempDir.appendingPathComponent("Bottles")
    let bottleManager = BottleManager(bottlesDirectory: bottlesDir)

    #expect(bottleManager.prefixPath(for: nil) == bottlesDir.appendingPathComponent("Profiles/common").path)
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
    let winetricksCacheFile = manager.winetricksCacheDirectory.appendingPathComponent("win7sp1/windows6.1-KB976932-X64.exe")

    for file in [libraryFile, coverFile, wineFile, bottleFile, fontFile, cabextractFile, winetricksFile, winetricksCacheFile] {
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
    #expect(FileManager.default.fileExists(atPath: winetricksCacheFile.path))
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
    let winetricksCacheFile = manager.winetricksCacheDirectory.appendingPathComponent("win7sp1/windows6.1-KB976932-X64.exe")

    for file in [libraryFile, coverFile, wineFile, bottleFile, fontFile, cabextractFile, winetricksFile, winetricksCacheFile] {
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
    #expect(!FileManager.default.fileExists(atPath: winetricksCacheFile.path))
    #expect(FileManager.default.fileExists(atPath: manager.wineDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.bottlesDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.fontsDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.toolsDirectory.path))
    #expect(FileManager.default.fileExists(atPath: manager.cacheDirectory.path))
}
