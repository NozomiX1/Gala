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
    #expect(migrated[0].bottleConfig.prefixPath == dir.appendingPathComponent("Bottles/Profiles/common").path)
    #expect(!migrated[0].isRuntimeConfigured)
    #expect(migrated[0].profileID == nil)
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

@Test func runtimeProfileMigrationSendsFormerNativeLaunchGamesToCommonBottle() throws {
    let bottles = URL(fileURLWithPath: "/tmp/Gala/Bottles")
    let game = Game(
        title: "Unity Game",
        executablePath: "/games/unity/game.exe",
        engine: .unity,
        isRuntimeConfigured: true,
        runtimeProfileMigrationVersion: 1,
        runtimeProfileMigrationExecutablePath: "/games/unity/game.exe",
        bottleConfig: BottleConfig(prefixPath: bottles.appendingPathComponent("Profiles/unity").path)
    )

    let migrated = RuntimeProfileMigration.migrate(games: [game], bottlesDirectory: bottles) { _ in nil }

    #expect(migrated[0].engine == .unity)
    #expect(migrated[0].bottleConfig.prefixPath == bottles.appendingPathComponent("Profiles/common").path)
    #expect(!migrated[0].isRuntimeConfigured)
    #expect(migrated[0].runtimeProfileMigrationVersion == RuntimeProfileMigration.currentRulesVersion)
}

@Test func runtimeProfileMigrationKeepsWineConfiguredRenPyGameAfterExecutableChange() throws {
    let bottles = URL(fileURLWithPath: "/tmp/Gala/Bottles")
    let game = Game(
        title: "RenPy Game",
        executablePath: "/games/renpy/new.exe",
        engine: .renpy,
        isRuntimeConfigured: true,
        runtimeProfileMigrationVersion: RuntimeProfileMigration.currentRulesVersion,
        runtimeProfileMigrationExecutablePath: "/games/renpy/old.exe",
        bottleConfig: BottleConfig(prefixPath: bottles.appendingPathComponent("Profiles/common").path)
    )

    let migrated = RuntimeProfileMigration.migrate(games: [game], bottlesDirectory: bottles) { _ in nil }

    #expect(migrated[0].isRuntimeConfigured)
    #expect(migrated[0].runtimeProfileMigrationExecutablePath == "/games/renpy/new.exe")
}

@Test func aConfiguredKiriKiriGameIsPinnedToItsOldProfileAndAnUnconfiguredOneMovesToCommon() {
    let bottles = URL(fileURLWithPath: "/tmp/gala-test/Bottles")
    let oldPrefix = bottles.appendingPathComponent("Profiles/kirikiri").path
    let configured = Game(title: "千恋", executablePath: "/g/a/a.exe", engine: .kirikiri, isRuntimeConfigured: true,
                          runtimeProfileMigrationVersion: 2, runtimeProfileMigrationExecutablePath: "/g/a/a.exe",
                          bottleConfig: BottleConfig(prefixPath: oldPrefix))
    let unconfigured = Game(title: "新", executablePath: "/g/b/b.exe", engine: .kirikiri, isRuntimeConfigured: false,
                            runtimeProfileMigrationVersion: 2, runtimeProfileMigrationExecutablePath: "/g/b/b.exe",
                            bottleConfig: BottleConfig(prefixPath: oldPrefix))

    let migrated = RuntimeProfileMigration.migrate(games: [configured, unconfigured], bottlesDirectory: bottles) { _ in .kirikiri }

    #expect(migrated[0].profileID == "kirikiri")
    #expect(migrated[0].bottleConfig.prefixPath == oldPrefix)
    #expect(migrated[0].isRuntimeConfigured)
    #expect(ProfileStore.bundled.recipe(for: migrated[0])?.id == "kirikiri")

    #expect(migrated[1].profileID == nil)
    #expect(migrated[1].bottleConfig.prefixPath == bottles.appendingPathComponent("Profiles/common").path)
    #expect(ProfileStore.bundled.recipe(for: migrated[1])?.id == "common")

    // Running the rules again changes nothing.
    let again = RuntimeProfileMigration.migrate(games: migrated, bottlesDirectory: bottles) { _ in .kirikiri }
    #expect(!RuntimeProfileMigration.didChangeRuntimeProfile(from: migrated, to: again))
    #expect(again.map(\.profileID) == migrated.map(\.profileID))
}

@Test func aConfiguredArtemisD3D11GameStaysInThePrefixItHas() {
    let bottles = URL(fileURLWithPath: "/tmp/gala-test/Bottles")
    let oldPrefix = bottles.appendingPathComponent("Profiles/artemis-d3d11").path
    let configured = Game(title: "ハミダシ", executablePath: "/g/h/h.exe", engine: .artemisD3D11, isRuntimeConfigured: true,
                          runtimeProfileMigrationVersion: 2, runtimeProfileMigrationExecutablePath: "/g/h/h.exe",
                          bottleConfig: BottleConfig(prefixPath: oldPrefix))
    var unconfigured = configured
    unconfigured.isRuntimeConfigured = false

    let migrated = RuntimeProfileMigration.migrate(games: [configured, unconfigured], bottlesDirectory: bottles) { _ in .artemisD3D11 }

    #expect(migrated[0].bottleConfig.prefixPath == oldPrefix)
    #expect(migrated[0].isRuntimeConfigured)
    #expect(migrated[0].profileID == nil)
    #expect(migrated[1].bottleConfig.prefixPath == bottles.appendingPathComponent("Profiles/common").path)
}
