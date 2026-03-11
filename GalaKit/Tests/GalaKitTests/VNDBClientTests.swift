import Testing
import Foundation
@testable import GalaKit

@Test func decodeVNDBSearchResponse() throws {
    let json = """
    {
        "results": [
            {
                "id": "v11",
                "title": "Fate/stay night",
                "alttitle": "Fate/stay night",
                "released": "2004-01-30",
                "rating": 83.5,
                "image": {
                    "url": "https://t.vndb.org/cv/71/89071.jpg",
                    "dims": [600, 900],
                    "thumbnail": "https://t.vndb.org/cv.t/71/89071.jpg",
                    "thumbnail_dims": [256, 384]
                }
            }
        ],
        "more": true
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(VNDBResponse<VNDBVn>.self, from: json)
    #expect(response.results.count == 1)
    #expect(response.results[0].id == "v11")
    #expect(response.results[0].title == "Fate/stay night")
    #expect(response.results[0].rating == 83.5)
    #expect(response.results[0].image?.url == "https://t.vndb.org/cv/71/89071.jpg")
    #expect(response.more == true)
}

@Test func decodeVNDBReleaseWithEngine() throws {
    let json = """
    {
        "results": [
            {
                "id": "r123",
                "title": "Fate/stay night",
                "engine": "KiriKiri",
                "platforms": ["win"]
            }
        ],
        "more": false
    }
    """.data(using: .utf8)!

    let response = try JSONDecoder().decode(VNDBResponse<VNDBRelease>.self, from: json)
    #expect(response.results[0].engine == "KiriKiri")
    #expect(response.results[0].platforms?.contains("win") == true)
}

@Test func buildSearchRequestBody() throws {
    let body = VNDBClient.searchRequestBody(query: "Fate", results: 10)
    let data = try JSONSerialization.jsonObject(with: body) as! [String: Any]
    let filters = data["filters"] as! [Any]
    #expect(filters[0] as! String == "search")
    #expect(filters[1] as! String == "=")
    #expect(filters[2] as! String == "Fate")
}
