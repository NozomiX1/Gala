import Foundation

public enum RuntimeProfileMigration {
    public static func migrate(games: [Game], bottlesDirectory: URL) -> [Game] {
        games.map { game in
            guard shouldMoveToIkuraGDLFamilyProject(game) else { return game }

            var migrated = game
            let targetPrefix = bottlesDirectory
                .appendingPathComponent("Profiles")
                .appendingPathComponent(Engine.ikuraGDLFamilyProject.runtimeProfile.rawValue)
                .path

            let changedRuntime = migrated.engine != .ikuraGDLFamilyProject ||
                migrated.bottleConfig.prefixPath != targetPrefix
            migrated.engine = .ikuraGDLFamilyProject
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

    private static func shouldMoveToIkuraGDLFamilyProject(_ game: Game) -> Bool {
        if game.engine == .ikuraGDLFamilyProject { return true }
        guard game.engine == nil || game.engine == .unknown else { return false }

        let directory = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        return EngineDetector.detect(in: directory) == .ikuraGDLFamilyProject
    }
}
