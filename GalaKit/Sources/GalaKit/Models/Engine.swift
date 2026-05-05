import Foundation

public enum Engine: String, Codable, CaseIterable, Sendable {
    case kirikiri, nscripter, renpy, rpgMaker, unity
    case bgi, catSystem2, siglusEngine, artemis, yuris
    case majiro, advHD, realLive, qlie, leaf, unknown
}

public struct RegistryValue: Sendable {
    public let key: String
    public let valueName: String
    public let type: String
    public let data: String

    public init(key: String, valueName: String, type: String, data: String) {
        self.key = key
        self.valueName = valueName
        self.type = type
        self.data = data
    }
}

public struct EnginePreset: Sendable {
    public let components: [String]
    public let dllOverrides: [String: String]
    public let registryValues: [RegistryValue]

    public init(
        components: [String],
        dllOverrides: [String: String],
        registryValues: [RegistryValue] = []
    ) {
        self.components = components
        self.dllOverrides = dllOverrides
        self.registryValues = registryValues
    }

    public static let empty = EnginePreset(components: [], dllOverrides: [:])
}

extension Engine {
    private static let legacyVideoComponents = ["quartz", "amstream", "lavfilters"]
    private static let legacyVideoPreset = EnginePreset(
        components: legacyVideoComponents,
        dllOverrides: [:]
    )

    public var preset: EnginePreset {
        switch self {
        case .kirikiri:
            return EnginePreset(components: Self.legacyVideoComponents, dllOverrides: ["quartz": "native"])
        case .bgi:
            return Self.legacyVideoPreset
        case .catSystem2:
            return EnginePreset(components: ["dotnet40", "quartz", "vcrun2015"], dllOverrides: [:])
        case .siglusEngine:
            return EnginePreset(components: Self.legacyVideoComponents + ["xact", "xinput", "vcrun2019"],
                              dllOverrides: ["xaudio2_7": "native", "xactengine3_7": "native"])
        case .artemis, .nscripter, .yuris, .realLive:
            return Self.legacyVideoPreset
        case .leaf:
            let lavOutputKey = "HKCU\\Software\\LAV\\Video\\Output"
            return EnginePreset(
                components: Self.legacyVideoComponents,
                dllOverrides: [
                    "quartz": "builtin",
                    "amstream": "builtin",
                    "devenum": "builtin",
                    "*quartz": "builtin",
                    "*amstream": "builtin",
                    "*devenum": "builtin",
                    "wmvdecod": "disabled",
                    "wmadmod": "disabled",
                    "winegstreamer": "disabled",
                ],
                registryValues: [
                    RegistryValue(key: lavOutputKey, valueName: "nv12", type: "REG_DWORD", data: "0"),
                    RegistryValue(key: lavOutputKey, valueName: "yv12", type: "REG_DWORD", data: "0"),
                    RegistryValue(key: lavOutputKey, valueName: "yuy2", type: "REG_DWORD", data: "0"),
                    RegistryValue(key: lavOutputKey, valueName: "uyvy", type: "REG_DWORD", data: "0"),
                    RegistryValue(key: lavOutputKey, valueName: "rgb24", type: "REG_DWORD", data: "1"),
                    RegistryValue(key: lavOutputKey, valueName: "rgb32", type: "REG_DWORD", data: "1"),
                ]
            )
        case .rpgMaker:
            return EnginePreset(components: ["d3dx9"], dllOverrides: [:])
        case .unity:
            return EnginePreset(components: ["dotnet48", "d3dcompiler_47"], dllOverrides: [:])
        case .renpy, .majiro, .advHD, .qlie, .unknown:
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
        case .leaf: return "Leaf/AQUAPLUS"
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
