import Testing
import Foundation
import CryptoKit
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

    #expect(manager.mediaFoundationRuntimeArchiveURL.path == tempDir.appendingPathComponent("Cache/media-foundation/gala-mf-runtime-1.1/gala-mf-runtime-1.1-macos.tar.gz").path)
    #expect(manager.mediaFoundationRuntimeDirectory.path == tempDir.appendingPathComponent("Tools/MediaFoundation/gala-mf-runtime-1.1").path)
    #expect(manager.mediaFoundationFFmpegURL.path == tempDir.appendingPathComponent("Tools/MediaFoundation/gala-mf-runtime-1.1/bin/ffmpeg").path)
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
    _ = BottleManager(bottlesDirectory: bottlesDir)

    #expect(FileManager.default.fileExists(atPath: bottlesDir.path))
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
    #expect(bottleManager.prefixPath(for: Engine.renpy) == bgi)
    #expect(bottleManager.prefixPath(for: Engine.rpgMaker) == bgi)
    #expect(bottleManager.prefixPath(for: Engine.unity) == bgi)
    #expect(ikuraGDLFamilyProject == bottlesDir.appendingPathComponent("Profiles/do-kizunar").path)
    #expect(ikuraGDLFamilyProject != bgi)
    // Same prefix contents as common: only the Wine build that starts the game differs.
    #expect(artemisD3D11 == bgi)
    #expect(bottleManager.prefixPath(forProfile: "artemis-d3d11") == bgi)
    #expect(artemisMFD3D11 == bottlesDir.appendingPathComponent("Profiles/artemis-mf-d3d11").path)
    #expect(artemisMFD3D11 != artemisD3D11)
    #expect(kirikiri == bgi)
    // It only changes a DLL choice, which is passed at launch, so it needs no prefix of its own.
    // Games pinned to it before keep the path stored on them.
    #expect(bottleManager.prefixPath(forProfile: "kirikiri") == bgi)
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

@Test func downloadCandidatesPreferMirrorThenGitHubForGalaAssets() {
    let pairs: [(URL, String)] = [
        (WineManager.wineDownloadURL, "https://gala.feng7.cn/deps-v1/wine-staging-11.6-osx64.tar.xz"),
        (WineManager.fontDownloadURL, "https://gala.feng7.cn/deps-v1/SourceHanSansSC-Regular.otf"),
        (WineManager.cabextractDownloadURL, "https://gala.feng7.cn/deps-v1/cabextract"),
        (WineManager.winetricksDownloadURL, "https://gala.feng7.cn/deps-v1/winetricks"),
        (WineManager.dxmtDownloadURL, "https://gala.feng7.cn/deps-v2/dxmt-v0.80-builtin.tar.gz"),
        (WineManager.mediaFoundationRuntimeDownloadURL, "https://gala.feng7.cn/deps-v3/gala-mf-runtime-1.1-macos.tar.gz"),
    ]

    for (canonical, expectedMirror) in pairs {
        let candidates = WineManager.downloadCandidates(for: canonical)
        #expect(candidates.count == 2)
        #expect(candidates[0].absoluteString == expectedMirror)
        #expect(candidates[1] == canonical)
    }

    let external = URL(string: "https://example.com/custom.tar.xz")!
    #expect(WineManager.downloadCandidates(for: external) == [external])
}

@Test func downloadWithFallbackUsesMirrorWhenHealthy() async throws {
    let token = UUID().uuidString
    let payload = Data("healthy-mirror-payload".utf8)
    let expectedSHA = sha256Hex(payload)
    let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
    let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

    let tracker = RequestTracker()
    StubDownloadProtocol.register(prefix: "/\(token)/") { url in
        tracker.record(url)
        return .http(200, payload)
    }
    defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let destination = tempDir.appendingPathComponent("asset.bin")

    try await WineManager.downloadWithFallback(
        candidates: [mirrorURL, fallbackURL],
        to: destination,
        expectedSHA256: expectedSHA,
        configuration: StubDownloadProtocol.sessionConfiguration(),
        resumeDelayNanoseconds: 0
    ) { _ in }

    #expect(try Data(contentsOf: destination) == payload)
    #expect(tracker.urls == [mirrorURL])
}

@Test func downloadWithFallbackRecoversFromMirrorHTTP404() async throws {
    let token = UUID().uuidString
    let payload = Data("github-fallback-payload".utf8)
    let expectedSHA = sha256Hex(payload)
    let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
    let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

    let tracker = RequestTracker()
    StubDownloadProtocol.register(prefix: "/\(token)/") { url in
        tracker.record(url)
        if url == mirrorURL {
            return .http(404, Data("Not Found".utf8))
        }
        return .http(200, payload)
    }
    defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let destination = tempDir.appendingPathComponent("asset.bin")

    try await WineManager.downloadWithFallback(
        candidates: [mirrorURL, fallbackURL],
        to: destination,
        expectedSHA256: expectedSHA,
        configuration: StubDownloadProtocol.sessionConfiguration(),
        resumeDelayNanoseconds: 0
    ) { _ in }

    #expect(try Data(contentsOf: destination) == payload)
    #expect(tracker.urls == [mirrorURL, fallbackURL])
}

