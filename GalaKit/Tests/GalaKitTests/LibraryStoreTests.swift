import Testing
import Foundation
@testable import GalaKit

@Test func loadEmptyLibrary() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)
    let games = try store.load()
    #expect(games.isEmpty)
}

@Test func saveAndLoadGames() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)
    var game = Game(title: "Test Game", executablePath: "/test.exe")
    game.totalPlayTime = 3600
    game.engine = .kirikiri

    try store.save([game])
    let loaded = try store.load()

    #expect(loaded.count == 1)
    #expect(loaded[0].title == "Test Game")
    #expect(loaded[0].totalPlayTime == 3600)
    #expect(loaded[0].engine == .kirikiri)
}

@Test func loadVersionedLibraryDocument() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let json = """
    {
      "schemaVersion": 1,
      "games": [
        {
          "id": "00000000-0000-0000-0000-000000000010",
          "title": "Versioned Game",
          "executablePath": "/Games/versioned.exe",
          "totalPlayTime": 7200,
          "engine": "kirikiri",
          "status": "playing",
          "isFavorite": true,
          "bottleConfig": {
            "prefixPath": "/tmp/Gala/Bottles/Profiles/kirikiri",
            "windowsVersion": "win10",
            "dllOverrides": {},
            "environment": {},
            "launchArguments": [],
            "locale": "zh_CN.UTF-8",
            "winetricksComponents": []
          },
          "isRuntimeConfigured": true
        }
      ]
    }
    """
    try Data(json.utf8).write(to: tempDir.appendingPathComponent("library.json"))

    let loaded = try LibraryStore(baseURL: tempDir).load()

    #expect(loaded.count == 1)
    #expect(loaded[0].title == "Versioned Game")
    #expect(loaded[0].totalPlayTime == 7200)
    #expect(loaded[0].engine == .kirikiri)
    #expect(loaded[0].status == .playing)
    #expect(loaded[0].isFavorite)
    #expect(loaded[0].isRuntimeConfigured)
}

@Test func saveWritesVersionedLibraryDocument() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)
    try store.save([Game(title: "Schema Game", executablePath: "/schema.exe")])

    let data = try Data(contentsOf: tempDir.appendingPathComponent("library.json"))
    let object = try JSONSerialization.jsonObject(with: data) as? [String: Any]
    let games = object?["games"] as? [[String: Any]]

    #expect(object?["schemaVersion"] as? Int == LibraryStore.currentSchemaVersion)
    #expect(games?.count == 1)
    #expect(games?.first?["title"] as? String == "Schema Game")
}

@Test func saveMigratedCreatesBackupBeforeOverwritingLibrary() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let originalJSON = """
    [
      {
        "id": "00000000-0000-0000-0000-000000000011",
        "title": "Original Game",
        "executablePath": "/Games/original.exe",
        "totalPlayTime": 3600,
        "bottleConfig": {
          "prefixPath": "/tmp/Gala/Bottles/Profiles/common",
          "windowsVersion": "win10",
          "dllOverrides": {},
          "environment": {},
          "launchArguments": [],
          "locale": "zh_CN.UTF-8",
          "winetricksComponents": []
        }
      }
    ]
    """
    let libraryURL = tempDir.appendingPathComponent("library.json")
    try Data(originalJSON.utf8).write(to: libraryURL)

    let store = LibraryStore(baseURL: tempDir)
    let migrated = Game(title: "Migrated Game", executablePath: "/Games/migrated.exe")
    let backupURL = try #require(try store.saveMigrated([migrated], reason: "test-migration"))

    #expect(backupURL.lastPathComponent.contains("test-migration"))
    #expect(backupURL.deletingLastPathComponent().lastPathComponent == "Backups")
    #expect(try String(contentsOf: backupURL, encoding: .utf8) == originalJSON)

    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].title == "Migrated Game")
}

@Test func saveRecreatesLibraryDirectoryIfDeleted() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let libraryDir = tempDir.appendingPathComponent("Gala")
    try FileManager.default.createDirectory(at: libraryDir, withIntermediateDirectories: true)
    let store = LibraryStore(baseURL: libraryDir)
    try FileManager.default.removeItem(at: libraryDir)

    let game = Game(title: "After Reset", executablePath: "/game.exe")
    try store.save([game])

    let loaded = try store.load()
    #expect(loaded.count == 1)
    #expect(loaded[0].title == "After Reset")
}

@Test func addAndRemoveGame() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let store = LibraryStore(baseURL: tempDir)
    let game1 = Game(title: "Game 1", executablePath: "/g1.exe")
    let game2 = Game(title: "Game 2", executablePath: "/g2.exe")

    try store.save([game1, game2])
    var games = try store.load()
    #expect(games.count == 2)

    games.removeAll { $0.id == game1.id }
    try store.save(games)
    let reloaded = try store.load()
    #expect(reloaded.count == 1)
    #expect(reloaded[0].title == "Game 2")
}
