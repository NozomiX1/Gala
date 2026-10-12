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

/// Extra facts about one visual novel, fetched when its page is opened.
public struct VNDBDetail: Decodable, Sendable {
    public let lengthMinutes: Int?
    public let titles: [VNDBTitle]?
    public let screenshots: [VNDBScreenshot]?

    enum CodingKeys: String, CodingKey {
        case lengthMinutes = "length_minutes"
        case titles, screenshots
    }

    /// Screenshots VNDB's voters flagged as neither sexual nor violent. Anything else is never shown.
    public var safeScreenshots: [VNDBScreenshot] {
        (screenshots ?? []).filter { $0.sexual == 0 && $0.violence == 0 }
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

public struct VNDBScreenshot: Decodable, Hashable, Sendable {
    public let url: String
    public let sexual: Double
    public let violence: Double
}

public struct VNDBRelease: Decodable, Sendable {
    public let id: String
    public let title: String?
    public let engine: String?
    public let platforms: [String]?
    public let patch: Bool?

    public init(
        id: String,
        title: String?,
        engine: String?,
        platforms: [String]?,
        patch: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.engine = engine
        self.platforms = platforms
        self.patch = patch
    }
}
