import Testing
import Foundation
@testable import GalaKit

private func release(official: Bool, _ languages: VNDBReleaseLanguage...) -> VNDBRelease {
    VNDBRelease(id: "r1", title: nil, engine: nil, platforms: nil, official: official, languages: languages)
}

@Test func detailPrefersTheSimplifiedChineseTitle() throws {
    let json = #"{"length_minutes":2400,"votecount":2345,"titles":[{"lang":"ja","title":"穢翼のユースティア"},{"lang":"zh-Hant","title":"穢翼的尤斯蒂婭"},{"lang":"zh-Hans","title":"秽翼的尤斯蒂娅"}]}"#
    let detail = try JSONDecoder().decode(VNDBDetail.self, from: Data(json.utf8))

    #expect(detail.chineseTitle == "秽翼的尤斯蒂娅")
    #expect(detail.lengthMinutes == 2400)
    #expect(detail.votecount == 2345)
}

@Test func detailWithNothingKnownIsEmptyRatherThanAnError() throws {
    let detail = try JSONDecoder().decode(VNDBDetail.self, from: Data("{}".utf8))

    #expect(detail.chineseTitle == nil)
    #expect(detail.lengthMinutes == nil)
}

@Test func chineseAvailabilityPrefersAnOfficialRelease() {
    let releases = [
        release(official: false, VNDBReleaseLanguage(lang: "zh-Hans")),
        release(official: true, VNDBReleaseLanguage(lang: "ja"), VNDBReleaseLanguage(lang: "zh-Hant")),
    ]

    #expect(ChineseAvailability.from(chineseReleases: releases) == .official)
}

@Test func chineseAvailabilityReportsFanTranslations() {
    #expect(ChineseAvailability.from(chineseReleases: [release(official: false, VNDBReleaseLanguage(lang: "zh-Hans"))]) == .fan)
}

@Test func chineseAvailabilityIgnoresMachineTranslationsAndOtherLanguages() {
    let releases = [
        release(official: true, VNDBReleaseLanguage(lang: "zh-Hans", mtl: true)),
        release(official: true, VNDBReleaseLanguage(lang: "en")),
    ]

    #expect(ChineseAvailability.from(chineseReleases: releases) == .none)
    #expect(ChineseAvailability.from(chineseReleases: []) == .none)
}

@Test func chineseReleasesRequestFiltersByLanguageOnTheServer() throws {
    let body = String(decoding: VNDBClient.chineseReleasesRequestBody(vnId: "v3770"), as: UTF8.self)

    #expect(body.contains("zh-Hans"))
    #expect(body.contains("zh-Hant"))
    #expect(body.contains("v3770"))
}

@Test func gameStoresVNDBFactsAndStillReadsLibrariesWithoutThem() throws {
    var game = Game(title: "穢翼のユースティア", executablePath: "/games/eustia/BGI.exe")
    #expect(game.chineseAvailability == nil)

    game.apply(VNDBFacts(chineseTitle: "秽翼的尤斯蒂娅", voteCount: 2345, lengthMinutes: 2400, chineseAvailability: .fan))
    let decoded = try JSONDecoder().decode(Game.self, from: JSONEncoder().encode(game))

    #expect(decoded.chineseTitle == "秽翼的尤斯蒂娅")
    #expect(decoded.voteCount == 2345)
    #expect(decoded.lengthMinutes == 2400)
    #expect(decoded.chineseAvailability == .fan)

    let legacy = #"{"id":"7B0F3C52-0000-4000-8000-000000000001","title":"Old","executablePath":"/g/a.exe","bottleConfig":{"prefixPath":"","dllOverrides":{},"environment":{},"launchArguments":[],"locale":"zh_CN.UTF-8"}}"#
    #expect(try JSONDecoder().decode(Game.self, from: Data(legacy.utf8)).chineseAvailability == nil)
}
