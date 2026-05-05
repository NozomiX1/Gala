import SwiftUI
import GalaKit
import UniformTypeIdentifiers

enum SidebarCategory: String, CaseIterable {
    case all = "全部游戏"
    case recent = "最近游玩"
    case favorites = "收藏"
    case completed = "已通关"

    var icon: String {
        switch self {
        case .recent: return "clock"
        case .all: return "gamecontroller"
        case .favorites: return "star"
        case .completed: return "checkmark.circle"
        }
    }
}

struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var selectedCategory: SidebarCategory = .all
    @State private var showingAddGame = false
    @State private var showingRuntimeEnvironment = false
    @State private var gameVM = GameViewModel()
    @State private var changeExeGame: Game?

    var body: some View {
        Group {
            if !viewModel.isRuntimeEnvironmentReady {
                WelcomeView(
                    wineManager: viewModel.wineManagerInstance,
                    onComplete: {
                        viewModel.refreshRuntimeEnvironmentStatus()
                    },
                    onOpenEnvironment: {
                        showingRuntimeEnvironment = true
                    }
                )
            } else {
                mainContent
            }
        }
        .sheet(isPresented: $showingRuntimeEnvironment) {
            RuntimeEnvironmentView(wineManager: viewModel.wineManagerInstance) { change in
                switch change {
                case .dependenciesRepaired:
                    break
                case .wineConfigurationReset:
                    viewModel.markWineRuntimesUnconfigured()
                case .allApplicationDataReset:
                    viewModel.loadLibrary()
                    viewModel.selectedGameId = nil
                }
                viewModel.refreshRuntimeEnvironmentStatus()
            }
        }
    }

    private var mainContent: some View {
        NavigationSplitView {
            List(SidebarCategory.allCases, id: \.self, selection: $selectedCategory) { category in
                Label(category.rawValue, systemImage: category.icon)
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(min: 150, ideal: 180)
        } content: {
            GameGridView(
                games: filteredByCategory,
                selectedGameId: $viewModel.selectedGameId,
                imageCache: viewModel.imageCache,
                onLaunch: { game in
                    gameVM.launchGame(game, viewModel: viewModel)
                },
                onConfigureRuntime: { game in
                    gameVM.configureRuntime(for: game, viewModel: viewModel)
                },
                onRemoveRuntime: { game in
                    viewModel.removeRuntime(for: game)
                },
                onRemoveFromLibrary: { game in
                    if viewModel.selectedGameId == game.id {
                        viewModel.selectedGameId = nil
                    }
                    viewModel.removeFromLibrary(game)
                },
                onChangeExe: { game in
                    changeExeGame = game
                },
                onSetStatus: { game, status in
                    var updated = game
                    updated.status = status
                    viewModel.updateGame(updated)
                },
                onToggleFavorite: { game in
                    var updated = game
                    updated.isFavorite.toggle()
                    viewModel.updateGame(updated)
                }
            )
            .searchable(text: $viewModel.searchText, prompt: "搜索游戏...")
            .navigationSplitViewColumnWidth(min: 300, ideal: 500)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingRuntimeEnvironment = true
                    } label: {
                        Label("运行环境", systemImage: "wrench.and.screwdriver")
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGame = true
                    } label: {
                        Label("添加游戏", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let game = viewModel.selectedGame {
                GameDetailView(game: game, viewModel: viewModel)
            } else {
                Text("选择一个游戏")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingAddGame) {
            AddGameView(viewModel: viewModel)
        }
        .onChange(of: changeExeGame?.id) { _, newValue in
            guard newValue != nil else { return }
            let panel = NSOpenPanel()
            panel.allowedContentTypes = [.exe]
            panel.canChooseDirectories = false
            panel.message = "选择新的启动文件"
            if panel.runModal() == .OK, let url = panel.url, var game = changeExeGame {
                game.executablePath = url.path
                viewModel.updateGame(game)
            }
            changeExeGame = nil
        }
    }

    private var filteredByCategory: [Game] {
        let games = viewModel.filteredGames
        switch selectedCategory {
        case .recent:
            let recent = games.filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
            return recent.isEmpty ? games : recent
        case .all: return games
        case .favorites: return games.filter { $0.isFavorite }
        case .completed: return games.filter { $0.status == .completed }
        }
    }
}
