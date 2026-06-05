import CryptoKit
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
    public var dxmtCacheDirectory: URL { cacheDirectory.appendingPathComponent("dxmt") }
    public var mediaFoundationCacheDirectory: URL { cacheDirectory.appendingPathComponent("media-foundation") }
    public var mediaOverlaysDirectory: URL { baseURL.appendingPathComponent("MediaOverlays") }
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
        try? FileManager.default.createDirectory(at: mediaOverlaysDirectory, withIntermediateDirectories: true)
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
        let preferred = wineDirectory.appendingPathComponent(Self.wineVersionName)
        if let found = wineBinary(in: preferred) { return found }

        guard let contents = try? FileManager.default.contentsOfDirectory(
            at: wineDirectory, includingPropertiesForKeys: nil
        ) else { return nil }
        for dir in contents where dir.lastPathComponent != "active" &&
            dir.lastPathComponent != Self.dxmtWineVersionName {
            if let found = wineBinary(in: dir) { return found }
        }
        return nil
    }

    private func wineBinary(in directory: URL) -> URL? {
        for name in ["wine", "wine64"] {
            let appBundle = directory.appendingPathComponent("Contents/Resources/wine/bin/\(name)")
            if FileManager.default.fileExists(atPath: appBundle.path) { return appBundle }
            let flat = directory.appendingPathComponent("bin/\(name)")
            if FileManager.default.fileExists(atPath: flat.path) { return flat }
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
        try FileManager.default.createDirectory(at: mediaOverlaysDirectory, withIntermediateDirectories: true)
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
    public static let dxmtWineVersionName = "wine-staging-11.6-dxmt-v0.80"

    /// Download URL for Source Han Sans SC (OFL-licensed CJK font, hosted in Gala releases)
    public static let fontDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/SourceHanSansSC-Regular.otf")!
    public static let bundledFontName = "SourceHanSansSC-Regular.otf"

    /// Download URL for cabextract (needed by winetricks to install Windows components)
    public static let cabextractDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/cabextract")!

    /// Download URL for winetricks (needed to install engine-specific Windows components)
    public static let winetricksDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/winetricks")!

    /// Download URL for DXMT v0.80 builtin (hosted in Gala releases for stability)
    public static let dxmtDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v2/dxmt-v0.80-builtin.tar.gz")!
    public static let dxmtArchiveName = "dxmt-v0.80-builtin.tar.gz"
    public static let dxmtSHA256 = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

    /// Download URL for the Gala Media Foundation runtime bundle.
    public static let mediaFoundationRuntimeDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v3/gala-mf-runtime-1.0-macos.tar.gz")!
    public static let mediaFoundationRuntimeVersionName = "gala-mf-runtime-1.0"
    public static let mediaFoundationRuntimeArchiveName = "gala-mf-runtime-1.0-macos.tar.gz"
    public static let mediaFoundationRuntimeSHA256: String? = "66596147ba88f694ae2280e780c501f991e0e83a0c08253e39cbea43f8b14da5"

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

    public var dxmtArchiveURL: URL {
        dxmtCacheDirectory
            .appendingPathComponent("v0.80")
            .appendingPathComponent(Self.dxmtArchiveName)
    }

    public var dxmtWineDirectory: URL {
        wineDirectory.appendingPathComponent(Self.dxmtWineVersionName)
    }

    public var dxmtWineBinaryURL: URL? {
        for name in ["wine", "wine64"] {
            let appBundle = dxmtWineDirectory
                .appendingPathComponent("Contents/Resources/wine/bin/\(name)")
            if FileManager.default.fileExists(atPath: appBundle.path) {
                return appBundle
            }
            let flat = dxmtWineDirectory.appendingPathComponent("bin/\(name)")
            if FileManager.default.fileExists(atPath: flat.path) {
                return flat
            }
        }
        return nil
    }

    public var mediaFoundationRuntimeArchiveURL: URL {
        mediaFoundationCacheDirectory
            .appendingPathComponent(Self.mediaFoundationRuntimeVersionName)
            .appendingPathComponent(Self.mediaFoundationRuntimeArchiveName)
    }

    public var mediaFoundationRuntimeDirectory: URL {
        toolsDirectory
            .appendingPathComponent("MediaFoundation")
            .appendingPathComponent(Self.mediaFoundationRuntimeVersionName)
    }

    public var mediaFoundationFFmpegURL: URL {
        mediaFoundationRuntimeDirectory.appendingPathComponent("bin/ffmpeg")
    }

    public var mediaFoundationGStreamerRegistryURL: URL {
        mediaFoundationCacheDirectory
            .appendingPathComponent(Self.mediaFoundationRuntimeVersionName)
            .appendingPathComponent("gst-registry.bin")
    }

    public var mediaFoundationRuntime: MediaFoundationRuntime? {
        guard isMediaFoundationRuntimeInstalled else { return nil }
        return MediaFoundationRuntime(
            rootURL: mediaFoundationRuntimeDirectory,
            gStreamerRegistryURL: mediaFoundationGStreamerRegistryURL
        )
    }

    public var isMediaFoundationRuntimeInstalled: Bool {
        let libDir = mediaFoundationRuntimeDirectory.appendingPathComponent("lib")
        return FileManager.default.isExecutableFile(atPath: mediaFoundationFFmpegURL.path) &&
            FileManager.default.fileExists(atPath: libDir.path)
    }

    public func isManagedRuntimeReady(for game: Game) -> Bool {
        guard let components = game.engine?.preset.managedComponents,
              !components.isEmpty else {
            return true
        }

        for component in components {
            switch component {
            case .dxmt:
                if wineBinaryURL(for: game) == nil { return false }
            case .mediaFoundation:
                if !isMediaFoundationRuntimeInstalled { return false }
            }
        }
        return true
    }

    public func wineBinaryURL(for game: Game) -> URL? {
        guard game.engine?.usesDXMTWineVariant == true else {
            return wineBinaryURL
        }
        return dxmtWineBinaryURL
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

    public func ensureDXMTWineVariant(
        progressHandler: (@Sendable (Double?) -> Void)? = nil
    ) async throws {
        if dxmtWineBinaryURL != nil { return }

        guard FileManager.default.fileExists(
            atPath: wineDirectory.appendingPathComponent(Self.wineVersionName).path
        ) else {
            throw WineError.wineNotInstalled
        }

        try await downloadDXMT(progressHandler: progressHandler)

        let destinationDir = dxmtWineDirectory
        let sourceDir = wineDirectory.appendingPathComponent(Self.wineVersionName)
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gala-dxmt-\(UUID().uuidString)")

        do {
            try? FileManager.default.removeItem(at: destinationDir)
            try cloneDirectory(from: sourceDir, to: destinationDir)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try extractArchive(dxmtArchiveURL, to: extractDir)
            try installDXMTOverlay(from: extractDir.appendingPathComponent("v0.80"), to: destinationDir)
            try? FileManager.default.removeItem(at: extractDir)
        } catch {
            try? FileManager.default.removeItem(at: extractDir)
            try? FileManager.default.removeItem(at: destinationDir)
            throw error
        }
    }

    public func ensureMediaFoundationRuntime(
        progressHandler: (@Sendable (Double?) -> Void)? = nil
    ) async throws {
        if isMediaFoundationRuntimeInstalled { return }

        try await downloadMediaFoundationRuntime(progressHandler: progressHandler)

        let destinationDir = mediaFoundationRuntimeDirectory
        let extractDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("gala-mf-runtime-\(UUID().uuidString)")

        do {
            try? FileManager.default.removeItem(at: destinationDir)
            try FileManager.default.createDirectory(at: extractDir, withIntermediateDirectories: true)
            try extractArchive(mediaFoundationRuntimeArchiveURL, to: extractDir)

            let extractedRoot = try extractedMediaFoundationRuntimeRoot(in: extractDir)
            try FileManager.default.createDirectory(
                at: destinationDir.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try FileManager.default.moveItem(at: extractedRoot, to: destinationDir)
            try FileManager.default.setAttributes(
                [.posixPermissions: 0o755],
                ofItemAtPath: mediaFoundationFFmpegURL.path
            )
            try? FileManager.default.removeItem(at: extractDir)
        } catch {
            try? FileManager.default.removeItem(at: extractDir)
            try? FileManager.default.removeItem(at: destinationDir)
            throw error
        }
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

    private func downloadDXMT(progressHandler: (@Sendable (Double?) -> Void)? = nil) async throws {
        var shouldDownload = !FileManager.default.fileExists(atPath: dxmtArchiveURL.path)
        if !shouldDownload {
            do {
                try verifySHA256(fileURL: dxmtArchiveURL, expected: Self.dxmtSHA256)
            } catch {
                try? FileManager.default.removeItem(at: dxmtArchiveURL)
                shouldDownload = true
            }
        }

        if shouldDownload {
            await MainActor.run {
                isDownloading = true
                currentDownloadDescription = "正在下载 DXMT..."
                downloadProgress = 0
                isDownloadProgressIndeterminate = false
            }
            do {
                try FileManager.default.createDirectory(
                    at: dxmtArchiveURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try await Self.downloadFile(from: Self.dxmtDownloadURL, to: dxmtArchiveURL) { progress in
                    progressHandler?(progress)
                    Task { @MainActor in
                        self.downloadProgress = progress
                    }
                }
                try verifySHA256(fileURL: dxmtArchiveURL, expected: Self.dxmtSHA256)
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
    }

    private func downloadMediaFoundationRuntime(
        progressHandler: (@Sendable (Double?) -> Void)? = nil
    ) async throws {
        var shouldDownload = !FileManager.default.fileExists(atPath: mediaFoundationRuntimeArchiveURL.path)
        if let expectedSHA = Self.mediaFoundationRuntimeSHA256, !shouldDownload {
            do {
                try verifySHA256(fileURL: mediaFoundationRuntimeArchiveURL, expected: expectedSHA)
            } catch {
                try? FileManager.default.removeItem(at: mediaFoundationRuntimeArchiveURL)
                shouldDownload = true
            }
        }

        guard shouldDownload else { return }

        await MainActor.run {
            isDownloading = true
            currentDownloadDescription = "正在下载 Media Foundation 媒体运行时..."
            downloadProgress = 0
            isDownloadProgressIndeterminate = false
        }

        do {
            try FileManager.default.createDirectory(
                at: mediaFoundationRuntimeArchiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await Self.downloadFile(
                from: Self.mediaFoundationRuntimeDownloadURL,
                to: mediaFoundationRuntimeArchiveURL
            ) { progress in
                progressHandler?(progress)
                Task { @MainActor in
                    self.downloadProgress = progress
                }
            }
            if let expectedSHA = Self.mediaFoundationRuntimeSHA256 {
                try verifySHA256(fileURL: mediaFoundationRuntimeArchiveURL, expected: expectedSHA)
            }
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

    private func extractedMediaFoundationRuntimeRoot(in extractDir: URL) throws -> URL {
        let preferred = extractDir.appendingPathComponent(Self.mediaFoundationRuntimeVersionName)
        if FileManager.default.fileExists(atPath: preferred.path) {
            return preferred
        }

        let contents = try FileManager.default.contentsOfDirectory(
            at: extractDir,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        if contents.count == 1,
           (try contents[0].resourceValues(forKeys: [.isDirectoryKey])).isDirectory == true {
            return contents[0]
        }

        let stagedRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("gala-mf-runtime-root-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: stagedRoot, withIntermediateDirectories: true)
        for item in contents {
            try FileManager.default.moveItem(
                at: item,
                to: stagedRoot.appendingPathComponent(item.lastPathComponent)
            )
        }
        return stagedRoot
    }

    private func cloneDirectory(from source: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/cp")
        process.arguments = ["-R", "-c", source.path, destination.path]
        try process.run()
        process.waitUntilExit()

        if process.terminationStatus != 0 {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.copyItem(at: source, to: destination)
        }
    }

    private func extractArchive(_ archive: URL, to destination: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/tar")
        process.arguments = ["-xzf", archive.path, "-C", destination.path]
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            throw WineError.extractionFailed
        }
    }

    private func installDXMTOverlay(from dxmtRoot: URL, to wineRoot: URL) throws {
        let wineLib = wineRoot.appendingPathComponent("Contents/Resources/wine/lib/wine")
        let overlayDirectories = ["x86_64-windows", "i386-windows", "x86_64-unix"]

        for directoryName in overlayDirectories {
            let sourceDir = dxmtRoot.appendingPathComponent(directoryName)
            let targetDir = wineLib.appendingPathComponent(directoryName)
            guard let files = try? FileManager.default.contentsOfDirectory(
                at: sourceDir,
                includingPropertiesForKeys: nil
            ) else { continue }

            try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
            for sourceFile in files {
                let targetFile = targetDir.appendingPathComponent(sourceFile.lastPathComponent)
                try? FileManager.default.removeItem(at: targetFile)
                try FileManager.default.copyItem(at: sourceFile, to: targetFile)
            }
        }
    }

    private func verifySHA256(fileURL: URL, expected: String) throws {
        let data = try Data(contentsOf: fileURL)
        let digest = SHA256.hash(data: data)
        let actual = digest.map { String(format: "%02x", $0) }.joined()
        guard actual == expected else {
            throw WineError.checksumMismatch(fileURL.lastPathComponent)
        }
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
    case checksumMismatch(String)

    public var errorDescription: String? {
        switch self {
        case .versionNotFound(let v): return "Wine version '\(v)' not found"
        case .extractionFailed: return "Failed to extract Wine archive"
        case .wineNotInstalled: return "Wine is not installed"
        case .helperToolNotInstalled(let name): return "\(name) is not installed"
        case .helperToolFailed(let name, let status): return "\(name) failed with exit code \(status)"
        case .checksumMismatch(let name): return "\(name) checksum mismatch"
        }
    }
}
