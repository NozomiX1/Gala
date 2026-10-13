import Foundation

public enum ProfileImportError: Error, Equatable, LocalizedError {
    case noJSON
    case several(Int)
    case unreadable(String)
    case unknownFields([String])
    case missingName
    case badID(String)
    case bundledID(String)
    case invalid(String)

    public var errorDescription: String? {
        switch self {
        case .noJSON: return "没有找到运行环境的内容。它应该是一段用花括号包起来的 JSON。"
        case .several(let count): return "这段文字里有 \(count) 份不同的运行环境。请只粘贴你要用的那一份：从它的左花括号到右花括号。"
        case .unreadable(let detail): return "这段 JSON 读不出来：\(detail)"
        case .unknownFields(let names): return "有不认识的字段：\(names.joined(separator: "、"))。可能是拼写错了；可用的字段见 README 的“自己写一个运行环境”。"
        case .missingName: return "缺少 name（这个运行环境叫什么）。"
        case .badID(let id): return "id “\(id)”里有不能用的字符。只能用英文字母、数字、连字符和下划线。"
        case .bundledID(let id): return "id “\(id)”和 Gala 自带的运行环境重名了。请换一个 id，或者不写 id 让 Gala 自己起。"
        case .invalid(let detail): return detail
        }
    }
}

/// A profile handed over as text, checked and ready to be shown before anything is written.
/// What comes in is what a chat assistant wrote: one JSON object, possibly with prose or a code fence around it.
public struct ProfileImport: Equatable, Sendable {
    public let file: ProfileFile
    public let recipe: RuntimeRecipe
    /// The name of the user's own profile this would replace, when the id is already theirs.
    public let replaces: String?
    /// The user's own profiles it was written on top of, nearest first. Their contents are folded into `file`,
    /// which is built on the first bundled profile beneath them: nothing imported depends on another import,
    /// so an earlier attempt can be deleted once a later one has taken its place.
    public let absorbed: [ProfileFile]

    static let knownFields: Set<String> = [
        "id", "name", "notes", "advice", "base", "version", "wine", "components", "managedComponents", "dllOverrides",
        "environment", "launchArguments", "locale", "registry", "registryDelete", "features", "verifiedGames",
    ]

    /// The launch settings of its base that this file takes away. They leave no line in the folded recipe,
    /// so they are listed here for the user to see before agreeing.
    public var removals: [String] {
        var removed: [String] = []
        for (name, value) in (file.dllOverrides ?? [:]).sorted(by: { $0.key < $1.key }) where value == nil {
            removed.append("DLL 设置 \(name)")
        }
        for (name, value) in (file.environment ?? [:]).sorted(by: { $0.key < $1.key }) where value == nil {
            removed.append("环境变量 \(name)")
        }
        if file.launchArguments?.isEmpty == true { removed.append("启动参数") }
        return removed
    }

    /// Whether it needs a prefix of its own; false when it only changes how a game is launched.
    public var needsOwnPrefix: Bool { recipe.bottleID == file.id }

    public static func parse(_ text: String, userDirectory: URL) throws -> ProfileImport {
        // A whole chat reply gets pasted. Its prose has braces of its own (a GUID quoted from the log), and it may
        // hold a first attempt next to its correction: the one with a name is the profile, and two that differ are not guessed between.
        var objects: [[String: Any]] = []
        var failure: Error?
        for run in braceRuns(in: text) {
            do {
                if let object = try JSONSerialization.jsonObject(with: Data(run.utf8)) as? [String: Any],
                   !objects.contains(where: { ($0 as NSDictionary).isEqual(to: object) }) {
                    objects.append(object)
                }
            } catch {
                failure = error
            }
        }
        let named = objects.filter { $0["name"] != nil }
        guard named.count <= 1 else { throw ProfileImportError.several(named.count) }
        guard var object = named.first ?? objects.first else {
            throw failure.map { ProfileImportError.unreadable($0.localizedDescription) } ?? ProfileImportError.noJSON
        }

        // A misspelt field would otherwise be dropped in silence and the prefix built without it.
        let unknown = object.keys.filter { !knownFields.contains($0) }.sorted()
        guard unknown.isEmpty else { throw ProfileImportError.unknownFields(unknown) }
        guard let name = object["name"] as? String, !name.trimmingCharacters(in: .whitespaces).isEmpty else {
            throw ProfileImportError.missingName
        }

        let bundled = Set(ProfileStore.bundledFiles.map(\.id))
        let own = ProfileStore.userFiles(in: userDirectory).map(\.file)
        var replaces: String?
        if let id = object["id"] as? String, !id.isEmpty {
            guard id.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-" || $0 == "_") }) else {
                throw ProfileImportError.badID(id)
            }
            // A file dropped into the folder by hand may replace a bundled profile; something pasted may not.
            guard !bundled.contains(id) else { throw ProfileImportError.bundledID(id) }
            replaces = own.first { $0.id == id }?.name
        } else {
            object["id"] = freeID(for: name, taken: bundled.union(own.map(\.id)))
        }

