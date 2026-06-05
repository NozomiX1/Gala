import Foundation

public enum RuntimeProfileMigration {
    public static let currentRulesVersion = 1

    public static func migrate(
        games: [Game],
        bottlesDirectory: URL,
        engineDetector: (URL) -> Engine? = EngineDetector.detect
    ) -> [Game] {
        games.map { game in
            guard !isCurrent(game) else { return game }

            var migrated = game
            if let targetEngine = specialRuntimeTarget(for: game, engineDetector: engineDetector) {
                let targetPrefix = sharedPrefixPath(for: targetEngine, bottlesDirectory: bottlesDirectory)

                let changedRuntime = migrated.engine != targetEngine ||
                    migrated.bottleConfig.prefixPath != targetPrefix
                migrated.engine = targetEngine
                migrated.bottleConfig.prefixPath = targetPrefix
                if changedRuntime {
                    migrated.isRuntimeConfigured = false
                }
            }
            markCurrent(&migrated)
            return migrated
        }
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

    private static func sharedPrefixPath(for engine: Engine, bottlesDirectory: URL) -> String {
        bottlesDirectory
            .appendingPathComponent("Profiles")
            .appendingPathComponent(engine.runtimeProfile.rawValue)
            .path
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
