import Foundation

public final class WineManager: ObservableObject, @unchecked Sendable {
    private let baseURL: URL

    public var wineDirectory: URL { baseURL.appendingPathComponent("Wine") }
    public var bottlesDirectory: URL { baseURL.appendingPathComponent("Bottles") }
    public var fontsDirectory: URL { baseURL.appendingPathComponent("Fonts") }
    public var toolsDirectory: URL { baseURL.appendingPathComponent("Tools") }
    private var activeLink: URL { wineDirectory.appendingPathComponent("active") }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: wineDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
    }

    public var isWineInstalled: Bool {
        wineBinaryURL != nil
    }

    public var wineBinaryURL: URL? {
        // Check managed Wine installations (prefer wine over wine64 for better WoW64 support)
        for name in ["wine", "wine64"] {
            let managedBinary = activeLink
                .appendingPathComponent("Contents/Resources/wine/bin/\(name)")
            if FileManager.default.fileExists(atPath: managedBinary.path) {
                return managedBinary
            }
            let flatBinary = activeLink.appendingPathComponent("bin/\(name)")
            if FileManager.default.fileExists(atPath: flatBinary.path) {
                return flatBinary
            }
        }
        // Scan managed Wine directory for any installed version
        if let found = findManagedWineBinary() { return found }
        return nil
    }

    private func findManagedWineBinary() -> URL? {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: wineDirectory, includingPropertiesForKeys: nil
        ) else { return nil }
        for dir in contents where dir.lastPathComponent != "active" {
            for name in ["wine", "wine64"] {
                let appBundle = dir.appendingPathComponent("Contents/Resources/wine/bin/\(name)")
                if FileManager.default.fileExists(atPath: appBundle.path) { return appBundle }
                let flat = dir.appendingPathComponent("bin/\(name)")
                if FileManager.default.fileExists(atPath: flat.path) { return flat }
            }
        }
        return nil
    }

    /// Download URL for Wine Staging (hosted in Gala releases for stability)
    public static let wineDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/wine-staging-11.6-osx64.tar.xz")!
    public static let wineVersionName = "wine-staging-11.6"

    /// Download URL for Source Han Sans SC (OFL-licensed CJK font, hosted in Gala releases)
    public static let fontDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/SourceHanSansSC-Regular.otf")!
    public static let bundledFontName = "SourceHanSansSC-Regular.otf"

    /// Download URL for cabextract (needed by winetricks to install Windows components)
    public static let cabextractDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/cabextract")!

    public var fontFileURL: URL {
        fontsDirectory.appendingPathComponent(Self.bundledFontName)
    }

    public var isFontInstalled: Bool {
        FileManager.default.fileExists(atPath: fontFileURL.path)
    }

    public func downloadFont() async throws {
        guard !isFontInstalled else { return }
        let (tempURL, _) = try await URLSession.shared.download(from: Self.fontDownloadURL)
        try FileManager.default.moveItem(at: tempURL, to: fontFileURL)
    }

    public var cabextractURL: URL {
        toolsDirectory.appendingPathComponent("cabextract")
    }

    public var isCabextractInstalled: Bool {
        FileManager.default.fileExists(atPath: cabextractURL.path)
    }

    public func downloadCabextract() async throws {
        guard !isCabextractInstalled else { return }
        let (tempURL, _) = try await URLSession.shared.download(from: Self.cabextractDownloadURL)
        try FileManager.default.moveItem(at: tempURL, to: cabextractURL)
        // Make executable
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cabextractURL.path)
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
        process.arguments = ["xf", tempURL.path, "-C", destinationDir.path, "--strip-components=1"]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            // Clean up failed extraction directory so retries can work
            try? FileManager.default.removeItem(at: destinationDir)
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
