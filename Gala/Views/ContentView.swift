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
                onAdd: startAdding
            )
            .navigationDestination(for: UUID.self) { id in
                if let game = library.games.first(where: { $0.id == id }) {
                    GameDetailView(game: game, library: library, gameVM: gameVM)
                }
            }
        }
        .sheet(item: $addGameRequest) { request in
            AddGameView(viewModel: library, executable: request.executable)
        }
        .onChange(of: library.addGameRequests) {
            startAdding(from: nil)
        }
        .onChange(of: library.games.map(\.id)) { _, ids in
            // Leave the detail page of a game that was just removed.
            path.removeAll { !ids.contains($0) }
        }
    }

    /// Goes straight to the file panel; the sheet only appears once there is an executable to match.
    private func startAdding(from dropped: URL?) {
        if let dropped, dropped.pathExtension.lowercased() == "exe" {
            addGameRequest = AddGameRequest(executable: dropped)
            return
        }
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.exe]
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "选择游戏的 .exe 文件"
        panel.directoryURL = dropped
        guard panel.runModal() == .OK, let url = panel.url else { return }
        addGameRequest = AddGameRequest(executable: url)
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
        if let executable = environment["GALA_DEBUG_ADD"] {
            addGameRequest = AddGameRequest(executable: URL(fileURLWithPath: executable))
        }
        if environment["GALA_DEBUG_POP"] != nil {
            Task {
                try? await Task.sleep(for: .seconds(2))
                path = []
            }
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

/// A request to show the add-game sheet for one executable.
struct AddGameRequest: Identifiable {
    let id = UUID()
    let executable: URL
}
