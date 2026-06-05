import Foundation

public struct MediaCompatibilityProgress: Equatable, Sendable {
    public let message: String
    public let completedUnitCount: Int
    public let totalUnitCount: Int

    public var fraction: Double? {
        guard totalUnitCount > 0 else { return nil }
        return Double(completedUnitCount) / Double(totalUnitCount)
    }
}

public final class MediaCompatibilityManager: @unchecked Sendable {
    private let overlaysDirectory: URL
    private let ffmpegURL: URL

    public init(overlaysDirectory: URL, ffmpegURL: URL) {
        self.overlaysDirectory = overlaysDirectory
        self.ffmpegURL = ffmpegURL
    }

    public func prepareLaunchGame(
        for game: Game,
        progressHandler: (@Sendable (MediaCompatibilityProgress) -> Void)? = nil
    ) async throws -> Game {
        guard game.engine == .artemisMFD3D11 else { return game }

        let sourceExecutable = URL(fileURLWithPath: game.executablePath)
        let sourceRoot = sourceExecutable.deletingLastPathComponent()
        let sourceMovieRoot = sourceRoot.appendingPathComponent("movie")
        guard FileManager.default.fileExists(atPath: sourceMovieRoot.path) else {
            return game
        }

        guard FileManager.default.isExecutableFile(atPath: ffmpegURL.path) else {
            throw MediaCompatibilityError.ffmpegMissing(ffmpegURL.path)
        }

        let overlayRoot = overlaysDirectory.appendingPathComponent(game.id.uuidString)
        try FileManager.default.createDirectory(at: overlayRoot, withIntermediateDirectories: true)
        try syncRootEntries(from: sourceRoot, to: overlayRoot)

        let manifest = try buildManifest(sourceRoot: sourceRoot, sourceMovieRoot: sourceMovieRoot)
        let manifestURL = overlayRoot.appendingPathComponent(Self.manifestFileName)
        if try isCurrentManifest(manifest, manifestURL: manifestURL, overlayRoot: overlayRoot) {
            return launchGame(game, sourceExecutable: sourceExecutable, overlayRoot: overlayRoot)
        }

        let oldManifest = try loadManifest(at: manifestURL)
        try removeGeneratedMovieFiles(from: oldManifest, overlayRoot: overlayRoot)
        try prepareMovieFiles(
            manifest.movies,
            sourceMovieRoot: sourceMovieRoot,
            overlayMovieRoot: overlayRoot.appendingPathComponent("movie"),
            progressHandler: progressHandler
        )
        try writeManifest(manifest, to: manifestURL)

        return launchGame(game, sourceExecutable: sourceExecutable, overlayRoot: overlayRoot)
    }

    private func launchGame(_ game: Game, sourceExecutable: URL, overlayRoot: URL) -> Game {
        var launchGame = game
        launchGame.executablePath = overlayRoot
            .appendingPathComponent(sourceExecutable.lastPathComponent)
            .path
        return launchGame
    }

    private func syncRootEntries(from sourceRoot: URL, to overlayRoot: URL) throws {
        let entries = try FileManager.default.contentsOfDirectory(
            at: sourceRoot,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )
        var currentNames = Set(entries.map(\.lastPathComponent))
        currentNames.insert("movie")
        currentNames.insert(Self.manifestFileName)
        try removeStaleRootSymlinks(from: overlayRoot, currentNames: currentNames)

        for entry in entries where entry.lastPathComponent.lowercased() != "movie" {
            let destination = overlayRoot.appendingPathComponent(entry.lastPathComponent)
            try replaceWithSymbolicLink(at: destination, to: entry, allowReplacingRegularItem: false)
        }
    }

