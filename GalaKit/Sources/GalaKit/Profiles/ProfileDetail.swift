import Foundation

/// A recipe laid out for reading: what it is built on and every setting it ends up with, each with the file it comes from.
/// The run settings panel shows it, and the help request carries it so an assistant can write a changed copy.
public struct ProfileDetail: Equatable, Sendable {
    public struct Row: Equatable, Sendable, Identifiable {
        public let label: String
        public let value: String
        /// The name of the profile the value is inherited from; nil when this profile's own file sets it.
        public let source: String?
        public var id: String { "\(label)|\(value)" }
    }

    /// One line: the base and how much this profile adds to it.
    public let summary: String
    public let rows: [Row]

    /// The same for a small panel: components on one line per file they come from, registry entries as a count.
    /// The full list stays in `rows` and `text`.
    public var compactRows: [Row] {
        var result: [Row] = []
        func group(_ labels: Set<String>, as label: String, value: ([Row]) -> String) {
            let matching = rows.filter { labels.contains($0.label) }
            var sources: [String?] = []
            for row in matching where !sources.contains(row.source) { sources.append(row.source) }
            // This profile's own first, then what it inherits.
            for source in sources.sorted(by: { $0 == nil && $1 != nil }) {
                result.append(Row(label: label, value: value(matching.filter { $0.source == source }), source: source))
            }
        }
        for row in rows where row.label == "基于" { result.append(row) }
        group(["组件"], as: "组件") { $0.map(\.value).joined(separator: "、") }
        result += rows.filter { !["基于", "组件", "注册表", "删除注册表"].contains($0.label) }
        group(["注册表", "删除注册表"], as: "注册表") { "\($0.count) 条" }
        return result
    }

    public var text: String {
        rows.map { "\($0.label)：\($0.value)\($0.source.map { "（来自 \($0)）" } ?? "")" }.joined(separator: "\n")
    }

    static func describe(dllMode mode: String) -> String {
        switch mode.replacingOccurrences(of: " ", with: "") {
        case "native": "Windows 原版"
        case "builtin": "Wine 自带"
        case "native,builtin": "原版优先"
        case "builtin,native": "自带优先"
        case "", "disabled": "禁用"
        default: mode
        }
    }
}

extension ProfileStore {
    public func detail(of recipe: RuntimeRecipe) -> ProfileDetail {
        func source(_ key: String) -> String? {
            guard let id = recipe.origins[key], id != recipe.id else { return nil }
            return self.recipe(id: id)?.name ?? id
        }
        func isOwn(_ key: String) -> Bool { recipe.origins[key] == recipe.id }
        var rows: [ProfileDetail.Row] = []
        func add(_ label: String, _ value: String, _ key: String?) {
            rows.append(.init(label: label, value: value, source: key.flatMap(source)))
        }

        let base = recipe.baseID.flatMap { self.recipe(id: $0) }
        add("基于", base.map { "\($0.name)（\($0.id)）" } ?? "没有，从零建立", nil)
        for name in recipe.preset.components { add("组件", name, "component:\(name)") }

        // "*quartz" and "quartz" are two spellings Wine looks up for one DLL; shown once when they agree.
        let overrides = recipe.preset.dllOverrides
        var ownLaunch = 0
        for name in overrides.keys.sorted() where !(name.hasPrefix("*") && overrides[String(name.dropFirst())] == overrides[name]) {
            add("DLL 设置", "\(name) = \(ProfileDetail.describe(dllMode: overrides[name] ?? ""))", "dll:\(name)")
            if isOwn("dll:\(name)") { ownLaunch += 1 }
        }
        if recipe.usesDXMTWine {
            add("Wine", "带 DXMT 的版本", "wine")
            if isOwn("wine") { ownLaunch += 1 }
        }
        for name in recipe.environment.keys.sorted() {
            add("环境变量", "\(name) = \(recipe.environment[name] ?? "")", "env:\(name)")
            if isOwn("env:\(name)") { ownLaunch += 1 }
        }
        if !recipe.launchArguments.isEmpty {
            add("启动参数", recipe.launchArguments.joined(separator: " "), "arguments")
            if isOwn("arguments") { ownLaunch += 1 }
        }
        if let locale = recipe.locale {
            add("文字区域", locale, "locale")
            if isOwn("locale") { ownLaunch += 1 }
        }
        for value in recipe.preset.registryValues {
            let key = value.key.components(separatedBy: "\\").suffix(2).joined(separator: "\\")
            add("注册表", "\(key) · \(value.valueName) = \(value.data)", "registry:\(value.key)|\(value.valueName)")
        }
        for key in recipe.preset.registryKeysToDelete { add("删除注册表", key, "registryDelete:\(key)") }

        let ownComponents = recipe.preset.components.filter { isOwn("component:\($0)") }.count
        let ownRegistry = recipe.preset.registryValues.filter { isOwn("registry:\($0.key)|\($0.valueName)") }.count
            + recipe.preset.registryKeysToDelete.filter { isOwn("registryDelete:\($0)") }.count
        var parts = [base.map { "基于\($0.name)" } ?? "从零建立"]
        if ownComponents > 0 { parts.append("\(base == nil ? "装" : "多装") \(ownComponents) 个组件") }
        if ownRegistry > 0 { parts.append("\(ownRegistry) 条注册表") }
        if ownLaunch > 0 { parts.append("\(ownLaunch) 条启动设置") }
        if base != nil, parts.count == 1 { parts.append("没有改动") }
        return ProfileDetail(summary: parts.joined(separator: " · "), rows: rows)
    }
}
