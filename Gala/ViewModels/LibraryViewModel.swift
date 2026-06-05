import SwiftUI
import GalaKit
import OSLog

private let startupLogger = Logger(subsystem: "com.nozomi.gala", category: "Startup")

@Observable
final class LibraryViewModel {
    var games: [Game] = []
    var selectedGameId: UUID?
    var searchText = ""
    var isRuntimeEnvironmentReady = false
    var isLoadingInitialState = true
    var libraryLoadErrorMessage: String?

    private let libraryStore: LibraryStore
    private let wineManager: WineManager
    let imageCache: ImageCache
    let vndbClient = VNDBClient()
    private var didLoadInitialState = false
    private var isLoadingInitialStateTask = false

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
    }

    @MainActor
    func loadInitialState() async {
        guard !didLoadInitialState, !isLoadingInitialStateTask else { return }

        isLoadingInitialState = true
        isLoadingInitialStateTask = true
        let totalStart = Self.now()

        let outcome: LibraryLoadOutcome
        do {
            outcome = try await loadLibraryInBackground()
            games = outcome.games
            selectedGameId = selectedGameId.flatMap { id in games.contains { $0.id == id } ? id : nil }
            libraryLoadErrorMessage = nil
        } catch {
            games = []
            selectedGameId = nil
            libraryLoadErrorMessage = "游戏库读取失败：\(error.localizedDescription)"
            outcome = LibraryLoadOutcome.empty
        }

        let runtimeStart = Self.now()
        refreshRuntimeEnvironmentStatus()
        let runtimeMilliseconds = Self.milliseconds(since: runtimeStart)

        let totalMilliseconds = Self.milliseconds(since: totalStart)
        let message = "initial state loaded in \(totalMilliseconds)ms; " +
            "library=\(outcome.loadMilliseconds)ms; " +
            "migration=\(outcome.migrationMilliseconds)ms; " +
            "save=\(outcome.saveMilliseconds)ms; " +
            "runtimeStatus=\(runtimeMilliseconds)ms; " +
            "games=\(outcome.games.count); " +
            "migrated=\(outcome.didMigrate)"
        startupLogger.info("\(message, privacy: .public)")

        didLoadInitialState = true
        isLoadingInitialState = false
        isLoadingInitialStateTask = false
    }

    func refreshRuntimeEnvironmentStatus() {
        isRuntimeEnvironmentReady = wineManager.runtimeEnvironmentStatus().isReady
    }

    func loadLibrary() {
        let loadedGames: [Game]
        do {
            loadedGames = try libraryStore.load()
            libraryLoadErrorMessage = nil
        } catch {
            games = []
            selectedGameId = nil
            libraryLoadErrorMessage = "游戏库读取失败：\(error.localizedDescription)"
            return
        }

        games = RuntimeProfileMigration.migrate(
            games: loadedGames,
            bottlesDirectory: wineManager.bottlesDirectory
        )
        if RuntimeProfileMigration.didChangeRuntimeProfile(from: loadedGames, to: games) {
            _ = try? libraryStore.saveMigrated(games, reason: "runtime-profile-migration")
        }
    }

    func saveLibrary() {
        guard libraryLoadErrorMessage == nil else { return }
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

    func markRuntimeConfigured(for game: Game) {
        var updated = game
        updated.isRuntimeConfigured = true
        updateGame(updated)
    }

    func removeRuntime(for game: Game) {
        deleteRuntimeConfigurationIfLastUser(for: game)

        var updated = game
        updated.isRuntimeConfigured = false
        updateGame(updated)
    }

    func removeFromLibrary(_ game: Game) {
        deleteRuntimeConfigurationIfLastUser(for: game)

        let cacheKey = game.vndbId ?? game.id.uuidString
        imageCache.delete(forKey: cacheKey)
        removeGame(game)
    }

    func markWineRuntimesUnconfigured() {
        var didChange = false
        for index in games.indices where games[index].engine?.supportsNativeLaunch != true && games[index].isRuntimeConfigured {
            games[index].isRuntimeConfigured = false
            didChange = true
        }

        if didChange {
            saveLibrary()
        }
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

    private func loadLibraryInBackground() async throws -> LibraryLoadOutcome {
        let libraryStore = libraryStore
        let bottlesDirectory = wineManager.bottlesDirectory

        return try await Task.detached(priority: .userInitiated) {
            let loadStart = Self.now()
            let loadedGames = try libraryStore.load()
            let loadMilliseconds = Self.milliseconds(since: loadStart)

            let migrationStart = Self.now()
            let migratedGames = RuntimeProfileMigration.migrate(
                games: loadedGames,
                bottlesDirectory: bottlesDirectory
            )
            let migrationMilliseconds = Self.milliseconds(since: migrationStart)

            let didMigrate = RuntimeProfileMigration.didChangeRuntimeProfile(
                from: loadedGames,
                to: migratedGames
            )
            let saveStart = Self.now()
            if didMigrate {
                _ = try? libraryStore.saveMigrated(migratedGames, reason: "runtime-profile-migration")
            }
            let saveMilliseconds = Self.milliseconds(since: saveStart)

            return LibraryLoadOutcome(
                games: migratedGames,
                loadMilliseconds: loadMilliseconds,
                migrationMilliseconds: migrationMilliseconds,
                saveMilliseconds: saveMilliseconds,
                didMigrate: didMigrate
            )
        }.value
    }

    private func deleteRuntimeConfigurationIfLastUser(for game: Game) {
        guard RuntimeConfigurationPolicy.shouldDeleteRuntimeConfiguration(for: game, in: games) else { return }
        try? bottleManager.deleteBottle(for: game)
    }

    private static func now() -> CFAbsoluteTime {
        CFAbsoluteTimeGetCurrent()
    }

    private static func milliseconds(since start: CFAbsoluteTime) -> Int {
        Int((CFAbsoluteTimeGetCurrent() - start) * 1000)
    }
}

private struct LibraryLoadOutcome {
    let games: [Game]
    let loadMilliseconds: Int
    let migrationMilliseconds: Int
    let saveMilliseconds: Int
    let didMigrate: Bool

    static let empty = LibraryLoadOutcome(
        games: [],
        loadMilliseconds: 0,
        migrationMilliseconds: 0,
        saveMilliseconds: 0,
        didMigrate: false
    )
}