@Test func downloadWithFallbackRecoversFromMirrorChecksumMismatch() async throws {
    let token = UUID().uuidString
    let goodPayload = Data("verified-good-bytes".utf8)
    let expectedSHA = sha256Hex(goodPayload)
    let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
    let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

    let tracker = RequestTracker()
    StubDownloadProtocol.register(prefix: "/\(token)/") { url in
        tracker.record(url)
        if url == mirrorURL {
            return .http(200, Data("corrupted-mirror-bytes".utf8))
        }
        return .http(200, goodPayload)
    }
    defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let destination = tempDir.appendingPathComponent("asset.bin")

    try await WineManager.downloadWithFallback(
        candidates: [mirrorURL, fallbackURL],
        to: destination,
        expectedSHA256: expectedSHA,
        configuration: StubDownloadProtocol.sessionConfiguration(),
        resumeDelayNanoseconds: 0
    ) { _ in }

    #expect(try Data(contentsOf: destination) == goodPayload)
    #expect(tracker.urls == [mirrorURL, fallbackURL])
}

@Test func downloadWithFallbackThrowsAndLeavesNoFileWhenAllCandidatesFail() async throws {
    let token = UUID().uuidString
    let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
    let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

    StubDownloadProtocol.register(prefix: "/\(token)/") { _ in
        .http(503, Data("Service Unavailable".utf8))
    }
    defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let destination = tempDir.appendingPathComponent("asset.bin")

    await #expect(throws: Error.self) {
        try await WineManager.downloadWithFallback(
            candidates: [mirrorURL, fallbackURL],
            to: destination,
            expectedSHA256: nil,
            configuration: StubDownloadProtocol.sessionConfiguration(),
            resumeDelayNanoseconds: 0
        ) { _ in }
    }

    #expect(!FileManager.default.fileExists(atPath: destination.path))
}

@Test func streamingSHA256MatchesCryptoKitAcrossMultipleChunks() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    // 2.5 MB spans multiple 1 MB read chunks.
    let data = Data((0..<(2_500_000)).map { UInt8($0 & 0xFF) })
    let file = tempDir.appendingPathComponent("blob.bin")
    try data.write(to: file)

    #expect(try WineManager.sha256Hex(of: file) == sha256Hex(data))
}

@Test func patchWineGStreamerAudioSampleLimitPatchesUniquePatternsIdempotently() throws {
    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let wineRoot = tempDir.appendingPathComponent("wine")
    let wineBin = wineRoot.appendingPathComponent("bin/wine")
    let dll32 = wineRoot.appendingPathComponent("lib/wine/i386-windows/winegstreamer.dll")
    let dll64 = wineRoot.appendingPathComponent("lib/wine/x86_64-windows/winegstreamer.dll")
    for url in [wineBin, dll32, dll64] {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    }
    FileManager.default.createFile(atPath: wineBin.path, contents: Data())

    let original32: [UInt8] = [0x3d, 0x00, 0x40, 0x00, 0x00, 0xbf, 0x00, 0x40, 0x00, 0x00, 0x0f, 0x42, 0xf8, 0x83, 0xbb, 0x00, 0xff, 0xff, 0xff, 0x01, 0x0f, 0x45, 0xf8]
    let patched32: [UInt8] = [0x3d, 0x00, 0x00, 0x01, 0x00, 0xbf, 0x00, 0x00, 0x01, 0x00, 0x0f, 0x42, 0xf8, 0x83, 0xbb, 0x00, 0xff, 0xff, 0xff, 0x01, 0x0f, 0x45, 0xf8]
    let original64: [UInt8] = [0x3d, 0x00, 0x40, 0x00, 0x00, 0x41, 0xbc, 0x00, 0x40, 0x00, 0x00, 0x44, 0x0f, 0x42, 0xe0, 0x83, 0xbd, 0xf8, 0xfe, 0xff, 0xff, 0x01, 0x44, 0x0f, 0x45, 0xe0]
    let patched64: [UInt8] = [0x3d, 0x00, 0x00, 0x01, 0x00, 0x41, 0xbc, 0x00, 0x00, 0x01, 0x00, 0x44, 0x0f, 0x42, 0xe0, 0x83, 0xbd, 0xf8, 0xfe, 0xff, 0xff, 0x01, 0x44, 0x0f, 0x45, 0xe0]

    let prefix = Data([0x90, 0x90, 0x90, 0x90])
    let suffix = Data([0xc3, 0xcc])
    try (prefix + Data(original32) + suffix).write(to: dll32)
    try (prefix + Data(original64) + suffix).write(to: dll64)

    #expect(WineManager.patchWineGStreamerAudioSampleLimitIfNeeded(forWineBinary: wineBin))
    #expect(try Data(contentsOf: dll32) == prefix + Data(patched32) + suffix)
    #expect(try Data(contentsOf: dll64) == prefix + Data(patched64) + suffix)

    // Already patched: second call is a no-op.
    #expect(!WineManager.patchWineGStreamerAudioSampleLimitIfNeeded(forWineBinary: wineBin))

    // Duplicate pattern must be refused without altering the file.
    let ambiguous = prefix + Data(original32) + prefix + Data(original32) + suffix
    try ambiguous.write(to: dll32)
    try Data("other-wine-version".utf8).write(to: dll64)
    #expect(!WineManager.patchWineGStreamerAudioSampleLimitIfNeeded(forWineBinary: wineBin))
    #expect(try Data(contentsOf: dll32) == ambiguous)
    #expect(try Data(contentsOf: dll64) == Data("other-wine-version".utf8))
}

