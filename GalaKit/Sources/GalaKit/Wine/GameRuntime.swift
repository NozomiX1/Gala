import Foundation

/// Why a game cannot be launched right now.
public enum LaunchBlocker: Error, Equatable, LocalizedError, Sendable {
    case notConfigured
    case wineMissing
    case dxmtMissing
    case bottleMissing
    case presetOutdated
    case stateUnreadable(String)

    /// The stored "configured" flag is wrong and the runtime has to be configured again.
    public var requiresReconfiguration: Bool {
        switch self {
        case .dxmtMissing, .bottleMissing, .presetOutdated: return true
        case .notConfigured, .wineMissing, .stateUnreadable: return false
        }
    }

    public var errorDescription: String? {
        switch self {
        case .notConfigured: return "请先配置运行环境。"
        case .wineMissing: return "Wine 未安装，请先安装。"
        case .dxmtMissing: return "DXMT 图形运行时未配置，请重新配置运行环境。"
        case .bottleMissing: return "运行环境不存在或未完成，请重新配置环境。"
        case .presetOutdated: return "运行环境配置已过期，请重新配置环境。"
        case .stateUnreadable(let detail): return "运行环境状态检查失败：\(detail)"
        }
    }
}

/// The steps between "a game in the library" and "a Wine process", shared by the app and gala-cli.
public struct GameRuntime: Sendable {
    public let wineManager: WineManager

    public init(wineManager: WineManager) {
        self.wineManager = wineManager
    }

    private var bottleManager: BottleManager {
        BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    }

    /// The recipe this game runs with; pass it to `WineProcess.launch` so a hand-picked profile is honoured.
    public func recipe(for game: Game) -> RuntimeRecipe? {
        wineManager.profiles.recipe(for: game)
    }

    /// Creates the bottle and applies the engine preset, skipping whatever an existing bottle already has.
    public func configure(
        _ game: Game,
        progress: @escaping @Sendable (_ message: String, _ fraction: Double?) -> Void
    ) async throws {
        guard wineManager.wineBinaryURL != nil else { throw LaunchBlocker.wineMissing }

        progress("检查运行环境...", nil)
        let bottleManager = bottleManager
        let bottleReady = bottleManager.isBottleReady(for: game)
        let needsBottle = RuntimeConfigurationPolicy.needsRuntimeConfiguration(for: game, bottleReady: bottleReady)
        let needsPreset = RuntimeConfigurationPolicy.needsEnginePreset(
            for: game,
            bottleReady: bottleReady,
            runtimeMarkerStatus: try bottleManager.runtimeMarkerStatus(for: game),
            managedRuntimeReady: wineManager.isManagedRuntimeReady(for: game)
        )

        if needsBottle {
            progress("初始化 Wine 前缀...", nil)
            try await bottleManager.createBottle(for: game)
        }

        guard needsBottle || needsPreset else {
            progress("复用已有运行环境...", nil)
            return
        }

        progress("应用引擎预设...", 0)
        try await bottleManager.applyEnginePreset(for: game) { step in
            progress(step.message, step.currentItemProgress ?? step.fraction)
        }
        try bottleManager.writeRuntimeMarker(for: game)
    }

    /// Checks that the game can launch and returns the Wine binary to launch it with.
    public func wineBinaryForLaunch(_ game: Game) throws -> URL {
        guard game.isRuntimeConfigured else { throw LaunchBlocker.notConfigured }
        guard let wineBinary = wineManager.wineBinaryURL(for: game) else {
            throw recipe(for: game)?.usesDXMTWine == true ? LaunchBlocker.dxmtMissing : LaunchBlocker.wineMissing
        }

        let bottleManager = bottleManager
        guard bottleManager.isBottleReady(for: game) else { throw LaunchBlocker.bottleMissing }

        let markerStatus: RuntimeMarkerStatus
        do {
            markerStatus = try bottleManager.runtimeMarkerStatus(for: game)
        } catch {
            throw LaunchBlocker.stateUnreadable(error.localizedDescription)
        }
        if RuntimeConfigurationPolicy.needsEnginePreset(
            for: game,
            bottleReady: true,
            runtimeMarkerStatus: markerStatus,
            managedRuntimeReady: wineManager.isManagedRuntimeReady(for: game)
        ) {
            throw LaunchBlocker.presetOutdated
        }
        return wineBinary
    }

    /// Builds the media overlay some profiles need; returns the game to actually launch.
    public func prepareMedia(
        for game: Game,
        progress: @escaping @Sendable (MediaCompatibilityProgress) -> Void
    ) async throws -> Game {
        guard let recipe = recipe(for: game), recipe.usesMediaFoundation else { return game }
        let manager = MediaCompatibilityManager(
            overlaysDirectory: wineManager.mediaOverlaysDirectory,
            ffmpegURL: wineManager.mediaFoundationFFmpegURL
        )
        return try await manager.prepareLaunchGame(for: game, recipe: recipe, progressHandler: progress)
    }
}

extension Game {
    /// Moves the game to another profile's prefix; nil goes back to its engine's default.
    /// The game then needs configuring, which is instant when that prefix already exists and is current.
    public mutating func useProfile(_ id: String?, bottlesDirectory: URL) {
        profileID = id
        bottleConfig.prefixPath = id.map { BottleManager.prefixPath(forProfile: $0, bottlesDirectory: bottlesDirectory) }
            ?? BottleManager.prefixPath(for: engine, bottlesDirectory: bottlesDirectory)
        isRuntimeConfigured = false
    }
}
