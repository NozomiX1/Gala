import SwiftUI
import GalaKit

enum SidebarCategory: String, CaseIterable {
    case all = "All Games"
    case recent = "Recent"
    case playing = "Playing"
    case backlog = "Backlog"
    case completed = "Completed"
    case dropped = "Dropped"

    var icon: String {
        switch self {
        case .all: return "gamecontroller"
        case .recent: return "clock"
        case .playing: return "play.circle"
        case .backlog: return "bookmark"
        case .completed: return "checkmark.circle"
        case .dropped: return "xmark.circle"
        }
    }
}

struct ContentView: View {
    @State private var viewModel = LibraryViewModel()
    @State private var selectedCategory: SidebarCategory = .all
    @State private var showingAddGame = false

    var body: some View {
        if !viewModel.isWineInstalled {
            WelcomeView(wineManager: viewModel.wineManagerInstance) {
                viewModel.isWineInstalled = true
            }
        } else {
            mainContent
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
                imageCache: viewModel.imageCache
            )
            .searchable(text: $viewModel.searchText, prompt: "Search games...")
            .navigationSplitViewColumnWidth(min: 300, ideal: 500)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showingAddGame = true
                    } label: {
                        Label("Add Game", systemImage: "plus")
                    }
                }
            }
        } detail: {
            if let game = viewModel.selectedGame {
                GameDetailView(game: game, viewModel: viewModel)
            } else {
                Text("Select a game")
                    .foregroundStyle(.secondary)
            }
        }
        .frame(minWidth: 800, minHeight: 500)
        .sheet(isPresented: $showingAddGame) {
            AddGameView(viewModel: viewModel)
        }
    }

    private var filteredByCategory: [Game] {
        let games = viewModel.filteredGames
        switch selectedCategory {
        case .all: return games
        case .recent:
            return games
                .filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .playing: return games.filter { $0.status == .playing }
        case .backlog: return games.filter { $0.status == .backlog }
        case .completed: return games.filter { $0.status == .completed }
        case .dropped: return games.filter { $0.status == .dropped }
        }
    }
}
