import Foundation

public struct VNDBResponse<T: Decodable>: Decodable {
    public let results: [T]
    public let more: Bool
}

public struct VNDBVn: Decodable, Sendable {
    public let id: String
    public let title: String
    public let alttitle: String?
    public let released: String?
    public let rating: Double?
    public let votecount: Int?
    public let lengthMinutes: Int?
    public let description: String?
    public let image: VNDBImage?
    public let developers: [VNDBProducer]?
    public let tags: [VNDBTag]?

    enum CodingKeys: String, CodingKey {
        case id, title, alttitle, released, rating, votecount
        case lengthMinutes = "length_minutes"
        case description, image, developers, tags
    }
}

public struct VNDBImage: Decodable, Sendable {
    public let url: String
    public let dims: [Int]?
    public let thumbnail: String?
    public let thumbnailDims: [Int]?

    enum CodingKeys: String, CodingKey {
        case url, dims, thumbnail
        case thumbnailDims = "thumbnail_dims"
    }
}

public struct VNDBProducer: Decodable, Sendable {
    public let id: String?
    public let name: String
}

public struct VNDBTag: Decodable, Sendable {
    public let id: String?
    public let name: String
    public let rating: Double?
}

public struct VNDBRelease: Decodable, Sendable {
    public let id: String
    public let title: String?
    public let engine: String?
    public let platforms: [String]?
}
