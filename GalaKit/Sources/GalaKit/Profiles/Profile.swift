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
    /// One thing the user has to do themselves for games in this profile, in their words. Shown on the game page.
    public var advice: String?
    public var base: String?
    /// Raise it to make every existing prefix of this profile reconfigure even though the recipe reads the same.
    public var version: Int?
    public var wine: Wine?
    public var components: [String]?
    public var managedComponents: [String]?
    /// A null value removes an entry inherited from `base`.
    public var dllOverrides: [String: String?]?
    /// Passed to the game's process at launch. A null value removes one inherited from `base`.
    public var environment: [String: String?]?
    /// Arguments for the game itself, after its executable. Replaces the base's list when present.
    public var launchArguments: [String]?
    /// The locale Wine starts in, for example `ja_JP.UTF-8`.
    public var locale: String?
    public var registry: [RegistryEntry]?
    public var registryDelete: [String]?
    /// Behaviour that lives in code and is switched on by name. See `ProfileFeature`.
    public var features: [String]?
    public var verifiedGames: [String]?
}

/// Things a profile can ask for that a file cannot express on its own.
public enum ProfileFeature: String, Sendable {
    /// Always map the game's folder as drive G:, for games whose install registry points there.
    case gameDriveG
}

/// A profile with its `base` chain folded in. It has two halves: what goes into the prefix (components, registry)
/// and what is passed at each launch (the Wine build, DLL overrides). Only the first half decides which prefix it lives in.
public struct RuntimeRecipe: Equatable, Sendable {
    public let id: String
    public let name: String
    public let notes: String?
    public let advice: String?
    public let version: Int
    public let usesDXMTWine: Bool
    public let preset: EnginePreset
    /// The rest of the launch half, next to `usesDXMTWine` and the preset's DLL overrides.
    public let environment: [String: String]
    public let launchArguments: [String]
    public let locale: String?
    public let features: Set<ProfileFeature>
    public let verifiedGames: [String]
    /// True for a file from the user's Profiles folder rather than one shipped with Gala.
    public let isUserProvided: Bool
    /// The profile whose prefix this one lives in: itself when it installs components or writes registry values,
    /// otherwise the nearest ancestor that does. A profile that only changes how a game is launched needs no prefix of its own.
    public let bottleID: String
    /// Ancestors with a prefix of their own, nearest first. A new prefix is cloned from the first one that is already built.
    public let cloneCandidates: [String]
    /// The profile this one is written on top of.
    public let baseID: String?
    /// Which file in the chain each setting comes from, so a folded recipe can still be shown line by line.
    /// Keys: `component:<name>`, `dll:<name>`, `env:<name>`, `registry:<key>|<name>`, `registryDelete:<key>`, `wine`, `arguments`, `locale`.
    public let origins: [String: String]

    public var usesMediaFoundation: Bool { preset.managedComponents.contains(.mediaFoundation) }

    /// Changes whenever anything that ends up in the prefix changes, so an edited profile is noticed without a version bump.
    /// The launch half (Wine build, DLL overrides) is left out: changing it changes nothing in the prefix.
    public var fingerprint: String {
        let registry = preset.registryValues.map { "\($0.key)|\($0.valueName)|\($0.type)|\($0.data)" }
        let parts = [preset.components, registry, preset.registryKeysToDelete]
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
    case unknownFeature(id: String, feature: String)
    case reservedEnvironment(id: String, name: String)

    public var errorDescription: String? {
        switch self {
        case .unreadable(let file, let detail): return "运行环境文件 \(file) 读不出来：\(detail)"
        case .duplicate(let id): return "有两个运行环境都叫 \(id)。"
        case .unknownBase(let id, let base): return "运行环境 \(id) 的 base 是 \(base)，但没有这个运行环境。"
        case .cycle(let id): return "运行环境 \(id) 的 base 绕了一圈又回到自己。"
        case .unknownManagedComponent(let id, let component): return "运行环境 \(id) 里的 managedComponents 有不认识的一项：\(component)。"
        case .unknownFeature(let id, let feature): return "运行环境 \(id) 里的 features 有不认识的一项：\(feature)。"
        case .reservedEnvironment(let id, let name): return "运行环境 \(id) 不能设置环境变量 \(name)：它由 Gala 自己管理。DLL 设置请写在 dllOverrides 里，文字区域写在 locale 里。"
        }
    }
}

/// The set of known profiles, resolved and validated.
public struct ProfileStore: Sendable {
    public let recipes: [RuntimeRecipe]

    static let bundledFiles: [ProfileFile] = {
        let directory = Bundle.module.url(forResource: "Profiles", withExtension: nil)!
        // A broken bundled file is a build defect, caught by the tests.
        return try! files(in: directory)
    }()

    /// The profiles shipped with Gala.
    public static let bundled = try! ProfileStore(files: bundledFiles)

