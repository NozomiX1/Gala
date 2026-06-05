import SwiftUI
import GalaKit

@Observable
final class GameViewModel {
    var isRunning = false
    var isSettingUp = false
    var setupStatus = ""
    var setupProgress: Double?
    var errorMessage: String?

    private let wineProcess = WineProcess()

    func configureRuntime(for game: Game, viewModel: LibraryViewModel) {
        guard !isRunning && !isSettingUp else { return }

        errorMessage = nil

        if game.engine?.supportsNativeLaunch == true {
            viewModel.markRuntimeConfigured(for: game)
            return
        }

        guard viewModel.wineManagerInstance.wineBinaryURL != nil else {
            errorMessage = "Wine 未安装，请先安装。"
            return
        }

        let bottleManager = viewModel.bottleManager

        Task { @MainActor in
            isSettingUp = true
            setupStatus = "检查运行环境..."
            setupProgress = nil

            do {
                let bottleReady = bottleManager.isBottleReady(for: game)
                let needsBottle = RuntimeConfigurationPolicy.needsRuntimeConfiguration(
                    for: game,
                    bottleReady: bottleReady
                )
                let needsPreset = game.engine != nil &&
                    (!game.isRuntimeConfigured || needsManagedRuntimePreparation(for: game, viewModel: viewModel))

                if needsBottle {
                    setupStatus = "初始化 Wine 前缀..."
                    setupProgress = nil
                    try await bottleManager.createBottle(for: game)
                }

                if needsBottle || needsPreset {
                    setupStatus = "应用引擎预设..."
                    setupProgress = 0
                    try await bottleManager.applyEnginePreset(for: game) { [weak self] progress in
                        Task { @MainActor in
                            self?.setupStatus = progress.message
                            self?.setupProgress = progress.currentItemProgress ?? progress.fraction
                        }
                    }
                } else {
                    setupStatus = "复用已有运行环境..."
                    setupProgress = nil
                }

                viewModel.markRuntimeConfigured(for: game)
            } catch {
                errorMessage = "环境配置失败：\(error.localizedDescription)"
            }

            isSettingUp = false
            setupProgress = nil
        }
    }

    func launchGame(_ game: Game, viewModel: LibraryViewModel) {
        guard !isRunning && !isSettingUp else { return }

        guard game.isRuntimeConfigured else {
            errorMessage = "请先配置运行环境。"
            return
        }

        let wineManager = viewModel.wineManagerInstance

        // Native engines skip Wine entirely
        if game.engine?.supportsNativeLaunch == true {
            launchNative(game, viewModel: viewModel)
            return
        }

        guard let wineBinary = wineManager.wineBinaryURL(for: game) else {
            if game.engine?.runtimeProfile == .artemisD3D11 {
                errorMessage = "DXMT 图形运行时未配置，请重新配置运行环境。"
                var updated = game
                updated.isRuntimeConfigured = false
                viewModel.updateGame(updated)
            } else {
                errorMessage = "Wine 未安装，请先安装。"
            }
            return
        }

        errorMessage = nil
        let bottleManager = viewModel.bottleManager

        guard bottleManager.isBottleReady(for: game) else {
            errorMessage = "运行环境不存在或未完成，请重新配置环境。"
            var updated = game
            updated.isRuntimeConfigured = false
            viewModel.updateGame(updated)
            return
        }

        Task { @MainActor in
            // Now launch the game
            isRunning = true
            do {
                try wineProcess.launch(game: game, wineBinary: wineBinary) { [weak self] duration, terminationStatus, output in
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

    private func launchNative(_ game: Game, viewModel: LibraryViewModel) {
        let gameDir = URL(fileURLWithPath: game.executablePath).deletingLastPathComponent()
        let fm = FileManager.default
        if let contents = try? fm.contentsOfDirectory(atPath: gameDir.path) {
            if let app = contents.first(where: { $0.hasSuffix(".app") }) {
                let appPath = gameDir.appendingPathComponent(app).path
                isRunning = true
                do {
                    try wineProcess.launchNative(path: appPath) { [weak self] duration, _, _ in
                        viewModel.recordPlayTime(gameId: game.id, duration: duration)
                        DispatchQueue.main.async {
                            self?.isRunning = false
                        }
                    }
                } catch {
                    errorMessage = error.localizedDescription
                    isRunning = false
                }
                return
            }
        }
        errorMessage = "未找到原生 macOS 程序，将使用 Wine 启动。"
    }

    private func needsManagedRuntimePreparation(for game: Game, viewModel: LibraryViewModel) -> Bool {
        guard game.engine?.preset.managedComponents.isEmpty == false else { return false }
        return viewModel.wineManagerInstance.wineBinaryURL(for: game) == nil
    }
}