    private func removeStaleRootSymlinks(from overlayRoot: URL, currentNames: Set<String>) throws {
        let overlayEntries = try FileManager.default.contentsOfDirectory(
            at: overlayRoot,
            includingPropertiesForKeys: [.isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        )

        for entry in overlayEntries
            where !currentNames.contains(entry.lastPathComponent) && Self.isSymbolicLink(entry) {
            try? FileManager.default.removeItem(at: entry)
        }
    }

    private func buildManifest(sourceRoot: URL, sourceMovieRoot: URL) throws -> MediaOverlayManifest {
        let movieFiles = try collectMovieFiles(in: sourceMovieRoot, relativeTo: sourceMovieRoot)
        return MediaOverlayManifest(
            version: 1,
            runtimeVersion: WineManager.mediaFoundationRuntimeVersionName,
            sourceRootPath: sourceRoot.path,
            movies: movieFiles
        )
    }

    private func collectMovieFiles(in directory: URL, relativeTo root: URL) throws -> [MediaOverlayMovie] {
        let entries = try FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: [.isDirectoryKey],
            options: [.skipsHiddenFiles]
        )

        var movies: [MediaOverlayMovie] = []
        for entry in entries {
            let values = try entry.resourceValues(forKeys: [.isDirectoryKey])
            if values.isDirectory == true {
                movies += try collectMovieFiles(in: entry, relativeTo: root)
                continue
            }

            let relativePath = Self.relativePath(from: entry, to: root)
            let signature = try fileSignature(for: entry)
            let action: MediaOverlayMovie.Action = entry.pathExtension.lowercased() == "wmv"
                ? .transcodeAudioToPCM
                : .symbolicLink
            movies.append(MediaOverlayMovie(
                relativePath: relativePath,
                byteCount: signature.byteCount,
                modifiedAt: signature.modifiedAt,
                action: action
            ))
        }

        return movies.sorted { $0.relativePath < $1.relativePath }
    }

    private func prepareMovieFiles(
        _ movies: [MediaOverlayMovie],
        sourceMovieRoot: URL,
        overlayMovieRoot: URL,
        progressHandler: (@Sendable (MediaCompatibilityProgress) -> Void)?
    ) throws {
        for (index, movie) in movies.enumerated() {
            let source = sourceMovieRoot.appendingPathComponent(movie.relativePath)
            let destination = overlayMovieRoot.appendingPathComponent(movie.relativePath)
            try FileManager.default.createDirectory(
                at: destination.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )

            progressHandler?(
                MediaCompatibilityProgress(
                    message: "正在准备视频 \(movie.relativePath)...",
                    completedUnitCount: index,
                    totalUnitCount: movies.count
                )
            )

            switch movie.action {
            case .transcodeAudioToPCM:
                try transcodeWMVAudioToPCM(from: source, to: destination, relativePath: movie.relativePath)
            case .symbolicLink:
                try replaceWithSymbolicLink(
                    at: destination,
                    to: source,
                    allowReplacingRegularItem: true
                )
            }
        }

        progressHandler?(
            MediaCompatibilityProgress(
                message: "媒体兼容缓存已准备好",
                completedUnitCount: movies.count,
                totalUnitCount: movies.count
            )
        )
    }

    private func transcodeWMVAudioToPCM(from source: URL, to destination: URL, relativePath: String) throws {
        let tempOutput = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.deletingPathExtension().lastPathComponent).\(UUID().uuidString).wmv")

        try? FileManager.default.removeItem(at: tempOutput)
        try? FileManager.default.removeItem(at: destination)

        let process = Process()
        process.executableURL = ffmpegURL
        process.arguments = [
            "-y",
            "-nostdin",
            "-hide_banner",
            "-loglevel", "error",
            "-i", source.path,
            "-map", "0",
            "-c:v", "copy",
            "-c:a", "pcm_s16le",
            tempOutput.path,
        ]

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()

        let output = String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
        guard process.terminationStatus == 0 else {
            try? FileManager.default.removeItem(at: tempOutput)
            throw MediaCompatibilityError.transcodeFailed(relativePath, process.terminationStatus, output)
        }

