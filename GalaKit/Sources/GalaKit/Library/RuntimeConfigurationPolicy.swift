import Foundation

public enum RuntimeConfigurationPolicy {
    public static func needsRuntimeConfiguration(for game: Game, bottleReady: Bool) -> Bool {
        !bottleReady
    }

    public static func needsEnginePreset(
        for game: Game,
        bottleReady: Bool,
        runtimeMarkerStatus: RuntimeMarkerStatus,
        managedRuntimeReady: Bool
    ) -> Bool {
        guard game.engine != nil else { return false }

        if !managedRuntimeReady { return true }
        if runtimeMarkerStatus == .outdated { return true }
        if game.isRuntimeConfigured { return false }

        guard bottleReady else { return true }
        return runtimeMarkerStatus != .current
    }

    public static func shouldDeleteRuntimeConfiguration(for game: Game, in games: [Game]) -> Bool {
        guard game.isRuntimeConfigured else { return false }

        let prefixPath = game.bottleConfig.prefixPath
        guard !prefixPath.isEmpty else { return false }

        return !games.contains { other in
            other.id != game.id &&
            other.isRuntimeConfigured &&
            other.bottleConfig.prefixPath == prefixPath
        }
    }
}
