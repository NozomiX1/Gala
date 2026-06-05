import Foundation

public enum RuntimeProfileMigration {
    public static func migrate(games: [Game], bottlesDirectory: URL) -> [Game] {
        games.map { game in
            guard let targetEngine = specialRuntimeTarget(for: game) else { return game }

            var migrated = game
            let targetPrefix = sharedPrefixPath(for: targetEngine, bottlesDirectory: bottlesDirectory)

            let changedRuntime = migrated.engine != targetEngine ||
                migrated.bottleConfig.prefixPath != targetPrefix
            migrated.engine = targetEngine
            migrated.bottleConfig.prefixPath = targetPrefix
            if changedRuntime {
                migrated.isRuntimeConfigured = false
            }
            return migrated
        }
    }

    public static func didChangeRuntimeProfile(from oldGames: [Game], to newGames: [Game]) -> Bool {
        guard oldGames.count == newGames.count else { return true }
        return zip(oldGames, newGames).contains { oldGame, newGame in
            oldGame.id != newGame.id ||
                oldGame.engine != newGame.engine ||
                oldGame.bottleConfig.prefixPath != newGame.bottleConfig.prefixPath ||
                oldGame.isRuntimeConfigured != newGame.isRuntimeConfigured
        }
    }

    private static func specialRuntimeTarget(for game: Game) -> Engine? {
        if shouldMoveToIkuraGDLFamilyProject(game) {
            return .ikuraGDLFamilyProject
        }
        if shouldMoveToArtemisMFD3D11(game) {
            return .artemisMFD3D11
        }
        if shouldMoveToArtemisD3D11(game) {
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

    private static func shouldMoveToIkuraGDLFamilyProject(_ game: Game) -> Bool {
        if game.engine == .ikuraGDLFamilyProject { return true }
        guard game.engine == nil || game.engine == .unknown else { return false }

        let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        return EngineDetector.detect(in: directory) == .ikuraGDLFamilyProject
    }

    private static func shouldMoveToArtemisD3D11(_ game: Game) -> Bool {
        if game.engine == .artemisD3D11 {
            let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
            return EngineDetector.detect(in: directory) != .artemisMFD3D11
        }
        guard game.engine == nil ||
            game.engine == .unknown ||
            game.engine == .kirikiri ||
            game.engine == .artemis else { return false }

        let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        return EngineDetector.detect(in: directory) == .artemisD3D11
    }

    private static func shouldMoveToArtemisMFD3D11(_ game: Game) -> Bool {
        if game.engine == .artemisMFD3D11 { return true }
        guard game.engine == nil ||
            game.engine == .unknown ||
            game.engine == .kirikiri ||
            game.engine == .artemis ||
            game.engine == .artemisD3D11 else { return false }

        let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        return EngineDetector.detect(in: directory) == .artemisMFD3D11
    }
}