@Test func downloadWithFallbackRetriesTransientTLSResetsBeforeFallingBack() async throws {
    let token = UUID().uuidString
    let payload = Data("recovered-on-third-attempt".utf8)
    let expectedSHA = sha256Hex(payload)
    let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
    let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

    let tracker = RequestTracker()
    StubDownloadProtocol.register(prefix: "/\(token)/") { url in
        let attempt = tracker.recordAndCount(url)
        if url == mirrorURL && attempt <= 2 {
            return .error(URLError(.secureConnectionFailed))
        }
        return .http(200, payload)
    }
    defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

    let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    defer { try? FileManager.default.removeItem(at: tempDir) }
    let destination = tempDir.appendingPathComponent("asset.bin")

    try await WineManager.downloadWithFallback(
        candidates: [mirrorURL, fallbackURL],
        to: destination,
        expectedSHA256: expectedSHA,
        configuration: StubDownloadProtocol.sessionConfiguration(),
        resumeDelayNanoseconds: 0,
        transientRetryDelaysNanoseconds: [0, 0]
    ) { _ in }

    #expect(try Data(contentsOf: destination) == payload)
    #expect(tracker.urls == [mirrorURL, mirrorURL, mirrorURL])
}

@Test func downloadWithFallbackDoesNotRetryTimedOutOrMissingHostOnMirror() async throws {
    for errorCode in [URLError.Code.timedOut, URLError.Code.cannotFindHost] {
        let token = UUID().uuidString
        let payload = Data("github-direct-fallback".utf8)
        let mirrorURL = URL(string: "https://mirror.test/\(token)/asset.bin")!
        let fallbackURL = URL(string: "https://github.test/\(token)/asset.bin")!

        let tracker = RequestTracker()
        StubDownloadProtocol.register(prefix: "/\(token)/") { url in
            tracker.record(url)
            if url == mirrorURL {
                return .error(URLError(errorCode))
            }
            return .http(200, payload)
        }
        defer { StubDownloadProtocol.unregister(prefix: "/\(token)/") }

        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        let destination = tempDir.appendingPathComponent("asset.bin")

        try await WineManager.downloadWithFallback(
            candidates: [mirrorURL, fallbackURL],
            to: destination,
            expectedSHA256: nil,
            configuration: StubDownloadProtocol.sessionConfiguration(),
            resumeDelayNanoseconds: 0,
            transientRetryDelaysNanoseconds: [0, 0]
        ) { _ in }

        #expect(try Data(contentsOf: destination) == payload)
        #expect(tracker.urls == [mirrorURL, fallbackURL])
    }
}

private func sha256Hex(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}

private final class RequestTracker: @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [URL] = []

    var urls: [URL] {
        lock.lock()
        defer { lock.unlock() }
        return recorded
    }

    func record(_ url: URL) {
        lock.lock()
        recorded.append(url)
        lock.unlock()
    }

    func recordAndCount(_ url: URL) -> Int {
        lock.lock()
        defer { lock.unlock() }
        recorded.append(url)
        return recorded.filter { $0 == url }.count
    }
}

private final class StubDownloadProtocol: URLProtocol {
    enum StubResponse {
        case http(Int, Data)
        case error(Error)
    }
    typealias Handler = @Sendable (URL) -> StubResponse

    private static let lock = NSLock()
    private static var handlers: [String: Handler] = [:]

    static func register(prefix: String, handler: @escaping Handler) {
        lock.lock()
        handlers[prefix] = handler
        lock.unlock()
    }

    static func unregister(prefix: String) {
        lock.lock()
        handlers.removeValue(forKey: prefix)
        lock.unlock()
    }

    static func sessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubDownloadProtocol.self]
        return config
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let url = request.url else {
            client?.urlProtocol(self, didFailWithError: URLError(.badURL))
            return
        }
        Self.lock.lock()
        let handler = Self.handlers.first { url.path.hasPrefix($0.key) }?.value
        Self.lock.unlock()

        guard let handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.fileDoesNotExist))
            return
        }

        switch handler(url) {
        case .error(let error):
            client?.urlProtocol(self, didFailWithError: error)
        case .http(let statusCode, let data):
            let response = HTTPURLResponse(
                url: url,
                statusCode: statusCode,
                httpVersion: "HTTP/1.1",
                headerFields: ["Content-Length": "\(data.count)"]
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    override func stopLoading() {}
}
