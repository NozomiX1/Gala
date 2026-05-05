import Foundation

public enum RuntimeConfigurationPolicy {
    public static func shouldDeleteRuntimeConfiguration(for game: Game, in games: [Game]) -> Bool {
        guard game.isRuntimeConfigured else { return false }
        guard game.engine?.supportsNativeLaunch != true else { return false }

        let prefixPath = game.bottleConfig.prefixPath
        guard !prefixPath.isEmpty else { return false }

        return !games.contains { other in
            other.id != game.id &&
            other.isRuntimeConfigured &&
            other.engine?.supportsNativeLaunch != true &&
            other.bottleConfig.prefixPath == prefixPath
        }
    }
}
