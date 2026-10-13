import Foundation

public enum GameStatus: String, Codable, CaseIterable, Sendable {
    case backlog, playing, completed, dropped

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = GameStatus(rawValue: rawValue) ?? .backlog
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Whether a visual novel can be played in Chinese, as far as VNDB's release list knows.
public enum ChineseAvailability: String, Codable, Sendable {
    case official, fan, none

    public init(from decoder: Decoder) throws {
        let rawValue = try decoder.singleValueContainer().decode(String.self)
        self = ChineseAvailability(rawValue: rawValue) ?? .none
    }

    /// Official beats fan-made; machine translations count as neither.
    public static func from(chineseReleases releases: [VNDBRelease]) -> ChineseAvailability {
        let translated = releases.filter { release in
            (release.languages ?? []).contains { $0.lang.hasPrefix("zh") && $0.mtl != true }
        }
        if translated.contains(where: { $0.official == true }) { return .official }
        return translated.isEmpty ? .none : .fan
    }
}

/// Facts about a visual novel looked up on VNDB once and then stored with the game.
public struct VNDBFacts: Equatable, Sendable {
    public var chineseTitle: String?
    public var voteCount: Int?
    public var lengthMinutes: Int?
    public var chineseAvailability: ChineseAvailability

    public init(chineseTitle: String?, voteCount: Int?, lengthMinutes: Int?, chineseAvailability: ChineseAvailability) {
        self.chineseTitle = chineseTitle
        self.voteCount = voteCount
        self.lengthMinutes = lengthMinutes
        self.chineseAvailability = chineseAvailability
    }
}

public struct Game: Identifiable, Codable, Sendable {
    public var id: UUID
    public var title: String
    public var originalTitle: String?
    public var vndbId: String?
    public var executablePath: String
    public var coverImagePath: String?
    public var engine: Engine?
    /// The runtime profile picked by hand. Nil means the engine's default profile.
    public var profileID: String?
    /// Chosen options of the named switches, by switch id. A switch that is absent follows the profile.
    public var launchSwitches: [String: String] = [:]
    /// Advice the user has already been shown for this game, so the game page stops pointing at it.
    public var acknowledgedAdvice: [String] = []
    public var totalPlayTime: TimeInterval
    public var lastPlayedAt: Date?
    public var addedAt: Date
    public var rating: Double?
    public var voteCount: Int?
    public var lengthMinutes: Int?
    public var chineseTitle: String?
    /// Nil until the VNDB facts have been fetched for this game.
    public var chineseAvailability: ChineseAvailability?
    public var developer: String?
    public var releasedAt: String?
    public var description: String?
    public var status: GameStatus
    public var isFavorite: Bool
    public var isRuntimeConfigured: Bool
    public var runtimeProfileMigrationVersion: Int?
    public var runtimeProfileMigrationExecutablePath: String?
    public var bottleConfig: BottleConfig

    public init(
        id: UUID = UUID(),
        title: String,
        originalTitle: String? = nil,
        vndbId: String? = nil,
        executablePath: String,
        coverImagePath: String? = nil,
        engine: Engine? = nil,
        profileID: String? = nil,
        totalPlayTime: TimeInterval = 0,
        lastPlayedAt: Date? = nil,
        addedAt: Date = Date(),
        rating: Double? = nil,
        developer: String? = nil,
        releasedAt: String? = nil,
        description: String? = nil,
        status: GameStatus = .backlog,
        isFavorite: Bool = false,
        isRuntimeConfigured: Bool = false,
        runtimeProfileMigrationVersion: Int? = nil,
        runtimeProfileMigrationExecutablePath: String? = nil,
        bottleConfig: BottleConfig? = nil
    ) {
        self.id = id
        self.title = title
        self.originalTitle = originalTitle
        self.vndbId = vndbId
        self.executablePath = executablePath
        self.coverImagePath = coverImagePath
        self.engine = engine
        self.profileID = profileID
        self.totalPlayTime = totalPlayTime
        self.lastPlayedAt = lastPlayedAt
        self.addedAt = addedAt
        self.rating = rating
        self.developer = developer
        self.releasedAt = releasedAt
        self.description = description
        self.status = status
        self.isFavorite = isFavorite
        self.isRuntimeConfigured = isRuntimeConfigured
        self.runtimeProfileMigrationVersion = runtimeProfileMigrationVersion
        self.runtimeProfileMigrationExecutablePath = runtimeProfileMigrationExecutablePath
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
        profileID = try container.decodeIfPresent(String.self, forKey: .profileID)
        launchSwitches = try container.decodeIfPresent([String: String].self, forKey: .launchSwitches) ?? [:]
        acknowledgedAdvice = try container.decodeIfPresent([String].self, forKey: .acknowledgedAdvice) ?? []
        totalPlayTime = try container.decodeIfPresent(TimeInterval.self, forKey: .totalPlayTime) ?? 0
        lastPlayedAt = try container.decodeIfPresent(Date.self, forKey: .lastPlayedAt)
        addedAt = try container.decodeIfPresent(Date.self, forKey: .addedAt) ?? Date()
        rating = try container.decodeIfPresent(Double.self, forKey: .rating)
        voteCount = try container.decodeIfPresent(Int.self, forKey: .voteCount)
        lengthMinutes = try container.decodeIfPresent(Int.self, forKey: .lengthMinutes)
        chineseTitle = try container.decodeIfPresent(String.self, forKey: .chineseTitle)
        chineseAvailability = try container.decodeIfPresent(ChineseAvailability.self, forKey: .chineseAvailability)
        developer = try container.decodeIfPresent(String.self, forKey: .developer)
        releasedAt = try container.decodeIfPresent(String.self, forKey: .releasedAt)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        status = try container.decodeIfPresent(GameStatus.self, forKey: .status) ?? .backlog
        isFavorite = try container.decodeIfPresent(Bool.self, forKey: .isFavorite) ?? false
        runtimeProfileMigrationVersion = try container.decodeIfPresent(
            Int.self,
            forKey: .runtimeProfileMigrationVersion
        )
        runtimeProfileMigrationExecutablePath = try container.decodeIfPresent(
            String.self,
            forKey: .runtimeProfileMigrationExecutablePath
        )
        bottleConfig = try container.decode(BottleConfig.self, forKey: .bottleConfig)
        isRuntimeConfigured = try container.decodeIfPresent(Bool.self, forKey: .isRuntimeConfigured)
            ?? !bottleConfig.prefixPath.isEmpty
    }

    public mutating func apply(_ facts: VNDBFacts) {
        chineseTitle = facts.chineseTitle
        voteCount = facts.voteCount
        lengthMinutes = facts.lengthMinutes
        chineseAvailability = facts.chineseAvailability
    }
}
