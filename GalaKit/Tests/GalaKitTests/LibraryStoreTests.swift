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
