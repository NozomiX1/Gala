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
    public let description: String?
    public let image: VNDBImage?
    public let developers: [VNDBProducer]?
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

/// The part of a visual novel's VNDB entry that the game page shows beyond the search result.
public struct VNDBDetail: Decodable, Sendable {
    public let lengthMinutes: Int?
    public let votecount: Int?
    public let titles: [VNDBTitle]?

    enum CodingKeys: String, CodingKey {
        case lengthMinutes = "length_minutes"
        case votecount, titles
    }

    /// The Chinese title, Simplified before Traditional.
    public var chineseTitle: String? {
        let titles = titles ?? []
        return ["zh-Hans", "zh-Hant", "zh"].lazy
            .compactMap { prefix in titles.first { $0.lang.hasPrefix(prefix) }?.title }
            .first
    }
}

public struct VNDBTitle: Decodable, Sendable {
    public let lang: String
    public let title: String
}

public struct VNDBReleaseLanguage: Decodable, Sendable {
    public let lang: String
    public let mtl: Bool?

    public init(lang: String, mtl: Bool? = nil) {
        self.lang = lang
        self.mtl = mtl
    }
}

public struct VNDBRelease: Decodable, Sendable {
    public let id: String
    public let title: String?
    public let engine: String?
    public let platforms: [String]?
    public let patch: Bool?
    public let official: Bool?
    public let languages: [VNDBReleaseLanguage]?

    public init(
        id: String,
        title: String?,
        engine: String?,
        platforms: [String]?,
        patch: Bool? = nil,
        official: Bool? = nil,
        languages: [VNDBReleaseLanguage]? = nil
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.platforms = platforms
        self.patch = patch
        self.official = official
        self.languages = languages
    }
}
