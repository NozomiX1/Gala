import CryptoKit
import Foundation

/// A runtime profile as written in a JSON file: a recipe for one Wine prefix.
/// With `base`, the file only lists what differs from that profile.
public struct ProfileFile: Codable, Equatable, Sendable {
    public struct RegistryEntry: Codable, Equatable, Sendable {
        public var key: String
        public var name: String
        public var type: String
        public var data: String
    }

    public enum Wine: String, Codable, Sendable {
        case standard = "default"
        case dxmt
    }

    public var id: String
    public var name: String
    public var notes: String?
    public var base: String?
    /// Raise it to make every existing prefix of this profile reconfigure even though the recipe reads the same.
    public var version: Int?
    public var wine: Wine?
    public var components: [String]?
    public var managedComponents: [String]?
    /// A null value removes an entry inherited from `base`.
    public var dllOverrides: [String: String?]?
    public var registry: [RegistryEntry]?
    public var registryDelete: [String]?
    public var verifiedGames: [String]?
}

/// A profile with its `base` chain folded in: everything needed to build and recognise its prefix.
public struct RuntimeRecipe: Equatable, Sendable {
    public let id: String
    public let name: String
    public let notes: String?
    public let version: Int
    public let usesDXMTWine: Bool
    public let preset: EnginePreset
    public let verifiedGames: [String]

    /// Changes whenever anything that ends up in the prefix changes, so an edited profile is noticed without a version bump.
    public var fingerprint: String {
        let overrides = preset.dllOverrides.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
        let registry = preset.registryValues.map { "\($0.key)|\($0.valueName)|\($0.type)|\($0.data)" }
        let parts = [
            [usesDXMTWine ? "dxmt" : "default"],
            preset.components,
            preset.managedComponents.map(\.rawValue),
            overrides,
            registry,
            preset.registryKeysToDelete,
        ]
        let text = parts.map { $0.joined(separator: "\n") }.joined(separator: "\n--\n")
        return SHA256.hash(data: Data(text.utf8)).map { String(format: "%02x", $0) }.joined()
    }
}

public enum ProfileError: Error, Equatable, LocalizedError {
    case unreadable(file: String, detail: String)
    case duplicate(id: String)
    case unknownBase(id: String, base: String)
    case cycle(id: String)
    case unknownManagedComponent(id: String, component: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let file, let detail): return "运行环境文件 \(file) 读不出来：\(detail)"
        case .duplicate(let id): return "有两个运行环境都叫 \(id)。"
        case .unknownBase(let id, let base): return "运行环境 \(id) 的 base 是 \(base)，但没有这个运行环境。"
        case .cycle(let id): return "运行环境 \(id) 的 base 绕了一圈又回到自己。"
        case .unknownManagedComponent(let id, let component): return "运行环境 \(id) 里的 managedComponents 有不认识的一项：\(component)。"
        }
    }
}

/// The set of known profiles, resolved and validated.
public struct ProfileStore: Sendable {
    public let recipes: [RuntimeRecipe]

    /// The profiles shipped with Gala. A broken bundled file is a build defect, caught by the tests.
    public static let bundled: ProfileStore = {
        let directory = Bundle.module.url(forResource: "Profiles", withExtension: nil)!
        return try! ProfileStore(files: files(in: directory))
    }()

    public init(files: [ProfileFile]) throws {
        var byID: [String: ProfileFile] = [:]
        for file in files {
            guard byID.updateValue(file, forKey: file.id) == nil else { throw ProfileError.duplicate(id: file.id) }
        }
        recipes = try files.map { try Self.resolve($0, in: byID) }
    }

    public func recipe(id: String) -> RuntimeRecipe? {
        recipes.first { $0.id == id }
    }

    public static func files(in directory: URL) throws -> [ProfileFile] {
        let urls = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        return try urls.map { url in
            do {
                return try JSONDecoder().decode(ProfileFile.self, from: Data(contentsOf: url))
            } catch {
                throw ProfileError.unreadable(file: url.lastPathComponent, detail: "\(error)")
            }
        }
    }

    private static func resolve(_ file: ProfileFile, in byID: [String: ProfileFile]) throws -> RuntimeRecipe {
        // Oldest ancestor first, so each later file adds to or overrides what came before.
        var chain = [file]
        while let baseID = chain[0].base {
            guard let base = byID[baseID] else { throw ProfileError.unknownBase(id: chain[0].id, base: baseID) }
            guard !chain.contains(where: { $0.id == baseID }) else { throw ProfileError.cycle(id: file.id) }
            chain.insert(base, at: 0)
        }

        var components: [String] = []
        var managed: [ManagedRuntimeComponent] = []
        var overrides: [String: String] = [:]
        var registry: [RegistryValue] = []
        var deletions: [String] = []
        var wine = ProfileFile.Wine.standard
        for link in chain {
            components += (link.components ?? []).filter { !components.contains($0) }
            for name in link.managedComponents ?? [] {
                guard let component = ManagedRuntimeComponent(rawValue: name) else {
                    throw ProfileError.unknownManagedComponent(id: link.id, component: name)
                }
                if !managed.contains(component) { managed.append(component) }
            }
            for (dll, mode) in link.dllOverrides ?? [:] {
                overrides[dll] = mode
            }
            registry += (link.registry ?? []).map {
                RegistryValue(key: $0.key, valueName: $0.name, type: $0.type, data: $0.data)
            }
            deletions += (link.registryDelete ?? []).filter { !deletions.contains($0) }
            wine = link.wine ?? wine
        }

        return RuntimeRecipe(
            id: file.id,
            name: file.name,
            notes: file.notes,
            // Versions start at 1, so a bump anywhere in the chain raises every profile built on it.
            version: chain.reduce(1) { $0 + ($1.version ?? 1) - 1 },
            usesDXMTWine: wine == .dxmt,
            preset: EnginePreset(
                components: components,
                managedComponents: managed,
                dllOverrides: overrides,
                registryValues: registry,
                registryKeysToDelete: deletions
            ),
            verifiedGames: file.verifiedGames ?? []
        )
    }
}
