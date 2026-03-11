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
        wineBinaryURL != nil
    }

    public var wineBinaryURL: URL? {
        // 1. Check our managed active symlink
        let managedBinary = activeLink.appendingPathComponent("bin").appendingPathComponent("wine64")
        if FileManager.default.fileExists(atPath: managedBinary.path) {
            return managedBinary
        }
        // 2. Check Homebrew GPTK installation
        for path in Self.homebrewWinePaths {
            if FileManager.default.fileExists(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }

    /// Common Homebrew Wine/GPTK binary paths
    private static let homebrewWinePaths = [
        "/opt/homebrew/bin/wine64",
        "/opt/homebrew/opt/game-porting-toolkit/bin/wine64",
        "/usr/local/bin/wine64",
        "/usr/local/opt/game-porting-toolkit/bin/wine64",
    ]

    /// Link an externally installed Wine binary (e.g. from Homebrew or user-provided path)
    public func linkExternalWine(at binaryPath: URL) throws {
        let binDir = binaryPath.deletingLastPathComponent()
        let wineRoot = binDir.deletingLastPathComponent() // go up from bin/
        let versionName = "external-\(wineRoot.lastPathComponent)"
        let symlinkTarget = wineDirectory.appendingPathComponent(versionName)

        // Create symlink to external Wine installation
        try? FileManager.default.removeItem(at: symlinkTarget)
        try FileManager.default.createSymbolicLink(at: symlinkTarget, withDestinationURL: wineRoot)
        try setActiveVersion(versionName)
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
