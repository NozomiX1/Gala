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
    public var logsDirectory: URL { baseURL.appendingPathComponent("Logs") }
    /// Where users put their own profile files.
    public var profilesDirectory: URL { baseURL.appendingPathComponent("Profiles") }
    private var activeLink: URL { wineDirectory.appendingPathComponent("active") }
    private var managedDirectories: [URL] {
        [wineDirectory, bottlesDirectory, fontsDirectory, toolsDirectory, cacheDirectory, mediaOverlaysDirectory, profilesDirectory]
    }

    @Published public var isDownloading = false
    @Published public var downloadProgress: Double = 0
    @Published public var currentDownloadDescription = ""
    @Published public var isDownloadProgressIndeterminate = false

    public init(baseURL: URL) {
        self.baseURL = baseURL
        for directory in managedDirectories {
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        reloadProfiles()
    }

    /// Bundled profiles plus the user's, and what was wrong with any user file that had to be left out.
    public private(set) var profiles = ProfileStore.bundled
    public private(set) var profileProblems: [ProfileError] = []

    public func reloadProfiles() {
        (profiles, profileProblems) = ProfileStore.loading(userDirectory: profilesDirectory)
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
        // The active version first, then any other installed version.
        wineBinary(in: activeLink) ?? findManagedWineBinary()
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
        // Prefer wine over wine64 for better WoW64 support.
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
        for directory in managedDirectories {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        }
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

    /// Official mirror for Gala release assets, tried before GitHub Releases for faster domestic downloads.
    public static let mirrorBaseURL = URL(string: "https://gala.feng7.cn")!
    private static let githubReleasePathPrefix = "/NozomiX1/Gala/releases/download/"

    /// Returns the mirror URL first when the asset belongs to Gala's GitHub releases, followed by the canonical URL.
    public static func downloadCandidates(for canonicalURL: URL) -> [URL] {
        guard canonicalURL.host?.lowercased() == "github.com",
              canonicalURL.path.hasPrefix(githubReleasePathPrefix) else {
            return [canonicalURL]
        }
        let relativePath = String(canonicalURL.path.dropFirst(githubReleasePathPrefix.count))
        guard !relativePath.isEmpty,
              let mirrorURL = URL(string: relativePath, relativeTo: mirrorBaseURL)?.absoluteURL else {
            return [canonicalURL]
        }
        return [mirrorURL, canonicalURL]
    }

    /// Download URL for Wine Staging (hosted in Gala releases for stability)
    public static let wineDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/wine-staging-11.6-osx64.tar.xz")!
    public static let wineSHA256 = "054113ce6d9322ccb2444df2a89abad3c7a8fee12b836ae0f400e00e6398eb70"
    public static let wineVersionName = "wine-staging-11.6"
    public static let dxmtWineVersionName = "wine-staging-11.6-dxmt-v0.80"

    /// Download URL for Source Han Sans SC (OFL-licensed CJK font, hosted in Gala releases)
    public static let fontDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/SourceHanSansSC-Regular.otf")!
    public static let fontSHA256 = "f1d8611151880c6c336aabeac4640ef434fa13cbfbf1ffe82d0a71b2a5637256"
    public static let bundledFontName = "SourceHanSansSC-Regular.otf"

    /// Download URL for cabextract (needed by winetricks to install Windows components)
    public static let cabextractDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/cabextract")!
    public static let cabextractSHA256 = "ace8ade5fe5ee05c6e2c472df813bd4466917ea44f110d295c144498f0830996"

    /// Download URL for winetricks (needed to install engine-specific Windows components)
    public static let winetricksDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v1/winetricks")!
    public static let winetricksSHA256 = "431f82fc74000e6c864409f1d8fb495d696c03928808e3e8acffc45179312a7b"

    /// Download URL for DXMT v0.80 builtin (hosted in Gala releases for stability)
    public static let dxmtDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v2/dxmt-v0.80-builtin.tar.gz")!
    public static let dxmtArchiveName = "dxmt-v0.80-builtin.tar.gz"
    public static let dxmtSHA256 = "8f260e36b5739e68f3bad613381441385c4dc7b85b78ba8de653d5a6a264529d"

    /// Download URL for the Gala Media Foundation runtime bundle.
    public static let mediaFoundationRuntimeDownloadURL = URL(string: "https://github.com/NozomiX1/Gala/releases/download/deps-v3/gala-mf-runtime-1.1-macos.tar.gz")!
    public static let mediaFoundationRuntimeVersionName = "gala-mf-runtime-1.1"
    public static let mediaFoundationRuntimeArchiveName = "gala-mf-runtime-1.1-macos.tar.gz"
    public static let mediaFoundationRuntimeSHA256 = "021f43bea3871e00e8a1bb0eec3e4a112bcc19fc4a3960e5e50df42f5ff94df9"

    public var fontFileURL: URL {
        fontsDirectory.appendingPathComponent(Self.bundledFontName)
    }

    public var isFontInstalled: Bool {
        FileManager.default.fileExists(atPath: fontFileURL.path)
    }

    public func downloadFont() async throws {
        guard !isFontInstalled else { return }
        try await downloadFile(from: Self.fontDownloadURL, to: fontFileURL, expectedSHA256: Self.fontSHA256, description: "中文字体")
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
        wineBinary(in: dxmtWineDirectory)
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
        guard let components = profiles.recipe(for: game)?.preset.managedComponents,
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

    /// The profile decides, unless the game's graphics switch says otherwise.
    public func usesDXMTWine(for game: Game) -> Bool {
        game.forcesDXMTWine ?? (profiles.recipe(for: game)?.usesDXMTWine == true)
    }

    public func wineBinaryURL(for game: Game) -> URL? {
        usesDXMTWine(for: game) ? dxmtWineBinaryURL : wineBinaryURL
    }

    public func downloadCabextract() async throws {
        guard !isCabextractInstalled else { return }
        try await downloadFile(from: Self.cabextractDownloadURL, to: cabextractURL, expectedSHA256: Self.cabextractSHA256, description: "cabextract")
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: cabextractURL.path)
    }

    public func downloadWinetricks() async throws {
        guard !isWinetricksInstalled else { return }
        try await downloadFile(from: Self.winetricksDownloadURL, to: winetricksURL, expectedSHA256: Self.winetricksSHA256, description: "winetricks")
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

        try await downloadVerifiedArchive(
            from: Self.dxmtDownloadURL,
            to: dxmtArchiveURL,
            sha256: Self.dxmtSHA256,
            description: "正在下载 DXMT...",
            progressHandler: progressHandler
        )

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

        try await downloadVerifiedArchive(
            from: Self.mediaFoundationRuntimeDownloadURL,
            to: mediaFoundationRuntimeArchiveURL,
            sha256: Self.mediaFoundationRuntimeSHA256,
            description: "正在下载 Media Foundation 媒体运行时...",
            progressHandler: progressHandler
        )

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

    /// Reuses a cached archive when its checksum matches, otherwise downloads and verifies it.
    private func downloadVerifiedArchive(
        from url: URL,
        to archiveURL: URL,
        sha256: String,
        description: String,
        progressHandler: (@Sendable (Double?) -> Void)?
    ) async throws {
        if FileManager.default.fileExists(atPath: archiveURL.path) {
            if (try? Self.verifySHA256(fileURL: archiveURL, expected: sha256)) != nil { return }
            try? FileManager.default.removeItem(at: archiveURL)
        }

        await MainActor.run {
            isDownloading = true
            currentDownloadDescription = description
            downloadProgress = 0
            isDownloadProgressIndeterminate = false
        }

        do {
            try FileManager.default.createDirectory(
                at: archiveURL.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try await Self.downloadWithFallback(
                candidates: Self.downloadCandidates(for: url),
                to: archiveURL,
                expectedSHA256: sha256
            ) { progress in
                progressHandler?(progress)
                Task { @MainActor in
                    self.downloadProgress = progress
                }
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

    static func sha256Hex(of fileURL: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer { try? handle.close() }
        var hasher = SHA256()
        while true {
            let chunk = try handle.read(upToCount: 1024 * 1024) ?? Data()
            if chunk.isEmpty { break }
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func verifySHA256(fileURL: URL, expected: String, displayName: String? = nil) throws {
        let actual = try sha256Hex(of: fileURL)
        guard actual == expected else {
            throw WineError.checksumMismatch(displayName ?? fileURL.lastPathComponent)
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

        let expectedSHA256 = url == Self.wineDownloadURL ? Self.wineSHA256 : nil
        try await downloadFile(
            from: url,
            to: tempURL,
            expectedSHA256: expectedSHA256,
            description: "Wine 运行时",
            keepStateActive: true
        )

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
        expectedSHA256: String? = nil,
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
            try await Self.downloadWithFallback(
                candidates: Self.downloadCandidates(for: url),
                to: destination,
                expectedSHA256: expectedSHA256
            ) { progress in
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

    private static func defaultDownloadSessionConfiguration() -> URLSessionConfiguration {
        let config = URLSessionConfiguration.ephemeral
        // Fail fast when a mirror stalls so we can resume or fall back to GitHub Releases.
        config.timeoutIntervalForRequest = 30
        config.timeoutIntervalForResource = 1800
        config.waitsForConnectivity = false
        return config
    }

    /// Downloads from each candidate URL in order (retrying transient resets and resuming mid-transfer drops) and verifies SHA256 before moving into place.
    static func downloadWithFallback(
        candidates: [URL],
        to destination: URL,
        expectedSHA256: String? = nil,
        configuration: URLSessionConfiguration? = nil,
        maxResumeAttempts: Int = 2,
        resumeDelayNanoseconds: UInt64 = 1_000_000_000,
        transientRetryDelaysNanoseconds: [UInt64] = [1_000_000_000, 3_000_000_000],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        precondition(!candidates.isEmpty, "downloadWithFallback requires at least one URL")
        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        var lastError: Error = URLError(.unknown)
        for (index, candidate) in candidates.enumerated() {
            if index > 0 {
                onProgress(0)
            }
            let stagedURL = destination.deletingLastPathComponent()
                .appendingPathComponent(".gala-download-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: stagedURL) }

            do {
                try await downloadSingleCandidate(
                    from: candidate,
                    to: stagedURL,
                    configuration: configuration ?? defaultDownloadSessionConfiguration(),
                    maxResumeAttempts: maxResumeAttempts,
                    resumeDelayNanoseconds: resumeDelayNanoseconds,
                    transientRetryDelaysNanoseconds: transientRetryDelaysNanoseconds,
                    onProgress: onProgress
                )
                if let expectedSHA256 {
                    try verifySHA256(fileURL: stagedURL, expected: expectedSHA256, displayName: destination.lastPathComponent)
                }
                try? FileManager.default.removeItem(at: destination)
                try FileManager.default.moveItem(at: stagedURL, to: destination)
                return
            } catch {
                lastError = error
            }
        }
        throw lastError
    }

    static func shouldRetryTransientConnectionError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .networkConnectionLost, .secureConnectionFailed, .cannotConnectToHost, .cannotLoadFromNetwork:
            return true
        default:
            return false
        }
    }

    private static func downloadSingleCandidate(
        from url: URL,
        to destination: URL,
        configuration: URLSessionConfiguration,
        maxResumeAttempts: Int,
        resumeDelayNanoseconds: UInt64,
        transientRetryDelaysNanoseconds: [UInt64],
        onProgress: @escaping @Sendable (Double) -> Void
    ) async throws {
        var resumeData: Data?
        var resumeAttempt = 0
        var transientRetryAttempt = 0

        while true {
            let outcome = await performDownloadAttempt(
                url: url,
                resumeData: resumeData,
                destination: destination,
                configuration: configuration,
                onProgress: onProgress
            )
            switch outcome {
            case .success:
                return
            case .failure(let error, let nextResumeData):
                if let nextResumeData, resumeAttempt < maxResumeAttempts {
                    resumeAttempt += 1
                    resumeData = nextResumeData
                    if resumeDelayNanoseconds > 0 {
                        try? await Task.sleep(nanoseconds: resumeDelayNanoseconds)
                    }
                    continue
                }
                if nextResumeData == nil,
                   transientRetryAttempt < transientRetryDelaysNanoseconds.count,
                   shouldRetryTransientConnectionError(error) {
                    let delay = transientRetryDelaysNanoseconds[transientRetryAttempt]
                    transientRetryAttempt += 1
                    resumeData = nil
                    if delay > 0 {
                        try? await Task.sleep(nanoseconds: delay)
                    }
                    continue
                }
                throw error
            }
        }
    }

    fileprivate enum DownloadAttemptOutcome {
        case success
        case failure(Error, resumeData: Data?)
    }

    private static func performDownloadAttempt(
        url: URL,
        resumeData: Data?,
        destination: URL,
        configuration: URLSessionConfiguration,
        onProgress: @escaping @Sendable (Double) -> Void
    ) async -> DownloadAttemptOutcome {
        let delegate = FileDownloadDelegate(destination: destination, onProgress: onProgress)
        let queue = OperationQueue()
        queue.maxConcurrentOperationCount = 1
        let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: queue)
        defer {
            session.finishTasksAndInvalidate()
        }

        return await withCheckedContinuation { continuation in
            delegate.continuation = continuation
            let task = resumeData.map { session.downloadTask(withResumeData: $0) } ?? session.downloadTask(with: url)
            task.resume()
        }
    }
}

private final class FileDownloadDelegate: NSObject, URLSessionDownloadDelegate, @unchecked Sendable {
    fileprivate var continuation: CheckedContinuation<WineManager.DownloadAttemptOutcome, Never>?

    private let destination: URL
    private let onProgress: @Sendable (Double) -> Void
    private var didMoveDownload = false
    private var didResume = false
    private var failureError: Error?

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
        if let http = downloadTask.response as? HTTPURLResponse, !(200..<300).contains(http.statusCode) {
            failureError = WineError.httpStatus(http.statusCode)
            return
        }
        do {
            try? FileManager.default.removeItem(at: destination)
            try FileManager.default.moveItem(at: location, to: destination)
            didMoveDownload = true
        } catch {
            failureError = error
        }
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        didCompleteWithError error: Error?
    ) {
        if let failureError {
            resume(with: .failure(failureError, resumeData: nil))
            return
        }
        if let error {
            let resumeData = (error as NSError).userInfo[NSURLSessionDownloadTaskResumeData] as? Data
            resume(with: .failure(error, resumeData: resumeData))
            return
        }

        guard didMoveDownload else {
            resume(with: .failure(URLError(.cannotCreateFile), resumeData: nil))
            return
        }

        resume(with: .success)
    }

    private func resume(with outcome: WineManager.DownloadAttemptOutcome) {
        guard !didResume else { return }
        didResume = true
        continuation?.resume(returning: outcome)
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
    case httpStatus(Int)

    public var errorDescription: String? {
        switch self {
        case .versionNotFound(let v): return "Wine version '\(v)' not found"
        case .extractionFailed: return "Failed to extract Wine archive"
        case .wineNotInstalled: return "Wine is not installed"
        case .helperToolNotInstalled(let name): return "\(name) is not installed"
        case .helperToolFailed(let name, let status): return "\(name) failed with exit code \(status)"
        case .checksumMismatch(let name): return "\(name) checksum mismatch"
        case .httpStatus(let code): return "Server returned HTTP \(code)"
        }
    }
}
