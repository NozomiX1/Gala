import Foundation

public struct AppVersion: Comparable, CustomStringConvertible, Sendable {
    public let rawValue: String
    private let components: [Int]

    public init(_ rawValue: String) {
        let normalized = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rawValue = normalized.hasPrefix("v") ? String(normalized.dropFirst()) : normalized
        self.components = Self.numericComponents(from: self.rawValue)
    }

    public init?(releaseTag: String) {
        let normalized = Self.normalizedReleaseTag(releaseTag)
        guard Self.isAppReleaseVersion(normalized) else { return nil }
        self.rawValue = normalized
        self.components = Self.numericComponents(from: normalized)
    }

    public var description: String {
        rawValue
    }

    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count, 3)
        for index in 0..<count {
            let left = index < lhs.components.count ? lhs.components[index] : 0
            let right = index < rhs.components.count ? rhs.components[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    private static func numericComponents(from version: String) -> [Int] {
        version
            .split { !$0.isNumber }
            .prefix(3)
            .map { Int($0) ?? 0 }
    }

    private static func normalizedReleaseTag(_ tag: String) -> String {
        let trimmed = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let first = trimmed.first,
              first == "v" || first == "V",
              trimmed.dropFirst().first?.isNumber == true else {
            return trimmed
        }
        return String(trimmed.dropFirst())
    }

    private static func isAppReleaseVersion(_ version: String) -> Bool {
        let metadataStripped = version.split(separator: "+", maxSplits: 1).first ?? ""
        let core = metadataStripped.split(separator: "-", maxSplits: 1).first ?? ""
        let parts = core.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count) else { return false }
        return parts.allSatisfy { part in
            !part.isEmpty && part.allSatisfy(\.isNumber)
        }
    }
}

public struct GitHubRelease: Decodable, Equatable, Sendable {
    public let tagName: String
    public let name: String?
    public let body: String?
    public let htmlURL: URL
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [GitHubReleaseAsset]

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case name
        case body
        case htmlURL = "html_url"
        case draft
        case prerelease
        case assets
    }
}

public struct GitHubReleaseAsset: Decodable, Equatable, Sendable {
    public let name: String
    public let browserDownloadURL: URL

    private enum CodingKeys: String, CodingKey {
        case name
        case browserDownloadURL = "browser_download_url"
    }
}

public struct AppUpdate: Equatable, Sendable {
    public let latestVersion: String
    public let releaseNotes: String
    public let releasePageURL: URL
    public let downloadURL: URL?
}

public enum AppUpdateCheckResult: Equatable, Sendable {
    case upToDate(currentVersion: String)
    case updateAvailable(AppUpdate)
    case missingInstaller(latestVersion: String, releasePageURL: URL, releaseNotes: String)
}

public enum AppUpdateEvaluator {
    public static func evaluate(
        currentVersion: String,
        releases: [GitHubRelease]
    ) -> AppUpdateCheckResult {
        guard let release = latestAppRelease(from: releases) else {
            return .upToDate(currentVersion: currentVersion)
        }
        return evaluate(currentVersion: currentVersion, release: release)
    }

    public static func latestAppRelease(from releases: [GitHubRelease]) -> GitHubRelease? {
        let candidates = releases.compactMap { release -> (release: GitHubRelease, version: AppVersion)? in
            guard !release.draft,
                  !release.prerelease,
                  let version = AppVersion(releaseTag: release.tagName) else {
                return nil
            }
            return (release, version)
        }

        return candidates.max { lhs, rhs in
            lhs.version < rhs.version
        }?.release
    }

    public static func evaluate(
        currentVersion: String,
        release: GitHubRelease
    ) -> AppUpdateCheckResult {
        guard !release.draft, !release.prerelease else {
            return .upToDate(currentVersion: currentVersion)
        }

        guard let latest = AppVersion(releaseTag: release.tagName) else {
            return .upToDate(currentVersion: currentVersion)
        }
        guard latest > AppVersion(currentVersion) else {
            return .upToDate(currentVersion: currentVersion)
        }

        let releaseNotes = release.body ?? ""
        guard let installer = release.assets.first(where: { asset in
            asset.name.lowercased().hasSuffix(".dmg")
        }) else {
            return .missingInstaller(
                latestVersion: latest.description,
                releasePageURL: release.htmlURL,
                releaseNotes: releaseNotes
            )
        }

        return .updateAvailable(AppUpdate(
            latestVersion: latest.description,
            releaseNotes: releaseNotes,
            releasePageURL: release.htmlURL,
            downloadURL: installer.browserDownloadURL
        ))
    }
}

public final class GitHubReleaseClient: Sendable {
    private let session: URLSession
    private let apiBaseURL: URL

    public init(
        session: URLSession = .shared,
        apiBaseURL: URL = URL(string: "https://api.github.com")!
    ) {
        self.session = session
        self.apiBaseURL = apiBaseURL
    }

    public func releases(owner: String, repo: String, limit: Int = 20) async throws -> [GitHubRelease] {
        let url = apiBaseURL
            .appendingPathComponent("repos")
            .appendingPathComponent(owner)
            .appendingPathComponent(repo)
            .appendingPathComponent("releases")
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "per_page", value: String(limit))
        ]

        var request = URLRequest(url: components?.url ?? url)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw AppUpdateError.httpError(statusCode: statusCode)
        }
        return try JSONDecoder().decode([GitHubRelease].self, from: data)
    }

    public func latestRelease(owner: String, repo: String) async throws -> GitHubRelease {
        let releases = try await releases(owner: owner, repo: repo)
        guard let release = AppUpdateEvaluator.latestAppRelease(from: releases) else {
            throw AppUpdateError.noAppRelease
        }
        return release
    }
}

public enum AppUpdateError: Error, LocalizedError {
    case httpError(statusCode: Int)
    case noAppRelease

    public var errorDescription: String? {
        switch self {
        case .httpError(let code):
            return "GitHub Releases API error (HTTP \(code))"
        case .noAppRelease:
            return "No Gala app release found"
        }
    }
}
