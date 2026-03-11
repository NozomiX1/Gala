import Foundation

public enum Engine: String, Codable, CaseIterable, Sendable {
    case kirikiri, nscripter, renpy, rpgMaker, unity
    case bgi, catSystem2, siglusEngine, artemis, yuris
    case majiro, advHD, realLive, qlie, unknown
}

public struct EnginePreset: Sendable {
    public let components: [String]
    public let dllOverrides: [String: String]
    public static let empty = EnginePreset(components: [], dllOverrides: [:])
}

extension Engine {
    public var preset: EnginePreset {
        switch self {
        case .kirikiri:
            return EnginePreset(components: ["quartz", "amstream", "lavfilters"], dllOverrides: ["quartz": "native"])
        case .bgi:
            return EnginePreset(components: ["quartz", "amstream", "lavfilters"], dllOverrides: [:])
        case .catSystem2:
            return EnginePreset(components: ["dotnet40", "quartz", "vcrun2015"], dllOverrides: [:])
        case .siglusEngine:
            return EnginePreset(components: ["quartz", "amstream", "lavfilters", "xact", "xinput", "vcrun2019"],
                              dllOverrides: ["xaudio2_7": "native", "xactengine3_7": "native"])
        case .rpgMaker:
            return EnginePreset(components: ["d3dx9"], dllOverrides: [:])
        case .unity:
            return EnginePreset(components: ["dotnet48", "d3dcompiler_47"], dllOverrides: [:])
        case .nscripter, .renpy, .artemis, .yuris, .majiro, .advHD, .realLive, .qlie, .unknown:
            return .empty
        }
    }

    public var displayName: String {
        switch self {
        case .kirikiri: return "KiriKiri"
        case .nscripter: return "NScripter"
        case .renpy: return "Ren'Py"
        case .rpgMaker: return "RPG Maker"
        case .unity: return "Unity"
        case .bgi: return "BGI/Ethornell"
        case .catSystem2: return "CatSystem2"
        case .siglusEngine: return "SiglusEngine"
        case .artemis: return "Artemis Engine"
        case .yuris: return "YU-RIS"
        case .majiro: return "Majiro"
        case .advHD: return "AdvHD"
        case .realLive: return "RealLive"
        case .qlie: return "QLIE"
        case .unknown: return "Unknown"
        }
    }

    public var supportsNativeLaunch: Bool {
        switch self {
        case .renpy, .rpgMaker, .unity: return true
        default: return false
        }
    }
}