    /// Strict: any problem in any file is an error. Used for the bundled set and in tests.
    public init(files: [ProfileFile]) throws {
        var byID: [String: ProfileFile] = [:]
        for file in files {
            guard byID.updateValue(file, forKey: file.id) == nil else { throw ProfileError.duplicate(id: file.id) }
        }
        recipes = try files.map { try Self.resolve($0, in: byID, userIDs: []) }
    }

    private init(recipes: [RuntimeRecipe]) {
        self.recipes = recipes
    }

    /// The bundled profiles plus the user's own. A user file with a bundled id replaces it.
    /// A file that cannot be read or resolved is left out and reported, so one bad file never takes the app down.
    public static func loading(userDirectory: URL) -> (store: ProfileStore, problems: [ProfileError]) {
        var problems: [ProfileError] = []
        var byID = Dictionary(uniqueKeysWithValues: bundledFiles.map { ($0.id, $0) })
        var order = bundledFiles.map(\.id)
        var userIDs: Set<String> = []

        let urls = ((try? FileManager.default.contentsOfDirectory(at: userDirectory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        for url in urls {
            do {
                let file = try JSONDecoder().decode(ProfileFile.self, from: Data(contentsOf: url))
                guard userIDs.insert(file.id).inserted else {
                    problems.append(.duplicate(id: file.id))
                    continue
                }
                if byID.updateValue(file, forKey: file.id) == nil { order.append(file.id) }
            } catch {
                problems.append(.unreadable(file: url.lastPathComponent, detail: error.localizedDescription))
            }
        }

        var recipes: [RuntimeRecipe] = []
        for id in order {
            do {
                recipes.append(try resolve(byID[id]!, in: byID, userIDs: userIDs))
            } catch let problem as ProfileError {
                problems.append(problem)
            } catch {}
        }
        return (ProfileStore(recipes: recipes), problems)
    }

    public func recipe(id: String) -> RuntimeRecipe? {
        recipes.first { $0.id == id }
    }

    /// The user's own files that can be read, with where each one is. One that cannot is someone else's problem to report.
    static func userFiles(in directory: URL) -> [(url: URL, file: ProfileFile)] {
        ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "json" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
            .compactMap { url in
                (try? JSONDecoder().decode(ProfileFile.self, from: Data(contentsOf: url))).map { (url, $0) }
            }
    }

    /// The user's own profiles written directly on top of the given one. While there are any, deleting it would break them.
    public static func userProfiles(basedOn id: String, in directory: URL) -> [ProfileFile] {
        userFiles(in: directory).map(\.file).filter { $0.base == id }
    }

    /// Deletes the user's own file with this id. A bundled profile has no such file and is left alone.
    public static func deleteUserProfile(id: String, in directory: URL) throws {
        for (url, file) in userFiles(in: directory) where file.id == id {
            try FileManager.default.removeItem(at: url)
        }
    }

    /// Resolves one file against the bundled profiles and the user's readable ones, as it would be once saved among them.
    static func resolve(_ file: ProfileFile, withUserFilesIn directory: URL) throws -> RuntimeRecipe {
        var byID = Dictionary(uniqueKeysWithValues: bundledFiles.map { ($0.id, $0) })
        var userIDs: Set<String> = [file.id]
        for (_, other) in userFiles(in: directory) {
            byID[other.id] = other
            userIDs.insert(other.id)
        }
        byID[file.id] = file
        return try resolve(file, in: byID, userIDs: userIDs)
    }

    /// The recipe a game runs with: the one picked by hand if it still exists, otherwise its engine's default.
    public func recipe(for game: Game) -> RuntimeRecipe? {
        if let id = game.profileID, let chosen = recipe(id: id) { return chosen }
        return game.engine.flatMap { recipe(id: $0.runtimeProfile.rawValue) }
    }

    /// The profile whose prefix the given one lives in. An unknown id owns its own.
    public func bottleID(forProfile id: String) -> String {
        recipe(id: id)?.bottleID ?? id
    }

    /// The recipe the game's prefix is built from and marked with; the game's own unless it shares a bottle.
    public func bottleRecipe(for game: Game) -> RuntimeRecipe? {
        guard let recipe = recipe(for: game) else { return nil }
        return self.recipe(id: recipe.bottleID) ?? recipe
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

    static let reservedEnvironment: Set<String> = [
        "WINEPREFIX", "WINESERVER", "WINELOADER", "WINEDLLPATH", "WINEDLLOVERRIDES", "WINEDEBUG", "LANG", "LC_ALL", "PATH", "HOME",
    ]

    private static func resolve(_ file: ProfileFile, in byID: [String: ProfileFile], userIDs: Set<String>) throws -> RuntimeRecipe {
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
        var features: Set<ProfileFeature> = []
        var wine = ProfileFile.Wine.standard
        var environment: [String: String] = [:]
        var launchArguments: [String] = []
        var locale: String?
        var origins: [String: String] = [:]
        for link in chain {
            for name in link.components ?? [] where origins["component:\(name)"] == nil { origins["component:\(name)"] = link.id }
            for name in (link.dllOverrides ?? [:]).keys { origins["dll:\(name)"] = link.id }
            for name in (link.environment ?? [:]).keys { origins["env:\(name)"] = link.id }
            for entry in link.registry ?? [] { origins["registry:\(entry.key)|\(entry.name)"] = link.id }
            for key in link.registryDelete ?? [] where origins["registryDelete:\(key)"] == nil { origins["registryDelete:\(key)"] = link.id }
            if link.wine != nil { origins["wine"] = link.id }
            if link.launchArguments != nil { origins["arguments"] = link.id }
            if link.locale != nil { origins["locale"] = link.id }
            for (name, value) in link.environment ?? [:] {
                // These decide which prefix and which Wine run, or have a field of their own; a pasted file must not redirect them.
                guard !reservedEnvironment.contains(name), !name.hasPrefix("DYLD_") else {
                    throw ProfileError.reservedEnvironment(id: link.id, name: name)
                }
                environment[name] = value
            }
            launchArguments = link.launchArguments ?? launchArguments
            locale = link.locale ?? locale
            components += (link.components ?? []).filter { !components.contains($0) }
            for name in link.managedComponents ?? [] {
                guard let component = ManagedRuntimeComponent(rawValue: name) else {
                    throw ProfileError.unknownManagedComponent(id: link.id, component: name)
                }
                if !managed.contains(component) { managed.append(component) }
            }
            for (dll, mode) in link.dllOverrides ?? [:] {
                overrides[dll] = mode
                // "quartz" and "*quartz" are two spellings Wine looks up for one DLL. A file that names one of them
                // means the DLL: an inherited twin left alone would keep the old choice in force.
                let twin = dll.hasPrefix("*") ? String(dll.dropFirst()) : "*" + dll
                if link.dllOverrides?.keys.contains(twin) != true, overrides[twin] != nil {
                    overrides[twin] = mode
                    origins["dll:\(twin)"] = link.id
                }
            }
            registry += (link.registry ?? []).map {
                RegistryValue(key: $0.key, valueName: $0.name, type: $0.type, data: $0.data)
            }
            deletions += (link.registryDelete ?? []).filter { !deletions.contains($0) }
            for name in link.features ?? [] {
                guard let feature = ProfileFeature(rawValue: name) else {
                    throw ProfileError.unknownFeature(id: link.id, feature: name)
                }
                features.insert(feature)
            }
            wine = link.wine ?? wine
        }

        // Asking for the DXMT Wine is enough to get it downloaded; a file need not also list it as a component.
        if wine == .dxmt, !managed.contains(.dxmt) { managed.insert(.dxmt, at: 0) }

        // A root always has a prefix; a later file gets its own only when it puts something into one.
        let owners = chain.filter { link in
            link.base == nil || !(link.components ?? []).isEmpty || !(link.registry ?? []).isEmpty || !(link.registryDelete ?? []).isEmpty
        }.map(\.id)

        return RuntimeRecipe(
            id: file.id,
            name: file.name,
            notes: file.notes,
            advice: file.advice,
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
            environment: environment,
            launchArguments: launchArguments,
            locale: locale,
            features: features,
            verifiedGames: file.verifiedGames ?? [],
            isUserProvided: userIDs.contains(file.id),
            bottleID: owners.last ?? file.id,
            cloneCandidates: owners.dropLast().reversed(),
            baseID: file.base,
            origins: origins
        )
    }
}

extension ProfileStore {
    /// The list of games each profile is known to run, as the Markdown kept in `docs/compatibility.md`.
    public var compatibilityMarkdown: String {
        var lines = [
            "# 已验证的游戏",
            "",
            "这份列表由各运行环境文件里的 `verifiedGames` 生成，不要手工修改。",
            "重新生成：`swift run --package-path GalaKit gala-cli compat > docs/compatibility.md`",
            "",
            "| 游戏 | 运行环境 |",
            "| --- | --- |",
        ]
        for recipe in recipes {
            for game in recipe.verifiedGames {
                lines.append("| \(game) | \(recipe.name)（`\(recipe.id)`） |")
            }
        }
        // A profile no engine starts in any more is kept for games already using it; it is not waiting to be verified.
        let defaults = Set(Engine.allCases.map(\.runtimeProfile.rawValue))
        let unverified = recipes.filter { $0.verifiedGames.isEmpty && defaults.contains($0.id) }
        if !unverified.isEmpty {
            lines += ["", "## 还没有验证过游戏的运行环境", ""]
            lines += unverified.map { "- \($0.name)（`\($0.id)`）" }
        }
        return lines.joined(separator: "\n") + "\n"
    }
}
