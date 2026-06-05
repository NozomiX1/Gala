import Foundation

public final class LibraryStore: Sendable {
    public static let currentSchemaVersion = 1

    private let libraryFileURL: URL
    private let backupsDirectoryURL: URL

    public init(baseURL: URL) {
        self.libraryFileURL = baseURL.appendingPathComponent("library.json")
        self.backupsDirectoryURL = baseURL.appendingPathComponent("Backups")
    }

    public func load() throws -> [Game] {
        guard FileManager.default.fileExists(atPath: libraryFileURL.path) else {
            return []
        }
        let data = try Data(contentsOf: libraryFileURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let document = try? decoder.decode(LibraryDocument.self, from: data) {
            return document.games
        }
        return try decoder.decode([Game].self, from: data)
    }

    public func save(_ games: [Game]) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let document = LibraryDocument(
            schemaVersion: Self.currentSchemaVersion,
            games: games
        )
        let data = try encoder.encode(document)
        try FileManager.default.createDirectory(
            at: libraryFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try data.write(to: libraryFileURL, options: .atomic)
    }

    @discardableResult
    public func saveMigrated(_ games: [Game], reason: String) throws -> URL? {
        let backupURL = try createBackup(reason: reason)
        try save(games)
        return backupURL
    }

    private func createBackup(reason: String) throws -> URL? {
        guard FileManager.default.fileExists(atPath: libraryFileURL.path) else {
            return nil
        }

        try FileManager.default.createDirectory(at: backupsDirectoryURL, withIntermediateDirectories: true)
        let timestamp = Self.backupTimestamp()
        let safeReason = Self.safeBackupReason(reason)
        let backupURL = backupsDirectoryURL
            .appendingPathComponent("library-\(timestamp)-\(safeReason).json")
        try FileManager.default.copyItem(at: libraryFileURL, to: backupURL)
        return backupURL
    }

    private static func backupTimestamp(date: Date = Date()) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "")
            .replacingOccurrences(of: "-", with: "")
    }

    private static func safeBackupReason(_ reason: String) -> String {
        let allowed = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "-_"))
        let scalars = reason.unicodeScalars.map { scalar in
            allowed.contains(scalar) ? Character(scalar) : "-"
        }
        let sanitized = String(scalars)
            .split(separator: "-")
            .joined(separator: "-")
        return sanitized.isEmpty ? "migration" : sanitized
    }
}

private struct LibraryDocument: Codable {
    let schemaVersion: Int
    let games: [Game]
}