        var file: ProfileFile
        do {
            file = try JSONDecoder().decode(ProfileFile.self, from: JSONSerialization.data(withJSONObject: object))
        } catch let error as DecodingError {
            throw ProfileImportError.unreadable(describe(error))
        }
        do {
            // Resolved as written first, so a bad base or a reserved variable is reported against what was pasted.
            _ = try ProfileStore.resolve(file, withUserFilesIn: userDirectory)

            var absorbed: [ProfileFile] = []
            while let baseID = file.base, !bundled.contains(baseID), baseID != file.id,
                  let base = own.first(where: { $0.id == baseID }), !absorbed.contains(where: { $0.id == baseID }) {
                absorbed.append(base)
                file = file.folded(onto: base)
            }

            // An assistant sometimes copies its base's settings out again. Dropping what is the same as inherited
            // keeps the saved file to its real changes, which is also all the user is shown.
            if let baseID = file.base,
               let base = try? ProfileStore.resolve(ProfileFile(id: "\(file.id)-base", name: "", base: baseID), withUserFilesIn: userDirectory) {
                file.dropWhatRepeats(base)
            }
            return ProfileImport(
                file: file,
                recipe: try ProfileStore.resolve(file, withUserFilesIn: userDirectory),
                replaces: replaces,
                absorbed: absorbed
            )
        } catch let error as ProfileError {
            throw ProfileImportError.invalid(error.localizedDescription)
        }
    }

    /// Writes the file among the user's own, over the one it replaces when there is one.
    @discardableResult
    public func save(to userDirectory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: userDirectory, withIntermediateDirectories: true)
        let existing = ProfileStore.userFiles(in: userDirectory).first { $0.file.id == file.id }?.url
        let url = existing ?? userDirectory.appendingPathComponent("\(file.id).json")
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        try encoder.encode(file).write(to: url, options: .atomic)
        return url
    }

    /// Every `{…}` run at the top level of the text, in order. One that never closes is skipped, not allowed to swallow the rest.
    static func braceRuns(in text: String) -> [String] {
        var runs: [String] = []
        var search = text.startIndex
        while let start = text[search...].firstIndex(of: "{") {
            if let end = closingBrace(in: text, from: start) {
                runs.append(String(text[start...end]))
                search = text.index(after: end)
            } else {
                search = text.index(after: start)
            }
        }
        return runs
    }

    private static func closingBrace(in text: String, from start: String.Index) -> String.Index? {
        var depth = 0, inString = false, escaped = false
        for index in text[start...].indices {
            let character = text[index]
            if inString {
                if escaped { escaped = false } else if character == "\\" { escaped = true } else if character == "\"" { inString = false }
                continue
            }
            switch character {
            case "\"": inString = true
            case "{": depth += 1
            case "}":
                depth -= 1
                if depth == 0 { return index }
            default: break
            }
        }
        return nil
    }

    /// An id from the name where it has Latin letters, otherwise a neutral one; numbered until it is free.
    static func freeID(for name: String, taken: Set<String>) -> String {
        let slug = name.lowercased().map { $0.isASCII && ($0.isLetter || $0.isNumber) ? $0 : "-" }
            .reduce(into: "") { result, character in
                if character != "-" || (result.last != "-" && !result.isEmpty) { result.append(character) }
            }
            .trimmingCharacters(in: CharacterSet(charactersIn: "-"))
        let stem = slug.count >= 3 ? "my-\(slug)" : "my-profile"
        var candidate = stem, number = 2
        while taken.contains(candidate) {
            candidate = "\(stem)-\(number)"
            number += 1
        }
        return candidate
    }

    private static func describe(_ error: DecodingError) -> String {
        func path(_ context: DecodingError.Context) -> String {
            context.codingPath.map { $0.intValue.map { "第 \($0 + 1) 项" } ?? $0.stringValue }.joined(separator: " → ")
        }
        switch error {
        case .typeMismatch(_, let context), .valueNotFound(_, let context):
            return "\(path(context)) 的写法不对。"
        case .keyNotFound(let key, let context):
            return "\(path(context).isEmpty ? "" : path(context) + " 里")缺少 \(key.stringValue)。"
        case .dataCorrupted(let context):
            return "\(path(context)) 的值不能用。"
        @unknown default:
            return error.localizedDescription
        }
    }
}

