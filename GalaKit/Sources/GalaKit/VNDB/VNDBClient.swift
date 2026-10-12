import Foundation

public final class VNDBClient: Sendable {
    private let baseURL = URL(string: "https://api.vndb.org/kana")!
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func searchVN(query: String, results: Int = 25) async throws -> VNDBResponse<VNDBVn> {
        let body = Self.searchRequestBody(query: query, results: results)
        return try await post(endpoint: "vn", body: body)
    }

    public func getReleases(vnId: String) async throws -> [VNDBRelease] {
        let body = Self.releasesRequestBody(vnId: vnId)
        let response: VNDBResponse<VNDBRelease> = try await post(endpoint: "release", body: body)
        return response.results
    }

    public func downloadImage(from url: URL) async throws -> Data {
        let (data, _) = try await session.data(from: url)
        return data
    }

    static func searchRequestBody(query: String, results: Int = 25) -> Data {
        let body: [String: Any] = [
            "filters": ["search", "=", query],
            "fields": "id, title, alttitle, released, rating, description, image{url,dims,thumbnail,thumbnail_dims}, developers{id,name}",
            "sort": "searchrank",
            "results": results
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    static func releasesRequestBody(vnId: String) -> Data {
        let body: [String: Any] = [
            "filters": ["vn", "=", ["id", "=", vnId]],
            "fields": "id, title, engine, platforms, patch",
            "results": 50
        ]
        return try! JSONSerialization.data(withJSONObject: body)
    }

    private func post<T: Decodable>(endpoint: String, body: Data) async throws -> T {
        var request = URLRequest(url: baseURL.appendingPathComponent(endpoint))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              200..<300 ~= httpResponse.statusCode else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw VNDBError.httpError(statusCode: statusCode)
        }
        return try JSONDecoder().decode(T.self, from: data)
    }
}

public enum VNDBError: Error, LocalizedError {
    case httpError(statusCode: Int)

    public var errorDescription: String? {
        switch self {
        case .httpError(let code): return "VNDB API error (HTTP \(code))"
        }
    }
}
