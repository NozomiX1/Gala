import Foundation

public enum GameStatus: String, Codable, CaseIterable, Sendable {
    case backlog, playing, completed, dropped
}

public struct Game: Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var originalTitle: String?
    public var vndbId: String?
    public var executablePath: String
    public var coverImagePath: String?
    public var engine: Engine?
    public var totalPlayTime: TimeInterval
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var rating: Double?
    public var developer: String?
    public var releasedAt: String?
    public var description: String?
    public var tags: [String]
    public var status: GameStatus
    public var isFavorite: Bool
    public var bottleConfig: BottleConfig

    public init(
        id: UUID = UUID(),
        title: String,
        originalTitle: String? = nil,
        vndbId: String? = nil,
        executablePath: String,
        coverImagePath: String? = nil,
        engine: Engine? = nil,
        totalPlayTime: TimeInterval = 0,
        lastPlayedAt: Date? = nil,
        addedAt: Date = Date(),
        rating: Double? = nil,
        developer: String? = nil,
        releasedAt: String? = nil,
        description: String? = nil,
        tags: [String] = [],
        status: GameStatus = .backlog,
        isFavorite: Bool = false,
        bottleConfig: BottleConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.vndbId = vndbId
        self.executablePath = executablePath
        self.coverImagePath = coverImagePath
        self.engine = engine
        self.totalPlayTime = totalPlayTime
        self.lastPlayedAt = lastPlayedAt
        self.addedAt = addedAt
        self.rating = rating
        self.developer = developer
        self.releasedAt = releasedAt
        self.description = description
        self.tags = tags
        self.status = status
        self.isFavorite = isFavorite
        self.bottleConfig = bottleConfig ?? BottleConfig(prefixPath: "")
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        title = try container.decode(String.self, forKey: .title)
        originalTitle = try container.decodeIfPresent(String.self, forKey: .originalTitle)
        vndbId = try container.decodeIfPresent(String.self, forKey: .vndbId)
        executablePath = try container.decode(String.self, forKey: .executablePath)
        coverImagePath = try container.decodeIfPresent(String.self, forKey: .coverImagePath)
        engine = try container.decodeIfPresent(Engine.self, forKey: .engine)
        totalPlayTime = try container.decodeIfPresent(TimeInterval.self, forKey: .totalPlayTime) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        releasedAt = try container.decodeIfPresent(String.self, forKey: .releasedAt)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        status = try container.decodeIfPresent(GameStatus.self, forKey: .status) ?? .backlog
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        bottleConfig = try container.decode(BottleConfig.self, forKey: .bottleConfig)
    }
}
