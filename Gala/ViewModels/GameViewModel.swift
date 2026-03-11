import SwiftUI
import GalaKit

@Observable
final class GameViewModel {
    var isRunning = false
    var errorMessage: String?

    private let wineProcess = WineProcess()

    func launchGame(_ game: Game, viewModel: LibraryViewModel) {
        guard !isRunning else { return }

        let wineManager = viewModel.wineManagerInstance

        if game.engine == .renpy {
            launchNative(game, viewModel: viewModel)
            return
        }

        guard let wineBinary = wineManager.wineBinaryURL else {
            errorMessage = "Wine is not installed. Please install it from Settings."
            return
        }

        isRunning = true
        errorMessage = nil

        do {
            try wineProcess.launch(game: game, wineBinary: wineBinary) { [weak self] duration in
                viewModel.recordPlayTime(gameId: game.id, duration: duration)
                DispatchQueue.main.async {
                    self?.isRunning = false
                }
            }
        } catch {
            errorMessage = error.localizedDescription
            isRunning = false
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
        errorMessage = "No native macOS binary found. Wine will be used."
    }
}
