import Foundation

public enum Engine: String, Codable, CaseIterable, Sendable {
    case kirikiri, nscripter, renpy, rpgMaker, unity
    case bgi, catSystem2, siglusEngine, artemis, artemisD3D11, yuris
    case majiro, advHD, realLive, qlie, leaf
    case ikuraGDLFamilyProject = "doKizunar"
    case unknown

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        let rawValue = try container.decode(String.self)
        self = Engine(rawValue: rawValue) ?? .unknown
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

public enum RuntimeProfile: String, Codable, Sendable {
    case common = "common"
    case kirikiri = "kirikiri"
    case catSystem2 = "cat-system2"
    case siglusEngine = "siglus-engine"
    case artemisD3D11 = "artemis-d3d11"
    case leaf = "leaf"
    case ikuraGDLFamilyProject = "do-kizunar"
    case rpgMaker = "rpg-maker"
    case unity = "unity"
}

public enum ManagedRuntimeComponent: String, Sendable {
    case dxmt
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
    public let managedComponents: [ManagedRuntimeComponent]
    public let dllOverrides: [String: String]
    public let registryValues: [RegistryValue]

    public init(
        components: [String],
        managedComponents: [ManagedRuntimeComponent] = [],
        dllOverrides: [String: String],
        registryValues: [RegistryValue] = []
    ) {
        self.components = components
        self.managedComponents = managedComponents
        self.dllOverrides = dllOverrides
        self.registryValues = registryValues
    }

    public static let empty = EnginePreset(components: [], dllOverrides: [:])
}

extension Engine {
    private static let commonVideoComponents = ["quartz", "amstream", "lavfilters"]
    private static let nativeDirectShowDLLOverrides = [
        "quartz": "native,builtin",
        "*quartz": "native,builtin",
        "amstream": "native,builtin",
        "*amstream": "native,builtin",
    ]
    private static let lavAudioFormatsKey = "HKCU\\Software\\LAV\\Audio\\Formats"
    private static let lavWMARegistryValues = [
        RegistryValue(key: lavAudioFormatsKey, valueName: "wma", type: "REG_DWORD", data: "1"),
        RegistryValue(key: lavAudioFormatsKey, valueName: "wmapro", type: "REG_DWORD", data: "1"),
        RegistryValue(key: lavAudioFormatsKey, valueName: "wmalossless", type: "REG_DWORD", data: "1"),
    ]

    private static func commonVideoPreset(
        additionalComponents: [String] = [],
        dllOverrides: [String: String] = [:],
        baseDllOverrides: [String: String] = nativeDirectShowDLLOverrides,
        registryValues additionalRegistryValues: [RegistryValue] = []
    ) -> EnginePreset {
        var mergedDllOverrides = baseDllOverrides
        for (dll, mode) in dllOverrides {
            mergedDllOverrides[dll] = mode
        }

        return EnginePreset(
            components: commonVideoComponents + additionalComponents,
            dllOverrides: mergedDllOverrides,
            registryValues: lavWMARegistryValues + additionalRegistryValues
        )
    }

    public var preset: EnginePreset {
        switch self {
        case .kirikiri:
            return Self.commonVideoPreset(dllOverrides: ["quartz": "native"])
        case .bgi, .artemis, .nscripter, .yuris, .realLive, .renpy, .majiro, .advHD, .qlie, .unknown:
            return Self.commonVideoPreset()
        case .artemisD3D11:
            return EnginePreset(
                components: ["d3dcompiler_47"],
                managedComponents: [.dxmt],
                dllOverrides: ["d3dcompiler_47": "native,builtin"]
            )
        case .catSystem2:
            return Self.commonVideoPreset(additionalComponents: ["dotnet40", "vcrun2015"])
        case .siglusEngine:
            return Self.commonVideoPreset(
                additionalComponents: ["xact", "xinput", "vcrun2019"],
                dllOverrides: ["xaudio2_7": "native", "xactengine3_7": "native"]
            )
        case .leaf:
            let lavOutputKey = "HKCU\\Software\\LAV\\Video\\Output"
            return Self.commonVideoPreset(
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
        case .ikuraGDLFamilyProject:
            return Self.commonVideoPreset(
                dllOverrides: [
                    "quartz": "builtin",
                    "*quartz": "builtin",
                ],
                baseDllOverrides: [:]
            )
        case .rpgMaker:
            return EnginePreset(components: ["d3dx9"], dllOverrides: [:])
        case .unity:
            return EnginePreset(components: ["dotnet48", "d3dcompiler_47"], dllOverrides: [:])
        }
    }

    func gameSpecificRegistryValues(for game: Game) -> [RegistryValue] {
        guard self == .ikuraGDLFamilyProject else { return [] }

        let key = "HKCU\\Software\\DO\\KIZUNAR"
        let gameDrive = "G:\\"
        return [
            RegistryValue(key: key, valueName: "InstallDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "SaveDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "DataDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "MusicDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "VoiceDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "VideoDir", type: "REG_SZ", data: gameDrive),
            RegistryValue(key: key, valueName: "InstallType", type: "REG_DWORD", data: "2"),
        ]
    }

    public var runtimeProfile: RuntimeProfile {
        switch self {
        case .bgi, .artemis, .nscripter, .yuris, .realLive, .renpy, .majiro, .advHD, .qlie, .unknown:
            return .common
        case .artemisD3D11:
            return .artemisD3D11
        case .kirikiri:
            return .kirikiri
        case .catSystem2:
            return .catSystem2
        case .siglusEngine:
            return .siglusEngine
        case .leaf:
            return .leaf
        case .ikuraGDLFamilyProject:
            return .ikuraGDLFamilyProject
        case .rpgMaker:
            return .rpgMaker
        case .unity:
            return .unity
        }
    }

    public var runtimeConfigVersion: Int {
        1
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
        case .artemisD3D11: return "Artemis Engine (D3D11)"
        case .yuris: return "YU-RIS"
        case .majiro: return "Majiro"
        case .advHD: return "AdvHD"
        case .realLive: return "RealLive"
        case .qlie: return "QLIE"
        case .leaf: return "Leaf/AQUAPLUS"
        case .ikuraGDLFamilyProject: return "Ikura GDL / Family Project"
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
