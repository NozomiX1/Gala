import Foundation

public struct RuntimeEnvironmentStatus: Sendable {
    public let isWineInstalled: Bool
    public let isFontInstalled: Bool
    public let isHelperToolInstalled: Bool
    public let hasWineConfiguration: Bool

    public var isReady: Bool {
        isWineInstalled && isFontInstalled && isHelperToolInstalled
    }
}

public final class WineManager: ObservableObject, @unchecked Sendable {
    private let baseURL: URL

    public var wineDirectory: URL { baseURL.appendingPathComponent("Wine") }
    public var bottlesDirectory: URL { baseURL.appendingPathComponent("Bottles") }
    public var fontsDirectory: URL { baseURL.appendingPathComponent("Fonts") }
    public var toolsDirectory: URL { baseURL.appendingPathComponent("Tools") }
    public var cacheDirectory: URL { baseURL.appendingPathComponent("Cache") }
    public var winetricksCacheDirectory: URL { cacheDirectory.appendingPathComponent("winetricks") }
    private var activeLink: URL { wineDirectory.appendingPathComponent("active") }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0
    @Published public var currentDownloadDescription = ""
    @Published public var isDownloadProgressIndeterminate = false

    public init(baseURL: URL) {
        self.baseURL = baseURL
        try? FileManager.default.createDirectory(at: wineDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        try? FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public var isWineInstalled: Bool {
        wineBinaryURL != nil
    }

    public func runtimeEnvironmentStatus() -> RuntimeEnvironmentStatus {
        RuntimeEnvironmentStatus(
            isWineInstalled: isWineInstalled,
            isFontInstalled: isFontInstalled,
            isHelperToolInstalled: isHelperToolInstalled,
            hasWineConfiguration: directoryHasContents(bottlesDirectory)
        )
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

    private func directoryHasContents(_ url: URL) -> Bool {
        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: url, includingPropertiesForKeys: nil
        ) else { return false }
        return contents.contains { !$0.lastPathComponent.hasPrefix(".") }
    }

    public func resetWineConfiguration() throws {
        if FileManager.default.fileExists(atPath: bottlesDirectory.path) {
            try FileManager.default.removeItem(at: bottlesDirectory)
        }
        try FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
    }

    public func resetAllApplicationData() throws {
        if FileManager.default.fileExists(atPath: baseURL.path) {
            try FileManager.default.removeItem(at: baseURL)
        }
        try FileManager.default.createDirectory(at: wineDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bottlesDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fontsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: toolsDirectory, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cacheDirectory, withIntermediateDirectories: true)
    }

    public func repairMissingDependencies() async throws {
        if !isWineInstalled {
            try await downloadWine(from: Self.wineDownloadURL, versionName: Self.wineVersionName)
        }
        if !isFontInstalled {
            try await downloadFont()
        }
        if !isCabextractInstalled {
            try await downloadCabextract()
        }
        if !isWinetricksInstalled {
            try await downloadWinetricks()
        }
    }

    /// Download URL for Wine Staging (hosted in Gala releases for stability)
    public static let wineDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/wine-staging-11.6-osx64.tar.xz")!
    public static let wineVersionName = "wine-staging-11.6"

    /// Download URL for Source Han Sans SC (OFL-licensed CJK font, hosted in Gala releases)
    public static let fontDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/SourceHanSansSC-Regular.otf")!
    public static let bundledFontName = "SourceHanSansSC-Regular.otf"

    /// Download URL for cabextract (needed by winetricks to install Windows components)
    public static let cabextractDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/cabextract")!

    /// Download URL for winetricks (needed to install engine-specific Windows components)
    public static let winetricksDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/winetricks")!

    public var fontFileURL: URL {
        fontsDirectory.appendingPathComponent(Self.bundledFontName)
    }

    public var isFontInstalled: Bool {
        FileManager.default.fileExists(atPath: fontFileURL.path)
    }

    public func downloadFont() async throws {
        guard !isFontInstalled else { return }
        try await downloadFile(from: Self.fontDownloadURL, to: fontFileURL, description: "中文字体")
    }

    public var cabextractURL: URL {
        toolsDirectory.appendingPathComponent("cabextract")
    }

    public var isCabextractInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: cabextractURL.path)
    }

