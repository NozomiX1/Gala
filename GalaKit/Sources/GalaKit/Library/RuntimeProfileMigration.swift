import Foundation

public enum RuntimeProfileMigration {
    public static let currentRulesVersion = 3

    public static func migrate(
        games: [Game],
        bottlesDirectory: URL,
        engineDetector: (URL) -> Engine? = EngineDetector.detect
    ) -> [Game] {
        games.map { game in
            guard !isCurrent(game) else { return game }

            var migrated = game
            // A profile picked by hand is the user's decision; the automatic rules leave it alone.
            if game.profileID != nil {
                markCurrent(&migrated)
                return migrated
            }
            if let targetEngine = specialRuntimeTarget(for: game, engineDetector: engineDetector) {
                let targetPrefix = BottleManager.prefixPath(for: targetEngine, bottlesDirectory: bottlesDirectory)

                // A configured game whose engine is unchanged stays in the prefix it has, even when new games of
                // that engine now go elsewhere (artemis-d3d11 began sharing common's prefix in rules v3).
                if migrated.engine != targetEngine || !migrated.isRuntimeConfigured {
                    let changedRuntime = migrated.engine != targetEngine ||
                        migrated.bottleConfig.prefixPath != targetPrefix
                    migrated.engine = targetEngine
                    migrated.bottleConfig.prefixPath = targetPrefix
                    if changedRuntime {
                        migrated.isRuntimeConfigured = false
                    }
                }
            } else if usedRemovedNativeLaunch(game) {
                migrated.bottleConfig.prefixPath = BottleManager.prefixPath(
                    for: game.engine,
                    bottlesDirectory: bottlesDirectory
                )
                migrated.isRuntimeConfigured = false
            } else if usesRetiredKiriKiriPrefix(game, bottlesDirectory: bottlesDirectory) {
                if game.isRuntimeConfigured {
                    // Keeps running exactly as before; only new KiriKiri games start in common.
                    migrated.profileID = RuntimeProfile.kirikiri.rawValue
                } else {
                    migrated.bottleConfig.prefixPath = BottleManager.prefixPath(for: game.engine, bottlesDirectory: bottlesDirectory)
                }
            }
            markCurrent(&migrated)
            return migrated
        }
    }

    /// Until rules v3 KiriKiri games had a profile and a prefix of their own.
    private static func usesRetiredKiriKiriPrefix(_ game: Game, bottlesDirectory: URL) -> Bool {
        guard (game.runtimeProfileMigrationVersion ?? 0) < 3, game.engine == .kirikiri else { return false }
        // Spelled out: asked today, the kirikiri profile answers with common's prefix.
        return game.bottleConfig.prefixPath == bottlesDirectory.appendingPathComponent("Profiles/kirikiri").path
    }

    public static func didChangeRuntimeProfile(from oldGames: [Game], to newGames: [Game]) -> Bool {
        guard oldGames.count == newGames.count else { return true }
        return zip(oldGames, newGames).contains { oldGame, newGame in
            oldGame.id != newGame.id ||
                oldGame.engine != newGame.engine ||
                oldGame.bottleConfig.prefixPath != newGame.bottleConfig.prefixPath ||
                oldGame.isRuntimeConfigured != newGame.isRuntimeConfigured ||
                oldGame.runtimeProfileMigrationVersion != newGame.runtimeProfileMigrationVersion ||
                oldGame.runtimeProfileMigrationExecutablePath != newGame.runtimeProfileMigrationExecutablePath
        }
    }

    private static func isCurrent(_ game: Game) -> Bool {
        game.runtimeProfileMigrationVersion == currentRulesVersion &&
            game.runtimeProfileMigrationExecutablePath == game.executablePath
    }

    private static func markCurrent(_ game: inout Game) {
        game.runtimeProfileMigrationVersion = currentRulesVersion
        game.runtimeProfileMigrationExecutablePath = game.executablePath
    }

    /// Before rules v2, Ren'Py, RPG Maker, and Unity were marked configured without a Wine bottle.
    private static func usedRemovedNativeLaunch(_ game: Game) -> Bool {
        guard (game.runtimeProfileMigrationVersion ?? 0) < 2 else { return false }
        return game.engine == .renpy || game.engine == .rpgMaker || game.engine == .unity
    }

    private static func specialRuntimeTarget(
        for game: Game,
        engineDetector: (URL) -> Engine?
    ) -> Engine? {
        var didDetect = false
        var detectedEngine: Engine?

        func detectEngine() -> Engine? {
            if !didDetect {
                let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
                detectedEngine = engineDetector(directory)
                didDetect = true
            }
            return detectedEngine
        }

        if shouldMoveToIkuraGDLFamilyProject(game, detectedEngine: detectEngine) {
            return .ikuraGDLFamilyProject
        }
        if shouldMoveToArtemisMFD3D11(game, detectedEngine: detectEngine) {
            return .artemisMFD3D11
        }
        if shouldMoveToArtemisD3D11(game, detectedEngine: detectEngine) {
            return .artemisD3D11
        }
        return nil
    }

    private static func shouldMoveToIkuraGDLFamilyProject(
        _ game: Game,
        detectedEngine: () -> Engine?
    ) -> Bool {
        if game.engine == .ikuraGDLFamilyProject { return true }
        guard game.engine == nil || game.engine == .unknown else { return false }

        return detectedEngine() == .ikuraGDLFamilyProject
    }

    private static func shouldMoveToArtemisD3D11(
        _ game: Game,
        detectedEngine: () -> Engine?
    ) -> Bool {
        if game.engine == .artemisD3D11 {
            return detectedEngine() != .artemisMFD3D11
        }
        guard game.engine == nil ||
            game.engine == .unknown ||
            game.engine == .kirikiri ||
            game.engine == .artemis else { return false }

        return detectedEngine() == .artemisD3D11
    }

    private static func shouldMoveToArtemisMFD3D11(
        _ game: Game,
        detectedEngine: () -> Engine?
    ) -> Bool {
        if game.engine == .artemisMFD3D11 { return true }
        guard game.engine == nil ||
            game.engine == .unknown ||
            game.engine == .kirikiri ||
            game.engine == .artemis ||
            game.engine == .artemisD3D11 else { return false }

        return detectedEngine() == .artemisMFD3D11
    }
}
