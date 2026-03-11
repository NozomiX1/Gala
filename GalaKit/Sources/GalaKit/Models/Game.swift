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
        self.bottleConfig = bottleConfig ?? BottleConfig(prefixPath: "")
    }
}
