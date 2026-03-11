import Foundation

public final class WineManager: ObservableObject, @unchecked Sendable {
    private let baseURL: URL

    public var wineDirectory: URL { baseURL.appendingPathComponent("Wine") }
    public var bottlesDirectory: URL { baseURL.appendingPathComponent("Bottles") }
    private var activeLink: URL { wineDirectory.appendingPathComponent("active") }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: wineDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
    }

    public var isWineInstalled: Bool {
        let wineBinary = activeLink.appendingPathComponent("bin").appendingPathComponent("wine64")
        return FileManager.default.fileExists(atPath: wineBinary.path)
    }

    public var wineBinaryURL: URL? {
        guard isWineInstalled else { return nil }
        return activeLink.appendingPathComponent("bin").appendingPathComponent("wine64")
    }

    public func installedVersions() -> [String] {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: wineDirectory, includingPropertiesForKeys: nil
        ) else { return [] }
        return contents
            .filter { $0.lastPathComponent != "active" }
            .filter { $0.hasDirectoryPath }
            .map { $0.lastPathComponent }
            .sorted()
    }

    public func setActiveVersion(_ versionDir: String) throws {
        let target = wineDirectory.appendingPathComponent(versionDir)
        guard FileManager.default.fileExists(atPath: target.path) else {
            throw WineError.versionNotFound(versionDir)
        }
        try? FileManager.default.removeItem(at: activeLink)
        try FileManager.default.createSymbolicLink(at: activeLink, withDestinationURL: target)
    }

    public func downloadWine(from url: URL, versionName: String) async throws {
        await MainActor.run {
            isDownloading = true
            downloadProgress = 0
        }
        defer {
            Task { @MainActor in
                isDownloading = false
            }
        }

        let destinationDir = wineDirectory.appendingPathComponent(versionName)
        let (tempURL, _) = try await URLSession.shared.download(from: url)

        try FileManager.default.createDirectory(at: destinationDir, withIntermediateDirectories: true)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["xzf", tempURL.path, "-C", destinationDir.path, "--strip-components=1"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WineError.extractionFailed
        }

        try setActiveVersion(versionName)
        try? FileManager.default.removeItem(at: tempURL)

        await MainActor.run {
            downloadProgress = 1.0
        }
    }
}

public enum WineError: Error, LocalizedError {
    case versionNotFound(String)
    case extractionFailed
    case wineNotInstalled

    public var errorDescription: String? {
        switch self {
        case .versionNotFound(let v): return "Wine version '\(v)' not found"
        case .extractionFailed: return "Failed to extract Wine archive"
        case .wineNotInstalled: return "Wine is not installed"
        }
    }
}
