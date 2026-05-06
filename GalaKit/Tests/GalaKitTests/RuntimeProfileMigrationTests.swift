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