        try FileManager.default.moveItem(at: tempOutput, to: destination)
    }

    private func removeGeneratedMovieFiles(from manifest: MediaOverlayManifest?, overlayRoot: URL) throws {
        guard let manifest else { return }
        let overlayMovieRoot = overlayRoot.appendingPathComponent("movie")
        for movie in manifest.movies {
            let generated = overlayMovieRoot.appendingPathComponent(movie.relativePath)
            try? FileManager.default.removeItem(at: generated)
        }
    }

    private func isCurrentManifest(
        _ manifest: MediaOverlayManifest,
        manifestURL: URL,
        overlayRoot: URL
    ) throws -> Bool {
        guard let existing = try loadManifest(at: manifestURL), existing == manifest else {
            return false
        }

        let overlayMovieRoot = overlayRoot.appendingPathComponent("movie")
        return manifest.movies.allSatisfy { movie in
            FileManager.default.fileExists(
                atPath: overlayMovieRoot.appendingPathComponent(movie.relativePath).path
            )
        }
    }

    private func loadManifest(at url: URL) throws -> MediaOverlayManifest? {
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode(MediaOverlayManifest.self, from: data)
    }

    private func writeManifest(_ manifest: MediaOverlayManifest, to url: URL) throws {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode(manifest)
        try data.write(to: url, options: .atomic)
    }

    private func replaceWithSymbolicLink(
        at destination: URL,
        to source: URL,
        allowReplacingRegularItem: Bool
    ) throws {
        if FileManager.default.fileExists(atPath: destination.path) ||
            Self.isSymbolicLink(destination) {
            if Self.isSymbolicLink(destination),
               (try? FileManager.default.destinationOfSymbolicLink(atPath: destination.path)) == source.path {
                return
            }

            guard allowReplacingRegularItem || Self.isSymbolicLink(destination) else {
                return
            }
            try? FileManager.default.removeItem(at: destination)
        }

        try FileManager.default.createDirectory(
            at: destination.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createSymbolicLink(
            atPath: destination.path,
            withDestinationPath: source.path
        )
    }

    private func fileSignature(for url: URL) throws -> (byteCount: Int64, modifiedAt: Date) {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        let byteCount = (attributes[.size] as? NSNumber)?.int64Value ?? 0
        let modifiedAt = (attributes[.modificationDate] as? Date) ?? .distantPast
        return (byteCount, modifiedAt)
    }

    private static func relativePath(from url: URL, to root: URL) -> String {
        let rootPath = root.standardizedFileURL.path
        let path = url.standardizedFileURL.path
        guard path.hasPrefix(rootPath + "/") else {
            return url.lastPathComponent
        }
        return String(path.dropFirst(rootPath.count + 1))
    }

    private static func isSymbolicLink(_ url: URL) -> Bool {
        guard let values = try? url.resourceValues(forKeys: [.isSymbolicLinkKey]) else {
            return false
        }
        return values.isSymbolicLink == true
    }

    private static let manifestFileName = ".gala-media-overlay.json"
}

private struct MediaOverlayManifest: Codable, Equatable {
    let version: Int
    let runtimeVersion: String
    let sourceRootPath: String
    let movies: [MediaOverlayMovie]
}

private struct MediaOverlayMovie: Codable, Equatable {
    enum Action: String, Codable {
        case transcodeAudioToPCM
        case symbolicLink
    }

    let relativePath: String
    let byteCount: Int64
    let modifiedAt: Date
    let action: Action
}

public enum MediaCompatibilityError: Error, LocalizedError, Sendable {
    case ffmpegMissing(String)
    case transcodeFailed(String, Int32, String)

    public var errorDescription: String? {
        switch self {
        case .ffmpegMissing(let path):
            return "Media Foundation media tool is missing: \(path)"
        case .transcodeFailed(let relativePath, let status, let output):
            let detail = output.trimmingCharacters(in: .whitespacesAndNewlines)
            if detail.isEmpty {
                return "Failed to prepare \(relativePath), ffmpeg exited with \(status)"
            }
            return "Failed to prepare \(relativePath), ffmpeg exited with \(status): \(detail)"
        }
    }
}
