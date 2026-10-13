import Foundation

public enum Engine: String, Codable, CaseIterable, Sendable {
    case kirikiri, nscripter, renpy, rpgMaker, unity
    case bgi, catSystem2, siglusEngine, artemis, artemisD3D11
    case artemisMFD3D11 = "artemis-mf-d3d11"
    case yuris
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
    case artemisMFD3D11 = "artemis-mf-d3d11"
    case leaf = "leaf"
    case ikuraGDLFamilyProject = "do-kizunar"
}

public enum ManagedRuntimeComponent: String, Sendable {
    case dxmt
    case mediaFoundation
}

public struct RegistryValue: Equatable, Sendable {
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

public struct EnginePreset: Equatable, Sendable {
    public let components: [String]
    public let managedComponents: [ManagedRuntimeComponent]
    public let dllOverrides: [String: String]
    public let registryValues: [RegistryValue]
    public let registryKeysToDelete: [String]

    public init(
        components: [String],
        managedComponents: [ManagedRuntimeComponent] = [],
        dllOverrides: [String: String],
        registryValues: [RegistryValue] = [],
        registryKeysToDelete: [String] = []
    ) {
        self.components = components
        self.managedComponents = managedComponents
        self.dllOverrides = dllOverrides
        self.registryValues = registryValues
        self.registryKeysToDelete = registryKeysToDelete
    }
}

extension Engine {
    /// The recipe of the profile this engine's games use by default, read from the bundled profile files.
    public var recipe: RuntimeRecipe {
        // Every RuntimeProfile case has a bundled file; a test checks that.
        ProfileStore.bundled.recipe(id: runtimeProfile.rawValue)!
    }

    public var preset: EnginePreset { recipe.preset }

    public var usesDXMTWineVariant: Bool { recipe.usesDXMTWine }

    public var runtimeConfigVersion: Int { recipe.version }

    public var runtimeProfile: RuntimeProfile {
        switch self {
        case .bgi, .artemis, .nscripter, .yuris, .realLive, .renpy, .rpgMaker, .unity,
             .majiro, .advHD, .qlie, .unknown, .kirikiri:
            return .common
        case .artemisD3D11:
            return .artemisD3D11
        case .artemisMFD3D11:
            return .artemisMFD3D11
        case .catSystem2:
            return .catSystem2
        case .siglusEngine:
            return .siglusEngine
        case .leaf:
            return .leaf
        case .ikuraGDLFamilyProject:
            return .ikuraGDLFamilyProject
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
        case .artemisD3D11: return "Artemis Engine (D3D11)"
        case .artemisMFD3D11: return "Artemis Engine (MF / D3D11)"
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

    /// The engine as players know it, without the variant that only decides which runtime profile is used.
    public var familyName: String {
        switch self {
        case .artemis, .artemisD3D11, .artemisMFD3D11: return "Artemis"
        case .ikuraGDLFamilyProject: return "Ikura GDL"
        default: return displayName
        }
    }
}
