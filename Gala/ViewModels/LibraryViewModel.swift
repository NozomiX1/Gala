import SwiftUI
import GalaKit
import OSLog

private let startupLogger = Logger(subsystem: "com.nozomi.gala", category: "Startup")

enum RuntimeEnvironmentChange {
    case dependenciesRepaired
    case wineConfigurationReset
    case allApplicationDataReset
}

enum LibraryFilter: String, CaseIterable, Identifiable {
    case all = "全部"
    case recent = "最近"
    case favorites = "收藏"
    case completed = "已通关"

    var id: Self { self }
}

@Observable
final class LibraryViewModel {
    var games: [Game] = []
    var selectedGameId: UUID?
    var searchText = ""
    var isRuntimeEnvironmentReady = false
    var isLoadingInitialState = true
    var libraryLoadErrorMessage: String?
    var didResetAllApplicationData = false

    private let covers = NSCache<NSString, NSImage>()
    private let libraryStore: LibraryStore
    private let wineManager: WineManager
    let imageCache: ImageCache
    let vndbClient = VNDBClient()
    private var didLoadInitialState = false
    private var isLoadingInitialStateTask = false

    var selectedGame: Game? {
        games.first { $0.id == selectedGameId }
    }

    func games(matching filter: LibraryFilter) -> [Game] {
        let found = searchText.isEmpty ? games : games.filter {
            $0.title.localizedCaseInsensitiveContains(searchText) ||
            ($0.originalTitle?.localizedCaseInsensitiveContains(searchText) ?? false)
        }
        switch filter {
        case .all: return found
        case .recent:
            return found.filter { $0.lastPlayedAt != nil }
                .sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        case .favorites: return found.filter(\.isFavorite)
        case .completed: return found.filter { $0.status == .completed }
        }
    }

    /// Decoded cover art, kept in memory so views do not decode it on every redraw.
    func cover(for game: Game) -> NSImage? {
        guard let path = game.coverImagePath else { return nil }
        let key = URL(fileURLWithPath: path).lastPathComponent
        if let cached = covers.object(forKey: key as NSString) { return cached }
        guard let data = imageCache.load(forKey: key), let image = NSImage(data: data) else { return nil }
        covers.setObject(image, forKey: key as NSString)
        return image
    }

    /// Fetches the VNDB facts for a game added before they were stored, then saves them. Retries next time if offline.
    @MainActor
    func loadFactsIfMissing(for game: Game) async {
        guard let id = game.vndbId, game.chineseAvailability == nil,
              let facts = try? await vndbClient.getFacts(vnId: id),
              var current = games.first(where: { $0.id == game.id }) else { return }
        current.apply(facts)
        updateGame(current)
    }

    /// The cover that tints the wall: the most recently played game's, else the first one that has art.
    var ambientCover: NSImage? {
        let byRecency = games.sorted { ($0.lastPlayedAt ?? .distantPast) > ($1.lastPlayedAt ?? .distantPast) }
        return byRecency.lazy.compactMap { self.cover(for: $0) }.first
    }

    func apply(_ change: RuntimeEnvironmentChange) {
        switch change {
        case .dependenciesRepaired:
            didResetAllApplicationData = false
        case .wineConfigurationReset:
            markWineRuntimesUnconfigured()
        case .allApplicationDataReset:
            covers.removeAllObjects()
            loadLibrary()
            selectedGameId = nil
            didResetAllApplicationData = true
        }
        refreshRuntimeEnvironmentStatus()
    }

    init() {
        // GALA_HOME points development runs at a throwaway data directory.
        let baseURL = ProcessInfo.processInfo.environment["GALA_HOME"].map { URL(fileURLWithPath: $0) }
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
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
        do {
            games = try Self.loadAndMigrate(
                libraryStore: libraryStore,
                bottlesDirectory: wineManager.bottlesDirectory
            ).games
            libraryLoadErrorMessage = nil
        } catch {
            games = []
            selectedGameId = nil
            libraryLoadErrorMessage = "游戏库读取失败：\(error.localizedDescription)"
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
        try? FileManager.default.removeItem(at: LaunchLog.directory(gameID: game.id, logsDirectory: wineManager.logsDirectory))
        removeGame(game)
    }

    func markWineRuntimesUnconfigured() {
        var didChange = false
        for index in games.indices where games[index].isRuntimeConfigured {
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

    func toggleFavorite(_ game: Game) {
        var updated = game
        updated.isFavorite.toggle()
        updateGame(updated)
    }

    func toggleCompleted(_ game: Game) {
        var updated = game
        updated.status = game.status == .completed ? .backlog : .completed
        updateGame(updated)
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
            try Self.loadAndMigrate(libraryStore: libraryStore, bottlesDirectory: bottlesDirectory)
        }.value
    }

    private static func loadAndMigrate(
        libraryStore: LibraryStore,
        bottlesDirectory: URL
    ) throws -> LibraryLoadOutcome {
        let loadStart = now()
        let loadedGames = try libraryStore.load()
        let loadMilliseconds = milliseconds(since: loadStart)

        let migrationStart = now()
        let migratedGames = RuntimeProfileMigration.migrate(
            games: loadedGames,
            bottlesDirectory: bottlesDirectory
        )
        let migrationMilliseconds = milliseconds(since: migrationStart)

        let didMigrate = RuntimeProfileMigration.didChangeRuntimeProfile(
            from: loadedGames,
            to: migratedGames
        )
        let saveStart = now()
        if didMigrate {
            _ = try? libraryStore.saveMigrated(migratedGames, reason: "runtime-profile-migration")
        }
        let saveMilliseconds = milliseconds(since: saveStart)

        return LibraryLoadOutcome(
            games: migratedGames,
            loadMilliseconds: loadMilliseconds,
            migrationMilliseconds: migrationMilliseconds,
            saveMilliseconds: saveMilliseconds,
            didMigrate: didMigrate
        )
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