extension ProfileFile {
    /// This file and the one it is built on as a single file built on that one's base, saying the same thing.
    func folded(onto parent: ProfileFile) -> ProfileFile {
        func merged<Value>(_ older: [String: Value?]?, _ newer: [String: Value?]?, twins: Bool) -> [String: Value?]? {
            guard older != nil || newer != nil else { return nil }
            var result = older ?? [:]
            for (name, value) in newer ?? [:] {
                result[name] = value
                // The same rule as when a chain is resolved: naming one spelling of a DLL speaks for the other.
                let twin = name.hasPrefix("*") ? String(name.dropFirst()) : "*" + name
                if twins, newer?.keys.contains(twin) != true, result.keys.contains(twin) { result[twin] = value }
            }
            return result
        }
        func union(_ older: [String]?, _ newer: [String]?) -> [String]? {
            guard older != nil || newer != nil else { return nil }
            return (older ?? []) + (newer ?? []).filter { !(older ?? []).contains($0) }
        }
        var registry = parent.registry ?? []
        for entry in self.registry ?? [] {
            registry.removeAll { $0.key == entry.key && $0.name == entry.name }
            registry.append(entry)
        }
        return ProfileFile(
            id: id,
            name: name,
            notes: notes ?? parent.notes,
            advice: advice ?? parent.advice,
            base: parent.base,
            wine: wine ?? parent.wine,
            components: union(parent.components, components),
            managedComponents: union(parent.managedComponents, managedComponents),
            dllOverrides: merged(parent.dllOverrides, dllOverrides, twins: true),
            environment: merged(parent.environment, environment, twins: false),
            launchArguments: launchArguments ?? parent.launchArguments,
            locale: locale ?? parent.locale,
            registry: registry.isEmpty ? nil : registry,
            registryDelete: union(parent.registryDelete, registryDelete),
            features: union(parent.features, features),
            verifiedGames: verifiedGames
        )
    }

    /// Removes from this file whatever says the same as the recipe it is built on. Removals (`null`) are kept: they are changes.
    mutating func dropWhatRepeats(_ base: RuntimeRecipe) {
        func trimmed<Value>(_ dictionary: [String: Value?]?, against inherited: [String: Value]) -> [String: Value?]? where Value: Equatable {
            guard let dictionary else { return nil }
            let kept = dictionary.filter { name, value in value == nil ? inherited[name] != nil : inherited[name] != value }
            return kept.isEmpty ? nil : kept
        }
        dllOverrides = trimmed(dllOverrides, against: base.preset.dllOverrides)
        environment = trimmed(environment, against: base.environment)
        if launchArguments == base.launchArguments { launchArguments = nil }
        if locale == base.locale { locale = nil }
        if wine == (base.usesDXMTWine ? .dxmt : .standard) { wine = nil }
        if let own = components?.filter({ !base.preset.components.contains($0) }) { components = own.isEmpty ? nil : own }
        if let own = registry?.filter({ entry in
            !base.preset.registryValues.contains { $0.key == entry.key && $0.valueName == entry.name && $0.type == entry.type && $0.data == entry.data }
        }) { registry = own.isEmpty ? nil : own }
        if let own = registryDelete?.filter({ !base.preset.registryKeysToDelete.contains($0) }) { registryDelete = own.isEmpty ? nil : own }
    }
}
