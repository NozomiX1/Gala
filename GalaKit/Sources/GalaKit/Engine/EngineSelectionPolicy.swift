import Foundation

public enum EngineAliasResolver {
    public static func resolve(vndbEngineName: String?, gameDirectory: URL? = nil) -> Engine? {
        guard let vndbEngineName else { return nil }

        switch normalize(vndbEngineName) {
        case "bgiethornell", "ethornell", "bgi":
            return .bgi
        case "kirikiri", "kirikiriz", "kirikiri2":
            return .kirikiri
        case "artemisengine", "artemis":
            return .artemis
        case "siglusengine":
            return .siglusEngine
        case "catsystem2":
            return .catSystem2
        case "nscripter":
            return .nscripter
        case "yuris":
            return .yuris
        case "reallive":
            return .realLive
        case "majiro":
            return .majiro
        case "advhd":
            return .advHD
        case "qlie":
            return .qlie
        case "renpy":
            return .renpy
        case "unity", "unityengine":
            return .unity
        case "rpgmaker", "rpgmakermv", "rpgmakermz", "rpgmakervx", "rpgmakervxace":
            return .rpgMaker
        case "ikuragdl":
            guard let gameDirectory,
                  EngineDetector.detectsIkuraGDLFamilyProject(in: gameDirectory) else {
                return nil
            }
            return .ikuraGDLFamilyProject
        case "aquaplusengine":
            guard let gameDirectory,
                  EngineDetector.detectsLeafAQUAPLUS(in: gameDirectory) else {
                return nil
            }
            return .leaf
        default:
            return nil
        }
    }

    private static func normalize(_ name: String) -> String {
        name
            .folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: Locale(identifier: "en_US_POSIX"))
            .lowercased()
            .filter { $0.isLetter || $0.isNumber }
    }
}

public enum EngineSelectionPolicy {
    public static func select(
        localDetection: Engine?,
        vndbReleases: [VNDBRelease],
        gameDirectory: URL?
    ) -> Engine {
        if let localDetection { return localDetection }

        // One title can ship on several engines (a Whale original, a KiriKiri re-release), and VNDB cannot tell which copy this is.
        let names = Set(vndbReleases.filter(isUsableWindowsRelease).compactMap(\.engine))
        guard names.count == 1, let name = names.first else { return .unknown }
        return EngineAliasResolver.resolve(vndbEngineName: name, gameDirectory: gameDirectory) ?? .unknown
    }

    private static func isUsableWindowsRelease(_ release: VNDBRelease) -> Bool {
        guard release.patch != true else { return false }
        return release.platforms?.contains("win") == true
    }
}
