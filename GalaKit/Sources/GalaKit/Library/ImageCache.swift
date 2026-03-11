import Foundation

public final class ImageCache: Sendable {
    private let cacheDirectory: URL

    public init(cacheDirectory: URL) {
        self.cacheDirectory = cacheDirectory
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func save(_ data: Data, forKey key: String) throws {
        let fileURL = fileURL(forKey: key)
        try data.write(to: fileURL, options: .atomic)
    }

    public func load(forKey key: String) -> Data? {
        let fileURL = fileURL(forKey: key)
        return try? Data(contentsOf: fileURL)
    }

    public func path(forKey key: String) -> String? {
        let fileURL = fileURL(forKey: key)
        guard FileManager.default.fileExists(atPath: fileURL.path) else { return nil }
        return fileURL.path
    }

    public func delete(forKey key: String) {
        let fileURL = fileURL(forKey: key)
        try? FileManager.default.removeItem(at: fileURL)
    }

    private func fileURL(forKey key: String) -> URL {
        cacheDirectory.appendingPathComponent(key)
    }
}
