import SwiftUI
import GalaKit

@Observable
final class GameViewModel {
    var isRunning = false
    var isSettingUp = false
    var setupStatus = ""
    var errorMessage: String?

    private let wineProcess = WineProcess()

    func launchGame(_ game: Game, viewModel: LibraryViewModel) {
        guard !isRunning && !isSettingUp else { return }

        let wineManager = viewModel.wineManagerInstance

        // Native engines skip Wine entirely
        if game.engine?.supportsNativeLaunch == true {
            launchNative(game, viewModel: viewModel)
            return
        }

        guard let wineBinary = wineManager.wineBinaryURL else {
            errorMessage = "Wine 未安装，请先安装。"
            return
        }

        errorMessage = nil
        let bottleManager = viewModel.bottleManager

        Task { @MainActor in
            // First launch: set up bottle if not ready
            if !bottleManager.isBottleReady(for: game) {
                isSettingUp = true
                setupStatus = "初始化 Wine 前缀..."

                do {
                    try await bottleManager.createBottle(for: game)

                    if game.engine != nil {
                        setupStatus = "应用引擎预设..."
                        try await bottleManager.applyEnginePreset(for: game)
                    }
                } catch {
                    errorMessage = "环境配置失败：\(error.localizedDescription)"
                    isSettingUp = false
                    return
                }

                isSettingUp = false
            }

            // Now launch the game
            isRunning = true
            do {
                try wineProcess.launch(game: game, wineBinary: wineBinary) { [weak self] duration in
                    viewModel.recordPlayTime(gameId: game.id, duration: duration)
                    DispatchQueue.main.async {
                        self?.isRunning = false
                        // Show Wine output if game exited quickly (likely crashed),
                        // but filter out harmless Wine fixme/stub noise
                        if duration < 5, let output = self?.wineProcess.lastOutput, !output.isEmpty {
                            let meaningful = output.components(separatedBy: "\n")
                                .filter { line in
                                    let l = line.trimmingCharacters(in: .whitespaces)
                                    return !l.isEmpty && !l.contains(":fixme:") && !l.contains(") stub")
                                }
                                .joined(separator: "\n")
                            if !meaningful.isEmpty {
                                self?.errorMessage = "游戏快速退出。Wine 输出：\n\(String(meaningful.suffix(500)))"
                            }
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
                    try wineProcess.launchNative(path: appPath) { [weak self] duration in
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
}
