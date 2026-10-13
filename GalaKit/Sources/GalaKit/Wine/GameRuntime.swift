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

        // A game can ask for the DXMT Wine through its graphics switch even when its profile does not.
        if wineManager.usesDXMTWine(for: game) {
            try await wineManager.ensureDXMTWineVariant { progress("正在下载 DXMT 图形运行时...", $0) }
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
            throw wineManager.usesDXMTWine(for: game) ? LaunchBlocker.dxmtMissing : LaunchBlocker.wineMissing
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
        bottleManager.adoptOlderMarker(for: game)
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
        let launchGame = try await manager.prepareLaunchGame(for: game, recipe: recipe, progressHandler: progress)
        buildGStreamerRegistryIfMissing(for: launchGame, recipe: recipe, progress: progress)
        return launchGame
    }

    /// What the latest launch of this game loaded; nil before the first launch.
    public func observation(for game: Game) -> LaunchObservation? {
        guard let url = LaunchLog.latest(gameID: game.id, logsDirectory: wineManager.logsDirectory),
              let log = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let observation = LaunchObservation(log: log)
        return observation.isEmpty ? nil : observation
    }

    /// Things the user could do for this game: what its profile's author says, then what the last launch showed.
    public func advice(for game: Game) -> [String] {
        let recipe = recipe(for: game)
        let observed = observation(for: game)?.advice(
            usesDXMTWine: wineManager.usesDXMTWine(for: game),
            usesMediaFoundationRuntime: recipe?.usesMediaFoundation == true
        ) ?? []
        return [recipe?.advice].compactMap { $0 } + observed
    }

    /// GStreamer indexes its plugins the first time it starts. Inside the game that takes most of a minute with the window
    /// black, after which the game quits. Wine's own dxdiag touches the DirectShow filters and gets the same index written in seconds.
    private func buildGStreamerRegistryIfMissing(
        for game: Game,
        recipe: RuntimeRecipe,
        progress: @escaping @Sendable (MediaCompatibilityProgress) -> Void
    ) {
        guard let runtime = wineManager.mediaFoundationRuntime,
              !FileManager.default.fileExists(atPath: runtime.gStreamerRegistryURL.path),
              let wineBinary = try? wineBinaryForLaunch(game) else { return }
        progress(MediaCompatibilityProgress(message: "准备视频组件...", completedUnitCount: 0, totalUnitCount: 0))

        let directory = FileManager.default.temporaryDirectory.appendingPathComponent("gala-dxdiag-\(UUID().uuidString)")
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let process = Process()
        process.executableURL = wineBinary
        process.arguments = ["dxdiag", "/whql:off", "/t", "report.txt"]
        process.currentDirectoryURL = directory
        process.environment = WineLaunchConfig.buildEnvironment(
            game: game,
            wineBinary: wineBinary,
            mediaFoundationRuntime: runtime,
            recipe: recipe
        )
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        // Best effort: without the index the game still starts, the slow way.
        guard (try? process.run()) != nil else { return }
        process.waitUntilExit()
        WineProcess.waitForWineDescendants(wineBinary: wineBinary, environment: process.environment)
    }
}

extension Game {
    /// Moves the game to another profile's prefix; nil goes back to its engine's default.
    /// The game then needs configuring, which is instant when that prefix already exists and is current.
    public mutating func useProfile(_ id: String?, bottlesDirectory: URL, profiles: ProfileStore = .bundled) {
        profileID = id
        bottleConfig.prefixPath = id.map { BottleManager.prefixPath(forProfile: $0, bottlesDirectory: bottlesDirectory, profiles: profiles) }
            ?? BottleManager.prefixPath(for: engine, bottlesDirectory: bottlesDirectory, profiles: profiles)
        isRuntimeConfigured = false
    }
}