    public var winetricksURL: URL {
        toolsDirectory.appendingPathComponent("winetricks")
    }

    public var isWinetricksInstalled: Bool {
        FileManager.default.isExecutableFile(atPath: winetricksURL.path)
    }

    public var isHelperToolInstalled: Bool {
        isCabextractInstalled && isWinetricksInstalled
    }

    public func downloadCabextract() async throws {
        guard !isCabextractInstalled else { return }
        try await downloadFile(from: Self.cabextractDownloadURL, to: cabextractURL, description: "cabextract")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cabextractURL.path)
    }

    public func downloadWinetricks() async throws {
        guard !isWinetricksInstalled else { return }
        try await downloadFile(from: Self.winetricksDownloadURL, to: winetricksURL, description: "winetricks")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: winetricksURL.path)
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
        let destinationDir = wineDirectory.appendingPathComponent(versionName)
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("tar.xz")

        try await downloadFile(from: url, to: tempURL, description: "Wine 运行时", keepStateActive: true)

        await MainActor.run {
            currentDownloadDescription = "正在解压 Wine 运行时..."
            isDownloadProgressIndeterminate = true
        }

        do {
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
                finishDownloadState()
            }
        } catch {
            await MainActor.run {
                finishDownloadState()
            }
            throw error
        }
    }

    private func downloadFile(
        from url: URL,
        to destination: URL,
        description: String,
        keepStateActive: Bool = false
    ) async throws {
        await MainActor.run {
            isDownloading = true
            currentDownloadDescription = "正在下载 \(description)..."
            downloadProgress = 0
            isDownloadProgressIndeterminate = false
        }

        do {
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await Self.downloadFile(from: url, to: destination) { progress in
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            }
            if !keepStateActive {
                await MainActor.run {
                    downloadProgress = 1.0
                    finishDownloadState()
                }
            }
        } catch {
            await MainActor.run {
                finishDownloadState()
            }
            throw error
        }
    }

    @MainActor
    private func finishDownloadState() {
        isDownloading = false
        currentDownloadDescription = ""
        isDownloadProgressIndeterminate = false
    }

    private static func downloadFile(
        from url: URL,
        to destination: URL,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        let delegate = FileDownloadDelegate(destination: destination, onProgress: onProgress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: .default, delegate: delegate, delegateQueue: queue)
        defer {
            session.finishTasksAndInvalidate()
        }

        try await withCheckedThrowingContinuation { continuation in
            delegate.continuation = continuation
            session.downloadTask(with: url).resume()
        }
    }
}

private final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    fileprivate var continuation: CheckedContinuation<Void, Error>?

    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var didMoveDownload = false
    private var didResume = false

    init(destination: URL, onProgress: @escaping @Sendable (Double) -> Void) {
        self.destination = destination
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(min(1, Double(totalBytesWritten) / Double(totalBytesExpectedToWrite)))
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            didMoveDownload = true
        } catch {
            resume(with: .failure(error))
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let error {
            resume(with: .failure(error))
            return
        }

        guard didMoveDownload else {
            resume(with: .failure(URLError(.cannotCreateFile)))
            return
        }

        resume(with: .success(()))
    }

    private func resume(with result: Result<Void, Error>) {
        guard !didResume else { return }
        didResume = true
        switch result {
        case .success:
            continuation?.resume()
        case .failure(let error):
            continuation?.resume(throwing: error)
        }
        continuation = nil
    }
}

public enum WineError: Error, LocalizedError {
    case versionNotFound(String)
    case extractionFailed
    case wineNotInstalled
    case helperToolNotInstalled(String)
    case helperToolFailed(String, Int32)

    public var errorDescription: String? {
        switch self {
        case .versionNotFound(let v): return "Wine version '\(v)' not found"
        case .extractionFailed: return "Failed to extract Wine archive"
        case .wineNotInstalled: return "Wine is not installed"
        case .helperToolNotInstalled(let name): return "\(name) is not installed"
        case .helperToolFailed(let name, let status): return "\(name) failed with exit code \(status)"
        }
    }
}
