import Testing
import Foundation
@testable import GalaKit

private let sample = #"""
{"results":[{"length_minutes":2400,
  "titles":[{"lang":"ja","title":"穢翼のユースティア"},{"lang":"zh-Hant","title":"穢翼的尤斯蒂婭"},{"lang":"zh-Hans","title":"秽翼的尤斯蒂娅"}],
  "screenshots":[{"url":"https://t.vndb.org/sf/1.jpg","sexual":0,"violence":0},
                 {"url":"https://t.vndb.org/sf/2.jpg","sexual":1.2,"violence":0},
                 {"url":"https://t.vndb.org/sf/3.jpg","sexual":0,"violence":0.4}]}],"more":false}
"""#

@Test func detailKeepsOnlyScreenshotsWithNoContentFlags() throws {
    let detail = try #require(JSONDecoder().decode(VNDBResponse<VNDBDetail>.self, from: Data(sample.utf8)).results.first)

    #expect(detail.safeScreenshots.map(\.url) == ["https://t.vndb.org/sf/1.jpg"])
    #expect(detail.lengthMinutes == 2400)
}

@Test func detailPrefersTheSimplifiedChineseTitle() throws {
    let detail = try #require(JSONDecoder().decode(VNDBResponse<VNDBDetail>.self, from: Data(sample.utf8)).results.first)

    #expect(detail.chineseTitle == "秽翼的尤斯蒂娅")
}

@Test func detailWithNothingKnownIsEmptyRatherThanAnError() throws {
    let detail = try JSONDecoder().decode(VNDBDetail.self, from: Data("{}".utf8))

    #expect(detail.safeScreenshots.isEmpty)
    #expect(detail.chineseTitle == nil)
}

@Test func detailRequestAsksForTheContentFlags() throws {
    let body = try #require(JSONSerialization.jsonObject(with: VNDBClient.detailRequestBody(vnId: "v3770")) as? [String: Any])

    #expect((body["fields"] as? String)?.contains("screenshots{url,sexual,violence}") == true)
}
