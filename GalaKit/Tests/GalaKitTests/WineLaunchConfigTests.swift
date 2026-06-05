import Testing
import Foundation
@testable import GalaKit

@Test func asciiPathUsesDirectExeAndSetsWorkingDir() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let exePath = dir.appendingPathComponent("game.exe").path
    let prefixPath = dir.appendingPathComponent("prefix").path
    let game = Game(
        title: "Test",
        executablePath: exePath,
        bottleConfig: BottleConfig(prefixPath: prefixPath)
    )

    let config = try WineLaunchConfig.resolve(game: game)

    #expect(config.arguments == ["game.exe"])
    #expect(config.workingDirectory?.path == dir.path)
    #expect(config.driveMapping == nil)
}

@Test func ikuraGDLFamilyProjectUsesMappedGameDriveEvenForAsciiPath() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Kizunar")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let prefixPath = dir.appendingPathComponent("prefix").path
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: prefixPath), withIntermediateDirectories: true
    )

    let exePath = gameDir.appendingPathComponent("kzn_sc.exe").path
    let game = Game(
        title: "Family Project",
        executablePath: exePath,
        engine: .ikuraGDLFamilyProject,
        bottleConfig: BottleConfig(prefixPath: prefixPath)
    )

    let config = try WineLaunchConfig.resolve(game: game)

    #expect(config.arguments == ["g:\\kzn_sc.exe"])
    #expect(config.workingDirectory?.path == gameDir.path)
    #expect(config.driveMapping?.driveLetter == "g:")
    #expect(config.driveMapping?.targetPath == gameDir.path)
}

@Test func nonAsciiPathUsesDriveMappingAndSetsWorkingDir() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("日本語ゲーム")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let prefixPath = dir.appendingPathComponent("prefix").path
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: prefixPath), withIntermediateDirectories: true
    )

    let exePath = gameDir.appendingPathComponent("BGI.exe").path
    let game = Game(
        title: "テスト",
        executablePath: exePath,
        bottleConfig: BottleConfig(prefixPath: prefixPath)
    )

    let config = try WineLaunchConfig.resolve(game: game)

    // Should use G: drive for the exe argument
    #expect(config.arguments == ["g:\\BGI.exe"])
    // Non-ASCII path: workingDirectory must be set so child processes find siblings
    #expect(config.workingDirectory?.path == gameDir.path)
    // Drive mapping should be created
    #expect(config.driveMapping != nil)
    #expect(config.driveMapping?.driveLetter == "g:")
    #expect(config.driveMapping?.targetPath == gameDir.path)

    // Verify symlink was actually created in dosdevices
    let gDrive = URL(fileURLWithPath: prefixPath)
        .appendingPathComponent("dosdevices")
        .appendingPathComponent("g:")
    let dest = try FileManager.default.destinationOfSymbolicLink(atPath: gDrive.path)
    #expect(dest == gameDir.path)
}

@Test func nonAsciiPathRecreatesDriveSymlink() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("中文路径")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let prefixPath = dir.appendingPathComponent("prefix").path
    try FileManager.default.createDirectory(
        at: URL(fileURLWithPath: prefixPath), withIntermediateDirectories: true
    )

    // Pre-create a stale g: symlink pointing somewhere else
    let dosdevices = URL(fileURLWithPath: prefixPath).appendingPathComponent("dosdevices")
    try FileManager.default.createDirectory(at: dosdevices, withIntermediateDirectories: true)
    let gDrive = dosdevices.appendingPathComponent("g:")
    try FileManager.default.createSymbolicLink(atPath: gDrive.path, withDestinationPath: "/tmp")

    let exePath = gameDir.appendingPathComponent("game.exe").path
    let game = Game(
        title: "测试",
        executablePath: exePath,
        bottleConfig: BottleConfig(prefixPath: prefixPath)
    )

    let config = try WineLaunchConfig.resolve(game: game)

    // Should overwrite the stale symlink
    let dest = try FileManager.default.destinationOfSymbolicLink(atPath: gDrive.path)
    #expect(dest == gameDir.path)
    #expect(config.workingDirectory?.path == gameDir.path)
}

@Test func environmentDoesNotSetDYLDForMissingPaths() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let game = Game(
        title: "Test",
        executablePath: dir.appendingPathComponent("game.exe").path,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("prefix").path)
    )
    // Wine binary in a dir without lib/external — simulates Wine Staging
    let fakeBin = dir.appendingPathComponent("bin/wine")
    try FileManager.default.createDirectory(
        at: fakeBin.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: fakeBin.path, contents: nil)

    let env = WineLaunchConfig.buildEnvironment(game: game, wineBinary: fakeBin)

    // DYLD_FALLBACK_LIBRARY_PATH should NOT be set if lib dirs don't exist
    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"] == nil)
    #expect(env["WINEPREFIX"] == dir.appendingPathComponent("prefix").path)
    #expect(env["LANG"] == "zh_CN.UTF-8")
    #expect(env["LC_ALL"] == "zh_CN.UTF-8")
}

