import SwiftUI
import GalaKit

@Observable
final class GameViewModel {
    var isRunning = false
    var isSettingUp = false
    var setupStatus = ""
    var setupProgress: Double?
    var errorMessage: String?
    /// The game the state above belongs to. Only one game is configured or running at a time.
    private(set) var activeGameID: UUID?

    private let wineProcess = WineProcess()

    var isBusy: Bool { isRunning || isSettingUp }

    func configureRuntime(for game: Game, viewModel: LibraryViewModel) {
        guard !isRunning && !isSettingUp else { return }

        activeGameID = game.id
        errorMessage = nil
        let runtime = GameRuntime(wineManager: viewModel.wineManagerInstance)

        Task { @MainActor in
            isSettingUp = true
            setupProgress = nil

            do {
                try await runtime.configure(game) { [weak self] message, fraction in
                    Task { @MainActor in
                        self?.setupStatus = message
                        self?.setupProgress = fraction
                    }
                }
                viewModel.markRuntimeConfigured(for: game)
            } catch let blocker as LaunchBlocker {
                errorMessage = blocker.localizedDescription
            } catch {
                errorMessage = "环境配置失败：\(error.localizedDescription)"
            }

            isSettingUp = false
            setupProgress = nil
        }
    }

    func launchGame(_ game: Game, viewModel: LibraryViewModel) {
        guard !isRunning && !isSettingUp else { return }

        activeGameID = game.id
        let wineManager = viewModel.wineManagerInstance
        let runtime = GameRuntime(wineManager: wineManager)

        let wineBinary: URL
        do {
            wineBinary = try runtime.wineBinaryForLaunch(game)
        } catch {
            errorMessage = error.localizedDescription
            if (error as? LaunchBlocker)?.requiresReconfiguration == true {
                var updated = game
                updated.isRuntimeConfigured = false
                viewModel.updateGame(updated)
            }
            return
        }

        errorMessage = nil

        Task { @MainActor in
            do {
                let launchGame = try await prepareMediaCompatibilityIfNeeded(for: game, runtime: runtime)

                // Now launch the game
                isRunning = true
                try wineProcess.launch(
                    game: launchGame,
                    wineBinary: wineBinary,
                    mediaFoundationRuntime: wineManager.mediaFoundationRuntime,
                    logFile: try? LaunchLog.newURL(gameID: game.id, logsDirectory: wineManager.logsDirectory),
                    recipe: runtime.recipe(for: game)
                ) { [weak self] duration, terminationStatus, output in
                    viewModel.recordPlayTime(gameId: game.id, duration: duration)
                    DispatchQueue.main.async {
                        self?.isRunning = false
                        if let meaningful = WineLaunchDiagnostics.meaningfulQuickExitOutput(
                            duration: duration,
                            terminationStatus: terminationStatus,
                            output: output
                        ) {
                            self?.errorMessage = "游戏快速退出。Wine 输出：\n\(meaningful)"
                        }
                    }
                }
            } catch {
                errorMessage = "启动失败：\(error.localizedDescription)"
                isRunning = false
            }
        }
    }

    private func prepareMediaCompatibilityIfNeeded(for game: Game, runtime: GameRuntime) async throws -> Game {
        // Checked here as well so other games do not flash the progress view.
        guard runtime.recipe(for: game)?.usesMediaFoundation == true else { return game }

        isSettingUp = true
        setupStatus = "准备媒体兼容缓存..."
        setupProgress = 0
        defer {
            isSettingUp = false
            setupProgress = nil
        }

        return try await runtime.prepareMedia(for: game) { [weak self] progress in
            Task { @MainActor in
                self?.setupStatus = progress.message
                self?.setupProgress = progress.fraction
            }
        }
    }
}
