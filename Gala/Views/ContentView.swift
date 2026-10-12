import SwiftUI
import GalaKit
import UniformTypeIdentifiers

struct ContentView: View {
    @Bindable var library: LibraryViewModel
    let gameVM: GameViewModel

    @State private var path: [UUID] = []
    @State private var filter: LibraryFilter = .all
    @State private var addGameRequest: AddGameRequest?
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Group {
            if library.isLoadingInitialState {
                startupLoadingView
            } else {
                switch RuntimeEnvironmentEntryPolicy.presentation(
                    isRuntimeEnvironmentReady: library.isRuntimeEnvironmentReady,
                    didResetAllApplicationData: library.didResetAllApplicationData
                ) {
                case .prepareEnvironment:
                    WelcomeView(
                        wineManager: library.wineManagerInstance,
                        onComplete: {
                            library.didResetAllApplicationData = false
                            library.refreshRuntimeEnvironmentStatus()
                        },
                        onOpenEnvironment: { openSettings() }
                    )
                case .resetComplete:
                    ResetCompleteView(
                        onInstallRuntime: {
                            library.didResetAllApplicationData = false
                            library.refreshRuntimeEnvironmentStatus()
                        },
                        onQuit: {
                            NSApplication.shared.terminate(nil)
                        }
                    )
                case .library:
                    if let errorMessage = library.libraryLoadErrorMessage {
                        libraryErrorView(errorMessage)
                    } else {
                        mainContent
                    }
                }
            }
        }
        .frame(minWidth: 820, minHeight: 540)
        .task {
            await library.loadInitialState()
            #if DEBUG
            applyDebugLaunchOptions()
            #endif
        }
    }

    private var mainContent: some View {
        NavigationStack(path: $path) {
            LibraryView(
                library: library,
                gameVM: gameVM,
                filter: $filter,
                onOpen: { path = [$0.id] },
                onAdd: { addGameRequest = AddGameRequest(droppedURL: $0) }
            )
            .navigationDestination(for: UUID.self) { id in
                if let game = library.games.first(where: { $0.id == id }) {
                    GameDetailView(game: game, library: library, gameVM: gameVM)
                }
            }
        }
        .sheet(item: $addGameRequest) { request in
            AddGameView(viewModel: library, droppedURL: request.droppedURL)
        }
        .onChange(of: library.games.map(\.id)) { _, ids in
            // Leave the detail page of a game that was just removed.
            path.removeAll { !ids.contains($0) }
        }
    }

    private var startupLoadingView: some View {
        VStack(spacing: 14) {
            ProgressView()
                .controlSize(.large)
            Text("正在加载游戏库...")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func libraryErrorView(_ message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 42))
                .foregroundStyle(.orange)
            Text("游戏库读取失败")
                .font(.title2.bold())
            Text(message)
                .font(.callout)
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            Text("Gala 没有覆盖现有游戏库文件。请检查 Application Support/Gala 下的 library.json 或从 Backups 目录恢复。")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 520)
            HStack {
                Button("重新读取") {
                    library.loadLibrary()
                }
                Button("打开设置") {
                    openSettings()
                }
            }
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    #if DEBUG
    /// Development-only shortcuts for reaching a screen without clicking, used when capturing screenshots.
    private func applyDebugLaunchOptions() {
        let environment = ProcessInfo.processInfo.environment
        if let appearance = environment["GALA_DEBUG_APPEARANCE"] {
            NSApp.appearance = NSAppearance(named: appearance == "dark" ? .darkAqua : .aqua)
        }
        if let query = environment["GALA_DEBUG_OPEN"],
           let game = library.games.first(where: { $0.title.localizedCaseInsensitiveContains(query) }) {
            path = [game.id]
        }
        if environment["GALA_DEBUG_SETTINGS"] != nil {
            openSettings()
        }
        if environment["GALA_DEBUG_ACTIVATE"] != nil {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
    #endif
}

/// A request to show the add-game sheet, optionally starting from something dropped on the window.
struct AddGameRequest: Identifiable {
    let id = UUID()
    let droppedURL: URL?
}
