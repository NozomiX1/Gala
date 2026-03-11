import Foundation

public final class LibraryStore: Sendable {
    private let libraryFileURL: URL

    public init(baseURL: URL) {
        self.libraryFileURL = baseURL.appendingPathComponent("library.json")
    }

    public func load() throws -> [Game] {
        guard FileManager.default.fileExists(atPath: libraryFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: libraryFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode([Game].self, from: data)
    }

    public func save(_ games: [Game]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(games)
        try data.write(to: libraryFileURL, options: .atomic)
    }
}
