import Testing
import Foundation
@testable import GalaKit

@Test func saveAndLoadImage() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let testData = Data("fake image data".utf8)

    try cache.save(testData, forKey: "v11")
    let loaded = cache.load(forKey: "v11")

    #expect(loaded == testData)
}

@Test func loadMissingImageReturnsNil() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let loaded = cache.load(forKey: "nonexistent")
    #expect(loaded == nil)
}

@Test func imagePathForKey() throws {
    let tempDir = FileManager.default.temporaryDirectory
        .appendingPathComponent(UUID().uuidString)
    try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    defer { try? FileManager.default.removeItem(at: tempDir) }

    let cache = ImageCache(cacheDirectory: tempDir)
    let testData = Data("fake".utf8)
    try cache.save(testData, forKey: "v17")

    let path = cache.path(forKey: "v17")
    #expect(path != nil)
    #expect(FileManager.default.fileExists(atPath: path!))
}