@Test func environmentInheritsProcessEnv() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let game = Game(
        title: "Test",
        executablePath: dir.appendingPathComponent("game.exe").path,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("prefix").path)
    )
    let fakeBin = dir.appendingPathComponent("bin/wine")
    try FileManager.default.createDirectory(
        at: fakeBin.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: fakeBin.path, contents: nil)

    let env = WineLaunchConfig.buildEnvironment(game: game, wineBinary: fakeBin)

    // Should inherit process environment
    #expect(env["HOME"] != nil)
    // Wine-specific vars should be set
    #expect(env["WINEPREFIX"] != nil)
}

@Test func environmentSuppressesVerboseWineAndMoltenVKLogsByDefault() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let game = Game(
        title: "Test",
        executablePath: dir.appendingPathComponent("game.exe").path,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("prefix").path)
    )
    let fakeBin = dir.appendingPathComponent("bin/wine")
    try FileManager.default.createDirectory(
        at: fakeBin.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: fakeBin.path, contents: nil)

    let env = WineLaunchConfig.buildEnvironment(game: game, wineBinary: fakeBin)

    #expect(env["WINEDEBUG"] == "-all")
    #expect(env["MVK_CONFIG_LOG_LEVEL"] == "0")
}

@Test func gameEnvironmentCanOverrideWineLogDefaults() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let game = Game(
        title: "Test",
        executablePath: dir.appendingPathComponent("game.exe").path,
        bottleConfig: BottleConfig(
            prefixPath: dir.appendingPathComponent("prefix").path,
            environment: [
                "WINEDEBUG": "+seh",
                "MVK_CONFIG_LOG_LEVEL": "3",
            ]
        )
    )
    let fakeBin = dir.appendingPathComponent("bin/wine")
    try FileManager.default.createDirectory(
        at: fakeBin.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: fakeBin.path, contents: nil)

    let env = WineLaunchConfig.buildEnvironment(game: game, wineBinary: fakeBin)

    #expect(env["WINEDEBUG"] == "+seh")
    #expect(env["MVK_CONFIG_LOG_LEVEL"] == "3")
}

@Test func mediaFoundationRuntimeEnvironmentAddsGStreamerPaths() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let runtimeRoot = dir.appendingPathComponent("gala-mf-runtime-1.0")
    let runtimeLib = runtimeRoot.appendingPathComponent("lib")
    let pluginDir = runtimeRoot.appendingPathComponent("lib/gstreamer-1.0")
    let scanner = runtimeRoot.appendingPathComponent("libexec/gstreamer-1.0/gst-plugin-scanner")
    let registry = dir.appendingPathComponent("Cache/media-foundation/gst-registry.bin")
    for url in [runtimeLib, pluginDir, scanner.deletingLastPathComponent()] {
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }
    FileManager.default.createFile(atPath: scanner.path, contents: Data("#!/bin/sh\n".utf8))
    try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scanner.path)

    let game = Game(
        title: "Amakano 3",
        executablePath: dir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisMFD3D11,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("prefix").path)
    )
    let fakeBin = dir.appendingPathComponent("Wine/bin/wine")
    try FileManager.default.createDirectory(
        at: fakeBin.deletingLastPathComponent(), withIntermediateDirectories: true
    )
    FileManager.default.createFile(atPath: fakeBin.path, contents: nil)

    let env = WineLaunchConfig.buildEnvironment(
        game: game,
        wineBinary: fakeBin,
        mediaFoundationRuntime: MediaFoundationRuntime(rootURL: runtimeRoot, gStreamerRegistryURL: registry)
    )

    #expect(env["DYLD_FALLBACK_LIBRARY_PATH"]?.split(separator: ":").first == Substring(runtimeLib.path))
    #expect(env["GST_PLUGIN_PATH_1_0"] == pluginDir.path)
    #expect(env["GST_PLUGIN_SYSTEM_PATH_1_0"] == "")
    #expect(env["GST_PLUGIN_SCANNER_1_0"] == scanner.path)
    #expect(env["GST_REGISTRY"] == registry.path)
    #expect(env["GST_REGISTRY_FORK"] == "no")
}

@Test func launchArgumentsArePrepended() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let exePath = dir.appendingPathComponent("game.exe").path
    let game = Game(
        title: "Test",
        executablePath: exePath,
        bottleConfig: BottleConfig(
            prefixPath: dir.appendingPathComponent("prefix").path,
            launchArguments: ["--some-flag"]
        )
    )

    let config = try WineLaunchConfig.resolve(game: game)

    #expect(config.arguments == ["--some-flag", "game.exe"])
}
