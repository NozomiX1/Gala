import SwiftUI
import GalaKit

@Observable
final class LibraryViewModel {
    var games: [Game] = []
    var selectedGameId: UUID?
    var searchText = ""
    var isWineInstalled = false

    private let libraryStore: LibraryStore
    private let wineManager: WineManager
    let imageCache: ImageCache
    let vndbClient = VNDBClient()

    var selectedGame: Game? {
        games.first { $0.id == selectedGameId }
    }

    var filteredGames: [Game] {
        if searchText.isEmpty { return games }
        return games.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.originalTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
    }

    init() {
        let baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Gala")
        try? FileManager.default.createDirectory(at: baseURL, withIntermediateDirectories: true)

        self.libraryStore = LibraryStore(baseURL: baseURL)
        self.wineManager = WineManager(baseURL: baseURL)
        self.imageCache = ImageCache(
            cacheDirectory: baseURL.appendingPathComponent("Cache").appendingPathComponent("covers")
        )

        loadLibrary()
        isWineInstalled = wineManager.isWineInstalled
    }

    func loadLibrary() {
        games = (try? libraryStore.load()) ?? []
    }

    func saveLibrary() {
        try? libraryStore.save(games)
    }

    func addGame(_ game: Game) {
        games.append(game)
        saveLibrary()
    }

    func removeGame(_ game: Game) {
        games.removeAll { $0.id == game.id }
        saveLibrary()
    }

    func updateGame(_ game: Game) {
        if let index = games.firstIndex(where: { $0.id == game.id }) {
            games[index] = game
            saveLibrary()
        }
    }

    func recordPlayTime(gameId: UUID, duration: TimeInterval) {
        if let index = games.firstIndex(where: { $0.id == gameId }) {
            games[index].totalPlayTime += duration
            games[index].lastPlayedAt = Date()
            saveLibrary()
        }
    }

    var wineManagerInstance: WineManager { wineManager }
    var bottleManager: BottleManager {
        BottleManager(bottlesDirectory: wineManager.bottlesDirectory, wineManager: wineManager)
    }
}
