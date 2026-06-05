import Testing
import Foundation
@testable import GalaKit

@Test func updateEvaluatorFindsNewerReleaseWithDMGAsset() throws {
    let release = try decodeRelease("""
    {
      "tag_name": "v1.2.0",
      "name": "Gala 1.2.0",
      "body": "Migration-safe updates",
      "html_url": "https://github.com/NozomiX1/Gala/releases/tag/v1.2.0",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "Gala.dmg",
          "browser_download_url": "https://github.com/NozomiX1/Gala/releases/download/v1.2.0/Gala.dmg"
        }
      ]
    }
    """)

    let result = AppUpdateEvaluator.evaluate(currentVersion: "1.1.2", release: release)

    guard case .updateAvailable(let update) = result else {
        Issue.record("Expected updateAvailable, got \(result)")
        return
    }
    #expect(update.latestVersion == "1.2.0")
    #expect(update.releaseNotes == "Migration-safe updates")
    #expect(update.downloadURL?.absoluteString.hasSuffix("/Gala.dmg") == true)
}

@Test func updateEvaluatorTreatsSameVersionAsUpToDate() throws {
    let release = try decodeRelease("""
    {
      "tag_name": "v1.1.2",
      "name": "Gala 1.1.2",
      "body": "Current",
      "html_url": "https://github.com/NozomiX1/Gala/releases/tag/v1.1.2",
      "draft": false,
      "prerelease": false,
      "assets": []
    }
    """)

    #expect(AppUpdateEvaluator.evaluate(currentVersion: "1.1.2", release: release) == .upToDate(currentVersion: "1.1.2"))
}

@Test func updateEvaluatorIgnoresPrerelease() throws {
    let release = try decodeRelease("""
    {
      "tag_name": "v1.3.0-beta.1",
      "name": "Gala 1.3.0 beta",
      "body": "Beta",
      "html_url": "https://github.com/NozomiX1/Gala/releases/tag/v1.3.0-beta.1",
      "draft": false,
      "prerelease": true,
      "assets": []
    }
    """)

    #expect(AppUpdateEvaluator.evaluate(currentVersion: "1.1.2", release: release) == .upToDate(currentVersion: "1.1.2"))
}

@Test func updateEvaluatorReportsMissingInstallerAsset() throws {
    let release = try decodeRelease("""
    {
      "tag_name": "v1.2.0",
      "name": "Gala 1.2.0",
      "body": "No DMG yet",
      "html_url": "https://github.com/NozomiX1/Gala/releases/tag/v1.2.0",
      "draft": false,
      "prerelease": false,
      "assets": [
        {
          "name": "Source.zip",
          "browser_download_url": "https://github.com/NozomiX1/Gala/archive/refs/tags/v1.2.0.zip"
        }
      ]
    }
    """)

    let result = AppUpdateEvaluator.evaluate(currentVersion: "1.1.2", release: release)

    guard case .missingInstaller(let latestVersion, let releasePageURL, let releaseNotes) = result else {
        Issue.record("Expected missingInstaller, got \(result)")
        return
    }
    #expect(latestVersion == "1.2.0")
    #expect(releasePageURL.absoluteString.hasSuffix("/v1.2.0"))
    #expect(releaseNotes == "No DMG yet")
}

@Test func semanticVersionComparisonHandlesMultiDigitComponents() {
    #expect(AppVersion("1.10.0") > AppVersion("1.9.9"))
    #expect(AppVersion("v2.0") > AppVersion("1.99.99"))
}

private func decodeRelease(_ json: String) throws -> GitHubRelease {
    try JSONDecoder().decode(GitHubRelease.self, from: Data(json.utf8))
}
