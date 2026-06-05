import Testing
import Foundation
@testable import GalaKit

@Test func runtimeProfileMigrationMovesExistingIkuraGDLFamilyProjectGameOutOfCommon() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Kizunar")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("kzn_sc.exe").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("KIZUNAR.SUF").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("FAM_OP.MPG").path, contents: nil)

    let commonPrefix = dir.appendingPathComponent("Bottles/Profiles/common").path
    let game = Game(
        title: "Family Project",
        executablePath: gameDir.appendingPathComponent("kzn_sc.exe").path,
        engine: nil,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: commonPrefix)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    )

    #expect(migrated[0].engine == .ikuraGDLFamilyProject)
    #expect(migrated[0].bottleConfig.prefixPath == dir.appendingPathComponent("Bottles/Profiles/do-kizunar").path)
    #expect(!migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationMovesMisdetectedArtemisD3D11GameOutOfKiriKiri() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Amakano3")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("Amakano3_chs.xp3").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("Amakano3.pfs").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("iarsys64.dll").path, contents: nil)
    try Data("D3D11CreateDevice\0D3DCompile\0Artemis.vs2022.pdb".utf8)
        .write(to: gameDir.appendingPathComponent("Amakano3_chs.exe"))

    let game = Game(
        title: "Amakano 3",
        executablePath: gameDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .kirikiri,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/kirikiri").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    )

    #expect(migrated[0].engine == .artemisD3D11)
    #expect(migrated[0].bottleConfig.prefixPath == dir.appendingPathComponent("Bottles/Profiles/artemis-d3d11").path)
    #expect(!migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationMovesMediaFoundationArtemisD3D11GameToSeparateProfile() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Amakano3")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("Amakano3_chs.xp3").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("Amakano3.pfs").path, contents: nil)
    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("iarsys64.dll").path, contents: nil)
    try Data("localized launcher".utf8)
        .write(to: gameDir.appendingPathComponent("Amakano3_chs.exe"))
    try Data("D3D11CreateDevice\0D3DCompile\0MFCreateMediaSession\0MFPlat.DLL\0Artemis.vs2022.pdb".utf8)
        .write(to: gameDir.appendingPathComponent("Amakano3.exe"))

    let game = Game(
        title: "Amakano 3",
        executablePath: gameDir.appendingPathComponent("Amakano3_chs.exe").path,
        engine: .artemisD3D11,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/artemis-d3d11").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    )

    #expect(migrated[0].engine == .artemisMFD3D11)
    #expect(migrated[0].bottleConfig.prefixPath == dir.appendingPathComponent("Bottles/Profiles/artemis-mf-d3d11").path)
    #expect(!migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationDetectsEligibleGameOnlyOnce() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Artemis")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var detectionCount = 0
    let game = Game(
        title: "Artemis",
        executablePath: gameDir.appendingPathComponent("game.exe").path,
        engine: .kirikiri,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/kirikiri").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    ) { _ in
        detectionCount += 1
        return .artemisD3D11
    }

    #expect(detectionCount == 1)
    #expect(migrated[0].engine == .artemisD3D11)
    #expect(!migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationSkipsDetectionWhenMigrationMarkerIsCurrent() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("KiriKiri")
    let executablePath = gameDir.appendingPathComponent("game.exe").path
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var detectionCount = 0
    let game = Game(
        title: "KiriKiri",
        executablePath: executablePath,
        engine: .kirikiri,
        isRuntimeConfigured: true,
        runtimeProfileMigrationVersion: RuntimeProfileMigration.currentRulesVersion,
        runtimeProfileMigrationExecutablePath: executablePath,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/kirikiri").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    ) { _ in
        detectionCount += 1
        return .artemisD3D11
    }

    #expect(detectionCount == 0)
    #expect(migrated[0].engine == .kirikiri)
    #expect(migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationRerunsDetectionWhenExecutablePathChanges() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Artemis")
    let executablePath = gameDir.appendingPathComponent("game.exe").path
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    var detectionCount = 0
    let game = Game(
        title: "Artemis",
        executablePath: executablePath,
        engine: .kirikiri,
        isRuntimeConfigured: true,
        runtimeProfileMigrationVersion: RuntimeProfileMigration.currentRulesVersion,
        runtimeProfileMigrationExecutablePath: gameDir.appendingPathComponent("old.exe").path,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/kirikiri").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    ) { _ in
        detectionCount += 1
        return .artemisD3D11
    }

    #expect(detectionCount == 1)
    #expect(migrated[0].engine == .artemisD3D11)
    #expect(migrated[0].runtimeProfileMigrationExecutablePath == executablePath)
    #expect(!migrated[0].isRuntimeConfigured)
}

@Test func runtimeProfileMigrationPersistsCurrentMarkerWhenRuntimeDoesNotChange() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Unknown")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    let game = Game(
        title: "Unknown",
        executablePath: gameDir.appendingPathComponent("game.exe").path,
        engine: .unknown,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/common").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    ) { _ in nil }

    #expect(RuntimeProfileMigration.didChangeRuntimeProfile(from: [game], to: migrated))
    #expect(migrated[0].engine == .unknown)
    #expect(migrated[0].bottleConfig.prefixPath == game.bottleConfig.prefixPath)
    #expect(migrated[0].runtimeProfileMigrationVersion == RuntimeProfileMigration.currentRulesVersion)
    #expect(migrated[0].runtimeProfileMigrationExecutablePath == game.executablePath)
}

@Test func runtimeProfileMigrationLeavesOtherUnknownGamesAlone() throws {
    let dir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
    let gameDir = dir.appendingPathComponent("Unknown")
    try FileManager.default.createDirectory(at: gameDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: dir) }

    FileManager.default.createFile(atPath: gameDir.appendingPathComponent("game.exe").path, contents: nil)

    let game = Game(
        title: "Unknown",
        executablePath: gameDir.appendingPathComponent("game.exe").path,
        engine: nil,
        isRuntimeConfigured: true,
        bottleConfig: BottleConfig(prefixPath: dir.appendingPathComponent("Bottles/Profiles/common").path)
    )

    let migrated = RuntimeProfileMigration.migrate(
        games: [game],
        bottlesDirectory: dir.appendingPathComponent("Bottles")
    )

    #expect(migrated[0].engine == nil)
    #expect(migrated[0].bottleConfig.prefixPath == game.bottleConfig.prefixPath)
    #expect(migrated[0].isRuntimeConfigured)
}
